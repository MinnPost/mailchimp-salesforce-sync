public with sharing class MailchimpFieldMappingsController {
    public MailchimpFieldMapping__mdt[] fieldMappings {
        get {
            if (fieldMappings == null) {
                fieldMappings =
                    [SELECT DeveloperName,
                            Direction__c,
                            Salesforce_Object_API_Name__c,
                            Salesforce_Field_API_Name__c,
                            Push_To_Mailchimp_As__c,
                            Mailchimp_Merge_Field_Tag__c,
                            Mailchimp_Member_Attribute__c,
                            Default_Value__c
                     FROM MailchimpFieldMapping__mdt
                     ORDER BY Direction__c ASC,
                              Push_To_Mailchimp_As__c ASC,
                              Salesforce_Object_API_Name__c ASC,
                              Salesforce_Field_API_Name__c ASC];
            }
            return fieldMappings;
        }
        private set;
    }

    public MCFieldMapping newMapping {
        get {
            if (newMapping == null) {
                newMapping = new MCFieldMapping();
            }
            return newMapping;
        }
        private set;
    }

    public SelectOption[] objChoices {
        get {
            if (objChoices == null) {
                objChoices = new List<SelectOption>{
                    new SelectOption('Account', 'Account'),
                    new SelectOption('Contact', 'Contact')
                };
            }
            return objChoices;
        }
        private set;
    }

    public SelectOption[] fieldChoices {
        get {
            if (fieldChoices == null) {
                Map<String, Map<String, String>> fieldsByObject =
                    this.getFieldsByObject();
                fieldChoices = new List<SelectOption>{};
                for (String objType : fieldsByObject.keySet()) {
                    String[] sortedKeys = new List<String>(fieldsByObject.get(objType).keySet());
                    sortedKeys.sort();
                    for (String fieldName : sortedKeys) {
                        fieldChoices.add(
                            new SelectOption(
                                fieldName,
                                fieldsByObject.get(objType).get(fieldName)
                            )
                        );
                    }
                }
            }
            return fieldChoices;
        }
        private set;
    }

    public SelectOption[] directionChoices {
        get {
            if (directionChoices == null) {
                directionChoices = new List<SelectOption>{
                    new SelectOption('push', 'Push ->'),
                    new SelectOption('pull', '<- Pull'),
                    new SelectOption('sync', 'Set on creation')
                };
            }
            return directionChoices;
        }
        private set;
    }

    public SelectOption[] attrFieldTagOptions {
        get {
            if (attrFieldTagOptions == null) {
                attrFieldTagOptions = new List<SelectOption>();
                attrFieldTagOptions.addAll(
                    optionsForChoices(getAttrChoices())
                );
                attrFieldTagOptions.addAll(
                    optionsForChoices(getMergeFieldChoices())
                );
                attrFieldTagOptions.addAll(
                    optionsForChoices(getTagChoices())
                );
            }
            return attrFieldTagOptions;
        }
        private set;
    }

    public Map<String, Map<String, String>> getFieldsByObject() {
        String[] objTypes = new String[]{ 'Account', 'Contact' };
        Schema.DescribeSObjectResult[] objDescs =
            Schema.describeSObjects(objTypes);
        Map<String, Map<String, String>> choicesByObject =
            new Map<String, Map<String, String>>();
        for (Schema.DescribeSObjectResult objDesc : objDescs) {
            Map<String, Schema.SObjectField> fieldMap =
                objDesc.fields.getMap();
            Map<String, String> choices = new Map<String, String>();
            for (String fn : fieldMap.keySet()) {
                choices.put(fn, fieldMap.get(fn).getDescribe().getLabel());
            }
            choicesByObject.put(objDesc.getName(), choices);
        }

        return choicesByObject;
    }

    public String getFieldsByObjectJSON() {
        return JSON.serialize(this.getFieldsByObject());
    }

    public Map<String, String> getAttrChoices() {
        String[] attrs = new List<String>{
            'id',
            'email_address',
            'email_client',
            'email_type',
            'ip_opt',
            'ip_signup',
            'language',
            'member_rating',
            'source',
            'status',
            'tags_count',
            'timestamp_opt',
            'timestamp_signup',
            'vip'
        };
        Map<String, String> choices = new Map<String, String>();
        for (String attr : attrs) {
            choices.put('attr--' + attr, attr);
        }
        return choices;
    }

    public Map<String, String> getMergeFieldChoices() {
        Map<String, String> choices = new Map<String, String>();

        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.fetchMergeFields();
        if (resp.getStatusCode() != 200) return choices;

        JSONParser parser = JSON.createParser(resp.getBody());
        MailchimpAPI.MergeFieldsResponse body =
            (MailchimpAPI.MergeFieldsResponse)parser
                .readValueAs(MailchimpAPI.MergeFieldsResponse.class);
        for (MailchimpAPI.MergeField mergeField : body.merge_fields) {
            choices.put('field--' + mergeField.tag, mergeField.name);
        }

        return choices;
    }

    public Map<String, String> getTagChoices() {
        Map<String, String> choices = new Map<String, String>();

        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.fetchTags();
        if (resp.getStatusCode() != 200) return choices;

        JSONParser parser = JSON.createParser(resp.getBody());
        MailchimpAPI.TagsResponse body =
            (MailchimpAPI.TagsResponse)parser
                .readValueAs(MailchimpAPI.TagsResponse.class);
        for (MailchimpAPI.Tag tag : body.segments) {
            choices.put('tag--' + tag.name, tag.name);
        }

        return choices;
    }

    public String getAttrFieldTagChoicesJSON() {
        return JSON.serialize(new Map<String, Map<String, String>>{
            'mcMemberAttrs' => this.getAttrChoices(),
            'mcMergeFields' => this.getMergeFieldChoices(),
            'mcTags' => this.getTagChoices()
        });
    }

    private SelectOption[] optionsForChoices(Map<String, String> choices) {
        SelectOption[] options = new List<SelectOption>();
        for (String key : choices.keySet()) {
            options.add(new SelectOption(
                key,
                choices.get(key)
            ));
        }
        return options;
    }

    public PageReference createMapping() {
        Metadata.DeployContainer mdc = new Metadata.DeployContainer();
        Metadata.CustomMetadata cm = this.newMapping.asCustomMetadata();
        mdc.addMetadata(cm);
        System.debug(LoggingLevel.INFO,
            Metadata.Operations.enqueueDeployment(mdc, null));
        ApexPages.addMessage(new ApexPages.Message(
            ApexPages.Severity.INFO,
            'Deploying new field mapping, which may take a few seconds. ' +
            'Refresh the page to see the updated list.'
        ));

        this.newMapping = null;
        return null;
    }
}
