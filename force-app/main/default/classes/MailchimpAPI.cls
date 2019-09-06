public class MailchimpAPI {
    private Http connection;

    public class Interest {
        public String id;
        public String name;
        public Long subscriber_count;
        public Integer display_order;
    }

    public class InterestCategory {
        public String id;
        public String title;
        public String type;
        public Integer display_order;
        public List<Interest> interests;

        public InterestCategory() {
            this.interests = new List<Interest>();
        }
    }

    public String listEndpoint() {
        return 'lists/3528e74526';
    }

    public String membersEndpoint() {
        return this.listEndpoint() + '/members';
    }

    public String interestCategoriesEndpoint() {
        return this.listEndpoint() + '/interest-categories';
    }

    public String contactTagsEndpoint(Contact c) {
        Blob input = Blob.valueOf(c.Email.toLowerCase());
        Blob emailDigest = Crypto.generateDigest('MD5', input);
        String subscriberHash = EncodingUtil.convertToHex(emailDigest);
        return this.membersEndpoint() + '/' + subscriberHash + '/tags';
    }

    public HttpResponse get(String endpoint) {
        if (this.connection == null) {
            this.connection = new Http();
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setTimeout(30000);

        return this.connection.send(req);
    }

    public HttpResponse post(String endpoint, String body) {
        if (this.connection == null) {
            this.connection = new Http();
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:Mailchimp/' + endpoint);
        req.setBody(body);
        req.setTimeout(120000);

        return this.connection.send(req);
    }
}
