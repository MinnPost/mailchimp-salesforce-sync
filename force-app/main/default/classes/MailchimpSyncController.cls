public with sharing class MailchimpSyncController {
    public List<Contact> contactList { get; private set; }
    public List<Mailchimp_Sync_Error__c> recentSyncErrors { get; private set; }
    public List<Mailchimp_Batch_Operation__c> unfinishedBatchOperations { get; private set; }
    public List<AsyncApexJob> processingJobs { get; private set; }

    public void fetchData() {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        this.contactList = mailchimp.contactsToSync(50);
        this.recentSyncErrors =
            [SELECT Id, Name, CreatedDate, Stage__c, Contact__c, Title__c, Detail__c
             FROM Mailchimp_Sync_Error__c
             ORDER BY CreatedDate DESC LIMIT 20];
        this.unfinishedBatchOperations = mailchimp.unfinishedBatches(20);
        this.processingJobs =
            [SELECT Id, ApexClass.Name, CreatedDate, Status, ExtendedStatus, NumberOfErrors
             FROM AsyncApexJob
             WHERE ApexClassID IN (
                SELECT Id FROM ApexClass WHERE Name IN ('MailchimpPullJob', 'MailchimpSyncJob')
             )
             ORDER BY CreatedDate DESC LIMIT 20];
    }

    public PageReference pushContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        Database.executeBatch(new MailchimpSyncJob(), 400);

        return redirect;
    }

    public PageReference pullInterests() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.pullInterests();

        return redirect;
    }

    public PageReference pullContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        System.enqueueJob(new MailchimpPullJob(400, 0));

        return redirect;
    }

    public PageReference updateBatches() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.updateBatches();

        return redirect;
    }
}
