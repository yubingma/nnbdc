package beidanci.api.model;

public class VerbTenseVo extends UuidVo {


    private WordVo word;

    /**
     * 时态的类型
     */
    private TenseType tenseType;

    private String tensedSpell;


    public WordVo getWord() {
        return word;
    }

    public void setWord(WordVo word) {
        this.word = word;
    }

    public TenseType getTenseType() {
        return tenseType;
    }

    public void setTenseType(TenseType tenseType) {
        this.tenseType = tenseType;
    }

    public String getTensedSpell() {
        return tensedSpell;
    }

    public void setTensedSpell(String tensedSpell) {
        this.tensedSpell = tensedSpell;
    }

}
