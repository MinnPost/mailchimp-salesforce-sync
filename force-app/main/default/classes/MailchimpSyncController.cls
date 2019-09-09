public with sharing class MailchimpSyncController {
    public List<Contact> contactList { get; private set; }
    public List<Mailchimp_Sync_Error__c> recentSyncErrors { get; private set; }
    public List<Mailchimp_Batch_Operation__c> unfinishedBatchOperations { get; private set; }

    public void fetchData() {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        this.contactList = mailchimp.contactsToSync(50);
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
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        Contact[] contacts = Mailchimp.contactsToSync(400);
        MailchimpSyncManager.Result result = mailchimp.pushAll(contacts);
        System.debug(result);

        return redirect;
    }

    public PageReference pullInterests() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.pullInterests();

        return redirect;
    }

    private Boolean shouldRetry(Database.UpsertResult result) {
        if (result.isSuccess() || !result.isCreated()) return false;

        for (Database.Error err : result.getErrors()) {
            System.debug(err);
            if (err.getStatusCode() == StatusCode.REQUIRED_FIELD_MISSING &&
                err.getFields().contains('Last Name')) {
                return true;
            }
        }

        return false;
    }

    public PageReference pullContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MCSubscriber[] members = mailchimp.pullAll(100, 0);

        Contact[] contacts = new List<Contact>();
        for (MCSubscriber member : members) {
            Contact c = new Contact(
                Email=member.email_address,
                MailchimpEmailHash__c=member.ID,
                MailchimpMemberRating__c=member.member_rating,
                MailchimpLastChanged__c=member.last_changed
            );
            contacts.add(c);
        }

        // Try to upsert without first/last name, check for the appropriate error.
        // New records will come back with a result with isCreated() == TRUE,
        // and a REQUIRED_FIELD_MISSING error on LastName.
        Database.UpsertResult[] results = Database.upsert(contacts, Contact.Fields.Email, false);
        Contact[] contactsToInsert = new List<Contact>();
        for (Integer i = 0; i < results.size(); ++i) {
            Database.UpsertResult result = results[i];
            Contact c = contacts[i];
            MCSubscriber member = members[i];

            if (result.isSuccess()) continue;
            if (this.shouldRetry(result)) {
                c.FirstName = member.merge_fields.get('FNAME');
                c.LastName = member.merge_fields.get('LNAME');
                contactsToInsert.add(c);
                continue;
            }

            System.debug('Error(s) inserting or updating contact.');
            for (Database.Error err : result.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
            }
        }

        Database.SaveResult[] insertResults = Database.insert(contactsToInsert, false);
        for (Database.SaveResult result : insertResults) {
            if (result.isSuccess()) continue;

            System.debug('Error(s) inserting or updating contact.');
            for (Database.Error err : result.getErrors()) {
                System.debug(err.getStatusCode() + ': ' + err.getMessage());
            }
        }

        return redirect;
    }
}
