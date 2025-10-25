package beidanci.api.model;

public class SearchWordResult {
    private WordVo word;

    public Boolean getIsInMySelectedDicts() {
        return isInMySelectedDicts;
    }


    public void setIsInMySelectedDicts(Boolean isInMySelectedDicts) {
        this.isInMySelectedDicts = isInMySelectedDicts;
    }

    /**
     * 我目前学习的词书中是否包含该单词？
     */
    private Boolean isInMySelectedDicts;

    /**
     * 我的生词本中是否包含该单词？
     */
    private Boolean isInRawWordDict;


    public SearchWordResult(WordVo word, String soundPath,
                            Boolean isInMySelectedDicts, boolean isInRawWordDict) {
        super();
        this.word = word;
        this.soundPath = soundPath;
        this.isInMySelectedDicts = isInMySelectedDicts;
        this.isInRawWordDict = isInRawWordDict;
    }

    public Boolean getIsInRawWordDict() {
        return isInRawWordDict;
    }

    public void setIsInRawWordDict(Boolean inRawWordDict) {
        isInRawWordDict = inRawWordDict;
    }

    private String soundPath;

    public WordVo getWord() {
        return word;
    }

    public void setWord(WordVo word) {
        this.word = word;
    }

    public String getSound() {
        return soundPath;
    }

    public void setSound(String soundPath) {
        this.soundPath = soundPath;
    }
}
