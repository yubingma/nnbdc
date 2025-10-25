package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;
import javax.persistence.UniqueConstraint;

/**
 * 用户数据库版本表
 */
@Entity
@Table(name = "user_db_version", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"userId"})
})
public class UserDbVersion extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false)
    private User user;

    @Column(name = "version", nullable = false)
    private Integer version;

    public UserDbVersion() {
    }

    public UserDbVersion(User user, Integer version) {
        this.user = user;
        this.version = version;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Integer getVersion() {
        return version;
    }

    public void setVersion(Integer version) {
        this.version = version;
    }
}
