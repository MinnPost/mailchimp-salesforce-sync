public class MCMemberRatingController {
    public Integer memberRating;

    public void setMemberRating(Integer rating) {
        System.debug('assigning rating ' + rating);
        this.memberRating = rating;
    }

    public String getMemberRating() {
        if (this.memberRating == null) {
            return 'null';
        }
        return '✯'.repeat(this.memberRating);
    }
}
