public class MailchimpAPI {
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

    static final String[] MEMBERS_FIELDS = new List<String>{
        'total_items',
        'members.id',
        'members.email_address',
        'members.status',
        'members.member_rating',
        'members.last_changed',
        'members.merge_fields',
        'members.interests'
    };

    private Http connection;

    public class Subscriber {
        public String ID;
        public String email_address;
        public String status;
        public Integer member_rating;
        public Datetime last_changed;
        public Map<String, String> merge_fields;
        public Map<String, Boolean> interests;

        public String getEmailAddress() {
            return this.email_address;
        }

        public Integer getMemberRating() {
            return this.member_rating;
        }
    }

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

    public HttpResponse pushContactTags(List<Contact> contacts, Set<String> contactErrors) {
        // Sync boolean fields as tags using batch endpoint
        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        JSONGenerator body = JSON.createGenerator(false);
        JSONGenerator tagsBody;

        body.writeStartObject();
        body.writeFieldName('operations');
        body.writeStartArray();
        for (Contact c : contacts) {
            if (contactErrors.contains(c.Email)) {
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
        return this.post('batches', body.getAsString());
    }

    public HttpResponse fetchMembers(Integer count, Integer offset, Datetime changedSince) {
        String fields = String.join(MEMBERS_FIELDS, ',');
        String queryString =
            '?fields=' + fields +
            '&sort_field=last_changed' +
            '&sort_dir=ASC' +
            '&count=' + count +
            '&offset=' + offset;
        if (changedSince != null) {
            queryString += '&since_last_changed=' + changedSince.format('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
        }
        return this.get(this.membersEndpoint() + queryString);
    }
}
