package beidanci.api.model;

import java.util.List;

/**
 * 诊断结果视图对象 - 用于前端展示，不是数据库表记录
 */
public class DiagnosticResultVo {
    private boolean isHealthy;
    private int totalIssues;
    private List<String> errors;
    private List<DiagnosticIssue> issues;

    public DiagnosticResultVo() {
    }

    public DiagnosticResultVo(boolean isHealthy, int totalIssues, List<String> errors, List<DiagnosticIssue> issues) {
        this.isHealthy = isHealthy;
        this.totalIssues = totalIssues;
        this.errors = errors;
        this.issues = issues;
    }

    public boolean isHealthy() {
        return isHealthy;
    }

    public void setHealthy(boolean healthy) {
        isHealthy = healthy;
    }

    public int getTotalIssues() {
        return totalIssues;
    }

    public void setTotalIssues(int totalIssues) {
        this.totalIssues = totalIssues;
    }

    public List<String> getErrors() {
        return errors;
    }

    public void setErrors(List<String> errors) {
        this.errors = errors;
    }

    public List<DiagnosticIssue> getIssues() {
        return issues;
    }

    public void setIssues(List<DiagnosticIssue> issues) {
        this.issues = issues;
    }
}
