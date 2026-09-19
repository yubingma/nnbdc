package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.Table;

@Entity
@Table(name = "word_core_image", indexes = {
    @Index(name = "idx_wci_word_id", columnList = "word_id", unique = true),
    @Index(name = "idx_wci_word", columnList = "word")
})
public class WordCoreImage extends UuidPo {

    @Column(name = "word_id", length = 32, nullable = false)
    private String wordId;

    @Column(name = "word", length = 100, nullable = false)
    private String word;

    @Column(name = "is_applicable", nullable = false)
    private Boolean isApplicable = false;

    @Column(name = "not_applicable_reason", length = 255)
    private String notApplicableReason;

    @Column(name = "core_image", length = 255)
    private String coreImage;

    @Column(name = "schema_desc", length = 1000)
    private String schemaDesc;

    @Column(name = "topology_json", columnDefinition = "TEXT")
    private String topologyJson;

    @Column(name = "image_prompt", columnDefinition = "TEXT")
    private String imagePrompt;

    @Column(name = "image_url", length = 500)
    private String imageUrl;

    @Column(name = "image_status", length = 32)
    private String imageStatus;

    @Column(name = "image_model", length = 100)
    private String imageModel;

    public WordCoreImage() {
    }

    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getWord() {
        return word;
    }

    public void setWord(String word) {
        this.word = word;
    }

    public Boolean getIsApplicable() {
        return isApplicable;
    }

    public void setIsApplicable(Boolean isApplicable) {
        this.isApplicable = isApplicable;
    }

    public String getNotApplicableReason() {
        return notApplicableReason;
    }

    public void setNotApplicableReason(String notApplicableReason) {
        this.notApplicableReason = notApplicableReason;
    }

    public String getCoreImage() {
        return coreImage;
    }

    public void setCoreImage(String coreImage) {
        this.coreImage = coreImage;
    }

    public String getSchemaDesc() {
        return schemaDesc;
    }

    public void setSchemaDesc(String schemaDesc) {
        this.schemaDesc = schemaDesc;
    }

    public String getTopologyJson() {
        return topologyJson;
    }

    public void setTopologyJson(String topologyJson) {
        this.topologyJson = topologyJson;
    }

    public String getImagePrompt() {
        return imagePrompt;
    }

    public void setImagePrompt(String imagePrompt) {
        this.imagePrompt = imagePrompt;
    }

    public String getImageUrl() {
        return imageUrl;
    }

    public void setImageUrl(String imageUrl) {
        this.imageUrl = imageUrl;
    }

    public String getImageStatus() {
        return imageStatus;
    }

    public void setImageStatus(String imageStatus) {
        this.imageStatus = imageStatus;
    }

    public String getImageModel() {
        return imageModel;
    }

    public void setImageModel(String imageModel) {
        this.imageModel = imageModel;
    }
}
