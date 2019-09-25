public with sharing class MailchimpFieldMappingsController {
    public MailchimpFieldMapping__mdt[] fieldMappings {
        get {
            if (fieldMappings == null) {
                fieldMappings =
                    [SELECT Direction__c,
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
        set;
    }

    public PageReference save() {
        return ApexPages.currentPage();
    }
}
