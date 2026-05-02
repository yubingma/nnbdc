package beidanci.api.model;

import java.io.Serializable;

public class AiStoryVo implements Serializable {
    private static final long serialVersionUID = 1L;

    private String storyContent;
    private String wordsHash;
    private boolean enTtsEnabled;
    private boolean cnTtsEnabled;

    public AiStoryVo() {}

    public AiStoryVo(String storyContent, String wordsHash) {
        this.storyContent = storyContent;
        this.wordsHash = wordsHash;
    }

    public AiStoryVo(String storyContent, String wordsHash, boolean enTtsEnabled, boolean cnTtsEnabled) {
        this.storyContent = storyContent;
        this.wordsHash = wordsHash;
        this.enTtsEnabled = enTtsEnabled;
        this.cnTtsEnabled = cnTtsEnabled;
    }

    public String getStoryContent() {
        return storyContent;
    }

    public void setStoryContent(String storyContent) {
        this.storyContent = storyContent;
    }

    public String getWordsHash() {
        return wordsHash;
    }

    public void setWordsHash(String wordsHash) {
        this.wordsHash = wordsHash;
    }

    public boolean isEnTtsEnabled() {
        return enTtsEnabled;
    }

    public void setEnTtsEnabled(boolean enTtsEnabled) {
        this.enTtsEnabled = enTtsEnabled;
    }

    public boolean isCnTtsEnabled() {
        return cnTtsEnabled;
    }

    public void setCnTtsEnabled(boolean cnTtsEnabled) {
        this.cnTtsEnabled = cnTtsEnabled;
    }
}
