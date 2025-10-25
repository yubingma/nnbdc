package beidanci.api.model;

/**
 * 单词在本日学习单词列表中的序号及学习模式
 */
public class WordIndexAndLearningMode {
    private int wordeIndex;

    public int getLearningMode() {
        return learningMode;
    }

    public void setLearningMode(int learningMode) {
        this.learningMode = learningMode;
    }

    private int learningMode;

    public int getWordeIndex() {
        return wordeIndex;
    }

    public void setWordeIndex(int wordeIndex) {
        this.wordeIndex = wordeIndex;
    }

    public WordIndexAndLearningMode(int wordeIndex, int learningMode) {
        this.wordeIndex = wordeIndex;
        this.learningMode = learningMode;
    }

    @Override
    public String toString() {
        return wordeIndex + ":" + learningMode;
    }
}
