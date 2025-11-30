package beidanci.api.model;

import java.io.Serializable;

/**
 * 消息数量 VO
 * 用于返回消息总数和未读数量
 */
public class MsgCountVo implements Serializable {
    private static final long serialVersionUID = 1L;

    private Integer first;
    private Integer second;

    public MsgCountVo() {
    }

    public MsgCountVo(Integer first, Integer second) {
        this.first = first;
        this.second = second;
    }

    public Integer getFirst() {
        return first;
    }

    public void setFirst(Integer first) {
        this.first = first;
    }

    public Integer getSecond() {
        return second;
    }

    public void setSecond(Integer second) {
        this.second = second;
    }
}

