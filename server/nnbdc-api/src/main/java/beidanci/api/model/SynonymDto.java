package beidanci.api.model;

public class SynonymDto extends Dto {
    /**
     * 本单词的一个释义项
     */
    private String meaningItemId;

    /**
     * 近义词的ID
     */
    private String wordId;

    private String spell;

    public String getMeaningItemId() {
        return meaningItemId;
    }

    public void setMeaningItemId(String meaningItemId) {
        this.meaningItemId = meaningItemId;
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }
}
