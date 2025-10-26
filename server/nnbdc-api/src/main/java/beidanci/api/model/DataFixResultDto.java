package beidanci.api.model;

import java.util.List;

/**
 * 数据修复结果DTO
 */
public class DataFixResultDto implements Dto {
    private boolean hasFixed;
    private boolean hasErrors;
    private List<String> fixed;
    private List<String> errors;

    public DataFixResultDto() {
    }

    public DataFixResultDto(boolean hasFixed, boolean hasErrors, List<String> fixed, List<String> errors) {
        this.hasFixed = hasFixed;
        this.hasErrors = hasErrors;
        this.fixed = fixed;
        this.errors = errors;
    }

    public boolean isHasFixed() {
        return hasFixed;
    }

    public void setHasFixed(boolean hasFixed) {
        this.hasFixed = hasFixed;
    }

    public boolean isHasErrors() {
        return hasErrors;
    }

    public void setHasErrors(boolean hasErrors) {
        this.hasErrors = hasErrors;
    }

    public List<String> getFixed() {
        return fixed;
    }

    public void setFixed(List<String> fixed) {
        this.fixed = fixed;
    }

    public List<String> getErrors() {
        return errors;
    }

    public void setErrors(List<String> errors) {
        this.errors = errors;
    }
}
