// Copyright 2019 MinnPost <tech@minnpost.com>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

global with sharing class MailchimpSyncJob implements Schedulable {
    global void execute(SchedulableContext context) {
        System.enqueueJob(new MailchimpPullInterestsJob(new MailchimpPullJob(200, 0)));
    }
}
