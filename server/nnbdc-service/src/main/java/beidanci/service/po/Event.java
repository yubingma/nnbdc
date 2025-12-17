package beidanci.service.po;

import beidanci.api.model.EventType;

import javax.persistence.*;

@Entity
@Table(name = "event")
public class Event extends UuidPo {


    @Enumerated(EnumType.STRING)
    @Column(name = "event_type", nullable = false, length = 30)
    private EventType eventType;

    @Column(name = "user_id")
    private User user;

    @Column(name = "word_image_id")
    private WordImage wordImage;

    public Sentence getSentence() {
        return sentence;
    }

    public void setSentence(Sentence sentence) {
        this.sentence = sentence;
    }

    @Column(name = "sentence_id")
    private Sentence sentence;

    @Column(name = "word_short_desc_chinese_id")
    private WordShortDescChinese wordShortDescChinese;

    public Event(EventType eventType, User user, WordImage wordImage) {
        this.eventType = eventType;
        this.user = user;
        this.wordImage = wordImage;
    }

    public Event(EventType eventType, User user, Sentence sentence) {
        this.eventType = eventType;
        this.user = user;
        this.sentence = sentence;
    }

    public Event(EventType eventType, User user, WordShortDescChinese wordShortDescChinese) {
        this.eventType = eventType;
        this.user = user;
        this.wordShortDescChinese = wordShortDescChinese;
    }

    public Event() {

    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public WordImage getWordImage() {
        return wordImage;
    }

    public void setWordImage(WordImage wordImage) {
        this.wordImage = wordImage;
    }

    public EventType getEventType() {
        return eventType;
    }

    public void setEventType(EventType eventType) {
        this.eventType = eventType;
    }

    public WordShortDescChinese getWordShortDescChinese() {
        return wordShortDescChinese;
    }

    public void setWordShortDescChinese(WordShortDescChinese wordShortDescChinese) {
        this.wordShortDescChinese = wordShortDescChinese;
    }
}
