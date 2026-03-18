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
import beidanci.util.Constants;

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
    private beidanci.service.util.SysParamUtil sysParamUtil;

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
            String dictId = (String) config.get("dictId");
            String strategy = (String) config.getOrDefault("strategy", "SKIP"); // SKIP, APPEND, RECREATE
            @SuppressWarnings("unchecked")
            List<String> rawWords = (List<String>) config.get("words"); // 场景2：仅单词
            @SuppressWarnings("unchecked")
            List<Map<String, String>> wordsWithMeanings = (List<Map<String, String>>) config.get("wordsWithMeanings"); // 场景3

            int total = rawWords != null ? rawWords.size() : wordsWithMeanings.size();
            task.setTotalWords(total);

            if (isSystemImport) {
                processSystemImport(task, dictId, rawWords, strategy, stats);
            } else if (rawWords != null) {
                processUserImportWordsOnly(task, dictId, rawWords, strategy, stats);
            } else {
                processUserImportWithMeanings(task, dictId, wordsWithMeanings, strategy, stats);
            }

            task = importTaskBo.findById(taskId); // 重新加载以防状态冲突
            task.setResults(JsonUtils.toJson(stats));
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

    private void processSystemImport(ImportTask task, String dictId, List<String> words, String strategy, TaskStatistics stats) {
        User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
        for (int i = 0; i < words.size(); i++) {
            String spell = words.get(i).trim();
            try {
                processSingleWord(spell, null, true, systemUser, dictId, strategy, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWordsOnly(ImportTask task, String dictId, List<String> words, String strategy, TaskStatistics stats) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            String spell = words.get(i).trim();
            try {
                processSingleWord(spell, null, false, owner, dictId, strategy, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWithMeanings(ImportTask task, String dictId, List<Map<String, String>> words, String strategy, TaskStatistics stats) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            Map<String, String> item = words.get(i);
            String spell = item.get("word").trim();
            String manualMeaning = item.get("meaning");
            try {
                processSingleWord(spell, manualMeaning, false, owner, dictId, strategy, stats);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                stats.errorCount++;
                stats.wordDetails.add(new WordDetail(spell, "ERROR", e.getMessage(), null));
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processSingleWord(String spell, String manualMeaning, boolean isSystem, User user, String dictId, String strategy, TaskStatistics stats) throws Exception {
        Word word = wordBo.getWordBySpell(spell);
        boolean isNewWord = (word == null);
        String actionType = "ADDED";
        AiResult lastAiResult = null;

        if (isNewWord) {
            word = new Word();
            word.setSpell(spell);
            word.setPopularity(5); // 默认中等
            // 调用 AI 获取音标（及其它固有属性）
            lastAiResult = getAiResult(spell, null, null);
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
        }

        if (word == null) {
            throw new RuntimeException("无法获取或创建单词对象: " + spell);
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
                        // 使用有道绝佳的真人英式播报 API，远比大模型直接盲读强且完全免费
                        String urlStr = "http://dict.youdao.com/dictvoice?type=1&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8");
                        java.net.URL url = new java.net.URL(urlStr);
                        java.net.HttpURLConnection conn = (java.net.HttpURLConnection) url.openConnection();
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
                            logger.info("通过真人词库补上了发音文件: " + soundFile.getAbsolutePath());
                        } else {
                            throw new RuntimeException("Http Status " + conn.getResponseCode());
                        }
                    } catch (Exception e) {
                        logger.warn("从有道词典下载真人发音失败 (" + pureSpell + ")，自动回退使用大模型 TTS 合成降级补全: " + e.getMessage());
                        byte[] audioData = aiBo.generateSpeech(spell);
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

        // 查找该词在目标词典中的现有释义
        List<MeaningItemDto> existingMeaningsInDict = meaningItemBo.findMeaningsByWordAndDict(word.getId(), dictId);
        if (!existingMeaningsInDict.isEmpty()) {
            if ("SKIP".equalsIgnoreCase(strategy)) {
                logger.info("单词 {} 在词典 {} 中已存在，跳过", spell, dictId);
                stats.skippedCount++;
                stats.wordDetails.add(new WordDetail(spell, "SKIPPED", null, null));
                return;
            } else if ("RECREATE".equalsIgnoreCase(strategy)) {
                actionType = "RECREATED";
                logger.info("单词 {} 在词典 {} 中已存在，执行重刷（删除现有资源）", spell, dictId);
                stats.recreatedCount++;
                for (MeaningItemDto mi : existingMeaningsInDict) {
                    // 1. 删除例句并在必要时记录日志
                    List<Sentence> sentences = sentenceBo.findByMeaningItem(mi.getId());
                    stats.deletedSentenceCount += sentences.size();
                    if (Constants.COMMON_DICT_ID.equals(dictId)) {
                        for (Sentence s : sentences) {
                            sysDbSyncBo.logOperation("DELETE", "sentence", s.getId(), "{}");
                            stats.addSyncLog("DELETE", "sentence");
                        }
                    }
                    sentenceBo.deleteByMeaningItem(mi.getId());
                    
                    // 2. 删除同义词
                    synonymBo.deleteByMeaningItem(mi.getId());
                    // 3. 删除释义项
                    meaningItemBo.deleteMeaningItem(mi.getId());
                    stats.deletedMeaningCount++;
                    
                    // 3. 如果是系统词典，记录删除日志
                    if (Constants.COMMON_DICT_ID.equals(dictId)) {
                        sysDbSyncBo.logOperation("DELETE", "meaning_item", mi.getId(), "{}");
                        stats.addSyncLog("DELETE", "meaning_item");
                    }
                }
            }
        }

        // 获取该词在所有词典中的现有释义（为了给 AI 提供上下文参考）
        List<MeaningItemDto> allExistingMeanings = meaningItemBo.findMeaningsByWord(word.getId());
        String contextMeanings = allExistingMeanings.stream()
                .map(m -> (m.getCiXing() != null ? m.getCiXing() : "") + " " + m.getMeaning())
                .collect(java.util.stream.Collectors.joining("; "));

        if (isSystem) {
            // 场景 1：加入通用词典
            // 此时 dictId 应该是 "0"
            lastAiResult = getAiResult(spell, null, contextMeanings);
            saveExtrinsicResources(word, lastAiResult, Constants.SYS_USER_SYS_ID, Constants.COMMON_DICT_ID, stats);
        } else {
            // 用户导入
            if (manualMeaning != null) {
                // 场景 3：单词+外部释义 (私有)
                lastAiResult = getAiResult(spell, manualMeaning, contextMeanings);
                saveExtrinsicResources(word, lastAiResult, user.getId(), dictId, stats);
            } else {
                // 场景 2：仅单词
                // 如果通用库已有，且不需要强制重刷，则由 DictWord 关联即可。
                // 但如果 strategy 是 RECREATE 或指定了私有词库，我们倾向于生成资源。
                boolean hasCommonMeaning = allExistingMeanings.stream().anyMatch(m -> Constants.COMMON_DICT_ID.equals(m.getDictId()));
                if (!hasCommonMeaning || "RECREATE".equalsIgnoreCase(strategy) || !Constants.COMMON_DICT_ID.equals(dictId)) {
                    lastAiResult = getAiResult(spell, null, contextMeanings);
                    saveExtrinsicResources(word, lastAiResult, user.getId(), dictId, stats);
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
                dict = dictWordBo.dictBo.findById(dictId);
                dict.setWordCount(dict.getWordCount() + 1);
                dictWordBo.dictBo.updateEntity(dict);
            }
        }
        
        stats.wordDetails.add(new WordDetail(spell, actionType, null, lastAiResult));
    }

    private void saveExtrinsicResources(Word word, AiResult aiResult, String ownerId, String dictId, TaskStatistics stats) {
        if (aiResult.meaning == null || aiResult.meaning.trim().isEmpty()) {
            return;
        }

        String[] meanings = aiResult.meaning.split("[;；]"); // 分割多个释义
        MeaningItem firstMeaning = null;

        for (int i = 0; i < meanings.length; i++) {
            String m = meanings[i].trim();
            if (m.isEmpty()) continue;

            // 创建 MeaningItem
            MeaningItem meaning = new MeaningItem();
            meaning.setWord(word);
            meaning.setCiXing(aiResult.pos);
            meaning.setMeaning(m);
            // 多个同词性释义通过 popularity 作微弱区分（如果需要），这里简化处理
            meaning.setPopularity(aiResult.popularity > i ? aiResult.popularity - i : 1);
            
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

            if (firstMeaning == null) {
                firstMeaning = meaning;
            }
        }

        if (firstMeaning == null) {
            return;
        }

        // 创建 Sentence
        if (aiResult.sentenceEn != null && !aiResult.sentenceEn.trim().isEmpty()) {
            Sentence sentence = new Sentence();
            sentence.setEnglish(aiResult.sentenceEn);
            sentence.setChinese(aiResult.sentenceCn);
            
            sentence.setWordMeaning(firstMeaning.getMeaning());
            sentence.setPartOfSpeech(firstMeaning.getCiXing());
            
            sentence.setMeaningItem(firstMeaning);
            sentence.setNeedTts(true); // 标记需要生成音频
            sentence.setTheType("waitting_tts");
            sentence.setEnglishDigest(beidanci.service.util.Util.makeSentenceDigest(aiResult.sentenceEn));
            if (ownerId != null) {
                User author = new User();
                author.setId(ownerId);
                sentence.setAuthor(author);
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
        if (aiResult.synonyms != null && !aiResult.synonyms.isEmpty()) {
            for (String synSpell : aiResult.synonyms) {
                Word synWord = wordBo.getWordBySpell(synSpell);
                if (synWord != null) {
                    Synonym synonym = new Synonym();
                    SynonymId sid = new SynonymId();
                    sid.setMeaningItemId(firstMeaning.getId());
                    sid.setWordId(synWord.getId());
                    synonym.setId(sid);
                    synonym.setMeaningItem(firstMeaning);
                    synonym.setCreateTime(new Date());
                    synonymBo.createEntity(synonym);
                    stats.addedSynonymCount++;
                }
            }
        }
    }

    private AiResult getAiResult(String spell, String manualMeaning, String context) {
        String systemPrompt = "You are a professional English dictionary assistant. Return JSON only. " +
                "IMPORTANT RULES:\n" +
                "1. 'pos' field MUST be abbreviations (e.g., n., v., adj., adv.).\n" +
                "2. 'meaning' field MUST be in Chinese, and MUST include all commonly used meanings, separated by semicolons if multiple.\n" +
                "3. Ensure the sentence is practical and natural.\n" +
                "4. Use <b>word</b> in BOTH sentenceEn and sentenceCn to highlight the vocabulary word and its Chinese meaning respectively.";
        StringBuilder userPrompt = new StringBuilder();
        userPrompt.append(String.format("Generating data for word '%s'. ", spell));
        
        if (context != null && !context.trim().isEmpty()) {
            userPrompt.append(String.format("Existing meanings for reference: [%s]. Try to provide better or complementary info if needed. ", context));
        }

        if (manualMeaning == null) {
            userPrompt.append("Return in this exact JSON format: {\"phonetic\": \"/xxx/\", \"pos\": \"n.\", \"meaning\": \"中文意思1; 中文意思2\", \"popularity\": 1-10, \"synonyms\": [\"syn1\", \"syn2\"], \"sentenceEn\": \"...\", \"sentenceCn\": \"...\"}. " +
                    "provide at most 3 common synonyms.");
        } else {
            userPrompt.append(String.format("Given manual meaning '%s', generate phonetics, example sentence and synonyms. " +
                    "Return: {\"phonetic\": \"/xxx/\", \"pos\": \"n.\", \"meaning\": \"%s\", \"popularity\": 5, \"synonyms\": [\"syn1\", \"syn2\"], \"sentenceEn\": \"...\", \"sentenceCn\": \"...\"}.", 
                    manualMeaning, manualMeaning));
        }

        String rawJson = aiBo.generateText(systemPrompt, userPrompt.toString());
        // 清理 AI 可能带的 Markdown 代码块标签
        rawJson = rawJson.replaceAll("```json", "").replaceAll("```", "").trim();
        Map<String, Object> map = JsonUtils.parseMap(rawJson);
        
        AiResult res = new AiResult();
        res.phonetic = (String) map.get("phonetic");
        res.pos = (String) map.get("pos");
        res.meaning = (String) map.get("meaning");
        res.popularity = (Integer) map.getOrDefault("popularity", 5);
        res.sentenceEn = (String) map.get("sentenceEn");
        res.sentenceCn = (String) map.get("sentenceCn");
        @SuppressWarnings("unchecked")
        List<String> synonyms = (List<String>) map.get("synonyms");
        res.synonyms = synonyms;
        return res;
    }

    public static class AiResult {
        String phonetic;
        String pos;
        String meaning;
        Integer popularity;
        String sentenceEn;
        String sentenceCn;
        List<String> synonyms;
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
}
