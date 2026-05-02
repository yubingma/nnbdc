package beidanci.api.model;

import java.io.Serializable;

public class AiStoryVo implements Serializable {
    private static final long serialVersionUID = 1L;

    private String storyContent;
    private String wordsHash;

    public AiStoryVo() {}

    public AiStoryVo(String storyContent, String wordsHash) {
        this.storyContent = storyContent;
        this.wordsHash = wordsHash;
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
}
