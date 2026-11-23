@IsTest
private class UatSlackAlertTest {
    private class SlackMock implements HttpCalloutMock {
        public Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            calls++;
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getEndpoint().startsWith('callout:Kicksaw_UAT_Slack'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    private static UAT_Feedback__c item() {
        return new UAT_Feedback__c(Type__c = 'Bug', Priority__c = 'High', Status__c = 'New',
            Description__c = 'Private tester text that must not be posted', SubmittedBy__c = UserInfo.getUserId());
    }

    @IsTest
    static void postsWhenEnabled() {
        UatSlackAlert.enabledOverride = true;
        SlackMock mock = new SlackMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        insert item();
        Test.stopTest();
        System.assertEquals(1, mock.calls);
        Map<String, String> body = UatSlackAlert.sent[0];
        System.assertEquals('🟥🟥🟥🟥🟥🟥🟥🟥', body.get('bar'));
        String details = body.get('details');
        System.assertEquals('Type: Bug\nPriority: High\nJira Story: none\nSubmitted By: ' + UserInfo.getName(), details);
        System.assert(String.isNotBlank(body.get('name')), body);
        System.assert(body.get('link').contains('/lightning/r/UAT_Feedback__c/'), body.get('link'));
        String text = body.get('text');
        System.assertEquals(body.get('bar') + '\nNew UAT feedback ' + body.get('name') + '\n' + details + '\n'
            + body.get('link'), text);
        System.assert(!text.contains('`'), text);
        System.assert(!JSON.serialize(body).contains('Private tester text'), text);
    }

    @IsTest
    static void barColorFollowsPriority() {
        System.assertEquals('🟥🟥🟥🟥🟥🟥🟥🟥', UatSlackAlert.priorityBar('Blocker'));
        System.assertEquals('🟥🟥🟥🟥🟥🟥🟥🟥', UatSlackAlert.priorityBar('High'));
        System.assertEquals('🟧🟧🟧🟧🟧🟧🟧🟧', UatSlackAlert.priorityBar('Medium'));
        System.assertEquals('🟩🟩🟩🟩🟩🟩🟩🟩', UatSlackAlert.priorityBar('Low'));
        System.assertEquals('⬜⬜⬜⬜⬜⬜⬜⬜', UatSlackAlert.priorityBar(null));
    }

    @IsTest
    static void silentWhenDisabled() {
        UatSlackAlert.enabledOverride = false;
        SlackMock mock = new SlackMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        insert item();
        Test.stopTest();
        System.assertEquals(0, mock.calls);
    }

    @IsTest
    static void slackErrorNeverBlocks() {
        UatSlackAlert.enabledOverride = true;
        Test.setMock(HttpCalloutMock.class, new FailingMock());
        Test.startTest();
        UAT_Feedback__c f = item();
        insert f;
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM UAT_Feedback__c WHERE Id = :f.Id]);
    }

    private class FailingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Slack is down');
        }
    }
}
