@IsTest
private class UatReviewControllerTest {

    private static User reviewer() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String u = 'uatreview' + Crypto.getRandomInteger() + '@example.com.test';
        User usr = new User(Alias = 'uatrev', Email = 'uatreview@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Reviewer', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles', UserName = u);
        insert usr;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Kicksaw_UAT_App' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = usr.Id, PermissionSetId = ps.Id);
        return usr;
    }

    private static UAT_Feedback__c item(String severity) {
        return new UAT_Feedback__c(Type__c = 'Bug', Priority__c = severity, Status__c = 'New',
            Description__c = 'Review test ' + severity, Claude_Proposed_Resolution__c = 'Proposed: Bug');
    }

    @IsTest
    static void queueSortsBySeverityAndDecisionsSave() {
        User usr = reviewer();
        System.runAs(usr) {
            List<UAT_Feedback__c> rows = new List<UAT_Feedback__c>{ item('Low'), item('Blocker'), item('Medium'), item('High') };
            insert rows;

            List<UatReviewController.Item> queue = UatReviewController.getQueue('review');
            System.assertEquals(4, queue.size());
            System.assertEquals('Blocker', queue[0].severity, 'Blockers first');
            System.assertEquals('Low', queue[3].severity);

            // Jira
            UAT_Story__c story = new UAT_Story__c(Name = 'PROJ-1 Test story', Jira_Key__c = 'PROJ-1');
            insert story;
            Boolean blocked = false;
            try { UatReviewController.decide(queue[0].id, 'jira', 'Bug', null, null, null, null, null); } catch (AuraHandledException e) { blocked = true; }
            System.assert(blocked, 'A bug needs a story before Jira');
            UatReviewController.decide(queue[0].id, 'jira', 'Bug', 'Proposed: Bug. Fix the save.', null, null, story.Id, null);
            UAT_Feedback__c jira = [SELECT Kicksaw_Determination__c, Needs_Jira_Ticket__c, Jira_Sync_Status__c, Claude_Proposed_Resolution__c FROM UAT_Feedback__c WHERE Id = :queue[0].id];
            System.assertEquals('Bug', jira.Kicksaw_Determination__c);
            System.assertEquals(story.Id, [SELECT Tested_Story__c FROM UAT_Feedback__c WHERE Id = :queue[0].id].Tested_Story__c);
            System.assert(jira.Needs_Jira_Ticket__c);
            System.assertEquals('Requested', jira.Jira_Sync_Status__c);
            System.assert(jira.Claude_Proposed_Resolution__c.contains('Fix the save'));

            // Resolve without Jira
            UatReviewController.decide(queue[1].id, 'resolve', 'Training', null, 'Use the Edit button on the inquiry.', null, null, null);
            UAT_Feedback__c trained = [SELECT Status__c, Kicksaw_Determination__c FROM UAT_Feedback__c WHERE Id = :queue[1].id];
            System.assertEquals('Resolved', trained.Status__c);
            System.assertEquals('Training', trained.Kicksaw_Determination__c);

            // Duplicate
            UatReviewController.decide(queue[2].id, 'resolve', 'Duplicate', null, 'Same as the other item.', queue[0].id, null, null);
            System.assertEquals('Duplicate', [SELECT Status__c FROM UAT_Feedback__c WHERE Id = :queue[2].id].Status__c);

            // Needs info
            UatReviewController.decide(queue[3].id, 'needsInfo', null, null, 'Which inquiry was it?', null, null, null);
            System.assertEquals(1, UatReviewController.getQueue('needsInfo').size());
            System.assertEquals(0, UatReviewController.getQueue('review').size(), 'Every item decided');
        }
    }

    @IsTest
    static void invalidDecisionsAreRejected() {
        User usr = reviewer();
        System.runAs(usr) {
            UAT_Feedback__c row = item('High');
            insert row;
            for (List<String> bad : new List<List<String>>{
                    new List<String>{ 'jira', 'Training', null },
                    new List<String>{ 'resolve', 'Bug', 'x' },
                    new List<String>{ 'resolve', 'Not a Bug', '' },
                    new List<String>{ 'resolve', 'Duplicate', 'x' },
                    new List<String>{ 'needsInfo', null, '' },
                    new List<String>{ 'other', null, 'x' } }) {
                Boolean failed = false;
                try {
                    UatReviewController.decide(row.Id, bad[0], bad[1], null, bad[2], null, null, null);
                } catch (AuraHandledException e) {
                    failed = true;
                }
                System.assert(failed, 'Expected a rejection for ' + bad);
            }
        }
    }

    @IsTest
    static void nonReviewersCannotDecide() {
        UAT_Feedback__c row = item('Low');
        insert row;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User other = new User(Alias = 'uatoth', Email = 'uatother@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Other', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles', UserName = 'uatother' + Crypto.getRandomInteger() + '@example.com.test');
        insert other;
        System.runAs(other) {
            Boolean failed = false;
            try {
                UatReviewController.decide(row.Id, 'jira', 'Bug', null, null, null, null, null);
            } catch (AuraHandledException e) {
                failed = true;
            }
            System.assert(failed, 'Non-reviewers are blocked');
        }
    }

    @IsTest
    static void nextSavesCardEditsAndKeepsItemInQueue() {
        User usr = reviewer();
        System.runAs(usr) {
            UAT_Feedback__c row = item('Low');
            insert row;
            UAT_Story__c story = new UAT_Story__c(Name = 'PROJ-2 Test story', Jira_Key__c = 'PROJ-2');
            insert story;
            UatReviewController.saveDraft(row.Id, 'Bug', 'Proposed: Bug. Edited.', story.Id, 'High');
            UAT_Feedback__c saved = [SELECT Kicksaw_Determination__c, Priority__c, Tested_Story__c, Story_Suggested_by_Claude__c,
                                            Claude_Proposed_Resolution__c, Needs_Jira_Ticket__c, Status__c
                                     FROM UAT_Feedback__c WHERE Id = :row.Id];
            System.assertEquals('Bug', saved.Kicksaw_Determination__c);
            System.assertEquals('High', saved.Priority__c);
            System.assertEquals(story.Id, saved.Tested_Story__c);
            System.assertEquals(false, saved.Story_Suggested_by_Claude__c);
            System.assertEquals('Proposed: Bug. Edited.', saved.Claude_Proposed_Resolution__c);
            System.assertEquals(false, saved.Needs_Jira_Ticket__c, 'Next does not request Jira');
            System.assertEquals('New', saved.Status__c);
            List<UatReviewController.Item> queue = UatReviewController.getQueue('review');
            System.assertEquals(1, queue.size(), 'Saved but not acted on: still to review');
            System.assertEquals('Bug', queue[0].determination);

            // Severity on a decision, and draft-only rules
            UatReviewController.decide(row.Id, 'jira', 'Bug', null, null, null, null, 'Blocker');
            System.assertEquals('Blocker', [SELECT Priority__c FROM UAT_Feedback__c WHERE Id = :row.Id].Priority__c);
            System.assertEquals(0, UatReviewController.getQueue('review').size());
            for (List<String> bad : new List<List<String>>{ new List<String>{ 'Needs Info', null }, new List<String>{ null, 'Urgent' } }) {
                Boolean failed = false;
                try { UatReviewController.saveDraft(row.Id, bad[0], null, null, bad[1]); } catch (AuraHandledException e) { failed = true; }
                System.assert(failed, 'Expected a rejection for ' + bad);
            }
        }
    }
}
