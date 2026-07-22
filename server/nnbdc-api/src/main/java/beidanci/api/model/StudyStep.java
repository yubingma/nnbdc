package beidanci.api.model;

public enum StudyStep {
    List("单词列表"),
    En2Ch("英→中"),
    Ch2En("中→英"),
    EnSentence2Ch("例句英→中"),
    ChSentence2En("例句中→英");

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
