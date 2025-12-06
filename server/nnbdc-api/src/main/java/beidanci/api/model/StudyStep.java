package beidanci.api.model;

public enum StudyStep {
    En2Ch("英→中"),
    Ch2En("中→英");

    private String description;

    private StudyStep(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public static StudyStep fromDescription(String description) {
        for (StudyStep studyStep : StudyStep.values()) {
            if (studyStep.description.equalsIgnoreCase(description)) {
                return studyStep;
            }
        }
        return null;
    }
}
