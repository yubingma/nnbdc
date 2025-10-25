package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

import beidanci.api.model.DictWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.store.WordCache;

@Entity
@Table(name = "dict_word", indexes = {
        @Index(name = "idx_dict_seq", columnList = "dictId,seq", unique = false)})
public class DictWord extends Po  {

    public DictWord() {

    }

    @Id
    private DictWordId id;

    @ManyToOne
    @JoinColumn(name = "dictId", nullable = false, updatable = false, insertable = false)
    private Dict dict;

    @ManyToOne
    @JoinColumn(name = "wordId", nullable = false, updatable = false, insertable = false)
    private Word word;

    /**
     * 单词在单词书中的顺序号，从1开始
     */
    @Column(name = "seq", nullable = true)
    private Integer seq;

    public Integer getSeq() {
        return seq;
    }

    public void setSeq(Integer seq) {
        this.seq = seq;
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
        dictWord.setCreateTime(dto.getCreateTime());
        dictWord.setUpdateTime(dto.getUpdateTime());

        return dictWord;
    }
}
