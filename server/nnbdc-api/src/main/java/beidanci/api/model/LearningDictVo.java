package beidanci.api.model;

/**
 * Created by Administrator on 2015/11/29.
 */
public class LearningDictVo extends Vo {

    private DictVo dict;
    private Integer currentWordSeq;
    private boolean isPrivileged;

    public DictVo getDict() {
        return dict;
    }

    public void setDict(DictVo dict) {
        this.dict = dict;
    }

    public Integer getCurrentWordSeq() {
        return currentWordSeq;
    }

    public void setCurrentWordSeq(Integer currentWordSeq) {
        this.currentWordSeq = currentWordSeq;
    }

    public boolean getIsPrivileged() {
        return isPrivileged;
    }

    public void setIsPrivileged(boolean privileged) {
        isPrivileged = privileged;
    }
}
