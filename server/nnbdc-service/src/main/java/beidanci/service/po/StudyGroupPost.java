package beidanci.service.po;

import java.sql.Timestamp;
import java.util.Date;
import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.OrderBy;
import javax.persistence.Table;

@Entity
@Table(name = "study_group_post")
public class StudyGroupPost extends UuidPo {


    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "postCreatorId")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "groupId")
    private StudyGroup studyGroup;

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

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "studyGroupPost", fetch = FetchType.LAZY)
    @OrderBy("updateTime asc")
    private List<StudyGroupPostReply> studyGroupPostReplies;

    /**
     * default constructor
     */
    public StudyGroupPost() {
    }

    /**
     * minimal constructor
     */
    public StudyGroupPost(String id, User user, StudyGroup studyGroup, String postTitle, String postContent,
                          Integer replyCount, Timestamp lastReplyTime) {
        this.id = id;
        this.user = user;
        this.studyGroup = studyGroup;
        this.postTitle = postTitle;
        this.postContent = postContent;
        this.replyCount = replyCount;
        this.lastReplyTime = lastReplyTime;
    }

    /**
     * full constructor
     */
    public StudyGroupPost(String id, User user, StudyGroup studyGroup, String postTitle, String postContent,
                          Integer replyCount, Timestamp lastReplyTime, List<StudyGroupPostReply> studyGroupPostReplies) {
        this.id = id;
        this.user = user;
        this.studyGroup = studyGroup;
        this.postTitle = postTitle;
        this.postContent = postContent;
        this.replyCount = replyCount;
        this.lastReplyTime = lastReplyTime;
        this.studyGroupPostReplies = studyGroupPostReplies;
    }


    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public StudyGroup getStudyGroup() {
        return this.studyGroup;
    }

    public void setStudyGroup(StudyGroup studyGroup) {
        this.studyGroup = studyGroup;
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

    public List<StudyGroupPostReply> getStudyGroupPostReplies() {
        return studyGroupPostReplies;
    }

    public void setStudyGroupPostReplies(List<StudyGroupPostReply> studyGroupPostReplies) {
        this.studyGroupPostReplies = studyGroupPostReplies;
    }
}
