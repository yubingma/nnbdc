package beidanci.api.model;

import java.util.List;

/**
 * 数据诊断结果DTO
 */
public class DataDiagnosticDto implements Dto {
    private boolean isHealthy;
    private int totalIssues;
    private List<String> errors;
    private List<DiagnosticIssueDto> issues;

    public DataDiagnosticDto() {
    }

    public DataDiagnosticDto(boolean isHealthy, int totalIssues, List<String> errors, List<DiagnosticIssueDto> issues) {
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

    public List<DiagnosticIssueDto> getIssues() {
        return issues;
    }

    public void setIssues(List<DiagnosticIssueDto> issues) {
        this.issues = issues;
    }
}
