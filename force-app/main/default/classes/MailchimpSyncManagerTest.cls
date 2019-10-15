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
            else if (req.getMethod() == 'GET' && endpoint.startsWith('lists/3528e74526/members')) {
                MailchimpAPI.Subscriber sub = new MailchimpAPI.Subscriber();
                sub.id = '7ec16a886e5baa2052c20bb16464a45b';
                sub.email_address = 'helen1604@example.com';
                sub.status = 'subscribed';
                sub.member_rating = 3;
                sub.last_changed = Datetime.newInstanceGmt(2019, 9, 17, 10, 55, 9);
                sub.merge_fields = new Map<String, String>{};
                sub.interests = new Map<String, Boolean>{};
                MailchimpSyncManager.MembersResponse mr =
                    new MailchimpSyncManager.MembersResponse();
                mr.members = new List<MailchimpAPI.Subscriber>{ sub };
                mr.total_items = 1;
                resp.setBody(JSON.serialize(mr));
            }
            else {
                resp.setBody('{}');
            }

            return resp;
        }
    }

    @TestSetup
    static void setup() {
        MailchimpSettings__c settings = MailchimpSettings__c.getOrgDefaults();
        settings.AudienceID__c = '3528e74526';
        upsert settings;

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
            new Contact(
                FirstName='Joe',
                LastName='Schmoe',
                Email='joe.schmoe@example.com'
            ),
            new Contact(
                FirstName='Julie',
                LastName='Schmoo',
                Email='jschmoo@example.com'
            ),
            new Contact(
                FirstName='Abdi',
                LastName='Mohammed',
                Email='mohabdi@example.com'
            ),
            new Contact(
                FirstName='Helen',
                LastName='Troius',
                Email='helen1604@example.com'
            ),
            new Contact(
                FirstName='Fujiwara',
                LastName='Morimoto',
                Email='mfuji@example.co.jp'
            )
        };
        Database.SaveResult[] results = Database.insert(testContacts);

        MailchimpSyncStatus__c[] testStatuses = new List<MailchimpSyncStatus__c>{
            // Pulled but never pushed back
            new MailchimpSyncStatus__c(
                Email__c='joe.schmoe@example.com',
                LastChanged__c=Datetime.newInstanceGmt(2019, 9, 17, 10, 2, 55)
            ),

            // jschmoo@example.com - Not in Mailchimp, should not be pushed
            null,

            // Already pushed, should not be pushed again
            new MailchimpSyncStatus__c(
                Email__c='mohabdi@example.com',
                LastChanged__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 9),
                // This will be (very slightly) greater than the contact's
                // LastModifiedDate
                LastPushed__c=Datetime.now()
            ),

            // Pulled but not pushed back yet
            new MailchimpSyncStatus__c(
                Email__c='helen1604@example.com',
                LastChanged__c=Datetime.newInstanceGmt(2019, 9, 12, 5, 5, 5),
                // A day ago is less than the contact's LastModifiedDate
                LastPushed__c=(Datetime.now() - 1)
            ),

            // Synced but tag operation still in progress, should show up in count
            new MailchimpSyncStatus__c(
                Email__c='mfuji@example.co.jp',
                BatchID__c='psBNCYMK33',
                LastChanged__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 9),
                // This will be (very slightly) greater than the contact's
                // LastModifiedDate
                LastPushed__c=Datetime.now()
            )
        };

        MailchimpSyncStatus__c[] statusesToInsert = new List<MailchimpSyncStatus__c>();
        for (Integer i = 0; i < results.size(); ++i) {
            MailchimpSyncStatus__c status = testStatuses[i];
            if (status == null) continue;

            status.Contact__c = results[i].getId();
            statusesToInsert.add(status);
        }
        insert statusesToInsert;
        for (Contact c : testContacts) {
            c.recalculateFormulas();
        }
    }

    static MailchimpSyncManager subject() {
        MailchimpFieldMapping__mdt[] fieldMappings = new List<MailchimpFieldMapping__mdt>{
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Id',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Id',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='SF_CONTACT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Email',
                Direction__c='sync',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Email',
                Mailchimp_Member_Attribute__c='email_address'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.FirstName',
                Direction__c='sync',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='FirstName',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='FNAME'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.LastName',
                Direction__c='sync',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='LastName',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='LNAME'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Drupal_ID',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Drupal_ID__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CMS_UID'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Drupal_Username',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Drupal_Username__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CMS_USER'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.MailchimpEmailHash',
                Direction__c='sync',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='MailchimpEmailHash__c',
                Mailchimp_Member_Attribute__c='id'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.MailchimpMemberRating',
                Direction__c='pull',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='MailchimpMemberRating__c',
                Mailchimp_Member_Attribute__c='member_rating'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.CY_contribution_revenue',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='CY_contribution_revenue__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CY_CONTRIB'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.CY_1_contribution_revenue',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='CY_1_contribution_revenue__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CY_1_CONT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.CY_2_contribution_revenue',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='CY_2_contribution_revenue__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CY_2_CONT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.CY_3_contribution_revenue',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='CY_3_contribution_revenue__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='CY_3_CONT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Id',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Id',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='SF_ACCOUNT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Membership_Expiration_Date',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Membership_Expiration_Date__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='MEMBER_EXP'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Membership_Level',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Membership_Level__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='MEMBER_LEV'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Membership_Level_Number',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Membership_Level_Number__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='MEMLEV_NUM'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Membership_level_qualification_a',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Membership_level_qualification_amount__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='MEMLEV_AMT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.Recurring_donations_Annualized_v',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='Recurring_donations_Annualized_value_new__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='RECURR_AMT'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Account.SF_Record_Type',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Account',
                Salesforce_Field_API_Name__c='SF_Record_Type__c',
                Push_To_Mailchimp_As__c='*|MERGE|* Field',
                Mailchimp_Merge_Field_Tag__c='SFACCTTYPE'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Active_sustainer_account',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Active_sustainer_account__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='Active sustainer'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.MinnPost_com_user_account',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='MinnPost_com_user_account__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='CMS user'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Current_member',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Current_member__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='Current member'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Lapsed_member',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Lapsed_member__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='Lapsed member'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Never_member',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Never_member__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='Never member'
            ),
            new MailchimpFieldMapping__mdt(
                MasterLabel='Contact.Is_partner_offer_eligible',
                Direction__c='push',
                Salesforce_Object_API_Name__c='Contact',
                Salesforce_Field_API_Name__c='Is_partner_offer_eligible__c',
                Push_To_Mailchimp_As__c='Tag',
                Mailchimp_Merge_Field_Tag__c='Partner offer eligible'
            )
        };

        return new MailchimpSyncManager(fieldMappings);
    }

    @isTest static void testContactsToSync() {
        Test.startTest();

        Contact[] contacts = subject().contactsToSync(200);
        System.debug(contacts);
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

        Long delta = Datetime.now().getTime() -
            subject().lastSyncCompletedAt().getTime();
        System.debug('testLastSyncCompletedAt: delta = ' + delta);
        System.assert(
            delta < 30000 // 30s
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

    @isTest static void testPullAll() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncManager.PullResult result = subject().pullAll(1000, 0, false);
        System.assertEquals(MailchimpSyncManager.PullResult.DONE, result);

        Test.stopTest();
    }

    @isTest static void testPullAllSinceLastSync() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncManager.PullResult result = subject().pullAll(1000, 0);
        System.assertEquals(MailchimpSyncManager.PullResult.DONE, result);

        Test.stopTest();
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
