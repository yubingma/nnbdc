package beidanci.api.model;

import java.util.Date;
import java.util.List;

public class ForumPostVo extends UuidVo {

    private UserVo user;

    private ForumVo forum;

    private String postTitle;

    private String postContent;

    private Integer replyCount;

    private Integer browseCount;

    private Date lastReplyTime;

    private List<ForumPostReplyVo> forumPostReplies;


    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public ForumVo getForum() {
        return forum;
    }

    public void setForum(ForumVo forum) {
        this.forum = forum;
    }

    public String getPostTitle() {
        return postTitle;
    }

    public void setPostTitle(String postTitle) {
        this.postTitle = postTitle;
    }

    public String getPostContent() {
        return postContent;
    }

    public void setPostContent(String postContent) {
        this.postContent = postContent;
    }

    public Integer getReplyCount() {
        return replyCount;
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

    public List<ForumPostReplyVo> getForumPostReplies() {
        return forumPostReplies;
    }

    public void setForumPostReplies(List<ForumPostReplyVo> forumPostReplies) {
        this.forumPostReplies = forumPostReplies;
    }
}
