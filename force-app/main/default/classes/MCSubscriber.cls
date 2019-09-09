public class MCSubscriber {
	public String ID;
    public String email_address;
    public String status;
    public Integer member_rating;
    public Datetime last_changed;
    public Map<String, String> merge_fields;

    public String getEmailAddress() {
        return this.email_address;
    }

    public Integer getMemberRating() {
        return this.member_rating;
    }
}
