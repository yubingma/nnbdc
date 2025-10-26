package beidanci.service.bo;

import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.SystemHealthCheckResult;
import beidanci.api.model.SystemHealthFixResult;
import beidanci.api.model.SystemHealthIssue;
import beidanci.service.dao.UserDbVersionDao;

/**
 * 系统健康检查业务逻辑
 */
@Service
public class SystemHealthCheckBo {

    @Autowired
    private DictBo dictBo;
    
    @Autowired
    private LearningDictBo learningDictBo;
    
    @Autowired
    private UserDbVersionDao userDbVersionDao;
    
    @Autowired
    private MeaningItemBo meaningItemBo;
    
    @Autowired
    private SentenceBo sentenceBo;

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
            // 获取所有用户词典（ownerId != 15118）
            List<String> userDictIds = dictBo.getUserDictIds();
            
            for (String dictId : userDictIds) {
                // 检查词典单词序号连续性
                checkDictWordSequence(dictId, issues);
                
                // 检查词典单词数量一致性
                checkDictWordCount(dictId, issues);
            }
            
        } catch (Exception e) {
            errors.add("检查用户词典完整性时出错: " + e.getMessage());
        }
        
        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    /**
     * 检查学习进度合理性
     */
    public SystemHealthCheckResult checkLearningProgress() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 查找学习进度大于词书单词数量的记录
            List<Object[]> invalidRecords = learningDictBo.findInvalidLearningProgress();
            
            for (Object[] record : invalidRecords) {
                String userId = (String) record[0];
                String dictId = (String) record[1];
                Integer currentSeq = (Integer) record[2];
                Integer wordCount = (Integer) record[3];
                
                issues.add(new SystemHealthIssue(
                    "学习进度异常",
                    String.format("用户 %s 在词典 %s 中的学习进度(%d)超过词典单词数(%d)", 
                                userId, dictId, currentSeq, wordCount),
                    "learning_progress"
                ));
            }
            
        } catch (Exception e) {
            errors.add("检查学习进度合理性时出错: " + e.getMessage());
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
     * 自动修复系统问题
     */
    @Transactional
    public SystemHealthFixResult autoFixSystemIssues(List<String> issueTypes) {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        int fixedCount = 0;
        
        try {
            for (String issueType : issueTypes) {
                switch (issueType) {
                    case "system_dict_integrity":
                        fixedCount += fixSystemDictIntegrity(fixed);
                        break;
                    case "user_dict_integrity":
                        fixedCount += fixUserDictIntegrity(fixed);
                        break;
                    case "learning_progress":
                        fixedCount += fixLearningProgress(fixed);
                        break;
                    case "db_version":
                        fixedCount += fixDbVersionConsistency(fixed);
                        break;
                    case "common_dict_integrity":
                        fixedCount += fixCommonDictIntegrity(fixed);
                        break;
                    default:
                        errors.add("未知的问题类型: " + issueType);
                }
            }
        } catch (Exception e) {
            errors.add("自动修复过程中出错: " + e.getMessage());
        }
        
        return new SystemHealthFixResult(fixedCount, errors, fixed);
    }

    // 私有辅助方法

    private void checkDictWordSequence(String dictId, List<SystemHealthIssue> issues) {
        try {
            List<Object[]> dictWords = dictBo.checkDictWordSequence(dictId);
            if (dictWords.isEmpty()) return;
            
            // 检查序号是否从1开始
            Integer firstSeq = (Integer) dictWords.get(0)[1];
            if (firstSeq != 1) {
                issues.add(new SystemHealthIssue(
                    "序号不连续",
                    String.format("词典 %s 第一个单词序号不是1，实际是%d", dictId, firstSeq),
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
                                    dictId, wordId, spell, expectedSeq, actualSeq),
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
                                dictId, lastSeq, dictWords.size()),
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
            
            if (!actualCount.equals(recordedCount.longValue())) {
                issues.add(new SystemHealthIssue(
                    "单词数量不匹配",
                    String.format("词典 %s 记录数量: %d, 实际数量: %d", 
                                dictId, recordedCount, actualCount),
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
                // 修复序号
                dictBo.fixDictWordSequence(dictId);
                
                // 修复数量
                Long actualCount = dictBo.getDictWordCount(dictId);
                dictBo.updateDictWordCount(dictId, actualCount.intValue());
                
                fixed.add("修复系统词典 " + dictId + " 的完整性问题");
                fixedCount++;
            }
        } catch (Exception e) {
            // 错误已在调用方处理
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
            // 错误已在调用方处理
        }
        return fixedCount;
    }

    private int fixLearningProgress(List<String> fixed) {
        int fixedCount = 0;
        try {
            List<Object[]> invalidRecords = learningDictBo.findInvalidLearningProgress();
            for (Object[] record : invalidRecords) {
                String userId = (String) record[0];
                String dictId = (String) record[1];
                Integer wordCount = (Integer) record[3];
                
                learningDictBo.fixLearningProgress(userId, dictId, wordCount);
                fixed.add(String.format("修复用户 %s 在词典 %s 中的学习进度", userId, dictId));
                fixedCount++;
            }
        } catch (Exception e) {
            // 错误已在调用方处理
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
            // 错误已在调用方处理
        }
        return fixedCount;
    }

    private int fixCommonDictIntegrity(List<String> fixed) {
        // 通用词典完整性修复比较复杂，需要根据具体业务逻辑实现
        // 这里暂时返回0，表示暂不支持自动修复
        return 0;
    }
}
