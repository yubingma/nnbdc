package beidanci.service.po;

import java.util.ArrayList;
import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

// JDBC 不再支持 Hibernate 缓存和 Fetch 注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;
// import org.hibernate.annotations.Fetch;
// import org.hibernate.annotations.FetchMode;

/**
 * 单词的释义
 *
 * @author MaYubing
 */
@Entity
@Table(name = "meaning_item")
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class MeaningItem extends UuidPo {
    
    // no Java serialization


    /**
     * 释义所属单词
     */
    @Column(name = "word_id")
    private Word word;

    /**
     * 单词词性
     */
    @Column(name = "ci_xing", length = 10)
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
    // @Fetch(FetchMode.SUBSELECT)  // JDBC 不支持
    // @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
    private List<Synonym> synonyms = new ArrayList<>();

    /**
     * 例句
     */
    // @Fetch(FetchMode.SUBSELECT)  // JDBC 不支持
    // @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
    private List<Sentence> sentences = new ArrayList<>();

    @Column(name = "dict_id")
    private Dict dict;

    /**
     * 释义的所有者（用户）。
     * 1. 性能优化：在拉取单词释义时，可直接通过 owner_id 过滤（公共资源 + 我的私有资源），避免通过词书表进行复杂的跨表 JOIN。
     * 2. UGC 隔离：支持用户在公共词书下记录仅自己可见的私有解释或笔记。
     * 归属规则：
     * - 系统/共享资源：归属于系统管理员 (Constants.SYS_USER_SYS_ID，即 "15118")。
     * - 用户私有资源：归属于该特定的学习用户。
     */
    @Column(name = "owner_id", nullable = false)
    private User owner;

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

    public User getOwner() {
        return owner;
    }

    public void setOwner(User owner) {
        this.owner = owner;
    }
}
