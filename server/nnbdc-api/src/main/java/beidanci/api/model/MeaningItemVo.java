package beidanci.api.model;

import java.util.ArrayList;
import java.util.List;

/**
 * For example, word "face" has 3 meaning items, as below:
 * <ul>
 * <li>n.面容； 表面； 脸； 方面</li>
 * <li>vt.& vi.面对； 面向…； 正视； 承认</li>
 * <li>vt.（感到不能）对付； （明知不好办而）交谈； 必须对付（某情况）； 面临…</li>
 * <ul>
 * <br>
 *
 * @author Administrator
 */
public class MeaningItemVo extends UuidVo {

    // no Java serialization
    private String ciXing;
    private String meaning;
    private DictVo dict;
    private List<SynonymVo> synonyms;
    private List<SentenceVo> sentences = new ArrayList<>();

    public MeaningItemVo() {

    }

    public MeaningItemVo(String ciXing, String meaning) {
        this.ciXing = ciXing;
        this.meaning = meaning;

    }

    public List<SentenceVo> getSentences() {
        return sentences;
    }

    public void setSentences(List<SentenceVo> sentences) {
        this.sentences = sentences;
    }

    public DictVo getDict() {
        return dict;
    }

    public void setDict(DictVo dict) {
        this.dict = dict;
    }

    public List<SynonymVo> getSynonyms() {
        return synonyms;
    }

    public void setSynonyms(List<SynonymVo> synonyms) {
        this.synonyms = synonyms;
    }

    @Override
    public String toString() {
        String meaningStr = meaning;
        if (!meaningStr.endsWith(";") && !meaningStr.endsWith("；")) {
            meaningStr += "；";
        }

        return String.format("%s %s", ciXing, meaningStr);
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
}
