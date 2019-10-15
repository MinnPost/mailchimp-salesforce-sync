global with sharing class MailchimpSyncJob implements Schedulable {
    global void execute(SchedulableContext context) {
        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(200, 0)));
    }
}
