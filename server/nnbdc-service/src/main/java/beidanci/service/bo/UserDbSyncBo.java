package beidanci.service.bo;

import java.text.SimpleDateFormat;
import java.util.*;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.Assert;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionException;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.DefaultTransactionDefinition;

import beidanci.api.model.*;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.exception.DbVersionNotMatchException;
import beidanci.service.exception.RawWordDataErrorException;
import beidanci.service.po.*;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.UserSorter;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Service
public class UserDbSyncBo {
    private static final Logger logger = LoggerFactory.getLogger(UserDbSyncBo.class);

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 用户验证结果的内部类，仅封装数据库版本号
     * （User 对象已在验证过程中确认存在，后续只需要使用 userId 即可）
     */
    private static class UserValidationResult {
        private final int version;

        public UserValidationResult(int version) {
            this.version = version;
        }

        public int getVersion() {
            return version;
        }
    }

    @Autowired
    private UserBo userBo;

    @Autowired
    private LearningWordBo learningWordBo;

    @Autowired
    private LearningDictBo learningDictBo;

    @Autowired
    private BookMarkBo bookMarkBo;

    @Autowired
    private UserStudyStepBo userStudyStepBo;

    @Autowired
    private DakaBo dakaBo;

    @Autowired
    private UserOperBo userOperBo;

    @Autowired
    private WrongWordBo wrongWordBo;

    @Autowired
    private DictWordBo dictWordBo;

    @Autowired
    private UserCowDungLogBo userCowDungLogBo;

    @Autowired
    private UserDbLogBo userDbLogBo;

    @Autowired
    private LearningLogBo learningLogBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    @Autowired
    private UserDbVersionDao userDbVersionDao;

    @Autowired
    private UserDbIssueBo userDbIssueBo;

    @Autowired
    private UserSorter userSorter;

    @Autowired
    private UserStudyDailyStatBo userStudyDailyStatBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private DictBo dictBo;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    /**
     * 修复用户基础数据（生词本、已掌握、学习步骤），并生成同步日志，确保客户端能够增量同步。
     */
    @Transactional
    public void repairUserBaseData(String userId) {
        User user = userBo.findById(userId);
        if (user == null) {
            return;
        }

        List<UserDbLogDto> logs = new ArrayList<>();

        // 1. 检查并修复“生词本”
        Dict rawDict = dictBo.getRawWordDict(user);
        if (rawDict == null) {
            rawDict = dictBo.createRawWordDictForUser(user);
            logs.add(new UserDbLogDto(null, userId, 0, "INSERT", "dict", rawDict.getId(),
                    JsonUtils.toJson(dictBo.toDto(rawDict)), null, null));

            LearningDict ld = learningDictBo.getLearningDictOfUser(user, "生词本");
            if (ld != null) {
                logs.add(new UserDbLogDto(null, userId, 0, "INSERT", "learning_dict", userId + "-" + rawDict.getId(),
                        JsonUtils.toJson(learningDictBo.toDto(ld)), null, null));
            }
        }

        // 2. 检查并修复“已掌握”词书 (注：已掌握词书不需要也不允许出现在 learning_dict 中)
        Dict masteredDict = dictBo.getMasteredWordDict(user);
        if (masteredDict == null) {
            masteredDict = dictBo.createMasteredWordDictForUser(user);
            logs.add(new UserDbLogDto(null, userId, 0, "INSERT", "dict", masteredDict.getId(),
                    JsonUtils.toJson(dictBo.toDto(masteredDict)), null, null));
        }

        // 3. 检查并修复“学习步骤”
        List<UserStudyStep> stepsBefore = userStudyStepBo.getUserStudySteps(userId);
        userStudyStepBo.initUserStudySteps(userId);
        List<UserStudyStep> stepsAfter = userStudyStepBo.getUserStudySteps(userId);

        for (UserStudyStep stepAfter : stepsAfter) {
            boolean existed = stepsBefore.stream().anyMatch(s -> s.getStudyStep() == stepAfter.getStudyStep());
            if (!existed) {
                logs.add(new UserDbLogDto(null, userId, 0, "INSERT", "user_study_step",
                        userId + "-" + stepAfter.getStudyStep(),
                        JsonUtils.toJson(userStudyStepBo.toDto(stepAfter)), null, null));
            }
        }

        // 如果发生了修复，记录同步日志并升级版本号
        if (!logs.isEmpty()) {
            logUserOperations(userId, logs);
            logger.info("🛠️ [REPAIR] 用户[{}]的基础数据修复完成, 生成了 {} 条同步日志", user.getUserName(), logs.size());
        }
    }

    /**
     * 服务端主动修改用户数据后，将变更写入 user_db_log 并递增 user_db_version，
     * 这样客户端下一次同步即可拿到最新数据。
     *
     * @param userId 用户ID
     * @param logs   变更日志列表（每个日志包含表名、操作类型、记录ID、以及 JSON 格式的记录内容）
     */
    @Transactional
    public void logUserOperations(String userId, List<UserDbLogDto> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }

        // 确保版本记录存在
        userDbVersionDao.ensureUserDbVersionExists(jdbcTemplate, userId);

        // 加锁读当前版本号
        int currentVersion = userDbVersionDao.getUserDbVersionWithLock(jdbcTemplate, userId);
        int nextVersion = currentVersion + 1;

        Date now = new Date();
        for (UserDbLogDto logDto : logs) {
            UserDbLog log = new UserDbLog();
            log.setUserId(userId);
            log.setVersion(nextVersion);
            log.setCreateTime(now);
            log.setUpdateTime(now);
            log.setTable(logDto.getTblName());
            log.setOperate(logDto.getOperate());
            log.setRecordId(logDto.getRecordId());
            log.setRecord(JsonUtils.enrichRecordJson(logDto.getRecord()));
            userDbLogBo.createEntity(log);
        }

        // 使用 CAS 原子更新数据库版本（虽然已加锁，但使用 CAS 更安全）
        boolean ok = userDbVersionDao.updateUserDbVersionCAS(jdbcTemplate, userId, currentVersion, nextVersion);
        if (!ok) {
            throw new RuntimeException("更新 user_db_version 失败（可能存在并发修改），userId=" + userId);
        }
    }

    /**
     * 服务端主动修改用户数据后，将单个变更写入 user_db_log (增强安全性版本，包含对象所有权校验)。
     */
    public void logUserOperation(Object entity, String userId, String tblName, String operate, String recordId, String recordJson) {
        if (entity instanceof Ownerable) {
            String ownerId = ((Ownerable) entity).getOwnerId();
            Assert.isTrue(userId.equals(ownerId),
                    "SECURITY ALERT: Attempted to log data belonging to user [" + ownerId + "] to sync log of user [" + userId + "]!");
        }
        logUserOperation(userId, tblName, operate, recordId, recordJson);
    }

    /**
     * 服务端主动修改用户数据后，将单个变更写入 user_db_log。
     */
    @Transactional
    public void logUserOperation(String userId, String tblName, String operate, String recordId, String recordJson) {
        UserDbLogDto logDto = new UserDbLogDto(null, userId, 0, operate, tblName, recordId, recordJson, null, null);
        List<UserDbLogDto> logs = new ArrayList<>();
        logs.add(logDto);
        logUserOperations(userId, logs);
    }

    /**
     * 同步用户客户端数据库到服务端
     *
     * @param userId                  用户ID
     * @param expectedServerDbVersion 期望的服务端数据库版本（用于防止并发问题）
     * @param logs                    同步日志列表
     * @return 同步后，服务端数据库最新版本
     * @throws DbVersionNotMatchException 数据库版本不匹配异常
     * @throws IllegalAccessException     非法访问异常
     * @throws RawWordDataErrorException  生词数据错误异常
     */
    public int syncUserDb2Back(String userId, int expectedServerDbVersion, List<UserDbLogDto> logs)
            throws DbVersionNotMatchException, IllegalAccessException, RawWordDataErrorException {

        DefaultTransactionDefinition def = new DefaultTransactionDefinition();
        def.setName("syncUserDb");
        def.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRED);
        TransactionStatus status = transactionManager.getTransaction(def);

        try {
            // 验证用户和版本，同时获取加锁后的版本号
            UserValidationResult validationResult = validateUserAndVersion(userId, expectedServerDbVersion);
            if (validationResult == null) {
                // 用户不存在，直接提交空事务
                transactionManager.commit(status);
                return 0;
            }

            // 使用已经加锁查询的版本号，避免重复查询数据库
            final int lastVersion = validationResult.getVersion();

            // 执行数据同步
            Date now = new Date();
            for (UserDbLogDto log : logs) {
                String recordJson = null;
                try {
                    recordJson = JsonUtils.enrichRecordJson(log.getRecord());
                    processSyncLog(userId, log, recordJson);

                    // 检查record id是否超出长度限制
                    if (log.getRecordId().length() > 131) {
                        throw new IllegalArgumentException(String.format("record id(%s)超出长度限制(最多131), table(%s)",
                                log.getRecordId(), log.getTblName()));
                    }

                    // 生成服务端数据库日志(用于同步到该用户的其他客户端)
                    UserDbLog userDbLog = new UserDbLog();
                    userDbLog.setUserId(userId);
                    userDbLog.setVersion(lastVersion + 1);
                    userDbLog.setCreateTime(now);
                    userDbLog.setUpdateTime(now);
                    userDbLog.setTable(log.getTblName());
                    userDbLog.setRecordId(log.getRecordId());
                    userDbLog.setOperate(log.getOperate());
                    userDbLog.setRecord(recordJson);
                    userDbLogBo.createEntity(userDbLog);
                } catch (IllegalAccessException | IllegalArgumentException e) {
                    // 任何异常都会导致整个事务回滚
                    logger.error("同步数据失败，将回滚整个事务, 用户[{}], 表[{}], 记录[{}], 错误: {}",
                            userId, log.getTblName(), recordJson, e.getMessage());
                    logger.error("异常详情:", e);
                    throw new RuntimeException("同步数据失败: " + e.getMessage(), e);
                }
            }

            // 生词本顺序校验和后续处理
            validateAndFinalizeSync(userId, logs, lastVersion);

            transactionManager.commit(status);
            return lastVersion + 1;
        } catch (DbVersionNotMatchException | RawWordDataErrorException | IllegalAccessException | RuntimeException e) {
            try {
                // 检查事务状态，只有在事务仍然活跃时才回滚
                if (!status.isCompleted()) {
                    transactionManager.rollback(status);
                } else {
                    logger.warn("事务已经完成，跳过回滚操作");
                }
            } catch (TransactionException ex) {
                logger.error("回滚事务失败: {}", ex.getMessage(), ex);
            }
            if (e instanceof DbVersionNotMatchException dbVersionNotMatchException)
                throw dbVersionNotMatchException;
            if (e instanceof IllegalAccessException illegalAccessException)
                throw illegalAccessException;
            if (e instanceof RawWordDataErrorException rawWordDataErrorException)
                throw rawWordDataErrorException;
            throw new RuntimeException(e.getMessage(), e);
        }
    }

    /**
     * 验证用户和版本（使用数据库行锁防止并发冲突）
     * 
     * 重要改进：
     * 1. 使用 FOR UPDATE 行锁来防止并发事务同时修改同一用户的数据
     * 2. 同时返回用户对象和版本号，避免调用方重复查询
     * 
     * @param userId                  用户ID
     * @param expectedServerDbVersion 期望的服务端数据库版本
     * @return UserValidationResult 包含用户对象和版本号，如果用户不存在则返回null
     * @throws DbVersionNotMatchException 版本号不匹配时抛出
     */
    private UserValidationResult validateUserAndVersion(String userId, int expectedServerDbVersion)
            throws DbVersionNotMatchException {
        // 如果用户不存在，则返回null（这种情况可能发生在客户端未登录到后端时，指定要同步的用户（用户可能是前端首先创建的））
        User user = userBo.findById(userId);
        if (user == null) {
            return null;
        }

        // 使用 FOR UPDATE 锁定版本号记录，防止并发修改
        // 注意：这个锁会一直持有到事务提交或回滚

        // 先确保版本记录存在（对于新用户可能不存在）
        userDbVersionDao.ensureUserDbVersionExists(jdbcTemplate, userId);

        // 使用带锁的查询方法，锁定该用户的版本号行
        final int lastVersion = userDbVersionDao.getUserDbVersionWithLock(jdbcTemplate, userId);

        if (expectedServerDbVersion != lastVersion) {
            logger.error("数据库版本不匹配: expected={}, actual={}", expectedServerDbVersion, lastVersion);
            throw new DbVersionNotMatchException(String.format("数据库版本不匹配，期望版本[%d]，当前版本[%d]，本次同步失败（请重试）",
                    expectedServerDbVersion, lastVersion));
        }

        // 返回版本号，避免调用方重复查询
        return new UserValidationResult(lastVersion);
    }

    /**
     * 处理单个同步日志
     */
    private void processSyncLog(String userId, UserDbLogDto log, String recordJson)
            throws IllegalAccessException {
        String tableName = log.getTblName().toLowerCase();
        String operation = log.getOperate().toUpperCase();

        switch (tableName) {
            case "learning_word" -> processLearningWordSync(userId, recordJson, operation);
            case "learning_dict" -> processLearningDictSync(userId, recordJson, operation);
            case "user" -> processUserSync(userId, recordJson, operation);
            case "dict" -> processDictSync(userId, recordJson, operation);
            case "book_mark" -> processBookMarkSync(userId, recordJson, operation);
            case "user_study_step" -> processUserStudyStepSync(userId, recordJson, operation);
            case "daka" -> processDakasSync(userId, recordJson, operation);
            case "user_oper" -> processUserOperSync(userId, recordJson, operation);
            case "user_wrong_word" -> processUserWrongWordSync(userId, recordJson, operation);
            case "dict_word" -> processDictWordSync(userId, recordJson, operation);
            case "mastered_word" -> {
                // 已废弃：mastered_word 表已迁移到 dict + dict_word 体系
                // 保留此 case 以兼容老客户端可能发送的旧格式日志，直接忽略
                logger.info("忽略已废弃的 mastered_word 同步日志: operation={}", operation);
            }
            case "user_cow_dung_log" -> processUserCowDungLogSync(userId, recordJson, operation);
            case "meaning_item" -> processMeaningItemSync(userId, recordJson, operation);
            case "learning_log" -> processLearningLogSync(userId, recordJson, operation);
            case "user_study_daily_stat" -> processUserStudyDailyStatSync(userId, recordJson, operation);
            default -> {
                String errorMsg = String.format("不支持的表同步: %s, 记录ID: %s, 操作: %s", tableName, log.getRecordId(),
                        operation);
                logger.warn(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            }
        }
    }

    /**
     * 处理学习单词同步
     */
    private void processLearningWordSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            learningWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            LearningWordDto learningWordDto = JsonUtils.makeObject(recordJson, LearningWordDto.class);
            learningWordDto.setUserId(userId);
            LearningWord learningWord = LearningWord.fromDto(learningWordDto);
            switch (operation) {
                case "INSERT" -> {
                    // 检查记录是否已存在，避免主键冲突
                    LearningWord existing = learningWordBo.findById(learningWord.getId());
                    if (existing == null) {
                        learningWordBo.createEntity(learningWord);
                    } else {
                        logger.info("learning_word 已存在，忽略重复 INSERT: id={}", learningWord.getId());
                    }
                }
                case "UPDATE" -> {
                    // 检查记录是否存在，不存在则创建
                    LearningWord existingForUpdate = learningWordBo.findById(learningWord.getId());
                    if (existingForUpdate == null) {
                        learningWordBo.createEntity(learningWord);
                    } else {
                        learningWordBo.updateEntity(learningWord);
                    }
                }
                case "DELETE" -> learningWordBo.deleteEntity(learningWord);
            }
        }
    }

    /**
     * 处理学习词典同步
     */
    private void processLearningDictSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            learningDictBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            LearningDictDto learningDictDto = JsonUtils.makeObject(recordJson, LearningDictDto.class);
            learningDictDto.setUserId(userId);
            LearningDict learningDict = LearningDict.fromDto(learningDictDto, wordBo, dictBo, userBo);
            switch (operation) {
                case "INSERT" -> {
                    // 【校验一】禁止将“已掌握”词书添加到学习计划中
                    Dict dict = dictBo.findById(learningDictDto.getDictId());
                    if (dict != null && "已掌握".equals(dict.getName())) {
                        throw new IllegalArgumentException("“已掌握”词书不允许作为学习计划同步");
                    }

                    // 检查记录是否已存在，避免主键冲突
                    LearningDict existing = learningDictBo.findById(learningDict.getId());
                    if (existing == null) {
                        learningDictBo.createEntity(learningDict);
                    } else {
                        logger.info("learning_dict 已存在，忽略重复 INSERT: user_id={}, dict_id={}",
                                userId, learningDictDto.getDictId());
                    }
                }
                case "UPDATE" -> {
                    // 检查记录是否存在，不存在则创建
                    LearningDict existingForUpdate = learningDictBo.findById(learningDict.getId());
                    if (existingForUpdate == null) {
                        learningDictBo.createEntity(learningDict);
                    } else {
                        learningDictBo.updateEntity(learningDict);
                    }
                }
                case "DELETE" -> learningDictBo.deleteEntity(learningDict);
            }
        }
    }

    /**
     * 处理用户同步
     * 注意：isAdmin、isSuperAdmin、isSysUser 这三个字段只允许后端同步到前端，不允许前端修改
     */
    private void processUserSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("UPDATE".equals(operation)) {
            UserDto userDto = JsonUtils.makeObject(recordJson, UserDto.class);
            User user = userBo.findById(userId);
            if (user != null) {
                String platform = MDC.get("platform");
                String premiumStatus = getPremiumStatusString(user);
                SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
                logger.info("收到用户同步请求: 昵称={}, ID={}, 学习天数={}, 已掌握={}, 客户端={}, 创建时间={}, 会员状态={}",
                        userDto.getNickName(),
                        userId.substring(0, Math.min(userId.length(), 6)),
                        userDto.getLearnedDays(),
                        userDto.getMasteredWordsCount(),
                        platform != null ? platform : "Unknown",
                        userDto.getCreateTime() != null ? sdf.format(userDto.getCreateTime()) : "未知",
                        premiumStatus);
                User userFromClient = User.fromDto(userDto);

                // 保护敏感字段：isAdmin、isSuperAdmin、isSysUser 只允许后端同步到前端
                // 将这些字段从后端数据库的原始值恢复到 userFromClient
                userFromClient.setIsAdmin(user.getIsAdmin());
                userFromClient.setIsSuperAdmin(user.getIsSuperAdmin());
                userFromClient.setIsSysUser(user.getIsSysUser());

                // 同样，保护微信相关的只读字段，如果不回填，会被无相关支持的老客户端/未下发字段写成空
                userFromClient.setWechatOpenId(user.getWechatOpenId());
                userFromClient.setWechatUnionId(user.getWechatUnionId());
                userFromClient.setWechatNickname(user.getWechatNickname());
                // 头像允许由客户端同步（仅当客户端提供了非空值，例如手动设置头像场景），
                // 否则回填服务端的值防止老客户端误将字段写空。
                if (userDto.getWechatAvatar() == null || userDto.getWechatAvatar().isEmpty()) {
                    userFromClient.setWechatAvatar(user.getWechatAvatar());
                }
                userFromClient.setAppleUserId(user.getAppleUserId());

                // 订阅字段仅允许后端维护（客户端同步UserDto不包含这些字段）
                // 如果不回填，update 时会把字段覆盖成 null/默认值，甚至触发 NOT NULL 约束
                userFromClient.setIsPremiumIos(Boolean.TRUE.equals(user.getIsPremiumIos()));
                userFromClient.setSubscriptionExpireDateIos(user.getSubscriptionExpireDateIos());
                userFromClient.setSubscriptionTypeIos(user.getSubscriptionTypeIos());
                userFromClient.setSubscriptionStatusIos(user.getSubscriptionStatusIos());
                userFromClient.setLastReceiptDataIos(user.getLastReceiptDataIos());

                // 强制会员字段同样只允许后端维护（避免客户端覆盖）
                userFromClient.setPremiumOverrideEnabled(Boolean.TRUE.equals(user.getPremiumOverrideEnabled()));
                userFromClient.setPremiumOverrideUpdateTime(user.getPremiumOverrideUpdateTime());
                userFromClient.setPremiumOverrideReason(user.getPremiumOverrideReason());
                userFromClient.setPremiumOverrideDuration(user.getPremiumOverrideDuration());

                // 防止邮箱冲突：如果客户端同步过来的邮箱已被占用，置空它以防报错阻断同步
                String clientEmail = userFromClient.getEmail();
                if (clientEmail != null && !clientEmail.isEmpty()) {
                    List<User> existingUsers = userBo.findByEmail(clientEmail);
                    if (existingUsers != null && !existingUsers.isEmpty()) {
                        for (User u : existingUsers) {
                            if (!u.getId().equals(userId)) {
                                logger.warn("用户同步的邮箱 '{}' 已被其他账号使用，强制清空该同步数据", clientEmail);
                                userFromClient.setEmail("");
                                break;
                            }
                        }
                    }
                }

                userBo.updateEntity(userFromClient);
                logger.info("同步更新用户成功: userName={}", userFromClient.getUserName());
            }
        } else {
            String errorMsg = String.format("不支持的用户表操作: %s", operation);
            logger.error(errorMsg);
            throw new IllegalArgumentException(errorMsg);
        }
        // 不支持INSERT和DELETE操作，用户记录应当已经存在
    }

    /**
     * 处理词书同步
     */
    private void processDictSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        DictDto dictDto = JsonUtils.makeObject(recordJson, DictDto.class);
    
        // 只允许用户同步自己的词书或共享词书
        // 场景 1: 用户同步自己创建的词书 (ownerId == userId)
        // 场景 2: 用户同步其他人创建的共享词书 (isShared == true)
        boolean isOwner = userId.equals(dictDto.getOwnerId());
        boolean isShared = Boolean.TRUE.equals(dictDto.getIsShared());
            
        if (!isOwner && !isShared) {
            String errorMsg = String.format("用户%s尝试同步不属于自己的词书且该词书未共享：dictId=%s, ownerId=%s, isShared=%s",
                    userId, dictDto.getId(), dictDto.getOwnerId(), dictDto.getIsShared());
            logger.warn(errorMsg);
            throw new IllegalArgumentException(errorMsg);
        }

        if (null == operation) {
            String errorMsg = String.format("不支持的词书表操作: %s", operation);
            logger.error(errorMsg);
            throw new IllegalArgumentException(errorMsg);
        } else
            switch (operation) {
                case "INSERT", "UPDATE" -> {
                    Dict dict = dictBo.findById(dictDto.getId());
                    User owner = userBo.findById(dictDto.getOwnerId());
                    if (owner == null) {
                        String errorMsg = String.format("词书所属用户不存在: ownerId=%s", dictDto.getOwnerId());
                        logger.error(errorMsg);
                        throw new IllegalArgumentException(errorMsg);
                    }

                    // 【强制校验一】禁止通过同步接口创建核心或系统词书
                    String name = dictDto.getName();
                    String ownerId = dictDto.getOwnerId();
                    if (dict == null) {
                        if ("生词本".equals(name) || "已掌握".equals(name) || Constants.SYS_USER_SYS_ID.equals(ownerId)) {
                            throw new IllegalArgumentException(String.format("禁止通过同步创建核心/系统词书: name=[%s], ownerId=[%s]", name, ownerId));
                        }
                    }

                    // 【强制校验二】禁止通过同步接口修改核心或系统词书的基础配置 (如名称)
                    if (dict != null) {
                        String oldName = dict.getName();
                        String oldOwnerId = dict.getOwner().getId();
                        if ("生词本".equals(oldName) || "已掌握".equals(oldName) || Constants.SYS_USER_SYS_ID.equals(oldOwnerId)) {
                            if (!oldName.equals(name)) {
                                throw new IllegalArgumentException(String.format("禁止通过同步修改核心/系统词书名称: oldName=[%s], newName=[%s]", oldName, name));
                            }
                        }
                    }

                    if (dict == null) {
                        // 创建新词书
                        dict = new Dict();
                        dict.setId(dictDto.getId());
                        dict.setName(dictDto.getName());
                        dict.setOwner(owner);
                        dict.setIsShared(dictDto.getIsShared());
                        dict.setIsReady(dictDto.getIsReady());
                        dict.setVisible(dictDto.getVisible());
                        dict.setWordCount(dictDto.getWordCount());
                        dict.setPopularityLimit(dictDto.getPopularityLimit());
                        dict.setEditable(dictDto.getEditable() != null ? dictDto.getEditable() : false);
                        dict.setCreateTime(dictDto.getCreateTime());
                        dict.setUpdateTime(dictDto.getUpdateTime() != null ? dictDto.getUpdateTime() : dictDto.getCreateTime());

                        dictBo.createEntity(dict);
                        logger.debug("同步创建词书成功: dictId={}, name={}, wordCount={}",
                                dict.getId(), dict.getName(), dict.getWordCount());
                    } else {
                        // 更新现有词书
                        dict.setName(dictDto.getName());
                        dict.setOwner(owner);
                        dict.setIsShared(dictDto.getIsShared());
                        dict.setIsReady(dictDto.getIsReady());
                        dict.setVisible(dictDto.getVisible());
                        dict.setWordCount(dictDto.getWordCount());
                        dict.setPopularityLimit(dictDto.getPopularityLimit());
                        dict.setEditable(dictDto.getEditable() != null ? dictDto.getEditable() : false);
                        dict.setUpdateTime(dictDto.getUpdateTime());

                        dictBo.updateEntity(dict);
                        logger.debug("同步更新词书成功: dictId={}, name={}, wordCount={}",
                                dict.getId(), dict.getName(), dict.getWordCount());
                    }
                }
                case "DELETE" -> {
                    Dict dict = dictBo.findById(dictDto.getId());
                    if (dict != null) {
                        if (!isOwner) {
                            String errorMsg = String.format("尝试删除不属于自己的词书: dictId=%s", dictDto.getId());
                            logger.warn(errorMsg);
                            throw new IllegalArgumentException(errorMsg);
                        }
                        dictBo.deleteDictSafely(dict.getId());
                        logger.debug("同步删除词书成功: dictId={}", dictDto.getId());
                    }
                }
                default -> {
                    String errorMsg = String.format("不支持的词书表操作: %s", operation);
                    logger.error(errorMsg);
                    throw new IllegalArgumentException(errorMsg);
                }
            }
    }

    /**
     * 处理书签同步
     */
    private void processBookMarkSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            bookMarkBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            BookMarkDto bookMarkDto = JsonUtils.makeObject(recordJson, BookMarkDto.class);

            if (null == operation) {
                String errorMsg = String.format("不支持的书签表操作: %s", operation);
                logger.error(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            } else
                switch (operation) {
                    case "INSERT", "UPDATE" -> bookMarkBo.saveBookMark(bookMarkDto.getBookMarkName(),
                            bookMarkDto.getSpell(),
                            bookMarkDto.getPosition(),
                            bookMarkDto.getUserId());
                    case "DELETE" -> {
                        BookMark bookMark = BookMark.fromDto(bookMarkDto);
                        bookMarkBo.deleteEntity(bookMark);
                    }
                    default -> {
                        String errorMsg = String.format("不支持的书签表操作: %s", operation);
                        logger.error(errorMsg);
                        throw new IllegalArgumentException(errorMsg);
                    }
                }
        }
    }

    /**
     * 处理用户学习步骤同步
     */
    private void processUserStudyStepSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            userStudyStepBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            UserStudyStepDto stepDto = JsonUtils.makeObject(recordJson, UserStudyStepDto.class);
            stepDto.setUserId(userId);
            UserStudyStepId id = new UserStudyStepId(userId, stepDto.getStudyStep());
            UserStudyStep studyStep = new UserStudyStep(id);
            studyStep.setSeq(stepDto.getSeq());
            studyStep.setState(stepDto.getState());

            if (stepDto.getCreateTime() != null) {
                studyStep.setCreateTime(stepDto.getCreateTime());
            }
            if (stepDto.getUpdateTime() != null) {
                studyStep.setUpdateTime(stepDto.getUpdateTime());
            }

            switch (operation) {
                case "INSERT" -> {
                    // 【校验三】禁止通过同步创建学习步骤
                    throw new IllegalArgumentException(String.format("禁止通过同步创建学习步骤: step=[%s]", stepDto.getStudyStep()));
                }
                case "UPDATE" -> {
                    // 检查记录是否存在，不存在则创建
                    UserStudyStep existingForUpdate = userStudyStepBo.findById(id);
                    if (existingForUpdate == null) {
                        userStudyStepBo.createEntity(studyStep);
                    } else {
                        userStudyStepBo.updateEntity(studyStep);
                    }
                }
                case "DELETE" -> userStudyStepBo.deleteEntity(studyStep);
                default -> {
                    String errorMsg = String.format("不支持的用户学习步骤表操作: %s", operation);
                    logger.error(errorMsg);
                    throw new IllegalArgumentException(errorMsg);
                }
            }
        }
    }

    /**
     * 处理每日学习统计同步
     */
    private void processUserStudyDailyStatSync(String userId, String recordJson, String operation) throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            userStudyDailyStatBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            UserStudyDailyStatDto statsDto = JsonUtils.makeObject(recordJson, UserStudyDailyStatDto.class);
            statsDto.setUserId(userId);
            UserStudyDailyStat stats = userStudyDailyStatBo.fromDto(statsDto);
            switch (operation) {
                case "INSERT", "UPDATE" -> {
                    UserStudyDailyStat existing = userStudyDailyStatBo.findById(stats.getId());
                    if (existing == null) {
                        userStudyDailyStatBo.createEntity(stats);
                    } else {
                        userStudyDailyStatBo.updateEntity(stats);
                    }
                }
                case "DELETE" -> userStudyDailyStatBo.deleteEntity(stats);
            }
        }
    }

    /**
     * 处理打卡同步
     */
    private void processDakasSync(String userId, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            dakaBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                DakaDto dakaDto = JsonUtils.makeObject(recordJson, DakaDto.class);
                dakaDto.setUserId(userId);
                Daka daka = dakaBo.fromDto(dakaDto);

                switch (operation) {
                    case "INSERT" -> {
                        // 检查记录是否已存在，避免主键冲突
                        Daka existing = dakaBo.findById(daka.getId());
                        if (existing == null) {
                            dakaBo.createEntity(daka);
                        } else {
                            logger.info("daka 已存在，忽略重复 INSERT: id={}", daka.getId());
                        }
                    }
                    case "UPDATE" -> {
                        // 检查记录是否存在，不存在则创建
                        Daka existingForUpdate = dakaBo.findById(daka.getId());
                        if (existingForUpdate == null) {
                            dakaBo.createEntity(daka);
                        } else {
                            dakaBo.updateEntity(daka);
                        }
                    }
                    case "DELETE" -> dakaBo.deleteEntity(daka);
                }
            } catch (IllegalAccessException | IllegalArgumentException e) {
                logger.error("同步打卡数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理用户操作历史同步
     */
    private void processUserOperSync(String userId, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            userOperBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            UserOperDto operDto = JsonUtils.makeObject(recordJson, UserOperDto.class);
            operDto.setUserId(userId);
            UserOper oper = userOperBo.fromDto(operDto);
            if ("INSERT".equals(operation)) {
                // 检查记录是否已存在，避免主键冲突
                UserOper existing = userOperBo.findById(oper.getId());
                if (existing == null) {
                    userOperBo.createEntity(oper);
                } else {
                    logger.info("user_oper 已存在，忽略重复 INSERT: id={}", oper.getId());
                }
            } else {
                String errorMsg = String.format("不支持的操作：%s，用户操作历史记录不支持删除", operation);
                logger.error(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            }
        }
    }

    /**
     * 处理错词同步
     */
    private void processUserWrongWordSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            wrongWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            WrongWordDto wrongWordDto = JsonUtils.makeObject(recordJson, WrongWordDto.class);
            wrongWordDto.setUserId(userId);
            WrongWord wrongWord = WrongWord.fromDto(wrongWordDto);
            switch (operation) {
                case "INSERT" -> wrongWordBo.createIfAbsent(wrongWord);
                case "UPDATE" -> {
                    // 检查记录是否存在，不存在则创建
                    WrongWord existingForUpdate = wrongWordBo.findById(wrongWord.getId());
                    if (existingForUpdate == null) {
                        wrongWordBo.createEntity(wrongWord);
                    } else {
                        wrongWordBo.updateEntity(wrongWord);
                    }
                }
                case "DELETE" -> wrongWordBo.deleteEntity(wrongWord);
                default -> {
                    String errorMsg = String.format("不支持的错词表操作: %s", operation);
                    logger.error(errorMsg);
                    throw new IllegalArgumentException(errorMsg);
                }
            }
        }
    }

    /**
     * 处理生词本同步
     */
    private void processDictWordSync(String userId, String recordJson, String operation) throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            dictWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            DictWordDto dictWordDto = JsonUtils.makeObject(recordJson, DictWordDto.class);
            DictWord dictWord = DictWord.fromDto(dictWordDto);
            DictWord existing = dictWordBo.findById(dictWord.getId());

            switch (operation) {
                case "INSERT" -> {
                    if (existing == null) {
                        dictWordBo.createEntity(dictWord);
                    } else {
                        logger.info("dict_word 已存在，忽略重复 INSERT");
                    }
                }
                case "UPDATE" -> {
                    if (existing == null) {
                        dictWordBo.createEntity(dictWord);
                    } else {
                        dictWordBo.updateEntity(dictWord);
                    }
                }
                case "DELETE" -> {
                    if (existing != null) {
                        deleteDictWordSafely(dictWord);
                    }
                }
                default -> {
                    String errorMsg = String.format("不支持的生词表操作: %s", operation);
                    logger.error(errorMsg);
                    throw new IllegalArgumentException(errorMsg);
                }
            }
        }
    }

    /**
     * 安全删除生词本记录
     */
    private void deleteDictWordSafely(DictWord dictWord) {
        try {
            DictWord toDelete = dictWordBo.findById(dictWord.getId());
            if (toDelete != null) {
                dictWordBo.deleteEntity(toDelete);
            }
        } catch (Exception deleteEx) {
            logger.warn("删除dict_word时出现异常，尝试使用原生SQL删除: {}", deleteEx.getMessage());
            try {
                String deleteSql = "DELETE FROM dict_word WHERE dict_id = ? AND word_id = ?";
                int deletedRows = jdbcTemplate.update(deleteSql,
                        dictWord.getId().getDictId(),
                        dictWord.getId().getWordId());
                if (deletedRows > 0) {
                    logger.info("使用原生SQL成功删除dict_word: dictId={}, wordId={}",
                            dictWord.getId().getDictId(), dictWord.getId().getWordId());
                }
            } catch (DataAccessException sqlEx) {
                logger.error("使用原生SQL删除dict_word也失败: {}", sqlEx.getMessage(), sqlEx);
                throw sqlEx;
            }
        }
    }

    // processMasteredWordSync 已移除：mastered_word 表已迁移到 dict + dict_word 体系

    /**
     * 处理魔法泡泡日志同步
     */
    private void processUserCowDungLogSync(String userId, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            userCowDungLogBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            UserCowDungLogDto cowDungLogDto = JsonUtils.makeObject(recordJson, UserCowDungLogDto.class);
            cowDungLogDto.setUserId(userId);
            UserCowDungLog cowDungLog = UserCowDungLog.fromDto(cowDungLogDto);
            User user = userBo.findById(cowDungLogDto.getUserId());
            if (user != null) {
                cowDungLog.setUser(user);
                if ("INSERT".equals(operation)) {
                    // 检查记录是否已存在，避免主键冲突
                    UserCowDungLog existing = userCowDungLogBo.findById(cowDungLog.getId());
                    if (existing == null) {
                        userCowDungLogBo.createEntity(cowDungLog);
                    } else {
                        logger.info("user_cow_dung_log 已存在，忽略重复 INSERT: id={}", cowDungLog.getId());
                    }
                } else {
                    String errorMsg = String.format("不支持的魔法泡泡日志表操作: %s", operation);
                    logger.error(errorMsg);
                    throw new IllegalArgumentException(errorMsg);
                }
                // 注意：魔法泡泡日志通常只支持INSERT操作
            } else {
                String errorMsg = "魔法泡泡日志关联的用户不存在";
                logger.error(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            }
        }
    }

    /**
     * 处理记忆历史日志同步
     */
    private void processLearningLogSync(String userId, String recordJson, String operation) throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            learningLogBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            LearningLogDto dto = JsonUtils.makeObject(recordJson, LearningLogDto.class);
            dto.setUserId(userId);
            LearningLog log = LearningLog.fromDto(dto);
            if ("INSERT".equals(operation)) {
                LearningLog existing = learningLogBo.findById(log.getId());
                if (existing == null) {
                    learningLogBo.createEntity(log);
                } else {
                    logger.info("learning_log 已存在，忽略重复 INSERT: id={}", log.getId());
                }
            } else if ("UPDATE".equals(operation)) {
                LearningLog existing = learningLogBo.findById(log.getId());
                if (existing == null) {
                    learningLogBo.createEntity(log);
                } else {
                    learningLogBo.updateEntity(log);
                }
            } else if ("DELETE".equals(operation)) {
                learningLogBo.deleteEntity(log);
            } else {
                String errorMsg = String.format("不支持的 learning_log日志表操作: %s", operation);
                logger.error(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            }
        }
    }

    /**
     * 验证和完成同步（使用 CAS 原子更新版本号）
     * 
     * 重要改进：使用 CAS (Compare-And-Swap) 来更新版本号，确保原子性
     */
    private void validateAndFinalizeSync(String userId, List<UserDbLogDto> logs, int lastVersion)
            throws IllegalAccessException, RawWordDataErrorException, DbVersionNotMatchException {
        // 用户所有个人词书的顺序校验
        try {
            String issue = dictWordBo.validateDictWordsOrderOfUser(userId);
            if (issue != null) {
                userDbIssueBo.recordIssue(userId, "DICT_WORD_ORDER_INVALID", issue);
                throw new RawWordDataErrorException("DICT_WORD_ORDER_INVALID: " + issue);
            }
        } catch (RawWordDataErrorException e) {
            throw e;
        } catch (IllegalAccessException e) {
            logger.error("校验生词本顺序失败，将回滚整个事务: {}", e.getMessage(), e);
            throw new RuntimeException("校验生词本顺序失败: " + e.getMessage(), e);
        }

        // 更新用户排名（在版本号更新之前，避免排名更新失败影响版本号）
        updateUserRankingIfNeeded(userId, logs);

        // 使用 CAS 原子更新数据库版本
        final int newVersion = lastVersion + 1;
        boolean updateSuccess = userDbVersionDao.updateUserDbVersionCAS(jdbcTemplate, userId, lastVersion, newVersion);

        if (!updateSuccess) {
            // CAS 更新失败，说明版本号在同步过程中被其他事务修改了
            // 这种情况理论上不应该发生，因为我们在 validateUserAndVersion 中已经加了行锁
            // 但为了安全起见，还是要处理这种情况
            logger.error("使用 CAS 更新版本号失败，期望版本[{}]，新版本[{}]",
                    lastVersion, newVersion);
            throw new DbVersionNotMatchException(String.format(
                    "更新数据库版本失败，期望版本[%d]，可能存在并发修改", lastVersion));
        }

        logger.info("数据库版本更新成功：{} -> {}", lastVersion, newVersion);
    }

    /**
     * 如果需要，更新用户排名
     */
    private void updateUserRankingIfNeeded(String userId, List<UserDbLogDto> logs) {
        boolean needUpdateRanking = logs.stream()
                .anyMatch(log -> log.getTblName().equalsIgnoreCase("dakas") ||
                        log.getTblName().equalsIgnoreCase("user_game") ||
                        log.getTblName().equalsIgnoreCase("user"));

        if (needUpdateRanking) {
            try {
                User updatedUser = userBo.findById(userId);
                if (updatedUser != null) {
                    List<User> changedUsers = new ArrayList<>();
                    changedUsers.add(updatedUser);
                    userSorter.onUserChanged(changedUsers);
                    logger.info("数据同步后，排名已更新");
                }
            } catch (Exception e) {
                logger.error("更新用户排名失败，将回滚整个事务：" + e.getMessage(), e);
                throw new RuntimeException("更新用户排名失败: " + e.getMessage(), e);
            }
        }
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
     * 获取 fromVersion 之后第一条日志的创建时间
     * 用于判断日志是否过旧，可能已被清理
     *
     * @param userId      用户ID
     * @param fromVersion 起始版本号（不包含）
     * @return 第一条日志的创建时间，如果不存在则返回 null
     */
    private Date getFirstLogTimeAfterVersion(String userId, int fromVersion) {
        String sql = "SELECT create_time FROM user_db_log WHERE user_id = :userId AND version > :fromVersion ORDER BY version ASC LIMIT 1";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("fromVersion", fromVersion);
        try {
            return namedParameterJdbcTemplate.queryForObject(sql, params, Date.class);
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            return null;
        }
    }

    /**
     * 获取增量日志数量
     *
     * @param userId      用户ID
     * @param fromVersion 起始版本号（不包含）
     * @return 增量日志数量
     */
    private long getIncrementalLogCount(String userId, int fromVersion) {
        String sql = "SELECT COUNT(*) FROM user_db_log WHERE user_id = :userId AND version > :fromVersion";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("userId", userId);
        params.addValue("fromVersion", fromVersion);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count != null ? count : 0L;
    }

    /**
     * 获取用户数据库日志
     *
     * @param fromVersion 从此版本开始，不包括此版本
     * @return
     */
    public List<UserDbLogDto> getUserDbLogsFromVersion(String userId, int fromVersion) {
        User user = userBo.findById(userId);

        // 如果用户不存在，则返回空列表（这种情况可能发生在客户端未登录到后端时，指定要同步的用户（用户可能是前端首先创建的））
        if (user == null) {
            return new ArrayList<>();
        }

        // 获取用户数据库版本
        int userDbVersion = userDbVersionDao.getUserDbVersion(jdbcTemplate, userId);
        logger.info("查询用户数据库日志: serverVersion={}, clientFromVersion={}", userDbVersion, fromVersion);

        // 1. 如果前后端版本一致，无需任何同步
        if (userDbVersion <= fromVersion && fromVersion > 0) {
            logger.info("前后端版本一致且不为0，无需同步");
            return new ArrayList<>();
        }

        // 判定是否需要全量同步
        boolean needsFullSync = false;
        if (fromVersion == 0) {
            needsFullSync = true;
        } else if (!hasVersionLogs(userId, fromVersion + 1)) {
            // 连下一条日志都找不到，必然需要全量同步（可能是日志断档或被清理）
            needsFullSync = true;
        } else {
            // 检查下一条日志的时间是否过旧
            Date firstLogTime = getFirstLogTimeAfterVersion(userId, fromVersion);
            Date tenDaysAgo = new Date(System.currentTimeMillis() - 10L * 24 * 60 * 60 * 1000);
            if (firstLogTime != null && firstLogTime.before(tenDaysAgo)) {
                needsFullSync = true;
            } else {
                // 日志没过旧，最后才检查条数，避免无条件执行耗时查询
                // 由于实施了 SQL Compaction，2000 条原始记录合并后压力很小
                if (getIncrementalLogCount(userId, fromVersion) > 2000) {
                    needsFullSync = true;
                }
            }
        }
        
        logger.info("同步决策: needsFullSync={}", needsFullSync);

        if (needsFullSync) {
            // 生成全量日志
            List<UserDbLogDto> logs = new ArrayList<>();

            // 1. 本人记录 (users)
            // 获取最新版本的 user 记录（user 变量在 1086 行已定义）
            if (user != null) {
                UserDto userDto = user.toDto();
                UserDbLogDto log = new UserDbLogDto(Util.uuid(), userId, userDbVersion, "INSERT", "user",
                        userDto.getId(), JsonUtils.toJson(userDto),
                        userDto.getCreateTime(),
                        userDto.getUpdateTime());
                logs.add(log);
            }

            // 2. 用户词典 (dict)
            List<DictDto> ownDictDtos = dictBo.getDictDtosOfUser(userId);
            for (DictDto dictDto : ownDictDtos) {
                UserDbLogDto log = new UserDbLogDto(Util.uuid(), userId, userDbVersion, "INSERT", "dict",
                        dictDto.getId(), JsonUtils.toJson(dictDto),
                        dictDto.getCreateTime(),
                        dictDto.getUpdateTime());
                logs.add(log);
            }

            // 2. 学习中单词 (learning_word)
            List<LearningWordDto> learningWords = learningWordBo.getLearningWordDtosOfUser(userId);
            for (LearningWordDto learningWord : learningWords) {
                UserDbLogDto log = new UserDbLogDto(Util.uuid(), userId, userDbVersion, "INSERT", "learning_word",
                        learningWord.getUserId() + "-" + learningWord.getWordId(), JsonUtils.toJson(learningWord),
                        learningWord.getCreateTime(),
                        learningWord.getUpdateTime());
                logs.add(log);
            }

            // 3. 用户选择的词书 (learning_dict)
            List<LearningDictDto> learningDicts = learningDictBo.getLearningDictDtosOfUser(userId);
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

            // 生成用户自定义词典的释义(meaning_item)全量日志
            for (DictDto dictDto : ownDictDtos) {
                List<MeaningItemDto> meaningItemDtos = meaningItemBo.getMeaningItemsOfDict(dictDto.getId());
                for (MeaningItemDto meaningItemDto : meaningItemDtos) {
                    UserDbLogDto log = new UserDbLogDto(
                            Util.uuid(),
                            userId,
                            userDbVersion,
                            "INSERT",
                            "meaning_item",
                            meaningItemDto.getId(),
                            JsonUtils.toJson(meaningItemDto),
                            meaningItemDto.getCreateTime(),
                            meaningItemDto.getUpdateTime());
                    logs.add(log);
                }
            }

            // mastered_word 全量日志已不再需要：已掌握单词现在作为 dict + dict_word 同步

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

            // 生成用户的记忆历史全量日志
            List<LearningLogDto> learningLogDtos = learningLogBo.getLearningLogDtosOfUser(userId);
            for (LearningLogDto dto : learningLogDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "learning_log",
                        dto.getId(),
                        JsonUtils.toJson(dto),
                        dto.getCreateTime(),
                        dto.getUpdateTime());
                logs.add(log);
            }

            // 生成用户每日学习统计全量日志
            List<UserStudyDailyStatDto> statsDtos = userStudyDailyStatBo.getStatsDtosOfUser(userId);
            SimpleDateFormat statsDateFormat = new SimpleDateFormat("yyyy-MM-dd");
            for (UserStudyDailyStatDto dto : statsDtos) {
                UserDbLogDto log = new UserDbLogDto(
                        Util.uuid(),
                        userId,
                        userDbVersion,
                        "INSERT",
                        "user_study_daily_stat",
                        userId + "|" + statsDateFormat.format(dto.getDate()),
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
            ordered.put("dict", counts.getOrDefault("dict", 0));
            ordered.put("learning_word", counts.getOrDefault("learning_word", 0));
            ordered.put("learning_dict", counts.getOrDefault("learning_dict", 0));
            ordered.put("user_study_step", counts.getOrDefault("user_study_step", 0));
            ordered.put("daka", counts.getOrDefault("daka", 0));
            ordered.put("user_oper", counts.getOrDefault("user_oper", 0));
            ordered.put("user_wrong_word", counts.getOrDefault("user_wrong_word", 0));
            ordered.put("dict_word", counts.getOrDefault("dict_word", 0));
            ordered.put("meaning_item", counts.getOrDefault("meaning_item", 0));
            ordered.put("user_cow_dung_log", counts.getOrDefault("user_cow_dung_log", 0));
            ordered.put("learning_log", counts.getOrDefault("learning_log", 0));
            ordered.put("user_study_daily_stats", counts.getOrDefault("user_study_daily_stats", 0));

            // 输出未在固定列表中的表名（如果有）
            Map<String, Integer> extra = new LinkedHashMap<>();
            for (Map.Entry<String, Integer> e : counts.entrySet()) {
                if (!ordered.containsKey(e.getKey())) {
                    extra.put(e.getKey(), e.getValue());
                }
            }
            if (!extra.isEmpty()) {
                logger.info("进行全量同步分类统计(其他明细): {}", extra);
            }
            logger.info("进行全量同步分类统计: {}", ordered);

            logger.info("进行全量同步, 共生成{}条同步日志, 服务端/客户端数据版本号为{}", logs.size(),
                    userDbVersion + "-" + fromVersion);

            return logs;
        } else { // 增量同步 (SQL 层面进行 Compaction 优化，防止 N+1 子查询导致的大数据量超时)
            String sql = "SELECT s.* FROM user_db_log s " +
                    "INNER JOIN ( " +
                    "  SELECT tbl_name, record_id, MAX(version) as last_v " +
                    "  FROM user_db_log " +
                    "  WHERE user_id = :userId AND version > :fromVersion " +
                    "  GROUP BY tbl_name, record_id " +
                    ") m ON s.user_id = :userId AND s.tbl_name = m.tbl_name AND s.record_id = m.record_id AND s.version = m.last_v " +
                    "ORDER BY s.version ASC";
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

            logger.info("进行增量同步, 共生成{}条同步日志, 服务端/客户端数据版本号为{}", logs.size(),
                    userDbVersion + "-" + fromVersion);
            return logs;
        }
    }

    /**
     * 处理单词释义同步
     */
    private void processMeaningItemSync(String userId, String recordJson, String operation) {
        if (null == operation) {
            String errorMsg = String.format("不支持的释义表操作: %s", operation);
            logger.error(errorMsg);
            throw new IllegalArgumentException(errorMsg);
        } else switch (operation) {
            case "UPDATE" -> {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = JsonUtils.makeObject(recordJson, Map.class);
                String dictId = (String) data.get("dictId");
                String wordId = (String) data.get("wordId");
                @SuppressWarnings("unchecked")
                List<Map<String, String>> meanings = (List<Map<String, String>>) data.get("meanings");
                meaningItemBo.updateMeanings(dictId, wordId, meanings, userId);
                logger.info("同步更新单词释义成功: dictId={}, wordId={}", dictId, wordId);
            }
            case "INSERT" ->                 {
                    MeaningItemDto meaningItemDto = JsonUtils.makeObject(recordJson, MeaningItemDto.class);
                    meaningItemBo.createMeaningItem(meaningItemDto);
                    logger.info("同步插入单词释义成功: id={}", meaningItemDto.getId());
                }
            case "DELETE" ->                 {
                    MeaningItemDto meaningItemDto = JsonUtils.makeObject(recordJson, MeaningItemDto.class);
                    meaningItemBo.deleteMeaningItem(meaningItemDto.getId());
                    logger.info("同步删除单词释义成功: id={}", meaningItemDto.getId());
                }
            default -> {
                String errorMsg = String.format("不支持的释义表操作: %s", operation);
                logger.error(errorMsg);
                throw new IllegalArgumentException(errorMsg);
            }
        }
    }

    private String getPremiumStatusString(User user) {
        if (user == null) return "未知";

        StringBuilder status = new StringBuilder();
        boolean isIosPremium = Boolean.TRUE.equals(user.getIsPremiumIos());
        boolean isOverrideEnabled = Boolean.TRUE.equals(user.getPremiumOverrideEnabled());

        if (isIosPremium) {
            status.append("iOS会员");
        }

        if (isOverrideEnabled) {
            if (status.length() > 0) status.append("+");
            if (user.getPremiumOverrideDuration() == null) {
                status.append("永久会员(手动)");
            } else {
                status.append("强制会员(手动)");
            }
        }

        return status.length() == 0 ? "免费" : status.toString();
    }
}
