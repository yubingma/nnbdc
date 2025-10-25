package beidanci.api.model;

public class ErrorReportVo extends UuidVo {
    public ErrorReportVo(String id, String createdBy, String createdByNickname, String content, String spell,
            boolean fixed) {
        super();
        this.id = id;
        this.createdBy = createdBy;
        this.createdByNickName = createdByNickname;
        this.content = content;
        this.word = spell;
        this.fixed = fixed;
    }

    private final String createdBy;
    private final String createdByNickName;
    private final String content;
    private String word;
    private Boolean fixed;

    public Boolean getFixed() {
        return fixed;
    }

    public void setFixed(Boolean fixed) {
        this.fixed = fixed;
    }

    @Override
    public String getId() {
        return id;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public String getCreatedByNickName() {
        return createdByNickName;
    }

    public String getContent() {
        return content;
    }

    public String getWord() {
        return word;
    }

    public void setWord(String word) {
        this.word = word;
    }
}
