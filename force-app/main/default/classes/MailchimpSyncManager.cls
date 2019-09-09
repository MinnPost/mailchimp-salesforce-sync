public with sharing class MailchimpSyncManager {
    static final String TAG_ACTIVE_SUSTAINER = 'Active sustainer';
    static final String TAG_CMS_USER = 'CMS user';
    static final String TAG_CURRENT_MEMBER = 'Current member';
    static final String TAG_LAPSED_MEMBER = 'Lapsed member';
    static final String TAG_NEVER_MEMBER = 'Never member';
    static final String TAG_PARTNER_OFFER_ELIGIBLE = 'Partner offer eligible';
    static final Map<String, String> TAG_FIELDS = new Map<String, String>{
        TAG_ACTIVE_SUSTAINER => 'Active_sustainer_account__c',
        TAG_CMS_USER => 'MinnPost_com_user_account__c',
        TAG_CURRENT_MEMBER => 'Current_member__c',
        TAG_LAPSED_MEMBER => 'Lapsed_member__c',
        TAG_NEVER_MEMBER => 'Never_member__c',
        TAG_PARTNER_OFFER_ELIGIBLE => 'Is_partner_offer_eligible__c'
    };
    static final String STAGE_BATCH_SUB_UNSUB = '1 - Add/update contacts in Mailchimp';
    static final String STAGE_BATCH_TAG = '2 - Add/update tags in Mailchimp';

    class BatchEmailError {
        public String email_address;
        public String error;
    }

    public class Result {
        public Integer totalCreated = 0;
        public Integer totalUpdated = 0;
        public Integer errorCount = 0;
        public Mailchimp_Sync_Error__c requestError;
        public Map<String, Mailchimp_Sync_Error__c> contactErrors { get; private set; }

        public Result() {
            this.contactErrors = new Map<String, Mailchimp_Sync_Error__c>();
        }

        public Boolean isError() {
            return (requestError != null);
        }
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
        insert syncError;
        return syncError;
    }

    private HttpResponse pushContactFields(List<Contact> contacts) {
        // Sync to Mailchimp using bulk-add endpoint
        // - what about deletes? Unlikely that a contact would ever be removed from Salesforce
        // - Need to ensure we don't re-subscribe anyone who's unsubscribed
        // - May need to use a batch request to avoid SF callout response size limits
        // - TODO: Need to handle duplicate e-mail addresses
        JSONGenerator body = JSON.createGenerator(false);
        body.writeStartObject();
        body.writeFieldName('members');
        body.writeStartArray();
        for (Contact c : contacts) {
            body.writeStartObject();
            body.writeStringField('email_address', c.Email);
            body.writeStringField('status_if_new', 'subscribed');
            body.writeFieldName('merge_fields');
            body.writeStartObject();
            body.writeStringField('SF_CONTACT', c.Id);
            body.writeStringField('SF_ACCOUNT', c.Account.Id);
            body.writeStringField('SFACCTTYPE', c.Account.SF_Record_Type__c);
            if (c.FirstName != null) {
                body.writeStringField('FNAME', c.FirstName);
            }
            if (c.LastName != null) {
                body.writeStringField('LNAME', c.LastName);
            }
            if (c.Account.Membership_Level_Number__c != null) {
                body.writeNumberField('MEMLEV_NUM', c.Account.Membership_Level_Number__c);
            }
            if (c.Account.Membership_Level__c != null) {
                body.writeStringField('MEMBER_LEV', c.Account.Membership_Level__c);
            }
            if (c.Account.Membership_level_qualification_amount__c != null) {
                body.writeNumberField('MEMLEV_AMT', c.Account.Membership_level_qualification_amount__c);
            }
            if (c.Account.Membership_Expiration_Date__c != null) {
                body.writeDateTimeField('MEMBER_EXP', c.Account.Membership_Expiration_Date__c);
            }
            if (c.Account.Recurring_donations_Annualized_value_new__c != null) {
                body.writeNumberField('RECURR_AMT', c.Account.Recurring_donations_Annualized_value_new__c);
            }
            if (c.Drupal_ID__c != null) {
                body.writeStringField('CMS_UID', c.Drupal_ID__c);
            }
            if (c.Drupal_Username__c != null) {
                body.writeStringField('CMS_USER', c.Drupal_Username__c);
            }
            body.writeEndObject();
            body.writeEndObject();
        }
        body.writeEndArray();
        body.writeBooleanField('update_existing', true);
        body.writeEndObject();

        MailchimpAPI mailchimp = new MailchimpAPI();
        return mailchimp.post(mailchimp.listEndpoint(), body.getAsString());
    }

    private Boolean parseContactFieldsResponse(Contact[] contacts, String respBody, Result result) {
        JSONParser parser = JSON.createParser(respBody);
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug(LoggingLevel.ERROR,
                'Error parsing Mailchimp response: expected ' + JSONToken.START_OBJECT +
                ', got ' + parser.getCurrentToken());
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_BATCH_SUB_UNSUB,
                Title__c='Error parsing Mailchimp response',
                Detail__c='expected ' + JSONToken.START_OBJECT + ', got ' + parser.getCurrentToken()
            );
            insert result.requestError;
            return false;
        }

        while (parser.nextValue() != null) {
            switch on parser.getCurrentName() {
                when 'total_created' {
                    result.totalCreated = parser.getIntegerValue();
                }
                when 'total_updated' {
                    result.totalUpdated = parser.getIntegerValue();
                }
                when 'error_count' {
                    result.errorCount = parser.getIntegerValue();
                }
                when 'errors' {
                    System.assert(parser.getCurrentToken() == JSONToken.START_ARRAY);
                    while (parser.nextToken() != JSONToken.END_ARRAY) {
                        BatchEmailError error =
                            (BatchEmailError)parser.readValueAsStrict(BatchEmailError.class);
                        parser.skipChildren();
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
                }
                when else {
                    if (parser.getCurrentToken() == JSONToken.START_OBJECT ||
                        parser.getCurrentToken() == JSONToken.START_ARRAY) {
                        parser.skipChildren();
                    }
                }
            }
        }

        return true;
    }

    private void writeTagField(JSONGenerator tagsBody, Contact c, String tag) {
        Boolean active = (Boolean)c.get(TAG_FIELDS.get(tag));
        if (active == null) {
            active = false;
        }

        tagsBody.writeStartObject();
        tagsBody.writeStringField('name', tag);
        tagsBody.writeStringField('status', active ? 'active' : 'inactive');
        tagsBody.writeEndObject();
    }

    private HttpResponse pushContactTags(List<Contact> contacts, Result result) {
        // Sync boolean fields as tags using batch endpoint
        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        JSONGenerator body = JSON.createGenerator(false);
        JSONGenerator tagsBody;
        MailchimpAPI mailchimp = new MailchimpAPI();

        body.writeStartObject();
        body.writeFieldName('operations');
        body.writeStartArray();
        for (Contact c : contacts) {
            if (result.contactErrors.containsKey(c.Email)) {
                continue;
            }

            tagsBody = JSON.createGenerator(false);
            tagsBody.writeStartObject();
            tagsBody.writeFieldName('tags');
            tagsBody.writeStartArray();
            this.writeTagField(tagsBody, c, TAG_ACTIVE_SUSTAINER);
            this.writeTagField(tagsBody, c, TAG_CMS_USER);
            this.writeTagField(tagsBody, c, TAG_CURRENT_MEMBER);
            this.writeTagField(tagsBody, c, TAG_LAPSED_MEMBER);
            this.writeTagField(tagsBody, c, TAG_NEVER_MEMBER);
            this.writeTagField(tagsBody, c, TAG_PARTNER_OFFER_ELIGIBLE);
            tagsBody.writeEndArray();
            tagsBody.writeEndObject();

            body.writeStartObject();
            body.writeStringField('method', 'POST');
            body.writeStringField('path', mailchimp.contactTagsEndpoint(c));
            body.writeStringField('body', tagsBody.getAsString());
            body.writeStringField('operation_id', c.Id);

            body.writeEndObject();
        }
        body.writeEndArray();
        body.writeEndObject();

        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        return mailchimp.post('batches', body.getAsString());
    }

    private Boolean parseBatchResponse(String respBody, Result result) {
        return this.parseBatchResponse(respBody, result, new Mailchimp_Batch_Operation__c());
    }

    private Boolean parseBatchResponse(String respBody, Result result, Mailchimp_Batch_Operation__c batch) {
        JSONParser parser = JSON.createParser(respBody);
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug(LoggingLevel.ERROR,
                'Error parsing Mailchimp response: expected ' + JSONToken.START_OBJECT +
                ', got ' + parser.getCurrentToken()
            );
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_BATCH_TAG,
                Title__c='Error parsing Mailchimp response',
                Detail__c='expected ' + JSONToken.START_OBJECT + ', got ' + parser.getCurrentToken()
            );
            insert result.requestError;
            return false;
        }

        while (parser.nextValue() != null) {
            switch on parser.getCurrentName() {
                when 'id' {
                    batch.Name = parser.getText();
                }
                when 'status' {
                    batch.Status__c = parser.getText();
                }
                when 'submitted_at' {
                    if (parser.getText() != '') {
                        batch.Submitted_At__c = parser.getDateTimeValue();
                    }
                }
                when 'completed_at' {
                    if (parser.getText() != '') {
                        batch.Completed_At__c = parser.getDateTimeValue();
                    }
                }
                when 'total_operations' {
                    batch.Total_Operations__c = parser.getIntegerValue();
                }
                when 'finished_operations' {
                    batch.Finished_Operations__c = parser.getIntegerValue();
                }
                when 'errored_operations' {
                    batch.Errored_Operations__c = parser.getIntegerValue();
                }
                when 'response_body_url' {
                    batch.Response_Body_URL__c = parser.getText();
                }
                when else {
                    if (parser.getCurrentToken() == JSONToken.START_OBJECT ||
                        parser.getCurrentToken() == JSONToken.START_ARRAY) {
                        parser.skipChildren();
                    }
                }
            }
        }
        upsert batch;
        return true;
    }

    private List<MCSubscriber> parseMembersResponse(String respBody) {
        List<MCSubscriber> contacts = new List<MCSubscriber>();
        JSONParser parser = JSON.createParser(respBody);
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + parser.getCurrentToken());
            return contacts;
        }
        while (parser.nextValue() != null) {
            if (parser.getCurrentName() == 'members') {
                if (parser.getCurrentToken() != JSONToken.START_ARRAY) {
                    throw new TypeException('"members" in response was expected to be an array, got ' + parser.getCurrentToken());
                }
                while (parser.nextToken() == JSONToken.START_OBJECT) {
                    MCSubscriber member = (MCSubscriber)parser.readValueAs(MCSubscriber.class);
                    contacts.add(member);
                }
            }
        }
        return contacts;
    }

    public Result pushAll(List<Contact> contacts) {
        Result result = new Result();

        // Mailchimp API returns 200 even if some of the sub/unsub changes
        // produced errors.
        // I have observed it return a 400 Bad Request with an error response
        // if there are duplicate e-mails in the list.
        HttpResponse resp = this.pushContactFields(contacts);
        if (resp.getStatusCode() != 200) {
            result.requestError = this.reportError(STAGE_BATCH_SUB_UNSUB, resp.getBody());
            return result;
        }
        if (!this.parseContactFieldsResponse(contacts, resp.getBody(), result)) {
            return result;
        }

        HttpResponse tagsResp = this.pushContactTags(contacts, result);
        if (tagsResp.getStatusCode() != 200) {
            result.requestError = this.reportError(STAGE_BATCH_TAG, tagsResp.getBody());
            return result;
        }
        if (!this.parseBatchResponse(tagsResp.getBody(), result)) {
            return result;
        }

        return result;
    }

    public Result updateBatch(String batchId) {
        Mailchimp_Batch_Operation__c batch =
            [SELECT Id, Name, Status__c, Submitted_At__c, Completed_At__c,
                    Total_Operations__c, Finished_Operations__c, Errored_Operations__c,
                    Response_Body_URL__c
             FROM Mailchimp_Batch_Operation__c WHERE Name = :batchId LIMIT 1];
        Result result = new Result();

        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get('batches/' + batchId);
        if (resp.getStatusCode() != 200) {
            JSONParser parser = JSON.createParser(resp.getBody());
            MailchimpErrorResponse error =
                (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
            result.requestError = new Mailchimp_Sync_Error__c(
                Stage__c=STAGE_BATCH_TAG,
                Status_Code__c=String.valueOf(error.status),
                Title__c=error.title,
                Detail__c=error.detail
            );
            return result;
        }

        if (!this.parseBatchResponse(resp.getBody(), result, batch)) {
            return result;
        }

        return result;
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

    public List<MailchimpAPI.InterestCategory> pullInterests() {
        List<MailchimpAPI.InterestCategory> interestCategories = new List<MailchimpAPI.InterestCategory>();
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get(mailchimp.interestCategoriesEndpoint());
        if (resp.getStatusCode() != 200) {
            JSONParser parser = JSON.createParser(resp.getBody());
            MailchimpErrorResponse error =
                (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
            System.debug(LoggingLevel.ERROR, error);
            return interestCategories;
        }

        JSONParser parser = JSON.createParser(resp.getBody());
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + parser.getCurrentToken());
            return interestCategories;
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

        return interestCategories;
    }

    public MCSubscriber[] pullAll(Integer count, Integer offset) {
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get(
            mailchimp.membersEndpoint() +
            '?fields=total_items,members.id,members.email_address,members.status,members.member_rating,members.last_changed,members.merge_fields,members.interests' +
            '&count=' + count + '&offset=' + offset
        );
        return this.parseMembersResponse(resp.getBody());
    }
}
