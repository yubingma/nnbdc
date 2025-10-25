package beidanci.api.model;

public enum StudyStepState {
    Active("激活"), Inactive("非激活");

    private String description;

    private StudyStepState(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
