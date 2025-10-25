package beidanci.api.model;

public class SimilarWordDto implements Dto {

    private String wordId;
    private String similarWordId;
    private String similarWordSpell;
    private int distance;


    public String getWordId() {
        return wordId;
    }

    public void setWordId(String wordId) {
        this.wordId = wordId;
    }

    public String getSimilarWordId() {
        return similarWordId;
    }

    public void setSimilarWordId(String similarWordId) {
        this.similarWordId = similarWordId;
    }

    public int getDistance() {
        return distance;
    }

    public void setDistance(int distance) {
        this.distance = distance;
    }

    public String getSimilarWordSpell() {
        return similarWordSpell;
    }

    public void setSimilarWordSpell(String similarWordSpell) {
        this.similarWordSpell = similarWordSpell;
    }

}
