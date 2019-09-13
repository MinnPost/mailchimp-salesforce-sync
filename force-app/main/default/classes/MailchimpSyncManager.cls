public with sharing class MailchimpSyncManager {
    static final String STAGE_FETCH_MEMBERS = '1 - Fetch contacts from Mailchimp';
    static final String STAGE_BATCH_SUB_UNSUB = '2 - Add/update contacts in Mailchimp';
    static final String STAGE_BATCH_TAG = '3 - Add/update tags in Mailchimp';
    static final String STAGE_MARK_CONTACTS_SYNCED = '4 - Mark Salesforce contacts as synced';
    static final String STAGE_UPDATE_BATCH_STATUS = '5 - Check Mailchimp batch job status';

    class ContactFieldsResponse {
        public Integer total_created;
        public Integer total_updated;
        public Integer error_count;
        public BatchEmailError[] errors;

        public ContactFieldsResponse() {
            this.errors = new List<BatchEmailError>();
        }
    }

    class BatchEmailError {
        public String email_address;
        public String error;
    }

    class BatchResponse {
        public String id;
        public String status;
        public Datetime submitted_at;
        public String completed_at;
        public Integer total_operations;
        public Integer finished_operations;
        public Integer errored_operations;
        public String response_body_url;
    }

    class MembersResponse {
        public Integer total_items;
        public MailchimpAPI.Subscriber[] members;
    }

    class MembersResult {
        public MailchimpAPI.Subscriber[] members;
        public Mailchimp_Sync_Error__c requestError;
        public Integer totalItems = 0;

        public MembersResult() {
            this.members = new List<MailchimpAPI.Subscriber>();
        }

        public Boolean isError() {
            return (requestError != null);
        }
    }

    public class Result {
        public Integer totalCreated = 0;
        public Integer totalUpdated = 0;
        public Integer errorCount = 0;
        public Mailchimp_Sync_Error__c requestError;
        public Map<String, Mailchimp_Sync_Error__c> contactErrors { get; private set; }
        public Long totalItems = 0;

        public Result() {
            this.contactErrors = new Map<String, Mailchimp_Sync_Error__c>();
        }

        public Boolean isError() {
            return (requestError != null);
        }
    }

    public String contactsQuery(Integer lim) {
        // TODO: annual donation history
        String query = 'SELECT ID, Email, FirstName, LastName, Drupal_ID__c, Drupal_Username__c,' +
            ' Account.ID, Account.SF_Record_Type__c,' +
            ' Account.Membership_Level_Number__c, Account.Membership_Level__c,' +
            ' Account.Membership_level_qualification_amount__c, Account.Membership_Expiration_Date__c,' +
            ' Account.Recurring_donations_Annualized_value_new__c,' +
            ' Active_sustainer_account__c, Is_partner_offer_eligible__c,' +
            ' Current_member__c, Lapsed_member__c, Never_member__c,' +
            ' MinnPost_com_user_account__c' +
            ' FROM Contact' +
            ' WHERE Email != null AND MailchimpNeedsSync__c = TRUE' +
            ' ORDER BY Email ASC';
        if (lim != null) {
            query += ' LIMIT ' + lim;
        }
        return query;
    }

    public String contactsCountQuery() {
        return this.contactsCountQuery(null);
    }

    public String contactsCountQuery(Integer lim) {
        String query = 'SELECT COUNT() FROM Contact' +
            ' WHERE (Email != null AND MailchimpNeedsSync__c = TRUE)' +
            ' OR MailchimpBatchID__c != null';
        if (lim != null) {
            query += ' LIMIT ' + lim;
        }
        return query;
    }

    public Integer contactsCount() {
        return Database.countQuery(this.contactsCountQuery());
    }

    public Database.QueryLocator contactsQueryLocator() {
        return this.contactsQueryLocator(null);
    }

    public Database.QueryLocator contactsQueryLocator(Integer lim) {
        return Database.getQueryLocator(this.contactsQuery(lim));
    }

    public Contact[] contactsToSync(Integer lim) {
        return Database.query(this.contactsQuery(lim));
    }

    public Mailchimp_Batch_Operation__c[] unfinishedBatches() {
        return this.unfinishedBatches(null);
    }

    public Mailchimp_Batch_Operation__c[] unfinishedBatches(Integer lim) {
        String query = 'SELECT Id, Name, Status__c, Submitted_At__c, Completed_At__c,' +
            ' Total_Operations__c, Finished_Operations__c, Errored_Operations__c,' +
            ' Response_Body_URL__c' +
            ' FROM Mailchimp_Batch_Operation__c WHERE Status__c <> \'finished\'' +
            ' ORDER BY Submitted_At__C DESC';
        if (lim != null) {
            query += ' LIMIT ' + lim;
        }
        return Database.query(query);
    }

    public Datetime lastSyncCompletedAt() {
        AggregateResult[] maxResults =
            [SELECT MAX(MailchimpLastSyncedAt__c) mostRecentSyncedAt FROM Contact];
        return (Datetime)maxResults[0].get('mostRecentSyncedAt');
    }

    public Integer inProgressJobsCount() {
        return [SELECT COUNT() FROM AsyncApexJob
                WHERE Status IN ('Preparing', 'Processing')
                AND ApexClassID IN (
                    SELECT Id FROM ApexClass WHERE Name IN (
                        'MailchimpPullInterestsJob',
                        'MailchimpPullJob',
                        'MailchimpSyncJob'
                    )
                )];
    }

    private Mailchimp_Sync_Error__c reportError(String stage, String respBody) {
        JSONParser parser = JSON.createParser(respBody);
        MailchimpErrorResponse error =
            (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
        System.debug(LoggingLevel.ERROR,
            'Error in ' + stage + '. ' +
            error.status + ' ' + error.title + ': ' + error.detail);
        Mailchimp_Sync_Error__c syncError = new Mailchimp_Sync_Error__c(
            Stage__c=stage,
            Status_Code__c=String.valueOf(error.status),
            Title__c=error.title,
            Detail__c=error.detail
        );
        return syncError;
    }

    private void parseContactFieldsResponse(Contact[] contacts, String respBody, Result result) {
        JSONParser parser = JSON.createParser(respBody);
        try {
            ContactFieldsResponse response = (ContactFieldsResponse)parser.readValueAs(ContactFieldsResponse.class);
            result.totalCreated = response.total_created;
            result.totalUpdated = response.total_updated;
            result.errorCount = response.error_count;
            if (response.errors == null) {
                return;
            }
            for (BatchEmailError error : response.errors) {
                String email = error.email_address;
                Id cId = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1].Id;
                result.contactErrors.put(
                    email,
                    new Mailchimp_Sync_Error__c(
                        Stage__c=STAGE_BATCH_SUB_UNSUB,
                        Contact__c=cId,
                        Detail__c=error.error
                    )
                );
            }
        } catch (JSONException e) {
            System.debug(LoggingLevel.ERROR, e);
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_BATCH_SUB_UNSUB,
                Title__c=e.getTypeName() + ' while parsing Mailchimp response',
                Detail__c=e.getMessage()
            );
        }
    }

    private Mailchimp_Batch_Operation__c parseBatchResponse(String respBody, Result result) {
        Mailchimp_Batch_Operation__c batch = new Mailchimp_Batch_Operation__c();
        this.parseBatchResponse(respBody, result, batch);
        if (result.isError()) {
            return null;
        }
        insert batch;
        return batch;
    }

    private void parseBatchResponse(String respBody, Result result, Mailchimp_Batch_Operation__c batch) {
        JSONParser parser = JSON.createParser(respBody);
        try {
            BatchResponse response = (BatchResponse)parser.readValueAs(BatchResponse.class);
            batch.Name = response.id;
            batch.Status__c = response.status;
            batch.Submitted_At__c = response.submitted_at;
            if (response.completed_at != '') {
                Datetime completedAt = (Datetime)JSON.deserialize('"' + response.completed_at + '"', Datetime.class);
                batch.Completed_At__c = completedAt;
            }
            batch.Total_Operations__c = response.total_operations;
            batch.Finished_Operations__c = response.finished_operations;
            batch.Errored_Operations__c = response.errored_operations;
            batch.Response_Body_URL__c = response.response_body_url;
        } catch (JSONException e) {
            System.debug(LoggingLevel.ERROR, e);
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_BATCH_TAG,
                Title__c=e.getTypeName() + ' while parsing Mailchimp batch response',
                Detail__c=e.getMessage()
            );
        }
    }

    private MembersResult parseMembersResponse(String respBody) {
        MembersResult result = new MembersResult();
        JSONParser parser = JSON.createParser(respBody);
        try {
            MembersResponse response = (MembersResponse)parser.readValueAs(MembersResponse.class);
            result.members = response.members;
            result.totalItems = response.total_items;
        } catch (JSONException e) {
            System.debug(LoggingLevel.ERROR, e);
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_FETCH_MEMBERS,
                Title__c=e.getTypeName() + ' while parsing Mailchimp members response',
                Detail__c=e.getMessage()
            );
        }
        return result;
    }

    private void markContactsSynced(
        Contact[] contacts,
        Map<String, Mailchimp_Sync_Error__c> contactErrors,
        String tagBatchID
    ) {
        DateTime lastSyncedAt = DateTime.now();

        // Mark contacts as synced
        // TODO: I've observed this fail because of a Flow Trigger blowing over
        // the Apex CPU time limit. Need to figure out what to do about that.
        for (Contact c : contacts) {
            if (contactErrors.containsKey(c.Email)) continue;
            c.MailchimpLastSyncedAt__c = lastSyncedAt;
            c.MailchimpBatchID__c = tagBatchID;
        }
        Database.SaveResult[] results = Database.update(contacts);
        for (Database.SaveResult saveResult : results) {
            if (saveResult.isSuccess()) continue;
            System.debug('Error(s) updating timestamp on synced records.');
            for (Database.Error err : saveResult.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
            }
        }
    }

    public Result pushAll(Contact[] contacts) {
        Result result = new Result();

        // Mailchimp API returns 200 even if some of the sub/unsub changes
        // produced errors.
        // I have observed it return a 400 Bad Request with an error response
        // if there are duplicate e-mails in the list.
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse pushFieldsResp = mailchimp.pushContactFields(contacts);
        if (pushFieldsResp.getStatusCode() != 200) {
            result.requestError = this.reportError(STAGE_BATCH_SUB_UNSUB, pushFieldsResp.getBody());
            insert result.requestError;
            return result;
        }
        this.parseContactFieldsResponse(contacts, pushFieldsResp.getBody(), result);
        if (result.isError()) {
            insert result.requestError;
            return result;
        }

        HttpResponse tagsResp = mailchimp.pushContactTags(contacts, result.contactErrors.keySet());
        if (tagsResp.getStatusCode() != 200) {
            result.requestError = this.reportError(STAGE_BATCH_TAG, tagsResp.getBody());
            insert result.requestError;
            return result;
        }
        Mailchimp_Batch_Operation__c batch = this.parseBatchResponse(tagsResp.getBody(), result);
        if (result.isError()) {
            insert result.requestError;
            return result;
        }

        insert result.contactErrors.values();
        this.markContactsSynced(contacts, result.contactErrors, batch.Name);
        return result;
    }

    public void updateBatches() {
        Mailchimp_Batch_Operation__c[] batches = this.unfinishedBatches();

        Mailchimp_Sync_Error__c[] errors = new List<Mailchimp_Sync_Error__c>();
        Mailchimp_Batch_Operation__c[] updated = new List<Mailchimp_Batch_Operation__c>();
        for (Mailchimp_Batch_Operation__c batch : batches) {
            Result result = this.updateBatch(batch);
            if (result.isError()) {
                errors.add(result.requestError);
                continue;
            }
            updated.add(batch);
        }
        insert errors;
        update updated;
        String[] batchIDsForContactUpdate = new List<String>();
        for (Mailchimp_Batch_Operation__c batch : updated) {
            if (batch.Status__c == 'finished') {
                batchIDsForContactUpdate.add(batch.Name);
            }
        }
        MailchimpSyncManager.updateContactsInBatches(batchIDsForContactUpdate);
    }

    public void updateBatch(String batchId) {
        Mailchimp_Batch_Operation__c batch =
            [SELECT Id, Name, Status__c, Submitted_At__c, Completed_At__c,
                    Total_Operations__c, Finished_Operations__c, Errored_Operations__c,
                    Response_Body_URL__c
             FROM Mailchimp_Batch_Operation__c WHERE Name = :batchId LIMIT 1];
        Result result = this.updateBatch(batch);
        if (result.isError()) {
            insert result.requestError;
        }
    }

    public Result updateBatch(Mailchimp_Batch_Operation__c batch) {
        Result result = new Result();

        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get('batches/' + batch.Name);
        if (resp.getStatusCode() != 200) {
            JSONParser parser = JSON.createParser(resp.getBody());
            MailchimpErrorResponse error =
                (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_UPDATE_BATCH_STATUS,
                Status_Code__c=String.valueOf(error.status),
                Title__c=error.title,
                Detail__c=error.detail
            );
            return result;
        }

        this.parseBatchResponse(resp.getBody(), result, batch);
        return result;
    }

    @future
    public static void updateContactsInBatches(String[] batchIDs) {
        Datetime lastSyncedAt = Datetime.now();
        System.debug('Begin updating contacts for finished batches: ' + batchIDs);
        for (Contact[] contacts : [SELECT Id, MailchimpBatchID__c, MailchimpLastSyncedAt__c FROM Contact WHERE MailchimpBatchID__c IN :batchIDs]) {
            for (Contact c : contacts) {
                c.MailchimpLastSyncedAt__c = lastSyncedAt;
                c.MailchimpBatchId__c = null;
            }
            update contacts;
        }
        System.debug('End updating contacts for finished batches: ' + batchIDs);
    }

    public List<MailchimpAPI.Interest> pullInterestsInCategory(String categoryId) {
        List<MailchimpAPI.Interest> interests = new List<MailchimpAPI.Interest>();
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get(mailchimp.interestCategoriesEndpoint() + '/' + categoryId + '/interests');
        if (resp.getStatusCode() != 200) {
            JSONParser parser = JSON.createParser(resp.getBody());
            MailchimpErrorResponse error =
                (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
            System.debug(LoggingLevel.ERROR, error);
            return interests;
        }

        JSONParser parser = JSON.createParser(resp.getBody());
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + parser.getCurrentToken());
            return interests;
        }
        while (parser.nextValue() != null) {
            switch on parser.getCurrentName() {
                when 'interests' {
                    while (parser.nextToken() != JSONToken.END_ARRAY) {
                        MailchimpAPI.Interest interest =
                            (MailchimpAPI.Interest)parser.readValueAs(MailchimpAPI.Interest.class);
                        interests.add(interest);
                    }
                }
                when else {
                    if (parser.getCurrentToken() == JSONToken.START_OBJECT ||
                        parser.getCurrentToken() == JSONToken.START_ARRAY) {
                        parser.skipChildren();
                    }
                }
            }
        }

        return interests;
    }

    private void upsertInterests(MailchimpAPI.InterestCategory[] categories) {
        for (MailchimpAPI.InterestCategory c : categories) {
            InterestCategory__c category = new InterestCategory__c(
                CategoryID__c=c.id,
                Name=c.title,
                Type__c=c.type,
                DisplayOrder__c=c.display_order
            );
            Database.upsert(category, InterestCategory__c.Fields.CategoryID__c);

            Interest__c[] interests = new List<Interest__c>();
            for (MailchimpAPI.Interest i : c.interests) {
                Interest__c interest = new Interest__c(
                    InterestID__c=i.id,
                    Name=i.name,
                    SubscriberCount__c=i.subscriber_count,
                    DisplayOrder__c=i.display_order,
                    InterestCategory__c=category.Id
                );
                interests.add(interest);
            }

            Database.UpsertResult[] results = Database.upsert(interests, Interest__c.Fields.InterestID__c, false);
            for (Database.UpsertResult result : results) {
                if (result.isSuccess()) continue;

                System.debug('Error(s) creating/updating interest.');
                for (Database.Error err : result.getErrors()) {
                    System.debug(err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
    }

    public void pullInterests() {
        List<MailchimpAPI.InterestCategory> interestCategories = new List<MailchimpAPI.InterestCategory>();
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get(mailchimp.interestCategoriesEndpoint());
        if (resp.getStatusCode() != 200) {
            JSONParser parser = JSON.createParser(resp.getBody());
            MailchimpErrorResponse error =
                (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
            System.debug(LoggingLevel.ERROR, error);
            return;
        }

        JSONParser parser = JSON.createParser(resp.getBody());
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + parser.getCurrentToken());
            return;
        }
        while (parser.nextValue() != null) {
            switch on parser.getCurrentName() {
                when 'categories' {
                    while (parser.nextToken() != JSONToken.END_ARRAY) {
                        MailchimpAPI.InterestCategory category =
                            (MailchimpAPI.InterestCategory)parser.readValueAs(MailchimpAPI.InterestCategory.class);
                        category.interests = this.pullInterestsInCategory(category.id);
                        interestCategories.add(category);
                    }
                }
                when else {
                    if (parser.getCurrentToken() == JSONToken.START_OBJECT ||
                        parser.getCurrentToken() == JSONToken.START_ARRAY) {
                        parser.skipChildren();
                    }
                }
            }
        }

        this.upsertInterests(interestCategories);
    }

    private Boolean shouldRetry(Database.UpsertResult result) {
        if (result.isSuccess() || !result.isCreated()) return false;

        for (Database.Error err : result.getErrors()) {
            if (err.getStatusCode() == StatusCode.REQUIRED_FIELD_MISSING &&
                err.getFields().contains('Last Name')) {
                return true;
            }
        }

        return false;
    }

    private void upsertContacts(MailchimpAPI.Subscriber[] members, Contact[] contacts, Result result) {
        // Try to upsert without first/last name, check for the appropriate error.
        // New records will come back with a result with isCreated() == TRUE,
        // and a REQUIRED_FIELD_MISSING error on LastName.
        Database.UpsertResult[] results = Database.upsert(contacts, Contact.Fields.Email, false);
        Contact[] contactsToInsert = new List<Contact>();
        for (Integer i = 0; i < results.size(); ++i) {
            Database.UpsertResult upsertResult = results[i];
            Contact c = contacts[i];
            MailchimpAPI.Subscriber member = members[i];

            if (upsertResult.isSuccess()) continue;
            if (this.shouldRetry(upsertResult)) {
                String firstName = member.merge_fields.get('FNAME');
                if (firstName == null || firstName == '') {
                    firstName = 'Subscriber';
                }
                String lastName = member.merge_fields.get('LNAME');
                if (lastName == null || lastName == '') {
                    lastName = 'Subscriber';
                }

                c.FirstName = firstName;
                c.LastName = lastName;
                contactsToInsert.add(c);
                continue;
            }

            System.debug('Error(s) updating contact.');
            String email = c.Email;
            ID cId = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1].Id;
            for (Database.Error err : upsertResult.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
                result.contactErrors.put(
                    email,
                    new Mailchimp_Sync_Error__c(
                        Stage__c=STAGE_FETCH_MEMBERS,
                        Contact__c=cId,
                        Title__c='Error while updating contact',
                        Detail__c=err.getMessage()
                    )
                );
            }
        }

        Database.SaveResult[] insertResults = Database.insert(contactsToInsert, false);
        for (Integer i = 0; i < insertResults.size(); ++i) {
            Database.SaveResult insertResult = insertResults[i];
            Contact c = contactsToInsert[i];
            if (insertResult.isSuccess()) continue;

            System.debug('Error(s) creating contact.');
            for (Database.Error err : insertResult.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
                result.contactErrors.put(
                    c.Email,
                    new Mailchimp_Sync_Error__c(
                        Stage__c=STAGE_FETCH_MEMBERS,
                        Title__c='Error while creating contact ' + c.Email,
                        Detail__c=err.getMessage()
                    )
                );
            }
        }
    }

    public Contact[] collectContacts(MailchimpAPI.Subscriber[] members) {
        Contact[] contacts = new List<Contact>();

        for (MailchimpAPI.Subscriber member : members) {
            Contact c = new Contact(
                Email=member.email_address,
                MailchimpEmailHash__c=member.ID,
                MailchimpMemberRating__c=member.member_rating,
                MailchimpLastChanged__c=member.last_changed
            );
            contacts.add(c);
        }

        return contacts;
    }

    public MailchimpSubscription__c[] collectSubscriptions(
        MailchimpAPI.Subscriber[] members,
        Set<String> contactErrors
    ) {
        MailchimpSubscription__c[] subscriptions = new List<MailchimpSubscription__c>();

        for (MailchimpAPI.Subscriber member : members) {
            if (contactErrors.contains(member.email_address)) continue;

            // Create reference versions of the contact we can use to update subscriptions
            Contact contactRef = new Contact(
                MailchimpEmailHash__c=member.ID
            );

            for (String interestID : member.interests.keySet()) {
                Interest__c interestRef = new Interest__c(InterestID__c=interestID);
                MailchimpSubscription__c sub = new MailchimpSubscription__c(
                    Name=member.email_address + ' ' + interestID,
                    SubscriptionKey__c=member.ID + '-' + interestID,
                    Contact__r=contactRef,
                    Interest__r=interestRef,
                    Subscribed__c=member.interests.get(interestID)
                );
                subscriptions.add(sub);
            }
        }

        return subscriptions;
    }

    public void pullAll(Integer count) {
        this.pullAll(count, 0);
    }

    public Result pullAll(Integer count, Integer offset) {
        return this.pullAll(count, offset, true);
    }

    public Result pullAll(Integer count, Integer offset, Boolean sinceLastChanged) {
        Result result = new Result();

        MailchimpAPI mailchimp = new MailchimpAPI();
        Datetime mostRecentSyncedAt = null;
        if (sinceLastChanged) {
            mostRecentSyncedAt = this.lastSyncCompletedAt();
        }
        HttpResponse resp = mailchimp.fetchMembers(count, offset, mostRecentSyncedAt);
        MembersResult memResult = this.parseMembersResponse(resp.getBody());
        if (memResult.isError()) {
            insert memResult.requestError;
            result.requestError = memResult.requestError;
            return result;
        }
        result.totalItems = memResult.totalItems;

        Contact[] contacts = this.collectContacts(memResult.members);

        this.upsertContacts(memResult.members, contacts, result);

        MailchimpSubscription__c[] subscriptions = this.collectSubscriptions(
            memResult.members,
            result.contactErrors.keySet()
        );
        Database.upsert(subscriptions, MailchimpSubscription__c.Fields.SubscriptionKey__c);

        insert result.contactErrors.values();
        return result;
    }
}
