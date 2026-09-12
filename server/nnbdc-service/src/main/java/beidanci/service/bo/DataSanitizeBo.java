package beidanci.service.bo;

import java.io.File;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import beidanci.api.model.MeaningItemDto;
import beidanci.api.model.SystemHealthCheckResult;
import beidanci.api.model.SystemHealthFixResult;
import beidanci.api.model.SystemHealthIssue;
import beidanci.service.po.Dict;
import beidanci.service.po.MeaningItem;
import beidanci.service.po.Sentence;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.MyImage;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;
import beidanci.util.Constants;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

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
    private WordImageBo wordImageBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private UserDbSyncBo userDbSyncBo;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private UserBo userBo;

    private static volatile boolean isPopularitySanitizing = false;
    private static volatile int popularitySanitizeTotal = 0;
    private static volatile int popularitySanitizeProcessed = 0;
    private static volatile String popularitySanitizeLog = "";

    private static volatile boolean isWordImageSanitizing = false;
    private static volatile int wordImageSanitizeTotal = 0;
    private static volatile int wordImageSanitizeProcessed = 0;
    private static volatile int wordImageSanitizeFixedCount = 0;
    private static volatile String wordImageSanitizeLog = "";

    private static volatile boolean isMeaningSanitizing = false;
    private static volatile int meaningSanitizeTotal = 0;
    private static volatile int meaningSanitizeProcessed = 0;
    private static volatile int meaningSanitizeFixedCount = 0;
    private static volatile String meaningSanitizeLog = "";

    private static volatile boolean isDataSanitizing = false;    private static volatile int dataSanitizeStepIndex = 0;
    private static volatile String dataSanitizeStepLabel = "";
    private static volatile int dataSanitizeTotal = 0;
    private static volatile int dataSanitizeProcessed = 0;
    private static volatile int dataSanitizeFixedCount = 0;
    private static volatile List<String> dataSanitizeMessages = new ArrayList<>();
    private static volatile List<String> dataSanitizeErrors = new ArrayList<>();

    private static volatile boolean isAbbreviationSoundRegenerating = false;
    private static volatile int abbreviationSoundTotal = 0;
    private static volatile int abbreviationSoundProcessed = 0;
    private static volatile int abbreviationSoundRegeneratedCount = 0;
    private static volatile String abbreviationSoundLog = "";

    private final OkHttpClient httpClient = new OkHttpClient.Builder()
            .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .build();

    // 数据规范性检查相关的 SQL 条件片段
    // 音标：判定条件必须与 Util.sanitizePhonetic 的修复范围严格一致，否则会出现"洗完仍报脏"的假告警。
    // 脏形态 = 首尾包裹了 / [ ［ ] ］、尾部残留逗号、或 JSON 转义残留的反斜杠。
    private static final String DIRTY_WORD_PHONETIC_SQL_WHERE = 
        "(btrim(pronounce) ~ '^[/\\[［]' OR btrim(pronounce) ~ '[/\\]］]$' OR btrim(pronounce) ~ '[,，]$' OR pronounce ~ '\\\\') " +
        "OR (btrim(british_pronounce) ~ '^[/\\[［]' OR btrim(british_pronounce) ~ '[/\\]］]$' OR btrim(british_pronounce) ~ '[,，]$' OR british_pronounce ~ '\\\\') " +
        "OR (btrim(america_pronounce) ~ '^[/\\[［]' OR btrim(america_pronounce) ~ '[/\\]］]$' OR btrim(america_pronounce) ~ '[,，]$' OR america_pronounce ~ '\\\\')";
    
    private static final String DIRTY_MEANING_SQL_WHERE = 
        "(meaning ~ '[,，]\\s*$') OR (ci_xing ~ '[,，]\\s*$')";

    // 释义项内部禁止出现分号：一条释义项只能承载一个义项
    private static final String DIRTY_MEANING_SEPARATOR_SQL_WHERE =
        "(meaning ~ '" + Util.MEANING_SEPARATOR_REGEX + "')";
    
    private static final String DIRTY_SENTENCE_SQL_WHERE = 
        "(english ~ '[,，]\\s*$') OR (chinese ~ '[,，]\\s*$') " +
        "OR (word_meaning ~ '[,，]\\s*$') OR (part_of_speech ~ '[,，]\\s*$')";

    /**
     * 清洗系统数据（后台异步线程执行，修复AI导入产生的多余逗号和斜线，清理损坏/无效的单词配图等）。
     * <p>
     * 全量清洗要改写数万条记录并扫描全部配图文件，同步执行极易超过客户端 5 分钟超时并诱发重复触发，
     * 因此与"配图清洗""常用度清洗"保持一致：后台异步 + 进度轮询 + 并发保护。
     */
    public SystemHealthFixResult sanitizeData() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isDataSanitizing) {
            errors.add("数据清洗任务正在后台运行中，请勿重复触发。");
            fixed.add(describeDataSanitizeProgress());
            return new SystemHealthFixResult(1, errors, fixed);
        }

        isDataSanitizing = true;
        dataSanitizeStepIndex = 0;
        dataSanitizeStepLabel = "准备扫描";
        dataSanitizeTotal = 0;
        dataSanitizeProcessed = 0;
        dataSanitizeFixedCount = 0;
        dataSanitizeMessages = new ArrayList<>();
        dataSanitizeErrors = new ArrayList<>();

        new Thread(() -> {
            try {
                executeDataSanitization();
            } finally {
                isDataSanitizing = false;
            }
        }).start();

        fixed.add("数据清洗任务已成功在后台启动。");
        return new SystemHealthFixResult(0, errors, fixed);
    }

    /**
     * 获取全量数据清洗状态及进度
     */
    public SystemHealthFixResult getDataSanitizeStatus() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isDataSanitizing) {
            fixed.add(describeDataSanitizeProgress());
            fixed.addAll(dataSanitizeMessages);
            return new SystemHealthFixResult(1, errors, fixed);
        }
        if (dataSanitizeTotal > 0) {
            fixed.addAll(dataSanitizeMessages);
            errors.addAll(dataSanitizeErrors);
        } else {
            fixed.add("任务未运行。");
        }
        return new SystemHealthFixResult(0, errors, fixed);
    }

    private String describeDataSanitizeProgress() {
        if (dataSanitizeStepIndex == 0) {
            return "正在统计待清洗数据...";
        }
        return String.format("正在清洗第 %d/4 步「%s」: %d/%d",
                dataSanitizeStepIndex, dataSanitizeStepLabel, dataSanitizeProcessed, dataSanitizeTotal);
    }

    private void executeDataSanitization() {
        List<String> messages = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        int totalFixedCount = 0;

        try {
            dataSanitizeTotal = countSanitizeTargets();
            dataSanitizeProcessed = 0;

            // 1. 清洗单词音标
            dataSanitizeStepIndex = 1;
            dataSanitizeStepLabel = "音标";
            totalFixedCount += sanitizeWordPhonetics(messages);
            dataSanitizeMessages = new ArrayList<>(messages);

            // 2. 清洗释义项
            dataSanitizeStepIndex = 2;
            dataSanitizeStepLabel = "释义项";
            totalFixedCount += sanitizeMeaningItems(messages);
            dataSanitizeMessages = new ArrayList<>(messages);

            // 3. 清洗例句
            dataSanitizeStepIndex = 3;
            dataSanitizeStepLabel = "例句";
            totalFixedCount += sanitizeSentences(messages);
            dataSanitizeMessages = new ArrayList<>(messages);

            // 4. 清洗损坏或无效的单词配图
            dataSanitizeStepIndex = 4;
            dataSanitizeStepLabel = "单词配图";
            totalFixedCount += sanitizeWordImages(messages);
        } catch (Exception e) {
            logger.error("数据清洗失败", e);
            errors.add("数据清洗过程中出错: " + e.getMessage());
        }

        dataSanitizeFixedCount = totalFixedCount;
        if (errors.isEmpty()) {
            messages.add(totalFixedCount == 0
                    ? "未发现需要清洗的数据。"
                    : String.format("数据清洗完成，共修复 %d 条记录。", totalFixedCount));
        } else {
            messages.add(String.format("数据清洗中断，已修复 %d 条记录。", totalFixedCount));
        }
        dataSanitizeMessages = new ArrayList<>(messages);
        dataSanitizeErrors = new ArrayList<>(errors);
    }

    /**
     * 统计本轮全量清洗需要处理的记录总数（用于进度展示）。
     */
    private int countSanitizeTargets() {
        Integer imageCount = namedParameterJdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM word_image", new MapSqlParameterSource(), Integer.class);
        return countDirtyRecords("word", DIRTY_WORD_PHONETIC_SQL_WHERE)
                + countDirtyRecords("meaning_item", DIRTY_MEANING_SQL_WHERE)
                + countDirtyRecords("sentence", DIRTY_SENTENCE_SQL_WHERE)
                + (imageCount != null ? imageCount : 0);
    }

    /**
     * 单独清洗单词配图（后台异步线程执行，清理损坏/无效的图片文件并生成同步日志）
     */
    public SystemHealthFixResult sanitizeWordImagesOnly() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isWordImageSanitizing) {
            errors.add("单词配图清洗任务正在后台运行中，请勿重复触发。");
            fixed.add(String.format("当前进度: %d/%d。详情: %s", 
                    wordImageSanitizeProcessed, wordImageSanitizeTotal, wordImageSanitizeLog));
            return new SystemHealthFixResult(0, errors, fixed);
        }

        isWordImageSanitizing = true;
        wordImageSanitizeTotal = 0;
        wordImageSanitizeProcessed = 0;
        wordImageSanitizeFixedCount = 0;
        wordImageSanitizeLog = "准备扫描单词配图...";

        new Thread(() -> {
            try {
                executeWordImageSanitization();
            } finally {
                isWordImageSanitizing = false;
            }
        }).start();

        fixed.add("单词配图清洗任务已成功在后台启动。");
        return new SystemHealthFixResult(0, errors, fixed);
    }

    /**
     * 获取单词配图清洗状态及进度
     */
    public SystemHealthFixResult getWordImageSanitizeStatus() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        if (isWordImageSanitizing) {
            fixed.add(String.format("当前进度: %d/%d。已清理: %d 条。详情: %s", 
                    wordImageSanitizeProcessed, wordImageSanitizeTotal, wordImageSanitizeFixedCount, wordImageSanitizeLog));
            return new SystemHealthFixResult(1, errors, fixed);
        } else {
            if (wordImageSanitizeTotal > 0) {
                fixed.add(String.format("配图清洗完成。总扫描: %d 条，共清理 %d 条损坏或无效配图记录。", 
                        wordImageSanitizeTotal, wordImageSanitizeFixedCount));
            } else {
                fixed.add("任务未运行。");
            }
            return new SystemHealthFixResult(0, errors, fixed);
        }
    }

    private void executeWordImageSanitization() {
        try {
            wordImageSanitizeLog = "正在查询单词配图列表...";
            String sql = "SELECT id, image_file FROM word_image";
            List<Map<String, Object>> images = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
            wordImageSanitizeTotal = images.size();
            wordImageSanitizeProcessed = 0;
            wordImageSanitizeFixedCount = 0;
            File wordImageDir = requireWordImageDir();

            User sysUser = null;
            try {
                String sysUserId = userBo.getSysUser_sys(false).getId();
                sysUser = userBo.findById(sysUserId);
            } catch (Exception e) {
                logger.error("获取系统用户失败", e);
            }

            for (int i = 0; i < images.size(); i++) {
                Map<String, Object> map = images.get(i);
                String id = (String) map.get("id");
                String fileName = (String) map.get("image_file");
                boolean invalid = false;
                if (fileName == null || fileName.trim().isEmpty()) {
                    invalid = true;
                } else {
                    File file = new File(wordImageDir, fileName);
                    if (!MyImage.isValidImage(file)) {
                        invalid = true;
                    }
                }

                if (invalid) {
                    try {
                        wordImageBo.deleteWordImage(id, sysUser, false);
                        wordImageSanitizeFixedCount++;
                    } catch (Exception e) {
                        logger.error("清洗单词配图失败, id=" + id, e);
                    }
                }

                wordImageSanitizeProcessed++;
                if (i % 100 == 0 || i == images.size() - 1) {
                    wordImageSanitizeLog = String.format("正在扫描配图文件 (%d/%d)...", wordImageSanitizeProcessed, wordImageSanitizeTotal);
                }
            }
            wordImageSanitizeLog = String.format("清洗完成，扫描 %d 条，共清理 %d 条损坏或无效配图。", wordImageSanitizeTotal, wordImageSanitizeFixedCount);
            logger.info("单词配图清洗完成: 总数={}, 清理数={}", wordImageSanitizeTotal, wordImageSanitizeFixedCount);
        } catch (Exception e) {
            logger.error("执行单词配图清洗异常", e);
            wordImageSanitizeLog = "清洗过程中出错: " + e.getMessage();
        }
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

            // 释义项内用分号挤入了多个义项（应拆分为多条独立释义项）
            int meaningSeparatorCount = countDirtyRecords("meaning_item", DIRTY_MEANING_SEPARATOR_SQL_WHERE);
            if (meaningSeparatorCount > 0) {
                issues.add(new SystemHealthIssue("释义项含分号", String.format("发现 %d 个释义项把多个义项用分号挤在了一条记录里", meaningSeparatorCount), "data_sanitization"));
            }

            // 3. 检查例句
            int sentenceCount = countDirtyRecords("sentence", DIRTY_SENTENCE_SQL_WHERE);
            if (sentenceCount > 0) {
                issues.add(new SystemHealthIssue("例句不规范", String.format("发现 %d 个例句文本或关联释义以逗号结尾", sentenceCount), "data_sanitization"));
            }

            // 4. 检查损坏或缺失的单词配图
            int invalidImageCount = countInvalidWordImages();
            if (invalidImageCount > 0) {
                issues.add(new SystemHealthIssue("单词配图损坏或缺失", String.format("发现 %d 条配图记录对应的物理文件不存在或为损坏/非图片数据（如 HTML 错误页）", invalidImageCount), "data_sanitization"));
            }

        } catch (Exception e) {
            logger.error("检查数据规范性失败", e);
            errors.add("检查数据规范性过程中出错: " + e.getMessage());
        }

        return new SystemHealthCheckResult(issues.isEmpty() && errors.isEmpty(), issues, errors);
    }

    @SuppressWarnings("null")
    private int countDirtyRecords(String table, String where) {
        String sql = String.format("SELECT COUNT(*) FROM %s WHERE %s", table, where);
        Integer count = namedParameterJdbcTemplate.queryForObject(sql, new MapSqlParameterSource(), Integer.class);
        return count != null ? count : 0;
    }

    private int countInvalidWordImages() {
        String sql = "SELECT id, image_file FROM word_image";
        List<Map<String, Object>> images = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
        File wordImageDir = requireWordImageDir();
        int count = 0;
        for (Map<String, Object> map : images) {
            String fileName = (String) map.get("image_file");
            if (fileName == null || fileName.trim().isEmpty()) {
                count++;
                continue;
            }
            File file = new File(wordImageDir, fileName);
            if (!MyImage.isValidImage(file)) {
                count++;
            }
        }
        return count;
    }

    /**
     * 配图目录预检。
     * <p>
     * {@link MyImage#isValidImage} 对"文件不存在/不可读/任何异常"一律返回 false，
     * 若目录本身不可用（未配置、路径写错、权限不足、挂载丢失），会把全部配图误判为损坏并删除，
     * 且删除会连带删除物理图片文件、不可恢复。因此这里必须先确认目录可用，否则直接报错中止。
     */
    private File requireWordImageDir() {
        String baseDir = sysParamUtil.getImageBaseDir();
        if (baseDir == null || baseDir.trim().isEmpty()) {
            throw new IllegalStateException("系统参数 imgBaseDir 未配置，已中止配图清洗以避免误删全部配图");
        }
        File dir = new File(baseDir.trim(), "word");
        if (!dir.isDirectory() || !dir.canRead()) {
            throw new IllegalStateException("配图目录不可用，已中止配图清洗以避免误删全部配图: " + dir.getAbsolutePath());
        }
        return dir;
    }

    private int sanitizeWordImages(List<String> fixed) {
        int count = 0;
        String sql = "SELECT id, image_file FROM word_image";
        List<Map<String, Object>> images = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
        File wordImageDir = requireWordImageDir();

        User sysUser = null;
        try {
            String sysUserId = userBo.getSysUser_sys(false).getId();
            sysUser = userBo.findById(sysUserId);
        } catch (Exception e) {
            logger.error("获取系统用户失败", e);
        }

        for (Map<String, Object> map : images) {
            String id = (String) map.get("id");
            String fileName = (String) map.get("image_file");
            boolean invalid = false;
            if (fileName == null || fileName.trim().isEmpty()) {
                invalid = true;
            } else {
                File file = new File(wordImageDir, fileName);
                if (!MyImage.isValidImage(file)) {
                    invalid = true;
                }
            }

            if (invalid) {
                try {
                    wordImageBo.deleteWordImage(id, sysUser, false);
                    count++;
                } catch (Exception e) {
                    logger.error("清洗单词配图失败, id=" + id, e);
                }
            }
            dataSanitizeProcessed++;
        }
        if (count > 0) {
            fixed.add(String.format("清理了 %d 张损坏或无效的单词配图记录，并已生成同步日志。", count));
        }
        return count;
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
            dataSanitizeProcessed++;
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
            dataSanitizeProcessed++;
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
            dataSanitizeProcessed++;
        }
        if (count > 0) fixed.add(String.format("修复了 %d 个例句的文本格式。", count));
        return count;
    }

    /**
     * 清洗单词释义常用度数据（由管理员点击触发，后台异步线程执行）
     */
    public SystemHealthFixResult sanitizeWordPopularity() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isPopularitySanitizing) {
            errors.add("常用度清洗任务正在后台运行中，请勿重复触发。");
            fixed.add(String.format("当前进度: %d/%d。详情: %s", 
                    popularitySanitizeProcessed, popularitySanitizeTotal, popularitySanitizeLog));
            return new SystemHealthFixResult(0, errors, fixed);
        }

        // 异步启动清洗线程
        isPopularitySanitizing = true;
        popularitySanitizeLog = "准备初始化清洗任务...";
        
        new Thread(() -> {
            try {
                executePopularitySanitization();
            } finally {
                isPopularitySanitizing = false;
            }
        }).start();

        fixed.add("单词常用度清洗及自动对齐任务已成功在后台启动。");
        return new SystemHealthFixResult(0, errors, fixed);
    }

    /**
     * 获取单词释义常用度清洗状态及进度
     */
    public SystemHealthFixResult getWordPopularitySanitizeStatus() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        
        if (isPopularitySanitizing) {
            fixed.add(String.format("当前进度: %d/%d。详情: %s", 
                    popularitySanitizeProcessed, popularitySanitizeTotal, popularitySanitizeLog));
            return new SystemHealthFixResult(1, errors, fixed);
        } else {
            fixed.add("任务未运行。");
            return new SystemHealthFixResult(0, errors, fixed);
        }
    }

    private void executePopularitySanitization() {
        popularitySanitizeLog = "正在查询通用词表单词列表...";
        popularitySanitizeProcessed = 0;
        popularitySanitizeTotal = 0;

        try {
            // 1. 查询所有通用词表里尚未清洗过常用度的单词 (dict_id = '0')
            String sql = "SELECT w.id, w.spell FROM word w " +
                         "INNER JOIN dict_word dw ON dw.word_id = w.id " +
                         "WHERE dw.dict_id = '0' " +
                         "  AND NOT EXISTS ( " +
                         "      SELECT 1 FROM meaning_item mi " +
                         "      WHERE mi.word_id = w.id " +
                         "        AND mi.dict_id = '0' " +
                         "        AND mi.popularity_percent IS NOT NULL " +
                         "  )";
            List<Map<String, Object>> words = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
            popularitySanitizeTotal = words.size();
            popularitySanitizeLog = String.format("查询完成，共找到 %d 个待清洗单词。", popularitySanitizeTotal);
            logger.info("开始常用度数据清洗。总单词数: {}", popularitySanitizeTotal);

            User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
            Dict commonDict = new Dict();
            commonDict.setId("0");

            for (Map<String, Object> wordMap : words) {
                if (Thread.currentThread().isInterrupted()) {
                    popularitySanitizeLog = "清洗任务已被系统强行中断。";
                    break;
                }

                String wordId = (String) wordMap.get("id");
                String spell = (String) wordMap.get("spell");

                popularitySanitizeLog = String.format("正在处理单词 [%s] (%d/%d)...", spell, popularitySanitizeProcessed + 1, popularitySanitizeTotal);
                
                try {
                    // 2. 爬取海词
                    String url = "https://dict.cn/search?q=" + URLEncoder.encode(spell, "UTF-8");
                    Request request = new Request.Builder()
                            .url(url)
                            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                            .build();

                    String html = null;
                    try (Response response = httpClient.newCall(request).execute()) {
                        if (response.isSuccessful() && response.body() != null) {
                            html = response.body().string();
                        }
                    }

                    if (html == null) {
                        logger.warn("无法获取单词 [{}] 的海词页面", spell);
                        popularitySanitizeProcessed++;
                        continue;
                    }

                    // 3. 正则提取海词常用度数据
                    Map<String, Object> dictCnMeanings = parseChartData(html, "id=\"dict-chart-basic\"\\s+data=\"([^\"]+)\"");
                    if (dictCnMeanings == null || dictCnMeanings.isEmpty()) {
                        logger.info("单词 [{}] 没有海词释义图表数据，跳过。", spell);
                        popularitySanitizeProcessed++;
                        continue;
                    }

                    // 4. 加载系统现有释义（通用词表 '0'）
                    List<MeaningItemDto> currentMeanings = meaningItemBo.findMeaningsByWordAndDict(wordId, "0");
                    if (currentMeanings.isEmpty()) {
                        logger.info("系统内单词 [{}] (ID: {}) 没有现有释义，跳过。", spell, wordId);
                        popularitySanitizeProcessed++;
                        continue;
                    }

                    // 5. 构造 Prompt 调用大模型进行对齐
                    String currentMeaningsJson = JsonUtils.toJson(currentMeanings);
                    String dictCnMeaningsJson = JsonUtils.toJson(dictCnMeanings);

                    String systemPrompt = "你是一个词典释义对齐专家。你需要根据海词提供的单词释义频率数据，对我们系统现有的释义列表进行对齐，并识别缺失的高频释义。\n" +
                            "输入格式如下：\n" +
                            "1. word: 目标单词拼写。\n" +
                            "2. currentMeanings: 系统现有的释义项列表。每个释义包含 'id' (UUID)、'ciXing' (词性，如 n., v., adj. 等) 和 'meaning' (释义，可能包含多个以逗号/分号分隔的同义词)。\n" +
                            "3. dictCnMeanings: 海词的释义频率分布数据。包含海词各个释义的百分比（percent）和释义简称（sense）。\n" +
                            "\n" +
                            "你需要处理的逻辑：\n" +
                            "1. 词性与语义对齐：对同词性下的释义进行语义匹配。例如，海词中 sense 为“书” (n.)，系统现有释义为“n. 书，本子 (id: uuid1)”，那么它们语义一致，匹配成功。将该系统的 id 映射到对应的百分比，形如：{\"meaningItemId\": \"uuid1\", \"percent\": 87}。\n" +
                            "2. 累加与分合：如果系统现有的一个 id 对应了海词的多个 sense（如系统的 meaning 包含这两个 sense），请将海词的百分比相加后赋予该 id。如果反过来，请平均分配或分别映射。\n" +
                            "3. 缺失释义识别：如果在海词的释义中，有某个释义的百分比大于等于 10%，但在我们系统的 currentMeanings 中完全找不到对应的词义，则将该释义判定为【缺失的高频释义】。\n" +
                            "4. 对每个判定为【缺失的高频释义】，请你：\n" +
                            "   - 生成推荐的英文词性（pos，如 n., v., adj. 等）。\n" +
                            "   - 生成中文释义（meaning）。\n" +
                            "   - 提供 1 个非常实用、自然的英文例句（sentenceEn）及中文翻译（sentenceCn）。在英文例句和中文翻译中，对目标单词使用 <b>单词</b> 标签进行加粗高亮。\n" +
                            "5. 严格按照以下 JSON 格式返回，不要有任何 Markdown 标注或说明性文字：\n" +
                            "{\n" +
                            "  \"matches\": [\n" +
                            "    {\"meaningItemId\": \"uuid1\", \"percent\": 87}\n" +
                            "  ],\n" +
                            "  \"missing\": [\n" +
                            "    {\n" +
                            "      \"pos\": \"v.\",\n" +
                            "      \"meaning\": \"预订\",\n" +
                            "      \"percent\": 11,\n" +
                            "      \"sentenceEn\": \"We should <b>book</b> a table in advance.\",\n" +
                            "      \"sentenceCn\": \"我们应该提前<b>预订</b>一张桌子。\"\n" +
                            "    }\n" +
                            "  ]\n" +
                            "}";

                    String userPrompt = String.format("{\"word\": \"%s\", \"currentMeanings\": %s, \"dictCnMeanings\": %s}",
                            spell, currentMeaningsJson, dictCnMeaningsJson);

                    String aiOutput = aiBo.generateText(systemPrompt, userPrompt);
                    if (aiOutput != null) {
                        aiOutput = aiOutput.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();
                    }

                    Map<String, Object> aiRes = JsonUtils.parseMap(aiOutput);
                    if (aiRes == null) {
                        logger.warn("大模型返回结果解析失败: spell={}", spell);
                        popularitySanitizeProcessed++;
                        continue;
                    }

                    // 6. 处理匹配上的释义，更新 popularity_percent
                    List<?> matches = (List<?>) aiRes.get("matches");
                    if (matches != null) {
                        for (Object matchObj : matches) {
                            if (matchObj instanceof Map) {
                                Map<?, ?> matchMap = (Map<?, ?>) matchObj;
                                String meaningItemId = (String) matchMap.get("meaningItemId");
                                Object percentVal = matchMap.get("percent");
                                if (meaningItemId != null && percentVal != null) {
                                    int percent = ((Number) percentVal).intValue();
                                    MeaningItem mi = meaningItemBo.findById(meaningItemId);
                                    if (mi != null) {
                                        mi.setPopularityPercent(percent);
                                        meaningItemBo.updateEntity(mi);
                                        // 记录系统同步日志
                                        sysDbSyncBo.logOperation(meaningItemBo.toDto(mi), "UPDATE", "meaning_item", meaningItemId, JsonUtils.toJson(meaningItemBo.toDto(mi)));
                                    }
                                }
                            }
                        }
                    }

                    // 7. 处理缺失的高频释义补全
                    List<?> missingList = (List<?>) aiRes.get("missing");
                    if (missingList != null) {
                        Word word = wordBo.findById(wordId);
                        for (Object missingObj : missingList) {
                            if (missingObj instanceof Map) {
                                Map<?, ?> missingMap = (Map<?, ?>) missingObj;
                                String pos = (String) missingMap.get("pos");
                                String meaning = (String) missingMap.get("meaning");
                                Object percentVal = missingMap.get("percent");
                                int percent = percentVal != null ? ((Number) percentVal).intValue() : 0;
                                
                                // 只有百分比大于等于 10% 且词性与释义不为空才进行补全
                                if (percent >= 10 && pos != null && meaning != null && word != null) {
                                    // AI 偶发违约：一条释义里用分号挤进了多个义项，按约定拆成多条独立释义项
                                    List<String> meaningParts = Util.splitMeanings(meaning);
                                    if (meaningParts.size() > 1) {
                                        logger.warn("AI 返回的释义使用了分号，已拆分为 {} 条义项 - word: {}, meaning: {}",
                                                meaningParts.size(), spell, meaning);
                                    }
                                    for (int p = 0; p < meaningParts.size(); p++) {
                                        // 插入 MeaningItem
                                        MeaningItem mi = new MeaningItem();
                                        mi.setWord(word);
                                        mi.setCiXing(pos);
                                        mi.setMeaning(meaningParts.get(p));
                                        mi.setPopularityPercent(percent);
                                        mi.setOwner(systemUser);
                                        mi.setDict(commonDict);
                                        meaningItemBo.createEntity(mi);

                                        // 记录同步日志
                                        sysDbSyncBo.logOperation(meaningItemBo.toDto(mi), "INSERT", "meaning_item", mi.getId(), JsonUtils.toJson(meaningItemBo.toDto(mi)));

                                        // 插入 Sentence 例句（AI 只提供了一条例句，归属首条义项）
                                        String sentenceEn = (String) missingMap.get("sentenceEn");
                                        String sentenceCn = (String) missingMap.get("sentenceCn");
                                        if (p == 0 && sentenceEn != null && !sentenceEn.trim().isEmpty()) {
                                            Sentence sentence = new Sentence();
                                            sentence.setEnglish(sentenceEn);
                                            sentence.setChinese(sentenceCn);
                                            sentence.setWordMeaning(meaningParts.get(p));
                                            sentence.setPartOfSpeech(pos);
                                            sentence.setMeaningItem(mi);
                                            sentence.setNeedTts(true); // 触发 TTS 定时任务生成语音
                                            sentence.setTheType("waitting_tts");
                                            sentence.setOwner(systemUser);
                                            sentence.setAuthor(systemUser);
                                            sentence.setEnglishDigest(Util.makeSentenceDigest(sentenceEn));

                                            sentenceBo.createEntity(sentence);
                                            // 记录例句同步日志
                                            sysDbSyncBo.logOperation(sentence, "INSERT", "sentence", sentence.getId(), JsonUtils.toJson(sentenceBo.toDto(sentence)));
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 8. 重新校准该单词下的所有释义的 popularity 序号
                    List<MeaningItemDto> allMeanings = meaningItemBo.findMeaningsByWordAndDict(wordId, "0");
                    if (allMeanings.size() > 1) {
                        // 按 popularityPercent 降序排列 (null 的排到最后)
                        allMeanings.sort((o1, o2) -> {
                            Integer p1 = o1.getPopularityPercent();
                            Integer p2 = o2.getPopularityPercent();
                            if (p1 == null && p2 == null) return 0;
                            if (p1 == null) return 1;
                            if (p2 == null) return -1;
                            return p2.compareTo(p1); // 降序
                        });

                        // 重新更新其 popularity 值
                        for (int i = 0; i < allMeanings.size(); i++) {
                            MeaningItemDto dto = allMeanings.get(i);
                            int newSeq = i + 1;
                            if (dto.getPopularity() != newSeq) {
                                MeaningItem mi = meaningItemBo.findById(dto.getId());
                                if (mi != null) {
                                    mi.setPopularity(newSeq);
                                    meaningItemBo.updateEntity(mi);
                                    // 记录系统同步日志
                                    sysDbSyncBo.logOperation(meaningItemBo.toDto(mi), "UPDATE", "meaning_item", mi.getId(), JsonUtils.toJson(meaningItemBo.toDto(mi)));
                                }
                            }
                        }
                    }

                } catch (Exception e) {
                    logger.error("处理单词 [{}] 时发生异常", spell, e);
                }

                popularitySanitizeProcessed++;
                // 每次请求后休息 1.5 秒以防被海词封锁 IP
                try {
                    Thread.sleep(1500);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    popularitySanitizeLog = "清洗任务在等待中被中断。";
                    break;
                }
            }

            popularitySanitizeLog = String.format("清洗任务完成。共处理 %d 个单词。", popularitySanitizeProcessed);
            logger.info("单词常用度清洗完成。总处理数: {}", popularitySanitizeProcessed);

        } catch (Exception e) {
            logger.error("执行常用度清洗任务失败", e);
            popularitySanitizeLog = "执行清洗任务失败: " + e.getMessage();
        }
    }

    /**
     * 清洗释义项中非法的分号分隔（由管理员点击触发，后台异步线程执行）。
     * <p>
     * 对每个含分号的释义项调用大模型判定分号两侧是「同一义项的近义复述」还是「不同义项」：
     * 近义则合并为一条（逗号连接），异义则拆成多条独立释义项。
     */
    public SystemHealthFixResult sanitizeMeaningSeparators() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isMeaningSanitizing) {
            errors.add("释义项清洗任务正在后台运行中，请勿重复触发。");
            fixed.add(String.format("当前进度: %d/%d。详情: %s",
                    meaningSanitizeProcessed, meaningSanitizeTotal, meaningSanitizeLog));
            return new SystemHealthFixResult(0, errors, fixed);
        }

        isMeaningSanitizing = true;
        meaningSanitizeTotal = 0;
        meaningSanitizeProcessed = 0;
        meaningSanitizeFixedCount = 0;
        meaningSanitizeLog = "准备扫描含分号的释义项...";

        new Thread(() -> {
            try {
                executeMeaningSeparatorSanitization();
            } finally {
                isMeaningSanitizing = false;
            }
        }).start();

        fixed.add("释义项清洗任务已成功在后台启动。");
        return new SystemHealthFixResult(0, errors, fixed);
    }

    /**
     * 获取释义项清洗状态及进度
     */
    public SystemHealthFixResult getMeaningSeparatorSanitizeStatus() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isMeaningSanitizing) {
            fixed.add(String.format("当前进度: %d/%d。已修复: %d 个释义项。详情: %s",
                    meaningSanitizeProcessed, meaningSanitizeTotal, meaningSanitizeFixedCount, meaningSanitizeLog));
            return new SystemHealthFixResult(1, errors, fixed);
        }
        if (meaningSanitizeTotal > 0) {
            fixed.add(String.format("释义项清洗完成。共处理 %d 个词条，共修复 %d 个释义项。",
                    meaningSanitizeTotal, meaningSanitizeFixedCount));
        } else {
            fixed.add("任务未运行。");
        }
        return new SystemHealthFixResult(0, errors, fixed);
    }

    private void executeMeaningSeparatorSanitization() {
        try {
            meaningSanitizeLog = "正在查询含分号的释义项...";
            String sql = "SELECT word_id, dict_id FROM meaning_item WHERE " + DIRTY_MEANING_SEPARATOR_SQL_WHERE
                    + " GROUP BY word_id, dict_id";
            List<Map<String, Object>> groups = namedParameterJdbcTemplate.queryForList(sql, new MapSqlParameterSource());
            meaningSanitizeTotal = groups.size();
            meaningSanitizeProcessed = 0;
            meaningSanitizeFixedCount = 0;
            meaningSanitizeLog = String.format("查询完成，共找到 %d 个待清洗词条。", meaningSanitizeTotal);
            logger.info("开始释义项清洗。待清洗词条数: {}", meaningSanitizeTotal);

            for (Map<String, Object> group : groups) {
                if (Thread.currentThread().isInterrupted()) {
                    meaningSanitizeLog = "清洗任务已被系统强行中断。";
                    break;
                }

                String wordId = (String) group.get("word_id");
                String dictId = (String) group.get("dict_id");
                Word word = wordBo.findById(wordId);
                if (word == null) {
                    logger.warn("释义项清洗跳过不存在的单词: wordId={}", wordId);
                    meaningSanitizeProcessed++;
                    continue;
                }

                meaningSanitizeLog = String.format("正在处理 [%s] (%d/%d)...",
                        word.getSpell(), meaningSanitizeProcessed + 1, meaningSanitizeTotal);
                try {
                    meaningSanitizeFixedCount += sanitizeMeaningsOfWord(word, dictId);
                } catch (Exception e) {
                    logger.error("清洗单词 [{}] 的释义项失败", word.getSpell(), e);
                }
                meaningSanitizeProcessed++;
            }

            meaningSanitizeLog = String.format("清洗完成。共处理 %d 个词条，共修复 %d 个释义项。",
                    meaningSanitizeProcessed, meaningSanitizeFixedCount);
            logger.info("释义项清洗完成: 词条数={}, 修复数={}", meaningSanitizeProcessed, meaningSanitizeFixedCount);
        } catch (Exception e) {
            logger.error("执行释义项清洗任务失败", e);
            meaningSanitizeLog = "执行清洗任务失败: " + e.getMessage();
        }
    }

    /**
     * 清洗一个单词在指定词典下的全部含分号释义项，返回修复的释义项条数。
     */
    private int sanitizeMeaningsOfWord(Word word, String dictId) throws Exception {
        List<MeaningItemDto> dirtyItems = new ArrayList<>();
        for (MeaningItemDto dto : meaningItemBo.findMeaningsByWordAndDict(word.getId(), dictId)) {
            if (Util.hasMeaningSeparator(dto.getMeaning())) {
                dirtyItems.add(dto);
            }
        }
        if (dirtyItems.isEmpty()) {
            return 0;
        }

        Map<String, String> actions = decideMeaningActions(word.getSpell(), dirtyItems);
        int fixedCount = 0;
        for (MeaningItemDto dto : dirtyItems) {
            List<String> parts = Util.splitMeanings(dto.getMeaning());
            if (parts.size() < 2) {
                continue;
            }
            String action = actions.get(dto.getId());
            if (action == null) {
                logger.warn("大模型未对该释义项给出判定，保持原样等待下次清洗: id={}, meaning={}", dto.getId(), dto.getMeaning());
                continue;
            }
            if ("split".equals(action)) {
                fixedCount += splitMeaningItem(dto, parts);
            } else {
                fixedCount += mergeMeaningItem(dto, parts);
            }
        }
        return fixedCount;
    }

    /**
     * 让大模型逐条判定分号两侧是近义复述（merge）还是不同义项（split）。
     * 判定失败时返回空 Map，调用方保持数据原样，不擅自猜测。
     */
    private Map<String, String> decideMeaningActions(String spell, List<MeaningItemDto> items) {
        String systemPrompt = "你是一个中文词典释义整理专家。系统约定：一条释义项只能承载一个义项，同一义项内的近义表达用逗号连接，不允许出现分号。\n"
                + "下面给出某个单词的若干条释义项，它们的释义文本内部用分号连接了多个表达。请逐条判断分号两侧属于哪种情况：\n"
                + "1. 同一义项的不同说法（近义复述）-> action = \"merge\"，表示应合并为一条并用逗号连接；\n"
                + "2. 不同的义项 -> action = \"split\"，表示应拆成多条独立释义项。\n"
                + "严格只返回 JSON，不要有任何 Markdown 标注或说明性文字，格式为：\n"
                + "{\"decisions\": [{\"id\": \"释义项id\", \"action\": \"merge\"}]}";

        StringBuilder itemsJson = new StringBuilder("[");
        for (MeaningItemDto dto : items) {
            if (itemsJson.length() > 1) {
                itemsJson.append(",");
            }
            itemsJson.append(String.format("{\"id\": \"%s\", \"ciXing\": \"%s\", \"meaning\": \"%s\"}",
                    dto.getId(), dto.getCiXing() == null ? "" : dto.getCiXing(), dto.getMeaning()));
        }
        itemsJson.append("]");

        Map<String, String> actions = new HashMap<>();
        String aiOutput = aiBo.generateText(systemPrompt, String.format("{\"word\": \"%s\", \"items\": %s}", spell, itemsJson));
        if (aiOutput != null) {
            aiOutput = aiOutput.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();
        }
        Map<String, Object> aiRes = JsonUtils.parseMap(aiOutput);
        if (aiRes == null) {
            logger.warn("释义项清洗：大模型返回结果解析失败, spell={}", spell);
            return actions;
        }
        List<?> decisions = (List<?>) aiRes.get("decisions");
        if (decisions == null) {
            return actions;
        }
        for (Object decisionObj : decisions) {
            if (decisionObj instanceof Map) {
                Map<?, ?> decisionMap = (Map<?, ?>) decisionObj;
                String id = (String) decisionMap.get("id");
                String action = (String) decisionMap.get("action");
                if (id != null && action != null) {
                    actions.put(id, action.trim().toLowerCase());
                }
            }
        }
        return actions;
    }

    /**
     * 近义合并：把分号分隔的多段用逗号连回一条释义项，并生成同步日志。
     */
    private int mergeMeaningItem(MeaningItemDto dto, List<String> parts) throws Exception {
        MeaningItem mi = meaningItemBo.findById(dto.getId());
        if (mi == null) {
            return 0;
        }
        mi.setMeaning(String.join("，", parts));
        meaningItemBo.updateEntity(mi);
        logMeaningItemChange(mi, "UPDATE");
        updateSentenceWordMeaning(mi);
        return 1;
    }

    /**
     * 异义拆分：首段保留在原释义项上，其余各段新建为独立释义项（继承词性、常用度与归属），并生成同步日志。
     */
    private int splitMeaningItem(MeaningItemDto dto, List<String> parts) throws Exception {
        MeaningItem first = meaningItemBo.findById(dto.getId());
        if (first == null) {
            return 0;
        }
        first.setMeaning(parts.get(0));
        meaningItemBo.updateEntity(first);
        logMeaningItemChange(first, "UPDATE");
        updateSentenceWordMeaning(first);

        int count = 1;
        for (int i = 1; i < parts.size(); i++) {
            MeaningItem extra = new MeaningItem();
            extra.setWord(first.getWord());
            extra.setDict(first.getDict());
            extra.setOwner(first.getOwner());
            extra.setCiXing(first.getCiXing());
            extra.setMeaning(parts.get(i));
            extra.setPopularity(first.getPopularity());
            extra.setPopularityPercent(first.getPopularityPercent());
            meaningItemBo.createEntity(extra);
            logMeaningItemChange(extra, "INSERT");
            count++;
        }
        return count;
    }

    /**
     * 按释义项归属写入端云同步日志（系统资源写 sys_db_log，用户私有资源写 user_db_log）。
     */
    private void logMeaningItemChange(MeaningItem mi, String operation) {
        MeaningItemDto dto = meaningItemBo.toDto(mi);
        String ownerId = mi.getOwner() != null ? mi.getOwner().getId() : null;
        if (Constants.SYS_USER_SYS_ID.equals(ownerId)) {
            sysDbSyncBo.logOperation(dto, operation, "meaning_item", mi.getId(), JsonUtils.toJson(dto));
        } else if (ownerId != null) {
            userDbSyncBo.logUserOperation(mi, ownerId, "meaning_item", operation, mi.getId(), JsonUtils.toJson(dto));
        }
    }

    /**
     * 释义文本变更后，同步回填其下例句的冗余字段 {@code word_meaning}。
     * <p>
     * 该字段是释义的副本，若不同步回填，例句会一直显示拆分前那条分号串。
     */
    private void updateSentenceWordMeaning(MeaningItem mi) throws Exception {
        String wordMeaning = mi.getMeaning();
        for (Sentence sentence : sentenceBo.findByMeaningItem(mi.getId())) {
            if (Objects.equals(sentence.getWordMeaning(), wordMeaning)) {
                continue;
            }
            sentence.setWordMeaning(wordMeaning);
            sentenceBo.updateEntity(sentence);

            String ownerId = sentence.getOwner() != null ? sentence.getOwner().getId() : null;
            String record = JsonUtils.toJson(sentenceBo.toDto(sentence));
            if (Constants.SYS_USER_SYS_ID.equals(ownerId)) {
                sysDbSyncBo.logOperation(sentence, "UPDATE", "sentence", sentence.getId(), record);
            } else if (ownerId != null) {
                userDbSyncBo.logUserOperation(sentence, ownerId, "sentence", "UPDATE", sentence.getId(), record);
            }
        }
    }

    /**
     * 重生成含占位缩写（sb / sth）的发音（后台异步线程执行）。
     * <p>
     * 这些拼写里的 sb/sth 会被 TTS 逐字母朗读（"ess-bee slash ess-tee-aitch"），
     * 现在已经按 sb=somebody、sth=something、斜线="or" 展开后再送合成，
     * 但存量音频文件还是老的，必须强制覆盖重生成：
     * <ul>
     *   <li>单词：重新生成 3 个变体音频（无后缀 / _uk / _us），并 bump update_time —— 客户端音频 URL 带
     *       {@code ?v=updateTime}，updateTime 一变缓存即失效。</li>
     *   <li>例句：置为待合成状态，交给既有的 TtsTask 重新合成（写回同一个 digest 文件）。</li>
     * </ul>
     */
    public SystemHealthFixResult regenerateAbbreviationSounds() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isAbbreviationSoundRegenerating) {
            errors.add("缩写发音重生成任务正在后台运行中，请勿重复触发。");
            fixed.add(describeAbbreviationSoundProgress());
            return new SystemHealthFixResult(0, errors, fixed);
        }

        isAbbreviationSoundRegenerating = true;
        abbreviationSoundTotal = 0;
        abbreviationSoundProcessed = 0;
        abbreviationSoundRegeneratedCount = 0;
        abbreviationSoundLog = "准备扫描含 sb/sth 的单词与例句...";

        new Thread(() -> {
            try {
                executeAbbreviationSoundRegeneration();
            } finally {
                isAbbreviationSoundRegenerating = false;
            }
        }).start();

        fixed.add("缩写发音重生成任务已成功在后台启动。");
        return new SystemHealthFixResult(0, errors, fixed);
    }

    /**
     * 获取缩写发音重生成任务的状态及进度
     */
    public SystemHealthFixResult getAbbreviationSoundRegenerateStatus() {
        List<String> fixed = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        if (isAbbreviationSoundRegenerating) {
            fixed.add(describeAbbreviationSoundProgress());
            return new SystemHealthFixResult(1, errors, fixed);
        }
        if (abbreviationSoundTotal > 0) {
            fixed.add(String.format("缩写发音重生成完成。共处理 %d 项，成功重生成 %d 项。",
                    abbreviationSoundProcessed, abbreviationSoundRegeneratedCount));
        } else {
            fixed.add("任务未运行。");
        }
        return new SystemHealthFixResult(0, errors, fixed);
    }

    private String describeAbbreviationSoundProgress() {
        return String.format("%s (%d/%d)", abbreviationSoundLog,
                abbreviationSoundProcessed, abbreviationSoundTotal);
    }

    private void executeAbbreviationSoundRegeneration() {
        try {
            abbreviationSoundLog = "正在查询含 sb/sth 的单词与例句...";
            List<Map<String, Object>> words = namedParameterJdbcTemplate.queryForList(
                    "SELECT id FROM word WHERE " + abbreviationSqlWhere("spell"), new MapSqlParameterSource());
            List<String> sentenceIds = namedParameterJdbcTemplate.queryForList(
                    "SELECT id FROM sentence WHERE " + abbreviationSqlWhere("english") + " AND english_digest IS NOT NULL",
                    new MapSqlParameterSource(), String.class);
            abbreviationSoundTotal = words.size() + sentenceIds.size();
            abbreviationSoundProcessed = 0;
            abbreviationSoundRegeneratedCount = 0;
            abbreviationSoundLog = String.format("查询完成：%d 个单词、%d 条例句待重生成。", words.size(), sentenceIds.size());
            logger.info("开始重生成缩写发音。单词数={}, 例句数={}", words.size(), sentenceIds.size());

            int consecutiveFailures = 0;
            for (Map<String, Object> word : words) {
                if (Thread.currentThread().isInterrupted()) {
                    abbreviationSoundLog = "任务已被系统强行中断。";
                    break;
                }
                String wordId = (String) word.get("id");
                try {
                    if (wordBo.regeneratePronunciation(wordId)) {
                        abbreviationSoundRegeneratedCount++;
                        consecutiveFailures = 0;
                    } else if (++consecutiveFailures >= 20) {
                        abbreviationSoundLog = "连续 20 个单词发音全部生成失败，已中止（请检查发音服务是否可用）。";
                        logger.error("缩写发音重生成连续失败，提前中止");
                        break;
                    }
                } catch (Exception e) {
                    logger.error("重生成单词发音失败: wordId=" + wordId, e);
                }
                abbreviationSoundProcessed++;
                abbreviationSoundLog = "正在重生成单词发音...";
            }

            abbreviationSoundLog = "正在标记待重合成的例句...";
            for (String sentenceId : sentenceIds) {
                if (Thread.currentThread().isInterrupted()) {
                    abbreviationSoundLog = "任务已被系统强行中断。";
                    break;
                }
                try {
                    Sentence sentence = sentenceBo.findById(sentenceId);
                    if (sentence != null) {
                        // 交给既有的 TtsTask 重新合成：它会用展开后的文本，并覆盖同一个 digest 音频文件
                        sentence.setNeedTts(true);
                        sentence.setTheType("waitting_tts");
                        sentenceBo.updateEntity(sentence);
                        sysDbSyncBo.logOperation(sentence, "UPDATE", "sentence", sentenceId,
                                JsonUtils.toJson(sentenceBo.toDto(sentence)));
                        abbreviationSoundRegeneratedCount++;
                    }
                } catch (Exception e) {
                    logger.error("标记例句待重合成失败: sentenceId=" + sentenceId, e);
                }
                abbreviationSoundProcessed++;
            }

            abbreviationSoundLog = String.format("完成。共处理 %d 项，成功 %d 项。例句音频将由 TTS 定时任务陆续重新合成。",
                    abbreviationSoundProcessed, abbreviationSoundRegeneratedCount);
            logger.info("缩写发音重生成完成: 处理={}, 成功={}", abbreviationSoundProcessed, abbreviationSoundRegeneratedCount);
        } catch (Exception e) {
            logger.error("执行缩写发音重生成任务失败", e);
            abbreviationSoundLog = "执行任务失败: " + e.getMessage();
        }
    }

    /**
     * 英语占位缩写（sb / sth 及其所有格）的 SQL 匹配条件
     */
    private static String abbreviationSqlWhere(String column) {
        return "(" + column + " ~* '\\y(sb|sth)\\y')";
    }

    private Map<String, Object> parseChartData(String html, String patternStr) {
        Pattern pattern = Pattern.compile(patternStr);
        Matcher matcher = pattern.matcher(html);
        if (matcher.find()) {
            String encodedData = matcher.group(1);
            try {
                String decodedJson = URLDecoder.decode(encodedData, "UTF-8");
                return JsonUtils.parseMap(decodedJson);
            } catch (Exception e) {
                logger.error("解析 Chart 数据失败", e);
            }
        }
        return null;
    }
}
