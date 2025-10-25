package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

/**
 * 记录用户数据库同步中的异常情况（例如生词本顺序异常）
 */
@Entity
@Table(name = "user_db_issue")
public class UserDbIssue extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false)
    private User user;

    @Column(name = "issueType", nullable = false, length = 64)
    private String issueType;

    @Column(name = "details", nullable = true, length = 2000)
    private String details;

    public UserDbIssue() {
    }

    public UserDbIssue(User user, String issueType, String details) {
        this.user = user;
        this.issueType = issueType;
        this.details = details;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String getIssueType() {
        return issueType;
    }

    public void setIssueType(String issueType) {
        this.issueType = issueType;
    }

    public String getDetails() {
        return details;
    }

    public void setDetails(String details) {
        this.details = details;
    }
}


