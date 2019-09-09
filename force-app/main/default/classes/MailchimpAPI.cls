public class MailchimpAPI {
    private Http connection;

    public class Interest {
        public String id;
        public String name;
        public Long subscriber_count;
        public Integer display_order;
    }

    public class InterestCategory {
        public String id;
        public String title;
        public String type;
        public Integer display_order;
        public List<Interest> interests;

        public InterestCategory() {
            this.interests = new List<Interest>();
        }
    }

    public String listEndpoint() {
        return 'lists/3528e74526';
    }

    public String membersEndpoint() {
        return this.listEndpoint() + '/members';
    }

    public String interestCategoriesEndpoint() {
        return this.listEndpoint() + '/interest-categories';
    }

    public String contactTagsEndpoint(Contact c) {
        Blob input = Blob.valueOf(c.Email.toLowerCase());
        Blob emailDigest = Crypto.generateDigest('MD5', input);
        String subscriberHash = EncodingUtil.convertToHex(emailDigest);
        return this.membersEndpoint() + '/' + subscriberHash + '/tags';
    }

    public HttpResponse get(String endpoint) {
        if (this.connection == null) {
            this.connection = new Http();
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setTimeout(30000);

        return this.connection.send(req);
    }

    public HttpResponse post(String endpoint, String body) {
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

    public HttpResponse pushContactFields(List<Contact> contacts) {
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

        return this.post(this.listEndpoint(), body.getAsString());
    }
}
