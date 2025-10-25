package beidanci.api.model;

/**
 * 动词的时态类型
 *
 * @author MaYubing
 */
public enum TenseType {
    PastTense("过去式"), PastParticiple("过去分词"), PresentParticiple("现在分词");

    private String description;

    private TenseType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
