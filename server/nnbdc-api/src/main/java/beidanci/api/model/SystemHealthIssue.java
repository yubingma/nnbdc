package beidanci.api.model;

/**
 * 系统健康问题
 */
public class SystemHealthIssue {
    private String type;
    private String description;
    private String category;

    public SystemHealthIssue() {
    }

    public SystemHealthIssue(String type, String description, String category) {
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
