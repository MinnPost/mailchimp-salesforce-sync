public with sharing class MailchimpSyncController {
    private MailchimpSyncManager mailchimp {
        get {
            if (mailchimp == null) {
                mailchimp = new MailchimpSyncManager();
            }
            return mailchimp;
        }
        set;
    }

    public String contactsNeedingSync {
        get {
            if (contactsNeedingSync == null) {
                Integer contactsCount = mailchimp.contactsCount();
                contactsNeedingSync = contactsCount > 0 ?
                    String.valueOf(contactsCount) :
                    'No';
            }
            return contactsNeedingSync;
        }
        private set;
    }

    public String lastSyncCompletedAt {
        get {
            if (lastSyncCompletedAt == null) {
                Datetime lastDatetime = mailchimp.lastSyncCompletedAt();
                lastSyncCompletedAt = lastDatetime == null ?
                    'No sync has been performed yet.' :
                    'Last sync finished at ' + lastDatetime.format() + '.';
            }
            return lastSyncCompletedAt;
        }
        private set;
    }

    public String jobsInProgress {
        get {
            if (jobsInProgress == null) {
                Integer count = mailchimp.inProgressJobsCount();
                jobsInProgress = count > 0 ?
                    String.valueOf(count) :
                    'No';
            }
            return jobsInProgress;
        }
        private set;
    }

    public List<Mailchimp_Sync_Error__c> recentSyncErrors {
        get {
            if (recentSyncErrors == null) {
                recentSyncErrors =
                    [SELECT Id, Name, CreatedDate, Stage__c, Contact__c,
                            Title__c, Detail__c
                     FROM Mailchimp_Sync_Error__c
                     ORDER BY CreatedDate DESC LIMIT 20];
            }
            return recentSyncErrors;
        }
        private set;
    }

    public List<Mailchimp_Batch_Operation__c> unfinishedBatchOperations {
        get {
            if (unfinishedBatchOperations == null) {
                unfinishedBatchOperations = mailchimp.unfinishedBatches(20);
            }
            return unfinishedBatchOperations;
        }
        private set;
    }

    public List<AsyncApexJob> recentJobs {
        get {
            if (recentJobs == null) {
                recentJobs =
                    [SELECT Id, ApexClass.Name, CreatedDate, Status,
                            ExtendedStatus, NumberOfErrors
                     FROM AsyncApexJob
                     WHERE ApexClassID IN (
                         SELECT Id FROM ApexClass WHERE Name IN (
                             'MailchimpPullInterestsJob',
                             'MailchimpPullJob',
                             'MailchimpPushJob',
                             'MailchimpSyncJob'
                         )
                     )
                     ORDER BY CreatedDate DESC LIMIT 10];
            }
            return recentJobs;
        }
        private set;
    }

    public String mailchimpBaseURL {
        get {
            if (mailchimpBaseURL == null) {
                NamedCredential nc =
                    [SELECT DeveloperName, Endpoint FROM NamedCredential
                     WHERE DeveloperName = 'Mailchimp' LIMIT 1];
                if (nc == null) {
                    mailchimpBaseURL = '(not configured)';
                } else {
                    mailchimpBaseURL = nc.Endpoint;
                }
            }
            return mailchimpBaseURL;
        }
        private set;
    }

    public String mailchimpAudience {
        get {
            if (mailchimpAudience == null) {
                MailchimpAPI api = new MailchimpAPI();
                try {
                    mailchimpAudience = api.fetchList().name;
                } catch (CalloutException e) {
                    // swallow it
                }
            }
            return mailchimpAudience;
        }
        private set;
    }

    public String mailchimpListID {
        get {
            if (mailchimpListID == null) {
                MailchimpSettings__c settings = MailchimpSettings__c.getInstance();
                mailchimpListID = settings.AudienceID__c;
            }
            return mailchimpListID;
        }
        set;
    }

    public SelectOption[] mailchimpListOptions {
        get {
            if (mailchimpListOptions == null) {
                mailchimpListOptions = new List<SelectOption>();
                MailchimpAPI api = new MailchimpAPI();
                for (MailchimpAPI.ListResponse audience : api.fetchLists().lists) {
                    mailchimpListOptions.add(
                        new SelectOption(audience.id, audience.name)
                    );
                }
            }
            return mailchimpListOptions;
        }
        private set;
    }

    public void updateListID() {
        MailchimpSettings__c settings = MailchimpSettings__c.getOrgDefaults();
        settings.AudienceID__c = this.mailchimpListID;
        upsert settings;
    }

    public PageReference updateContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(200, 0)));

        return redirect;
    }

    public PageReference syncAllContacts() {
        PageReference redirect = ApexPages.currentPage();
        redirect.setRedirect(true);

        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(200, 0, false)));

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
