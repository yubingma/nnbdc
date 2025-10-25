package beidanci.api.model;

import java.util.List;

/**
 * Created by Administrator on 2015/11/29.
 */
public class DictVo extends UuidVo {
    private String name;
    private String shortName;
    private UserVo owner;
    /**
     * 对于用户自定义的单词书，该标志指明该单词书是否已经共享给其他用户
     */
    private Boolean isShared;
    /**
     * 该单词书是否已经准备就绪（只有准备就绪的单词书才能供用户使用，并且一旦就绪后就不能再编辑）
     */
    private Boolean isReady;
    private Boolean visible;
    private List<DictWordVo> dictWords;
    /**
     * 该单词书的单词数量
     */
    private Integer wordCount;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }


    public Boolean getVisible() {
        return visible;
    }

    public void setVisible(Boolean visible) {
        this.visible = visible;
    }

    public List<DictWordVo> getDictWords() {
        return dictWords;
    }

    public void setDictWords(List<DictWordVo> dictWords) {
        this.dictWords = dictWords;
    }

    public String getShortName() {
        return shortName;
    }

    public void setShortName(String shortName) {
        this.shortName = shortName;
    }

    public Integer getWordCount() {
        return wordCount;
    }

    public void setWordCount(Integer wordCount) {
        this.wordCount = wordCount;
    }

    public UserVo getOwner() {
        return owner;
    }

    public void setOwner(UserVo owner) {
        this.owner = owner;
    }

    public Boolean getIsShared() {
        return isShared;
    }

    public void setIsShared(Boolean isShared) {
        this.isShared = isShared;
    }

    public Boolean getIsReady() {
        return isReady;
    }

    public void setIsReady(Boolean isReady) {
        this.isReady = isReady;
    }

}
