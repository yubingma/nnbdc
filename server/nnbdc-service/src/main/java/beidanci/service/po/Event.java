package beidanci.service.po;

import beidanci.api.model.EventType;

import javax.persistence.*;

@Entity
@Table(name = "event")
public class Event extends UuidPo {


    @Enumerated(EnumType.STRING)
    @Column(name = "eventType", nullable = false, length = 30)
    private EventType eventType;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false)
    private User user;

    @ManyToOne
    @JoinColumn(name = "wordImage", nullable = true)
    private WordImage wordImage;

    public Sentence getSentence() {
        return sentence;
    }

    public void setSentence(Sentence sentence) {
        this.sentence = sentence;
    }

    @ManyToOne
    @JoinColumn(name = "sentence", nullable = true)
    private Sentence sentence;

    @ManyToOne
    @JoinColumn(name = "wordShortDescChinese", nullable = true)
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
