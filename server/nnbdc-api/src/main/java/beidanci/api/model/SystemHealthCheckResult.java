package beidanci.api.model;

import java.util.List;

/**
 * 系统健康检查结果
 */
public class SystemHealthCheckResult {
    private boolean isHealthy;
    private List<SystemHealthIssue> issues;
    private List<String> errors;

    /**
     * 可选：可逐词修复的明细（目前只有「学习进度与学习记录一致性」体检会填）。
     * 其余检查项为空列表。加在这里而不是新开一个接口，是为了让一次体检就能同时拿到
     * "有哪些问题"与"哪些能修"，避免为同一件事跑两遍全量扫描。
     */
    private List<LearningProgressRepairItem> repairs;

    public SystemHealthCheckResult() {
    }

    public SystemHealthCheckResult(boolean isHealthy, List<SystemHealthIssue> issues, List<String> errors) {
        this(isHealthy, issues, errors, null);
    }

    public SystemHealthCheckResult(boolean isHealthy, List<SystemHealthIssue> issues, List<String> errors,
            List<LearningProgressRepairItem> repairs) {
        this.isHealthy = isHealthy;
        this.issues = issues;
        this.errors = errors;
        this.repairs = repairs;
    }

    public List<LearningProgressRepairItem> getRepairs() {
        return repairs;
    }

    public void setRepairs(List<LearningProgressRepairItem> repairs) {
        this.repairs = repairs;
    }

    public boolean getIsHealthy() {
        return isHealthy;
    }

    public void setIsHealthy(boolean isHealthy) {
        this.isHealthy = isHealthy;
    }

    public List<SystemHealthIssue> getIssues() {
        return issues;
    }

    public void setIssues(List<SystemHealthIssue> issues) {
        this.issues = issues;
    }

    public List<String> getErrors() {
        return errors;
    }

    public void setErrors(List<String> errors) {
        this.errors = errors;
    }
}
