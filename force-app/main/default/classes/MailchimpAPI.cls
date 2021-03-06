// Copyright 2019 MinnPost <tech@minnpost.com>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

public class MailchimpAPI {
    public static final String PUSH_AS_MERGE_FIELD = '*|MERGE|* Field';
    public static final String PUSH_AS_TAG = 'Tag';

    static Object getField(Contact c, String field, String lookup) {
        if (lookup != 'Contact') {
            return c.getSObject(lookup).get(field);
        }
        return c.get(field);
    }

    static Boolean getTagValue(Contact c, String field, String lookup) {
        if (lookup != 'Contact') {
            return (Boolean)c.getSObject(lookup).get(field);
        }
        return (Boolean)c.get(field);
    }

    static final String[] MEMBERS_FIELDS = new List<String>{
        'total_items',
        'members.id',
        'members.email_address',
        'members.status',
        'members.member_rating',
        'members.last_changed',
        'members.merge_fields',
        'members.interests',
        'members.tags'
    };

    private Http connection {
        get {
            if (connection == null) {
                connection = new Http();
            }
            return connection;
        }
        set;
    }

    public class SubscriberTag {
        public Long id;
        public String name;
    }

    public class Subscriber {
        public String ID;
        public String email_address;
        public String status;
        public Integer member_rating;
        public Datetime last_changed;
        public Map<String, String> merge_fields;
        public Map<String, Boolean> interests;
        public SubscriberTag[] tags;

        public String getEmailAddress() {
            return this.email_address;
        }

        public Integer getMemberRating() {
            return this.member_rating;
        }

        public Object get(String attrName) {
            switch on attrName {
                when 'id' {
                    return this.ID;
                }
                when 'email_address' {
                    return this.email_address;
                }
                when 'status' {
                    return this.status;
                }
                when 'member_rating' {
                    return this.member_rating;
                }
                when 'last_changed' {
                    return this.last_changed;
                }
                when else {
                    throw new TypeException('Can\'t get unknown attribute ' + attrName);
                }
            }
        }

        public Boolean isTaggedWith(String tagName) {
            for (SubscriberTag tag : tags) {
                if (tagName == tag.name) { return true; }
            }
            return false;
        }
    }

    public class ListsResponse {
        public ListResponse[] lists;
        public Integer total_items;
    }

    public class ListResponse {
        public String id;
        public String name;
    }

    public class InterestsResponse {
        public Interest[] interests;
        public Integer total_items;

        public InterestsResponse(Interest[] interests) {
            this.interests = interests;
            this.total_items = interests.size();
        }
    }

    public class Interest {
        public String id;
        public String name;
        public Long subscriber_count;
        public Integer display_order;

        public Interest(String id, String name, Long subscriber_count) {
            this.id = id;
            this.name = name;
            this.subscriber_count = subscriber_count;
        }
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
        public List<Interest> interests {
            get {
                if (interests == null) {
                    interests = new List<Interest>();
                }
                return interests;
            }
            set;
        }
    }

    public class MergeField {
        public Integer merge_id;
        public String tag;
        public String name;
        public String type;
        public Boolean required;
        public String default_value;
    }

    public class MergeFieldsResponse {
        public MergeField[] merge_fields;
        public Integer total_items;
    }

    public class Tag {
        public Integer id;
        public String name;
        public Integer member_count;
    }

    public class TagsResponse {
        public Tag[] segments;
        public Integer total_items;
    }

    public String listEndpoint() {
        MailchimpSettings__c settings = MailchimpSettings__c.getInstance();
        return 'lists/' + settings.AudienceID__c;
    }

    public String mergeFieldsEndpoint() {
        return this.listEndpoint() + '/merge-fields?count=1000';
    }

    public String tagsEndpoint() {
        return this.listEndpoint() + '/segments?type=static&count=1000';
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
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setTimeout(30000);

        return this.connection.send(req);
    }

    public HttpResponse post(String endpoint, String body) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setBody(body);
        req.setTimeout(120000);

        return this.connection.send(req);
    }

    public ListsResponse fetchLists() {
        HttpResponse resp = this.get('lists');
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Request failed: ' +
                resp.getStatusCode() + ' ' + resp.getStatus()
            );
        }
        JSONParser parser = JSON.createParser(resp.getBody());
        return (ListsResponse)parser.readValueAs(ListsResponse.class);
    }

    public ListResponse fetchList() {
        HttpResponse resp = this.get(this.listEndpoint());
        if (resp.getStatusCode() != 200) {
            throw new CalloutException(
                'Request failed: ' +
                resp.getStatusCode() + ' ' + resp.getStatus()
            );
        }
        JSONParser parser = JSON.createParser(resp.getBody());
        return (ListResponse)parser.readValueAs(ListResponse.class);
    }

    private void writeContactField(JSONGenerator body, Contact c, MailchimpFieldMapping__mdt fieldMapping) {
        String objName = fieldMapping.Salesforce_Object_API_Name__c;
        String fieldName = fieldMapping.Salesforce_Field_API_Name__c;
        String mergeTag = fieldMapping.Mailchimp_Merge_Field_Tag__c;

        Object value = MailchimpAPI.getField(c, fieldName, objName);
        if (value == null) return;

        Map<String, Schema.SObjectType> objMap = Schema.getGlobalDescribe();
        Map<String, Schema.SObjectField> fieldMap = objMap.get(objName).getDescribe().fields.getMap();
        Schema.SoapType type = fieldMap.get(fieldName).getDescribe().getSOAPType();
        switch on type {
            when STRING, ID {
                body.writeStringField(mergeTag, (String)value);
            }
            when INTEGER, DOUBLE {
                body.writeNumberField(mergeTag, (Decimal)value);
            }
            when DATE, DATETIME {
                body.writeDateTimeField(mergeTag, (Datetime)value);
            }
            when else {
                throw new TypeException(
                    'Attempted to push field ' + fieldMapping.MasterLabel +
                    ' with unhandled type ' + type
                );
            }
        }
    }

    public HttpResponse pushContactFields(Map<String, Contact> contacts, MailchimpFieldMapping__mdt[] fieldMappings) {
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

        for (String email : contacts.keySet()) {
            Contact c = contacts.get(email);

            body.writeStartObject();
            body.writeStringField('email_address', email);
            body.writeStringField('status_if_new', 'unsubscribed');
            body.writeFieldName('merge_fields');
            body.writeStartObject();
            for (MailchimpFieldMapping__mdt fieldMapping : fieldMappings) {
                if (fieldMapping.Direction__c != 'push') continue;
                if (fieldMapping.Push_To_Mailchimp_As__c != PUSH_AS_MERGE_FIELD) continue;

                this.writeContactField(body, c, fieldMapping);
            }
            body.writeEndObject();
            body.writeEndObject();
        }

        body.writeEndArray();
        body.writeBooleanField('update_existing', true);
        body.writeEndObject();

        return this.post(this.listEndpoint(), body.getAsString());
    }

    private void writeTagField(JSONGenerator tagsBody, Contact c, MailchimpFieldMapping__mdt fieldMapping) {
        String objName = fieldMapping.Salesforce_Object_API_Name__c;
        String fieldName = fieldMapping.Salesforce_Field_API_Name__c;
        String tagName = fieldMapping.Mailchimp_Merge_Field_Tag__c;

        Boolean active = MailchimpAPI.getTagValue(c, fieldName, objName);
        if (active == null) {
            active = false;
        }

        tagsBody.writeStartObject();
        tagsBody.writeStringField('name', tagName);
        tagsBody.writeStringField('status', active ? 'active' : 'inactive');
        tagsBody.writeEndObject();
    }

    public HttpResponse pushContactTags(Map<String, Contact> contacts, Set<String> contactErrors, MailchimpFieldMapping__mdt[] fieldMappings) {
        // Sync boolean fields as tags using batch endpoint
        // This call will return pretty much immediately, since the batch
        // operations are queued up to happen asynchronously.
        JSONGenerator body = JSON.createGenerator(false);
        JSONGenerator tagsBody;

        body.writeStartObject();
        body.writeFieldName('operations');
        body.writeStartArray();
        for (String email : contacts.keySet()) {
            if (contactErrors.contains(email)) {
                continue;
            }

            Contact c = contacts.get(email);
            tagsBody = JSON.createGenerator(false);
            tagsBody.writeStartObject();
            tagsBody.writeFieldName('tags');
            tagsBody.writeStartArray();
            for (MailchimpFieldMapping__mdt fieldMapping : fieldMappings) {
                if (fieldMapping.Direction__c != 'push') continue;
                if (fieldMapping.Push_To_Mailchimp_As__c != PUSH_AS_TAG) continue;

                this.writeTagField(tagsBody, c, fieldMapping);
            }
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

    public HttpResponse fetchMergeFields() {
        return this.get(this.mergeFieldsEndpoint());
    }

    public HttpResponse fetchTags() {
        return this.get(this.tagsEndpoint());
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
