package beidanci.api.model;

public class ForumPostReplyVo extends UuidVo {

    private UserVo user;

    private ForumPostVo forumPost;

    private String content;


    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public ForumPostVo getForumPost() {
        return forumPost;
    }

    public void setForumPost(ForumPostVo forumPost) {
        this.forumPost = forumPost;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }
}
