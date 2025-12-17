package beidanci.service.po;

// JDBC 不再支持 Hibernate 缓存注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

@Entity
@Table(name = "word_sentence")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class WordSentence extends Po {
    @Id
    private WordSentenceId id;

    @Column(name = "word_id")
    private Word word;

    @Column(name = "sentence_id")
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
