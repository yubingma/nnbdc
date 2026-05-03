package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.DictWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.store.WordCache;

@Entity
@Table(name = "dict_word", indexes = {
        @Index(name = "idx_dict_seq", columnList = "dict_id, seq", unique = false)})
public class DictWord extends Po  {

    public DictWord() {

    }

    @Id
    private DictWordId id;

    @Column(name = "dict_id")
    private Dict dict;

    @Column(name = "word_id")
    private Word word;

    /**
     * 单词在单词书中的顺序号，从1开始
     */
    @Column(name = "seq", nullable = true)
    private Integer seq;

    /**
     * 单词所属单元序号，0 表示无单元
     */
    @Column(name = "unit", nullable = false)
    private Integer unit = 0;

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

    public DictWordId getId() {
        return id;
    }

    public void setId(DictWordId id) {
        this.id = id;
    }

    public Dict getDict() {
        return dict;
    }

    public void setDict(Dict dict) {
        this.dict = dict;
    }

    public WordVo getWordVo(WordCache wordCache, String[] excludeFields)  {
        return wordCache.getWordById(id.getWordId(), excludeFields);
    }

    public Word getWord() {
        return word;
    }

    public void setWord(Word word) {
        this.word = word;
    }

    public static DictWord fromDto(DictWordDto dto) {
        DictWord dictWord = new DictWord();

        // 设置复合主键
        DictWordId id = new DictWordId(dto.getDictId(), dto.getWordId());
        dictWord.setId(id);

        // 设置其他属性
        dictWord.setSeq(dto.getSeq());
        dictWord.setUnit(dto.getUnit() != null ? dto.getUnit() : 0);
        dictWord.setCreateTime(dto.getCreateTime());
        dictWord.setUpdateTime(dto.getUpdateTime() != null ? dto.getUpdateTime() : dto.getCreateTime());

        return dictWord;
    }
}
