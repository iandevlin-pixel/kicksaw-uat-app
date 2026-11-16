/**
 * Back end for the uatReview component (Kicksaw UAT App v2): Kicksaw reviewers work through
 * UAT Feedback one item at a time and decide, for each, whether it becomes a Jira ticket
 * (Bug / Enhancement) or is resolved in Salesforce (Training, Not a Bug, Duplicate, Won't Do),
 * or goes back to the tester (Needs Info). There is deliberately no "mark all" action.
 */
public with sharing class UatReviewController {

    private static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        'Blocker' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
    };
    private static final Set<String> JIRA_TYPES = new Set<String>{ 'Bug', 'Enhancement' };
    private static final Map<String, String> RESOLVE_STATUS = new Map<String, String>{
        'Training' => 'Resolved', 'Not a Bug' => 'Not a Bug', 'Duplicate' => 'Duplicate', 'Won\'t Do' => 'Won\'t Do'
    };
    private static final Set<String> DETERMINATIONS = new Set<String>{ 'Bug', 'Enhancement', 'Not a Bug', 'Needs Info', 'Training' };
    // Determinations "Next" can save without acting on them; the item stays in the To review queue until a
    // reviewer creates the Jira ticket, resolves it or sends it back.
    private static final Set<String> DRAFT_DETERMINATIONS = new Set<String>{ 'Bug', 'Enhancement', 'Not a Bug', 'Training' };
    private static final Set<String> SEVERITIES = new Set<String>{ 'Blocker', 'High', 'Medium', 'Low' };

    public class Item {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String steps;
        @AuraEnabled public String expected;
        @AuraEnabled public String actual;
        @AuraEnabled public Id storyId;
        @AuraEnabled public Boolean storySuggested;
        @AuraEnabled public String storyName;
        @AuraEnabled public String storyUrl;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String objectName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String proposal;
        @AuraEnabled public String reasoning;
        @AuraEnabled public String repro;
        @AuraEnabled public Datetime lastTriageRun;
        @AuraEnabled public String determination;
        @AuraEnabled public String resolution;
        @AuraEnabled public Integer fileCount;
    }

    /**
     * @param view 'review' = new items with no Kicksaw decision acted on yet (default; includes items whose
     *             determination was saved with Next but not yet sent to Jira / resolved);
     *             'needsInfo' = items sent back to the tester as Needs Info.
     */
    @AuraEnabled
    public static List<Item> getQueue(String view) {
        Boolean needsInfo = view == 'needsInfo';
        List<UAT_Feedback__c> rows = needsInfo
            ? [SELECT Id, Name, Type__c, Priority__c, Status__c, Description__c, Steps__c, ExpectedBehavior__c,
                      Actual_Behavior__c, Tested_Story__c, Story_Suggested_by_Claude__c, Tested_Story__r.Name, Tested_Story_Jira__c, SubmittedBy__r.Name, CreatedDate,
                      ObjectName__c, RecordURL__c, Claude_Proposed_Resolution__c, Claude_Classification_Reasoning__c,
                      Claude_Repro_Steps__c, Last_Triage_Run__c, Kicksaw_Determination__c, Resolution__c
               FROM UAT_Feedback__c
               WHERE Status__c = 'New' AND Kicksaw_Determination__c = 'Needs Info'
               WITH USER_MODE ORDER BY CreatedDate LIMIT 200]
            : [SELECT Id, Name, Type__c, Priority__c, Status__c, Description__c, Steps__c, ExpectedBehavior__c,
                      Actual_Behavior__c, Tested_Story__c, Story_Suggested_by_Claude__c, Tested_Story__r.Name, Tested_Story_Jira__c, SubmittedBy__r.Name, CreatedDate,
                      ObjectName__c, RecordURL__c, Claude_Proposed_Resolution__c, Claude_Classification_Reasoning__c,
                      Claude_Repro_Steps__c, Last_Triage_Run__c, Kicksaw_Determination__c, Resolution__c
               FROM UAT_Feedback__c
               WHERE Status__c = 'New' AND Needs_Jira_Ticket__c = false
                 AND (Kicksaw_Determination__c = null OR Kicksaw_Determination__c IN :DRAFT_DETERMINATIONS)
               WITH USER_MODE ORDER BY CreatedDate LIMIT 200];
        Map<Id, Integer> files = new Map<Id, Integer>();
        if (!rows.isEmpty()) {
            Set<Id> ids = new Map<Id, UAT_Feedback__c>(rows).keySet();
            for (AggregateResult ar : [SELECT LinkedEntityId parentId, COUNT(Id) n FROM ContentDocumentLink
                                       WHERE LinkedEntityId IN :ids GROUP BY LinkedEntityId]) {
                files.put((Id) ar.get('parentId'), (Integer) ar.get('n'));
            }
        }
        List<Item> items = new List<Item>();
        for (UAT_Feedback__c r : rows) {
            Item i = new Item();
            i.id = r.Id;
            i.name = r.Name;
            i.type = r.Type__c;
            i.severity = r.Priority__c;
            i.status = r.Status__c;
            i.description = r.Description__c;
            i.steps = r.Steps__c;
            i.expected = r.ExpectedBehavior__c;
            i.actual = r.Actual_Behavior__c;
            i.storyId = r.Tested_Story__c;
            i.storySuggested = r.Story_Suggested_by_Claude__c;
            i.storyName = r.Tested_Story__r?.Name;
            i.storyUrl = r.Tested_Story_Jira__c;
            i.submittedBy = r.SubmittedBy__r?.Name;
            i.createdDate = r.CreatedDate;
            i.objectName = r.ObjectName__c;
            i.recordId = r.RecordURL__c;
            i.proposal = r.Claude_Proposed_Resolution__c;
            i.reasoning = r.Claude_Classification_Reasoning__c;
            i.repro = r.Claude_Repro_Steps__c;
            i.lastTriageRun = r.Last_Triage_Run__c;
            i.determination = r.Kicksaw_Determination__c;
            i.resolution = r.Resolution__c;
            i.fileCount = files.containsKey(r.Id) ? files.get(r.Id) : 0;
            items.add(i);
        }
        items.sort(new BySeverity());
        return items;
    }

    private class BySeverity implements Comparator<Item> {
        public Integer compare(Item a, Item b) {
            Integer ra = SEVERITY_RANK.containsKey(a.severity) ? SEVERITY_RANK.get(a.severity) : 9;
            Integer rb = SEVERITY_RANK.containsKey(b.severity) ? SEVERITY_RANK.get(b.severity) : 9;
            if (ra != rb) { return ra - rb; }
            if (a.createdDate == b.createdDate) { return 0; }
            return a.createdDate < b.createdDate ? -1 : 1;
        }
    }

    /**
     * Saves the reviewer's decision on one item.
     * @param action      'jira' (Bug / Enhancement: requests a Jira ticket),
     *                    'resolve' (Training, Not a Bug, Duplicate, Won't Do: closes it in Salesforce),
     *                    'needsInfo' (sends it back to the tester)
     * @param decision    Bug, Enhancement, Training, Not a Bug, Duplicate or Won't Do
     * @param proposal    the (edited) proposed resolution; it goes into the Jira ticket
     * @param resolution  Final Resolution for 'resolve', or the question for the tester for 'needsInfo'
     * @param duplicateOf the original item when decision = Duplicate
     * @param storyId     the tested story the reviewer confirmed or picked (null = leave as is)
     * @param severity    Blocker, High, Medium or Low if the reviewer changed it (null = leave as is)
     */
    @AuraEnabled
    public static void decide(Id itemId, String action, String decision, String proposal, String resolution, Id duplicateOf, Id storyId, String severity) {
        requireReviewer();
        UAT_Feedback__c current = [SELECT Tested_Story__c FROM UAT_Feedback__c WHERE Id = :itemId WITH USER_MODE];
        UAT_Feedback__c item = cardEdits(current, itemId, proposal, storyId, severity);
        Id story = storyId != null ? storyId : current.Tested_Story__c;
        if (action == 'jira') {
            if (!JIRA_TYPES.contains(decision)) {
                throw new AuraHandledException('Only a Bug or an Enhancement gets a Jira ticket.');
            }
            if (decision == 'Bug' && story == null) {
                throw new AuraHandledException('Pick the tested story first: a bug\'s Jira ticket hangs off its story.');
            }
            item.Kicksaw_Determination__c = decision;
            item.Needs_Jira_Ticket__c = true;
            item.Jira_Requested_At__c = System.now();
            item.Jira_Sync_Status__c = 'Requested';
        } else if (action == 'resolve') {
            if (!RESOLVE_STATUS.containsKey(decision)) {
                throw new AuraHandledException('Pick Training, Not a Bug, Duplicate or Won\'t Do to resolve without Jira.');
            }
            if (String.isBlank(resolution)) {
                throw new AuraHandledException('Write a Final Resolution for the tester first.');
            }
            if (decision == 'Duplicate' && duplicateOf == null) {
                throw new AuraHandledException('Pick the original item for a duplicate.');
            }
            if (DETERMINATIONS.contains(decision)) {
                item.Kicksaw_Determination__c = decision;
            }
            item.Status__c = RESOLVE_STATUS.get(decision);
            item.Resolution__c = resolution;
            item.Duplicate_Of__c = decision == 'Duplicate' ? duplicateOf : null;
        } else if (action == 'needsInfo') {
            if (String.isBlank(resolution)) {
                throw new AuraHandledException('Say what the tester needs to add.');
            }
            item.Kicksaw_Determination__c = 'Needs Info';
            item.Resolution__c = 'Needs info: ' + resolution;
        } else {
            throw new AuraHandledException('Unknown action: ' + action);
        }
        save(item);
    }

    /**
     * "Next" on UAT Review: saves what the reviewer changed on the card without acting on it, so the item stays
     * in the To review queue. Saves the tested story, severity, proposed resolution and, for Bug / Enhancement /
     * Training / Not a Bug, the determination. Needs Info, Duplicate and Won't Do need their note or original
     * item, so they are only saved by the decision buttons (decide).
     */
    @AuraEnabled
    public static void saveDraft(Id itemId, String decision, String proposal, Id storyId, String severity) {
        requireReviewer();
        if (decision != null && !DRAFT_DETERMINATIONS.contains(decision)) {
            throw new AuraHandledException('Use the decision button to save ' + decision + '.');
        }
        UAT_Feedback__c current = [SELECT Tested_Story__c FROM UAT_Feedback__c WHERE Id = :itemId WITH USER_MODE];
        UAT_Feedback__c item = cardEdits(current, itemId, proposal, storyId, severity);
        if (decision != null) {
            item.Kicksaw_Determination__c = decision;
        }
        save(item);
    }

    private static void requireReviewer() {
        if (!FeatureManagement.checkPermission('UAT_Kicksaw_Reviewer')) {
            throw new AuraHandledException('Only Kicksaw reviewers can make UAT decisions.');
        }
    }

    // The fields a reviewer can edit on the card, whatever the decision.
    private static UAT_Feedback__c cardEdits(UAT_Feedback__c current, Id itemId, String proposal, Id storyId, String severity) {
        UAT_Feedback__c item = new UAT_Feedback__c(Id = itemId);
        if (storyId != null && storyId != current.Tested_Story__c) {
            item.Tested_Story__c = storyId;
            item.Story_Suggested_by_Claude__c = false; // a person picked it
        }
        if (proposal != null) {
            item.Claude_Proposed_Resolution__c = proposal;
        }
        if (severity != null) {
            if (!SEVERITIES.contains(severity)) {
                throw new AuraHandledException('Unknown severity: ' + severity);
            }
            item.Priority__c = severity;
        }
        return item;
    }

    private static void save(UAT_Feedback__c item) {
        try {
            update as user item;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
}
