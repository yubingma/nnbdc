package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "sentence")
public class Sentence extends UuidPo {

    /**
     * 原声例句(音频)
     */
    public static final String HUMAN_AUDIO = "human_audio";


    /**
     * TTS例句(现在TTS的质量已经非常接近真人了)
     */
    public static final String TTS = "tts";

    /**
     * 正在等待tts配音的例句
     */
    public static final String WAITTING_TTS = "waitting_tts";

    @Column(name = "English", length = 300)
    private String english;

    @Column(name = "chinese", length = 300)
    private String chinese;

    @Column(name = "wordMeaning", length = 300)
    private String wordMeaning;

    @Column(name = "TheType", length = 45)
    private String theType;

    @Column(name = "englishDigest", length = 32)
    private String englishDigest;

    @Column(name = "LastDiyUpdateTime")
    private Date lastDiyUpdateTime;

    @Column(name = "producer", length = 20)
    private String soundProducer;

    @Column(name = "needTts")
    private Boolean needTts;

    @Column(name = "footCount")
    private Integer footCount = 0;

    @Column(name = "handCount")
    private Integer handCount = 0;

    @ManyToOne
    @JoinColumn(name = "authorId", nullable = false)
    private User author;

    @ManyToOne
    @JoinColumn(name = "meaningItemId", nullable = false)
    private MeaningItem meaningItem;

    @Column(name = "popularity")
    private Integer popularity = 1;

    @Column(name = "partOfSpeech", length = 10)
    private String partOfSpeech;

    public String getSoundProducer() {
        return soundProducer;
    }

    public void setSoundProducer(String soundProducer) {
        this.soundProducer = soundProducer;
    }

    public Boolean getNeedTts() {
        return needTts;
    }

    public void setNeedTts(Boolean needTts) {
        this.needTts = needTts;
    }

    public String getWordMeaning() {
        return wordMeaning;
    }

    public void setWordMeaning(String wordMeaning) {
        this.wordMeaning = wordMeaning;
    }

    public User getAuthor() {
        return author;
    }

    public void setAuthor(User author) {
        this.author = author;
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
    // Constructors

    /**
     * default constructor
     */
    public Sentence() {

    }

    /**
     * minimal constructor
     */
    public Sentence(String english, User author) {
        this.english = english;
        this.author = author;
    }

    /**
     * full constructor
     */
    public Sentence(String english, String type) {
        this.english = english;
        this.theType = type;
    }

    public MeaningItem getMeaningItem() {
        return meaningItem;
    }

    public void setMeaningItem(MeaningItem meaningItem) {
        this.meaningItem = meaningItem;
    }

    public String getEnglish() {
        return this.english;
    }

    public void setEnglish(String english) {
        this.english = english;
    }

    public String getTheType() {
        return this.theType;
    }

    public void setTheType(String type) {
        this.theType = type;
    }

    public String getEnglishDigest() {
        return englishDigest;
    }

    public void setEnglishDigest(String digest) {
        this.englishDigest = digest;
    }

    public Date getLastDiyUpdateTime() {
        return lastDiyUpdateTime;
    }

    public void setLastDiyUpdateTime(Date lastDiyUpdateTime) {
        this.lastDiyUpdateTime = lastDiyUpdateTime;
    }

    public String getChinese() {
        return chinese;
    }

    public void setChinese(String chinese) {
        this.chinese = chinese;
    }

    public Integer getPopularity() {
        return popularity;
    }

    public void setPopularity(Integer popularity) {
        this.popularity = popularity;
    }

    public String getPartOfSpeech() {
        return partOfSpeech;
    }

    public void setPartOfSpeech(String partOfSpeech) {
        this.partOfSpeech = partOfSpeech;
    }
}
