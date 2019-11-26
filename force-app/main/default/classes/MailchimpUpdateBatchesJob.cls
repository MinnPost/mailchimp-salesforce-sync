// Copyright 2019 MinnPost <tech@minnpost.com>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

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
