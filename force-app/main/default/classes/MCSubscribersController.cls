public with sharing class MCSubscribersController {
    private Long totalSubscribers;
    private List<MCSubscriber> subscribers = new List<MCSubscriber>();

    public Long getTotalSubscribers() {
        return totalSubscribers;
    }
    
    public List<MCSubscriber> getSubscribers() {
        return subscribers;
    }

    public void fetch() {
        System.debug('Fetching Mailchimp subscribers...');
        MailchimpAPI mailchimp = new MailchimpAPI();
        HttpResponse resp = mailchimp.get(
            mailchimp.membersEndpoint() +
            '?count=1000&status=subscribed&fields=members.id,members.email_address,members.member_rating,total_items'
        );

        JSONParser parser = JSON.createParser(resp.getBody());
        if (parser.nextToken() != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + parser.getCurrentToken());
            return;
        }
        while (parser.nextValue() != null) {
            if (parser.getCurrentName() == 'total_items') {
                this.totalSubscribers = parser.getLongValue();
                continue;
            }
            if (parser.getCurrentName() == 'members') {
                if (parser.getCurrentToken() != JSONToken.START_ARRAY) {
                    throw new TypeException('"members" in response was expected to be an array, got ' + parser.getCurrentToken());
                }
                while (parser.nextToken() == JSONToken.START_OBJECT) {
                    this.subscribers.add((MCSubscriber)parser.readValueAs(MCSubscriber.class));
                }
            }
        }
    }
}
