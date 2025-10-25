package beidanci.service.store;

import java.util.ArrayList;
import java.util.List;

public class Meaning {

    private final String meaning;

    private final List<String> sentences;

    public List<String> getSentences() {
        return sentences;
    }

    public Meaning(String meaingStr) {
        assert (meaingStr.trim().length() > 0);
        this.meaning = meaingStr;
        sentences = new ArrayList<>();
    }

    public void addSentence(String sentence) {
        sentences.add(sentence);
    }

    public String makeStoreString() {
        StringBuilder sb = new StringBuilder();

        sb.append("\t\t{").append("\n");
        sb.append("\t\t").append(meaning).append("\n");

        for (String sentence : sentences) {
            sb.append("\t\t\t{").append(sentence).append("}").append("\n");
        }

        sb.append("\t\t}").append("\n");

        return sb.toString();

    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();

        for (String sentence : sentences) {
            sb.append("\t\t").append(sentence).append("\n");
        }

        return sb.toString();
    }

    public String getMeaning() {
        return meaning;
    }
}
