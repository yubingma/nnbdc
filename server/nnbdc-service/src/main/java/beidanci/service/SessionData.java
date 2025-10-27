package beidanci.service;

import java.util.List;
import java.util.Map;

import beidanci.api.model.ClientType;
import beidanci.api.model.WordIndexAndLearningMode;
import beidanci.service.po.LearningWord;
import beidanci.service.po.UserStudyStep;

public class SessionData {
    public static final String SESSION_DATA = "sessionData";

    private List<LearningWord> todayWords;

    private WordIndexAndLearningMode wordIndexAndLearningMode;

    /**
     * 学习index到 单词index+学习模式 的映射
     */
    private Map<Integer, WordIndexAndLearningMode> learningIndexMap;

    /**
     * 服务端随机生成的奖励用户的魔法泡泡数
     */
    private int cowDung;

    /**
     * 用户昵称
     */
    private String userNickName;

    private String clientVersion;

    /**
     * 最近一次打卡所获得的积分
     */
    private Integer lastDakaScore;

    private ClientType clientType;

    private List<UserStudyStep> activeUserStudySteps;

    public SessionData() {
    }

    public WordIndexAndLearningMode getWordIndexAndLearningMode() {
        return wordIndexAndLearningMode;
    }

    public void setWordIndexAndLearningMode(WordIndexAndLearningMode wordIndexAndLearningMode) {
        this.wordIndexAndLearningMode = wordIndexAndLearningMode;
    }

    public Map<Integer, WordIndexAndLearningMode> getLearningIndexMap() {
        return learningIndexMap;
    }

    public void setLearningIndexMap(Map<Integer, WordIndexAndLearningMode> learningIndexMap) {
        this.learningIndexMap = learningIndexMap;
    }

    public String getClientVersion() {
        return clientVersion;
    }

    public void setClientVersion(String clientVersion) {
        this.clientVersion = clientVersion;
    }

    public Integer getLastDakaScore() {
        return lastDakaScore;
    }

    public void setLastDakaScore(Integer lastDakaScore) {
        this.lastDakaScore = lastDakaScore;
    }

    public ClientType getClientType() {
        return clientType;
    }

    public void setClientType(ClientType clientType) {
        this.clientType = clientType;
    }

    public List<LearningWord> getTodayWords() {
        return todayWords;
    }

    public void setTodayWords(List<LearningWord> todayWords) {
        this.todayWords = todayWords;
    }

    public int getCowDung() {
        return cowDung;
    }

    public void setCowDung(int cowDung) {
        this.cowDung = cowDung;
    }

    public void setActiveUserStudySteps(List<UserStudyStep> activeUserStudySteps) {
        this.activeUserStudySteps = activeUserStudySteps;
    }

    public String getUserNickName() {
        return userNickName;
    }

    public void setUserNickName(String userNickName) {
        this.userNickName = userNickName;
    }

    public List<UserStudyStep> getActiveUserStudySteps() {
        return this.activeUserStudySteps;
    }
}
