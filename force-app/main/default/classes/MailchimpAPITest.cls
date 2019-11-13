@isTest
private class MailchimpAPITest {
    @isTest static void testSubscriberIsTaggedWith() {
        MailchimpAPI.SubscriberTag tag = new MailchimpAPI.SubscriberTag();
        tag.id = 1;
        tag.name = 'Sample Mailchimp Tag';
        MailchimpAPI.Subscriber sub = new MailchimpAPI.Subscriber();
        sub.tags = new List<MailchimpAPI.SubscriberTag>{ tag };
        sub.email_address = 'noone@example.com';

        System.assert(sub.isTaggedWith('Sample Mailchimp Tag'));
        System.assert(!sub.isTaggedWith('Facebook Lead'));
    }
}
