package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "login_log")
public class LoginLog extends UuidPo {

    public LoginLog() {
    }

    public LoginLog(User user, Date loginTime) {
        this.user = user;
        this.loginTime = loginTime;
    }


    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Date getLoginTime() {
        return loginTime;
    }

    public void setLoginTime(Date loginTime) {
        this.loginTime = loginTime;
    }

    @Column(name = "user_id")
    private User user;

    @Column(name = "login_time", nullable = false)
    private Date loginTime;
}
