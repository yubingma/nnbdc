package beidanci.api.model;

import java.util.List;

/**
 * 系统健康修复结果
 */
public class SystemHealthFixResult {
    private int fixedCount;
    private List<String> errors;
    private List<String> fixed;

    public SystemHealthFixResult() {
    }

    public SystemHealthFixResult(int fixedCount, List<String> errors, List<String> fixed) {
        this.fixedCount = fixedCount;
        this.errors = errors;
        this.fixed = fixed;
    }

    public int getFixedCount() {
        return fixedCount;
    }

    public void setFixedCount(int fixedCount) {
        this.fixedCount = fixedCount;
    }

    public List<String> getErrors() {
        return errors;
    }

    public void setErrors(List<String> errors) {
        this.errors = errors;
    }

    public List<String> getFixed() {
        return fixed;
    }

    public void setFixed(List<String> fixed) {
        this.fixed = fixed;
    }
}
