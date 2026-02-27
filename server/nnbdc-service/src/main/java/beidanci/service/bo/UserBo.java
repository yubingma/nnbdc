package beidanci.service.bo;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.annotation.PostConstruct;
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
import beidanci.api.model.DictDto;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.PagedResults;
import beidanci.api.model.UserVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.po.Daka;
import beidanci.service.po.DakaId;
import beidanci.service.po.Dict;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningDictId;
import beidanci.service.po.LearningWord;
import beidanci.service.po.LoginLog;
import beidanci.service.po.StudyGroup;
import beidanci.service.po.User;
import beidanci.service.po.UserCowDungLog;
import beidanci.service.po.UserDbLog;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.EmojiFilter;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;
import beidanci.service.po.SysParam;
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
    private UserDbVersionDao userDbVersionDao;

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
                sysUser_deleted = createNewUser(Constants.SYS_USER_DELETED, "YouCantGuessIt~", "已删除用户(虚拟)",
                        null, null, true);
            }
        }
        return sysUser_deleted;
    }

    public List<User> findUsersWithMasteredWords(boolean includeGuest) {
        String sql;
        if (includeGuest) {
            sql = "SELECT * FROM \"user\" WHERE (mastered_words_count > 0)";
        } else {
            sql = "SELECT * FROM \"user\" WHERE user_name NOT LIKE 'guest%' AND user_name NOT LIKE 'guess%' AND user_name NOT LIKE '游客%' AND (mastered_words_count > 0)";
        }
        return jdbcTemplate.query(sql, new EntityRowMapper<>(User.class));
    }

    @Transactional
    public void deleteUnStartedDicts(User user, HashSet<String> exceptFor)
            throws IllegalArgumentException, IllegalAccessException {
        // 由于移除了 currentWord 字段，这里改为通过检查该词典下是否有已学习记录来判断
        for (Iterator<LearningDict> i = user.getLearningDicts().iterator(); i.hasNext();) {
            LearningDict learningDict = i.next();
            if (!exceptFor.contains(learningDict.getDict().getId())) {
                boolean hasLearningWords = learningWordBo.hasLearningWordsOfDict(user.getId(), learningDict.getDict().getId());
                if (!hasLearningWords) {
                    learningDictBo.deleteEntity(learningDict);
                    i.remove();
                }
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

    // getNewWordToLearn and getNewWordFromDicts have been removed as the study logic now uses learning_word table with batchId.

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


    public void deleteDeadUsers(int idleDays) throws IllegalAccessException {
        // 查询长期未登录的用户
        String sql = "SELECT * FROM \"user\" WHERE is_sys_user = false AND last_login_time < :time";
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

                // 已掌握单词现在作为用户词书(dict + dict_word)存储，
                // 上面 deleteDictSafely 已经处理了删除

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
                "WHERE u.is_sys_user = false AND u.last_login_time < ? " +
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
                        try {
                            user = createNewUser(userName + "@example.com", password, userName,
                                    userName + "@example.com", null, false);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败: userName={}", userName, e);
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
                        try {
                            user = createNewUser(email, password, nickname, email, null, false);
                        } catch (Exception e) {
                            logger.error("自动创建用户失败: email={}", email, e);
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
                user = createNewUser(email, "", nickname, email, null, false);
            } catch (Exception e) {
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

    /**
     * 为新创建的用户生成初始数据的同步日志（UserDbLog）。
     *
     * 当服务端直接创建用户数据（生词本、已掌握词书、学习步骤等）时，
     * 这些操作不经过客户端同步流程，因此不会自动生成 UserDbLog。
     * 客户端的增量同步依赖 UserDbLog 来获取变更，
     * 如果没有对应的日志，客户端将永远无法拉取到这些数据。
     *
     * 本方法在用户创建完成后被调用，为所有初始数据生成 INSERT 日志,
     * 确保客户端首次同步时能完整拉取到生词本、已掌握词书等必要数据。
     */
    @Transactional
    public void logInitialUserDataForSync(User user, Dict rawWordDict, Dict masteredDict) {
        String userId = user.getId();
        Date now = new Date();

        // 确保版本记录存在
        userDbVersionDao.ensureUserDbVersionExists(jdbcTemplate, userId);
        int currentVersion = userDbVersionDao.getUserDbVersionWithLock(jdbcTemplate, userId);
        int nextVersion = currentVersion + 1;

        // --- 1. 用户本身的 INSERT 日志 ---
        UserDbLog userLog = new UserDbLog();
        userLog.setUserId(userId);
        userLog.setVersion(nextVersion);
        userLog.setCreateTime(now);
        userLog.setUpdateTime(now);
        userLog.setTable("user");
        userLog.setOperate("INSERT");
        userLog.setRecordId(userId);
        userLog.setRecord(JsonUtils.toJson(user.toDto()));
        userDbLogBo.createEntity(userLog);

        // --- 2. 生词本的 INSERT 日志 ---
        DictDto rawDictDto = makeDictDto(rawWordDict);
        UserDbLog rawDictLog = new UserDbLog();
        rawDictLog.setUserId(userId);
        rawDictLog.setVersion(nextVersion);
        rawDictLog.setCreateTime(now);
        rawDictLog.setUpdateTime(now);
        rawDictLog.setTable("dict");
        rawDictLog.setOperate("INSERT");
        rawDictLog.setRecordId(rawWordDict.getId());
        rawDictLog.setRecord(JsonUtils.toJson(rawDictDto));
        userDbLogBo.createEntity(rawDictLog);

        // --- 3. 已掌握词书的 INSERT 日志 ---
        DictDto masteredDictDto = makeDictDto(masteredDict);
        UserDbLog masteredDictLog = new UserDbLog();
        masteredDictLog.setUserId(userId);
        masteredDictLog.setVersion(nextVersion);
        masteredDictLog.setCreateTime(now);
        masteredDictLog.setUpdateTime(now);
        masteredDictLog.setTable("dict");
        masteredDictLog.setOperate("INSERT");
        masteredDictLog.setRecordId(masteredDict.getId());
        masteredDictLog.setRecord(JsonUtils.toJson(masteredDictDto));
        userDbLogBo.createEntity(masteredDictLog);

        // --- 4. 生词本的 LearningDict (学习词典关联) INSERT 日志 ---
        logLearningDictInsert(userId, rawWordDict.getId(), true, now, nextVersion);

        // --- 5. 已掌握词书不一定有 LearningDict 关联，根据实际逻辑决定 ---
        // createMasteredWordDictForUser 没有创建 LearningDict，所以不需要

        // --- 6. 学习步骤的 INSERT 日志 ---
        List<beidanci.service.po.UserStudyStep> steps = userStudyStepBo.getUserStudySteps(userId);
        for (beidanci.service.po.UserStudyStep step : steps) {
            beidanci.api.model.UserStudyStepDto stepDto = new beidanci.api.model.UserStudyStepDto(
                    step.getId().getUserId(),
                    step.getStudyStep(),
                    step.getSeq(),
                    step.getState(),
                    step.getCreateTime(),
                    step.getUpdateTime()
            );
            UserDbLog stepLog = new UserDbLog();
            stepLog.setUserId(userId);
            stepLog.setVersion(nextVersion);
            stepLog.setCreateTime(now);
            stepLog.setUpdateTime(now);
            stepLog.setTable("user_study_step");
            stepLog.setOperate("INSERT");
            stepLog.setRecordId(userId + "_" + step.getStudyStep().name());
            stepLog.setRecord(JsonUtils.toJson(stepDto));
            userDbLogBo.createEntity(stepLog);
        }

        // 更新数据库版本号
        boolean ok = userDbVersionDao.updateUserDbVersionCAS(jdbcTemplate, userId, currentVersion, nextVersion);
        if (!ok) {
            throw new RuntimeException("更新 user_db_version 失败（可能存在并发修改），userId=" + userId);
        }

        logger.info("为新用户[{}]生成了初始同步日志, version: {} -> {}", user.getDisplayNickName(), currentVersion, nextVersion);
    }

    /**
     * 将 Dict 实体转换为 DictDto 用于序列化到同步日志
     */
    private DictDto makeDictDto(Dict dict) {
        return new DictDto(
                dict.getId(),
                dict.getName(),
                dict.getOwner().getId(),
                dict.getIsShared(),
                dict.getIsReady(),
                dict.getVisible(),
                dict.getWordCount(),
                dict.getPopularityLimit(),
                dict.getEditable(),
                dict.getDeletable(),
                dict.getCreateTime(),
                dict.getUpdateTime()
        );
    }

    /**
     * 生成 LearningDict 的 INSERT 同步日志
     */
    private void logLearningDictInsert(String userId, String dictId, boolean fetchMastered, Date now, int version) {
        beidanci.api.model.LearningDictDto ldDto = new beidanci.api.model.LearningDictDto();
        ldDto.setDictId(dictId);
        ldDto.setUserId(userId);
        ldDto.setIsPrivileged(false);
        ldDto.setFetchMastered(fetchMastered);
        ldDto.setCreateTime(now);
        ldDto.setUpdateTime(now);

        UserDbLog ldLog = new UserDbLog();
        ldLog.setUserId(userId);
        ldLog.setVersion(version);
        ldLog.setCreateTime(now);
        ldLog.setUpdateTime(now);
        ldLog.setTable("learning_dict");
        ldLog.setOperate("INSERT");
        ldLog.setRecordId(userId + "_" + dictId);
        ldLog.setRecord(JsonUtils.toJson(ldDto));
        userDbLogBo.createEntity(ldLog);
    }

    @Transactional(readOnly = true)
    public UserVo getUserVoById(String userId) {
        User user = findById(userId);
        if (user == null) {
            return null;
        }

        UserVo userVo = BeanUtils.makeVo(user, UserVo.class, new String[] { "invitedBy", "StudyGroupVo.creator",
                "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "UserGameVo.user" });

        return userVo;
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

    /**
     * 统一的创建新用户方法 — 所有注册方式（邮箱、微信等）都应调用此方法。
     * 负责设置所有默认字段、持久化到数据库、创建生词本和已掌握词书。
     *
     * @param userName  用户名（会被转为小写）
     * @param password  密码（微信方式可传随机值）
     * @param nickName  昵称
     * @param email     邮箱（微信方式可传 null）
     * @param invitedBy 邀请人（可为 null）
     * @param isSysUser 是否为系统用户
     * @return 已持久化的 User 对象
     */
    public User createNewUser(String userName, String password, String nickName,
                              String email, User invitedBy, boolean isSysUser) {
        User user = new User();
        user.setUserName(userName.toLowerCase());
        user.setPassword(password);
        user.setNickName(EmojiFilter.filterEmoji(nickName));
        user.setEmail(email);

        // wordsPerDay 从系统参数读取默认值
        SysParam sysParam = sysParamBo.findById("DefaultWordsPerDay", false);
        user.setWordsPerDay(Integer.valueOf(sysParam.getParamValue()));

        user.setCreateTime(new Timestamp(new Date().getTime()));
        user.setLastLoginTime(new Date());
        user.setLearnedDays(0);
        user.setLearningFinished(false);
        user.setMasteredWordsCount(0);
        user.setCowDung(20); // 注册送魔法泡泡
        user.setThrowDiceChance(0);
        user.setInvitedBy(invitedBy);
        user.setInviteAwardTaken(false);
        user.setIsSuperAdmin(false);
        user.setIsAdmin(false);
        user.setIsInputor(false);
        user.setDakaDayCount(0);
        user.setAutoPlaySentence(false);
        user.setAutoPlayWord(true);
        user.setShowAnswersDirectly(true);
        user.setContinuousDakaDayCount(0);
        user.setMaxContinuousDakaDayCount(0);
        user.setDakaScore(0);
        user.setGameScore(0);
        user.setEnableAllWrong(false);
        user.setTodayStudyStarted(false);
        user.setAsrPassRule("ONE");
        user.setIsSysUser(isSysUser);
        user.setIsPremiumIos(false);
        user.setPremiumOverrideEnabled(false);

        // 持久化
        createEntity(user);
        logger.info("创建了新用户: [{}]", user.getDisplayNickName());

        // 创建用户的生词本
        dictBo.createRawWordDictForUser(user);

        // 创建用户的"已掌握"词书
        dictBo.createMasteredWordDictForUser(user);

        // 初始化学习步骤（En2Ch、Ch2En、List）
        userStudyStepBo.initUserStudySteps(user.getId());

        // 注释掉初始化同步日志，因为客户端的第一次同步是全量拉取，不需要这些增量日志
        // logInitialUserDataForSync(user, rawWordDict, masteredDict);

        return user;
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
            // 1. 优先根据 unionId 查找用户 (如果微信返回了 unionId)
            List<User> users = new ArrayList<>();
            if (wechatUserInfo.unionId != null && !wechatUserInfo.unionId.isEmpty()) {
                String sql = "SELECT * FROM \"user\" WHERE wechat_union_id = :unionId";
                MapSqlParameterSource params = new MapSqlParameterSource("unionId", wechatUserInfo.unionId);
                users = namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(User.class));
            }

            // 1.5 降级：如果根据 unionId 没找到，尝试根据 openId 查找（兼容历史没有保存 unionId 的老数据）
            if (users.isEmpty() && wechatUserInfo.openId != null && !wechatUserInfo.openId.isEmpty()) {
                String sql = "SELECT * FROM \"user\" WHERE wechat_open_id = :openId";
                MapSqlParameterSource params = new MapSqlParameterSource("openId", wechatUserInfo.openId);
                users = namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(User.class));
            }

            if (!users.isEmpty()) {
                // 用户已存在，更新微信信息（昵称、头像和可能补充上的 unionId）
                User existingUser = users.get(0);
                existingUser.setWechatNickname(wechatUserInfo.nickname);
                existingUser.setWechatAvatar(wechatUserInfo.headImgUrl);
                // 只要新的 openId 存在就更新一下，确保对应当前端的 openId 是最新的 (如果是从网站应用扫码进来的)
                if (wechatUserInfo.openId != null) {
                   existingUser.setWechatOpenId(wechatUserInfo.openId);
                }
                if (wechatUserInfo.unionId != null) {
                    existingUser.setWechatUnionId(wechatUserInfo.unionId);
                }
                existingUser.setLastLoginTime(new Date());
                updateEntity(existingUser);
                return existingUser;
            }

            // 2. 用户不存在，使用统一方法创建新用户。
            // 使用 UUID 生成唯一的 userName，防止 wx_xxx 重名触发唯一键冲突
            String userName = "wx_" + java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 16);
            String randomPassword = MD5Utils.md5(wechatUserInfo.openId + System.currentTimeMillis());

            User newUser = createNewUser(userName, randomPassword, wechatUserInfo.nickname,
                    null, null, false);

            // 设置微信特有字段
            newUser.setWechatOpenId(wechatUserInfo.openId);
            newUser.setWechatUnionId(wechatUserInfo.unionId);
            newUser.setWechatNickname(wechatUserInfo.nickname);
            newUser.setWechatAvatar(wechatUserInfo.headImgUrl);
            updateEntity(newUser);

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
