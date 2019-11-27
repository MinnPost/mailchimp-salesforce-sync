@isTest
private class MCFieldMappingTest {
    @isTest static void testSetAttrFieldTag() {
        MCFieldMapping mapping = new MCFieldMapping();

        mapping.mcAttrFieldTag = 'attr--member_rating';
        System.assertEquals(null, mapping.mcPushAs);
        System.assertEquals(null, mapping.mcFieldTag);
        System.assertEquals('member_rating', mapping.mcMemberAttr);

        mapping.mcAttrFieldTag = 'field--TEST_FIELD';
        System.assertEquals('*|MERGE|* Field', mapping.mcPushAs);
        System.assertEquals('TEST_FIELD', mapping.mcFieldTag);
        System.assertEquals(null, mapping.mcMemberAttr);

        mapping.mcAttrFieldTag = 'tag--Facebook Lead';
        System.assertEquals('Tag', mapping.mcPushAs);
        System.assertEquals('Facebook Lead', mapping.mcFieldTag);
        System.assertEquals(null, mapping.mcMemberAttr);
    }

    @isTest static void testAsCustomMetadata() {
        MCFieldMapping mapping = new MCFieldMapping();
        mapping.sfObjName = 'Contact';
        mapping.sfFieldName = 'MailchimpMemberRating__c';
        mapping.direction = 'pull';
        mapping.mcAttrFieldTag = 'attr--member_rating';
        mapping.defaultValue = '2';

        String objName, fieldName, direction, mergeFieldTag, memberAttr, pushAs, defaultVal;
        Metadata.CustomMetadata md = mapping.asCustomMetadata();
        for (Metadata.CustomMetadataValue val : md.values) {
            String strVal = (String)val.value;
            switch on val.field {
                when 'Salesforce_Object_API_Name__c' {
                    objName = strVal;
                }
                when 'Salesforce_Field_API_Name__c' {
                    fieldName = strVal;
                }
                when 'Direction__c' {
                    direction = strVal;
                }
                when 'Mailchimp_Merge_Field_Tag__c' { 
                    mergeFieldTag = strVal;
                }
                when 'Mailchimp_Member_Attribute__c' {
                    memberAttr = strVal;
                }
                when 'Push_To_Mailchimp_As__c' {
                    pushAs = strVal;
                }
                when 'Default_Value__c' {
                    defaultVal = strVal;
                }
            }
        }

        System.assertEquals('Contact', objName);
        System.assertEquals('MailchimpMemberRating__c', fieldName);
        System.assertEquals('pull', direction);
        System.assertEquals(null, mergeFieldTag);
        System.assertEquals('member_rating', memberAttr);
        System.assertEquals('2', defaultVal);
    }
}
