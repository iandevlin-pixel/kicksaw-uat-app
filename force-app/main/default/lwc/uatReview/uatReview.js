import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STORY_NAME from '@salesforce/schema/UAT_Story__c.Name';
import STORY_URL from '@salesforce/schema/UAT_Story__c.Jira_URL__c';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQueue from '@salesforce/apex/UatReviewController.getQueue';
import decide from '@salesforce/apex/UatReviewController.decide';
import saveDraft from '@salesforce/apex/UatReviewController.saveDraft';

// Kicksaw UAT App v2. Review UAT feedback one item at a time: see what the tester reported and what
// the triage proposes, then send it to Jira (Bug / Enhancement), resolve it in Salesforce (Training,
// Not a Bug, Duplicate, Won't Do) or send it back to the tester (Needs info). No "mark all": every
// item gets its own decision.
//
// Moving between items:
//   Back (←)  previous item, nothing saved
//   Skip (S)  next item, nothing saved
//   Next (→)  saves the card edits (story, severity, proposed resolution, determination) and moves on;
//             the item stays in "To review" until someone acts on it with the decision button
//   Mouse wheel over the header / progress bar / item header: previous / next item (Skip). If the card has
//             unsaved edits the wheel does not move; it asks the reviewer to press Next or Skip instead.
const DECISIONS = [
    { value: 'Bug', label: 'Bug', action: 'jira' },
    { value: 'Enhancement', label: 'Enhancement', action: 'jira' },
    { value: 'Training', label: 'Training', action: 'resolve' },
    { value: 'Not a Bug', label: 'Not a bug', action: 'resolve' },
    { value: 'Duplicate', label: 'Duplicate', action: 'resolve' },
    { value: "Won't Do", label: "Won't do", action: 'resolve' },
    { value: 'Needs Info', label: 'Needs info', action: 'needsInfo' }
];
// Determinations Next can save on their own (the others need a note or an original item).
const DRAFT_DECISIONS = ['Bug', 'Enhancement', 'Training', 'Not a Bug'];
const SEVERITIES = ['Blocker', 'High', 'Medium', 'Low'];
const EDITABLE_TAGS = ['TEXTAREA', 'INPUT', 'SELECT', 'LIGHTNING-RECORD-PICKER', 'LIGHTNING-TEXTAREA', 'LIGHTNING-INPUT', 'LIGHTNING-COMBOBOX'];
const WHEEL_QUIET_MS = 350; // a wheel "flick" ends after this long without wheel events
const SMALL_SCREEN_PX = 768;
const BOTTOM_RESERVE_PX = 52; // room for an app utility bar under the page

export default class UatReview extends NavigationMixin(LightningElement) {
    view = 'review';
    items = [];
    index = 0;
    loading = true;
    error;
    actionError;
    navNotice;
    saving = false;
    decided = new Set();
    saved = new Set();
    rootStyle = '';

    decision;
    initialDecision;
    proposal = '';
    note = '';
    severity;
    duplicateOf;
    pickedStoryId;
    pickedStoryName;
    showStoryPicker = false;

    pickedStoryUrl;

    wheelLocked = false;
    wheelTimer;

    @wire(getRecord, { recordId: '$pickedStoryId', fields: [STORY_NAME, STORY_URL] })
    wiredStory({ data }) {
        if (data) {
            this.pickedStoryName = getFieldValue(data, STORY_NAME);
            this.pickedStoryUrl = getFieldValue(data, STORY_URL);
        }
    }

    connectedCallback() {
        this.onResize = () => this.fitHeight();
        window.addEventListener('resize', this.onResize);
        this.load();
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.onResize);
        clearTimeout(this.wheelTimer);
    }

    renderedCallback() {
        if (!this.fitted) {
            this.fitted = true;
            this.fitHeight();
        }
        this.syncTextareas();
    }

    // Fill the window from where the component starts down to the bottom (Ben, Nov 13). Small screens
    // keep the natural height and the page scrolls.
    fitHeight() {
        const el = this.template.querySelector('article');
        if (!el) return;
        if (window.innerWidth < SMALL_SCREEN_PX || window.innerHeight < 500) {
            this.rootStyle = '';
            return;
        }
        const top = el.getBoundingClientRect().top + (window.scrollY || 0);
        const height = Math.max(window.innerHeight - top - BOTTOM_RESERVE_PX, 480);
        this.rootStyle = `height:${Math.round(height)}px`;
    }

    // Plain textareas so they can grow with their text. Values are pushed in here (not bound) so typing
    // never moves the cursor.
    syncTextareas() {
        this.template.querySelectorAll('textarea[data-field]').forEach((ta) => {
            const value = this[ta.dataset.field] || '';
            if (ta.value !== value && this.template.activeElement !== ta) {
                ta.value = value;
            }
            this.autoGrow(ta);
        });
    }

    autoGrow(ta) {
        ta.style.height = 'auto';
        ta.style.height = `${ta.scrollHeight + 2}px`;
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.items = (await getQueue({ view: this.view })).map((i) => ({ ...i }));
            this.index = 0;
            this.decided = new Set();
            this.saved = new Set();
            this.resetDraft();
        } catch (e) {
            this.error = this.errorText(e);
        } finally {
            this.loading = false;
            this.focusCard();
        }
    }

    // ---------- derived state ----------
    get total() { return this.items.length; }
    get hasItems() { return this.total > 0 && !this.loading; }
    get decidedCount() { return this.decided.size; }
    get savedCount() { return this.saved.size; }
    get remaining() { return this.total - this.decided.size; }
    get position() { return Math.min(this.index + 1, this.total); }
    get progressPercent() { return this.total ? Math.round((this.decided.size / this.total) * 100) : 0; }
    get progressStyle() { return `width:${this.progressPercent}%`; }
    get current() { return this.items[this.index]; }
    get allDone() { return !this.loading && !this.error && (!this.total || this.remaining === 0 || !this.current); }
    get doneText() {
        if (!this.total) {
            return this.isReviewView ? 'Nothing is waiting for a Kicksaw decision.' : 'No items are waiting on the tester.';
        }
        const left = this.total - this.decided.size;
        return `${this.decided.size} decided, ${left} still open (${this.saved.size} saved with Next). Go back, or refresh to pick up open and new items.`;
    }
    get isReviewView() { return this.view === 'review'; }
    get isNeedsInfoView() { return this.view === 'needsInfo'; }
    get reviewTabClass() { return 'ur-tab' + (this.isReviewView ? ' ur-tab-on' : ''); }
    get needsInfoTabClass() { return 'ur-tab' + (this.isNeedsInfoView ? ' ur-tab-on' : ''); }
    get showFooter() { return this.hasItems && !this.error && this.remaining > 0; }
    get backDisabled() { return this.saving || this.prevIndex(this.index) < 0; }
    get isSaved() { return !!(this.current && this.saved.has(this.current.id)); }
    get currentUrl() { return this.current ? `/lightning/r/UAT_Feedback__c/${this.current.id}/view` : '#'; }
    get capturedUrl() {
        const id = this.current && this.current.recordId;
        return id && /^[a-zA-Z0-9]{15,18}$/.test(id) ? `/lightning/r/${id}/view` : null;
    }
    get storyName() { return this.pickedStoryName || (this.current && this.current.storyName); }
    get storyUrl() { return this.pickedStoryId ? this.pickedStoryUrl : this.current && this.current.storyUrl; }
    get storyIsSuggested() { return !this.pickedStoryId && this.current && this.current.storySuggested; }
    get hasStory() { return !!(this.pickedStoryId || (this.current && this.current.storyId)); }
    get storyToggleLabel() { return this.showStoryPicker ? 'Cancel' : this.hasStory ? 'Change' : 'Pick story'; }
    get notTriaged() { return !(this.current && (this.current.proposal || this.current.reasoning || this.current.repro)); }
    get metaLine() {
        const c = this.current;
        if (!c) return '';
        const by = c.submittedBy ? `From ${c.submittedBy}` : 'Tester unknown';
        const when = c.createdDate ? new Date(c.createdDate).toLocaleString() : '';
        return `${by} · ${when}`;
    }
    get severityOptions() {
        return SEVERITIES.map((value) => ({
            value,
            selected: value === this.severity,
            cls: 'ur-sev-btn ur-sev-' + value.toLowerCase() + (value === this.severity ? ' ur-sev-on' : '')
        }));
    }
    get decisionOptions() {
        return DECISIONS.map((d) => ({
            ...d,
            selected: d.value === this.decision,
            cls: 'ur-choice' + (d.value === this.decision ? ' ur-choice-on' : '') + (d.action === 'jira' ? ' ur-choice-jira' : '')
        }));
    }
    get decisionDef() { return DECISIONS.find((d) => d.value === this.decision); }
    get isDuplicate() { return this.decision === 'Duplicate'; }
    get needsNote() { return !!this.decisionDef && this.decisionDef.action !== 'jira'; }
    get noteLabel() { return this.decision === 'Needs Info' ? 'What does the tester need to add?' : 'Final resolution (the tester sees this)'; }
    get notePlaceholder() {
        return this.decision === 'Needs Info'
            ? 'e.g. Which inquiry were you on, and what did you click?'
            : 'e.g. This works as designed: …';
    }
    get primaryLabel() {
        const d = this.decisionDef;
        if (!d) return 'Pick a decision';
        if (d.value === 'Bug' && !this.hasStory) return 'Pick the story first';
        if (d.action === 'jira') return `Create Jira ticket (${d.value})`;
        if (d.action === 'needsInfo') return 'Send back to tester';
        return 'Resolve without Jira';
    }
    get primaryTitle() { return this.decisionDef && this.decisionDef.action === 'jira' ? 'Create Jira ticket (J)' : 'Save the decision (Enter)'; }
    get primaryClass() { return 'ur-btn ur-primary' + (this.decisionDef && this.decisionDef.action === 'jira' ? ' ur-jira' : ''); }
    get primaryDisabled() {
        const d = this.decisionDef;
        if (!d || this.saving) return true;
        if (d.action !== 'jira' && !this.note.trim()) return true;
        if (this.isDuplicate && !this.duplicateOf) return true;
        if (this.decision === 'Bug' && !this.hasStory) return true;
        return false;
    }
    get nextLabel() { return this.saving ? 'Saving…' : this.isDirty ? 'Save & next' : 'Next'; }
    get nextTitle() { return this.isDirty ? 'Save your changes on this card and go to the next item (→)' : 'Next item (→)'; }

    // What the reviewer changed on this card (the note only counts with its decision button).
    get changes() {
        const c = this.current;
        if (!c) return {};
        const out = {};
        if (this.pickedStoryId && this.pickedStoryId !== c.storyId) out.storyId = this.pickedStoryId;
        if (this.proposal !== (c.proposal || '')) out.proposal = this.proposal;
        if (this.severity && this.severity !== c.severity) out.severity = this.severity;
        if (this.decision !== this.initialDecision) out.decision = this.decision;
        return out;
    }
    get isDirty() { return Object.keys(this.changes).length > 0; }
    get hasUnsavedWork() { return this.isDirty || !!this.note.trim(); }

    // ---------- draft handling ----------
    resetDraft() {
        const c = this.current;
        this.actionError = undefined;
        this.navNotice = undefined;
        this.note = '';
        this.duplicateOf = undefined;
        this.pickedStoryId = undefined;
        this.pickedStoryName = undefined;
        this.pickedStoryUrl = undefined;
        this.showStoryPicker = false;
        this.proposal = (c && c.proposal) || '';
        this.severity = c && c.severity;
        this.decision = this.startingDecision(c);
        this.initialDecision = this.decision;
    }

    // A determination saved with Next wins; otherwise preselect what triage proposed
    // ("Proposed: <classification>" on the first line of the proposed resolution).
    startingDecision(c) {
        if (!c) return undefined;
        if (c.determination && DRAFT_DECISIONS.includes(c.determination)) return c.determination;
        const m = /Proposed:\s*([A-Za-z' ]+)/i.exec(c.proposal || '');
        const guess = m ? m[1].trim().toLowerCase() : '';
        const hit = DECISIONS.find((d) => guess.startsWith(d.value.toLowerCase()));
        return hit ? hit.value : undefined;
    }

    handleProposal(e) {
        this.proposal = e.target.value;
        this.autoGrow(e.target);
    }
    handleNote(e) {
        this.note = e.target.value;
        this.autoGrow(e.target);
    }
    handleDuplicateOf(e) { this.duplicateOf = e.detail.recordId; }
    handleToggleStory() { this.showStoryPicker = !this.showStoryPicker; }
    handleStoryPick(e) {
        this.pickedStoryId = e.detail.recordId;
        this.pickedStoryName = this.pickedStoryId ? 'Loading…' : undefined;
        if (this.pickedStoryId) this.showStoryPicker = false;
    }
    handleDecision(e) {
        this.decision = e.currentTarget.dataset.value;
        this.actionError = undefined;
    }
    handleSeverity(e) {
        this.severity = e.currentTarget.dataset.value;
    }

    // ---------- navigation ----------
    handleView(e) {
        const view = e.currentTarget.dataset.view;
        if (view !== this.view) {
            this.view = view;
            this.load();
        }
    }
    handleRefresh() { this.load(); }

    nextIndex(from) {
        let i = from + 1;
        while (i < this.total && this.decided.has(this.items[i].id)) i++;
        return i; // may be total (end of the list)
    }
    prevIndex(from) {
        let i = from - 1;
        while (i >= 0 && this.decided.has(this.items[i].id)) i--;
        return i;
    }
    goTo(i) {
        if (i < 0 || i > this.total || i === this.index) return false;
        this.index = i;
        this.resetDraft();
        const body = this.template.querySelector('.ur-body');
        if (body) body.scrollTop = 0;
        this.focusCard();
        return true;
    }
    handleSkip() { this.goTo(this.nextIndex(this.index)); }
    handleBack() { this.goTo(this.prevIndex(this.index)); }

    // Next: save what changed on the card (if anything), then move on.
    async handleNext() {
        const c = this.current;
        if (!c || this.saving) return;
        const ch = this.changes;
        if (!Object.keys(ch).length) {
            this.handleSkip();
            return;
        }
        const draftDecision = ch.decision && DRAFT_DECISIONS.includes(ch.decision) ? ch.decision : null;
        const heldBack = ch.decision && !draftDecision ? this.decisionDef.label : null;
        this.saving = true;
        this.actionError = undefined;
        try {
            if (draftDecision || ch.proposal !== undefined || ch.storyId || ch.severity) {
                await saveDraft({
                    itemId: c.id,
                    decision: draftDecision,
                    proposal: ch.proposal !== undefined ? ch.proposal : null,
                    storyId: ch.storyId || null,
                    severity: ch.severity || null
                });
                // Keep the saved values so Back shows them.
                if (draftDecision) c.determination = draftDecision;
                if (ch.proposal !== undefined) c.proposal = ch.proposal;
                if (ch.severity) c.severity = ch.severity;
                if (ch.storyId) {
                    c.storyId = ch.storyId;
                    c.storyName = this.pickedStoryName;
                    c.storyUrl = this.pickedStoryUrl;
                    c.storySuggested = false;
                }
                this.saved = new Set([...this.saved, c.id]);
            }
            if (heldBack) {
                this.toast(`${c.name}: card saved. "${heldBack}" isn't saved by Next; use the decision button.`, 'warning');
            } else {
                this.toast(`${c.name}: saved.`, 'success');
            }
            this.goTo(this.nextIndex(this.index));
        } catch (e) {
            this.actionError = this.errorText(e);
        } finally {
            this.saving = false;
        }
    }

    async handlePrimary() {
        if (this.primaryDisabled) return;
        const d = this.decisionDef;
        const c = this.current;
        const ch = this.changes;
        this.saving = true;
        this.actionError = undefined;
        try {
            await decide({
                itemId: c.id,
                action: d.action,
                decision: d.action === 'needsInfo' ? null : d.value,
                proposal: ch.proposal !== undefined ? ch.proposal : null,
                resolution: d.action === 'jira' ? null : this.note,
                duplicateOf: this.isDuplicate ? this.duplicateOf : null,
                storyId: this.pickedStoryId || null,
                severity: ch.severity || null
            });
            this.decided = new Set([...this.decided, c.id]);
            this.toast(`${c.name}: ${this.doneMessage(d)}`, 'success');
            this.goTo(this.nextIndex(this.index));
        } catch (e) {
            this.actionError = this.errorText(e);
        } finally {
            this.saving = false;
        }
    }

    doneMessage(d) {
        if (d.action === 'jira') return 'Jira ticket requested.';
        if (d.action === 'needsInfo') return 'sent back to the tester.';
        return `resolved as ${d.label.toLowerCase()}.`;
    }

    // ---------- mouse wheel "Rolodex" (Ben, Nov 13) ----------
    // Over the header, progress bar or item header the wheel flips items: one flick = one item.
    handleWheel(e) {
        if (!this.current || this.loading || this.saving) return;
        if (this.isEditable(e)) return;
        e.preventDefault();
        if (this.wheelLocked) {
            this.armWheelLock();
            return;
        }
        if (Math.abs(e.deltaY) < 4) return;
        this.armWheelLock();
        if (this.hasUnsavedWork) {
            this.navNotice = 'You have unsaved changes on this item: Next (→) saves them, Skip (S) drops them.';
            return;
        }
        if (e.deltaY > 0) this.handleSkip();
        else this.handleBack();
    }
    armWheelLock() {
        this.wheelLocked = true;
        clearTimeout(this.wheelTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.wheelTimer = setTimeout(() => {
            this.wheelLocked = false;
        }, WHEEL_QUIET_MS);
    }

    handleOpenItem(e) {
        e.preventDefault();
        this.navTo(this.current.id);
    }
    handleOpenCaptured(e) {
        e.preventDefault();
        this.navTo(this.current.recordId);
    }
    navTo(recordId) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId, actionName: 'view' } });
    }

    // ← back, → next (saves), S skip, J = create Jira ticket, Enter = save the decision. Only outside text boxes.
    handleKey(e) {
        if (!this.current || e.ctrlKey || e.metaKey || e.altKey || this.isEditable(e)) return;
        const key = e.key;
        if (key === 'ArrowRight') {
            e.preventDefault();
            this.handleNext();
        } else if (key === 'ArrowLeft') {
            e.preventDefault();
            if (!this.saving) this.handleBack();
        } else if (key === 's' || key === 'S') {
            e.preventDefault();
            if (!this.saving) this.handleSkip();
        } else if ((key === 'j' || key === 'J') && this.decisionDef && this.decisionDef.action === 'jira') {
            this.handlePrimary();
        } else if (key === 'Enter' && e.target === this.template.querySelector('article')) {
            this.handlePrimary();
        }
    }

    isEditable(e) {
        const path = (e.composedPath && e.composedPath()) || [e.target];
        return path.some((n) => n && n.tagName && (EDITABLE_TAGS.includes(n.tagName) || n.isContentEditable));
    }

    focusCard() {
        // Keep keyboard shortcuts working after moving (focus the card, not a text box).
        Promise.resolve().then(() => {
            const el = this.template.querySelector('article');
            const active = this.template.activeElement;
            if (el && (!active || active.tagName === 'BUTTON')) el.focus({ preventScroll: true });
        });
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
    errorText(e) {
        return (e && (e.body?.message || e.message)) || 'Something went wrong.';
    }
}
