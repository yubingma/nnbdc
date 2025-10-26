package beidanci.api.model;

/**
 * 诊断问题数据 - 用于传输诊断结果中的问题信息
 */
public class DiagnosticIssue {
    private String type;
    private String description;
    private String category;

    public DiagnosticIssue() {
    }

    public DiagnosticIssue(String type, String description, String category) {
        this.type = type;
        this.description = description;
        this.category = category;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }
}
