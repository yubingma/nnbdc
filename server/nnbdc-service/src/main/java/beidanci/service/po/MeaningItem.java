package beidanci.service.po;

import java.util.ArrayList;
import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.Table;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;
import org.hibernate.annotations.Fetch;
import org.hibernate.annotations.FetchMode;

/**
 * 单词的释义
 *
 * @author MaYubing
 */
@Entity
@Table(name = "meaning_item")
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class MeaningItem extends UuidPo {
    
    // no Java serialization


    /**
     * 释义所属单词
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "wordId")
    private Word word;

    /**
     * 单词词性
     */
    @Column(name = "ciXing", length = 10)
    private String ciXing;

    /**
     * 释义
     */
    @Column(name = "meaning", length = 500)
    private String meaning;

    /** 常用度 */
    @Column(name = "popularity", length = 10)
    private Integer popularity;

    /**
     * 近义词
     */
    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE}, mappedBy = "meaningItem")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private List<Synonym> synonyms = new ArrayList<>();

    /**
     * 例句
     */
    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE}, mappedBy = "meaningItem")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private List<Sentence> sentences = new ArrayList<>();

    @ManyToOne
    @JoinColumn(name = "dictId", updatable = false, insertable = false)
    private Dict dict;

    public MeaningItem() {

    }

    public MeaningItem(String ciXing, String meaning) {
        this.ciXing = ciXing;
        this.meaning = meaning;

    }

    @Override
    public String toString() {
        String meaningStr = meaning;
        if (!meaningStr.endsWith(";") && !meaningStr.endsWith("；")) {
            meaningStr += "；";
        }

        return String.format("%s %s", ciXing, meaningStr);
    }

    public List<Sentence> getSentences() {
        return sentences;
    }

    public void setSentences(List<Sentence> sentences) {
        this.sentences = sentences;
    }

    public String getCiXing() {
        return ciXing;
    }

    public void setCiXing(String ciXing) {
        this.ciXing = ciXing;
    }

    public String getMeaning() {
        return meaning;
    }

    public void setMeaning(String meaning) {
        this.meaning = meaning;
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public List<Synonym> getSynonyms() {
        return synonyms;
    }

    public void setSynonyms(List<Synonym> synonyms) {
        this.synonyms = synonyms;
    }

    public Dict getDict() {
        return dict;
    }

    public void setDict(Dict dict) {
        this.dict = dict;
    }

    public Integer getPopularity() {
        return popularity;
    }

    public void setPopularity(Integer popularity) {
        this.popularity = popularity;
    }
}
