package beidanci.api.model;

import java.util.Date;

public class WordCoreImageDto extends Dto {
    private String id;
    private String wordId;
    private String word;
    private Boolean isApplicable;
    private String notApplicableReason;
    private String coreImage;
    private String schemaDesc;
    private String topologyJson;
    private String imagePrompt;
    private String imageUrl;
    private String imageStatus;
    private String llmModel;
    private String imageModel;
    private Date createTime;
    private Date updateTime;

    public WordCoreImageDto() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
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

    public String getLlmModel() {
        return llmModel;
    }

    public void setLlmModel(String llmModel) {
        this.llmModel = llmModel;
    }

    public String getImageModel() {
        return imageModel;
    }

    public void setImageModel(String imageModel) {
        this.imageModel = imageModel;
    }

    public Date getCreateTime() {
        return createTime;
    }

    public void setCreateTime(Date createTime) {
        this.createTime = createTime;
    }

    public Date getUpdateTime() {
        return updateTime;
    }

    public void setUpdateTime(Date updateTime) {
        this.updateTime = updateTime;
    }
}
