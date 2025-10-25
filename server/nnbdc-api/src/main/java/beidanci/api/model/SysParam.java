package beidanci.api.model;

public class SysParam {

    public static final String COW_DUNG_PER_GAME = "CowDungPerGame";
    // Fields

    private String paramName;

    private String paramValue;

    private String comment;

    /**
     * default constructor
     */
    public SysParam() {
    }

    /**
     * minimal constructor
     */
    public SysParam(String paramName, String paramValue) {
        this.paramName = paramName;
        this.paramValue = paramValue;
    }

    /**
     * full constructor
     */
    public SysParam(String paramName, String paramValue, String comment) {
        this.paramName = paramName;
        this.paramValue = paramValue;
        this.comment = comment;
    }

    // Property accessors

    public String getParamName() {
        return this.paramName;
    }

    public void setParamName(String paramName) {
        this.paramName = paramName;
    }

    public String getParamValue() {
        return this.paramValue;
    }

    public void setParamValue(String paramValue) {
        this.paramValue = paramValue;
    }

    public String getComment() {
        return this.comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }

}
