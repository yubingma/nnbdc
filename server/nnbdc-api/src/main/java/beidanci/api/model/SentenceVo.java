package beidanci.api.model;

import java.util.Objects;

/**
 * For example, this is a example sentence:
 * <p>
 * On the face of it, this story seems unconvincing. <br>
 * 表面上看来，这个故事似乎令人难以置信。
 *
 * @author Administrator
 */
public class SentenceVo extends UuidVo {


    private String english;
    private String chinese;
    private String wordMeaning;

    private String englishDigest;

    private String theType;
    private Integer footCount;
    private Integer handCount;
    private UserVo author;

    public SentenceVo() {

    }

    public SentenceVo(String id, String english, String chinese, String type, String englishDigest,
                      int handCount, int footCount, UserVo author) {
        this.id = id;
        this.english = english;
        this.englishDigest = englishDigest;
        this.theType = type;
        this.handCount = handCount;
        this.footCount = footCount;
        this.author = author;
        this.chinese = chinese;
    }

    @Override
    public String getId() {
        return id;
    }

    @Override
    public void setId(String id) {
        this.id = id;
    }

    public Integer getFootCount() {
        return footCount;
    }

    public void setFootCount(Integer footCount) {
        this.footCount = footCount;
    }

    public Integer getHandCount() {
        return handCount;
    }

    public void setHandCount(Integer handCount) {
        this.handCount = handCount;
    }

    public UserVo getAuthor() {
        return author;
    }

    public void setAuthor(UserVo author) {
        this.author = author;
    }

    @Override
    public String toString() {
        return String.format("{%s}", english);
    }

    public String getEnglish() {
        return english;
    }

    public void setEnglish(String english) {
        this.english = english;
    }

    public String getTheType() {
        return theType;
    }

    public void setTheType(String type) {
        this.theType = type;
    }

    public String getEnglishDigest() {
        return englishDigest;
    }

    public void setEnglishDigest(String englishDigest) {
        this.englishDigest = englishDigest;
    }


    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        SentenceVo that = (SentenceVo) o;
        return Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    public String getChinese() {
        return chinese;
    }

    public void setChinese(String chinese) {
        this.chinese = chinese;
    }

    public String getWordMeaning() {
        return wordMeaning;
    }

    public void setWordMeaning(String wordMeaning) {
        this.wordMeaning = wordMeaning;
    }


}
