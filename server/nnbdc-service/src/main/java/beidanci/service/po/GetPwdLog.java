package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "get_pwd_log")
public class GetPwdLog extends UuidPo {

    @Column(name = "toEmail", length = 100)
    private String toEmail;

    @Column(name = "sendTime")
    private Date sendTime;

    @Column(name = "content", length = 4000)
    private String content;

    @Column(name = "result", length = 4000)
    private String result;

    // Constructors

    /**
     * default constructor
     */
    public GetPwdLog() {
    }

    public GetPwdLog(String toEmail, Date sendTime, String content, String result) {
        this.toEmail = toEmail;
        this.sendTime = sendTime;
        this.content = content;
        this.result = result;
    }

    public String getToEmail() {
        return toEmail;
    }

    public void setToEmail(String toEmail) {
        this.toEmail = toEmail;
    }

    public Date getSendTime() {
        return sendTime;
    }

    public void setSendTime(Date sendTime) {
        this.sendTime = sendTime;
    }

    public String getContent() {
        return this.content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public String getResult() {
        return this.result;
    }

    public void setResult(String result) {
        this.result = result;
    }

}
