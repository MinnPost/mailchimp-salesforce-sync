global with sharing class MailchimpSyncJob implements Database.Batchable<SObject>, Database.AllowsCallouts {
    global Database.QueryLocator start(Database.BatchableContext context) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        return mailchimp.contactsQueryLocator();
    }

    global void execute(Database.BatchableContext context, SObject[] contacts) {
        MailchimpSyncManager mailchimp = new MailchimpSyncManager();
        mailchimp.pushAll(contacts);
    }

    global void finish(Database.BatchableContext context) {
        System.debug('Batch Apex job ' + context.getJobId() + ' finished');
    }
}
