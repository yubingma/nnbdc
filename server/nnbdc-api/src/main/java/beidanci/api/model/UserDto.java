package beidanci.api.model;

import java.util.Date;

/**
 * 用于前后端同步的用户数据传输对象
 */
public class UserDto extends Dto {
    private String id;
    private String userName;
    private String nickName;
    private String password;
    private Date lastLoginTime;
    private Date lastShareTime;
    private String email;
    private String wechatOpenId;
    private String wechatUnionId;
    private String wechatNickname;
    private String wechatAvatar;
    private Date lastLearningDate;
    private Integer learnedDays;
    private Boolean learningFinished;
    private Boolean inviteAwardTaken;
    private Boolean isSuperAdmin;
    private Boolean isAdmin;
    private Boolean isInputor;
    private Boolean isSysUser;
    private Integer wordsPerDay;
    private Integer dakaDayCount;
    private Integer masteredWordsCount;
    private Integer cowDung;
    private Integer throwDiceChance;
    private Integer gameScore;
    private Integer continuousDakaDayCount;
    private Integer maxContinuousDakaDayCount;
    private Date lastDakaDate;
    private Integer dakaScore;
    private Boolean todayStudyStarted;
    private Integer totalLearningSeconds;
    private Integer todayLearningSeconds;

    // =========================
    // 订阅 / 会员相关字段
    // =========================
    // iOS订阅字段（由服务端维护，客户端可读）
    private Boolean isPremiumIos;
    private Date subscriptionExpireDateIos;
    private String subscriptionTypeIos;
    private String subscriptionStatusIos;
    private String lastReceiptDataIos;

    /**
     * 强制视为会员（用于纠纷处理/白名单/补偿等）
     * - enabled=true 且未过期（根据 updateTime + duration 判断）则认为是会员
     * - duration 形如：10天 / 360秒 / 15分钟，为 null 表示永久
     */
    private Boolean premiumOverrideEnabled;
    private Date premiumOverrideUpdateTime;
    private String premiumOverrideReason;
    private String premiumOverrideDuration;
    private String appleUserId;



    private String studyConfig;
    

    public UserDto() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
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

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getWechatOpenId() {
        return wechatOpenId;
    }

    public void setWechatOpenId(String wechatOpenId) {
        this.wechatOpenId = wechatOpenId;
    }

    public String getWechatUnionId() {
        return wechatUnionId;
    }

    public void setWechatUnionId(String wechatUnionId) {
        this.wechatUnionId = wechatUnionId;
    }

    public String getWechatNickname() {
        return wechatNickname;
    }

    public void setWechatNickname(String wechatNickname) {
        this.wechatNickname = wechatNickname;
    }

    public String getWechatAvatar() {
        return wechatAvatar;
    }

    public void setWechatAvatar(String wechatAvatar) {
        this.wechatAvatar = wechatAvatar;
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

    public Boolean getIsSysUser() {
        return isSysUser;
    }

    public void setIsSysUser(Boolean isSysUser) {
        this.isSysUser = isSysUser;
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

    public Integer getGameScore() {
        return gameScore;
    }

    public void setGameScore(Integer gameScore) {
        this.gameScore = gameScore;
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

    public Integer getDakaScore() {
        return dakaScore;
    }

    public void setDakaScore(Integer dakaScore) {
        this.dakaScore = dakaScore;
    }



    public Boolean getTodayStudyStarted() {
        return todayStudyStarted;
    }

    public void setTodayStudyStarted(Boolean todayStudyStarted) {
        this.todayStudyStarted = todayStudyStarted;
    }

    public Integer getTotalLearningSeconds() {
        return totalLearningSeconds;
    }

    public void setTotalLearningSeconds(Integer totalLearningSeconds) {
        this.totalLearningSeconds = totalLearningSeconds;
    }

    public Integer getTodayLearningSeconds() {
        return todayLearningSeconds;
    }

    public void setTodayLearningSeconds(Integer todayLearningSeconds) {
        this.todayLearningSeconds = todayLearningSeconds;
    }

    public Boolean getIsPremiumIos() {
        return isPremiumIos;
    }

    public void setIsPremiumIos(Boolean isPremiumIos) {
        this.isPremiumIos = isPremiumIos;
    }

    public Date getSubscriptionExpireDateIos() {
        return subscriptionExpireDateIos;
    }

    public void setSubscriptionExpireDateIos(Date subscriptionExpireDateIos) {
        this.subscriptionExpireDateIos = subscriptionExpireDateIos;
    }

    public String getSubscriptionTypeIos() {
        return subscriptionTypeIos;
    }

    public void setSubscriptionTypeIos(String subscriptionTypeIos) {
        this.subscriptionTypeIos = subscriptionTypeIos;
    }

    public String getSubscriptionStatusIos() {
        return subscriptionStatusIos;
    }

    public void setSubscriptionStatusIos(String subscriptionStatusIos) {
        this.subscriptionStatusIos = subscriptionStatusIos;
    }

    public String getLastReceiptDataIos() {
        return lastReceiptDataIos;
    }

    public void setLastReceiptDataIos(String lastReceiptDataIos) {
        this.lastReceiptDataIos = lastReceiptDataIos;
    }

    public Boolean getPremiumOverrideEnabled() {
        return premiumOverrideEnabled;
    }

    public void setPremiumOverrideEnabled(Boolean premiumOverrideEnabled) {
        this.premiumOverrideEnabled = premiumOverrideEnabled;
    }

    public Date getPremiumOverrideUpdateTime() {
        return premiumOverrideUpdateTime;
    }

    public void setPremiumOverrideUpdateTime(Date premiumOverrideUpdateTime) {
        this.premiumOverrideUpdateTime = premiumOverrideUpdateTime;
    }

    public String getPremiumOverrideReason() {
        return premiumOverrideReason;
    }

    public void setPremiumOverrideReason(String premiumOverrideReason) {
        this.premiumOverrideReason = premiumOverrideReason;
    }

    public String getPremiumOverrideDuration() {
        return premiumOverrideDuration;
    }

    public void setPremiumOverrideDuration(String premiumOverrideDuration) {
        this.premiumOverrideDuration = premiumOverrideDuration;
    }






    public String getStudyConfig() {
        return studyConfig;
    }

    public void setStudyConfig(String studyConfig) {
        this.studyConfig = studyConfig;
    }

    public String getAppleUserId() {
        return appleUserId;
    }

    public void setAppleUserId(String appleUserId) {
        this.appleUserId = appleUserId;
    }
}
