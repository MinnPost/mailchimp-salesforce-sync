public with sharing class MailchimpSyncController {
    public List<Contact> contactList { get; private set; }
    public List<Mailchimp_Sync_Error__c> recentSyncErrors { get; private set; }
    public List<Mailchimp_Batch_Operation__c> unfinishedBatchOperations { get; private set; }

    private List<Contact> contactsToSync() {
        return this.contactsToSync(null);
    }

    private List<Contact> contactsToSync(Integer lim) {
        String query = 'SELECT ID, Email, FirstName, LastName, Drupal_ID__c, Drupal_Username__c,' +
            ' Account.ID, Account.SF_Record_Type__c,' +
            ' Account.Membership_Level_Number__c, Account.Membership_Level__c,' +
            ' Account.Membership_level_qualification_amount__c, Account.Membership_Expiration_Date__c,' +
            ' Account.Recurring_donations_Annualized_value_new__c,' +
            ' Active_sustainer_account__c, Is_partner_offer_eligible__c,' +
            ' Current_member__c, Lapsed_member__c, Never_member__c,' +
            ' MinnPost_com_user_account__c' +
            ' FROM Contact' +
            ' WHERE Email != null AND MailchimpNeedsSync__c = TRUE' +
            ' ORDER BY Email ASC';
        if (lim != null) {
            query += ' LIMIT ' + lim;
        }
        return Database.query(query);
    }

    public void fetchData() {
        this.contactList = this.contactsToSync(50);
        this.recentSyncErrors =
            [SELECT Id, Name, CreatedDate, Stage__c, Contact__c, Title__c, Detail__c
             FROM Mailchimp_Sync_Error__c
             ORDER BY CreatedDate DESC LIMIT 20];
        this.unfinishedBatchOperations =
            [SELECT Id, Name, Status__c, Submitted_At__c
             FROM Mailchimp_Batch_Operation__c
             WHERE Status__c <> 'finished'
             ORDER BY Submitted_At__C DESC LIMIT 20];
    }

    public PageReference pushContacts() {
        // Find contacts (that haven't been synced [recently]?)
        // - Need subset of fields, plus account ID & type (Household)
        // - Contact might not have e-mail address, in which case exclude from sync?
        // - Can add last-synced date, compare against last-modified date
        List<Contact> contacts = this.contactsToSync(400);
        DateTime lastSyncedAt = DateTime.now();

        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MailchimpSyncManager.Result result = mailchimp.pushAll(contacts);
        if (result.isError()) {
            return redirect;
        }

        System.debug(result);

        // Mark contacts as synced
        // TODO: I've observed this fail because of a Flow Trigger blowing over
        // the Apex CPU time limit. Need to figure out what to do about that.
        for (Contact c : contacts) {
            if (result.contactErrors.containsKey(c.Email)) {
                insert result.contactErrors.get(c.Email);
                continue;
            }
            c.MailchimpLastSyncedAt__c = lastSyncedAt;
        }
        Database.SaveResult[] results = Database.update(contacts);
        for (Database.SaveResult saveResult : results) {
            if (saveResult.isSuccess()) continue;
            System.debug('Error(s) updating timestamp on synced records.');
            for (Database.Error err : saveResult.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
            }
        }

        return redirect;
    }
}
