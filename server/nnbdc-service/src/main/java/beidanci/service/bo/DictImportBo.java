package beidanci.service.bo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import beidanci.api.model.WordDto;
import beidanci.api.model.MeaningItemDto;
import beidanci.service.po.*;
import beidanci.service.po.DictWordId;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import beidanci.util.Constants;
import okhttp3.OkHttpClient;
import okhttp3.Request;

import java.io.File;
import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 词典导入业务类
 * 实现系统级和用户级词典的自动化导入与 AI 资源补全
 */
@Service
public class DictImportBo {

    private static final Logger logger = LoggerFactory.getLogger(DictImportBo.class);

    @Autowired
    private AiBo aiBo;

    @Autowired
    private ImportTaskBo importTaskBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    @Autowired
    private SentenceBo sentenceBo;

    @Autowired
    private DictWordBo dictWordBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private UserDbSyncBo userDbSyncBo;

    @Autowired
    private UserBo userBo;

    @Autowired
    private SynonymBo synonymBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    @Autowired
    private DictBo dictBo;

    @Autowired
    private WordImageBo wordImageBo;

    @Autowired
    private LearningDictBo learningDictBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private GameHallBo gameHallBo;

    /**
     * 异步执行导入任务
     *
     * @param taskId 任务ID
     */
    @Async
    public void executeImportTask(String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) return;

        TaskStatistics stats = new TaskStatistics();
        try {
            task.setStatus("RUNNING");
            importTaskBo.updateEntity(task);

            Map<String, Object> config = JsonUtils.parseMap(task.getConfig());
            boolean isSystemImport = (boolean) config.getOrDefault("isSystemImport", false);
            boolean generateWordImage = config.containsKey("generateWordImage") ? (boolean) config.get("generateWordImage") : false;
            String dictId = (String) config.get("dictId");
            String dictName = (String) config.get("dictName");
            String domain = (String) config.get("domain");
            @SuppressWarnings("unchecked")
            List<String> rawWords = (List<String>) config.get("words"); // 场景2：仅单词
            @SuppressWarnings("unchecked")
            List<Map<String, String>> wordsWithMeanings = (List<Map<String, String>>) config.get("wordsWithMeanings"); // 场景3

            int total = rawWords != null ? rawWords.size() : wordsWithMeanings.size();
            task.setTotalWords(total);
            importTaskBo.updateEntity(task);

            // 如果是系统导入且缺少dictId但给定了dictName，尝试按名称查找或新建词典
            if (isSystemImport && (dictId == null || dictId.isEmpty()) && dictName != null && !dictName.trim().isEmpty()) {
                User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
                Dict existingDict = dictBo.findByName(dictName.trim());
                if (existingDict != null) {
                    dictId = existingDict.getId();
                    if (domain != null && !domain.isEmpty()) {
                        existingDict.setDomain(domain);
                        dictBo.updateEntity(existingDict);
                    }
                } else {
                    Dict newDict = new Dict();
                    newDict.setWordCount(0);
                    newDict.setIsReady(true);
                    newDict.setIsShared(true); // 系统词库默认公开且可用
                    newDict.setVisible(true);
                    newDict.setEditable(false);
                    newDict.setDeletable(false); // 防止非系统用户删除
                    newDict.setPopularityLimit(10);
                    newDict.setName(dictName.trim());
                    if (domain != null && !domain.isEmpty()) {
                        newDict.setDomain(domain);
                    }
                    newDict.setOwner(systemUser);
                    dictBo.createEntity(newDict);
                    
                    beidanci.service.po.LearningDictId ldId = new beidanci.service.po.LearningDictId(systemUser.getId(), newDict.getId());
                    beidanci.service.po.LearningDict learningDict = new beidanci.service.po.LearningDict(ldId, newDict, systemUser, false, true);
                    learningDictBo.createEntity(learningDict);

                    dictId = newDict.getId();
                    
                    try {
                        beidanci.api.model.DictDto dictDto = dictBo.toDto(newDict);
                        sysDbSyncBo.logOperation("INSERT", "dict", dictId, JsonUtils.toJson(dictDto));
                    } catch (Exception e) {
                        logger.warn("生成新建系统词典同步日志失败", e);
                    }
                }
            }

            // 更新 config 中的 dictId 以便前端展示详情时能够使用 priorityDictId 读取此字典释义
            if (dictId != null && !dictId.isEmpty()) {
                config.put("dictId", dictId);
                task.setConfig(JsonUtils.toJson(config));
            }
            importTaskBo.updateEntity(task);

            boolean generateShuffledVersion = config.containsKey("generateShuffledVersion") ? (boolean) config.get("generateShuffledVersion") : false;

            String preferredVoices = (String) config.get("ttsVoices");

            if (isSystemImport) {
                processSystemImport(task, dictId, dictName, domain, rawWords, generateWordImage, preferredVoices, stats);
            } else if (rawWords != null) {
                processUserImportWordsOnly(task, dictId, dictName, domain, rawWords, generateWordImage, preferredVoices, stats);
            } else {
                processUserImportWithMeanings(task, dictId, dictName, domain, wordsWithMeanings, generateWordImage, preferredVoices, stats);
            }

            // 更新原词典的单词总数，并下发 UPDATE 同步日志通知客户端
            if (dictId != null && !dictId.isEmpty()) {
                Dict mainDict = dictBo.findById(dictId);
                if (mainDict != null) {
                    List<DictWord> currentWords = dictWordBo.findDictWordsByDictId(dictId);
                    int finalCount = (currentWords != null) ? currentWords.size() : 0;
                    mainDict.setWordCount(finalCount);
                    dictBo.updateEntity(mainDict);
                    if (isSystemImport) {
                        try {
                            sysDbSyncBo.logOperation("UPDATE", "dict", dictId, JsonUtils.toJson(dictBo.toDto(mainDict)));
                        } catch (Exception e) {
                            logger.warn("生成更新词典同步日志失败", e);
                        }
                    }
                }
            }

            // 处理乱序版
            if (isSystemImport && generateShuffledVersion && dictId != null) {
                try {
                    String shuffledDictName = dictBo.findById(dictId).getName() + " (乱序版)";
                    Dict existingShuffledDict = dictBo.findByName(shuffledDictName);
                    String shuffledDictId;
                    if (existingShuffledDict != null) {
                        shuffledDictId = existingShuffledDict.getId();
                        existingShuffledDict.setDomain(null);
                        existingShuffledDict.setBaseDictId(dictId);
                        existingShuffledDict.setSortAlg("md5");
                        dictBo.updateEntity(existingShuffledDict);
                    } else {
                        User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
                        Dict newDict = new Dict();
                        newDict.setWordCount(0);
                        newDict.setIsReady(true);
                        newDict.setIsShared(true); 
                        newDict.setVisible(true);
                        newDict.setEditable(false);
                        newDict.setDeletable(false);
                        newDict.setPopularityLimit(10);
                        newDict.setName(shuffledDictName);
                        newDict.setDomain(null); // 衍生词典的 domain 为 null, 表示跟随原词典
                        newDict.setBaseDictId(dictId);
                        newDict.setSortAlg("md5");
                        newDict.setOwner(systemUser);
                        dictBo.createEntity(newDict);
                        
                        beidanci.service.po.LearningDictId ldId = new beidanci.service.po.LearningDictId(systemUser.getId(), newDict.getId());
                        beidanci.service.po.LearningDict learningDict = new beidanci.service.po.LearningDict(ldId, newDict, systemUser, false, true);
                        learningDictBo.createEntity(learningDict);

                        shuffledDictId = newDict.getId();
                        
                        try {
                            beidanci.api.model.DictDto dictDto = dictBo.toDto(newDict);
                            sysDbSyncBo.logOperation("INSERT", "dict", shuffledDictId, JsonUtils.toJson(dictDto));
                        } catch (Exception e) {
                            logger.warn("生成新建乱序版词典同步日志失败", e);
                        }
                    }
                    
                    // 此时不真正插入 DictWord 记录，因为通过客户端本地“软绑定”随时可计算出乱序
                    // 只需令该空壳词典的 wordCount 与源同步即可
                    List<DictWord> originalDictWords = dictWordBo.findDictWordsByDictId(dictId);
                    int wc = (originalDictWords != null) ? originalDictWords.size() : 0;
                    Dict sDict = dictBo.findById(shuffledDictId);
                    sDict.setWordCount(wc);
                    dictBo.updateEntity(sDict);
                    try {
                        sysDbSyncBo.logOperation("UPDATE", "dict", shuffledDictId, JsonUtils.toJson(dictBo.toDto(sDict)));
                    } catch (Exception e) {
                        logger.warn("生成更新乱序版词典同步日志失败", e);
                    }

                } catch (Exception e) {
                    logger.error("生成乱序版本词书壳子失败!", e);
                }
            }

            // 处理词书与分组及大厅的直接绑定
            if (isSystemImport && dictId != null) {
                String targetDictGroupId = (String) config.get("targetDictGroupId");
                List<?> rawGameHallIds = (List<?>) config.get("targetGameHallIds");
                
                if (targetDictGroupId != null && !targetDictGroupId.trim().isEmpty()) {
                    linkDictToGroup(dictId, targetDictGroupId);
                }
                
                if (rawGameHallIds != null && !rawGameHallIds.isEmpty()) {
                    for (Object idObj : rawGameHallIds) {
                        if (idObj instanceof String) {
                            String targetGameHallId = (String) idObj;
                            if (!targetGameHallId.trim().isEmpty()) {
                                GameHall hall = gameHallBo.findById(targetGameHallId);
                                if (hall != null && hall.getDictGroup() != null) {
                                    linkDictToGroup(dictId, hall.getDictGroup().getId());
                                }
                            }
                        }
                    }
                }
                
                if (generateShuffledVersion) {
                    String shuffledDictName = dictBo.findById(dictId).getName() + " (乱序版)";
                    Dict sDict = dictBo.findByName(shuffledDictName);
                    if (sDict != null) {
                        if (targetDictGroupId != null && !targetDictGroupId.trim().isEmpty()) {
                            linkDictToGroup(sDict.getId(), targetDictGroupId);
                        }
                    }
                }
            }

            task = importTaskBo.findById(taskId); // 重新加载以防状态冲突
            task.setResults(JsonUtils.toJson(stats));
            
            // 执行导入后的健康检查: 打印无例句的释义项
            if (isSystemImport && dictId != null && !dictId.isEmpty()) {
                List<String> meaningIdsWithoutSentences = sentenceBo.findMeaningsWithoutSentences(dictId);
                if (meaningIdsWithoutSentences != null && !meaningIdsWithoutSentences.isEmpty()) {
                    String warnStr = "【系统健康检查警告】 发现本词典中存在 " + meaningIdsWithoutSentences.size() + " 个缺少关联例句的释义项! ID=" + meaningIdsWithoutSentences.toString();
                    logger.warn(warnStr);
                    task.setLog((task.getLog() == null ? "" : task.getLog() + "\n") + warnStr);
                    stats.wordDetails.add(new WordDetail("*HEALTH_CHECK*", "WARNING", "存在缺少例句的释义项", null));
                    task.setResults(JsonUtils.toJson(stats));
                }
            }

            task.setStatus("COMPLETED");
            importTaskBo.updateEntity(task);
        } catch (Exception e) {
            logger.error("词典导入任务失败: " + taskId, e);
            task.setStatus("FAILED");
            task.setResults(JsonUtils.toJson(stats));
            String errorMsg = e.getMessage() != null ? e.getMessage() : "未知错误";
            task.setLog((task.getLog() != null ? task.getLog() : "") + "\nERROR: " + errorMsg);
            try {
                importTaskBo.updateEntity(task);
            } catch (IllegalAccessException ignore) {
            }
        }
    }

    private void processSystemImport(ImportTask task, String dictId, String dictName, String domain, List<String> words, boolean generateWordImage, String preferredVoices, TaskStatistics stats) {
        User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
        for (int i = 0; i < words.size(); i++) {
            ImportTask curTask = importTaskBo.findById(task.getId());
            if (curTask != null && "CANCELED".equals(curTask.getStatus())) {
                throw new RuntimeException("导入任务已被手动终止");
            }
            String line = words.get(i).trim();
            if (line.isEmpty()) continue;
            String spell = line;
            String manualMeaning = null;
            if (line.contains("|")) {
                String[] parts = line.split("\\|", 2);
                spell = parts[0].trim();
                manualMeaning = parts[1].trim();
                if (manualMeaning.isEmpty()) manualMeaning = null;
            }
            try {
                processSingleWord(spell, manualMeaning, true, systemUser, dictId, dictName, domain, generateWordImage, preferredVoices, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWordsOnly(ImportTask task, String dictId, String dictName, String domain, List<String> words, boolean generateWordImage, String preferredVoices, TaskStatistics stats) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            ImportTask curTask = importTaskBo.findById(task.getId());
            if (curTask != null && "CANCELED".equals(curTask.getStatus())) {
                throw new RuntimeException("导入任务已被手动终止");
            }
            String spell = words.get(i).trim();
            try {
                processSingleWord(spell, null, false, owner, dictId, dictName, domain, generateWordImage, preferredVoices, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWithMeanings(ImportTask task, String dictId, String dictName, String domain, List<Map<String, String>> words, boolean generateWordImage, String preferredVoices, TaskStatistics stats) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            ImportTask curTask = importTaskBo.findById(task.getId());
            if (curTask != null && "CANCELED".equals(curTask.getStatus())) {
                throw new RuntimeException("导入任务已被手动终止");
            }
            Map<String, String> item = words.get(i);
            String spell = item.get("word").trim();
            String manualMeaning = item.get("meaning");
            try {
                processSingleWord(spell, manualMeaning, false, owner, dictId, dictName, domain, generateWordImage, preferredVoices, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processSingleWord(String spell, String manualMeaning, boolean isSystemDict, User user, String dictId, String dictName, String domain, boolean generateWordImage, String preferredVoices, TaskStatistics stats) throws Exception {
        Word word = wordBo.getWordBySpell(spell);
        boolean isNewWord = (word == null);
        String actionType = "ADDED";
        AiResult lastAiResult = null;

        if (isNewWord) {
            word = new Word();
            word.setSpell(spell);
            word.setPopularity(5); // 默认中等
            // 调用 AI 获取音标（及其它固有属性），对新词初始化无需在第一步请求配图，避免重复调用浪费资源
            lastAiResult = getAiResult(spell, null, null, false, null);
            word.setBritishPronounce(lastAiResult.phonetic);
            word.setAmericaPronounce(lastAiResult.phonetic);
            word.setPronounce(lastAiResult.phonetic);
            wordBo.createEntity(word);
            stats.addedWordCount++;
            stats.addedAudioCount++; // 统计单词发音资源

            // 新增单词全局可见，必须为客户端插入一条系统同步日志
            WordDto wordDto = new WordDto();
            org.springframework.beans.BeanUtils.copyProperties(word, wordDto);
            sysDbSyncBo.logOperation("INSERT", "word", word.getId(), beidanci.service.util.JsonUtils.toJson(wordDto));
            stats.addSyncLog("INSERT", "word");

            // 同步为通用兜底词书（ID="0"）添加关系并更新计数，以免触发数据不一致健康警告
            DictWord dw0 = new DictWord();
            dw0.setId(new beidanci.service.po.DictWordId(Constants.COMMON_DICT_ID, word.getId()));
            Dict commonDict = new Dict();
            commonDict.setId(Constants.COMMON_DICT_ID);
            dw0.setDict(commonDict);
            dw0.setWord(word);
            dw0.setSeq(dictWordBo.getMaxSeqNo(commonDict) + 1);
            dw0.setCreateTime(new Date());
            
            // 使用 try-catch 忽略数据库层面的触发器唯一键冲突
            try {
                dictWordBo.createEntity(dw0);
            } catch (Exception ignore) {
            }

            // 无论底层是否通过触发器创建了该记录，都必须为客户端插入一条系统同步日志，否则客户端不会拉取这条 dict_word ！
            beidanci.api.model.DictWordDto dwDto = new beidanci.api.model.DictWordDto();
            dwDto.setDictId(Constants.COMMON_DICT_ID);
            dwDto.setWordId(word.getId());
            dwDto.setSeq(dw0.getSeq());
            dwDto.setCreateTime(dw0.getCreateTime());
            sysDbSyncBo.logOperation("INSERT", "dict_word", Constants.COMMON_DICT_ID + "_" + word.getId(), beidanci.service.util.JsonUtils.toJson(dwDto));
            stats.addSyncLog("INSERT", "dict_word");

            // 更新 "0" 词书的 wordCount
            Dict dict0 = dictBo.findById(Constants.COMMON_DICT_ID);
            if (dict0 != null) {
                dict0.setWordCount(dict0.getWordCount() + 1);
                dictBo.updateEntity(dict0);
            } else {
                // 回退查找，防止在未提交事务中为空
                dict0 = new Dict();
                dict0.setId(Constants.COMMON_DICT_ID);
                dict0.setWordCount(dictWordBo.getMaxSeqNo(commonDict)); // fallback
            }
            
            // 同样必须同步 dict 表的变更
            beidanci.api.model.DictDto dictDto = new beidanci.api.model.DictDto();
            org.springframework.beans.BeanUtils.copyProperties(dict0, dictDto);
            sysDbSyncBo.logOperation("UPDATE", "dict", Constants.COMMON_DICT_ID, beidanci.service.util.JsonUtils.toJson(dictDto));
            stats.addSyncLog("UPDATE", "dict");
        }

        if (word == null) {
            throw new RuntimeException("无法获取或创建单词对象: " + spell);
        }

        List<MeaningItemDto> existingMeaningsInDict = meaningItemBo.findMeaningsByWordAndDict(word.getId(), dictId);
        boolean isPrivateReusing = false;

        // 对于私有词典：如果当前词典已经有该词的资源，直接跳过生成，实现一致性和防重复
        if (!isSystemDict && !isNewWord && !existingMeaningsInDict.isEmpty()) {
            logger.info("单词 {} 在私人词典 {} 中已存在资源，直接重用（跳过生成）", spell, dictId);
            stats.skippedCount++;
            stats.wordDetails.add(new WordDetail(spell, "REUSED", null, null));
            isPrivateReusing = true;
        }

        // 无论单词是否刚创建，检查其发音文件是否存在，若不存在则补发音
        try {
            String pureSpell = spell.replaceAll("[^a-zA-Z]", "").toLowerCase();
            if (pureSpell.length() > 0) {
                String firstChar = pureSpell.substring(0, 1);
                java.io.File dir = new java.io.File(sysParamUtil.getSoundPath() + "/" + firstChar);
                if (!dir.exists()) dir.mkdirs();
                java.io.File soundFile = new java.io.File(dir, pureSpell + ".mp3");

                if (!soundFile.exists()) {
                    try {
                        String[] urlStrs = {
                            "http://dict.youdao.com/dictvoice?type=2&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                            "http://dict.youdao.com/dictvoice?type=1&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                            "http://dict.youdao.com/dictvoice?le=eng&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8")
                        };
                        
                        boolean success = false;
                        for (String urlStr : urlStrs) {
                            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(urlStr).openConnection();
                            conn.setRequestMethod("GET");
                            conn.setConnectTimeout(3000);
                            conn.setReadTimeout(5000);
                            
                            if (conn.getResponseCode() == 200) {
                                try (java.io.InputStream is = conn.getInputStream();
                                     java.io.FileOutputStream fos = new java.io.FileOutputStream(soundFile)) {
                                    byte[] buffer = new byte[4096];
                                    int bytesRead;
                                    while ((bytesRead = is.read(buffer)) != -1) {
                                        fos.write(buffer, 0, bytesRead);
                                    }
                                    fos.flush();
                                }
                                logger.info("通过真人词库补上了发音文件: " + soundFile.getAbsolutePath() + " using " + urlStr);
                                success = true;
                                break;
                            }
                        }
                        
                        if (!success) {
                            throw new RuntimeException("All youdao URLs returned 500/404.");
                        }
                    } catch (Exception e) {
                        logger.warn("从有道词典下载真人发音失败 (" + pureSpell + ")，自动回退使用大模型 TTS 合成降级补全: " + e.getMessage());
                        byte[] audioData = aiBo.generateSpeech(spell, preferredVoices).audioData;
                        if (audioData != null && audioData.length > 0) {
                            try (java.io.FileOutputStream fos = new java.io.FileOutputStream(soundFile)) {
                                fos.write(audioData);
                                fos.flush();
                            }
                            logger.info("通过 AI 大模型补上了缺失的单词发音文件: " + soundFile.getAbsolutePath());
                        }
                    }
                }
            }
        } catch (Exception e) {
            logger.error("生成单词发音失败: " + spell, e);
        }

        // 获取该词在所有词典中的现有释义（为了给 AI 提供上下文参考）
        List<MeaningItemDto> allExistingMeanings = meaningItemBo.findMeaningsByWord(word.getId());
        String contextMeanings = allExistingMeanings.stream()
                .map(m -> (m.getCiXing() != null ? m.getCiXing() : "") + " " + m.getMeaning())
                .collect(java.util.stream.Collectors.joining("; "));

        if (!isPrivateReusing) {
            boolean hasDomain = (domain != null && !domain.trim().isEmpty());
            String aiContext = hasDomain ? domain : null;

            if (isSystemDict) {
                // 系统词书，实现绝对一致性状态：无论何时导入，都存在对应的补充内容（按需生成）
                // 1. 确保通用词库("0")有该词的基础托底释放
                boolean hasCommonMeaning = allExistingMeanings.stream().anyMatch(m -> Constants.COMMON_DICT_ID.equals(m.getDictId()));
                if (!hasCommonMeaning) {
                    AiResult genericAiResult = getAiResult(spell, null, contextMeanings, generateWordImage, null);
                    saveExtrinsicResources(word, genericAiResult, Constants.SYS_USER_SYS_ID, Constants.COMMON_DICT_ID, preferredVoices, stats);
                    lastAiResult = genericAiResult;
                }
                
                // 2. 如果声明了专业领域，且当前关联词书并非通用库自身，则必须确保该词书有专有资源
                if (hasDomain && !Constants.COMMON_DICT_ID.equals(dictId)) {
                    boolean hasSpecializedMeaning = allExistingMeanings.stream().anyMatch(m -> dictId.equals(m.getDictId()));
                    if (!hasSpecializedMeaning) {
                        AiResult specializedAiResult = getAiResult(spell, null, contextMeanings, generateWordImage, aiContext);
                        saveExtrinsicResources(word, specializedAiResult, Constants.SYS_USER_SYS_ID, dictId, preferredVoices, stats);
                        lastAiResult = specializedAiResult;
                    }
                }
            } else {
                // 用户导入
                if (manualMeaning != null) {
                    // 场景 3：单词+外部释义 (私有)
                    lastAiResult = getAiResult(spell, manualMeaning, contextMeanings, generateWordImage, aiContext);
                    saveExtrinsicResources(word, lastAiResult, user.getId(), dictId, preferredVoices, stats);
                } else {
                    // 场景 2：仅单词
                    lastAiResult = getAiResult(spell, null, contextMeanings, generateWordImage, aiContext);
                    saveExtrinsicResources(word, lastAiResult, user.getId(), dictId, preferredVoices, stats);
                }
            }
        }

        // 维护词书与单词关系
        if (dictId != null) {
            Dict dict = new Dict();
            dict.setId(dictId);
            if (dictWordBo.findById(new DictWordId(dictId, word.getId())) == null) {
                DictWord dw = new DictWord();
                dw.setId(new DictWordId(dictId, word.getId()));
                dw.setDict(dict);
                dw.setWord(word);
                dw.setSeq(dictWordBo.getMaxSeqNo(dict) + 1);
                dw.setCreateTime(new Date());
                dictWordBo.createEntity(dw);
                stats.addedDictWordCount++;
                
                // 更新词书单词计数
                dict = dictBo.findById(dictId);
                if (dict != null) {
                    dict.setWordCount(dict.getWordCount() + 1);
                    dictBo.updateEntity(dict);
                }
            }
        }

        // ----- 生成单词卡通配图 -----
        if (generateWordImage && lastAiResult != null && lastAiResult.imagePrompts != null && !lastAiResult.imagePrompts.isEmpty()) {
            String pureSpell = spell.replaceAll("[^a-zA-Z]", "").toLowerCase();
            for (int i = 0; i < Math.min(2, lastAiResult.imagePrompts.size()); i++) {
                String imgPrompt = lastAiResult.imagePrompts.get(i);
                try {
                    String imgUrl = aiBo.generateImage(imgPrompt);
                    if (imgUrl != null && !imgUrl.isEmpty()) {
                        String fileName = pureSpell + "_" + java.util.UUID.randomUUID().toString() + ".jpg";
                        File wordImgDir = new File(sysParamUtil.getImageBaseDir(), "word");
                        if (!wordImgDir.exists()) {
                            wordImgDir.mkdirs();
                        }
                        File destFile = new File(wordImgDir, fileName);
                        
                        OkHttpClient client = new OkHttpClient.Builder()
                                .connectTimeout(java.time.Duration.ofSeconds(10))
                                .readTimeout(java.time.Duration.ofSeconds(60))
                                .build();
                        Request request = new Request.Builder().url(imgUrl).build();
                        
                        try (okhttp3.Response response = client.newCall(request).execute()) {
                            if (response.isSuccessful() && response.body() != null) {
                                File tempFile = new File(wordImgDir, fileName + ".tmp");
                                try (java.io.InputStream is = response.body().byteStream();
                                     java.io.FileOutputStream fos = new java.io.FileOutputStream(tempFile)) {
                                    byte[] buffer = new byte[8192];
                                    int bytesRead;
                                    while ((bytesRead = is.read(buffer)) != -1) {
                                        fos.write(buffer, 0, bytesRead);
                                    }
                                }
                                
                                // 压缩图片，将其缩放至不大于 512x512（保持纵横比），使用 JPEG 压缩存储
                                beidanci.service.util.MyImage.resizeImage(tempFile, destFile, 512, 512, "JPEG", true);
                                tempFile.delete();
                                WordImage wordImage = new WordImage();
                                wordImage.setWord(word);
                                wordImage.setImageFile(fileName);
                                wordImage.setHand(0);
                                wordImage.setFoot(0);
                                wordImage.setAuthor(user);
                                wordImageBo.addWordImage(wordImage, user);
                                logger.info("成功为单词 {} 生成并保存配图，文件: {}", spell, destFile.getAbsolutePath());
                            } else {
                                logger.error("下载单词配图失败: HTTP {}, {}", response.code(), imgUrl);
                            }
                        }
                    }
                } catch (Exception e) {
                    logger.error("为单词 " + spell + " 生成配图失败: " + imgPrompt, e);
                }
            }
        }
        
        stats.wordDetails.add(new WordDetail(spell, actionType, null, lastAiResult));
    }


    private void saveExtrinsicResources(Word word, AiResult aiResult, String ownerId, String dictId, String preferredVoices, TaskStatistics stats) {
        if (aiResult.meanings == null || aiResult.meanings.isEmpty()) {
            return;
        }

        for (int i = 0; i < aiResult.meanings.size(); i++) {
            AiMeaning am = aiResult.meanings.get(i);
            if (am.meaning == null || am.meaning.trim().isEmpty()) continue;

            MeaningItem meaning = new MeaningItem();
            meaning.setWord(word);
            meaning.setCiXing(am.pos);
            meaning.setMeaning(am.meaning.trim().replaceAll("[;；]", "，"));
            meaning.setPopularity(aiResult.popularity != null && aiResult.popularity > i ? aiResult.popularity - i : 1);
            
            User owner = new User();
            owner.setId(ownerId != null ? ownerId : Constants.SYS_USER_SYS_ID);
            meaning.setOwner(owner);

            if (dictId != null) {
                Dict dict = new Dict();
                dict.setId(dictId);
                meaning.setDict(dict);
            }
            meaningItemBo.createEntity(meaning);
            stats.addedMeaningCount++;

            // 记录同步日志
            if (Constants.SYS_USER_SYS_ID.equals(ownerId)) {
                sysDbSyncBo.logOperation("INSERT", "meaning_item", meaning.getId(), JsonUtils.toJson(meaningItemBo.toDto(meaning)));
                stats.addSyncLog("INSERT", "meaning_item");
            } else {
                userDbSyncBo.logUserOperation(ownerId, "meaning_item", "INSERT", meaning.getId(), JsonUtils.toJson(meaningItemBo.toDto(meaning)));
            }

            // 创建 Sentence
            if (am.sentenceEn != null && !am.sentenceEn.trim().isEmpty()) {
                Sentence sentence = new Sentence();
                sentence.setEnglish(am.sentenceEn);
                sentence.setChinese(am.sentenceCn);
                
                sentence.setWordMeaning(am.meaning.trim());
                sentence.setPartOfSpeech(am.pos);
                
                sentence.setMeaningItem(meaning);
                sentence.setNeedTts(true); // 标记需要生成音频
                sentence.setTheType("waitting_tts");
                if (preferredVoices != null && !preferredVoices.trim().isEmpty()) {
                    sentence.setTtsVoice(preferredVoices);
                }
                sentence.setEnglishDigest(beidanci.service.util.Util.makeSentenceDigest(am.sentenceEn));
                if (ownerId != null) {
                    sentence.setAuthor(owner);
                }
                sentenceBo.createEntity(sentence);
                stats.addedSentenceCount++;
                stats.addedAudioCount++; // 统计例句音频资源

                // 记录同步日志（句子为公共资源，使用sysDbSyncBo）
                sysDbSyncBo.logOperation("INSERT", "sentence", sentence.getId(), JsonUtils.toJson(sentenceBo.toDto(sentence)));
                if (Constants.SYS_USER_SYS_ID.equals(ownerId)) {
                    stats.addSyncLog("INSERT", "sentence");
                }
            }

            // 创建同义词
            if (am.synonyms != null && !am.synonyms.isEmpty()) {
                for (String synSpell : am.synonyms) {
                    if (synSpell == null || synSpell.trim().isEmpty()) continue;
                    Word synWord = wordBo.getWordBySpell(synSpell.trim());
                    if (synWord != null) {
                        Synonym synonym = new Synonym();
                        SynonymId sid = new SynonymId();
                        sid.setMeaningItemId(meaning.getId());
                        sid.setWordId(synWord.getId());
                        synonym.setId(sid);
                        synonym.setMeaningItem(meaning);
                        synonym.setCreateTime(new Date());
                        synonymBo.createEntity(synonym);
                        stats.addedSynonymCount++;
                    }
                }
            }
        }
    }

    private AiResult getAiResult(String spell, String manualMeaning, String context, boolean generateWordImage, String dictNameContext) {
        String imageRule = generateWordImage 
                ? "6. IMAGE GENERATION: ONLY generate image prompts (1 or 2) if the word is highly visual, such as a physical object, animal, clear physical action, or a visually representable adjective/emotion (e.g., 'apple', 'dog', 'run', 'happy', 'fast'). DO NOT generate images for proper nouns, names, highly abstract concepts, adverbs, or grammar words (e.g., 'the', 'kerry', 'john', 'therefore', 'consider', 'very'). For all unsuitable words, firmly return an empty array [] for imagePrompts. If you DO generate, use clean, flat vector art style (start with 'A clean flat vector art style illustration of...'). DO NOT include any text, letters, UI elements, or the word itself in the image."
                : "6. IMAGE GENERATION: DO NOT generate ANY image prompts. Keep the imagePrompts array strictly empty [].";

        String systemPrompt = "You are a professional English dictionary assistant. Return JSON only. " +
                "IMPORTANT RULES:\n" +
                "1. Generate a list of 'meanings'. Each meaning MUST represent a distinct part of speech (pos) or distinct sense.\n" +
                "2. 'pos' field MUST be abbreviations (e.g., n., v., adj., adv.).\n" +
                "3. 'meaning' field MUST be in Chinese. Group closely related translations using COMMAS (e.g., '有, 拥有'), DO NOT use semicolons. Separate drastically different concepts into distinct meaning items.\n" +
                "4. For EACH meaning item, provide EXACTLY ONE highly practical, natural, and grammatically PERFECT example sentence (sentenceEn & sentenceCn).\n" +
                "5. Use <b>word</b> in BOTH sentenceEn and sentenceCn to highlight the vocabulary word and its Chinese translation respectively.\n" +
                "6. CRITICAL GRAMMAR RULE: Pay attention to 'a' vs 'an' articles when highlighting. It should be 'an <b>apple</b>', never 'a <b>apple</b>'!\n" +
                imageRule;
        StringBuilder userPrompt = new StringBuilder();
        userPrompt.append(String.format("Generating data for word '%s'. ", spell));
        
        if (dictNameContext != null && !dictNameContext.trim().isEmpty()) {
            userPrompt.append(String.format("\nTHIS IS A SPECIALIZED DOMAIN DICTIONARY: 《%s》. YOU MUST TAILOR THE MEANINGS, PART OF SPEECH, AND EXAMPLE SENTENCE STRICTLY TO THIS PROFESSIONAL/DOMAIN CONTEXT. ", dictNameContext));
        }

        if (context != null && !context.trim().isEmpty()) {
            userPrompt.append(String.format("\nExisting meanings for reference: [%s]. Try to provide better or complementary info if needed. ", context));
        }

        if (manualMeaning == null) {
            userPrompt.append("Return in this exact JSON format: {\"phonetic\": \"/xxx/\", \"popularity\": 1-10, \"meanings\": [{\"pos\": \"n.\", \"meaning\": \"中文意思1\", \"sentenceEn\": \"...\", \"sentenceCn\": \"...\", \"synonyms\": [\"syn1\", \"syn2\"]}], \"imagePrompts\": [\"...\"]}. " +
                    "provide at most 3 common synonyms per meaning.");
        } else {
            userPrompt.append(String.format("Given manual meaning '%s', break it down if there are multiple parts of speech or drastically different senses, and generate an example sentence and synonyms for EACH. " +
                    "Return: {\"phonetic\": \"/xxx/\", \"popularity\": 5, \"meanings\": [{\"pos\": \"n.\", \"meaning\": \"...\", \"sentenceEn\": \"...\", \"sentenceCn\": \"...\", \"synonyms\": [\"syn1\", \"syn2\"]}], \"imagePrompts\": [\"...\"]}.", 
                    manualMeaning));
        }

        String rawJson = aiBo.generateText(systemPrompt, userPrompt.toString());
        // 清理 AI 可能带的 Markdown 代码块标签
        rawJson = rawJson.replaceAll("```json", "").replaceAll("```", "").trim();
        Map<String, Object> map = JsonUtils.parseMap(rawJson);
        
        AiResult res = new AiResult();
        res.phonetic = (String) map.get("phonetic");
        res.popularity = (Integer) map.getOrDefault("popularity", 5);
        
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> meaningsList = (List<Map<String, Object>>) map.get("meanings");
        res.meanings = new java.util.ArrayList<>();
        if (meaningsList != null) {
            for (Map<String, Object> mObj : meaningsList) {
                AiMeaning am = new AiMeaning();
                am.pos = (String) mObj.get("pos");
                am.meaning = (String) mObj.get("meaning");
                am.sentenceEn = (String) mObj.get("sentenceEn");
                am.sentenceCn = (String) mObj.get("sentenceCn");
                
                @SuppressWarnings("unchecked")
                List<String> syn = (List<String>) mObj.get("synonyms");
                am.synonyms = syn;
                
                res.meanings.add(am);
            }
        }
        
        @SuppressWarnings("unchecked")
        List<String> imagePrompts = (List<String>) map.get("imagePrompts");
        res.imagePrompts = imagePrompts;
        
        return res;
    }

    public static class AiMeaning {
        public String pos;
        public String meaning;
        public String sentenceEn;
        public String sentenceCn;
        public List<String> synonyms;
    }

    public static class AiResult {
        public String phonetic;
        public Integer popularity;
        public List<AiMeaning> meanings;
        public List<String> imagePrompts;
    }

    public static class TaskStatistics {
        public List<WordDetail> wordDetails = new java.util.ArrayList<>();
        public int addedWordCount = 0;       // 新词入库
        public int addedDictWordCount = 0;   // 词书关联
        public int addedMeaningCount = 0;    // 释义项
        public int addedSentenceCount = 0;   // 例句
        public int deletedMeaningCount = 0;  // 删除释义
        public int deletedSentenceCount = 0; // 删除例句
        public int skippedCount = 0;         // 跳过已存在
        public int recreatedCount = 0;      // 触发重刷
        public int addedSynonymCount = 0;    // 同义词
        public int addedAudioCount = 0;      // 音频资源 (TTS/发音)
        public int addedImageCount = 0;      // 图像资源
        public Map<String, Map<String, Integer>> syncLogCounts = new java.util.HashMap<>(); // 实体类型 -> 操作类型 -> 数量
        public int errorCount = 0;           // 出错

        public void addSyncLog(String operation, String entity) {
            Map<String, Integer> opMap = syncLogCounts.computeIfAbsent(entity, k -> new java.util.HashMap<>());
            opMap.put(operation, opMap.getOrDefault(operation, 0) + 1);
        }
    }

    public static class WordDetail {
        public String spell;
        public String status;
        public String errorMsg;
        public AiResult aiResult;

        public WordDetail() {
        }

        public WordDetail(String spell, String status, String errorMsg, AiResult aiResult) {
            this.spell = spell;
            this.status = status;
            this.errorMsg = errorMsg;
            this.aiResult = aiResult;
        }
    }

    private void linkDictToGroup(String dictId, String groupId) {
        if (dictId == null || groupId == null) return;
        try {
            String checkSql = "SELECT count(*) FROM group_and_dict_link WHERE group_id = :groupId AND dict_id = :dictId";
            MapSqlParameterSource p = new MapSqlParameterSource()
                    .addValue("groupId", groupId)
                    .addValue("dictId", dictId);
            Integer count = namedParameterJdbcTemplate.queryForObject(checkSql, p, Integer.class);
            if (count == null || count == 0) {
                String insertSql = "INSERT INTO group_and_dict_link (group_id, dict_id) VALUES (:groupId, :dictId)";
                namedParameterJdbcTemplate.update(insertSql, p);
                
                // 记录系统同步日志，通知客户端拉取这层关系
                java.util.Map<String, String> linkDto = new java.util.HashMap<>();
                linkDto.put("groupId", groupId);
                linkDto.put("dictId", dictId);
                sysDbSyncBo.logOperation("INSERT", "group_and_dict_link", groupId + "_" + dictId, 
                        beidanci.service.util.JsonUtils.toJson(linkDto));
                        
                logger.info("系统词库导入：已自动建立词书关联: dictId={}, groupId={}", dictId, groupId);
            }
        } catch (Exception e) {
            logger.error("自动关联词库至分组时出错", e);
        }
    }
}
