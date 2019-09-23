@isTest
private class MailchimpSyncManagerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint().substringAfter('/');
            System.debug(req.getMethod() + ' ' + endpoint);
            if (req.getMethod() == 'POST' && endpoint == 'batches') {
                resp.setBody('{"id":"rA45kKQWre","status":"pending","total_operations":1,"submitted_at":"2019-09-17T10:55:09Z"}');
            }
            else if (endpoint.startsWith('batches')) {
                resp.setBody('{"id":"rA45kKQWre","status":"finished","total_operations":1,"finished_operations":1,"errored_operations":0,"submitted_at":"2019-09-17T10:55:09Z","completed_at":"2019-09-19T10:56:10Z"}');
            }
            else {
                resp.setBody('{}');
            }

            return resp;
        }
    }

    @TestSetup
    static void setup() {
        Mailchimp_Batch_Operation__c batch = new Mailchimp_Batch_Operation__c(
            Name='rA45kKQWre',
            Status__c='pending',
            Submitted_At__c=Datetime.newInstanceGmt(2019, 9, 11, 10, 10, 50)
        );
        insert batch;
        Mailchimp_Batch_Operation__c finishedBatch = new Mailchimp_Batch_Operation__c(
            Name='MfpxUuhLKC',
            Status__c='finished',
            Submitted_At__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 50),
            Completed_At__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 10, 50),
            Total_Operations__c=1,
            Errored_Operations__c=0,
            Finished_Operations__c=1,
            Response_Body_URL__c='https://s3.amazonaws.com/example/batch.tgz'
        );
        insert finishedBatch;

        Contact[] testContacts = new List<Contact>{
            // Should be synced
            new Contact(
                FirstName='Joe',
                LastName='Schmoe',
                Email='joe.schmoe@example.com',
                MailchimpLastChanged__c=Datetime.newInstanceGmt(2019, 9, 17, 10, 2, 55)
            ),
            // Not in Mailchimp, should not be synced
            new Contact(
                FirstName='Julie',
                LastName='Schmoo',
                Email='jschmoo@example.com',
                MailchimpLastChanged__c=null
            ),
            // Already synced, should not be synced again
            new Contact(
                FirstName='Abdi',
                LastName='Mohammed',
                Email='mohabdi@example.com',
                MailchimpLastChanged__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 9),
                MailchimpLastSyncedAt__c=Datetime.newInstanceGmt(2019, 9, 11, 10, 10, 10)
            ),
            // Pulled but not pushed back yet
            new Contact(
                FirstName='Helen',
                LastName='Troius',
                Email='helen1604@example.com',
                MailchimpLastChanged__c=Datetime.newInstanceGmt(2019, 9, 12, 5, 5, 5),
                MailchimpLastSyncedAt__c=Datetime.newInstanceGmt(2019, 9, 11, 10, 10, 10)
            ),
            // Synced but tag operation still in progress
            new Contact(
                FirstName='Fujiwara',
                LastName='Morimoto',
                Email='mfuji@example.co.jp',
                MailchimpLastChanged__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 9),
                MailchimpLastSyncedAt__c=Datetime.newInstanceGmt(2019, 9, 11, 10, 10, 10),
                MailchimpBatchID__c='psBNCYMK33'
            )
        };
        insert testContacts;
    }

    static MailchimpSyncManager subject() {
        return new MailchimpSyncManager();
    }

    @isTest static void testContactsToSync() {
        Test.startTest();

        Contact[] contacts = subject().contactsToSync(400);
        System.assertEquals(2, contacts.size());
        System.assertEquals('Helen', contacts[0].FirstName);
        System.assertEquals('Troius', contacts[0].LastName);
        System.assertEquals(
            'Household Account',
            contacts[0].Account.SF_Record_Type__c
        );
        System.assertEquals('Joe', contacts[1].FirstName);
        System.assertEquals('Schmoe', contacts[1].LastName);
        System.assertEquals(
            'Household Account',
            contacts[1].Account.SF_Record_Type__c
        );

        Test.stopTest();
    }

    @isTest static void testContactsCount() {
        Test.startTest();

        Integer count = subject().contactsCount();
        System.assertEquals(3, count);

        Test.stopTest();
    }

    @isTest static void testUnfinishedBatches() {
        Test.startTest();

        Mailchimp_Batch_Operation__c[] batches = subject().unfinishedBatches();
        System.assertEquals(1, batches.size());
        System.assertEquals('rA45kKQWre', batches[0].Name);

        Test.stopTest();
    }

    @isTest static void testLastSyncCompletedAt() {
        Test.startTest();

        System.assertEquals(
            Datetime.newInstanceGmt(2019, 9, 11, 10, 10, 10),
            subject().lastSyncCompletedAt()
        );

        Test.stopTest();
    }

    @isTest static void testUpdateBatches() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        subject().updateBatches();
        Mailchimp_Batch_Operation__c batch =
            [SELECT Name, Status__c, Completed_At__c, Total_Operations__c
             FROM Mailchimp_Batch_Operation__c
             WHERE Name = 'rA45kKQWre' LIMIT 1];
        System.assertEquals('finished', batch.Status__c);
        System.assertEquals(
            Datetime.newInstanceGmt(2019, 9, 19, 10, 56, 10),
            batch.Completed_At__c
        );
    }

    @isTest static void testPushAll() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncManager mailchimp = subject();
        Contact[] contacts = mailchimp.contactsToSync(null);
        MailchimpSyncManager.Result result = mailchimp.pushAll(contacts);
        System.assert(!result.isError());
        System.assert(result.contactErrors.isEmpty());

        Test.stopTest();
    }
}
