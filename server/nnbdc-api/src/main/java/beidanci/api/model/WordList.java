package beidanci.api.model;

public class WordList {
    private String name;
    private int wordCount;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getWordCount() {
        return wordCount;
    }

    public void setWordCount(int wordCount) {
        this.wordCount = wordCount;
    }

    public WordList(String name, int wordCount) {
        this.name = name;
        this.wordCount = wordCount;
    }
}
