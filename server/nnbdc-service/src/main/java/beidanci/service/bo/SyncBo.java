package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import org.hibernate.Session;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.DefaultTransactionDefinition;

import beidanci.api.model.BookMarkDto;
import beidanci.api.model.DakaDto;
import beidanci.api.model.DictDto;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.LearningDictDto;
import beidanci.api.model.LearningWordDto;
import beidanci.api.model.MasteredWordDto;
import beidanci.api.model.UserCowDungLogDto;
import beidanci.api.model.UserDbLogDto;
import beidanci.api.model.UserDto;
import beidanci.api.model.UserOperDto;
import beidanci.api.model.UserStudyStepDto;
import beidanci.api.model.WrongWordDto;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.exception.DbVersionNotMatchException;
import beidanci.service.exception.RawWordDataErrorException;
import beidanci.service.po.BookMark;
import beidanci.service.po.Daka;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningWord;
import beidanci.service.po.MasteredWord;
import beidanci.service.po.User;
import beidanci.service.po.UserCowDungLog;
import beidanci.service.po.UserDbLog;
import beidanci.service.po.UserOper;
import beidanci.service.po.UserStudyStep;
import beidanci.service.po.UserStudyStepId;
import beidanci.service.po.WrongWord;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.UserSorter;

@Service
public class SyncBo {
    private static final Logger logger = LoggerFactory.getLogger(SyncBo.class);

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
    private MasteredWordBo masteredWordBo;

    @Autowired
    private UserCowDungLogBo userCowDungLogBo;

    @Autowired
    private UserDbLogBo userDbLogBo;

    @Autowired
    private UserDbVersionDao userDbVersionDao;

    @Autowired
    private UserDbIssueBo userDbIssueBo;

    @Autowired
    private UserSorter userSorter;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private DictBo dictBo;

    @Autowired
    private PlatformTransactionManager transactionManager;

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
            Session session = userBo.getSession();

            // 执行数据同步
            for (UserDbLogDto log : logs) {
                String recordJson = null;
                try {
                    recordJson = log.getRecord();
                    processSyncLog(userId, log, recordJson);

                    // 检查record id是否超出长度限制
                    if (log.getRecordId().length() > 131) {
                        throw new IllegalArgumentException(String.format("record id(%s)超出长度限制(最多131), table(%s)", log.getRecordId(), log.getTable_()));
                    }

                    // 生成服务端数据库日志(用于同步到该用户的其他客户端)
                    UserDbLog userDbLog = new UserDbLog();
                    userDbLog.setUserId(userId);
                    userDbLog.setVersion(lastVersion + 1);
                    userDbLog.setCreateTime(new Date());
                    userDbLog.setUpdateTime(new Date());
                    userDbLog.setTable(log.getTable_());
                    userDbLog.setRecordId(log.getRecordId());
                    userDbLog.setOperate(log.getOperate());
                    userDbLog.setRecord(recordJson);
                    userDbLogBo.createEntity(userDbLog);
                } catch (Exception e) {
                    // 任何异常都会导致整个事务回滚
                    logger.error("同步数据失败，将回滚整个事务, 用户[{}], 表[{}], 记录[{}], 错误: {}",
                            userId, log.getTable_(), recordJson, e.getMessage());
                    logger.error("异常详情:", e);
                    throw new RuntimeException("同步数据失败: " + e.getMessage(), e);
                }
            }

            // 生词本顺序校验和后续处理
            validateAndFinalizeSync(userId, logs, lastVersion, session);

            transactionManager.commit(status);
            return lastVersion + 1;
        } catch (Throwable e) {
            try {
                // 检查事务状态，只有在事务仍然活跃时才回滚
                if (!status.isCompleted()) {
                    transactionManager.rollback(status);
                } else {
                    logger.warn("事务已经完成，跳过回滚操作");
                }
            } catch (Exception ex) {
                logger.error("回滚事务失败: {}", ex.getMessage(), ex);
            }
            if (e instanceof DbVersionNotMatchException)
                throw (DbVersionNotMatchException) e;
            if (e instanceof IllegalAccessException)
                throw (IllegalAccessException) e;
            if (e instanceof RawWordDataErrorException)
                throw (RawWordDataErrorException) e;
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
        Session session = userBo.getSession();
        
        // 先确保版本记录存在（对于新用户可能不存在）
        userDbVersionDao.ensureUserDbVersionExists(session, userId);
        
        // 使用带锁的查询方法，锁定该用户的版本号行
        final int lastVersion = userDbVersionDao.getUserDbVersionWithLock(session, userId);
        
        if (expectedServerDbVersion != lastVersion) {
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
        String tableName = log.getTable_().toLowerCase();
        String operation = log.getOperate().toUpperCase();

        switch (tableName) {
            case "learning_word":
                processLearningWordSync(userId, log, recordJson, operation);
                break;
            case "learning_dict":
                processLearningDictSync(userId, log, recordJson, operation);
                break;
            case "user":
                processUserSync(userId, log, recordJson, operation);
                break;
            case "dict":
                processDictSync(userId, log, recordJson, operation);
                break;
            case "book_mark":
                processBookMarkSync(userId, log, recordJson, operation);
                break;
            case "user_study_step":
                processUserStudyStepSync(userId, log, recordJson, operation);
                break;
            case "daka":
                processDakasSync(userId, log, recordJson, operation);
                break;
            case "user_oper":
                processUserOperSync(userId, log, recordJson, operation);
                break;
            case "user_wrong_word":
                processUserWrongWordSync(userId, log, recordJson, operation);
                break;
            case "dict_word":
                processDictWordSync(userId, log, recordJson, operation);
                break;
            case "mastered_word":
                processMasteredWordSync(userId, log, recordJson, operation);
                break;
            case "user_cow_dung_log":
                processUserCowDungLogSync(userId, log, recordJson, operation);
                break;
            default:
                logger.warn("不支持的表同步: {}", tableName);
                break;
        }
    }

    /**
     * 处理学习单词同步
     */
    private void processLearningWordSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            learningWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            LearningWordDto learningWordDto = JsonUtils.makeObject(recordJson, LearningWordDto.class);
            LearningWord learningWord = LearningWord.fromDto(learningWordDto);
            switch (operation) {
                case "INSERT":
                    // 检查记录是否已存在，避免主键冲突
                    LearningWord existing = learningWordBo.findById(learningWord.getId());
                    if (existing == null) {
                        learningWordBo.createEntity(learningWord);
                    } else {
                        logger.info("learning_word 已存在，忽略重复 INSERT: id={}", learningWord.getId());
                    }
                    break;
                case "UPDATE":
                    // 检查记录是否存在，不存在则创建
                    LearningWord existingForUpdate = learningWordBo.findById(learningWord.getId());
                    if (existingForUpdate == null) {
                        learningWordBo.createEntity(learningWord);
                    } else {
                        learningWordBo.updateEntity(learningWord);
                    }
                    break;
                case "DELETE":
                    learningWordBo.deleteEntity(learningWord);
                    break;
            }
        }
    }

    /**
     * 处理学习词典同步
     */
    private void processLearningDictSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            learningDictBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            LearningDictDto learningDictDto = JsonUtils.makeObject(recordJson, LearningDictDto.class);
            LearningDict learningDict = LearningDict.fromDto(learningDictDto, wordBo, dictBo, userBo);
            switch (operation) {
                case "INSERT":
                    // 检查记录是否已存在，避免主键冲突
                    LearningDict existing = learningDictBo.findById(learningDict.getId());
                    if (existing == null) {
                        learningDictBo.createEntity(learningDict);
                    } else {
                        logger.info("learning_dict 已存在，忽略重复 INSERT: userId={}, dictId={}",
                                userId, learningDictDto.getDictId());
                    }
                    break;
                case "UPDATE":
                    // 检查记录是否存在，不存在则创建
                    LearningDict existingForUpdate = learningDictBo.findById(learningDict.getId());
                    if (existingForUpdate == null) {
                        learningDictBo.createEntity(learningDict);
                    } else {
                        learningDictBo.updateEntity(learningDict);
                    }
                    break;
                case "DELETE":
                    learningDictBo.deleteEntity(learningDict);
                    break;
            }
        }
    }

    /**
     * 处理用户同步
     */
    private void processUserSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        if ("UPDATE".equals(operation)) {
            try {
                UserDto userDto = JsonUtils.makeObject(recordJson, UserDto.class);
                if (userBo.findById(userId) != null) {
                    User userFromClient = User.fromDto(userDto);
                    userBo.updateEntity(userFromClient);
                }
            } catch (IllegalAccessException | IllegalArgumentException e) {
                logger.error("同步用户数据失败：" + e.getMessage(), e);
            }
        }
        // 不支持INSERT和DELETE操作，用户记录应当已经存在
    }

    /**
     * 处理词书同步
     */
    private void processDictSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        try {
            DictDto dictDto = JsonUtils.makeObject(recordJson, DictDto.class);
            
            // 只允许用户同步自己的词书
            if (!userId.equals(dictDto.getOwnerId())) {
                logger.warn("用户{}尝试同步不属于自己的词书: dictId={}, ownerId={}", 
                    userId, dictDto.getId(), dictDto.getOwnerId());
                return;
            }
            
            if ("INSERT".equals(operation) || "UPDATE".equals(operation)) {
                Dict dict = dictBo.findById(dictDto.getId());
                User owner = userBo.findById(dictDto.getOwnerId());
                
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
                    dict.setCreateTime(dictDto.getCreateTime());
                    dict.setUpdateTime(dictDto.getUpdateTime());
                    
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
                    dict.setUpdateTime(dictDto.getUpdateTime());
                    
                    dictBo.updateEntity(dict);
                    logger.debug("同步更新词书成功: dictId={}, name={}, wordCount={}", 
                        dict.getId(), dict.getName(), dict.getWordCount());
                }
            }
            // 暂不支持DELETE操作，词书通常不会被删除
        } catch (Exception e) {
            logger.error("同步词书数据失败：" + e.getMessage(), e);
            throw e;
        }
    }

    /**
     * 处理书签同步
     */
    private void processBookMarkSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            bookMarkBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                BookMarkDto bookMarkDto = JsonUtils.makeObject(recordJson, BookMarkDto.class);
                if ("INSERT".equals(operation) || "UPDATE".equals(operation)) {
                    bookMarkBo.saveBookMark(bookMarkDto.getBookMarkName(),
                            bookMarkDto.getSpell(),
                            bookMarkDto.getPosition(),
                            bookMarkDto.getUserId());
                } else if ("DELETE".equals(operation)) {
                    BookMark bookMark = BookMark.fromDto(bookMarkDto);
                    bookMarkBo.deleteEntity(bookMark);
                }
            } catch (IllegalAccessException | IllegalArgumentException e) {
                logger.error("同步书签数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理用户学习步骤同步
     */
    private void processUserStudyStepSync(String userId, UserDbLogDto log, String recordJson, String operation)
            throws IllegalAccessException {
        if ("BATCH_DELETE".equals(operation)) {
            userStudyStepBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                UserStudyStepDto stepDto = JsonUtils.makeObject(recordJson, UserStudyStepDto.class);
                UserStudyStepId id = new UserStudyStepId(userId, stepDto.getStudyStep());
                UserStudyStep studyStep = new UserStudyStep(id);
                studyStep.setIndex(stepDto.getIndex());
                studyStep.setState(stepDto.getState());

                if (stepDto.getCreateTime() != null) {
                    studyStep.setCreateTime(stepDto.getCreateTime());
                }
                if (stepDto.getUpdateTime() != null) {
                    studyStep.setUpdateTime(stepDto.getUpdateTime());
                }

                switch (operation) {
                    case "INSERT":
                        // 检查记录是否已存在，避免主键冲突
                        UserStudyStep existing = userStudyStepBo.findById(id);
                        if (existing == null) {
                            userStudyStepBo.createEntity(studyStep);
                        } else {
                            logger.info("user_study_step 已存在，忽略重复 INSERT: userId={}, studyStep={}",
                                    userId, stepDto.getStudyStep());
                        }
                        break;
                    case "UPDATE":
                        // 检查记录是否存在，不存在则创建
                        UserStudyStep existingForUpdate = userStudyStepBo.findById(id);
                        if (existingForUpdate == null) {
                            userStudyStepBo.createEntity(studyStep);
                        } else {
                            userStudyStepBo.updateEntity(studyStep);
                        }
                        break;
                    case "DELETE":
                        userStudyStepBo.deleteEntity(studyStep);
                        break;
                }
            } catch (IllegalAccessException | IllegalArgumentException e) {
                logger.error("同步用户学习步骤数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理打卡同步
     */
    private void processDakasSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            dakaBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                DakaDto dakaDto = JsonUtils.makeObject(recordJson, DakaDto.class);
                Daka daka = dakaBo.fromDto(dakaDto);
                
                switch (operation) {
                    case "INSERT":
                        // 检查记录是否已存在，避免主键冲突
                        Daka existing = dakaBo.findById(daka.getId());
                        if (existing == null) {
                            dakaBo.createEntity(daka);
                        } else {
                            logger.info("daka 已存在，忽略重复 INSERT: id={}", daka.getId());
                        }
                        break;
                    case "UPDATE":
                        // 检查记录是否存在，不存在则创建
                        Daka existingForUpdate = dakaBo.findById(daka.getId());
                        if (existingForUpdate == null) {
                            dakaBo.createEntity(daka);
                        } else {
                            dakaBo.updateEntity(daka);
                        }
                        break;
                    case "DELETE":
                        dakaBo.deleteEntity(daka);
                        break;
                }
            } catch (Exception e) {
                logger.error("同步打卡数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理用户操作历史同步
     */
    private void processUserOperSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            userOperBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                UserOperDto operDto = JsonUtils.makeObject(recordJson, UserOperDto.class);
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
                    throw new IllegalArgumentException("不支持的操作：" + operation + "，用户操作历史记录不支持删除");
                }
            } catch (IllegalArgumentException e) {
                logger.error("同步用户操作历史数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理错词同步
     */
    private void processUserWrongWordSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            wrongWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                WrongWordDto wrongWordDto = JsonUtils.makeObject(recordJson, WrongWordDto.class);
                WrongWord wrongWord = WrongWord.fromDto(wrongWordDto);
                if ("INSERT".equals(operation)) {
                    wrongWordBo.createIfAbsent(wrongWord);
                } else if ("DELETE".equals(operation)) {
                    wrongWordBo.deleteEntity(wrongWord);
                }
            } catch (IllegalArgumentException | IllegalAccessException e) {
                logger.error("同步错词数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理生词本同步
     */
    private void processDictWordSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            dictWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                DictWordDto dictWordDto = JsonUtils.makeObject(recordJson, DictWordDto.class);
                DictWord dictWord = DictWord.fromDto(dictWordDto);
                DictWord existing = dictWordBo.findById(dictWord.getId());

                switch (operation) {
                    case "INSERT":
                        if (existing == null) {
                            dictWordBo.createEntity(dictWord);
                        } else {
                            logger.info("dict_word 已存在，忽略重复 INSERT");
                        }
                        break;
                    case "UPDATE":
                        if (existing == null) {
                            dictWordBo.createEntity(dictWord);
                        } else {
                            dictWordBo.updateEntity(dictWord);
                        }
                        break;
                    case "DELETE":
                        if (existing != null) {
                            deleteDictWordSafely(dictWord);
                        }
                        break;
                }
            } catch (IllegalArgumentException | IllegalAccessException e) {
                logger.error("同步生词数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 安全删除生词本记录
     */
    private void deleteDictWordSafely(DictWord dictWord) {
        try {
            userBo.getSession().evict(dictWord);
            DictWord toDelete = dictWordBo.findById(dictWord.getId());
            if (toDelete != null) {
                dictWordBo.deleteEntity(toDelete);
            }
        } catch (Exception deleteEx) {
            logger.warn("删除dict_word时出现异常，尝试使用原生SQL删除: {}", deleteEx.getMessage());
            try {
                String deleteSql = "DELETE FROM dict_word WHERE dictId = :dictId AND wordId = :wordId";
                javax.persistence.Query query = userBo.getSession().createNativeQuery(deleteSql);
                query.setParameter("dictId", dictWord.getId().getDictId());
                query.setParameter("wordId", dictWord.getId().getWordId());
                int deletedRows = query.executeUpdate();
                if (deletedRows > 0) {
                    logger.info("使用原生SQL成功删除dict_word: dictId={}, wordId={}",
                            dictWord.getId().getDictId(), dictWord.getId().getWordId());
                }
            } catch (Exception sqlEx) {
                logger.error("使用原生SQL删除dict_word也失败: {}", sqlEx.getMessage(), sqlEx);
                throw sqlEx;
            }
        }
    }

    /**
     * 处理已掌握单词同步
     */
    private void processMasteredWordSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            masteredWordBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                MasteredWordDto masteredWordDto = JsonUtils.makeObject(recordJson, MasteredWordDto.class);
                MasteredWord masteredWord = MasteredWord.fromDto(masteredWordDto);
                if ("INSERT".equals(operation)) {
                    // 检查记录是否已存在，避免主键冲突
                    MasteredWord existing = masteredWordBo.findById(masteredWord.getId());
                    if (existing == null) {
                        masteredWordBo.createEntity(masteredWord);
                    } else {
                        logger.info("mastered_word 已存在，忽略重复 INSERT: id={}", masteredWord.getId());
                    }
                } else if ("DELETE".equals(operation)) {
                    masteredWordBo.deleteEntity(masteredWord);
                }
                // 注意：mastered_word通常不支持UPDATE操作
            } catch (IllegalArgumentException e) {
                logger.error("同步已掌握单词数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 处理魔法泡泡日志同步
     */
    private void processUserCowDungLogSync(String userId, UserDbLogDto log, String recordJson, String operation) {
        if ("BATCH_DELETE".equals(operation)) {
            userCowDungLogBo.batchDeleteUserRecords(userId, recordJson);
        } else {
            try {
                UserCowDungLogDto cowDungLogDto = JsonUtils.makeObject(recordJson, UserCowDungLogDto.class);
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
                    }
                    // 注意：魔法泡泡日志通常只支持INSERT操作
                }
            } catch (IllegalArgumentException e) {
                logger.error("同步魔法泡泡日志数据失败：" + e.getMessage(), e);
            }
        }
    }

    /**
     * 验证和完成同步（使用 CAS 原子更新版本号）
     * 
     * 重要改进：使用 CAS (Compare-And-Swap) 来更新版本号，确保原子性
     */
    private void validateAndFinalizeSync(String userId, List<UserDbLogDto> logs, int lastVersion, Session session)
            throws IllegalAccessException, RawWordDataErrorException, DbVersionNotMatchException {
        // 生词本顺序校验
        try {
            String issue = dictWordBo.validateRawWordOrderOfUser(userId);
            if (issue != null) {
                userDbIssueBo.recordIssue(userId, "RAW_WORD_ORDER_INVALID", issue);
                throw new RawWordDataErrorException("RAW_WORD_ORDER_INVALID: " + issue);
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
        boolean updateSuccess = userDbVersionDao.updateUserDbVersionCAS(session, userId, lastVersion, newVersion);
        
        if (!updateSuccess) {
            // CAS 更新失败，说明版本号在同步过程中被其他事务修改了
            // 这种情况理论上不应该发生，因为我们在 validateUserAndVersion 中已经加了行锁
            // 但为了安全起见，还是要处理这种情况
            logger.error("使用 CAS 更新版本号失败，用户[{}]，期望版本[{}]，新版本[{}]", 
                    userId, lastVersion, newVersion);
            throw new DbVersionNotMatchException(String.format(
                    "更新数据库版本失败，期望版本[%d]，可能存在并发修改", lastVersion));
        }
        
        logger.info("用户[{}]数据库版本更新成功：{} -> {}", userId, lastVersion, newVersion);
    }

    /**
     * 如果需要，更新用户排名
     */
    private void updateUserRankingIfNeeded(String userId, List<UserDbLogDto> logs) {
        boolean needUpdateRanking = logs.stream()
                .anyMatch(log -> log.getTable_().equalsIgnoreCase("dakas") ||
                        log.getTable_().equalsIgnoreCase("user_game") ||
                        log.getTable_().equalsIgnoreCase("user"));

        if (needUpdateRanking) {
            try {
                User updatedUser = userBo.findById(userId);
                if (updatedUser != null) {
                    List<User> changedUsers = new ArrayList<>();
                    changedUsers.add(updatedUser);
                    userSorter.onUserChanged(changedUsers);
                    logger.info("用户[{}]数据同步后，排名已更新", userId);
                }
            } catch (Exception e) {
                logger.error("更新用户排名失败，将回滚整个事务：" + e.getMessage(), e);
                throw new RuntimeException("更新用户排名失败: " + e.getMessage(), e);
            }
        }
    }
}
