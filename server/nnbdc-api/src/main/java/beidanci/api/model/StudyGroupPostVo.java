package beidanci.api.model;

import java.util.Date;
import java.util.List;

public class StudyGroupPostVo extends UuidVo {

    private UserVo user;

    private StudyGroupVo studyGroup;

    private String postTitle;

    private String postContent;

    private Integer replyCount;

    private Integer browseCount;

    private Date lastReplyTime;

    private List<StudyGroupPostReplyVo> studyGroupPostReplies;


    public UserVo getUser() {
        return user;
    }

    public void setUser(UserVo user) {
        this.user = user;
    }

    public StudyGroupVo getStudyGroup() {
        return studyGroup;
    }

    public void setStudyGroup(StudyGroupVo studyGroup) {
        this.studyGroup = studyGroup;
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

    public List<StudyGroupPostReplyVo> getStudyGroupPostReplies() {
        return studyGroupPostReplies;
    }

    public void setStudyGroupPostReplies(List<StudyGroupPostReplyVo> studyGroupPostReplies) {
        this.studyGroupPostReplies = studyGroupPostReplies;
    }
}
