package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 版本更新记录
 */
@Entity
@Table(name = "update_log")
public class UpdateLog extends UuidPo {

    @Column(name = "time", nullable = false)
    private Date time;

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Date getTime() {
        return time;
    }

    public void setTime(Date time) {
        this.time = time;
    }

    @Column(name = "content", nullable = false)
    private String content;
}
