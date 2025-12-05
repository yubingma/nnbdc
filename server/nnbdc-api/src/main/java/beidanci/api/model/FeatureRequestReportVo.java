package beidanci.api.model;

import java.util.Date;

public class FeatureRequestReportVo extends UuidVo {
    private UserVo reporter;
    private FeatureRequestVo featureRequest;
    private String content;
    private Date createTime;

    public FeatureRequestReportVo() {
    }

    public UserVo getReporter() {
        return reporter;
    }

    public void setReporter(UserVo reporter) {
        this.reporter = reporter;
    }

    public FeatureRequestVo getFeatureRequest() {
        return featureRequest;
    }

    public void setFeatureRequest(FeatureRequestVo featureRequest) {
        this.featureRequest = featureRequest;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }
}
