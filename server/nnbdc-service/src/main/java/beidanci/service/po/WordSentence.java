package beidanci.service.po;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

@Entity
@Table(name = "word_sentence")
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class WordSentence extends Po {
    @Id
    private WordSentenceId id;

    @ManyToOne
    @JoinColumn(name = "wordId", nullable = false, updatable = false, insertable = false)
    private Word word;

    @ManyToOne
    @JoinColumn(name = "sentenceId", nullable = false, updatable = false, insertable = false)
    private Sentence sentence;

    public Sentence getSentence() {
        return sentence;
    }

    public WordSentence() {
    }

    public WordSentence(WordSentenceId id) {
        this.id = id;
    }

    public void setSentence(Sentence sentence) {
        this.sentence = sentence;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }


    public WordSentenceId getId() {
        return id;
    }

    public void setId(WordSentenceId id) {
        this.id = id;
    }
}
