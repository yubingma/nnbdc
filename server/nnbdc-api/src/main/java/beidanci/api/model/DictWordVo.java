package beidanci.api.model;

public class DictWordVo extends Vo {
    private DictVo dict;

    private WordVo word;

    /**
     * 单词在单词书中的顺序号，从1开始
     */
    private Integer seq;

    /**
     * 单词所属单元序号，0 表示无单元
     */
    private Integer unit;

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

    public Integer getUnit() {
        return unit;
    }

    public void setUnit(Integer unit) {
        this.unit = unit;
    }
}
