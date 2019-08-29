public with sharing class MailchimpSyncController {
    private List<Contact> contactList;

    public List<Contact> getContactList() {
        return contactList;
    }

    private List<Contact> contactsToSync() {
        return this.contactsToSync(null);
    }

    private List<Contact> contactsToSync(Integer lim) {
        // Depends on the MailchimpNeedsSync__c custom field, which is a formula defined as:
        //     ISBLANK(MailchimpLastSyncedAt__c) || MailchimpLastSyncedAt__c - LastModifiedDate > 0
        // where MailchimpLastSyncedAt__c is a custom field that the sync process sets [will set].
        String query = 'SELECT ID, Email, FirstName, LastName, Account.ID, Account.SF_Record_Type__c,' +
            ' Account.Membership_Level_Number__c, Account.Membership_Level__c,' +
            ' Account.Membership_level_qualification_amount__c, Account.Membership_Expiration_Date__c,' +
            ' Account.Recurring_donations_Annualized_value_new__c,' +
            ' Account.Active_sustainer__c, Is_partner_offer_eligible__c,' +
            ' Account.Current_member__c, Account.Lapsed_member__c, Account.Never_member__c,' +
            ' MinnPost_com_user_account__c' +
            ' FROM Contact' +
            ' WHERE Email != null AND MailchimpNeedsSync__c = TRUE';
        if (lim != null) {
            query += ' LIMIT ' + lim;
        }
        return Database.query(query);
    }

    public void fetchContacts() {
        this.contactList = this.contactsToSync(50);
    }

    public PageReference pushContacts() {
        System.debug('Pushing contacts to Mailchimp');
        // Find contacts (that haven't been synced [recently]?)
        // - Need subset of fields, plus account ID & type (Household)
        // - Contact might not have e-mail address, in which case exclude from sync?
        // - Can add last-synced date, compare against last-modified date
        List<Contact> contacts = this.contactsToSync(500);
        DateTime lastSyncedAt = DateTime.now();

        // Sync to Mailchimp using bulk-add endpoint
        // - what about deletes? Unlikely that a contact would ever be removed from Salesforce
        // - Need to ensure we don't re-subscribe anyone who's unsubscribed
        // - May need to use a batch request to avoid SF callout response size limits


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
            if (c.FirstName != null) {
                body.writeStringField('FNAME', c.FirstName);
            }
            if (c.LastName != null) {
                body.writeStringField('LNAME', c.LastName);
            }
            body.writeEndObject();
            body.writeEndObject();
            c.MailchimpLastSyncedAt__c = lastSyncedAt;
        }
        body.writeEndArray();
        body.writeBooleanField('update_existing', true);
        body.writeEndObject();

        System.debug(body.getAsString().abbreviate(500));

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Mailchimp/lists/3528e74526');
        req.setBody(body.getAsString());
        req.setTimeout(120000);
        Http conn = new Http();
        HttpResponse resp = conn.send(req);

        System.debug(resp.getBody().abbreviate(500));
        if (resp.getStatusCode() == 200) {
            // Mark contacts as synced
            Database.SaveResult[] results = Database.update(contacts);
            for (Database.SaveResult result : results) {
                if (result.isSuccess()) continue;
                System.debug('Error(s) updating timestamp on synced records.');
                for (Database.Error err : result.getErrors()) {
                    System.debug(err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }

        // Sync boolean fields as tags using batch endpoint
        // TODO

        return ApexPages.currentPage();
    }
}
