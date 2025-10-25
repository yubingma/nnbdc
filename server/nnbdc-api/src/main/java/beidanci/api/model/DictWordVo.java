package beidanci.api.model;

public class DictWordVo extends Vo {
    private DictVo dict;

    private WordVo word;

    /**
     * 单词在单词书中的顺序号，从1开始
     */
    private Integer seq;

    public DictVo getDict() {
        return dict;
    }

    public void setDict(DictVo dict) {
        this.dict = dict;
    }

    public WordVo getWord() {
        return word;
    }

    public void setWord(WordVo word) {
        this.word = word;
    }

    public Integer getSeq() {
        return seq;
    }

    public void setSeq(Integer seq) {
        this.seq = seq;
    }
}
