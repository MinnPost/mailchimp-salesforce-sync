@isTest
private class MailchimpSyncManagerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setHeader('Content-Type', 'application/json');
            resp.setBody('{}');

            return resp;
        }
    }

    @isTest static void testPushAll() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());

        Id household = [SELECT Id FROM RecordType WHERE sObjectType = 'Account' AND DeveloperName = 'HH_Account' LIMIT 1].Id;
        Account a = new Account(Name='Schmoe Household', RecordTypeId=household);
        insert a;
        Contact c = new Contact(AccountId=a.Id, FirstName='Joe', LastName='Schmoe', Email='joe.schmoe@example.com');
        insert c;

        Test.startTest();
        Id cId = c.Id;
        Contact testContact = [SELECT Id, Email, FirstName, LastName, Account.Id, Account.SF_Record_Type__c,
            Account.Membership_Level_Number__c, Account.Membership_Level__c,
            Account.Membership_level_qualification_amount__c, Account.Membership_Expiration_Date__c,
            Account.Recurring_donations_Annualized_value_new__c,
            Active_sustainer_account__c, Is_partner_offer_eligible__c,
            Current_member__c, Lapsed_member__c, Never_member__c,
            MinnPost_com_user_account__c
            FROM Contact WHERE Id = :cId LIMIT 1];
        System.assertEquals('Household Account', testContact.Account.SF_Record_Type__c);

        List<Contact> contacts = new List<Contact>{ testContact };
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MailchimpSyncManager.Result result = mailchimp.pushAll(contacts);
        System.assert(!result.isError());
        System.assert(result.contactErrors.isEmpty());

        Test.stopTest();
    }
}
