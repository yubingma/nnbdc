package beidanci.service.bo;

import java.util.*;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import beidanci.api.model.*;
import beidanci.service.po.*;
import beidanci.util.Constants;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.Util;

@Service
public class DataSanitizeBo {
    private static final org.slf4j.Logger logger = org.slf4j.LoggerFactory.getLogger(DataSanitizeBo.class);

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    @Autowired
    private SentenceBo sentenceBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    // 数据规范性检查相关的 SQL 条件片段
    private static final String DIRTY_WORD_PHONETIC_SQL_WHERE = 
        "(pronounce ~ '[/\\\\\\\\[\\\\\\\\]［］]|[,，]\\s*$') " +
        "OR (british_pronounce ~ '[/\\\\\\\\[\\\\\\\\]［］]|[,，]\\s*$') " +
        "OR (america_pronounce ~ '[/\\\\\\\\[\\\\\\\\]［］]|[,，]\\s*$')";
    
    private static final String DIRTY_MEANING_SQL_WHERE = 
        "(meaning ~ '[,，]\\s*$') OR (ci_xing ~ '[,，]\\s*$')";
    
    private static final String DIRTY_SENTENCE_SQL_WHERE = 
        "(english ~ '[,，]\\s*$') OR (chinese ~ '[,，]\\s*$') " +
        "OR (word_meaning ~ '[,，]\\s*$') OR (part_of_speech ~ '[,，]\\s*$')";

    /**
     * 清洗系统数据（修复AI导入产生的多余逗号和斜线）
     */
    public SystemHealthFixResult sanitizeData() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        int totalFixedCount = 0;

        try {
            // 1. 清洗单词音标
            totalFixedCount += sanitizeWordPhonetics(fixed);

            // 2. 清洗释义项
            totalFixedCount += sanitizeMeaningItems(fixed);

            // 3. 清洗例句
            totalFixedCount += sanitizeSentences(fixed);

            if (totalFixedCount == 0) {
                fixed.add("未发现需要清洗的数据。");
            } else {
                fixed.add(String.format("数据清洗完成，共修复 %d 条记录。", totalFixedCount));
            }
        } catch (Exception e) {
            logger.error("数据清洗失败", e);
            errors.add("数据清洗过程中出错: " + e.getMessage());
        }

        return new SystemHealthFixResult(totalFixedCount, errors, fixed);
    }

    /**
     * 检查系统数据规范性情况
     */
    public SystemHealthCheckResult checkDataSanitization() {
        List<SystemHealthIssue> issues = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        try {
            // 1. 检查单词音标
            int wordCount = countDirtyRecords("word", DIRTY_WORD_PHONETIC_SQL_WHERE);
            if (wordCount > 0) {
                issues.add(new SystemHealthIssue("音标不规范", String.format("发现 %d 个单词的音标包含斜线、方括号或以逗号结尾", wordCount), "data_sanitization"));
            }

            // 2. 检查释义项
            int meaningCount = countDirtyRecords("meaning_item", DIRTY_MEANING_SQL_WHERE);
            if (meaningCount > 0) {
                issues.add(new SystemHealthIssue("释义项不规范", String.format("发现 %d 个释义项内容或词性以逗号结尾", meaningCount), "data_sanitization"));
            }

            // 3. 检查例句
            int sentenceCount = countDirtyRecords("sentence", DIRTY_SENTENCE_SQL_WHERE);
            if (sentenceCount > 0) {
                issues.add(new SystemHealthIssue("例句不规范", String.format("发现 %d 个例句文本或关联释义以逗号结尾", sentenceCount), "data_sanitization"));
            }

        } catch (Exception e) {
            logger.error("检查数据规范性失败", e);
            errors.add("检查数据规范性过程中出错: " + e.getMessage());
        }

        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    private int countDirtyRecords(String table, String where) {
        String sql = String.format("SELECT COUNT(*) FROM %s WHERE %s", table, where);
        @SuppressWarnings("null")
        Integer count = namedParameterJdbcTemplate.queryForObject(sql, new MapSqlParameterSource(), Integer.class);
        return count != null ? count : 0;
    }

    private int sanitizeWordPhonetics(List<String> fixed) throws Exception {
        int count = 0;
        // 查找可能需要修复的单词：音标包含斜线、方括号，或以逗号结尾
        String sql = "SELECT id, spell, pronounce, british_pronounce, america_pronounce FROM word WHERE " + DIRTY_WORD_PHONETIC_SQL_WHERE;
        
        List<Map<String, Object>> words = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
        for (Map<String, Object> map : words) {
            String id = (String) map.get("id");
            String p = (String) map.get("pronounce");
            String bp = (String) map.get("british_pronounce");
            String ap = (String) map.get("america_pronounce");

            String np = Util.sanitizePhonetic(p);
            String nbp = Util.sanitizePhonetic(bp);
            String nap = Util.sanitizePhonetic(ap);

            if (!Objects.equals(p, np) || !Objects.equals(bp, nbp) || !Objects.equals(ap, nap)) {
                Word word = wordBo.findById(id);
                word.setPronounce(np);
                word.setBritishPronounce(nbp);
                word.setAmericaPronounce(nap);
                wordBo.updateEntity(word);
                
                // 记录同步日志
                sysDbSyncBo.logOperation(wordBo.toDto(word), "UPDATE", "word", id, JsonUtils.toJson(wordBo.toDto(word)));
                count++;
            }
        }
        if (count > 0) fixed.add(String.format("修复了 %d 个单词的音标格式。", count));
        return count;
    }

    private int sanitizeMeaningItems(List<String> fixed) throws Exception {
        int count = 0;
        // 查找可能需要修复的释义项：释义或词性以逗号结尾
        String sql = "SELECT id, meaning, ci_xing FROM meaning_item WHERE " + DIRTY_MEANING_SQL_WHERE;
        List<Map<String, Object>> items = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
        for (Map<String, Object> map : items) {
            String id = (String) map.get("id");
            String meaningStr = (String) map.get("meaning");
            String pos = (String) map.get("ci_xing");

            String nMeaning = Util.sanitizeAiString(meaningStr);
            String nPos = Util.sanitizeAiString(pos);

            if (!Objects.equals(meaningStr, nMeaning) || !Objects.equals(pos, nPos)) {
                MeaningItem mi = meaningItemBo.findById(id);
                mi.setMeaning(nMeaning);
                mi.setCiXing(nPos);
                meaningItemBo.updateEntity(mi);
                
                // 记录同步日志 (仅针对系统通用资源)
                if (mi.getOwner() != null && Constants.SYS_USER_SYS_ID.equals(mi.getOwner().getId())) {
                    sysDbSyncBo.logOperation(meaningItemBo.toDto(mi), "UPDATE", "meaning_item", id, JsonUtils.toJson(meaningItemBo.toDto(mi)));
                }
                count++;
            }
        }
        if (count > 0) fixed.add(String.format("修复了 %d 个释义项的文本格式。", count));
        return count;
    }

    private int sanitizeSentences(List<String> fixed) throws Exception {
        int count = 0;
        // 查找可能需要修复的例句：英文、中文、单词释义或词性以逗号结尾
        String sql = "SELECT id, english, chinese, word_meaning, part_of_speech FROM sentence WHERE " + DIRTY_SENTENCE_SQL_WHERE;
        List<Map<String, Object>> sentences = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
        for (Map<String, Object> map : sentences) {
            String id = (String) map.get("id");
            String en = (String) map.get("english");
            String cn = (String) map.get("chinese");
            String wm = (String) map.get("word_meaning");
            String pos = (String) map.get("part_of_speech");

            String nEn = Util.sanitizeAiString(en);
            String nCn = Util.sanitizeAiString(cn);
            String nWm = Util.sanitizeAiString(wm);
            String nPos = Util.sanitizeAiString(pos);

            if (!Objects.equals(en, nEn) || !Objects.equals(cn, nCn) || !Objects.equals(wm, nWm) || !Objects.equals(pos, nPos)) {
                Sentence s = sentenceBo.findById(id);
                s.setEnglish(nEn);
                s.setChinese(nCn);
                s.setWordMeaning(nWm);
                s.setPartOfSpeech(nPos);
                sentenceBo.updateEntity(s);
                
                // 记录同步日志 (仅针对系统通用资源)
                if (s.getOwner() != null && Constants.SYS_USER_SYS_ID.equals(s.getOwner().getId())) {
                    sysDbSyncBo.logOperation(sentenceBo.toDto(s), "UPDATE", "sentence", id, JsonUtils.toJson(sentenceBo.toDto(s)));
                }
                count++;
            }
        }
        if (count > 0) fixed.add(String.format("修复了 %d 个例句的文本格式。", count));
        return count;
    }
}
