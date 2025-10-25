package beidanci.api.model;

import java.util.Objects;

/**
 * 某个单词释义的一个同义词
 *
 * @author MaYubing
 */
public class SynonymVo extends Vo {

    /**
     * 本单词的一个释义项
     */
    private MeaningItemVo meaningItem;

    /**
     * 近义词的ID
     */
    private String wordId;
    /**
     * 近义词的拼写
     */
    private String spell;

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }

    public MeaningItemVo getMeaningItem() {
        return meaningItem;
    }

    public void setMeaningItem(MeaningItemVo meaningItem) {
        this.meaningItem = meaningItem;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        SynonymVo synonymVo = (SynonymVo) o;
        return wordId.equals(synonymVo.wordId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(wordId);
    }
}
