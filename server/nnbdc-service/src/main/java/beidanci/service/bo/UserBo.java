package beidanci.service.bo;

import java.io.IOException;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.annotation.PostConstruct;
import javax.naming.NamingException;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.commons.lang3.tuple.Pair;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
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
import beidanci.api.model.PagedResults;
import beidanci.api.model.UserCowDungLogDto;
import beidanci.api.model.UserDbLogDto;
import beidanci.api.model.UserOperDto;
import beidanci.api.model.UserStudyStepDto;
import beidanci.api.model.UserVo;
import beidanci.api.model.WordVo;
import beidanci.api.model.WrongWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
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
import beidanci.service.po.StudyGroup;
import beidanci.service.po.User;
import beidanci.service.po.UserCowDungLog;
import beidanci.service.po.UserDbLog;
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
    UserCowDungLogBo userCowDungLogBo;

    @Autowired
    StudyGroupBo studyGroupBo;

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    UserStudyStepBo userStudyStepBo;

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
    DakaBo dakaBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    SysParamBo sysParamBo;

    @Autowired
    UserOperBo userOperBo;

    @Autowired
    private UserDbVersionDao userDbVersionDao;

    @Autowired
    private WrongWordBo wrongWordBo;

    @Autowired
    private MasteredWordBo masteredWordBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<User>() {
        });
    }

    public int getUserDbVersion(String userId) {
        return userDbVersionDao.getUserDbVersion(jdbcTemplate, userId);
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
                sysUser_deleted = Util.createNewUser(Constants.SYS_USER_DELETED, "YouCantGuessIt~", "已删除用户(虚拟)", null,
                        null, sysParamBo,
                        dictBo, this, learningDictBo, true);
            }
        }
        return sysUser_deleted;
    }

    public List<User> findUsersTotalScoreMoreThan(int score, boolean includeGuest) {
        String sql;
        if (includeGuest) {
            sql = "SELECT * FROM \"user\" WHERE (game_score > 0 OR daka_score > 0)";
        } else {
            sql = "SELECT * FROM \"user\" WHERE user_name NOT LIKE 'guest%' AND user_name NOT LIKE 'guess%' AND user_name NOT LIKE '游客%' AND (game_score > 0 OR daka_score > 0)";
        }
        return jdbcTemplate.query(sql, new EntityRowMapper<>(User.class));
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
        String sql = "SELECT * FROM \"user\" WHERE is_sys_user = 0 AND last_login_time < :time";
        MapSqlParameterSource params = new MapSqlParameterSource("time",
                Utils.localDate2Date(LocalDate.now().plusDays(-idleDays)));
        List<User> users = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(User.class));
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
                // 删除用户选择的单词书（使用批量删除避免OptimisticLockException）
                String sql = "DELETE FROM learning_dict WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户的自定义单词书
                List<Dict> customedDicts = dictBo.getOwnDicts(user, Integer.MAX_VALUE);
                for (Dict dict : customedDicts) {
                    dictBo.deleteDictSafely(dict.getId());
                }

                // 删除用户的学习步骤
                userStudyStepBo.clearUserStudySteps(user.getId());

                // 删除用户正在学习的单词（使用批量删除避免外键约束问题）
                sql = "DELETE FROM learning_word WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户已掌握的单词
                sql = "DELETE FROM mastered_word WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户发送的消息（使用批量删除避免外键约束问题）
                sql = "DELETE FROM msg WHERE from_user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户接收的消息
                sql = "DELETE FROM msg WHERE to_user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户相关事件
                eventBo.clearUserEvents(user);

                // 删除用户的打卡记录（使用批量删除避免外键约束问题）
                sql = "DELETE FROM daka WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户的魔法泡泡收支记录（使用批量删除避免外键约束问题）
                sql = "DELETE FROM user_cow_dung_log WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户的游戏记录（使用批量删除避免外键约束问题）
                sql = "DELETE FROM user_game WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户每日快照记录（使用批量删除避免外键约束问题）
                sql = "DELETE FROM user_snapshot_daily WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户积分记录
                sql = "DELETE FROM user_score_log WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 清空错题集关联
                sql = "DELETE FROM user_wrong_word WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 解除该用户邀请的用户对其的引用（使用批量更新避免外键约束问题）
                User sysUser = getSysUser_deleted(false);
                // PostgreSQL 中 user 是保留字，这里需要加双引号
                sql = "UPDATE \"user\" SET invited_by_id = ? WHERE invited_by_id = ?";
                jdbcTemplate.update(sql, sysUser.getId(), user.getId());

                // 退出所在的小组
                if (user.getCreatedStudyGroups() != null) {
                    for (StudyGroup group : user.getCreatedStudyGroups()) {
                        studyGroupBo.exitGroup(user, group.getId());
                    }
                }
                if (user.getStudyGroups() != null) {
                    for (StudyGroup group : user.getStudyGroups()) {
                        studyGroupBo.exitGroup(user, group.getId());
                    }
                }
                if (user.getManagedStudyGroups() != null) {
                    for (StudyGroup group : user.getManagedStudyGroups()) {
                        studyGroupBo.exitGroup(user, group.getId());
                    }
                }

                // 删除登录日志
                loginLogBo.cleanLoginLogs(user);

                // 删除用户数据库日志
                sql = "DELETE FROM user_db_log WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 将用户UGC转让给系统虚拟用户
                sql = "UPDATE word_additional_info SET user_id = ? WHERE user_id = ?";
                jdbcTemplate.update(sql, sysUser.getId(), user.getId());
                sql = "UPDATE sentence SET author_id = ? WHERE author_id = ?";
                jdbcTemplate.update(sql, sysUser.getId(), user.getId());
                sql = "DELETE FROM info_vote_log WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());
                sql = "UPDATE word_image SET author_id = ? WHERE author_id = ?";
                jdbcTemplate.update(sql, sysUser.getId(), user.getId());
                sql = "UPDATE word_shortdesc_chinese SET author_id = ? WHERE author_id = ?";
                jdbcTemplate.update(sql, sysUser.getId(), user.getId());

                // 不再作为论坛管理员
                sql = "DELETE FROM forum_and_manager_link WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户回复的帖子
                // 历史库已执行列名 snake_case 修复：postReplyerId -> post_replyer_id
                sql = "DELETE FROM forum_post_reply WHERE post_replyer_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户的帖子
                // 历史库已执行列名 snake_case 修复：postCreatorId -> post_creator_id
                sql = "DELETE FROM forum_post WHERE post_creator_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户报错
                sql = "DELETE FROM error_report WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户数据库版本记录
                sql = "DELETE FROM user_db_version WHERE user_id = ?";
                jdbcTemplate.update(sql, user.getId());

                // 删除用户记录
                deleteEntity(user);
                return null;
            } catch (IllegalAccessException | RuntimeException e) {
                logger.error("删除用户异常，事务将回滚: userId={}", user.getId(), e);
                status.setRollbackOnly();
                throw new RuntimeException("删除用户异常，事务将回滚", e);
            }
        }));
    }

    public List<User> findByEmail(String email) {
        String sql = "SELECT * FROM \"user\" WHERE email = :email";
        MapSqlParameterSource params = new MapSqlParameterSource("email", email);
        return namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(User.class));
    }

    public User getByUserName(String userName, boolean openNewSession) {
        // JDBC 不需要管理 Session，直接查询
        String sql = "SELECT * FROM \"user\" WHERE user_name = :userName";
        MapSqlParameterSource params = new MapSqlParameterSource("userName", userName);
        List<User> results = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(User.class));
        return results.isEmpty() ? null : results.get(0);
    }

    public List<User> findAll() {
        String sql = "SELECT * FROM \"user\"";
        return jdbcTemplate.query(sql, new EntityRowMapper<>(User.class));
    }

    /**
     * 随机挑选一个非游客用户的昵称（优先 displayNickName，其次 nickName，再次 userName）。
     * 采用新会话查询，避免在无事务的socket线程中获取currentSession失败。
     */
    public String pickRandomNonGuestNickName() {
        // JDBC 不需要管理 Session
        String sql = "SELECT * FROM \"user\" WHERE user_name NOT LIKE 'guest%' LIMIT 50";
        List<User> candidates = jdbcTemplate.query(sql,
                new EntityRowMapper<>(User.class));
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        Collections.shuffle(candidates);
        User picked = candidates.get(0);
        return Util.getNickNameOfUser(picked);
    }

    /**
     * 随机挑选一个“超过指定天数未登录”且“玩过游戏”的真实用户，用作机器人陪玩。
     * 采用新会话查询，避免在无事务的socket线程中获取currentSession失败。
     */
    public User pickRandomInactiveGamer(int idleDays, int maxCandidates) {
        // JDBC 不需要管理 Session
        String sql = "SELECT DISTINCT u.* FROM user_game ug " +
                "INNER JOIN \"user\" u ON ug.user_id = u.id " +
                "WHERE u.is_sys_user = 0 AND u.last_login_time < ? " +
                "LIMIT ?";
        Date time = Utils.localDate2Date(LocalDate.now().plusDays(-idleDays));
        List<User> candidates = jdbcTemplate.query(sql,
                new EntityRowMapper<>(User.class),
                time, maxCandidates);
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        Collections.shuffle(candidates);
        return candidates.get(0);
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
            logger.error("不支持的验证方式: checkBy=null");
            throw new IllegalArgumentException("不支持的验证方式:" + checkBy);
        } else
            switch (checkBy) {
                case UserName -> {
                    // 检查用户名是否存在
                    user = getByUserName(userName, false);
                    if (user == null) {
                        // 如果用户不存在，创建一个新用户
                        user = Util.createNewUser(userName + "@example.com", password, userName,
                                userName + "@example.com",
                                null, sysParamBo,
                                dictBo, this, learningDictBo, false);
                        user.setWordsPerDay(20);
                        try {
                            createEntity(user);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败: userName={}", userName, e);
                            // 创建用户失败，抛出异常让调用者知道
                            throw new RuntimeException("自动创建用户失败: " + e.getMessage(), e);
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
                        user = Util.createNewUser(email, password, nickname, email, null, sysParamBo,
                                dictBo, this, learningDictBo, false);
                        user.setWordsPerDay(20);
                        try {
                            createEntity(user);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败: email={}", email, e);
                            // 创建用户失败，抛出异常让调用者知道
                            throw new RuntimeException("自动创建用户失败: " + e.getMessage(), e);
                        }
                    }
                }
                default -> {
                    logger.error("不支持的验证方式: checkBy={}", checkBy);
                    throw new IllegalArgumentException("不支持的验证方式:" + checkBy);
                }
            }

        return new Result<>(true, null, user);
    }

    /**
     * 通过邮箱验证码登录（验证码已在Controller中验证，不需要密码）
     * 如果用户存在，直接登录；如果不存在，自动创建账户
     * 
     * @param request       HTTP请求
     * @param email         邮箱地址
     * @param clientType    客户端类型
     * @param clientVersion 客户端版本
     * @return 用户验证结果
     */
    public Result<User> checkUserByEmailCode(HttpServletRequest request, String email,
            ClientType clientType, String clientVersion) {
        logger.info(String.format("用户正在通过邮箱验证码登录... IP[%s] email[%s] clientType[%s] UA[%s] ver[%s]",
                Util.getClientIP(request), email, clientType,
                request.getHeader("User-Agent"), clientVersion));

        List<User> users = findByEmail(email);
        User user;

        if (!users.isEmpty()) {
            // 用户存在，直接登录（验证码已验证通过）
            user = users.get(0);
        } else {
            // 如果Email对应的账户不存在，自动创建账户
            // 密码设为空字符串（CS架构下不再使用密码，登录后自动登录）
            String nickname = email != null && email.contains("@") ? email.split("@")[0] : "user";
            try {
                user = Util.createNewUser(email, "", nickname, email, null, sysParamBo,
                        dictBo, this, learningDictBo, false);
                user.setWordsPerDay(20);
                // 注意：genNewUser 内部已经调用了 createEntity，所以这里只需要更新 wordsPerDay
                updateEntity(user);
            } catch (IllegalAccessException | IllegalArgumentException e) {
                logger.error("自动创建用户失败", e);
                return new Result<>(false, "创建用户失败", null);
            }
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
            userStudyStepBo.initUserStudySteps(user.getId());
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

    // =========================
    // 会员判定 & 非会员限额
    // =========================

    /**
     * 非会员每日最大学习单词数
     */
    public static final int NON_PREMIUM_MAX_WORDS_PER_DAY = 20;

    /**
     * 判定用户是否“有效会员”。
     * - iOS订阅有效 => 会员
     * - 强制会员有效(未过期/永久) => 会员
     *
     * 重要：遇到不确定/异常字段时，优先判定为会员（避免用户纠纷）。
     */
    public boolean isPremiumEffective(User user, Date now) {
        if (user == null) {
            return true; // 偏向会员
        }
        if (now == null) {
            now = new Date();
        }

        // 1) iOS订阅
        try {
            if (Boolean.TRUE.equals(user.getIsPremiumIos())) {
                Date expire = user.getSubscriptionExpireDateIos();
                if (expire == null) {
                    return true; // 没有过期时间也视为会员
                }
                if (expire.after(now)) {
                    return true;
                }
            }
        } catch (Exception ignored) {
            return true; // 偏向会员
        }

        // 2) 强制会员
        try {
            if (!Boolean.TRUE.equals(user.getPremiumOverrideEnabled())) {
                return false;
            }

            String duration = user.getPremiumOverrideDuration();
            if (duration == null) {
                return true; // 永久
            }

            Date updateTime = user.getPremiumOverrideUpdateTime();
            if (updateTime == null) {
                return true; // 元数据缺失，偏向会员
            }

            Long durationMs = parseDurationMillis(duration);
            if (durationMs == null) {
                return true; // 无法解析，偏向会员
            }
            if (durationMs <= 0) {
                return false;
            }

            Date expireTime = new Date(updateTime.getTime() + durationMs);
            return expireTime.after(now);
        } catch (Exception ignored) {
            return true; // 偏向会员
        }
    }

    /**
     * 获取“本次学习逻辑应该使用的 wordsPerDay”。
     * 非会员将被限制到 20（但不会修改用户表中的真实设置值，便于未来变成会员后恢复）。
     */
    public int getEffectiveWordsPerDay(User user, Date now) {
        int raw = 20;
        try {
            if (user != null && user.getWordsPerDay() != null) {
                raw = user.getWordsPerDay();
            }
        } catch (Exception ignored) {
            raw = 20;
        }
        if (raw <= 0) {
            raw = 20;
        }
        if (isPremiumEffective(user, now)) {
            return raw;
        }
        return Math.min(raw, NON_PREMIUM_MAX_WORDS_PER_DAY);
    }

    /**
     * 解析时长字符串（形如：10天 / 360秒 / 15分钟 / 2小时）。
     * 返回毫秒；解析失败返回 null。
     */
    private static Long parseDurationMillis(String duration) {
        if (duration == null) {
            return null;
        }
        String s = duration.trim();
        if (s.isEmpty()) {
            return null;
        }

        // 允许简单格式：数字 + 单位
        Pattern p = Pattern.compile("^([0-9]+)\\s*(毫秒|ms|秒|s|分钟|分|m|小时|时|h|天|日|d)$", Pattern.CASE_INSENSITIVE);
        Matcher m = p.matcher(s);
        if (!m.matches()) {
            return null;
        }

        long value = Long.parseLong(m.group(1));
        String unit = m.group(2).toLowerCase();

        return switch (unit) {
            case "毫秒", "ms" -> value;
            case "秒", "s" -> value * 1000L;
            case "分钟", "分", "m" -> value * 60_000L;
            case "小时", "时", "h" -> value * 3_600_000L;
            case "天", "日", "d" -> value * 86_400_000L;
            default -> null;
        };
    }

    // =========================
    // 服务端主动修改 user 后，推送到 user_db_log 供客户端同步
    // =========================

    /**
     * 服务端主动更新用户信息后，将变更写入 user_db_log 并递增 user_db_version，
     * 这样客户端下一次同步即可拿到最新用户信息（含订阅/强制会员字段）。
     *
     * 注意：该方法需要在事务中调用。
     */
    @Transactional
    public void logUserUpdateForSync(User user) {
        if (user == null || user.getId() == null) {
            return;
        }

        // 确保版本记录存在
        userDbVersionDao.ensureUserDbVersionExists(jdbcTemplate, user.getId());

        // 加锁读版本号（在同一事务内）
        int currentVersion = userDbVersionDao.getUserDbVersionWithLock(jdbcTemplate, user.getId());
        int nextVersion = currentVersion + 1;

        // 写 user_db_log（record 使用 UserDto 的 JSON，前端可直接 User.fromJson 解析）
        UserDbLog log = new UserDbLog();
        log.setUserId(user.getId());
        log.setVersion(nextVersion);
        log.setCreateTime(new Date());
        log.setUpdateTime(new Date());
        log.setTable("user");
        log.setOperate("UPDATE");
        log.setRecordId(user.getId());
        log.setRecord(JsonUtils.toJson(user.toDto()));
        userDbLogBo.createEntity(log);

        boolean ok = userDbVersionDao.updateUserDbVersionCAS(jdbcTemplate, user.getId(), currentVersion, nextVersion);
        if (!ok) {
            throw new RuntimeException("更新 user_db_version 失败（可能存在并发修改），userId=" + user.getId());
        }
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
        // 如果传入的 User 对象是部分加载的（只有 id，其他字段为 null），需要重新加载完整对象
        if (user.getCowDung() == null && user.getId() != null) {
            String userId = user.getId();
            user = findById(userId);
            if (user == null) {
                throw new IllegalAccessException("用户不存在: " + userId);
            }
        }

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
        String sql = "SELECT COUNT(*) FROM user_db_log WHERE user_id = :userId AND version = :version";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("version", version);
        Integer count = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return count != null && count > 0;
    }

    /**
     * 获取用户数据库日志
     *
     * @param fromVersion 从此版本开始，不包括此版本
     * @return
     */
    public List<UserDbLogDto> getUserDbLogsFromVersion(String userId, int fromVersion) {
        User user = findById(userId);

        // 如果用户不存在，则返回空列表（这种情况可能发生在客户端未登录到后端时，指定要同步的用户（用户可能是前端首先创建的））
        if (user == null) {
            return new ArrayList<>();
        }

        // 获取用户数据库版本
        int userDbVersion = userDbVersionDao.getUserDbVersion(jdbcTemplate, userId);

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

            // 打印全量同步日志分类统计（便于定位日志量过大的原因）
            // 注意：tblName 需要与客户端同步消费的表名保持一致
            Map<String, Integer> counts = new HashMap<>();
            for (UserDbLogDto l : logs) {
                String tbl = l.getTblName();
                if (tbl == null) {
                    tbl = "null";
                }
                counts.put(tbl, counts.getOrDefault(tbl, 0) + 1);
            }

            // 按固定顺序输出，方便排查
            Map<String, Integer> ordered = new LinkedHashMap<>();
            ordered.put("learning_word", counts.getOrDefault("learning_word", 0));
            ordered.put("learning_dict", counts.getOrDefault("learning_dict", 0));
            ordered.put("user_study_step", counts.getOrDefault("user_study_step", 0));
            ordered.put("daka", counts.getOrDefault("daka", 0));
            ordered.put("user_oper", counts.getOrDefault("user_oper", 0));
            ordered.put("user_wrong_word", counts.getOrDefault("user_wrong_word", 0));
            ordered.put("dict_word", counts.getOrDefault("dict_word", 0));
            ordered.put("mastered_word", counts.getOrDefault("mastered_word", 0));
            ordered.put("user_cow_dung_log", counts.getOrDefault("user_cow_dung_log", 0));

            // 输出未在固定列表中的表名（如果有）
            Map<String, Integer> extra = new LinkedHashMap<>();
            for (Map.Entry<String, Integer> e : counts.entrySet()) {
                if (!ordered.containsKey(e.getKey())) {
                    extra.put(e.getKey(), e.getValue());
                }
            }
            if (!extra.isEmpty()) {
                logger.info("为用户{}进行全量同步分类统计(其他明细): {}", userId, extra);
            }
            logger.info("为用户{}进行全量同步分类统计: {}", userId, ordered);

            logger.info("为用户{}进行全量同步, 共生成{}条同步日志, 服务端/客户端数据版本号为{}", userId, logs.size(),
                    userDbVersion + "-" + fromVersion);

            return logs;
        } else { // 增量同步
            String sql = "SELECT e.id, e.user_id, e.version, e.operate, e.tbl_name, e.record_id, e.record, e.create_time, e.update_time FROM user_db_log e "
                    +
                    "WHERE e.user_id = :userId AND e.version > :fromVersion AND e.create_time = " +
                    "(SELECT MAX(e2.create_time) FROM user_db_log e2 WHERE e2.tbl_name = e.tbl_name AND e2.record_id = e.record_id) ORDER BY e.version ASC, e.create_time ASC";
            MapSqlParameterSource params = new MapSqlParameterSource();
            params.addValue("userId", userId);
            params.addValue("fromVersion", fromVersion);
            List<UserDbLogDto> logs = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
                UserDbLogDto log = new UserDbLogDto();
                log.setId(rs.getString("id"));
                log.setUserId(rs.getString("user_id"));
                log.setVersion(rs.getInt("version"));
                log.setOperate(rs.getString("operate"));
                log.setTblName(rs.getString("tbl_name"));
                log.setRecordId(rs.getString("record_id"));
                log.setRecord(rs.getString("record"));
                log.setCreateTime(rs.getTimestamp("create_time"));
                log.setUpdateTime(rs.getTimestamp("update_time"));
                return log;
            });

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
            String sql = "SELECT * FROM \"user\" WHERE wechat_open_id = :openId";
            MapSqlParameterSource params = new MapSqlParameterSource("openId", wechatUserInfo.openId);
            List<User> users = namedParameterJdbcTemplate.query(sql, params,
                    new EntityRowMapper<>(User.class));

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
            newUser.setIsSuperAdmin(false);
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
            String levelSql = "SELECT * FROM level ORDER BY id ASC LIMIT 1";
            List<Level> levels = jdbcTemplate.query(levelSql,
                    new EntityRowMapper<>(Level.class));
            if (!levels.isEmpty()) {
                newUser.setLevel(levels.get(0));
            }

            // 保存用户
            createEntity(newUser);

            logger.info("创建微信用户成功: openId={}, nickname={}", wechatUserInfo.openId, wechatUserInfo.nickname);

            return newUser;

        } catch (IllegalAccessException | IllegalArgumentException | DataAccessException e) {
            logger.error("查找或创建微信用户异常: openId={}, nickname={}",
                    wechatUserInfo.openId, wechatUserInfo.nickname, e);
            // 重新抛出异常，让调用者知道操作失败
            throw new RuntimeException("查找或创建微信用户失败: " + e.getMessage(), e);
        }
    }

    /**
     * 执行微信登录
     * 
     * @param user          用户对象
     * @param clientType    客户端类型
     * @param clientVersion 客户端版本
     * @param request       HTTP请求
     * @param response      HTTP响应
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
            userStudyStepBo.initUserStudySteps(user.getId());

            return new Result<>(true, "登录成功", user);

        } catch (Exception e) {
            logger.error("微信登录异常", e);
            return new Result<>(false, "登录失败，请稍后重试", null);
        }
    }

    /**
     * 分页搜索用户（管理员功能）
     * 支持按用户名、昵称、邮箱模糊搜索
     *
     * @param keyword    搜索关键词
     * @param pageNo     页码，从1开始
     * @param pageSize   每页大小
     * @param filterType 筛选类型：0-全部, 1-管理员, 2-超级管理员, 3-录入员
     * @return 分页结果
     */
    public PagedResults<User> searchUsers(String keyword, int pageNo, int pageSize, Integer filterType) {
        String sql;

        // 构建WHERE条件
        StringBuilder whereClause = new StringBuilder();
        boolean hasCondition = false;

        if (keyword != null && !keyword.trim().isEmpty()) {
            // 有搜索关键词，模糊匹配用户名、昵称、邮箱
            whereClause.append("(user_name LIKE :keyword OR nick_name LIKE :keyword OR email LIKE :keyword)");
            hasCondition = true;
        }

        // 添加权限筛选条件
        if (filterType != null && filterType > 0) {
            if (hasCondition) {
                whereClause.append(" AND ");
            }
            switch (filterType) {
                case 1 -> // 管理员
                    whereClause.append("is_admin = true");
                case 2 -> // 超级管理员
                    whereClause.append("is_super_admin = true");
                case 3 -> // 录入员
                    whereClause.append("is_inputor = true");
            }
            hasCondition = true;
        }

        // 构建完整SQL
        if (hasCondition) {
            sql = "SELECT * FROM \"user\" WHERE " + whereClause.toString() + " ORDER BY last_login_time DESC";
        } else {
            sql = "SELECT * FROM \"user\" ORDER BY last_login_time DESC";
        }

        // 设置参数（baseDao.pagedQuery 支持可变参数，避免手动创建泛型数组导致的 unchecked conversion）
        if (keyword != null && !keyword.trim().isEmpty()) {
            String searchPattern = "%" + keyword.trim() + "%";
            return baseDao.pagedQuery(jdbcTemplate, sql, pageNo, pageSize, Pair.of("keyword", searchPattern));
        }

        return baseDao.pagedQuery(jdbcTemplate, sql, pageNo, pageSize);
    }

    /**
     * 更新用户的管理员权限（管理员功能）
     *
     * @param userId       用户ID
     * @param isAdmin      是否为管理员
     * @param isSuperAdmin 是否为超级管理员
     * @param isInputor    是否为录入员
     * @return 更新结果
     */
    @Transactional
    public Result<Void> updateAdminPermission(String userId, Boolean isAdmin, Boolean isSuperAdmin, Boolean isInputor) {
        try {
            User user = findById(userId);
            if (user == null) {
                return Result.fail("用户不存在");
            }

            if (isAdmin != null) {
                user.setIsAdmin(isAdmin);
            }
            if (isSuperAdmin != null) {
                user.setIsSuperAdmin(isSuperAdmin);
            }
            if (isInputor != null) {
                user.setIsInputor(isInputor);
            }

            updateEntity(user);
            logger.info("更新用户管理员权限成功: userId={}, isAdmin={}, isSuperAdmin={}, isInputor={}",
                    userId, isAdmin, isSuperAdmin, isInputor);

            return Result.success(null);
        } catch (IllegalAccessException | IllegalArgumentException e) {
            logger.error("更新用户管理员权限失败", e);
            return Result.fail("更新失败: " + e.getMessage());
        }
    }

}
