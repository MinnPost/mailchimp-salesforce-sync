global with sharing class MailchimpUpdateBatchesJob implements Database.Batchable<SObject>, Database.AllowsCallouts {
    global Mailchimp_Batch_Operation__c[] start(Database.BatchableContext context) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        return mailchimp.unfinishedBatches();
    }

    global void execute(Database.BatchableContext context, SObject[] batches) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.updateBatches(batches);
    }

    global void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'MailchimpUpdateBatchesJob ' + context.getJobId() + ' finished');
    }
}
