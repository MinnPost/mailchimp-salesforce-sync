public with sharing class MailchimpSyncManager {
    static final String STAGE_BATCH_SUB_UNSUB = '1 - Add/update contacts in Mailchimp';
    static final String STAGE_BATCH_TAG = '2 - Add/update tags in Mailchimp';

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
        public MCSubscriber[] members;
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

    private Boolean parseContactFieldsResponse(Contact[] contacts, String respBody, Result result) {
        JSONParser parser = JSON.createParser(respBody);
        try {
            ContactFieldsResponse response = (ContactFieldsResponse)parser.readValueAs(ContactFieldsResponse.class);
            result.totalCreated = response.total_created;
            result.totalUpdated = response.total_updated;
            result.errorCount = response.error_count;
            if (response.errors == null) {
                return true;
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
            insert result.requestError;
            return false;
        }

        return true;
    }

    private Boolean parseBatchResponse(String respBody, Result result) {
        return this.parseBatchResponse(respBody, result, new Mailchimp_Batch_Operation__c());
    }

    private Boolean parseBatchResponse(String respBody, Result result, Mailchimp_Batch_Operation__c batch) {
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
                Title__c=e.getTypeName() + ' while parsing Mailchimp response',
                Detail__c=e.getMessage()
            );
            insert result.requestError;
            return false;
        }

        upsert batch;
        return true;
    }

    private List<MCSubscriber> parseMembersResponse(String respBody) {
        JSONParser parser = JSON.createParser(respBody);
        try {
            MembersResponse response = (MembersResponse)parser.readValueAs(MembersResponse.class);
            return response.members;
        } catch (JSONException e) {
            System.debug(LoggingLevel.ERROR, e);
            return new List<MCSubscriber>();
        }
    }

    public Result pushAll(List<Contact> contacts) {
        Result result = new Result();

        // Mailchimp API returns 200 even if some of the sub/unsub changes
        // produced errors.
        // I have observed it return a 400 Bad Request with an error response
        // if there are duplicate e-mails in the list.
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.pushContactFields(contacts);
        if (resp.getStatusCode() != 200) {
            result.requestError = this.reportError(STAGE_BATCH_SUB_UNSUB, resp.getBody());
            return result;
        }
        if (!this.parseContactFieldsResponse(contacts, resp.getBody(), result)) {
            return result;
        }

        HttpResponse tagsResp = mailchimp.pushContactTags(contacts, result.contactErrors.keySet());
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
