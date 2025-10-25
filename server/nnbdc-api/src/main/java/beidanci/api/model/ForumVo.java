package beidanci.api.model;

import java.util.List;

public class ForumVo extends UuidVo {

    private String name;

    private List<UserVo> managers;

    private List<ForumPostVo> forumPosts;


    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public List<UserVo> getManagers() {
        return managers;
    }

    public void setManagers(List<UserVo> managers) {
        this.managers = managers;
    }

    public List<ForumPostVo> getForumPosts() {
        return forumPosts;
    }

    public void setForumPosts(List<ForumPostVo> forumPosts) {
        this.forumPosts = forumPosts;
    }
}
