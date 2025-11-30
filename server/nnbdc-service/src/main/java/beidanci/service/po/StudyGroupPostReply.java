package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "study_group_post_reply")
public class StudyGroupPostReply extends UuidPo {


    private User user;

    private StudyGroupPost studyGroupPost;

    @Column(name = "content", length = 1048576, nullable = false)
    private String content;

    // Constructors

    /**
     * default constructor
     */
    public StudyGroupPostReply() {
    }


    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public StudyGroupPost getStudyGroupPost() {
        return this.studyGroupPost;
    }

    public void setStudyGroupPost(StudyGroupPost studyGroupPost) {
        this.studyGroupPost = studyGroupPost;
    }

    public String getContent() {
        return this.content;
    }

    public void setContent(String content) {
        this.content = content;
    }

}
