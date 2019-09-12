public with sharing class MailchimpPullInterestsJob implements Queueable, Database.AllowsCallouts {
    private Queueable nextJob;

    public MailchimpPullInterestsJob() {
        this(null);
    }

    public MailchimpPullInterestsJob(Queueable nextJob) {
        this.nextJob = nextJob;
    }

    public void execute(QueueableContext context) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.pullInterests();

        if (this.nextJob != null) {
            System.enqueueJob(this.nextJob);
        }
    }
}
