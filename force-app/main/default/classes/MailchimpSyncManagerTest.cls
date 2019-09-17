@isTest
private class MailchimpSyncManagerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint().substringAfter('/');
            System.debug(req.getMethod() + ' ' + endpoint);
            if (endpoint.startsWith('batches')) {
                resp.setBody('{"id":"rA45kKQWre","status":"pending","total_operations":1,"submitted_at":"2019-09-17T10:55:09Z"}');
            }
            else {
                resp.setBody('{}');
            }

            return resp;
        }
    }

    @TestSetup
    static void setup() {
        Id household = [SELECT Id FROM RecordType WHERE sObjectType = 'Account' AND DeveloperName = 'HH_Account' LIMIT 1].Id;
        Account a = new Account(Name='Schmoe Household', RecordTypeId=household);
        insert a;
        Contact c = new Contact(
            AccountId=a.Id,
            FirstName='Joe',
            LastName='Schmoe',
            Email='joe.schmoe@example.com',
            MailchimpLastChanged__c=Datetime.newInstance(2019, 9, 17, 10, 2, 55)
        );
        insert c;
    }

    @isTest static void testContactsToSync() {
        Test.startTest();

        MailchimpSyncManager subject = new MailchimpSyncManager();
        Contact[] contacts = subject.contactsToSync(1);
        System.assertEquals(1, contacts.size());
        System.assertEquals('Joe', contacts[0].FirstName);
        System.assertEquals('Schmoe', contacts[0].LastName);
        System.assertEquals(
            'Household Account',
            contacts[0].Account.SF_Record_Type__c
        );

        Test.stopTest();
    }

    @isTest static void testContactsCount() {
        Test.startTest();

        MailchimpSyncManager subject = new MailchimpSyncManager();
        Integer count = subject.contactsCount();
        System.assertEquals(1, count);

        Test.stopTest();
    }

    @isTest static void testPushAll() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();
        Contact testContact = [SELECT Id, Email, FirstName, LastName, Drupal_ID__c, Drupal_Username__c,
            Account.Id, Account.SF_Record_Type__c,
            Account.Membership_Level_Number__c, Account.Membership_Level__c,
            Account.Membership_level_qualification_amount__c, Account.Membership_Expiration_Date__c,
            Account.Recurring_donations_Annualized_value_new__c,
            Account.CY_contribution_revenue__c, Account.CY_1_contribution_revenue__c,
            Account.CY_2_contribution_revenue__c, Account.CY_3_contribution_revenue__c,
            Active_sustainer_account__c, Is_partner_offer_eligible__c,
            Current_member__c, Lapsed_member__c, Never_member__c,
            MinnPost_com_user_account__c, MailchimpNeedsSync__c
            FROM Contact LIMIT 1];
        System.assertEquals('Household Account', testContact.Account.SF_Record_Type__c);
        System.assert(testContact.MailchimpNeedsSync__c);

        List<Contact> contacts = new List<Contact>{ testContact };
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MailchimpSyncManager.Result result = mailchimp.pushAll(contacts);
        System.assert(!result.isError());
        System.assert(result.contactErrors.isEmpty());

        Test.stopTest();
    }
}
