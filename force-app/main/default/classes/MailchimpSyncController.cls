public with sharing class MailchimpSyncController {
    public String contactsNeedingSync { get; private set; }
    public String lastSyncCompletedAt { get; private set; }
    public String jobsInProgress { get; private set; }
    public List<Mailchimp_Sync_Error__c> recentSyncErrors { get; private set; }
    public List<Mailchimp_Batch_Operation__c> unfinishedBatchOperations { get; private set; }
    public List<AsyncApexJob> recentJobs { get; private set; }

    public void fetchData() {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        Integer contactsCount = mailchimp.contactsCount();
        this.contactsNeedingSync = contactsCount > 0 ?
                String.valueOf(contactsCount) :
                'No';
        Datetime lastSyncCompletedAt = mailchimp.lastSyncCompletedAt();
        this.lastSyncCompletedAt = lastSyncCompletedAt == null ?
            'No sync has been performed yet.' :
            'Last sync finished at ' + lastSyncCompletedAt.format() + '.';
        this.recentSyncErrors =
            [SELECT Id, Name, CreatedDate, Stage__c, Contact__c, Title__c, Detail__c
             FROM Mailchimp_Sync_Error__c
             ORDER BY CreatedDate DESC LIMIT 20];
        this.unfinishedBatchOperations = mailchimp.unfinishedBatches(20);
        this.recentJobs =
            [SELECT Id, ApexClass.Name, CreatedDate, Status, ExtendedStatus, NumberOfErrors
             FROM AsyncApexJob
             WHERE ApexClassID IN (
                SELECT Id FROM ApexClass WHERE Name IN ('MailchimpPullInterestsJob', 'MailchimpPullJob', 'MailchimpPushJob', 'MailchimpSyncJob')
             )
             ORDER BY CreatedDate DESC LIMIT 10];
        Integer jobsInProgress = mailchimp.inProgressJobsCount();
        this.jobsInProgress = jobsInProgress > 0 ?
            String.valueOf(jobsInProgress) :
            'No';
    }

    public PageReference updateContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(400, 0)));

        return redirect;
    }

    public PageReference syncAllContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(400, 0, false)));

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
