@isTest
private class MailchimpSyncControllerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public String respBody;

        public MailchimpApiMock() {
            this('{}');
        }

        public MailchimpApiMock(String respBody) {
            this.respBody = respBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody(respBody);
            return resp;
        }
    }

    static MailchimpSyncController subject() {
        return new MailchimpSyncController();
    }

    @isTest static void testContactsNeedingSync() {
        System.assertEquals('No', subject().contactsNeedingSync);
    }

    @isTest static void testLastSyncCompletedAt() {
        System.assertEquals('No sync has been performed yet.',
            subject().lastSyncCompletedAt);
    }

    @isTest static void testJobsInProgress() {
        System.assertEquals('No', subject().jobsInProgress);
    }

    @isTest static void testRecentSyncErrors() {
        System.assert(subject().recentSyncErrors != null);
        System.assertEquals(0, subject().recentSyncErrors.size());
    }

    @isTest static void testUnfinishedBatchOperations() {
        System.assert(subject().unfinishedBatchOperations != null);
    }

    @isTest static void testRecentJobs() {
        System.assert(subject().recentJobs != null);
        System.assertEquals(0, subject().recentJobs.size());
    }

    @isTest static void testMailchimpAudience() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        System.assertEquals(null, subject().mailchimpAudience);
    }

    @isTest static void testMailchimpListOptions() {
        Test.setMock(HttpCalloutMock.class,
            new MailchimpApiMock('{"lists":[]}'));
        System.assertEquals(0, subject().mailchimpListOptions.size());
    }

    @isTest static void testUpdateListID() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncController controller = subject();
        controller.mailchimpListID = 'aD9zFoQKSj';
        controller.updateListID();
        MailchimpSettings__c settings = MailchimpSettings__c.getOrgDefaults();
        System.assertEquals('aD9zFoQKSj', settings.AudienceID__c);

        Test.stopTest();
    }

    @isTest static void testUpdateContacts() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncController controller = subject();
        PageReference redirect = controller.updateContacts();
        System.assert(redirect.getRedirect());

        Test.stopTest();
    }

    @isTest static void testSyncAllContacts() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncController controller = subject();
        PageReference redirect = controller.syncAllContacts();
        System.assert(redirect.getRedirect());

        Test.stopTest();
    }

    @isTest static void testUpdateBatches() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncController controller = subject();
        PageReference redirect = controller.updateBatches();
        System.assert(redirect.getRedirect());

        Test.stopTest();
    }
}
