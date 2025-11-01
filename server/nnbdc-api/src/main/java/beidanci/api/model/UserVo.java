package beidanci.api.model;

import java.util.Date;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnore;

public class UserVo extends UuidVo {
    private String userName;
    private String nickName;
    @JsonIgnore
    private String password;
    private Boolean hasDakaToday;
    private List<StudyGroupVo> studyGroups;
    private List<UserGameVo> userGames;
    private Integer gameScore;
    /**
     * 打卡积分
     */
    private Integer dakaScore;
    /**
     * 是否直接显示备选答案
     */
    private Boolean showAnswersDirectly;
    /**
     * 是否自动朗读单词发音
     */
    private Boolean autoPlayWord;
    private Date lastLoginTime;
    private Date lastShareTime;
    private String email;
    private Date lastLearningDate;
    private Integer learnedDays;
    private Integer lastLearningPosition;
    private Integer lastLearningMode;
    private Boolean learningFinished;
    private Boolean inviteAwardTaken;
    private Boolean isSuperAdmin;
    private Boolean isAdmin;
    private Boolean isInputor;
    private Boolean isTodayLearningStarted;
    private Boolean isTodayLearningFinished;
    private Boolean autoPlaySentence;
    private Integer wordsPerDay;
    private Integer dakaDayCount;
    private Integer masteredWordsCount;
    private Integer cowDung;
    private Integer throwDiceChance;
    private String displayNickName;
    private UserVo invitedBy;
    private LevelVo level;
    /**
     * 连续打卡天数
     */
    private Integer continuousDakaDayCount;
    /**
     * 最大连续打卡天数
     */
    private Integer maxContinuousDakaDayCount;
    /**
     * 最近一次打卡的日期
     */
    private Date lastDakaDate;
    private Integer totalScore;
    private Double dakaRatio;
    private Boolean enableAllWrong;


    /**
     * ASR答对判定规则：ONE/HALF/ALL
     */
    private String asrPassRule;

    public Boolean getHasDakaToday() {
        return hasDakaToday;
    }

    public void setHasDakaToday(Boolean hasDakaToday) {
        this.hasDakaToday = hasDakaToday;
    }

    public String getAsrPassRule() {
        return asrPassRule;
    }

    public void setAsrPassRule(String asrPassRule) {
        this.asrPassRule = asrPassRule;
    }

    public List<StudyGroupVo> getStudyGroups() {
        return studyGroups;
    }

    public void setStudyGroups(List<StudyGroupVo> studyGroups) {
        this.studyGroups = studyGroups;
    }

    public List<UserGameVo> getUserGames() {
        return userGames;
    }

    public void setUserGames(List<UserGameVo> userGames) {
        this.userGames = userGames;
    }

    public UserGameVo getGameByName(String gameName) {
        UserGameVo gameVo = null;
        for (UserGameVo userGameVo : userGames) {
            if (userGameVo.getGame().equals(gameName)) {
                gameVo = userGameVo;
                break;
            }
        }

        if (gameVo == null) {
            gameVo = new UserGameVo(null, 0, 0, 0, gameName);
            userGames.add(gameVo);
        }

        return gameVo;
    }

    public Integer getGameScore() {
        return gameScore;
    }

    public void setGameScore(Integer gameScore) {
        this.gameScore = gameScore;
    }

    public Integer getDakaScore() {
        return dakaScore;
    }

    public void setDakaScore(Integer dakaScore) {
        this.dakaScore = dakaScore;
    }

    public Boolean getShowAnswersDirectly() {
        return showAnswersDirectly;
    }

    public void setShowAnswersDirectly(Boolean showAnswersDirectly) {
        this.showAnswersDirectly = showAnswersDirectly;
    }

    public LevelVo getLevel() {
        return level;
    }

    public void setLevel(LevelVo level) {
        this.level = level;
    }

    public Boolean getEnableAllWrong() {
        return enableAllWrong;
    }

    public void setEnableAllWrong(Boolean enableAllWrong) {
        this.enableAllWrong = enableAllWrong;
    }

    public Double getDakaRatio() {
        return dakaRatio;
    }

    public void setDakaRatio(Double dakaRatio) {
        this.dakaRatio = dakaRatio;
    }

    public Integer getTotalScore() {
        return totalScore;
    }

    public void setTotalScore(Integer totalScore) {
        this.totalScore = totalScore;
    }

    public Integer getContinuousDakaDayCount() {
        return continuousDakaDayCount;
    }

    public void setContinuousDakaDayCount(Integer continuousDakaDayCount) {
        this.continuousDakaDayCount = continuousDakaDayCount;
    }

    public Integer getMaxContinuousDakaDayCount() {
        return maxContinuousDakaDayCount;
    }

    public void setMaxContinuousDakaDayCount(Integer maxContinuousDakaDayCount) {
        this.maxContinuousDakaDayCount = maxContinuousDakaDayCount;
    }

    public Date getLastDakaDate() {
        return lastDakaDate;
    }

    public void setLastDakaDate(Date lastDakaDate) {
        this.lastDakaDate = lastDakaDate;
    }

    public String getDisplayNickName() {
        return displayNickName;
    }

    public void setDisplayNickName(String displayNickName) {
        this.displayNickName = displayNickName;
    }

    public String getUserName() {
        return userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public Date getLastLearningDate() {
        return lastLearningDate;
    }

    public void setLastLearningDate(Date lastLearningDate) {
        this.lastLearningDate = lastLearningDate;
    }

    public Integer getLearnedDays() {
        return learnedDays;
    }

    public void setLearnedDays(Integer learnedDays) {
        this.learnedDays = learnedDays;
    }

    public Integer getLastLearningPosition() {
        return lastLearningPosition;
    }

    public void setLastLearningPosition(Integer lastLearningPosition) {
        this.lastLearningPosition = lastLearningPosition;
    }

    public Integer getLastLearningMode() {
        return lastLearningMode;
    }

    public void setLastLearningMode(Integer lastLearningMode) {
        this.lastLearningMode = lastLearningMode;
    }

    public Boolean getLearningFinished() {
        return learningFinished;
    }

    public void setLearningFinished(Boolean learningFinished) {
        this.learningFinished = learningFinished;
    }

    public Boolean getInviteAwardTaken() {
        return inviteAwardTaken;
    }

    public void setInviteAwardTaken(Boolean inviteAwardTaken) {
        this.inviteAwardTaken = inviteAwardTaken;
    }

    public Boolean getIsSuperAdmin() {
        return isSuperAdmin;
    }

    public void setIsSuperAdmin(Boolean isSuperAdmin) {
        this.isSuperAdmin = isSuperAdmin;
    }

    public Boolean getAutoPlaySentence() {
        return autoPlaySentence;
    }

    public void setAutoPlaySentence(Boolean autoPlaySentence) {
        this.autoPlaySentence = autoPlaySentence;
    }

    public Integer getWordsPerDay() {
        return wordsPerDay;
    }

    public void setWordsPerDay(Integer wordsPerDay) {
        this.wordsPerDay = wordsPerDay;
    }

    public Integer getDakaDayCount() {
        return dakaDayCount;
    }

    public void setDakaDayCount(Integer dakaDayCount) {
        this.dakaDayCount = dakaDayCount;
    }

    public Integer getMasteredWordsCount() {
        return masteredWordsCount;
    }

    public void setMasteredWordsCount(Integer masteredWordsCount) {
        this.masteredWordsCount = masteredWordsCount;
    }

    public Integer getCowDung() {
        return cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    public Integer getThrowDiceChance() {
        return throwDiceChance;
    }

    public void setThrowDiceChance(Integer throwDiceChance) {
        this.throwDiceChance = throwDiceChance;
    }

    public UserVo getInvitedBy() {
        return invitedBy;
    }

    public void setInvitedBy(UserVo invitedBy) {
        this.invitedBy = invitedBy;
    }

    public Date getLastLoginTime() {
        return lastLoginTime;
    }

    public void setLastLoginTime(Date lastLoginTime) {
        this.lastLoginTime = lastLoginTime;
    }

    public Date getLastShareTime() {
        return lastShareTime;
    }

    public void setLastShareTime(Date lastShareTime) {
        this.lastShareTime = lastShareTime;
    }

    public Boolean getAutoPlayWord() {
        return autoPlayWord;
    }

    public void setAutoPlayWord(Boolean autoPlayWord) {
        this.autoPlayWord = autoPlayWord;
    }

    public Boolean getIsAdmin() {
        return isAdmin;
    }

    public void setIsAdmin(Boolean isAdmin) {
        this.isAdmin = isAdmin;
    }

    public Boolean getIsInputor() {
        return isInputor;
    }

    public void setIsInputor(Boolean isInputor) {
        this.isInputor = isInputor;
    }

    public Boolean getIsGuest() {
        return userName == null ? null : userName.startsWith("guest");
    }

    // passIfSpeakOutOneMeaning 已移除

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    @Override
    public boolean equals(Object obj) {
        if (!(obj instanceof UserVo)) {
            return false;
        }
        return id.equals(((UserVo) obj).getId());
    }

    public Boolean getIsTodayLearningStarted() {
        return isTodayLearningStarted;
    }

    public void setIsTodayLearningStarted(Boolean todayLearningStarted) {
        isTodayLearningStarted = todayLearningStarted;
    }

    public Boolean getIsTodayLearningFinished() {
        return isTodayLearningFinished;
    }

    public void setIsTodayLearningFinished(Boolean todayLearningFinished) {
        isTodayLearningFinished = todayLearningFinished;
    }

}
