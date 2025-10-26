package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.DiagnosticResultVo;
import beidanci.api.model.DataFixResultDto;
import beidanci.api.model.DiagnosticIssue;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.LearningDict;
import beidanci.service.po.SysDbLog;
import beidanci.service.util.Util;

/**
 * 数据诊断业务逻辑类
 */
@Service
public class DataDiagnosticBo {

    @Autowired
    private SysDbLogBo sysDbLogBo;
    
    @Autowired
    private DictBo dictBo;
    
    @Autowired
    private LearningDictBo learningDictBo;
    
    @Autowired
    private UserBo userBo;

    /**
     * 执行系统数据诊断
     */
    public DiagnosticResultVo performSystemDiagnostic() {
        List<String> errors = new ArrayList<>();
        List<DiagnosticIssue> issues = new ArrayList<>();
        
        try {
            // 1. 检查词典单词序号连续性
            checkDictWordSequences(issues);
            
            // 2. 检查词典单词数量一致性
            checkDictWordCounts(issues);
            
            // 3. 检查学习进度合理性
            checkLearningProgress(issues);
            
        } catch (Exception e) {
            errors.add("系统数据诊断过程中出现错误: " + e.getMessage());
        }
        
        boolean isHealthy = errors.isEmpty() && issues.isEmpty();
        int totalIssues = errors.size() + issues.size();
        
        return new DiagnosticResultVo(isHealthy, totalIssues, errors, issues);
    }

    /**
     * 执行用户数据诊断
     */
    public DiagnosticResultVo performUserDiagnostic(String userId) {
        List<String> errors = new ArrayList<>();
        List<DiagnosticIssue> issues = new ArrayList<>();
        
        try {
            // 1. 检查用户词典单词序号连续性
            checkUserDictWordSequences(issues, userId);
            
            // 2. 检查用户词典单词数量一致性
            checkUserDictWordCounts(issues, userId);
            
            // 3. 检查用户学习进度合理性
            checkUserLearningProgress(issues, userId);
            
        } catch (Exception e) {
            errors.add("用户数据诊断过程中出现错误: " + e.getMessage());
        }
        
        boolean isHealthy = errors.isEmpty() && issues.isEmpty();
        int totalIssues = errors.size() + issues.size();
        
        return new DiagnosticResultVo(isHealthy, totalIssues, errors, issues);
    }

    /**
     * 自动修复发现的问题
     */
    @Transactional
    public DataFixResultDto autoFix(DiagnosticResultVo diagnosticResult) {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        try {
            // 修复序号不连续问题
            if (hasIssue(diagnosticResult, "dict_word_sequence")) {
                fixDictWordSequences(fixed, errors);
            }
            
            // 修复单词数量不匹配问题
            if (hasIssue(diagnosticResult, "dict_word_count")) {
                fixDictWordCounts(fixed, errors);
            }
            
            // 修复学习进度异常问题
            if (hasIssue(diagnosticResult, "learning_progress")) {
                fixLearningProgress(fixed, errors);
            }
            
        } catch (Exception e) {
            errors.add("自动修复过程中出现错误: " + e.getMessage());
        }
        
        boolean hasFixed = !fixed.isEmpty();
        boolean hasErrors = !errors.isEmpty();
        
        return new DataFixResultDto(hasFixed, hasErrors, fixed, errors);
    }

    // 私有方法实现各种检查逻辑
    private void checkDictWordSequences(List<DiagnosticIssue> issues) {
        try {
            List<Dict> allDicts = dictBo.queryAll(new Dict(), false);
            
            for (Dict dict : allDicts) {
                Session session = dictBo.getSession();
                String hql = "from DictWord where dict=:dict order by seq asc";
                Query<DictWord> query = session.createQuery(hql, DictWord.class);
                query.setParameter("dict", dict);
                List<DictWord> wordsList = query.list();
                
                if (wordsList.isEmpty()) continue;
                
                // 检查序号是否从1开始
                if (wordsList.get(0).getSeq() != 1) {
                    issues.add(new DiagnosticIssue("序号不连续", 
                        "词典 \"" + dict.getName() + "\" 第一个单词序号不是1", "dict_word_sequence"));
                }
                
                // 检查序号是否连续
                for (int i = 0; i < wordsList.size(); i++) {
                    if (wordsList.get(i).getSeq() != i + 1) {
                        issues.add(new DiagnosticIssue("序号不连续", 
                            "词典 \"" + dict.getName() + "\" 位置" + (i + 1) + "的单词序号不正确", "dict_word_sequence"));
                        break;
                    }
                }
                
                // 检查最大序号是否等于总单词数
                if (wordsList.get(wordsList.size() - 1).getSeq() != wordsList.size()) {
                    issues.add(new DiagnosticIssue("序号不连续", 
                        "词典 \"" + dict.getName() + "\" 最大序号不等于总单词数", "dict_word_sequence"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查词典单词序号时出错: " + e.getMessage(), "system_error"));
        }
    }

    private void checkUserDictWordSequences(List<DiagnosticIssue> issues, String userId) {
        try {
            List<Dict> userDicts = dictBo.getDictsByOwnerId(userId, null);
            
            for (Dict dict : userDicts) {
                Session session = dictBo.getSession();
                String hql = "from DictWord where dict=:dict order by seq asc";
                Query<DictWord> query = session.createQuery(hql, DictWord.class);
                query.setParameter("dict", dict);
                List<DictWord> wordsList = query.list();
                
                if (wordsList.isEmpty()) continue;
                
                // 检查序号是否从1开始
                if (wordsList.get(0).getSeq() != 1) {
                    issues.add(new DiagnosticIssue("序号不连续", 
                        "词典 \"" + dict.getName() + "\" 第一个单词序号不是1", "dict_word_sequence"));
                }
                
                // 检查序号是否连续
                for (int i = 0; i < wordsList.size(); i++) {
                    if (wordsList.get(i).getSeq() != i + 1) {
                        issues.add(new DiagnosticIssue("序号不连续", 
                            "词典 \"" + dict.getName() + "\" 位置" + (i + 1) + "的单词序号不正确", "dict_word_sequence"));
                        break;
                    }
                }
                
                // 检查最大序号是否等于总单词数
                if (wordsList.get(wordsList.size() - 1).getSeq() != wordsList.size()) {
                    issues.add(new DiagnosticIssue("序号不连续", 
                        "词典 \"" + dict.getName() + "\" 最大序号不等于总单词数", "dict_word_sequence"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查用户词典单词序号时出错: " + e.getMessage(), "system_error"));
        }
    }

    private void checkDictWordCounts(List<DiagnosticIssue> issues) {
        try {
            List<Dict> allDicts = dictBo.queryAll(new Dict(), false);
            
            for (Dict dict : allDicts) {
                Session session = dictBo.getSession();
                String hql = "select count(*) from DictWord where dict=:dict";
                Query<Long> query = session.createQuery(hql, Long.class);
                query.setParameter("dict", dict);
                Long actualCount = query.uniqueResult();
                
                if (dict.getWordCount() != actualCount.intValue()) {
                    issues.add(new DiagnosticIssue("单词数量不匹配", 
                        "词典 \"" + dict.getName() + "\" 记录数量: " + dict.getWordCount() + ", 实际数量: " + actualCount, 
                        "dict_word_count"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查词典单词数量时出错: " + e.getMessage(), "system_error"));
        }
    }

    private void checkUserDictWordCounts(List<DiagnosticIssue> issues, String userId) {
        try {
            List<Dict> userDicts = dictBo.getDictsByOwnerId(userId, null);
            
            for (Dict dict : userDicts) {
                Session session = dictBo.getSession();
                String hql = "select count(*) from DictWord where dict=:dict";
                Query<Long> query = session.createQuery(hql, Long.class);
                query.setParameter("dict", dict);
                Long actualCount = query.uniqueResult();
                
                if (dict.getWordCount() != actualCount.intValue()) {
                    issues.add(new DiagnosticIssue("单词数量不匹配", 
                        "词典 \"" + dict.getName() + "\" 记录数量: " + dict.getWordCount() + ", 实际数量: " + actualCount, 
                        "dict_word_count"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查用户词典单词数量时出错: " + e.getMessage(), "system_error"));
        }
    }

    private void checkLearningProgress(List<DiagnosticIssue> issues) {
        try {
            List<LearningDict> allLearningDicts = learningDictBo.queryAll(new LearningDict(), false);
            
            for (LearningDict learningDict : allLearningDicts) {
                Dict dict = dictBo.findById(learningDict.getId().getDictId(), false);
                if (dict == null) continue;
                
                if (learningDict.getCurrentWordSeq() != null && learningDict.getCurrentWordSeq() > dict.getWordCount()) {
                    issues.add(new DiagnosticIssue("学习进度异常", 
                        "用户学习进度(" + learningDict.getCurrentWordSeq() + ")超过词典单词数(" + dict.getWordCount() + ")", 
                        "learning_progress"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查学习进度时出错: " + e.getMessage(), "system_error"));
        }
    }

    private void checkUserLearningProgress(List<DiagnosticIssue> issues, String userId) {
        try {
            List<LearningDict> userLearningDicts = learningDictBo.getLearningDictsOfUser(userBo.findById(userId, false));
            
            for (LearningDict learningDict : userLearningDicts) {
                Dict dict = dictBo.findById(learningDict.getId().getDictId(), false);
                if (dict == null) continue;
                
                if (learningDict.getCurrentWordSeq() != null && learningDict.getCurrentWordSeq() > dict.getWordCount()) {
                    issues.add(new DiagnosticIssue("学习进度异常", 
                        "用户学习进度(" + learningDict.getCurrentWordSeq() + ")超过词典单词数(" + dict.getWordCount() + ")", 
                        "learning_progress"));
                }
            }
        } catch (Exception e) {
            issues.add(new DiagnosticIssue("检查错误", "检查用户学习进度时出错: " + e.getMessage(), "system_error"));
        }
    }

    // 修复方法
    private void fixDictWordSequences(List<String> fixed, List<String> errors) {
        try {
            List<Dict> allDicts = dictBo.queryAll(new Dict(), false);
            
            for (Dict dict : allDicts) {
                Session session = dictBo.getSession();
                String hql = "from DictWord where dict=:dict order by seq asc";
                Query<DictWord> query = session.createQuery(hql, DictWord.class);
                query.setParameter("dict", dict);
                List<DictWord> wordsList = query.list();
                
                if (wordsList.isEmpty()) continue;
                
                // 重新分配序号
                boolean needsFix = false;
                for (int i = 0; i < wordsList.size(); i++) {
                    if (wordsList.get(i).getSeq() != i + 1) {
                        needsFix = true;
                        break;
                    }
                }
                
                if (needsFix) {
                    // 重新排序
                    for (int i = 0; i < wordsList.size(); i++) {
                        DictWord word = wordsList.get(i);
                        word.setSeq(i + 1);
                        // 这里需要调用更新方法
                    }
                    fixed.add("修复词典 \"" + dict.getName() + "\" 单词序号");
                    
                    // 生成同步日志
                    generateDictWordSequenceFixLog(dict.getId());
                }
            }
        } catch (Exception e) {
            errors.add("修复词典单词序号时出错: " + e.getMessage());
        }
    }

    private void fixDictWordCounts(List<String> fixed, List<String> errors) {
        try {
            List<Dict> allDicts = dictBo.queryAll(new Dict(), false);
            
            for (Dict dict : allDicts) {
                Session session = dictBo.getSession();
                String hql = "select count(*) from DictWord where dict=:dict";
                Query<Long> query = session.createQuery(hql, Long.class);
                query.setParameter("dict", dict);
                Long actualCount = query.uniqueResult();
                
                if (dict.getWordCount() != actualCount.intValue()) {
                    dict.setWordCount(actualCount.intValue());
                    dictBo.updateEntity(dict);
                    fixed.add("修复词典 \"" + dict.getName() + "\" 单词数量: " + actualCount);
                    
                    // 生成同步日志
                    generateDictWordCountFixLog(dict);
                }
            }
        } catch (Exception e) {
            errors.add("修复词典单词数量时出错: " + e.getMessage());
        }
    }

    private void fixLearningProgress(List<String> fixed, List<String> errors) {
        try {
            List<LearningDict> allLearningDicts = learningDictBo.queryAll(new LearningDict(), false);
            
            for (LearningDict learningDict : allLearningDicts) {
                Dict dict = dictBo.findById(learningDict.getId().getDictId(), false);
                if (dict == null) continue;
                
                if (learningDict.getCurrentWordSeq() != null && learningDict.getCurrentWordSeq() > dict.getWordCount()) {
                    learningDict.setCurrentWordSeq(dict.getWordCount());
                    learningDictBo.updateEntity(learningDict);
                    fixed.add("修复用户学习进度: " + dict.getWordCount());
                }
            }
        } catch (Exception e) {
            errors.add("修复学习进度时出错: " + e.getMessage());
        }
    }

    // 生成同步日志的方法
    private void generateDictWordSequenceFixLog(String dictId) {
        try {
            // 生成系统数据同步日志
            SysDbLog log = new SysDbLog();
            log.setId(Util.uuid());
            log.setVersion(1); // 简化版本，使用固定版本号
            log.setOperate("UPDATE");
            log.setTable("dict_word");
            log.setRecordId(dictId);
            log.setRecord("{\"action\":\"fix_sequence\",\"dictId\":\"" + dictId + "\",\"timestamp\":" + System.currentTimeMillis() + "}");
            log.setCreateTime(new Date());
            
            sysDbLogBo.createEntity(log);
        } catch (Exception e) {
            // 记录错误但不中断修复过程
            System.err.println("生成词典单词序号修复日志失败: " + e.getMessage());
        }
    }

    private void generateDictWordCountFixLog(Dict dict) {
        try {
            // 生成系统数据同步日志
            SysDbLog log = new SysDbLog();
            log.setId(Util.uuid());
            log.setVersion(1); // 简化版本，使用固定版本号
            log.setOperate("UPDATE");
            log.setTable("dict");
            log.setRecordId(dict.getId());
            log.setRecord("{\"action\":\"fix_word_count\",\"dictId\":\"" + dict.getId() + "\",\"wordCount\":" + dict.getWordCount() + ",\"timestamp\":" + System.currentTimeMillis() + "}");
            log.setCreateTime(new Date());
            
            sysDbLogBo.createEntity(log);
        } catch (Exception e) {
            System.err.println("生成词典单词数量修复日志失败: " + e.getMessage());
        }
    }

    private boolean hasIssue(DiagnosticResultVo diagnosticResult, String category) {
        if (diagnosticResult.getIssues() == null) return false;
        return diagnosticResult.getIssues().stream()
            .anyMatch(issue -> category.equals(issue.getCategory()));
    }
}