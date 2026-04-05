package beidanci.service.bo;

import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import beidanci.api.model.SystemHealthCheckResult;
import beidanci.api.model.SystemHealthFixResult;
import beidanci.api.model.SystemHealthIssue;
import beidanci.service.dao.UserDbVersionDao;
import beidanci.service.po.Dict;
import beidanci.service.po.User;
import beidanci.util.Constants;

/**
 * 系统健康检查业务逻辑
 */
@Service
public class SystemHealthCheckBo {

    @Autowired
    private DictBo dictBo;
    
    
    @Autowired
    private UserDbVersionDao userDbVersionDao;
    
    @Autowired
    private MeaningItemBo meaningItemBo;
    
    @Autowired
    private SentenceBo sentenceBo;
    
    @Autowired
    private UserBo userBo;
    
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private UserDbSyncBo userDbSyncBo;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private DictWordBo dictWordBo;

    @Autowired
    private WordImageBo wordImageBo;

    @Autowired
    private beidanci.service.util.SysParamUtil sysParamUtil;


    /**
     * 检查系统词典完整性
     */
    public SystemHealthCheckResult checkSystemDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有系统词典（ownerId = 15118）
            List<String> systemDictIds = dictBo.getSystemDictIds();
            
            for (String dictId : systemDictIds) {
                // 检查词典单词序号连续性
                checkDictWordSequence(dictId, issues);
                
                // 检查词典单词数量一致性
                checkDictWordCount(dictId, issues);
            }
            
        } catch (Exception e) {
            errors.add("检查系统词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查用户词典完整性
     */
    public SystemHealthCheckResult checkUserDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 使用原生SQL一次性获取所有用户词典信息，参考check_db.py的高效查询
            String sql = "SELECT d.id, d.name, d.owner_id, d.word_count, d.base_dict_id, d.create_time " +
                        "FROM dict d " +
                        "WHERE d.visible = 1 AND d.is_ready = 1 AND d.owner_id != :sysUserId " +
                        "ORDER BY d.create_time DESC";
            
            MapSqlParameterSource params = new MapSqlParameterSource("sysUserId", Constants.SYS_USER_SYS_ID);
            List<Object[]> dicts = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("name"),
                    rs.getString("owner_id"),
                    rs.getObject("wordCount", Integer.class),
                    rs.getString("base_dict_id")
                }
            );
            
            for (Object[] dict : dicts) {
                String dictId = (String) dict[0];
                String dictName = (String) dict[1];
                String ownerId = (String) dict[2];
                Integer wordCount = (Integer) dict[3];
                String baseDictId = (String) dict[4];
                
                // 检查词典单词序号连续性和数量一致性
                checkDictWordSequenceAndCount(dictId, dictName, ownerId, wordCount, baseDictId, issues);
            }
            
        } catch (DataAccessException e) {
            errors.add("检查用户词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    

    /**
     * 检查数据库版本一致性
     */
    public SystemHealthCheckResult checkDbVersionConsistency() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有用户的当前数据库版本
            List<Object[]> userVersions = userDbVersionDao.getAllUserVersions();
            
            for (Object[] userVersion : userVersions) {
                String userId = (String) userVersion[0];
                Integer currentVersion = (Integer) userVersion[1];
                
                // 检查是否有版本号大于当前版本的日志
                int invalidLogCount = userDbVersionDao.countInvalidLogs(userId, currentVersion);
                
                if (invalidLogCount > 0) {
                    issues.add(new SystemHealthIssue(
                        "版本号异常",
                        String.format("用户 %s 有 %d 条版本号异常的日志", userId, invalidLogCount),
                        "db_version"
                    ));
                }
            }
            
        } catch (Exception e) {
            errors.add("检查数据库版本一致性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查所有用户的学习步骤完整性
     * 使用单个 SQL 查询直接找出缺少学习步骤的用户，性能最优
     */
    public SystemHealthCheckResult checkUserStudySteps() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 使用一个 SQL 查询直接找出缺少 En2Ch 或 Ch2En 的用户
            String sql = "SELECT u.id, u.user_name, 'En2Ch' as missing_step " +
                        "FROM \"user\" u " +
                        "LEFT JOIN user_study_step uss ON u.id = uss.user_id AND uss.study_step = 'En2Ch' " +
                        "WHERE uss.user_id IS NULL " +
                        "UNION ALL " +
                        "SELECT u.id, u.user_name, 'Ch2En' as missing_step " +
                        "FROM \"user\" u " +
                        "LEFT JOIN user_study_step uss ON u.id = uss.user_id AND uss.study_step = 'Ch2En' " +
                        "WHERE uss.user_id IS NULL";
            
            List<Object[]> missingSteps = namedParameterJdbcTemplate.query(sql, 
                new MapSqlParameterSource(), 
                (rs, rowNum) -> new Object[]{
                    rs.getString("id"),
                    rs.getString("user_name"),
                    rs.getString("missing_step")
                }
            );
            
            // 将查询结果转换为问题列表
            for (Object[] record : missingSteps) {
                String userId = (String) record[0];
                String userName = (String) record[1];
                String missingStep = (String) record[2];
                
                issues.add(new SystemHealthIssue(
                    "学习步骤缺失",
                    String.format("用户 %s (%s) 缺少学习步骤：%s", userName, userId, missingStep),
                    "user_study_steps"
                ));
            }
            
        } catch (DataAccessException e) {
            errors.add("检查用户学习步骤时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查通用词典完整性
     */
    public SystemHealthCheckResult checkCommonDictIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 检查通用词典（id='0'）的完整性
            String commonDictId = "0";
            
            // 检查是否有释义项
            List<String> wordsWithoutMeanings = meaningItemBo.findWordsWithoutMeanings(commonDictId);
            for (String wordId : wordsWithoutMeanings) {
                issues.add(new SystemHealthIssue(
                    "通用词典不完整",
                    "单词 " + wordId + " 缺少释义项",
                    "common_dict_integrity"
                ));
            }
            
            // 检查释义项是否有例句
            List<String> meaningsWithoutSentences = sentenceBo.findMeaningsWithoutSentences(commonDictId);
            for (String meaningId : meaningsWithoutSentences) {
                issues.add(new SystemHealthIssue(
                    "通用词典不完整",
                    "释义项 " + meaningId + " 缺少例句",
                    "common_dict_integrity"
                ));
            }
            
        } catch (Exception e) {
            errors.add("检查通用词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查系统词典是否缺失通用词库（0库）物理托底数据
     */
    public SystemHealthCheckResult checkSystemDictMissingFallback() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            String sql = "SELECT COUNT(DISTINCT word_id) FROM dict_word WHERE word_id NOT IN (SELECT word_id FROM dict_word WHERE dict_id = '0')";
            Integer missingCount = namedParameterJdbcTemplate.queryForObject(sql, new MapSqlParameterSource(), Integer.class);
            if (missingCount != null && missingCount > 0) {
                issues.add(new SystemHealthIssue(
                    "底层通用词库缺失托底数据",
                    String.format("管理后台查出有 %d 个在用单词物理脱离了基础的0库记录，这会影响新下发的数据完整性，请立即修复。", missingCount),
                    "sys_dict_missing_fallback"
                ));
            }
        } catch (Exception e) {
            errors.add("检查底层托底完整性出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查用户是否缺失生词本或已掌握词书
     */
    public SystemHealthCheckResult checkMissingUserDicts() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 使用一条 SQL 查询同时找出缺少"生词本"或"已掌握"词书的用户
            String sql = "SELECT u.id, u.user_name, u.nick_name, '生词本' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '生词本' " +
                        "WHERE d.id IS NULL " +
                        "UNION ALL " +
                        "SELECT u.id, u.user_name, u.nick_name, '已掌握' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '已掌握' " +
                        "WHERE d.id IS NULL " +
                        "ORDER BY missing_dict, id";
            
            List<Object[]> missingDicts = namedParameterJdbcTemplate.query(sql, 
                new MapSqlParameterSource(), 
                (rs, rowNum) -> new Object[]{
                    rs.getString("id"),
                    rs.getString("user_name"),
                    rs.getString("nick_name"),
                    rs.getString("missing_dict")
                }
            );
            
            // 将查询结果转换为问题列表
            for (Object[] record : missingDicts) {
                String userId = (String) record[0];
                String userName = (String) record[1];
                String nickName = (String) record[2];
                String missingDict = (String) record[3];
                
                issues.add(new SystemHealthIssue(
                    "用户缺失词书",
                    String.format("用户 %s (%s, ID: %s) 缺少词书：%s", 
                                nickName != null ? nickName : userName, userName, userId, missingDict),
                    "missing_user_dict"
                ));
            }
            
        } catch (DataAccessException e) {
            errors.add("检查用户词书缺失时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查单词配图完整性 (检查配图文件是否存在)
     */
    public SystemHealthCheckResult checkWordImageIntegrity() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 获取所有配图记录
            String sql = "SELECT id, image_file FROM word_image";
            List<Object[]> images = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("image_file")
                }
            );
            
            String baseDir = sysParamUtil.getImageBaseDir() + "/word/";
            int missingCount = 0;
            
            for (Object[] image : images) {
                String fileName = (String) image[1];
                
                java.io.File file = new java.io.File(baseDir + fileName);
                if (!file.exists()) {
                    missingCount++;
                }
            }
            
            if (missingCount > 0) {
                issues.add(new SystemHealthIssue(
                    "配图文件缺失",
                    String.format("发现 %d 条配图记录对应的物理文件不存在", missingCount),
                    "word_image_integrity"
                ));
            }
            
        } catch (Exception e) {
            errors.add("检查单词配图完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 自动修复系统问题
     */
    public SystemHealthFixResult autoFixSystemIssues(List<String> issueTypes) {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        int fixedCount = 0;
        
        try {
            for (String issueType : issueTypes) {
                switch (issueType) {
                    case "system_dict_integrity" -> fixedCount += fixSystemDictIntegrity(fixed);
                    case "user_dict_integrity" -> fixedCount += fixUserDictIntegrity(fixed);
    
                    case "db_version" -> fixedCount += fixDbVersionConsistency(fixed);
                    case "common_dict_integrity" -> fixedCount += fixCommonDictIntegrity(fixed);
                    case "sys_dict_missing_fallback" -> fixedCount += fixSystemDictMissingFallback(fixed);
                    case "user_study_steps" -> fixedCount += fixUserStudySteps(fixed);
                    case "missing_raw_word_dict", "missing_user_dict" -> fixedCount += fixMissingUserDicts(fixed);
                    case "word_image_integrity" -> fixedCount += fixWordImageIntegrity(fixed);
                    default -> errors.add("未知的问题类型: " + issueType);
                }
                // fixedCount += fixLearningProgress(fixed);
                            }
        } catch (Exception e) {
            errors.add("自动修复过程中出错: " + e.getMessage());
        }
        
        return new SystemHealthFixResult(fixedCount, errors, fixed);
    }

    // 私有辅助方法

    /**
     * 修复单词缺失 0 库物理托底的问题
     */
    private int fixSystemDictMissingFallback(List<String> fixed) {
        int fixedCount = 0;
        try {
            String sqlWords1 = "SELECT DISTINCT word_id FROM dict_word WHERE word_id NOT IN (SELECT word_id FROM dict_word WHERE dict_id = '0')";
            List<String> missingPhysical = namedParameterJdbcTemplate.query(sqlWords1, new MapSqlParameterSource(), (rs, rowNum) -> rs.getString("word_id"));
            
            if (!missingPhysical.isEmpty()) {
                Dict commonDict = dictBo.findById(Constants.COMMON_DICT_ID);
                int maxSeq = dictWordBo.getMaxSeqNo(commonDict);
                
                for (String wordId : missingPhysical) {
                    try {
                        maxSeq++;
                        beidanci.service.po.DictWord dw0 = new beidanci.service.po.DictWord();
                        dw0.setId(new beidanci.service.po.DictWordId(Constants.COMMON_DICT_ID, wordId));
                        dw0.setDict(commonDict);
                        beidanci.service.po.Word word = new beidanci.service.po.Word();
                        word.setId(wordId);
                        dw0.setWord(word);
                        dw0.setSeq(maxSeq);
                        dw0.setCreateTime(new java.util.Date());
                        dictWordBo.createEntity(dw0);
                        
                        beidanci.api.model.DictWordDto dwDto = new beidanci.api.model.DictWordDto();
                        dwDto.setDictId(Constants.COMMON_DICT_ID);
                        dwDto.setWordId(wordId);
                        dwDto.setSeq(dw0.getSeq());
                        dwDto.setCreateTime(dw0.getCreateTime());
                        sysDbSyncBo.logOperation("INSERT", "dict_word", Constants.COMMON_DICT_ID + "_" + wordId, beidanci.service.util.JsonUtils.toJson(dwDto));
                        fixedCount++;
                    } catch (Exception ignore) {}
                }
                if (fixedCount > 0) {
                    commonDict.setWordCount(maxSeq);
                    dictBo.updateEntity(commonDict);
                    beidanci.api.model.DictDto dictDto = new beidanci.api.model.DictDto();
                    org.springframework.beans.BeanUtils.copyProperties(commonDict, dictDto);
                    sysDbSyncBo.logOperation("UPDATE", "dict", Constants.COMMON_DICT_ID, beidanci.service.util.JsonUtils.toJson(dictDto));
                }
                fixed.add(String.format("成功为 %d 个物理脱离单词补充并广播到 0 库。", fixedCount));
            }
        } catch (Exception e) {
            fixed.add("修复底层物理托底数据失败: " + e.getMessage());
        }
        return fixedCount;
    }

    /**
     * 为客户端提供点对点的托底防空洞救转数据，直接打包返回指定单词的全套系统资源
     */
    public java.util.Map<String, Object> getFallbackWordsData(List<String> wordIds) {
        List<beidanci.api.model.DictWordDto> dictWords = new ArrayList<>();
        List<beidanci.api.model.MeaningItemDto> meaningItems = new ArrayList<>();
        List<beidanci.api.model.SentenceDto> sentences = new ArrayList<>();
        
        if (wordIds != null) {
            for (String wordId : wordIds) {
                beidanci.service.po.DictWord dw = dictWordBo.findById(new beidanci.service.po.DictWordId(Constants.COMMON_DICT_ID, wordId));
                if (dw != null) {
                    beidanci.api.model.DictWordDto dwDto = new beidanci.api.model.DictWordDto();
                    dwDto.setDictId(Constants.COMMON_DICT_ID);
                    dwDto.setWordId(wordId);
                    dwDto.setSeq(dw.getSeq());
                    dwDto.setCreateTime(dw.getCreateTime());
                    dictWords.add(dwDto);
                }
                
                List<beidanci.api.model.MeaningItemDto> mDtos = meaningItemBo.findMeaningsByWordAndDict(wordId, Constants.COMMON_DICT_ID);
                if (mDtos != null) {
                    meaningItems.addAll(mDtos);
                    for (beidanci.api.model.MeaningItemDto mDto : mDtos) {
                        List<beidanci.service.po.Sentence> sList = sentenceBo.findByMeaningItem(mDto.getId());
                        if (sList != null) {
                            for (beidanci.service.po.Sentence s : sList) {
                                sentences.add(sentenceBo.toDto(s));
                            }
                        }
                    }
                }
            }
        }
        
        java.util.Map<String, Object> data = new java.util.HashMap<>();
        data.put("dictWords", dictWords);
        data.put("meaningItems", meaningItems);
        data.put("sentences", sentences);
        return data;
    }

    /**
     * 修复单词配图完整性 (删除对应的 db 记录并记录日志)
     */
    private int fixWordImageIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            // 这里为了安全，先查出所有记录，再逐个确认文件缺失
            String sql = "SELECT id, image_file FROM word_image";
            List<Object[]> images = namedParameterJdbcTemplate.query(sql, new MapSqlParameterSource(), (rs, rowNum) -> 
                new Object[]{
                    rs.getString("id"),
                    rs.getString("image_file")
                }
            );
            
            String baseDir = sysParamUtil.getImageBaseDir() + "/word/";
            
            for (Object[] image : images) {
                String id = (String) image[0];
                String fileName = (String) image[1];
                
                java.io.File file = new java.io.File(baseDir + fileName);
                if (!file.exists()) {
                    // 文件确实不存在
                    try {
                        // 使用 wordImageBo 的删除逻辑，它会记录 sys_db_log 并清理事件记录
                        // 管理员身份删除 (sys_user_id)
                        String sysUserId = userBo.getSysUser_sys(false).getId();
                        User sysUser = userBo.findById(sysUserId);
                        wordImageBo.deleteWordImage(id, sysUser, false);
                        fixedCount++;
                    } catch (Exception e) {
                        fixed.add("修复记录 [" + id + "] 失败: " + e.getMessage());
                    }
                }
            }
            
            if (fixedCount > 0) {
                fixed.add(String.format("成功清理了 %d 条缺失物理文件的配图记录，并已生成同步日志。", fixedCount));
            }
        } catch (Exception e) {
            fixed.add("修复单词配图完整性时出错: " + e.getMessage());
        }
        return fixedCount;
    }

    /**
     * 检查词典单词序号连续性和数量一致性（参考check_db.py的高效实现）
     */
    private void checkDictWordSequenceAndCount(String dictId, String dictName, String ownerId, Integer expectedWordCount, String baseDictId, List<SystemHealthIssue> issues) {
        if (baseDictId != null && !baseDictId.trim().isEmpty()) {
            return; // 衍生版（乱序版）词书本质上是一个共享源词库实体的空壳，不应该检查 dict_word
        }
        try {
            // 使用原生SQL一次性获取词典中的所有单词，按seq排序
            String sql = "SELECT dw.word_id, dw.seq, w.spell " +
                        "FROM dict_word dw " +
                        "JOIN word w ON dw.word_id = w.id " +
                        "WHERE dw.dict_id = :dictId " +
                        "ORDER BY dw.seq ASC";
            
            MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
            List<Object[]> dictWords = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
                new Object[]{
                    rs.getString("word_id"),
                    rs.getObject("seq", Integer.class),
                    rs.getString("spell")
                }
            );
            
            // 检查空词书
            if (dictWords.isEmpty()) {
                // 系统用户的生词本和已掌握词书（核心词书）允许为空
                boolean isSystemUserCoreDict = Constants.SYS_USER_SYS_ID.equals(ownerId) && 
                        ("生词本".equals(dictName) || "已掌握".equals(dictName));
                
                if (Constants.SYS_USER_SYS_ID.equals(ownerId) && !isSystemUserCoreDict) {
                    // 其他系统词书如果为空，是异常情况
                    issues.add(new SystemHealthIssue(
                        "系统词书为空",
                        String.format("系统词书 %s 为空，需要删除", dictName),
                        "empty_system_dict"
                    ));
                } else if (!isSystemUserCoreDict) {
                    // 如果词书为空但dict表记录的wordCount不为0，这也是个问题
                    if (expectedWordCount != null && expectedWordCount != 0) {
                        issues.add(new SystemHealthIssue(
                            "单词数量不匹配",
                            String.format("词典 %s 为空，但dict表记录wordCount=%d", dictName, expectedWordCount),
                            "word_count_mismatch"
                        ));
                    }
                }
                // 系统用户的核心词书允许为空，直接返回，不报告问题
                return;
            }
            
            int actualWordCount = dictWords.size();
            
            // 检查单词数量是否和dict表一致
            if (expectedWordCount != null && actualWordCount != expectedWordCount) {
                issues.add(new SystemHealthIssue(
                    "单词数量不匹配",
                    String.format("词典 %s 记录数量: %d, 实际数量: %d", dictName, expectedWordCount, actualWordCount),
                    "dict_word_count"
                ));
            }
            
            // 检查序号是否从1开始
            Integer firstSeq = (Integer) dictWords.get(0)[1];
            if (firstSeq != 1) {
                String firstWord = (String) dictWords.get(0)[2];
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 第一个单词 '%s' 序号不是1，实际序号: %d", dictName, firstWord, firstSeq),
                    "dict_word_sequence"
                ));
            }
            
            // 检查序号是否连续
            for (int i = 0; i < dictWords.size(); i++) {
                Integer actualSeq = (Integer) dictWords.get(i)[1];
                Integer expectedSeq = i + 1;
                if (!actualSeq.equals(expectedSeq)) {
                    String wordSpell = (String) dictWords.get(i)[2];
                    issues.add(new SystemHealthIssue(
                        "序号不连续",
                        String.format("词典 %s 位置%d断开，期望序号: %d, 实际序号: %d, 单词: '%s'", 
                            dictName, expectedSeq, expectedSeq, actualSeq, wordSpell),
                        "dict_word_sequence"
                    ));
                }
            }
            
            // 检查最大序号是否等于总单词数
            Integer maxSeq = (Integer) dictWords.get(dictWords.size() - 1)[1];
            if (!maxSeq.equals(actualWordCount)) {
                String lastWord = (String) dictWords.get(dictWords.size() - 1)[2];
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 最大序号不等于总单词数，最大序号: %d, 总单词数: %d, 单词: '%s'", 
                        dictName, maxSeq, actualWordCount, lastWord),
                    "dict_word_sequence"
                ));
            }
            
        } catch (DataAccessException e) {
            issues.add(new SystemHealthIssue(
                "检查序号连续性失败",
                String.format("检查词典 %s 序号连续性时出错: %s", dictName, e.getMessage()),
                "dict_word_sequence"
            ));
        }
    }

    private void checkDictWordSequence(String dictId, List<SystemHealthIssue> issues) {
        try {
            List<Object[]> dictWords = dictBo.checkDictWordSequence(dictId);
            
            // 获取词典信息
            Dict dict = dictBo.findById(dictId, false);
            if (dict == null) {
                issues.add(new SystemHealthIssue(
                    "词典不存在",
                    String.format("词典 %s 不存在", dictId),
                    "dict_word_sequence"
                ));
                return;
            }
            
            if (dict.getBaseDictId() != null && !dict.getBaseDictId().trim().isEmpty()) {
                return; // 衍生版直接跳过实体检查
            }
            
            // 检查空词书
            if (dictWords.isEmpty()) {
                // 系统用户的生词本和已掌握词书（核心系统词书）允许为空
                boolean isSystemUserCoreDict = Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId()) 
                        && ("生词本".equals(dict.getName()) || "已掌握".equals(dict.getName()));
                
                if (Constants.SYS_USER_SYS_ID.equals(dict.getOwner().getId()) && !isSystemUserCoreDict) {
                    // 其他系统词书如果为空，是异常情况
                    issues.add(new SystemHealthIssue(
                        "系统词书为空",
                        String.format("系统词书 %s 为空，需要删除", dict.getName()),
                        "empty_system_dict"
                    ));
                } else if (!isSystemUserCoreDict) {
                    // 如果词书为空但dict表记录的wordCount不为0，这也是个问题
                    if (dict.getWordCount() != 0) {
                        issues.add(new SystemHealthIssue(
                            "单词数量不匹配",
                            String.format("词书 %s 为空，但dict表记录wordCount=%d", dict.getName(), dict.getWordCount()),
                            "word_count_mismatch"
                        ));
                    }
                }
                // 系统用户的核心系统词书允许为空，直接返回，不报告问题
                return;
            }
            
            // 检查序号是否从1开始
            Integer firstSeq = (Integer) dictWords.get(0)[1];
            if (firstSeq != 1) {
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 第一个单词序号不是1，实际是%d", dict.getName(), firstSeq),
                    "dict_word_sequence"
                ));
                return;
            }
            
            // 检查序号是否连续
            for (int i = 0; i < dictWords.size(); i++) {
                Integer expectedSeq = i + 1;
                Integer actualSeq = (Integer) dictWords.get(i)[1];
                if (!expectedSeq.equals(actualSeq)) {
                    String wordId = (String) dictWords.get(i)[0];
                    String spell = (String) dictWords.get(i)[2];
                    issues.add(new SystemHealthIssue(
                        "序号不连续",
                        String.format("词典 %s 中单词 %s(%s) 序号不正确，期望%d，实际%d", 
                                    dict.getName(), wordId, spell, expectedSeq, actualSeq),
                        "dict_word_sequence"
                    ));
                    return;
                }
            }
            
            // 检查最大序号是否等于总单词数
            Integer lastSeq = (Integer) dictWords.get(dictWords.size() - 1)[1];
            if (!lastSeq.equals(dictWords.size())) {
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 最大序号(%d)不等于总单词数(%d)", 
                                dict.getName(), lastSeq, dictWords.size()),
                    "dict_word_sequence"
                ));
            }
        } catch (Exception e) {
            issues.add(new SystemHealthIssue(
                "检查序号连续性失败",
                String.format("检查词典 %s 序号连续性时出错: %s", dictId, e.getMessage()),
                "dict_word_sequence"
            ));
        }
    }

    private void checkDictWordCount(String dictId, List<SystemHealthIssue> issues) {
        try {
            Long actualCount = dictBo.getDictWordCount(dictId);
            Integer recordedCount = dictBo.getDictRecordedWordCount(dictId);
            
            // 获取词典信息
            Dict dict = dictBo.findById(dictId, false);
            if (dict == null) {
                issues.add(new SystemHealthIssue(
                    "词典不存在",
                    String.format("词典 %s 不存在", dictId),
                    "dict_word_count"
                ));
                return;
            }
            
            if (dict.getBaseDictId() != null && !dict.getBaseDictId().trim().isEmpty()) {
                return; // 衍生版直接跳过实体数量检查
            }
            
            if (!actualCount.equals(recordedCount.longValue())) {
                issues.add(new SystemHealthIssue(
                    "单词数量不匹配",
                    String.format("词典 %s 记录数量: %d, 实际数量: %d", 
                                dict.getName(), recordedCount, actualCount),
                    "dict_word_count"
                ));
            }
        } catch (Exception e) {
            issues.add(new SystemHealthIssue(
                "检查单词数量失败",
                String.format("检查词典 %s 单词数量时出错: %s", dictId, e.getMessage()),
                "dict_word_count"
            ));
        }
    }

    private int fixSystemDictIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<String> systemDictIds = dictBo.getSystemDictIds();
            for (String dictId : systemDictIds) {
                Dict dict = dictBo.findById(dictId, false);
                if (dict == null) continue;
                
                // 检查是否为空词书
                Long actualCount = dictBo.getDictWordCount(dictId);
                if (actualCount == 0) {
                    // 系统核心词书（生词本、已掌握）即使为空也不应删除
                    boolean isSystemUserCoreDict = "生词本".equals(dict.getName()) || "已掌握".equals(dict.getName());
                    if (!isSystemUserCoreDict) {
                        // 使用安全删除方法删除空的系统词书
                        dictBo.deleteDictSafely(dictId);
                        fixed.add("删除空的系统词书: " + dict.getName());
                        fixedCount++;
                    }
                } else {
                    // 修复序号
                    dictBo.fixDictWordSequence(dictId);
                    
                    // 修复数量
                    dictBo.updateDictWordCount(dictId, actualCount.intValue());
                    
                    fixed.add("修复系统词典 " + dict.getName() + " 的完整性问题");
                    fixedCount++;
                }
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

    private int fixUserDictIntegrity(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<String> userDictIds = dictBo.getUserDictIds();
            for (String dictId : userDictIds) {
                // 修复序号
                dictBo.fixDictWordSequence(dictId);
                
                // 修复数量
                Long actualCount = dictBo.getDictWordCount(dictId);
                dictBo.updateDictWordCount(dictId, actualCount.intValue());
                
                fixed.add("修复用户词典 " + dictId + " 的完整性问题");
                fixedCount++;
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }


    private int fixDbVersionConsistency(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<Object[]> userVersions = userDbVersionDao.getAllUserVersions();
            for (Object[] userVersion : userVersions) {
                String userId = (String) userVersion[0];
                Integer currentVersion = (Integer) userVersion[1];
                
                int invalidLogCount = userDbVersionDao.countInvalidLogs(userId, currentVersion);
                if (invalidLogCount > 0) {
                    userDbVersionDao.deleteInvalidLogs(userId, currentVersion);
                    fixed.add(String.format("删除用户 %s 的 %d 条异常日志", userId, invalidLogCount));
                    fixedCount++;
                }
            }
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

    private int fixCommonDictIntegrity(List<String> fixed) {
        String commonDictId = "0";
        int totalFixed = 0;

        // 1. 修复缺失的释义：从其他词库拷贝一份作为 0 库托底
        List<String> wordsWithoutMeanings = meaningItemBo.findWordsWithoutMeanings(commonDictId);
        if (wordsWithoutMeanings != null && !wordsWithoutMeanings.isEmpty()) {
            List<beidanci.api.model.MeaningItemDto> candidates = meaningItemBo.getOneMeaningPerWordFromAnyDict(wordsWithoutMeanings);
            int fixedMeaningCount = 0;
            for (beidanci.api.model.MeaningItemDto mDto : candidates) {
                try {
                    // 拷贝并修改为 0 库属性，生成新 ID 以确保主键不冲突 (源 ID 可能是共享的但 0 库需要物理实体)
                    String newId = beidanci.service.util.Util.uuid();
                    mDto.setId(newId);
                    mDto.setDictId(commonDictId);
                    mDto.setOwnerId(beidanci.util.Constants.SYS_USER_SYS_ID);
                    mDto.setCreateTime(new java.util.Date());
                    mDto.setUpdateTime(new java.util.Date());
                    
                    meaningItemBo.createMeaningItem(mDto);
                    sysDbSyncBo.logOperation("INSERT", "meaning_item", newId, beidanci.service.util.JsonUtils.toJson(mDto));
                    fixedMeaningCount++;
                } catch (Exception ignore) {}
            }
            if (fixedMeaningCount > 0) {
                fixed.add(String.format("成功为 %d 个单词补全了通用词典 0 库释义（从其他词典拷贝）。", fixedMeaningCount));
                totalFixed += fixedMeaningCount;
            }
        }

        // 2. 修复缺失的例句：AI 补齐逻辑
        List<String> meaningsWithoutSentences = sentenceBo.findMeaningsWithoutSentences(commonDictId);
        if (meaningsWithoutSentences == null || meaningsWithoutSentences.isEmpty()) {
            return totalFixed;
        }

        new Thread(() -> {
            try {
                org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class);
                logger.info("开始后台修复通用词典的 {} 个缺失例句的释义项...", meaningsWithoutSentences.size());
                
                String systemPrompt = "你是一个专业的外教，任务是专门给英语单词造例句。给定单词、词性和释义，请生成一条原生地道的英语例句及对应的中文翻译。严格只返回 JSON 对象，格式为：{\"sentenceEn\": \"英文例句\", \"sentenceCn\": \"中文翻译\"}。不要包含 markdown 或其他字符！";

                for (String meaningId : meaningsWithoutSentences) {
                    try {
                        beidanci.service.po.MeaningItem mi = meaningItemBo.findById(meaningId);
                        if (mi == null) continue;
                        
                        beidanci.service.po.Word stubWord = mi.getWord();
                        if (stubWord == null || stubWord.getId() == null) continue;
                        
                        beidanci.service.po.Word word = wordBo.findById(stubWord.getId());
                        if (word == null || word.getSpell() == null) continue;
                        
                        String spell = word.getSpell();
                        String promptText = "单词：[" + spell + "]\n要求：请造一个能准确反映词性[" + (mi.getCiXing() != null ? mi.getCiXing() : "未知") + "] 和释义[" + mi.getMeaning() + "]的例句。只返回JSON。";
                        
                        String jsonStr = aiBo.generateText(systemPrompt, promptText);
                        
                        if (jsonStr != null) {
                            int firstBrace = jsonStr.indexOf('{');
                            int lastBrace = jsonStr.lastIndexOf('}');
                            if (firstBrace >= 0 && lastBrace >= firstBrace) {
                                jsonStr = jsonStr.substring(firstBrace, lastBrace + 1);
                                java.util.Map<String, Object> map = beidanci.service.util.JsonUtils.parseMap(jsonStr);
                                if (map != null && map.containsKey("sentenceEn")) {
                                    String sentenceEn = (String) map.get("sentenceEn");
                                    String sentenceCn = (String) map.get("sentenceCn");
                                    
                                    beidanci.service.po.Sentence sentence = new beidanci.service.po.Sentence();
                                    sentence.setEnglish(sentenceEn);
                                    sentence.setChinese(sentenceCn);
                                    sentence.setWordMeaning(mi.getMeaning());
                                    sentence.setPartOfSpeech(mi.getCiXing());
                                    sentence.setMeaningItem(mi);
                                    sentence.setNeedTts(true);
                                    sentence.setTheType("waitting_tts");
                                    sentence.setEnglishDigest(beidanci.service.util.Util.makeSentenceDigest(sentenceEn));
                                    
                                    beidanci.service.po.User owner = new beidanci.service.po.User();
                                    owner.setId(beidanci.util.Constants.SYS_USER_SYS_ID);
                                    sentence.setAuthor(owner);
                                    
                                    sentenceBo.createEntity(sentence);
                                    
                                    sysDbSyncBo.logOperation("INSERT", "sentence", sentence.getId(), beidanci.service.util.JsonUtils.toJson(sentenceBo.toDto(sentence)));
                                    logger.info("成功为单词 {} 的释义补充了 AI 例句: {}", spell, sentenceEn);
                                }
                            }
                        }
                        
                        Thread.sleep(1500); // 防阿里云限流QPS
                    } catch (Exception innerE) {
                        logger.warn("处理释义项 {} 发生异常: {}", meaningId, innerE.getMessage());
                    }
                }
                logger.info("通用词典例句后台补齐任务全部完成！");
            } catch (Exception e) {
                org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("后台补齐大异常", e);
            }
        }).start();

        fixed.add("缺失例句释义项的 AI 后台补齐任务已提交，进度可在服务器日志中查看，补齐会自动同步到客户端更新。");
        return meaningsWithoutSentences.size();
    }

    private int fixUserStudySteps(List<String> fixed) {
        int fixedCount = 0;
        try {
            // 获取所有缺失学习步骤的用户 ID
            String findUsersSql = "SELECT DISTINCT id FROM \"user\" u " +
                                 "WHERE NOT EXISTS (" +
                                 "  SELECT 1 FROM user_study_step uss " +
                                 "  WHERE uss.user_id = u.id AND uss.study_step IN ('En2Ch', 'Ch2En')" +
                                 ")";
            List<String> userIds = namedParameterJdbcTemplate.query(findUsersSql, new MapSqlParameterSource(), (rs, rowNum) -> rs.getString("id"));
            
            for (String userId : userIds) {
                userDbSyncBo.repairUserBaseData(userId);
                fixedCount++;
            }
            
            if (fixedCount > 0) {
                fixed.add(String.format("为 %d 个缺失学习步骤的用户执行了基础数据修复及日志生成", fixedCount));
            }
            
        } catch (org.springframework.dao.DataAccessException e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }

    private int fixMissingUserDicts(List<String> fixed) {
        int fixedCount = 0;
        try {
            // 一次性查出所有缺少"生词本"或"已掌握"词书的用户
            String sql = "SELECT u.id, u.user_name, u.nick_name, '生词本' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '生词本' " +
                        "WHERE d.id IS NULL " +
                        "UNION ALL " +
                        "SELECT u.id, u.user_name, u.nick_name, '已掌握' as missing_dict " +
                        "FROM \"user\" u " +
                        "LEFT JOIN dict d ON u.id = d.owner_id AND d.name = '已掌握' " +
                        "WHERE d.id IS NULL";
            
            List<Object[]> missingDicts = namedParameterJdbcTemplate.query(sql, 
                new MapSqlParameterSource(), 
                (rs, rowNum) -> new Object[]{
                    rs.getString("id"),
                    rs.getString("user_name"),
                    rs.getString("nick_name"),
                    rs.getString("missing_dict")
                }
            );
            
            // 为每个缺失词书的用户创建对应词书
            for (Object[] record : missingDicts) {
                String userId = (String) record[0];
                String userName = (String) record[1];
                String nickName = (String) record[2];
                String missingDict = (String) record[3];
                
                try {
                    User user = userBo.findById(userId);
                    if (user == null) {
                        continue;
                    }
                    
                    // 使用统一的修复逻辑，涵盖词书创建、步骤创建、日志生成和版本升级
                    userDbSyncBo.repairUserBaseData(userId);
                    
                    fixed.add(String.format("为用户 %s (%s, ID: %s) 创建%s", 
                            nickName != null ? nickName : userName, userName, userId, missingDict));
                    fixedCount++;
                } catch (Exception e) {
                    // 记录错误但继续处理其他用户
                    fixed.add(String.format("为用户 %s (ID: %s) 创建%s失败: %s", 
                            userName, userId, missingDict, e.getMessage()));
                }
            }
        } catch (org.springframework.dao.DataAccessException e) {
            org.slf4j.LoggerFactory.getLogger(SystemHealthCheckBo.class).error("自动修复失败", e);
        }
        return fixedCount;
    }
}
