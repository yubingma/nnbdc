package beidanci.api.model;

import java.util.Date;

/**
 * Created by Administrator on 2015/12/4.
 */
public class UpdateLogVo extends Vo {
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

    private String content;
}
