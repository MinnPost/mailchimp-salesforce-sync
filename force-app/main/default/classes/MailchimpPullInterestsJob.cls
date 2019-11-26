// Copyright 2019 MinnPost <tech@minnpost.com>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

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
