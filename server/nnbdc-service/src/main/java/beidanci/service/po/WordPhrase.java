package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.Table;

/**
 * 单词的常用短语搭配（柯林斯词典来源）。
 *
 * 与 word 表里 spell 含空格的「短语词条」是两个不同概念：本表内容是单词的附属参考内容，
 * 在单词详情页展示，不是可独立背诵的学习单元。
 */
@Entity
@Table(name = "word_phrase", indexes = {
    @Index(name = "uk_word_phrase_word_phrase", columnList = "word_id, phrase", unique = true)
})
public class WordPhrase extends UuidPo {

    @Column(name = "word_id", length = 32, nullable = false)
    private String wordId;

    @Column(name = "phrase", length = 200, nullable = false)
    private String phrase;

    @Column(name = "part_of_speech", length = 20)
    private String partOfSpeech;

    @Column(name = "meaning_cn", length = 500)
    private String meaningCn;

    @Column(name = "meaning_en", length = 1000)
    private String meaningEn;

    @Column(name = "example_en", length = 500)
    private String exampleEn;

    @Column(name = "example_cn", length = 500)
    private String exampleCn;

    @Column(name = "source", length = 20, nullable = false)
    private String source;

    @Column(name = "display_index", nullable = false)
    private Integer displayIndex = 0;

    public WordPhrase() {
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getPhrase() {
        return phrase;
    }

    public void setPhrase(String phrase) {
        this.phrase = phrase;
    }

    public String getPartOfSpeech() {
        return partOfSpeech;
    }

    public void setPartOfSpeech(String partOfSpeech) {
        this.partOfSpeech = partOfSpeech;
    }

    public String getMeaningCn() {
        return meaningCn;
    }

    public void setMeaningCn(String meaningCn) {
        this.meaningCn = meaningCn;
    }

    public String getMeaningEn() {
        return meaningEn;
    }

    public void setMeaningEn(String meaningEn) {
        this.meaningEn = meaningEn;
    }

    public String getExampleEn() {
        return exampleEn;
    }

    public void setExampleEn(String exampleEn) {
        this.exampleEn = exampleEn;
    }

    public String getExampleCn() {
        return exampleCn;
    }

    public void setExampleCn(String exampleCn) {
        this.exampleCn = exampleCn;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public Integer getDisplayIndex() {
        return displayIndex;
    }

    public void setDisplayIndex(Integer displayIndex) {
        this.displayIndex = displayIndex;
    }
}
