package beidanci.api.model;

import java.util.List;

/**
 * 系统健康检查结果
 */
public class SystemHealthCheckResult {
    private boolean isHealthy;
    private List<SystemHealthIssue> issues;
    private List<String> errors;

    public SystemHealthCheckResult() {
    }

    public SystemHealthCheckResult(boolean isHealthy, List<SystemHealthIssue> issues, List<String> errors) {
        this.isHealthy = isHealthy;
        this.issues = issues;
        this.errors = errors;
    }

    public boolean isHealthy() {
        return isHealthy;
    }

    public void setHealthy(boolean healthy) {
        isHealthy = healthy;
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
