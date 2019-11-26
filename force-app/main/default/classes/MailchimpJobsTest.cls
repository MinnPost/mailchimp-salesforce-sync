@isTest
private class MailchimpJobsTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            if (req.getEndpoint().startsWith('batches')) {
                resp.setBody('');
            }
            resp.setBody('{}');
            return resp;
        }
    }

    @isTest static void testMailchimpSyncJob() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        Integer nextYear = Date.today().year() + 1;
        String jobId = System.schedule(
            'MailchimpSyncJob',
            '0 0 0 26 11 ? ' + nextYear,
            new MailchimpSyncJob()
        );
        CronTrigger ct =
            [SELECT Id, CronExpression, TimesTriggered, NextFireTime
	         FROM CronTrigger WHERE id = :jobId];
        System.assertEquals(nextYear + '-11-26 00:00:00',
            String.valueOf(ct.NextFireTime));
        Test.stopTest();
    }

    @isTest static void testPullInterestsJob() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        String jobId = System.enqueueJob(new MailchimpPullInterestsJob());
        Test.stopTest();

        AsyncApexJob jobInfo = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', jobInfo.Status);
    }

    @isTest static void testPullJob() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        MailchimpPullJob job = new MailchimpPullJob(200, 0);
        String jobId = System.enqueueJob(job);
        Test.stopTest();

        AsyncApexJob jobInfo = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', jobInfo.Status);
    }

    @isTest static void testPushJob() {
        Contact testContact = new Contact(
            FirstName='Joe',
            LastName='Schmoe',
            Email='joe.schmoe@example.com'
        );
        insert testContact;
        MailchimpSyncStatus__c testStatus = new MailchimpSyncStatus__c(
            Contact__c=testContact.Id,
            Email__c='joe.schmoe@example.com',
            LastChanged__c=Datetime.newInstanceGmt(2019, 9, 17, 10, 2, 55)
        );
        insert testStatus;

        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        Id jobId = Database.executeBatch(new MailchimpPushJob());
        Test.stopTest();

        AsyncApexJob jobInfo = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', jobInfo.Status);
    }

    @isTest static void testUpdateBatchesJob() {
        Mailchimp_Batch_Operation__c batch = new Mailchimp_Batch_Operation__c(
            Name='2av7lDQzO94',
            Status__c='pending',
            Submitted_At__c=Datetime.newInstance(2019, 11, 10, 9, 8, 7)
        );
        insert batch;

        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        MailchimpUpdateBatchesJob job = new MailchimpUpdateBatchesJob();
        String jobId = Database.executeBatch(job);
        Test.stopTest();

        AsyncApexJob jobInfo = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', jobInfo.Status);
    }
}
