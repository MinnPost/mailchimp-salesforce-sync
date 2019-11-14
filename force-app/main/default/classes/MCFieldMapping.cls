public with sharing class MCFieldMapping {
    public String sfObjName { get; set; }
    public String sfFieldName { get; set; }
    public String direction { get; set; }
    public String mcAttrFieldTag {
        get;
        set {
            mcAttrFieldTag = value;
            mcFieldTag = null;
            mcMemberAttr = null;
            if (value == null) return;

            String[] parts = mcAttrFieldTag.split('--', 2);
            if (parts.size() < 2) return;
            switch on parts[0] {
                when 'field', 'tag' {
                    mcFieldTag = parts[1];
                    mcPushAs = '*|MERGE|* Field';
                    if (parts[0] == 'tag') {
                        mcPushAs = 'Tag';
                    }
                }
                when 'attr' {
                    mcMemberAttr = parts[1];
                }
                when else {
                    throw new TypeException('unknown Mailchimp field/attribute type ' + parts[0]);
                }
            }
        }
    }
    public String defaultValue { get; set; }

    public String mcFieldTag { get; private set; }
    public String mcMemberAttr { get; private set; }
    public String mcPushAs { get; private set; }

    public Metadata.CustomMetadata asCustomMetadata() {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        String name = this.sfObjName.removeEnd('__c') +
            '_' + this.sfFieldName.removeEnd('__c');
        md.fullName = 'MailchimpFieldMapping.' + name.left(40);
        md.label = name.left(40);

        Metadata.CustomMetadataValue mvObjName = new Metadata.CustomMetadataValue();
        mvObjName.field = 'Salesforce_Object_API_Name__c';
        mvObjName.value = this.sfObjName;
        md.values.add(mvObjName);

        Metadata.CustomMetadataValue mvFieldName = new Metadata.CustomMetadataValue();
        mvFieldName.field = 'Salesforce_Field_API_Name__c';
        mvFieldName.value = this.sfFieldName;
        md.values.add(mvFieldName);

        Metadata.CustomMetadataValue mvDirection = new Metadata.CustomMetadataValue();
        mvDirection.field = 'Direction__c';
        mvDirection.value = this.direction;
        md.values.add(mvDirection);

        Metadata.CustomMetadataValue mvFieldTag = new Metadata.CustomMetadataValue();
        mvFieldTag.field = 'Mailchimp_Merge_Field_Tag__c';
        mvFieldTag.value = this.mcFieldTag;
        md.values.add(mvFieldTag);

        Metadata.CustomMetadataValue mvMemberAttr = new Metadata.CustomMetadataValue();
        mvMemberAttr.field = 'Mailchimp_Member_Attribute__c';
        mvMemberAttr.value = this.mcMemberAttr;
        md.values.add(mvMemberAttr);

        Metadata.CustomMetadataValue mvPushAs = new Metadata.CustomMetadataValue();
        mvPushAs.field = 'Push_To_Mailchimp_As__c';
        mvPushAs.value = this.mcPushAs;
        md.values.add(mvPushAs);

        Metadata.CustomMetadataValue mvDefaultVal = new Metadata.CustomMetadataValue();
        mvDefaultVal.field = 'Default_Value__c';
        mvDefaultVal.value = this.defaultValue;
        md.values.add(mvDefaultVal);

        return md;
    }
}
