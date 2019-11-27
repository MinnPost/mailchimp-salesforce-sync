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

    @isTest static void testErrorResponse() {
        MailchimpErrorResponse resp = new MailchimpErrorResponse();
        resp.type = 'test';
        resp.title = 'Test Error';
        resp.status = 420;
        resp.detail = 'This is a test error that does not indicate any malfunction.';
        resp.instance = 'bYW8jb0DY3w';

        System.assertEquals('test', resp.type);
        System.assertEquals('Test Error', resp.title);
        System.assertEquals(420, resp.status);
        System.assertEquals(60, resp.detail.length());
        System.assertEquals('bYW8jb0DY3w', resp.instance);
    }
}
