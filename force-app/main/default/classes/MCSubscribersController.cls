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
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:Mailchimp/lists/3528e74526/members?count=1000&status=subscribed&fields=members.id,members.email_address,members.member_rating,total_items');
        Http http = new Http();
        HttpResponse resp = http.send(req);

        JSONParser parser = JSON.createParser(resp.getBody());
        JSONToken currentToken = parser.nextToken();
        if (currentToken != JSONToken.START_OBJECT) {
            System.debug('Can\'t parse response beginning with ' + currentToken);
            return;
        }
        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() != JSONToken.FIELD_NAME) {
                continue;
            }
            parser.nextToken();
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
