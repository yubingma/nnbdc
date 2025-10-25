package beidanci.api.model;

public class BatchImportResult {
    private int successCount;
    private int failedCount;

    /**
     * 要导入的单词已在生词本中，则忽略之
     */
    private int ignoredCount;

    private String[] failedWords;
    private String[] failedReasons;

    public int getSuccessCount() {
        return successCount;
    }

    public void setSuccessCount(int successCount) {
        this.successCount = successCount;
    }

    public int getFailedCount() {
        return failedCount;
    }

    public void setFailedCount(int failedCount) {
        this.failedCount = failedCount;
    }

    public String[] getFailedWords() {
        return failedWords;
    }

    public void setFailedWords(String[] failedWords) {
        this.failedWords = failedWords;
    }

    public String[] getFailedReasons() {
        return failedReasons;
    }

    public void setFailedReasons(String[] failedReasons) {
        this.failedReasons = failedReasons;
    }

    public int getIgnoredCount() {
        return ignoredCount;
    }

    public void setIgnoredCount(int ignoredCount) {
        this.ignoredCount = ignoredCount;
    }
}
