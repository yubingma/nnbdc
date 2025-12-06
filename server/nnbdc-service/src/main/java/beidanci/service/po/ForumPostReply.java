package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "forum_post_reply")
public class ForumPostReply extends UuidPo {

    @Column(name = "userId")
    private User user;

    @Column(name = "forumPostId")
    private ForumPost forumPost;

    @Column(name = "content", length = 1048576, nullable = false)
    private String content;

    // Constructors

    /**
     * default constructor
     */
    public ForumPostReply() {
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public ForumPost getForumPost() {
        return this.forumPost;
    }

    public void setForumPost(ForumPost forumPost) {
        this.forumPost = forumPost;
    }

    public String getContent() {
        return this.content;
    }

    public void setContent(String content) {
        this.content = content;
    }

}
