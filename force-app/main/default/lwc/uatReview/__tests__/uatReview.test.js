import { createElement } from 'lwc';
import UatReview from 'c/uatReview';
import getQueue from '@salesforce/apex/UatReviewController.getQueue';
import decide from '@salesforce/apex/UatReviewController.decide';
import saveDraft from '@salesforce/apex/UatReviewController.saveDraft';

jest.mock('@salesforce/apex/UatReviewController.getQueue', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/UatReviewController.decide', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/UatReviewController.saveDraft', () => ({ default: jest.fn() }), { virtual: true });

const ITEMS = [
    { id: 'a01000000000001AAA', name: 'UATI-1', type: 'Bug', severity: 'High', description: 'First', proposal: 'Proposed: Bug\nFix it', reasoning: 'Misses AC 2', repro: '1. Open\n2. Save' },
    { id: 'a01000000000002AAA', name: 'UATI-2', type: 'Bug', severity: 'Medium', description: 'Second', proposal: '' },
    { id: 'a01000000000003AAA', name: 'UATI-3', type: 'Enhancement', severity: 'Low', description: 'Third', proposal: 'Proposed: Enhancement' }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount() {
    getQueue.mockResolvedValue(ITEMS.map((i) => ({ ...i })));
    const el = createElement('c-uat-review', { is: UatReview });
    document.body.appendChild(el);
    await flush();
    await flush();
    return el;
}
const name = (el) => el.shadowRoot.querySelector('.ur-name').textContent;
const button = (el, label) => [...el.shadowRoot.querySelectorAll('button')].find((b) => b.textContent.trim() === label);
const key = (el, k) => el.shadowRoot.querySelector('article').dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, composed: true }));

describe('c-uat-review', () => {
    afterEach(() => {
        jest.useRealTimers();
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('shows the first item with the proposal in an editable box and no AI brand name', async () => {
        const el = await mount();
        expect(name(el)).toBe('UATI-1');
        expect(el.shadowRoot.querySelector('textarea[data-field="proposal"]').value).toBe('Proposed: Bug\nFix it');
        expect(el.shadowRoot.textContent.toLowerCase()).not.toContain('claude');
    });

    it('Skip and Back move without saving; Next with no changes just moves', async () => {
        const el = await mount();
        button(el, 'Skip').click();
        await flush();
        expect(name(el)).toBe('UATI-2');
        button(el, 'Back').click();
        await flush();
        expect(name(el)).toBe('UATI-1');
        button(el, 'Next').click();
        await flush();
        expect(name(el)).toBe('UATI-2');
        expect(saveDraft).not.toHaveBeenCalled();
    });

    it('Next saves severity, proposal and determination, then moves on', async () => {
        saveDraft.mockResolvedValue();
        const el = await mount();
        el.shadowRoot.querySelector('button[data-value="Blocker"]').click();
        const ta = el.shadowRoot.querySelector('textarea[data-field="proposal"]');
        ta.value = 'Proposed: Bug\nFix the save button';
        ta.dispatchEvent(new CustomEvent('input'));
        el.shadowRoot.querySelector('button[data-value="Enhancement"]').click();
        await flush();
        button(el, 'Save & next').click();
        await flush();
        expect(saveDraft).toHaveBeenCalledWith({
            itemId: ITEMS[0].id, decision: 'Enhancement', proposal: 'Proposed: Bug\nFix the save button', storyId: null, severity: 'Blocker'
        });
        expect(name(el)).toBe('UATI-2');
    });

    it('arrow keys: right = Next, left = Back, S = Skip; ignored inside a text box', async () => {
        const el = await mount();
        key(el, 'ArrowRight');
        await flush();
        expect(name(el)).toBe('UATI-2');
        key(el, 's');
        await flush();
        expect(name(el)).toBe('UATI-3');
        key(el, 'ArrowLeft');
        await flush();
        expect(name(el)).toBe('UATI-2');
        el.shadowRoot.querySelector('textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, composed: true }));
        await flush();
        expect(name(el)).toBe('UATI-2');
    });

    it('mouse wheel over the item header flips one item per flick, and holds when there are unsaved edits', async () => {
        const el = await mount();
        jest.useFakeTimers();
        const head = () => el.shadowRoot.querySelector('.ur-card-head');
        head().dispatchEvent(new WheelEvent('wheel', { deltaY: 60, bubbles: true, cancelable: true }));
        head().dispatchEvent(new WheelEvent('wheel', { deltaY: 60, bubbles: true, cancelable: true }));
        await Promise.resolve();
        expect(name(el)).toBe('UATI-2');
        jest.advanceTimersByTime(400);
        el.shadowRoot.querySelector('button[data-value="Low"]').click();
        await Promise.resolve();
        head().dispatchEvent(new WheelEvent('wheel', { deltaY: 60, bubbles: true, cancelable: true }));
        await Promise.resolve();
        expect(name(el)).toBe('UATI-2');
        expect(el.shadowRoot.querySelector('.ur-notice')).not.toBeNull();
        jest.useRealTimers();
    });

    it('the decision button still sends severity with the Jira request', async () => {
        decide.mockResolvedValue();
        const el = await mount();
        el.shadowRoot.querySelector('button[data-value="Enhancement"]').click();
        el.shadowRoot.querySelector('button[data-value="Low"]').click();
        await flush();
        button(el, 'Create Jira ticket (Enhancement)').click();
        await flush();
        expect(decide).toHaveBeenCalledWith(expect.objectContaining({ itemId: ITEMS[0].id, action: 'jira', decision: 'Enhancement', severity: 'Low' }));
        expect(name(el)).toBe('UATI-2');
    });
});
