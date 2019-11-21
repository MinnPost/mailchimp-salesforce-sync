global with sharing class MailchimpPullJob implements Queueable, Database.AllowsCallouts {
    public Integer count = 200;
    public Integer offset = 0;
    public Boolean sinceLastChanged;

    public MailchimpPullJob(Integer count, Integer offset) {
        this(count, offset, true);
    }

    public MailchimpPullJob(Integer count, Integer offset, Boolean sinceLastChanged) {
        this.count = count;
        this.offset = offset;
        this.sinceLastChanged = sinceLastChanged;
    }

    public void execute(QueueableContext context) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MailchimpSyncManager.PullResult result =
            mailchimp.pullAll(this.count, this.offset, this.sinceLastChanged);

        if (result == MailchimpSyncManager.PullResult.ERROR) return;

        if (result == MailchimpSyncManager.PullResult.MORE_TO_PULL) {
            ID jobID = System.enqueueJob(
                new MailchimpPullJob(this.count, this.offset + this.count, this.sinceLastChanged)
            );
            System.debug('Queued another pull: ' + jobID);
            return;
        }

        // All done, now start pushing the Salesforce fields for the contacts
        // we just pulled
        Database.executeBatch(new MailchimpPushJob(), 200);
    }
}
