@isTest
private class MailchimpSyncManagerTest {
    class MailchimpApiMock implements HttpCalloutMock {
        public Boolean respondWithError { get; private set; }

        public MailchimpApiMock() {
            this(false);
        }

        public MailchimpApiMock(Boolean respondWithError) {
            this.respondWithError = respondWithError;
        }

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

                MailchimpAPI.Subscriber newSub = new MailchimpAPI.Subscriber();
                newSub.id = '779639e3ae4c9dac2663abfd18fca8d2';
                newSub.email_address = 'babs@barbrastreisand.com';
                newSub.status = 'subscribed';
                newSub.member_rating = 5;
                newSub.last_changed = Datetime.newInstanceGmt(1942, 4, 24, 12, 0, 0);
                newSub.merge_fields = new Map<String, String>{};
                newSub.interests = new Map<String, Boolean>{};

                MailchimpSyncManager.MembersResponse mr =
                    new MailchimpSyncManager.MembersResponse();
                mr.members = new List<MailchimpAPI.Subscriber>{ sub, newSub };
                mr.total_items = 2;
                resp.setBody(JSON.serialize(mr));
            }
            else if (
                req.getMethod() == 'GET' &&
                endpoint == 'lists/3528e74526/interest-categories'
            ) {
                resp.setBody('{"list_id":"3528e74526","categories":[{"list_id":"3528e74526","id":"9c9bf5fa6d","title":"Subscribe to these regular newsletters","display_order":0,"type":"checkboxes"},{"list_id":"3528e74526","id":"6707c372b5","title":"Occasional MinnPost emails","display_order":0,"type":"checkboxes"}],"total_items":2}');
            }
            else if (
                req.getMethod() == 'GET' &&
                endpoint.startsWith('lists/3528e74526/interest-categories/')
            ) {
                MailchimpAPI.Interest interest;

                if (endpoint.endsWith('/9c9bf5fa6d/interests')) {
                    interest = new MailchimpAPI.Interest(
                        '01cdc38eca', 'Greater Minnesota newsletter', 256
                    );
                }
                else if (endpoint.endsWith('/6707c372b5/interests')) {
                    interest = new MailchimpAPI.Interest(
                        'ff0e9befac', 'Opportunities to give input/feedback', 395
                    );
                }

                MailchimpAPI.InterestsResponse intResp = new MailchimpAPI.InterestsResponse(
                    new List<MailchimpAPI.Interest>{ interest }
                );
                resp.setBody(JSON.serialize(intResp));
            }
            else if (req.getMethod() == 'POST' && endpoint == 'lists/3528e74526') {
                if (this.respondWithError) {
                    resp.setBody('{"errors":[{"email_address":"joe.schmoe@example.com","error":"Test Batch Error"}],"total_created":0,"total_updated":0,"error_count":1}');
                }
                else {
                    resp.setBody('{}');
                }
            }
            else {
                System.assert(false, 'No mock response set for ' + req.getMethod() + ' ' + endpoint);
            }

            return resp;
        }
    }

    class MailchimpApiErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(422);
            resp.setBody('{"type":"test_error","title":"Test Error Response","status":"422","detail":"","instance":""}');
            return resp;
        }
    }

    class MailchimpApiInvalidJSONMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{[}] WAT');
            return resp;
        }
    }

    private static final Integer maxDelta = 60000; // 60s

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
        Mailchimp_Batch_Operation__c startedBatch = new Mailchimp_Batch_Operation__c(
            Name='G8XFlWEXtBI',
            Status__c='started',
            Submitted_At__c=Datetime.newInstanceGmt(2019, 9, 9, 9, 9, 9)
        );
        insert startedBatch;
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
                // A day from now is greater than the contact's
                // LastModifiedDate
                LastPushed__c=(Datetime.now() + 1)
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
                BatchID__c='rA45kKQWre',
                LastChanged__c=Datetime.newInstanceGmt(2019, 9, 10, 9, 9, 9),
                // A day from now is greater than the contact's
                // LastModifiedDate
                LastPushed__c=(Datetime.now() + 1)
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

    @isTest static void testConstructor() {
        Test.startTest();

        // This is a bit of a cheap test, meant to cover the no-argument
        // constructor and the fieldMappings getter.
        MailchimpSyncManager subject = new MailchimpSyncManager();
        System.assert(subject.fieldMappings != null);

        Test.stopTest();
    }

    @isTest static void testContactsToSync() {
        Test.startTest();

        Contact[] contacts = subject().contactsToSync(200);
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

    @isTest static void testContactsQueryLocator() {
        Test.startTest();

        String expectedQuery = 'SELECT Id,Email,FirstName,LastName,Drupal_ID__c,' +
            'Drupal_Username__c,MailchimpEmailHash__c,' +
            'Account.CY_contribution_revenue__c,' +
            'Account.CY_1_contribution_revenue__c,' +
            'Account.CY_2_contribution_revenue__c,' +
            'Account.CY_3_contribution_revenue__c,Account.Id,' +
            'Account.Membership_Expiration_Date__c,' +
            'Account.Membership_Level__c,' +
            'Account.Membership_Level_Number__c,' +
            'Account.Membership_level_qualification_amount__c,' +
            'Account.Recurring_donations_Annualized_value_new__c,' +
            'Account.SF_Record_Type__c,Active_sustainer_account__c,' +
            'MinnPost_com_user_account__c,Current_member__c,Lapsed_member__c,' +
            'Never_member__c,Is_partner_offer_eligible__c' +
            ' FROM Contact WHERE Id IN (' +
            '   SELECT Contact__c FROM MailchimpSyncStatus__c' +
            '    WHERE NeedsSync__c = TRUE' +
            ' )' +
            ' ORDER BY Email ASC';
        System.assertEquals(
            expectedQuery,
            subject().contactsQueryLocator().getQuery()
        );
        System.assertEquals(
            expectedQuery + ' LIMIT 10',
            subject().contactsQueryLocator(10).getQuery()
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
        System.assertEquals(2, batches.size());
        System.assertEquals('rA45kKQWre', batches[0].Name);

        Test.stopTest();
    }

    @isTest static void testUnfinishedBatchesLimit() {
        Test.startTest();

        Mailchimp_Batch_Operation__c[] batches = subject().unfinishedBatches(1);
        System.assertEquals(1, batches.size());
        System.assertEquals('rA45kKQWre', batches[0].Name);

        Test.stopTest();
    }

    @isTest static void testLastSyncCompletedAt() {
        Test.startTest();

        Datetime result = subject().lastSyncCompletedAt();
        Long delta = Datetime.now().getTime() -
            result.getTime();
        System.debug('testLastSyncCompletedAt: delta = ' + delta);
        System.assert(
            delta < maxDelta,
            'Expected: ≈ ' + Datetime.now() +
            ', Actual: ' + result
        );

        Test.stopTest();
    }

    @isTest static void testInProgressJobsCount() {
        Test.startTest();

        System.assertEquals(0, subject().inProgressJobsCount());

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

        Test.stopTest();
    }

    @isTest static void testUpdateBatchesError() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiErrorMock());
        Test.startTest();

        subject().updateBatches();
        Mailchimp_Batch_Operation__c batch =
            [SELECT Name, Status__c, Completed_At__c, Total_Operations__c
             FROM Mailchimp_Batch_Operation__c
             WHERE Name = 'rA45kKQWre' LIMIT 1];
        System.assertEquals('pending', batch.Status__c);
        System.assertEquals(null, batch.Completed_At__c);

        Test.stopTest();
    }

    @isTest static void testPullInterests() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        subject().pullInterests();

        Integer catCount = [SELECT COUNT() FROM InterestCategory__c];
        System.assertEquals(2, catCount);

        Integer count = [SELECT COUNT() FROM Interest__c];
        System.assertEquals(2, count);

        Test.stopTest();
    }

    @isTest static void testPullInterestsResponseError() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiErrorMock());
        Test.startTest();

        subject().pullInterests();
        Mailchimp_Sync_Error__c err =
            [SELECT Stage__c, Status_Code__c, Title__c, Detail__c
             FROM Mailchimp_Sync_Error__c LIMIT 1];
        System.assertEquals('1 - Fetch interests from Mailchimp', err.Stage__c);
        System.assertEquals('422', err.Status_Code__c);

        Test.stopTest();
    }

    @isTest static void testPullInterestsInvalidJSON() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiInvalidJSONMock());
        Test.startTest();

        subject().pullInterests();
        Mailchimp_Sync_Error__c err =
            [SELECT Stage__c, Status_Code__c, Title__c, Detail__c
             FROM Mailchimp_Sync_Error__c LIMIT 1];
        System.assertEquals('1 - Fetch interests from Mailchimp', err.Stage__c);
        System.assertEquals('System.JSONException while parsing Mailchimp interest categories response', err.Title__c);

        Test.stopTest();
    }

    @isTest static void testPullAll() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncManager.PullResult result = subject().pullAll(1000, 0, false);
        System.assertEquals(MailchimpSyncManager.PullResult.DONE, result);

        MailchimpSyncStatus__c status =
            [SELECT Email__c, LastChanged__c, LastPushed__c, NeedsSync__c
             FROM MailchimpSyncStatus__c
             WHERE Email__c = 'helen1604@example.com'
             LIMIT 1];
        System.assertEquals(true, status.NeedsSync__c);
        System.assertEquals(
            Datetime.newInstanceGmt(2019, 9, 17, 10, 55, 9),
            status.LastChanged__c
        );
        Long delta = (Datetime.now() - 1).getTime() -
            status.LastPushed__c.getTime();
        System.assert(
            delta < maxDelta,
            'Expected: ≈ ' + (Datetime.now() - 1) +
            ', Actual: ' + status.LastPushed__c
        );

        Test.stopTest();
    }

    @isTest static void testPullAllSinceLastSync() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock());
        Test.startTest();

        MailchimpSyncManager.PullResult result = subject().pullAll(1000, 0);
        System.assertEquals(MailchimpSyncManager.PullResult.DONE, result);

        MailchimpSyncStatus__c status =
            [SELECT Email__c, LastChanged__c, LastPushed__c, NeedsSync__c
             FROM MailchimpSyncStatus__c
             WHERE Email__c = 'helen1604@example.com'
             LIMIT 1];
        System.assertEquals(true, status.NeedsSync__c);
        System.assertEquals(
            Datetime.newInstanceGmt(2019, 9, 17, 10, 55, 9),
            status.LastChanged__c
        );
        Long delta = (Datetime.now() - 1).getTime() -
            status.LastPushed__c.getTime();
        System.assert(
            delta < maxDelta,
            'Expected: ≈ ' + (Datetime.now() - 1) +
            ', Actual: ' + status.LastPushed__c
        );

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

    @isTest static void testPushAllResponseError() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiErrorMock());
        Test.startTest();

        MailchimpSyncManager.Result result = subject().pushAll(new List<Contact>{});
        System.assert(result.isError());

        Test.stopTest();
    }

    @isTest static void testPushAllInvalidJSON() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiInvalidJSONMock());
        Test.startTest();

        MailchimpSyncManager.Result result = subject().pushAll(new List<Contact>{});
        System.assert(result.isError());

        Test.stopTest();
    }

    @isTest static void testPushAllContactParseError() {
        Test.setMock(HttpCalloutMock.class, new MailchimpApiMock(true));
        Test.startTest();

        MailchimpSyncManager.Result result = subject().pushAll(new List<Contact>{});
        System.assertEquals(1, result.contactErrors.size());
        
        Mailchimp_Sync_Error__c err =
            [SELECT Stage__c, Contact__c, Detail__c
             FROM Mailchimp_Sync_Error__c
             WHERE Contact__r.Email = 'joe.schmoe@example.com'];
        System.assertEquals('4 - Add/update contacts in Mailchimp', err.Stage__c);

        Test.stopTest();
    }
}
