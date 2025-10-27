package beidanci.service.po;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.Index;
import javax.persistence.JoinColumn;
import javax.persistence.JoinTable;
import javax.persistence.ManyToMany;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.OrderBy;
import javax.persistence.Table;

import beidanci.api.model.UserDto;
import beidanci.service.util.EmojiFilter;
import beidanci.service.util.Util;
import beidanci.util.Utils;

@Entity
@Table(name = "user", indexes = { @Index(name = "idx_userName", columnList = "userName", unique = true) })
public class User extends UuidPo {


    @Column(name = "userName", length = 100, unique = true)
    private String userName;
    @Column(name = "nickName", length = 100)
    private String nickName;
    @Column(name = "password", length = 64)
    private String password;
    @Column(name = "lastLoginTime")
    private Date lastLoginTime;
    @Column(name = "lastShareTime")
    private Date lastShareTime;
    @Column(name = "email", length = 100, unique = true)
    private String email;

    // 微信相关字段
    @Column(name = "wechatOpenId", length = 100, unique = true)
    private String wechatOpenId;
    
    @Column(name = "wechatUnionId", length = 100)
    private String wechatUnionId;
    
    @Column(name = "wechatNickname", length = 200)
    private String wechatNickname;
    
    @Column(name = "wechatAvatar", length = 500)
    private String wechatAvatar;

    @Column(name = "lastLearningDate")
    private Date lastLearningDate;
    @Column(name = "learnedDays", nullable = false)
    private Integer learnedDays;

    /**
     * 正在学习的单词在今日学习单词列表中的序号
     */
    @Column(name = "lastLearningPosition")
    private Integer lastLearningPosition;

    @Column(name = "lastLearningMode")
    private Integer lastLearningMode;
    @Column(name = "learningFinished", nullable = false)
    private Boolean learningFinished;
    @Column(name = "inviteAwardTaken", nullable = false)
    private Boolean inviteAwardTaken;
    @Column(name = "isSuper", nullable = false)
    private Boolean isSuper;
    @Column(name = "isAdmin", nullable = false)
    private Boolean isAdmin;
    @Column(name = "isInputor", nullable = false)
    private Boolean isInputor;
    @Column(name = "isSysUser", nullable = false)
    private Boolean isSysUser;
    @Column(name = "autoPlaySentence", nullable = false)
    private Boolean autoPlaySentence;
    @Column(name = "wordsPerDay", nullable = false)
    private Integer wordsPerDay;
    @Column(name = "dakaDayCount", nullable = false)
    private Integer dakaDayCount;
    @Column(name = "masteredWords", nullable = false)
    private Integer masteredWordsCount;
    @Column(name = "cowDung", nullable = false)
    private Integer cowDung;
    @Column(name = "throwDiceChance", nullable = false)
    private Integer throwDiceChance;

    public Integer getGameScore() {
        return gameScore;
    }

    public void setGameScore(Integer gameScore) {
        this.gameScore = gameScore;
    }

    @Column(name = "gameScore", nullable = false)
    private Integer gameScore;

    /**
     * 是否直接显示备选答案
     */
    @Column(name = "showAnswersDirectly", nullable = false)
    private Boolean showAnswersDirectly;
    /**
     * 是否自动朗读单词发音
     */
    @Column(name = "autoPlayWord", nullable = false)
    private Boolean autoPlayWord;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    @OrderBy("dictId asc")
    private  List<LearningDict> learningDicts;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private  List<MasteredWord> masteredWords;
    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private  List<LearningWord> learningWords;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "fromUser", fetch = FetchType.LAZY)
    private  List<Msg> sentMsgs;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "toUser", fetch = FetchType.LAZY)
    private  List<Msg> recvedMsgs;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private List<UserGame> userGames;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private List<UserCowDungLog> userCowDungLogs;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private  List<Daka> dakas;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private  List<UserScoreLog> userScoreLogs;
    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    @OrderBy("theDate asc")
    private  List<UserSnapshotDaily> userSnapshotDailys;
    @ManyToOne
    @JoinColumn(name = "invitedById", nullable = true)
    private User invitedBy;

    @ManyToOne
    @JoinColumn(name = "levelId", nullable = true)
    private Level level;

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "invitedBy", fetch = FetchType.LAZY)
    private  List<User> invitedUsers;

    @ManyToMany(mappedBy = "users")
    private  List<StudyGroup> studyGroups = new ArrayList<>();

    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "creator", fetch = FetchType.LAZY)
    private  List<StudyGroup> createdStudyGroups;

    @ManyToMany(mappedBy = "managers")
    private  List<StudyGroup> managedStudyGroups;

    /**
     * ugc - 用户创建的例句
     */
    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "author", fetch = FetchType.LAZY)
    private  List<Sentence> createdSentences;

    /**
     * ugc - 用户创建的单词笔记
     */
    @OneToMany(cascade = { CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE }, mappedBy = "user", fetch = FetchType.LAZY)
    private  List<WordAdditionalInfo> createdWordNotes;

    /**
     * 缓存用户回答错误的单词
     */
    @ManyToMany
    @JoinTable(name = "user_wrong_word", joinColumns = { @JoinColumn(name = "userId") }, inverseJoinColumns = {
            @JoinColumn(name = "wordId") })
    private  List<Word> wrongWords;

    /**
     * 连续打卡天数
     */
    @Column(name = "continuousDakaDayCount", nullable = false)
    private Integer continuousDakaDayCount;

    /**
     * 最大连续打卡天数
     */
    @Column(name = "maxContinuousDakaDayCount", nullable = false)
    private Integer maxContinuousDakaDayCount;

    /**
     * 最近一次打卡的日期
     */
    @Column(name = "lastDakaDate", nullable = true)
    private Date lastDakaDate;

    /**
     * 打卡积分
     */
    @Column(name = "dakaScore", nullable = false)
    private Integer dakaScore;

    /**
     * 是否显示[都不对]的选项（增加选择题难度）
     */
    @Column(name = "enableAllWrong", nullable = false)
    private Boolean enableAllWrong;


    /**
     * ASR答对判定规则：ONE/HALF/ALL
     */
    @Column(name = "asrPassRule", length = 10)
    private String asrPassRule;

    public Boolean getEnableAllWrong() {
        return enableAllWrong;
    }

    public void setEnableAllWrong(Boolean enableAllWrong) {
        this.enableAllWrong = enableAllWrong;
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

    public Boolean getIsSuper() {
        return isSuper;
    }

    public void setIsSuper(Boolean isSuper) {
        this.isSuper = isSuper;
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

        Boolean isSuper = dto.getIsSuper();
        user.setIsSuper(isSuper != null ? isSuper : false);

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
        dto.setIsSuper(this.getIsSuper());
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
        dto.setCreateTime(this.getCreateTime());
        dto.setUpdateTime(this.getUpdateTime());
        return dto;
    }

    public void setDakaScore(Integer dakaScore) {
        this.dakaScore = dakaScore;
    }
}
