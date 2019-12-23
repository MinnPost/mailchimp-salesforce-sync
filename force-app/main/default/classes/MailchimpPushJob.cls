// Copyright 2019 MinnPost <tech@minnpost.com>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

global with sharing class MailchimpPushJob implements Database.Batchable<SObject>, Database.AllowsCallouts {
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
        System.scheduleBatch(
            new MailchimpUpdateBatchesJob(),
            'Update Mailchimp batch job status',
            5, // minute(s)
            50 // batch size
        );
    }
}
