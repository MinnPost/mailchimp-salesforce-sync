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

    class BatchEmailError {
        public String email_address;
        public String error;
    }

    private Http connection;

    private String listEndpoint() {
        return 'lists/3528e74526';
    }

    private String contactTagsEndpoint(Contact c) {
        Blob input = Blob.valueOf(c.Email.toLowerCase());
        Blob emailDigest = Crypto.generateDigest('MD5', input);
        String subscriberHash = EncodingUtil.convertToHex(emailDigest);
        return this.listEndpoint() + '/members/' + subscriberHash + '/tags';
    }

    private HttpResponse postToMailchimp(String endpoint, String body) {
        if (this.connection == null) {
            this.connection = new Http();
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setBody(body);
        req.setTimeout(120000);

        return this.connection.send(req);
    }

    private void reportError(String stage, String respBody) {
        JSONParser parser = JSON.createParser(respBody);
        MailchimpErrorResponse error =
            (MailchimpErrorResponse)parser.readValueAsStrict(MailchimpErrorResponse.class);
        System.debug(LoggingLevel.ERROR,
            'Error in ' + stage + '. ' +
            error.status + ' ' + error.title + ': ' + error.detail);
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
            if (c.FirstName != null) {
                body.writeStringField('FNAME', c.FirstName);
            }
            if (c.LastName != null) {
                body.writeStringField('LNAME', c.LastName);
            }
            body.writeEndObject();
            body.writeEndObject();
        }
        body.writeEndArray();
        body.writeBooleanField('update_existing', true);
        body.writeEndObject();

        return this.postToMailchimp(this.listEndpoint(), body.getAsString());
    }

    private Boolean parseContactFieldsErrors(List<Contact> contacts, String respBody, Map<String, String> contactErrors) {
        JSONParser fieldErrParser = JSON.createParser(respBody);
        if (fieldErrParser.nextToken() != JSONToken.START_OBJECT) {
            System.debug(LoggingLevel.ERROR,
                'Error parsing Mailchimp response: expected ' + JSONToken.START_OBJECT +
                ', got ' + fieldErrParser.getCurrentToken());
            return false;
        }

        Integer totalCreated = 0, totalUpdated = 0, errorCount = 0;
        while (fieldErrParser.nextValue() != null) {
            switch on fieldErrParser.getCurrentName() {
                when 'total_created' {
                    totalCreated = fieldErrParser.getIntegerValue();
                }
                when 'total_updated' {
                    totalUpdated = fieldErrParser.getIntegerValue();
                }
                when 'error_count' {
                    errorCount = fieldErrParser.getIntegerValue();
                }
                when 'errors' {
                    System.assert(fieldErrParser.getCurrentToken() == JSONToken.START_ARRAY);
                    while (fieldErrParser.nextToken() != JSONToken.END_ARRAY) {
                        BatchEmailError error =
                            (BatchEmailError)fieldErrParser.readValueAsStrict(BatchEmailError.class);
                        fieldErrParser.skipChildren();
                        contactErrors.put(error.email_address, error.error);
                    }
                }
                when else {
                    if (fieldErrParser.getCurrentToken() == JSONToken.START_OBJECT ||
                        fieldErrParser.getCurrentToken() == JSONToken.START_ARRAY) {
                        fieldErrParser.skipChildren();
                    }
                }
            }
        }
        System.debug(totalCreated + ' contacts added, ' + totalUpdated + ' updated, ' + errorCount + ' errors');

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

    private HttpResponse pushContactTags(List<Contact> contacts, Map<String, String> contactErrors) {
        // Sync boolean fields as tags using batch endpoint
        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        JSONGenerator body = JSON.createGenerator(false);
        JSONGenerator tagsBody;
        body.writeStartObject();
        body.writeFieldName('operations');
        body.writeStartArray();
        for (Contact c : contacts) {
            if (contactErrors.containsKey(c.Email)) {
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
            body.writeStringField('path', this.contactTagsEndpoint(c));
            body.writeStringField('body', tagsBody.getAsString());
            body.writeStringField('operation_id', c.Id);

            body.writeEndObject();
        }
        body.writeEndArray();
        body.writeEndObject();

        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        // TODO: Record batch ID to check/match up w/webhook later
        return this.postToMailchimp('batches', body.getAsString());
    }

    public Boolean pushAll(List<Contact> contacts, Map<String, String> contactErrors) {
        // Mailchimp API returns 200 even if some of the sub/unsub changes
        // produced errors.
        // I have observed it return a 400 Bad Request with an error response
        // if there are duplicate e-mails in the list.
        HttpResponse resp = this.pushContactFields(contacts);
        if (resp.getStatusCode() != 200) {
            // TODO: Log errors to expose to user after redirect
            this.reportError('Mailchimp batch sub/unsub call', resp.getBody());
            return false;
        }
        if (!this.parseContactFieldsErrors(contacts, resp.getBody(), contactErrors)) {
            return false;
        }

        // TODO: Record batch ID to check/match up w/webhook later
        HttpResponse tagsResp = this.pushContactTags(contacts, contactErrors);
        if (tagsResp.getStatusCode() != 200) {
            // TODO: Log errors to expose to user after redirect
            this.reportError('Mailchimp batch tags call', tagsResp.getBody());
            return false;
        }

        // TODO: Log errors to expose to user after redirect
        // Maybe a lookup relationship on Contact to an error log table?
        // | ContactID | SyncDate | SyncStage | StatusCode | ErrorMessage | ...

        return true;
    }
}
