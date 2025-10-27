package beidanci.service.bo;

import java.io.IOException;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;

import javax.annotation.PostConstruct;
import javax.naming.NamingException;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.hibernate.HibernateException;
import org.hibernate.Session;
import org.hibernate.query.Query;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import beidanci.api.Result;
import beidanci.api.model.CheckBy;
import beidanci.api.model.ClientType;
import beidanci.api.model.DakaDto;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.LearningDictDto;
import beidanci.api.model.LearningWordDto;
import beidanci.api.model.LevelVo;
import beidanci.api.model.MasteredWordDto;
import beidanci.api.model.UserCowDungLogDto;
import beidanci.api.model.UserDbLogDto;
import beidanci.api.model.UserOperDto;
import beidanci.api.model.UserStudyStepDto;
import beidanci.api.model.UserVo;
import beidanci.api.model.WordVo;
import beidanci.api.model.WrongWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Daka;
import beidanci.service.po.DakaId;
import beidanci.service.po.Dict;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningDictId;
import beidanci.service.po.LearningWord;
import beidanci.service.po.Level;
import beidanci.service.po.LoginLog;
import beidanci.service.po.Msg;
import beidanci.service.po.StudyGroup;
import beidanci.service.po.User;
import beidanci.service.po.UserCowDungLog;
import beidanci.service.po.UserDbLog;
import beidanci.service.po.UserGame;
import beidanci.service.po.UserSnapshotDaily;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;
import beidanci.util.Constants;
import beidanci.util.MD5Utils;
import beidanci.util.Utils;

@Service
public class UserBo extends BaseBo<User> {
    private static final Logger logger = LoggerFactory.getLogger(UserBo.class);
    private static volatile User sysUser_sys = null;
    private static volatile User sysUser_deleted = null;

    @Autowired
    private TransactionTemplate trxTemplate;

    @Autowired
    WordCache wordCache;

    @Autowired
    UserSnapshotDailyBo userSnapshotDailyBo;

    @Autowired
    UserGameBo userGameBo;

    @Autowired
    UserCowDungLogBo userCowDungLogBo;

    @Autowired
    StudyGroupBo studyGroupBo;

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    UserStudyStepBo userStudyStepBo;

    @Autowired
    MsgBo msgBo;

    @Autowired
    EventBo eventBo;

    @Autowired
    LevelBo levelBo;

    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    LoginLogBo loginLogBo;

    @Autowired
    UserDbLogBo userDbLogBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    WordBo wordBo;

    @Autowired
    DakaBo dakaBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    SysParamBo sysParamBo;

    @Autowired
    BookMarkBo bookMarkBo;

    @Autowired
    UserOperBo userOperBo;

    @Autowired
    private UserDbVersionDao userDbVersionDao;

    @Autowired
    private WrongWordBo wrongWordBo;

    @Autowired
    private MasteredWordBo masteredWordBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<User>() {
        });
    }

    public int getUserDbVersion(String userId) {
        return userDbVersionDao.getUserDbVersion(getSession(), userId);
    }

    /**
     * 覆盖用户生词本
     */
    public int overwriteRawDict(String userId, ArrayList<DictWordDto> dictWords) throws IllegalAccessException {
        return dictWordBo.overwriteRawDictForUser(userId, dictWords);
    }

    /**
     * 获取系统用户，用于一些需要系统用户参与的操作
     *
     * @return 系统用户
     */
    public User getSysUser_sys(boolean openNewSession) {
        if (sysUser_sys == null) {
            sysUser_sys = getByUserName(Constants.SYS_USER_SYS, openNewSession);
        }
        return sysUser_sys;
    }

    public User getSysUser_deleted(boolean openNewSession) {
        if (sysUser_deleted == null) {
            sysUser_deleted = getByUserName(Constants.SYS_USER_DELETED, openNewSession);

            if (sysUser_deleted == null) {
                sysUser_deleted = Util.genNewUser(Constants.SYS_USER_DELETED, "YouCantGuessIt~", "已删除用户(虚拟)", null,
                        null, sysParamBo,
                        dictBo, this, learningDictBo, true);
                createEntity(sysUser_deleted);
            }

        }
        return sysUser_deleted;
    }

    public List<User> findUsersTotalScoreMoreThan(int score, boolean includeGuest) {
        String queryString;
        if (includeGuest) {
            queryString = "from User u where (u.gameScore > 0 or u.dakaScore > 0)";
        } else {
            queryString = "from User u where u.userName not like 'guest%' and u.userName not like 'guess%' and u.userName not like '游客%' and (u.gameScore > 0 or u.dakaScore > 0)";
        }

        try (Session session = openSession()) {
            Query<User> query = session.createQuery(queryString, User.class);
            return query.list();
        }
    }

    @Transactional
    public void deleteUnStartedDicts(User user, HashSet<String> exceptFor)
            throws IllegalArgumentException, IllegalAccessException {
        for (Iterator<LearningDict> i = user.getLearningDicts().iterator(); i.hasNext();) {
            LearningDict learningDict = i.next();
            if (learningDict.getCurrentWord() == null && !exceptFor.contains(learningDict.getDict().getId())) {
                learningDictBo.deleteEntity(learningDict);
                i.remove();
            }
        }
    }

    /**
     * 删除生命值为0,且不是今天学习的单词
     */
    @Transactional
    public void deleteFinishedLearningWordsExceptToday(User user)
            throws IllegalArgumentException, IllegalAccessException {
        for (Iterator<LearningWord> i = user.getLearningWords().iterator(); i.hasNext();) {
            LearningWord learningWord = i.next();
            if (learningWord.getLifeValue() == 0 && !Util.isSameDay(learningWord.getLastLearningDate(), new Date())) {
                learningWordBo.deleteEntity(learningWord);
                i.remove();
            }
        }
        updateEntity(user);
    }

    /**
     * 删除用户收藏的某本单词书，如果该单词书还没有开始学习，则也从正在学习的单词书中删除
     *
     * @param user
     * @param dictName
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    @Transactional
    public Result<Void> deleteSelectedDict(User user, String dictId)
            throws IllegalArgumentException, IllegalAccessException {
        Dict dict = dictBo.findById(dictId, false);
        if (dict.getName().equals("生词本")) {
            // 删除生词本，实际行为是清空生词本
            Dict rawDict = dictBo.getRawWordDict(user);
            dictBo.clearDict(user, rawDict);
            return Result.success(null);
        }
        for (Iterator<LearningDict> i = user.getLearningDicts().iterator(); i.hasNext();) {
            LearningDict selectedDict = i.next();
            if (selectedDict.getDict().getId().equals(dictId)) {
                learningDictBo.deleteEntity(selectedDict);
                i.remove();
            }
        }
        updateEntity(user);
        return Result.success(null);
    }

    /**
     * 随机从指定的某本单词书中取一个单词。
     *
     * @param selectedLearningDicts 单词书列表，将从中随机选出一本，并取一个单词。注意，指定的单词书中可能也包含生词本（生词本被模拟成一本特殊的单词书）
     * @return
     * @throws EmptySpellException
     * @throws InvalidMeaningFormatException
     * @throws ParseException
     * @throws IOException
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    private WordVo getNewWordFromDicts(List<LearningDict> selectedLearningDicts, User user)
            throws IOException, ParseException,
            InvalidMeaningFormatException, EmptySpellException, IllegalArgumentException, IllegalAccessException {

        // 将单词书打乱次序，模拟随机从某本单词书取词的效果
        Collections.shuffle(selectedLearningDicts);

        // 从当前学习的某本单词书中取下一个单词
        WordVo wordToLearn;
        for (LearningDict learningDict : selectedLearningDicts) {

            // 获取该单词书当前的学习位置
            Integer wordOrderInDict = learningDict.getCurrentWordSeq();
            if (wordOrderInDict == null) {// 尚未开始学习该单词书
                wordOrderInDict = 0;
            }

            // 如果该单词书尚未被学完，则取当前单词的下一个单词，并更新当前单词
            // Dict realDict = dictBo.findById(learningDict.getDict().getId());
            while (wordOrderInDict < learningDict.getDict().getWordCount()) {
                // 从单词书中取下一个单词
                WordVo nextWord = dictWordBo.getWordOfOrder(learningDict.getDict().getId(),
                        wordOrderInDict + 1);

                // 判断该单词是否已经取出过
                List<LearningDict> allLearningDicts = new ArrayList<>(user.getLearningDicts());// 用户所有学习中的单词书(包括当前并未选中的)
                boolean isLearned = isWordLearned(nextWord.getId(), allLearningDicts, learningDict);

                // 更新该单词书的当前单词
                wordToLearn = wordCache.getWordBySpell(nextWord.getSpell(), new String[] {
                        "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
                learningDict.setCurrentWord(new Word(nextWord.getId()));
                learningDict.setCurrentWordSeq(wordOrderInDict + 1);
                learningDictBo.updateEntity(learningDict);

                // 如果该单词已经学习过，则略过, 否则返回该单词
                if (isLearned) {
                    wordOrderInDict++;
                } else {
                    return wordToLearn;
                }
            }
        }

        return null;
    }

    /**
     * 从用户的某本单词书中选出一个单词学习
     *
     * @return 某个未学过的单词，如果所有单词都学过，return null.
     * @throws SQLException
     * @throws IOException
     * @throws ParseException
     * @throws InvalidMeaningFormatException
     * @throws EmptySpellException
     * @throws NamingException
     * @throws ClassNotFoundException
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public WordVo getNewWordToLearn(User user, List<LearningDict> highPriorityLearningDicts,
            List<LearningDict> lowPriorityLearningDicts)
            throws SQLException, IOException, ParseException, InvalidMeaningFormatException, EmptySpellException,
            NamingException, ClassNotFoundException, IllegalArgumentException, IllegalAccessException {

        // 从高优先级单词书中随机取一个单词
        WordVo word = getNewWordFromDicts(highPriorityLearningDicts, user);

        // 从普通优先级单词书中随机取一个单词
        if (word == null) {
            word = getNewWordFromDicts(lowPriorityLearningDicts, user);
        }

        return word;
    }

    /**
     * 获取指定优先级的所有学习中单词书
     *
     * @param user
     * @param isHighPriority true：获取高优先级的单词书，false：获取普通优先级的单词书
     * @return 指定优先级的所有学习中单词书（已过滤掉用户取消选中的单词书，另外生词本可能被模拟成一本特殊单词书）
     */
    public List<LearningDict> getLearningDictsWithPriority(User user, boolean isHighPriority) {
        // 获取用户所有学习中的单词书
        List<LearningDict> learningDicts = new ArrayList<>(user.getLearningDicts());

        // 选出指定优先级的单词书
        for (Iterator<LearningDict> i = learningDicts.iterator(); i.hasNext();) {
            LearningDict learningDict = i.next();
            LearningDictId id = new LearningDictId(user.getId(), learningDict.getDict().getId());
            LearningDict selectedDict = learningDictBo.findById(id, false);

            if (selectedDict == null) {// 单词书已经取消了选中
                i.remove();
            } else if (selectedDict.getIsPrivileged() != isHighPriority) {// 单词书不是指定的优先级
                i.remove();
            }
        }

        return learningDicts;
    }

    /**
     * 判断某个单词是否已经被该用户从任何一本单词书中取出过
     *
     * @param learningDicts
     * @return
     */
    private boolean isWordLearned(String wordId, List<LearningDict> learningDicts, LearningDict ignoreDict) {
        for (LearningDict dict : learningDicts) {
            if (dict.equals(ignoreDict)) { // 性能优化
                continue;
            }
            int wordOrder = dictWordBo.getOrderOfWordId(dict.getDict().getId(), wordId);

            Integer currentWordSeq = dict.getCurrentWordSeq();
            if (wordOrder != -1 && wordOrder <= (currentWordSeq == null ? -1 : currentWordSeq)) {
                return true;
            }
        }
        return false;
    }

    public void deleteDeadUsers(int idleDays) throws IllegalAccessException {
        // 查询长期未登录的用户
        String hql = "from User where isSysUser = 0 and lastLoginTime < :time";
        Query<User> query = getSession().createQuery(hql, User.class);
        query.setCacheable(false);
        query.setParameter("time", Utils.localDate2Date(LocalDate.now().plusDays(-idleDays)));
        List<User> users = query.list();
        logger.info("发现{}个长期未登录用户", users.size());

        // 删除这些用户
        for (User user : users) {
            deleteUser(user);
            logger.info("删除了用户：{}", user.getDisplayNickName());
        }
    }

    public void deleteUser(User user) throws IllegalArgumentException, IllegalAccessException {
        trxTemplate.execute((status -> {
            try {
                // 删除用户选择的单词书
                for (LearningDict dict : user.getLearningDicts()) {
                    learningDictBo.deleteEntity(dict);
                }
                user.getLearningDicts().clear();
                updateEntity(user);

                // 删除用户的自定义单词书
                List<Dict> customedDicts = dictBo.getOwnDicts(user, Integer.MAX_VALUE);
                for (Dict dict : customedDicts) {
                    dictBo.deleteById(dict.getId());
                }

                // 删除用户的学习步骤
                userStudyStepBo.clearUserStudySteps(user.getId());

                // 删除用户正在学习的单词
                for (LearningWord word : user.getLearningWords()) {
                    learningWordBo.deleteEntity(word);
                }
                user.getLearningWords().clear();
                updateEntity(user);

                // 删除用户已掌握的单词
                Session session = sessionFactory.getCurrentSession();
                Query<?> query = session.createQuery("delete MasteredWord where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户发送的消息
                for (Msg msg : user.getSentMsgs()) {
                    msgBo.deleteEntity(msg);
                }
                user.getSentMsgs().clear();
                updateEntity(user);

                // 删除用户接收的消息
                query = session.createQuery("delete Msg where toUser = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户相关事件
                eventBo.clearUserEvents(user);

                // 删除用户的打卡记录
                for (Daka daka : user.getDakas()) {
                    dakaBo.deleteEntity(daka);
                }
                user.getDakas().clear();
                updateEntity(user);

                // 删除用户的魔法泡泡收支记录
                for (UserCowDungLog userCowDungLog : user.getUserCowDungLogs()) {
                    userCowDungLogBo.deleteEntity(userCowDungLog);
                }
                user.getUserCowDungLogs().clear();
                updateEntity(user);

                // 删除用户的游戏记录
                for (UserGame userGame : user.getUserGames()) {
                    userGameBo.deleteEntity(userGame);
                }
                user.getUserGames().clear();
                updateEntity(user);

                // 删除用户每日快照记录
                for (UserSnapshotDaily userLearnProgress : user.getUserSnapshotDailys()) {
                    userSnapshotDailyBo.deleteEntity(userLearnProgress);
                }
                user.getUserSnapshotDailys().clear();
                updateEntity(user);

                // 删除用户积分记录
                query = session.createQuery("delete UserScoreLog where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 清空错题集关联
                query = session.createNativeQuery("delete from user_wrong_word where userId = :userId")
                        .setParameter("userId", user.getId());
                query.executeUpdate();

                // 解除该用户邀请的用户对其的引用
                for (User invitedUser : user.getInvitedUsers()) {
                    invitedUser.setInvitedBy(findById("nulluser"));
                    updateEntity(invitedUser);
                }
                user.getInvitedUsers().clear();
                updateEntity(user);

                // 退出所在的小组
                for (StudyGroup group : user.getCreatedStudyGroups()) {
                    studyGroupBo.exitGroup(user, group.getId());
                }
                for (StudyGroup group : user.getStudyGroups()) {
                    studyGroupBo.exitGroup(user, group.getId());
                }
                for (StudyGroup group : user.getManagedStudyGroups()) {
                    studyGroupBo.exitGroup(user, group.getId());
                }

                // 删除登录日志
                loginLogBo.cleanLoginLogs(user);

                // 删除用户数据库日志
                query = session.createQuery("delete UserDbLog where userId = :userId")
                        .setParameter("userId", user.getId());
                query.executeUpdate();

                // 将用户UGC转让给系统虚拟用户
                query = session
                        .createQuery("update WordAdditionalInfo set user = :sysUser where user = :user")
                        .setParameter("sysUser", getSysUser_deleted(false))
                        .setParameter("user", user);
                query.executeUpdate();
                query = session.createQuery("update Sentence set author = :sysUser where author = :user")
                        .setParameter("sysUser", getSysUser_deleted(false))
                        .setParameter("user", user);
                query.executeUpdate();
                query = session.createQuery("delete InfoVoteLog where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();
                query = session
                        .createQuery("update WordImage set author = :sysUser  where author = :user")
                        .setParameter("sysUser", getSysUser_deleted(false))
                        .setParameter("user", user);
                query.executeUpdate();
                query = session
                        .createQuery("update WordShortDescChinese set author = :sysUser  where author = :user")
                        .setParameter("sysUser", getSysUser_deleted(false))
                        .setParameter("user", user);
                query.executeUpdate();

                // 不再作为论坛管理员
                query = session
                        .createNativeQuery("delete from forum_and_manager_link where userId = :userId")
                        .setParameter("userId", user.getId());
                query.executeUpdate();

                // 删除用户回复的帖子
                query = session.createQuery("delete ForumPostReply where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户的帖子
                query = session.createQuery("delete ForumPost where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户报错
                query = session.createQuery("delete ErrorReport where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户数据库版本记录
                query = session.createQuery("delete UserDbVersion where user = :user")
                        .setParameter("user", user);
                query.executeUpdate();

                // 删除用户记录
                deleteEntity(user);
                return null;
            } catch (IllegalAccessException | IllegalArgumentException | HibernateException e) {
                status.setRollbackOnly();
                throw new RuntimeException("删除用户异常，事务将回滚", e);
            }
        }));
    }

    public List<User> findByEmail(String email) {
        String hql = "from User u where email = :email";
        Query<User> query = getSession().createQuery(hql, User.class);
        query.setParameter("email", email);
        return query.list();
    }

    public User getByUserName(String userName, boolean openNewSession) {
        Session session = openNewSession ? openSession() : getSession();
        try {
            String hql = "from User u where userName = :userName";
            return (User) session.createQuery(hql)
                    .setParameter("userName", userName)
                    .uniqueResult();
        } finally {
            if (openNewSession) {
                session.close();
            }
        }
    }

    public List<User> findAll() {
        String hql = "from User";
        Session session = getSession();
        Query<User> query = session.createQuery(hql, User.class);
        return query.list();
    }

    /**
     * 随机挑选一个非游客用户的昵称（优先 displayNickName，其次 nickName，再次 userName）。
     * 采用新会话查询，避免在无事务的socket线程中获取currentSession失败。
     */
    public String pickRandomNonGuestNickName() {
        try (Session session = openSession()) {
            List<User> candidates = session
                    .createQuery("from User u where u.userName not like 'guest%'", User.class)
                    .setMaxResults(50)
                    .list();
            if (candidates == null || candidates.isEmpty()) {
                return null;
            }
            java.util.Collections.shuffle(candidates);
            User picked = candidates.get(0);
            return beidanci.service.util.Util.getNickNameOfUser(picked);
        }
    }

    /**
     * 随机挑选一个“超过指定天数未登录”且“玩过游戏”的真实用户，用作机器人陪玩。
     * 采用新会话查询，避免在无事务的socket线程中获取currentSession失败。
     */
    public User pickRandomInactiveGamer(int idleDays, int maxCandidates) {
        try (Session session = openSession()) {
            String hql = "select distinct ug.user from UserGame ug where ug.user.isSysUser = false and ug.user.lastLoginTime < :time";
            Query<User> query = session.createQuery(hql, User.class);
            query.setParameter("time", Utils.localDate2Date(LocalDate.now().plusDays(-idleDays)));
            query.setMaxResults(maxCandidates);
            List<User> candidates = query.list();
            if (candidates == null || candidates.isEmpty()) {
                return null;
            }
            java.util.Collections.shuffle(candidates);
            return candidates.get(0);
        }
    }

    /**
     * 验证用户凭据
     *
     * @param request
     * @return 如果验证成功，返回User对象，否则返回null
     * @throws IllegalArgumentException
     */
    public Result<User> checkUser(HttpServletRequest request, String userName, String email, String password,
            final CheckBy checkBy, ClientType clientType, String clientVersion)
            throws IllegalArgumentException {

        logger.info(String.format("用户正在验证... IP[%s] checkBy[%s] clientType[%s] UA[%s] ver[%s]",
                Util.getClientIP(request), checkBy,
                clientType,
                request.getHeader("User-Agent"), clientVersion));

        // 完全去掉鉴权逻辑，无论输入什么都返回成功
        User user = null;
        if (null == checkBy) {
            throw new IllegalArgumentException("不支持的验证方式:" + checkBy);
        } else
            switch (checkBy) {
                case UserName -> {
                    // 检查用户名是否存在
                    user = getByUserName(userName, false);
                    if (user == null) {
                        // 如果用户不存在，创建一个新用户
                        user = Util.genNewUser(userName + "@example.com", password, userName, userName + "@example.com",
                                null, sysParamBo,
                                dictBo, this, learningDictBo, false);
                        user.setWordsPerDay(20);
                        try {
                            createEntity(user);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败", e);
                        }
                    }
                }
                case Email -> {
                    List<User> users = findByEmail(email);
                    if (!users.isEmpty()) {
                        user = users.get(0);
                    } else {
                        // 如果Email对应的账户不存在，自动创建账户
                        String nickname = email != null && email.contains("@") ? email.split("@")[0] : "user";
                        user = Util.genNewUser(email, password, nickname, email, null, sysParamBo,
                                dictBo, this, learningDictBo, false);
                        user.setWordsPerDay(20);
                        try {
                            createEntity(user);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败", e);
                        }
                    }
                }
                default -> throw new IllegalArgumentException("不支持的验证方式:" + checkBy);
            }

        return new Result<>(true, null, user);
    }

    @Transactional
    public Result<User> doCheckUser(String userName, String email, String passwordFromClient, CheckBy checkBy,
            ClientType clientType, String clientVersion,
            HttpServletRequest request, HttpServletResponse response)
            throws IllegalArgumentException, IllegalAccessException {
        Result<User> checkResult = checkUser(request, userName, email, passwordFromClient, checkBy, clientType,
                clientVersion);
        if (checkResult.isSuccess()) {
            User user = checkResult.getData();

            // 保存登录日志（无论是否登录成功）
            // 保存登录日志
            LoginLog loginLog = new LoginLog(getByUserName(user.getUserName(), false), new Date());
            loginLogBo.createEntity(loginLog);

            // 如果用户还没有学习步骤数据，创建之
            userStudyStepBo.initUserStudySteps(clientType, user.getId());
            return new Result<>(true,
                    null, user);
        } else {
            return new Result<>(false, checkResult.getMsg(), null);
        }
    }

    public void doLogout(HttpServletRequest request) throws ServletException {
        request.logout();
        request.getSession().invalidate();
    }

    /**
     * 保存掷骰子得到的魔法泡泡奖励
     *
     * @param delta
     * @param reason
     * @param user
     * @return
     * @throws IllegalArgumentException
     * @throws IllegalAccessException
     */
    public String saveCowDungOfThrowingDice(int delta, String reason, User user)
            throws IllegalArgumentException, IllegalAccessException {
        // 不再翻倍，直接使用传入的delta值
        // delta = delta;

        // 根据配置对魔法泡泡数乘以一个倍数(节假日)
        delta = (int) (delta * sysParamUtil.getHolidayCowDungRatio());

        // 如果用户是因为掷骰子得到魔法泡泡，将掷骰子机会数量减 1
        if (reason.equals("throw dice after learning")) {
            // 如果用户掷骰子的机会数都为0了，用户还在掷骰子，这样的情况应该不存在，
            // 但也可能是客户端采取了某些特殊手段
            if (user.getThrowDiceChance() == 0) {
                logger.warn("发现异常情况：用户掷骰子的机会数都为0了，用户还在掷骰子, user: " + user.getUserName());
                return "保存魔法泡泡失败";
            }

            user.setThrowDiceChance(user.getThrowDiceChance() - 1);
            updateEntity(user);

            logger.info(String.format("用户[%s]打卡后掷骰子得到[%d]个魔法泡泡", Util.getNickNameOfUser(user), delta));
        }

        // 更新用户的魔法泡泡数
        adjustCowDung(user, delta, reason);

        return null;
    }

    public void saveWordsPerDay(User user, int wordsPerDay) throws IllegalAccessException {
        user.setWordsPerDay(wordsPerDay);
        updateEntity(user);
    }

    @Transactional(readOnly = true)
    public UserVo getUserVoById(String userId) {
        User user = findById(userId);
        if (user == null) {
            return null;
        }

        UserVo userVo = BeanUtils.makeVo(user, UserVo.class, new String[] { "invitedBy", "StudyGroupVo.creator",
                "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "UserGameVo.user" });

        // 计算用户等级
        LevelVo levelVo = getUserLevelVo(user);
        userVo.setLevel(levelVo);

        return userVo;
    }

    public LevelVo getUserLevelVo(User user) {
        Level level = getUserLevel(user);
        LevelVo levelVo = BeanUtils.makeVo(level, LevelVo.class, null);
        return levelVo;
    }

    /**
     * 获取用户的等级
     *
     * @return
     */

    public Level getUserLevel(User user) {

        int userTotalScore = user.getTotalScore();
        List<Level> levels = levelBo.getLevels();
        for (Level level : levels) {
            if (userTotalScore >= level.getMinScore() && userTotalScore <= level.getMaxScore()) {
                return level;
            }
        }
        return null;
    }

    @Transactional
    public void adjustCowDung(User user, int delta, String reason) throws IllegalAccessException {
        UserCowDungLogBo bo = userCowDungLogBo;
        int currCowDung = user.getCowDung();
        UserCowDungLog userCowDungLog = new UserCowDungLog(user, delta, currCowDung + delta,
                new Timestamp(new Date().getTime()), reason);
        bo.createEntity(userCowDungLog);
        user.setCowDung(currCowDung + delta);
        updateEntity(user);
    }

    /**
     * 判断用户今日是否已打卡
     *
     * @return
     */
    public boolean getHasDakaToday(String userId) {
        DakaId id = new DakaId(userId, Utils.getPureDate(new Date()));
        Daka daka = dakaBo.findById(id);
        return daka != null;
    }

    public void unRegister(String userId) throws IllegalAccessException {
        // 删除用户
        User user = findById(userId);
        if (user != null) {
            deleteUser(user);
        }
    }

    @Override
    public String toString() {
        return super.toString();
    }

    private boolean hasVersionLogs(String userId, int version) {
        Session session = getSession();
        String hql = "FROM UserDbLog e WHERE e.userId= :userId and e.version = :version";
        Query<UserDbLog> query = session.createQuery(hql, UserDbLog.class);
        query.setParameter("userId", userId);
        query.setParameter("version", version);
        List<UserDbLog> logs = query.list();
        return !logs.isEmpty();
    }

    /**
     * 获取用户数据库日志
     *
     * @param fromVersion 从此版本开始，不包括此版本
     * @return
     */
    public List<UserDbLogDto> getUserNewDbLogs(String userId, int fromVersion) {
        User user = findById(userId);

        // 如果用户不存在，则返回空列表（这种情况可能发生在客户端未登录到后端时，指定要同步的用户（用户可能是前端首先创建的））
        if (user == null) {
            return new ArrayList<>();
        }

        // 获取用户数据库版本
        int userDbVersion = userDbVersionDao.getUserDbVersion(getSession(), userId);

        if (userDbVersion > fromVersion + 10 || !hasVersionLogs(userId, fromVersion)) { // 若客户端版本过旧，或者服务端没有指定版本的日志（老日志可能被删除了），则全量同步
            // 生成学习中单词全量日志
            List<LearningWordDto> learningWords = learningWordBo.getLearningWordDtosOfUser(userId);
            List<LearningDictDto> learningDicts = learningDictBo.getLearningDictDtosOfUser(userId);
            List<UserDbLogDto> logs = new ArrayList<>();
            for (LearningWordDto learningWord : learningWords) {
                UserDbLogDto log = new UserDbLogDto(Util.uuid(), userId, userDbVersion, "INSERT", "learning_word",
                        learningWord.getUserId() + "-" + learningWord.getWordId(), JsonUtils.toJson(learningWord),
                        learningWord.getCreateTime(),
                        learningWord.getUpdateTime());
                logs.add(log);
            }
            for (LearningDictDto learningDict : learningDicts) {
                UserDbLogDto log = new UserDbLogDto(Util.uuid(), userId, userDbVersion, "INSERT", "learning_dict",
                        learningDict.getUserId() + "-" + learningDict.getDictId(), JsonUtils.toJson(learningDict),
                        learningDict.getCreateTime(),
                        learningDict.getUpdateTime());
                logs.add(log);
            }

            // 生成用户学习步骤全量日志
            List<UserStudyStepDto> userStudyStepDtos = userStudyStepBo.getUserStudyStepDtosOfUser(userId);
            for (UserStudyStepDto stepDto : userStudyStepDtos) {
                // 创建日志条目
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "user_study_step",
                        userId + "-" + stepDto.getStudyStep(),
                        JsonUtils.toJson(stepDto),
                        stepDto.getCreateTime(),
                        stepDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户打卡记录全量日志
            List<DakaDto> dakaDtos = dakaBo.getDakaDtosOfUser(userId);
            SimpleDateFormat dateFormat = new SimpleDateFormat("yyyyMMdd");
            for (DakaDto dakaDto : dakaDtos) {
                // 创建日志条目
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "daka",
                        userId + "-" + dateFormat.format(dakaDto.getForLearningDate()),
                        JsonUtils.toJson(dakaDto),
                        dakaDto.getCreateTime(),
                        dakaDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户操作记录全量日志
            List<UserOperDto> userOperDtos = userOperBo.getUserOperDtosOfUser(userId);
            for (UserOperDto operDto : userOperDtos) {
                // 创建日志条目
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "user_oper",
                        operDto.getId(),
                        JsonUtils.toJson(operDto),
                        operDto.getCreateTime(),
                        operDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户错词(user_wrong_word)全量日志
            List<WrongWordDto> wrongWordDtos = wrongWordBo.getWrongWordDtosOfUser(userId);
            for (WrongWordDto wrongWordDto : wrongWordDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "user_wrong_word",
                        userId + "-" + wrongWordDto.getWordId(),
                        JsonUtils.toJson(wrongWordDto),
                        wrongWordDto.getCreateTime(),
                        wrongWordDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户生词本(dict_word)全量日志
            List<DictWordDto> dictWordDtos = dictWordBo.getDictWordDtosOfUser(userId);
            for (DictWordDto dictWordDto : dictWordDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "dict_word",
                        dictWordDto.getDictId() + "-" + dictWordDto.getWordId(),
                        JsonUtils.toJson(dictWordDto),
                        dictWordDto.getCreateTime(),
                        dictWordDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户已掌握单词(mastered_word)全量日志
            List<MasteredWordDto> masteredWordDtos = masteredWordBo.getMasteredWordDtosOfUser(userId);
            for (MasteredWordDto masteredWordDto : masteredWordDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "mastered_word",
                        userId + "-" + masteredWordDto.getWordId(),
                        JsonUtils.toJson(masteredWordDto),
                        masteredWordDto.getCreateTime(),
                        masteredWordDto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户魔法泡泡日志(user_cow_dung_log)全量日志
            List<UserCowDungLogDto> userCowDungLogDtos = userCowDungLogBo.getUserCowDungLogDtosOfUser(userId);
            for (UserCowDungLogDto dto : userCowDungLogDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "user_cow_dung_log",
                        dto.getId(),
                        JsonUtils.toJson(dto),
                        dto.getCreateTime(),
                        dto.getUpdateTime());
                logs.add(log);
            }

            logger.info("为用户{}进行全量同步, 共生成{}条同步日志, 服务端/客户端数据版本号为{}", userId, logs.size(),
                    userDbVersion + "-" + fromVersion);

            return logs;
        } else { // 增量同步
            Session session = getSession();
            String sql = "select e.id, e.userId, e.version, e.operate, e.tblName, e.recordId, e.record, e.createTime, e.updateTime FROM user_db_log e "
                    +
                    "WHERE e.userId= :userId and e.version > :fromVersion and e.createTime = " +
                    "(SELECT MAX(e2.createTime) FROM user_db_log e2 WHERE e2.tblName = e.tblName and e2.recordId = e.recordId) order by e.version asc, e.createTime asc";
            Query<?> query = session.createNativeQuery(sql);
            query.setParameter("userId", userId);
            query.setParameter("fromVersion", fromVersion);
            List<?> results = query.list();
            List<UserDbLogDto> logs = new ArrayList<>();
            for (Object obj : results) {
                Object[] values = (Object[]) obj;
                UserDbLogDto log = new UserDbLogDto();
                log.setId((String) values[0]);
                log.setUserId((String) values[1]);
                log.setVersion((Integer) values[2]);
                log.setOperate((String) values[3]);
                log.setTblName((String) values[4]);
                log.setRecordId((String) values[5]);
                log.setRecord((String) values[6]);
                log.setCreateTime((Date) values[7]);
                log.setUpdateTime((Date) values[8]);
                logs.add(log);
            }

            logger.info("为用户{}进行增量同步, 共生成{}条同步日志, 服务端/客户端数据版本号为{}", userId, logs.size(),
                    userDbVersion + "-" + fromVersion);
            return logs;
        }

    }

    /**
     * 根据微信信息查找或创建用户
     * 
     * @param wechatUserInfo 微信用户信息
     * @return 用户对象
     */
    @Transactional
    public User findOrCreateUserByWechat(WechatBo.WechatUserInfo wechatUserInfo) {
        try {
            // 1. 根据openId查找用户
            Session session = this.getSession();
            Query<User> query = session.createQuery(
                "FROM User WHERE wechatOpenId = :openId", User.class);
            query.setParameter("openId", wechatUserInfo.openId);
            List<User> users = query.getResultList();

            if (!users.isEmpty()) {
                // 用户已存在，更新微信信息（昵称和头像可能变化）
                User existingUser = users.get(0);
                existingUser.setWechatNickname(wechatUserInfo.nickname);
                existingUser.setWechatAvatar(wechatUserInfo.headImgUrl);
                if (wechatUserInfo.unionId != null) {
                    existingUser.setWechatUnionId(wechatUserInfo.unionId);
                }
                existingUser.setLastLoginTime(new Date());
                updateEntity(existingUser);
                return existingUser;
            }

            // 2. 用户不存在，创建新用户
            User newUser = new User();
            
            // 设置微信相关信息
            newUser.setWechatOpenId(wechatUserInfo.openId);
            newUser.setWechatUnionId(wechatUserInfo.unionId);
            newUser.setWechatNickname(wechatUserInfo.nickname);
            newUser.setWechatAvatar(wechatUserInfo.headImgUrl);
            
            // 设置基本信息（使用微信昵称作为用户名和昵称）
            // 生成唯一的用户名（微信昵称可能重复）
            String userName = "wx_" + wechatUserInfo.openId.substring(0, Math.min(20, wechatUserInfo.openId.length()));
            newUser.setUserName(userName);
            newUser.setNickName(wechatUserInfo.nickname);
            
            // 微信登录不需要密码，但字段不能为空，设置一个随机密码
            newUser.setPassword(MD5Utils.md5(wechatUserInfo.openId + System.currentTimeMillis()));
            
            // 设置默认值
            newUser.setLastLoginTime(new Date());
            newUser.setLearnedDays(0);
            newUser.setLearningFinished(false);
            newUser.setInviteAwardTaken(false);
            newUser.setIsSuper(false);
            newUser.setIsAdmin(false);
            newUser.setIsInputor(false);
            newUser.setIsSysUser(false);
            newUser.setAutoPlaySentence(true);
            newUser.setAutoPlayWord(true);
            newUser.setWordsPerDay(20);
            newUser.setDakaDayCount(0);
            newUser.setMasteredWordsCount(0);
            newUser.setCowDung(0);
            newUser.setThrowDiceChance(0);
            newUser.setGameScore(0);
            newUser.setShowAnswersDirectly(false);
            newUser.setContinuousDakaDayCount(0);
            newUser.setMaxContinuousDakaDayCount(0);
            newUser.setEnableAllWrong(false);
            
            // 设置默认等级（一般是第一个等级）
            Query<Level> levelQuery = session.createQuery("FROM Level ORDER BY id ASC", Level.class);
            levelQuery.setMaxResults(1);
            List<Level> levels = levelQuery.getResultList();
            if (!levels.isEmpty()) {
                newUser.setLevel(levels.get(0));
            }

            // 保存用户
            createEntity(newUser);
            
            logger.info("创建微信用户成功: openId={}, nickname={}", wechatUserInfo.openId, wechatUserInfo.nickname);
            
            return newUser;

        } catch (Exception e) {
            logger.error("查找或创建微信用户异常", e);
            return null;
        }
    }

    /**
     * 执行微信登录
     * 
     * @param user 用户对象
     * @param clientType 客户端类型
     * @param clientVersion 客户端版本
     * @param request HTTP请求
     * @param response HTTP响应
     * @return 登录结果
     */
    @Transactional
    public Result<User> doLoginByWechat(User user, ClientType clientType, String clientVersion,
            HttpServletRequest request, HttpServletResponse response) {
        try {
            // 保存登录日志
            LoginLog loginLog = new LoginLog(user, new Date());
            loginLogBo.createEntity(loginLog);

            // 如果用户还没有学习步骤数据，创建之
            userStudyStepBo.initUserStudySteps(clientType, user.getId());

            return new Result<>(true, "登录成功", user);

        } catch (Exception e) {
            logger.error("微信登录异常", e);
            return new Result<>(false, "登录失败，请稍后重试", null);
        }
    }

}
