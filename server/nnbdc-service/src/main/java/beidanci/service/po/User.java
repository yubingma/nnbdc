package beidanci.service.po;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.OrderBy;
import javax.persistence.Table;

import beidanci.api.model.UserDto;
import beidanci.service.util.EmojiFilter;
import beidanci.service.util.Util;
import beidanci.util.Utils;

@Entity
@Table(name = "user", indexes = { @Index(name = "idx_userName", columnList = "user_name", unique = true) })
public class User extends UuidPo {


    @Column(name = "user_name", length = 100, unique = true)
    private String userName;
    @Column(name = "nick_name", length = 100)
    private String nickName;
    @Column(name = "password", length = 64)
    private String password;
    @Column(name = "last_login_time")
    private Date lastLoginTime;
    @Column(name = "last_share_time")
    private Date lastShareTime;
    @Column(name = "email", length = 100, unique = true)
    private String email;

    // 微信相关字段
    @Column(name = "wechat_open_id", length = 100, unique = true)
    private String wechatOpenId;
    
    @Column(name = "wechat_union_id", length = 100)
    private String wechatUnionId;
    
    @Column(name = "wechat_nickname", length = 200)
    private String wechatNickname;
    
    @Column(name = "wechat_avatar", length = 500)
    private String wechatAvatar;

    @Column(name = "last_learning_date")
    private Date lastLearningDate;
    @Column(name = "learned_days", nullable = false)
    private Integer learnedDays;

    /**
     * 正在学习的单词在今日学习单词列表中的序号
     */
    @Column(name = "last_learning_position")
    private Integer lastLearningPosition;

    @Column(name = "last_learning_mode")
    private Integer lastLearningMode;
    @Column(name = "learning_finished", nullable = false)
    private Boolean learningFinished;
    @Column(name = "invite_award_taken", nullable = false)
    private Boolean inviteAwardTaken;
    @Column(name = "is_super_admin", nullable = false)
    private Boolean isSuperAdmin;
    @Column(name = "is_admin", nullable = false)
    private Boolean isAdmin;
    @Column(name = "is_inputor", nullable = false)
    private Boolean isInputor;
    @Column(name = "is_sys_user", nullable = false)
    private Boolean isSysUser;
    @Column(name = "auto_play_sentence", nullable = false)
    private Boolean autoPlaySentence;
    @Column(name = "words_per_day", nullable = false)
    private Integer wordsPerDay;
    @Column(name = "daka_day_count", nullable = false)
    private Integer dakaDayCount;
    @Column(name = "mastered_words", nullable = false)
    private Integer masteredWordsCount;
    @Column(name = "cow_dung", nullable = false)
    private Integer cowDung;
    @Column(name = "throw_dice_chance", nullable = false)
    private Integer throwDiceChance;

    public Integer getGameScore() {
        return gameScore;
    }

    public void setGameScore(Integer gameScore) {
        this.gameScore = gameScore;
    }

    @Column(name = "game_score", nullable = false)
    private Integer gameScore;

    /**
     * 是否直接显示备选答案
     */
    @Column(name = "show_answers_directly", nullable = false)
    private Boolean showAnswersDirectly;
    /**
     * 是否自动朗读单词发音
     */
    @Column(name = "auto_play_word", nullable = false)
    private Boolean autoPlayWord;

    @OrderBy("dictId asc")
    private  List<LearningDict> learningDicts;

    private  List<MasteredWord> masteredWords;
    private  List<LearningWord> learningWords;

    private  List<Msg> sentMsgs;

    private  List<Msg> recvedMsgs;

    private List<UserGame> userGames;

    private List<UserCowDungLog> userCowDungLogs;

    private  List<Daka> dakas;

    private  List<UserScoreLog> userScoreLogs;
    @OrderBy("theDate asc")
    private  List<UserSnapshotDaily> userSnapshotDailys;
    @Column(name = "invited_by_id")
    private User invitedBy;

    @Column(name = "level_id")
    private Level level;

    private  List<User> invitedUsers;

    private  List<StudyGroup> studyGroups = new ArrayList<>();

    private  List<StudyGroup> createdStudyGroups;

    private  List<StudyGroup> managedStudyGroups;

    /**
     * ugc - 用户创建的例句
     */
    private  List<Sentence> createdSentences;

    /**
     * ugc - 用户创建的单词笔记
     */
    private  List<WordAdditionalInfo> createdWordNotes;

    /**
     * 缓存用户回答错误的单词
     */
    private  List<Word> wrongWords;

    /**
     * 连续打卡天数
     */
    @Column(name = "continuous_daka_day_count", nullable = false)
    private Integer continuousDakaDayCount;

    /**
     * 最大连续打卡天数
     */
    @Column(name = "max_continuous_daka_day_count", nullable = false)
    private Integer maxContinuousDakaDayCount;

    /**
     * 最近一次打卡的日期
     */
    @Column(name = "last_daka_date", nullable = true)
    private Date lastDakaDate;

    /**
     * 打卡积分
     */
    @Column(name = "daka_score", nullable = false)
    private Integer dakaScore;

    /**
     * 是否显示[都不对]的选项（增加选择题难度）
     */
    @Column(name = "enable_all_wrong", nullable = false)
    private Boolean enableAllWrong;


    /**
     * ASR答对判定规则：ONE/HALF/ALL
     */
    @Column(name = "asr_pass_rule", length = 10)
    private String asrPassRule;

    /**
     * 订阅相关字段（仅支持iOS平台）
     */
    
    // iOS订阅字段
    /**
     * iOS是否为会员
     */
    @Column(name = "is_premium_ios", nullable = false)
    private Boolean isPremiumIos;

    /**
     * iOS订阅到期时间
     */
    @Column(name = "subscription_expire_date_ios", nullable = true)
    private Date subscriptionExpireDateIos;

    /**
     * iOS订阅类型：monthly/annual
     */
    @Column(name = "subscription_type_ios", length = 20, nullable = true)
    private String subscriptionTypeIos;

    /**
     * iOS订阅状态：active/expired/cancelled
     */
    @Column(name = "subscription_status_ios", length = 20, nullable = true)
    private String subscriptionStatusIos;

    /**
     * iOS最后验证的收据数据（用于恢复购买）
     */
    @Column(name = "last_receipt_data_ios", columnDefinition = "TEXT", nullable = true)
    private String lastReceiptDataIos;

    /**
     * 强制视为会员（用于纠纷处理/白名单/补偿等）
     * 注意：该字段及其元数据仅用于“判定是否视为会员”，程序不主动根据时间自动修改 enabled。
     */
    @Column(name = "premium_override_enabled", nullable = true)
    private Boolean premiumOverrideEnabled;

    /**
     * 强制会员状态最后修改时间
     */
    @Column(name = "premium_override_update_time", nullable = true)
    private Date premiumOverrideUpdateTime;

    /**
     * 强制会员状态修改原因
     */
    @Column(name = "premium_override_reason", length = 500, nullable = true)
    private String premiumOverrideReason;

    /**
     * 强制会员状态延续时长（形如：10天/360秒/15分钟；null 表示永久）
     */
    @Column(name = "premium_override_duration", length = 50, nullable = true)
    private String premiumOverrideDuration;

    public Boolean getEnableAllWrong() {
        return enableAllWrong;
    }

    public void setEnableAllWrong(Boolean enableAllWrong) {
        this.enableAllWrong = enableAllWrong;
    }

    // iOS订阅字段的getter/setter
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

    /**
     * default constructor
     */
    public User() {
    }

    public User(String id) {
        this.id = id;
    }

    public Boolean getIsGuest() {
        return userName.startsWith("guest");
    }

    public Boolean getIsAdmin() {
        return isAdmin;
    }

    public void setIsAdmin(Boolean isAdmin) {
        this.isAdmin = isAdmin;
    }

    public Boolean getIsSysUser() {
        return isSysUser;
    }

    public void setIsSysUser(Boolean sysUser) {
        isSysUser = sysUser;
    }

    public Boolean getShowAnswersDirectly() {
        return showAnswersDirectly;
    }

    public void setShowAnswersDirectly(Boolean showAnswersDirectly) {
        this.showAnswersDirectly = showAnswersDirectly;
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

    public List<Word> getWrongWords() {
        return wrongWords;
    }

    public void setWrongWords(List<Word> wrongWords) {
        this.wrongWords = wrongWords;
    }

    // Constructors

    // Property accessors

    public String getUserName() {
        return this.userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public String getNickName() {
        return this.nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = EmojiFilter.filterEmoji(nickName);
    }

    public String getPassword() {
        return this.password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getEmail() {
        return this.email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getWechatOpenId() {
        return this.wechatOpenId;
    }

    public void setWechatOpenId(String wechatOpenId) {
        this.wechatOpenId = wechatOpenId;
    }

    public String getWechatUnionId() {
        return this.wechatUnionId;
    }

    public void setWechatUnionId(String wechatUnionId) {
        this.wechatUnionId = wechatUnionId;
    }

    public String getWechatNickname() {
        return this.wechatNickname;
    }

    public void setWechatNickname(String wechatNickname) {
        this.wechatNickname = wechatNickname;
    }

    public String getWechatAvatar() {
        return this.wechatAvatar;
    }

    public void setWechatAvatar(String wechatAvatar) {
        this.wechatAvatar = wechatAvatar;
    }

    public Date getLastLearningDate() {
        return this.lastLearningDate;
    }

    public void setLastLearningDate(Date lastLearningDate) {
        this.lastLearningDate = lastLearningDate;
    }

    public Integer getLearnedDays() {
        return this.learnedDays;
    }

    public void setLearnedDays(Integer learnedDays) {
        this.learnedDays = learnedDays;
    }

    public Integer getLastLearningPosition() {
        return this.lastLearningPosition;
    }

    public void setLastLearningPosition(Integer lastLearningPosition) {
        this.lastLearningPosition = lastLearningPosition;
    }

    public Integer getLastLearningMode() {
        return this.lastLearningMode;
    }

    public void setLastLearningMode(Integer lastLearningMode) {
        this.lastLearningMode = lastLearningMode;
    }

    public Boolean getLearningFinished() {
        return this.learningFinished;
    }

    public void setLearningFinished(Boolean learningFinished) {
        this.learningFinished = learningFinished;
    }

    public Integer getWordsPerDay() {
        return this.wordsPerDay;
    }

    public void setWordsPerDay(Integer wordsPerDay) {
        this.wordsPerDay = wordsPerDay;
    }

    public Integer getMasteredWordsCount() {
        return this.masteredWordsCount;
    }

    public void setMasteredWordsCount(Integer masteredWords) {
        this.masteredWordsCount = masteredWords;
    }

    public Integer getCowDung() {
        return this.cowDung;
    }

    public void setCowDung(Integer cowDung) {
        this.cowDung = cowDung;
    }

    @Override
    public int hashCode() {
        return userName.hashCode();
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj)
            return true;
        if (obj == null || getClass() != obj.getClass())
            return false;
        User user = (User) obj;
        return id.equals(user.getId());
    }

    public Integer getThrowDiceChance() {
        return throwDiceChance;
    }

    public void setThrowDiceChance(Integer throwDiceChance) {
        this.throwDiceChance = throwDiceChance;
    }

    public User getInvitedBy() {
        return invitedBy;
    }

    public void setInvitedBy(User invitedBy) {
        this.invitedBy = invitedBy;
    }

    public Boolean getInviteAwardTaken() {
        return inviteAwardTaken;
    }

    public void setInviteAwardTaken(Boolean inviteAwardTaken) {
        this.inviteAwardTaken = inviteAwardTaken;
    }

    public List<UserSnapshotDaily> getUserSnapshotDailys() {
        return userSnapshotDailys;
    }

    public void setUserSnapshotDailys(List<UserSnapshotDaily> userSnapshotDailys) {
        this.userSnapshotDailys = userSnapshotDailys;
    }

    

    public String getAsrPassRule() {
        return asrPassRule;
    }

    public void setAsrPassRule(String asrPassRule) {
        this.asrPassRule = asrPassRule;
    }

    public void setCreatedSentences(List<Sentence> createdSentences) {
        this.createdSentences = createdSentences;
    }

    public void setCreatedWordNotes(List<WordAdditionalInfo> createdWordNotes) {
        this.createdWordNotes = createdWordNotes;
    }

    public List<Sentence> getCreatedSentences() {
        return createdSentences;
    }

    public List<WordAdditionalInfo> getCreatedWordNotes() {
        return createdWordNotes;
    }

    /**
     * 获取用户从注册至今的存在天数
     *
     * @return
     */
    public int getExistDays() {

        long existTime = Utils.getPureDate(new Date()).getTime() - Utils.getPureDate(getCreateTime()).getTime();
        int existDays = (int) (existTime / 1000 / 60 / 60 / 24) + 1;

        return existDays;
    }

    /**
     * 获取用户的打卡率
     *
     * @return
     */
    public double getDakaRatio() {
        int existDays = getExistDays();
        double dakaRatio = (dakaDayCount + 0.0) / existDays;
        return dakaRatio;
    }

    public String getDisplayNickName() {
        return Util.getNickNameOfUser(this);
    }

    /**
     * 计算用户的打卡积分
     *
     * @return
     */
    public Integer getDakaScore() {
        return dakaScore;
    }

    /**
     * 获取用户的积分（包括打卡分和游戏积分）
     *
     * @return
     */
    public int getTotalScore() {
        return getDakaScore() + getGameScore();
    }

    public Boolean getIsSuperAdmin() {
        return isSuperAdmin;
    }

    public void setIsSuperAdmin(Boolean isSuperAdmin) {
        this.isSuperAdmin = isSuperAdmin;
    }

    public Integer getDakaDayCount() {
        return dakaDayCount;
    }

    public void setDakaDayCount(Integer dakaDayCount) {
        this.dakaDayCount = dakaDayCount;
    }

    public Boolean getAutoPlaySentence() {
        return autoPlaySentence;
    }

    public void setAutoPlaySentence(Boolean autoPlaySentence) {
        this.autoPlaySentence = autoPlaySentence;
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

    public Boolean getIsInputor() {
        return isInputor;
    }

    public void setIsInputor(Boolean isInputor) {
        this.isInputor = isInputor;
    }

    public List<LearningDict> getLearningDicts() {
        return learningDicts;
    }

    public void setLearningDicts(List<LearningDict> learningDicts) {
        this.learningDicts = learningDicts;
    }

    public List<MasteredWord> getMasteredWords() {
        return masteredWords;
    }

    public void setMasteredWords(List<MasteredWord> masteredWords) {
        this.masteredWords = masteredWords;
    }

    public List<LearningWord> getLearningWords() {
        return learningWords;
    }

    public void setLearningWords(List<LearningWord> learningWords) {
        this.learningWords = learningWords;
    }

    public List<Msg> getSentMsgs() {
        return sentMsgs;
    }

    public void setSentMsgs(List<Msg> sentMsgs) {
        this.sentMsgs = sentMsgs;
    }

    public List<Msg> getRecvedMsgs() {
        return recvedMsgs;
    }

    public void setRecvedMsgs(List<Msg> recvedMsgs) {
        this.recvedMsgs = recvedMsgs;
    }

    public List<UserGame> getUserGames() {
        return userGames;
    }

    public void setUserGames(List<UserGame> userGames) {
        this.userGames = userGames;
    }

    public List<UserCowDungLog> getUserCowDungLogs() {
        return userCowDungLogs;
    }

    public void setUserCowDungLogs(List<UserCowDungLog> userCowDungLogs) {
        this.userCowDungLogs = userCowDungLogs;
    }

    public List<Daka> getDakas() {
        return dakas;
    }

    public void setDakas(List<Daka> dakas) {
        this.dakas = dakas;
    }

    public List<UserScoreLog> getUserScoreLogs() {
        return userScoreLogs;
    }

    public void setUserScoreLogs(List<UserScoreLog> userScoreLogs) {
        this.userScoreLogs = userScoreLogs;
    }

    public List<User> getInvitedUsers() {
        return invitedUsers;
    }

    public void setInvitedUsers(List<User> invitedUsers) {
        this.invitedUsers = invitedUsers;
    }

    public List<StudyGroup> getStudyGroups() {
        return studyGroups;
    }

    public void setStudyGroups(List<StudyGroup> studyGroups) {
        this.studyGroups = studyGroups;
    }

    public List<StudyGroup> getCreatedStudyGroups() {
        return createdStudyGroups;
    }

    public void setCreatedStudyGroups(List<StudyGroup> createdStudyGroups) {
        this.createdStudyGroups = createdStudyGroups;
    }

    public List<StudyGroup> getManagedStudyGroups() {
        return managedStudyGroups;
    }

    public void setManagedStudyGroups(List<StudyGroup> managedStudyGroups) {
        this.managedStudyGroups = managedStudyGroups;
    }

    public Level getLevel() {
        return level;
    }

    public void setLevel(Level level) {
        this.level = level;
    }

    public Boolean getIsTodayLearningFinished() {
        return learningFinished
                && Util.isSameDay(lastLearningDate, new Date());
    }

    public Boolean getIsTodayLearningStarted() {
        return !lastLearningPosition.equals(-1)
                && Util.isSameDay(lastLearningDate, new Date());
    }

    /**
     * 将UserDto对象转换为User实体对象
     *
     * @param dto UserDto对象
     * @return User实体对象
     */
    public static User fromDto(UserDto dto) {
        User user = new User();
        user.setId(dto.getId());
        user.setUserName(dto.getUserName());
        user.setNickName(dto.getNickName());
        user.setPassword(dto.getPassword());
        user.setLastLoginTime(dto.getLastLoginTime());
        user.setLastShareTime(dto.getLastShareTime());
        user.setEmail(dto.getEmail());
        user.setLastLearningDate(dto.getLastLearningDate());

        Integer learnedDays = dto.getLearnedDays();
        user.setLearnedDays(learnedDays != null ? learnedDays : 0);

        Integer lastLearningPosition = dto.getLastLearningPosition();
        user.setLastLearningPosition(lastLearningPosition != null ? lastLearningPosition : -1);

        Integer lastLearningMode = dto.getLastLearningMode();
        user.setLastLearningMode(lastLearningMode != null ? lastLearningMode : 0);

        Boolean learningFinished = dto.getLearningFinished();
        user.setLearningFinished(learningFinished != null ? learningFinished : false);

        Boolean inviteAwardTaken = dto.getInviteAwardTaken();
        user.setInviteAwardTaken(inviteAwardTaken != null ? inviteAwardTaken : false);

        Boolean isSuperAdmin = dto.getIsSuperAdmin();
        user.setIsSuperAdmin(isSuperAdmin != null ? isSuperAdmin : false);

        Boolean isAdmin = dto.getIsAdmin();
        user.setIsAdmin(isAdmin != null ? isAdmin : false);

        Boolean isInputor = dto.getIsInputor();
        user.setIsInputor(isInputor != null ? isInputor : false);

        Boolean isSysUser = dto.getIsSysUser();
        user.setIsSysUser(isSysUser != null ? isSysUser : false);

        Boolean autoPlaySentence = dto.getAutoPlaySentence();
        user.setAutoPlaySentence(autoPlaySentence != null ? autoPlaySentence : true);

        Integer wordsPerDay = dto.getWordsPerDay();
        user.setWordsPerDay(wordsPerDay != null ? wordsPerDay : 20);

        Integer dakaDayCount = dto.getDakaDayCount();
        user.setDakaDayCount(dakaDayCount != null ? dakaDayCount : 0);

        Integer masteredWordsCount = dto.getMasteredWordsCount();
        user.setMasteredWordsCount(masteredWordsCount != null ? masteredWordsCount : 0);

        Integer cowDung = dto.getCowDung();
        user.setCowDung(cowDung != null ? cowDung : 0);

        Integer throwDiceChance = dto.getThrowDiceChance();
        user.setThrowDiceChance(throwDiceChance != null ? throwDiceChance : 0);

        Integer gameScore = dto.getGameScore();
        user.setGameScore(gameScore != null ? gameScore : 0);

        Boolean showAnswersDirectly = dto.getShowAnswersDirectly();
        user.setShowAnswersDirectly(showAnswersDirectly != null ? showAnswersDirectly : false);

        Boolean autoPlayWord = dto.getAutoPlayWord();
        user.setAutoPlayWord(autoPlayWord != null ? autoPlayWord : true);

        Integer continuousDakaDayCount = dto.getContinuousDakaDayCount();
        user.setContinuousDakaDayCount(continuousDakaDayCount != null ? continuousDakaDayCount : 0);

        Integer maxContinuousDakaDayCount = dto.getMaxContinuousDakaDayCount();
        user.setMaxContinuousDakaDayCount(maxContinuousDakaDayCount != null ? maxContinuousDakaDayCount : 0);

        user.setLastDakaDate(dto.getLastDakaDate());

        Integer dakaScore = dto.getDakaScore();
        user.setDakaScore(dakaScore != null ? dakaScore : 0);

        Boolean enableAllWrong = dto.getEnableAllWrong();
        user.setEnableAllWrong(enableAllWrong != null ? enableAllWrong : false);

        user.setAsrPassRule(dto.getAsrPassRule());

        // ========== 订阅/强制会员字段（客户端同步不一定包含，允许为 null） ==========
        user.setIsPremiumIos(dto.getIsPremiumIos() != null ? dto.getIsPremiumIos() : false);
        user.setSubscriptionExpireDateIos(dto.getSubscriptionExpireDateIos());
        user.setSubscriptionTypeIos(dto.getSubscriptionTypeIos());
        user.setSubscriptionStatusIos(dto.getSubscriptionStatusIos());
        user.setLastReceiptDataIos(dto.getLastReceiptDataIos());

        user.setPremiumOverrideEnabled(dto.getPremiumOverrideEnabled());
        user.setPremiumOverrideUpdateTime(dto.getPremiumOverrideUpdateTime());
        user.setPremiumOverrideReason(dto.getPremiumOverrideReason());
        user.setPremiumOverrideDuration(dto.getPremiumOverrideDuration());

        // 处理level字段
        Level level = new Level();
        level.setId(dto.getLevelId());
        user.setLevel(level);

        if (dto.getCreateTime() != null) {
            user.setCreateTime(dto.getCreateTime());
        }
        if (dto.getUpdateTime() != null) {
            user.setUpdateTime(dto.getUpdateTime());
        }
        return user;
    }

    /**
     * 将User实体对象转换为UserDto对象
     *
     * @return UserDto对象
     */
    public UserDto toDto() {
        UserDto dto = new UserDto();
        dto.setId(this.getId());
        dto.setUserName(this.getUserName());
        dto.setNickName(this.getNickName());
        dto.setPassword(this.getPassword());
        dto.setLastLoginTime(this.getLastLoginTime());
        dto.setLastShareTime(this.getLastShareTime());
        dto.setEmail(this.getEmail());
        dto.setLastLearningDate(this.getLastLearningDate());
        dto.setLearnedDays(this.getLearnedDays());
        dto.setLastLearningPosition(this.getLastLearningPosition());
        dto.setLastLearningMode(this.getLastLearningMode());
        dto.setLearningFinished(this.getLearningFinished());
        dto.setInviteAwardTaken(this.getInviteAwardTaken());
        dto.setIsSuperAdmin(this.getIsSuperAdmin());
        dto.setIsAdmin(this.getIsAdmin());
        dto.setIsInputor(this.getIsInputor());
        dto.setIsSysUser(this.getIsSysUser());
        dto.setAutoPlaySentence(this.getAutoPlaySentence());
        dto.setWordsPerDay(this.getWordsPerDay());
        dto.setDakaDayCount(this.getDakaDayCount());
        dto.setMasteredWordsCount(this.getMasteredWordsCount());
        dto.setCowDung(this.getCowDung());
        dto.setThrowDiceChance(this.getThrowDiceChance());
        dto.setGameScore(this.getGameScore());
        dto.setShowAnswersDirectly(this.getShowAnswersDirectly());
        dto.setAutoPlayWord(this.getAutoPlayWord());
        dto.setContinuousDakaDayCount(this.getContinuousDakaDayCount());
        dto.setMaxContinuousDakaDayCount(this.getMaxContinuousDakaDayCount());
        dto.setLastDakaDate(this.getLastDakaDate());
        dto.setDakaScore(this.getDakaScore());
        dto.setEnableAllWrong(this.getEnableAllWrong());
        dto.setAsrPassRule(this.getAsrPassRule());
        if (this.getLevel() != null) {
            dto.setLevelId(this.getLevel().getId());
        }

        // ========== 订阅/强制会员字段 ==========
        dto.setIsPremiumIos(this.getIsPremiumIos());
        dto.setSubscriptionExpireDateIos(this.getSubscriptionExpireDateIos());
        dto.setSubscriptionTypeIos(this.getSubscriptionTypeIos());
        dto.setSubscriptionStatusIos(this.getSubscriptionStatusIos());
        dto.setLastReceiptDataIos(this.getLastReceiptDataIos());

        dto.setPremiumOverrideEnabled(this.getPremiumOverrideEnabled());
        dto.setPremiumOverrideUpdateTime(this.getPremiumOverrideUpdateTime());
        dto.setPremiumOverrideReason(this.getPremiumOverrideReason());
        dto.setPremiumOverrideDuration(this.getPremiumOverrideDuration());

        dto.setCreateTime(this.getCreateTime());
        dto.setUpdateTime(this.getUpdateTime());
        return dto;
    }

    public void setDakaScore(Integer dakaScore) {
        this.dakaScore = dakaScore;
    }
}
