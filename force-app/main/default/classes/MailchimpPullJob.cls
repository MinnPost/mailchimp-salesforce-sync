global with sharing class MailchimpPullJob implements Queueable, Database.AllowsCallouts {
    public Integer count = 400;
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
        MailchimpSyncManager.Result result =
            mailchimp.pullAll(this.count, this.offset, this.sinceLastChanged);

        System.debug(result);
        if (result.isError()) return;

        Integer nextOffset = this.offset + this.count;
        if (result.totalItems > nextOffset) {
            // queue another
            ID jobID = System.enqueueJob(
                new MailchimpPullJob(this.count, nextOffset)
            );
            System.debug('Queued another pull: ' + jobID);
            return;
        }

        // All done, now start pushing the Salesforce fields for the contacts
        // we just pulled
        Database.executeBatch(new MailchimpSyncJob(), 400);
    }
}
