global with sharing class MailchimpPullJob implements Queueable, Database.AllowsCallouts {
    public Integer count = 400;
    public Integer offset = 0;

    public MailchimpPullJob(Integer count, Integer offset) {
        this.count = count;
        this.offset = offset;
    }

    public void execute(QueueableContext context) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        MailchimpSyncManager.Result result =
            mailchimp.pullAll(this.count, this.offset);

        System.debug(result);
        if (result.isError()) return;

        Integer nextOffset = this.offset + this.count;
        if (result.totalItems > nextOffset) {
            // queue another
            ID jobID = System.enqueueJob(
                new MailchimpPullJob(this.count, nextOffset)
            );
            System.debug('Queued another pull: ' + jobID);
        }
    }
}
