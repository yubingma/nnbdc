package beidanci.api.model;

import java.util.List;

public class StudyProgress {
    int existDays;
    Integer dakaDayCount;
    double dakaRatio;
    int totalScore;
    int userOrder;
    int rawWordCount;
    Integer cowDung;
    LevelVo level;
    Integer masteredWordsCount;
    int learningWordsCount;
    Integer wordsPerDay;
    Integer continuousDakaDayCount;
    Integer throwDiceChance;
    boolean allDictsFinished;
    boolean todayLearningFinished;
    List<LearningDictVo> learningDicts;

    public int getExistDays() {
        return existDays;
    }

    public void setExistDays(int existDays) {
        this.existDays = existDays;
    }

    public Integer getDakaDayCount() {
        return dakaDayCount;
    }

    public void setDakaDayCount(Integer dakaDayCount) {
        this.dakaDayCount = dakaDayCount;
    }

    public double getDakaRatio() {
        return dakaRatio;
    }

    public void setDakaRatio(double dakaRatio) {
        this.dakaRatio = dakaRatio;
    }

    public int getTotalScore() {
        return totalScore;
    }

    public void setTotalScore(int totalScore) {
        this.totalScore = totalScore;
    }

    public int getUserOrder() {
        return userOrder;
    }

    public void setUserOrder(int userOrder) {
        this.userOrder = userOrder;
    }

    public int getRawWordCount() {
        return rawWordCount;
    }

    public void setRawWordCount(int rawWordCount) {
        this.rawWordCount = rawWordCount;
    }

    public Integer getCowDung() {
        return cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public LevelVo getLevel() {
        return level;
    }

    public void setLevel(LevelVo level) {
        this.level = level;
    }

    public Integer getMasteredWordsCount() {
        return masteredWordsCount;
    }

    public void setMasteredWordsCount(Integer masteredWordsCount) {
        this.masteredWordsCount = masteredWordsCount;
    }

    public int getLearningWordsCount() {
        return learningWordsCount;
    }

    public void setLearningWordsCount(int learningWordsCount) {
        this.learningWordsCount = learningWordsCount;
    }

    public Integer getWordsPerDay() {
        return wordsPerDay;
    }

    public void setWordsPerDay(Integer wordsPerDay) {
        this.wordsPerDay = wordsPerDay;
    }

    public Integer getContinuousDakaDayCount() {
        return continuousDakaDayCount;
    }

    public void setContinuousDakaDayCount(Integer continuousDakaDayCount) {
        this.continuousDakaDayCount = continuousDakaDayCount;
    }

    public Integer getThrowDiceChance() {
        return throwDiceChance;
    }

    public void setThrowDiceChance(Integer throwDiceChance) {
        this.throwDiceChance = throwDiceChance;
    }

    public boolean isAllDictsFinished() {
        return allDictsFinished;
    }

    public void setAllDictsFinished(boolean allDictsFinished) {
        this.allDictsFinished = allDictsFinished;
    }

    public boolean isTodayLearningFinished() {
        return todayLearningFinished;
    }

    public void setTodayLearningFinished(boolean todayLearningFinished) {
        this.todayLearningFinished = todayLearningFinished;
    }

    public List<LearningDictVo> getLearningDicts() {
        return learningDicts;
    }

    public void setLearningDicts(List<LearningDictVo> learningDicts) {
        this.learningDicts = learningDicts;
    }

}
