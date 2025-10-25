package beidanci.api.model;

import java.util.List;

public class SynonymsItem {
    private String meaning;
    List<String> words;

    public String getMeaning() {
        return meaning;
    }

    public void setMeaning(String meaning) {
        this.meaning = meaning;
    }

    public List<String> getWords() {
        return words;
    }

    public void setWords(List<String> words) {
        this.words = words;
    }

}
