package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "ai_stories")
public class AiStory extends UuidPo {

    @Column(name = "words_hash", length = 64, nullable = false, unique = true)
    private String wordsHash;

    @Column(name = "words_json", nullable = false)
    private String wordsJson;

    @Column(name = "story_content", nullable = false)
    private String storyContent;

    public AiStory() {
    }

    public AiStory(String id, String wordsHash, String wordsJson, String storyContent) {
        this.id = id;
        this.wordsHash = wordsHash;
        this.wordsJson = wordsJson;
        this.storyContent = storyContent;
    }

    public String getWordsHash() {
        return wordsHash;
    }

    public void setWordsHash(String wordsHash) {
        this.wordsHash = wordsHash;
    }

    public String getWordsJson() {
        return wordsJson;
    }

    public void setWordsJson(String wordsJson) {
        this.wordsJson = wordsJson;
    }

    public String getStoryContent() {
        return storyContent;
    }

    public void setStoryContent(String storyContent) {
        this.storyContent = storyContent;
    }
}
