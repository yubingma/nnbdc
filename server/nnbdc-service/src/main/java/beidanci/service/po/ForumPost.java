package beidanci.service.po;

import java.util.Date;
import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.OrderBy;
import javax.persistence.Table;

@Entity
@Table(name = "forum_post")
public class ForumPost extends UuidPo  {


    private User user;

    private Forum forum;

    @Column(name = "postTitle", length = 100, nullable = false)
    private String postTitle;

    @Column(name = "postContent", length = 1048576, nullable = false)
    private String postContent;

    @Column(name = "replyCount", nullable = false)
    private Integer replyCount;

    @Column(name = "browseCount", nullable = false)
    private Integer browseCount;

    @Column(name = "lastReplyTime")
    private Date lastReplyTime;

    @OrderBy("updateTime asc")
    private List<ForumPostReply> forumPostReplies;

    // Constructors

    /**
     * default constructor
     */
    public ForumPost() {
    }

    // Property accessors

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Forum getForum() {
        return this.forum;
    }

    public void setForum(Forum forum) {
        this.forum = forum;
    }

    public String getPostTitle() {
        return this.postTitle;
    }

    public void setPostTitle(String postTitle) {
        this.postTitle = postTitle;
    }

    public String getPostContent() {
        return this.postContent;
    }

    public void setPostContent(String postContent) {
        this.postContent = postContent;
    }

    public Integer getReplyCount() {
        return this.replyCount;
    }

    public void setReplyCount(Integer replyCount) {
        this.replyCount = replyCount;
    }

    public Integer getBrowseCount() {
        return browseCount;
    }

    public void setBrowseCount(Integer browseCount) {
        this.browseCount = browseCount;
    }

    public Date getLastReplyTime() {
        return lastReplyTime;
    }

    public void setLastReplyTime(Date lastReplyTime) {
        this.lastReplyTime = lastReplyTime;
    }

    public List<ForumPostReply> getForumPostReplies() {
        return forumPostReplies;
    }

    public void setForumPostReplies(List<ForumPostReply> forumPostReplies) {
        this.forumPostReplies = forumPostReplies;
    }
}
