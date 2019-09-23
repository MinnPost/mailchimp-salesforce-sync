public class MailchimpAPI {
    static final String FIELD_CONTACT_ID = 'SF_CONTACT';
    static final String FIELD_ACCOUNT_ID = 'SF_ACCOUNT';
    static final String FIELD_ACCOUNT_TYPE = 'SFACCTTYPE';
    static final String FIELD_FIRST_NAME = 'FNAME';
    static final String FIELD_LAST_NAME = 'LNAME';
    static final String FIELD_MEMBER_LEVEL = 'MEMBER_LEV';
    static final String FIELD_MEMBER_LEVEL_NUMBER = 'MEMLEV_NUM';
    static final String FIELD_MEMBER_LEVEL_QUALIFICATION_AMOUNT = 'MEMLEV_AMT';
    static final String FIELD_MEMBER_EXPIRATION_DATE = 'MEMBER_EXP';
    static final String FIELD_RECURRING_DONATIONS_AMOUNT = 'RECURR_AMT';
    static final String FIELD_CY_3_CONTRIBUTIONS = 'CY_3_CONTR';
    static final String FIELD_CY_2_CONTRIBUTIONS = 'CY_2_CONTR';
    static final String FIELD_CY_1_CONTRIBUTIONS = 'CY_1_CONTR';
    static final String FIELD_CY_CONTRIBUTIONS = 'CY_CONTRIB';
    static final String FIELD_CMS_USER_ID = 'CMS_UID';
    static final String FIELD_CMS_USERNAME = 'CMS_USER';
    static final Map<String, String> CONTACT_FIELDS = new Map<String, String>{
        FIELD_CONTACT_ID => 'Id',
        FIELD_FIRST_NAME => 'FirstName',
        FIELD_LAST_NAME => 'LastName',
        FIELD_CMS_USER_ID => 'Drupal_ID__c',
        FIELD_CMS_USERNAME => 'Drupal_Username__c'
    };
    static final Map<String, String> ACCOUNT_FIELDS = new Map<String, String>{
        FIELD_ACCOUNT_ID => 'Id',
        FIELD_ACCOUNT_TYPE => 'SF_Record_Type__c',
        FIELD_MEMBER_LEVEL_NUMBER => 'Membership_Level_Number__c',
        FIELD_MEMBER_LEVEL => 'Membership_Level__c',
        FIELD_MEMBER_LEVEL_QUALIFICATION_AMOUNT => 'Membership_level_qualification_amount__c',
        FIELD_MEMBER_EXPIRATION_DATE => 'Membership_Expiration_Date__c',
        FIELD_RECURRING_DONATIONS_AMOUNT => 'Recurring_donations_Annualized_value_new__c',
        FIELD_CY_3_CONTRIBUTIONS => 'CY_3_contribution_revenue__c',
        FIELD_CY_2_CONTRIBUTIONS => 'CY_2_contribution_revenue__c',
        FIELD_CY_1_CONTRIBUTIONS => 'CY_1_contribution_revenue__c',
        FIELD_CY_CONTRIBUTIONS => 'CY_contribution_revenue__c'
    };

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

    static Object getField(Contact c, String field) {
        if (ACCOUNT_FIELDS.containsKey(field)) {
            return c.Account.get(ACCOUNT_FIELDS.get(field));
        }
        return c.get(CONTACT_FIELDS.get(field));
    }

    static Boolean getTagValue(Contact c, String tag) {
        return (Boolean)c.get(TAG_FIELDS.get(tag));
    }

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

    public class InterestsResponse {
        public Interest[] interests;
        public Integer total_items;
    }

    public class Interest {
        public String id;
        public String name;
        public Long subscriber_count;
        public Integer display_order;
    }

    public class InterestCategoriesResponse {
        public InterestCategory[] categories;
        public Integer total_items;
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
        String subscriberHash = c.MailchimpEmailHash__c;
        if (subscriberHash == null) {
            Blob input = Blob.valueOf(c.Email.toLowerCase());
            Blob emailDigest = Crypto.generateDigest('MD5', input);
            subscriberHash = EncodingUtil.convertToHex(emailDigest);
        }
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

    private void writeContactStringField(JSONGenerator body, Contact c, String field) {
        String value = (String)MailchimpAPI.getField(c, field);
        if (value == null) return;

        body.writeStringField(field, value);
    }

    private void writeContactNumberField(JSONGenerator body, Contact c, String field) {
        Decimal value = (Decimal)MailchimpAPI.getField(c, field);
        if (value == null) return;

        body.writeNumberField(field, value);
    }

    private void writeContactDatetimeField(JSONGenerator body, Contact c, String field) {
        Datetime value = (Datetime)MailchimpAPI.getField(c, field);
        if (value == null) return;

        body.writeDateTimeField(field, value);
    }

    public HttpResponse pushContactFields(List<Contact> contacts) {
        // Sync to Mailchimp using bulk-add endpoint
        // - what about deletes? Unlikely that a contact would ever be removed
        //   from Salesforce -- but contacts can be merged
        // - Need to ensure we don't re-subscribe anyone who's unsubscribed -
        //   this should be covered by only setting 'status_if_new'
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
            this.writeContactNumberField(body, c, FIELD_MEMBER_LEVEL_NUMBER);
            this.writeContactStringField(body, c, FIELD_MEMBER_LEVEL);
            this.writeContactNumberField(body, c, FIELD_MEMBER_LEVEL_QUALIFICATION_AMOUNT);
            this.writeContactDatetimeField(body, c, FIELD_MEMBER_EXPIRATION_DATE);
            this.writeContactNumberField(body, c, FIELD_RECURRING_DONATIONS_AMOUNT);
            this.writeContactNumberField(body, c, FIELD_CY_3_CONTRIBUTIONS);
            this.writeContactNumberField(body, c, FIELD_CY_2_CONTRIBUTIONS);
            this.writeContactNumberField(body, c, FIELD_CY_1_CONTRIBUTIONS);
            this.writeContactNumberField(body, c, FIELD_CY_CONTRIBUTIONS);
            this.writeContactStringField(body, c, FIELD_CMS_USER_ID);
            this.writeContactStringField(body, c, FIELD_CMS_USERNAME);
            body.writeEndObject();
            body.writeEndObject();
        }
        body.writeEndArray();
        body.writeBooleanField('update_existing', true);
        body.writeEndObject();

        return this.post(this.listEndpoint(), body.getAsString());
    }

    private void writeTagField(JSONGenerator tagsBody, Contact c, String tag) {
        Boolean active = MailchimpAPI.getTagValue(c, tag);
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

    public HttpResponse fetchInterestCategories() {
        return this.get(this.interestCategoriesEndpoint());
    }

    public HttpResponse fetchInterests(String categoryId) {
        return this.get(this.interestCategoriesEndpoint() + '/' + categoryId + '/interests');
    }

    public HttpResponse fetchMembers(Integer count, Integer offset) {
        return this.fetchMembers(count, offset, null);
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
            queryString += '&since_last_changed=' + changedSince.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSSZ');
        }
        return this.get(this.membersEndpoint() + queryString);
    }
}
