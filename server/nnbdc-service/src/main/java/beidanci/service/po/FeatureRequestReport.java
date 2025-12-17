package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/* 需求墙举报 */
@Entity
@Table(name = "feature_request_report")
public class FeatureRequestReport extends UuidPo {

    @Column(name = "reporter_id", nullable = false)
    private User reporter;

    @Column(name = "feature_request_id", nullable = false)
    private FeatureRequest featureRequest;

    @Column(name = "content", length = 2000, nullable = false)
    private String content;

    public FeatureRequestReport() {
    }

    public User getReporter() {
        return reporter;
    }

    public void setReporter(User reporter) {
        this.reporter = reporter;
    }

    public FeatureRequest getFeatureRequest() {
        return featureRequest;
    }

    public void setFeatureRequest(FeatureRequest featureRequest) {
        this.featureRequest = featureRequest;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }
}
