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
        String text = UatSlackAlert.sent[0];
        System.assert(text.startsWith('New UAT feedback <'), text);
        System.assert(text.contains('Bug, High, no story picked, submitted by '), text);
        System.assert(!text.contains('Private tester text'), text);
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
