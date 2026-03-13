package beidanci.service.bo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

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
    private UserBo userBo;

    /**
     * 异步执行导入任务
     *
     * @param taskId 任务ID
     */
    @Async
    public void executeImportTask(String taskId) {
        ImportTask task = importTaskBo.findById(taskId);
        if (task == null) return;

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
                processSystemImport(task, dictId, rawWords, strategy);
            } else if (rawWords != null) {
                processUserImportWordsOnly(task, dictId, rawWords, strategy);
            } else {
                processUserImportWithMeanings(task, dictId, wordsWithMeanings, strategy);
            }

            task = importTaskBo.findById(taskId); // 重新加载以防状态冲突
            task.setStatus("COMPLETED");
            importTaskBo.updateEntity(task);
        } catch (Exception e) {
            logger.error("词典导入任务失败: " + taskId, e);
            task.setStatus("FAILED");
            String errorMsg = e.getMessage() != null ? e.getMessage() : "未知错误";
            task.setLog((task.getLog() != null ? task.getLog() : "") + "\nERROR: " + errorMsg);
            try {
                importTaskBo.updateEntity(task);
            } catch (IllegalAccessException ignore) {
            }
        }
    }

    private void processSystemImport(ImportTask task, String dictId, List<String> words, String strategy) {
        User systemUser = userBo.findById(Constants.SYS_USER_SYS_ID);
        for (int i = 0; i < words.size(); i++) {
            String spell = words.get(i).trim();
            try {
                processSingleWord(spell, null, true, systemUser, dictId, strategy);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWordsOnly(ImportTask task, String dictId, List<String> words, String strategy) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            String spell = words.get(i).trim();
            try {
                processSingleWord(spell, null, false, owner, dictId, strategy);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processUserImportWithMeanings(ImportTask task, String dictId, List<Map<String, String>> words, String strategy) {
        User owner = task.getOwner();
        for (int i = 0; i < words.size(); i++) {
            Map<String, String> item = words.get(i);
            String spell = item.get("word").trim();
            String manualMeaning = item.get("meaning");
            try {
                processSingleWord(spell, manualMeaning, false, owner, dictId, strategy);
                importTaskBo.updateProgress(task.getId(), i + 1, "Processed: " + spell);
            } catch (Exception e) {
                logger.warn("处理单词失败: " + spell, e);
                importTaskBo.updateProgress(task.getId(), i + 1, "Failed: " + spell + " (" + e.getMessage() + ")");
            }
        }
    }

    private void processSingleWord(String spell, String manualMeaning, boolean isSystem, User user, String dictId, String strategy) throws Exception {
        Word word = wordBo.getWordBySpell(spell);
        boolean isNewWord = (word == null);

        if (isNewWord) {
            word = new Word();
            word.setSpell(spell);
            word.setPopularity(5); // 默认中等
            // 调用 AI 获取音标（及其它固有属性）
            AiResult aiResult = getAiResult(spell, null, null);
            word.setBritishPronounce(aiResult.phonetic);
            word.setAmericaPronounce(aiResult.phonetic);
            word.setPronounce(aiResult.phonetic);
            wordBo.createEntity(word);
        }

        if (word == null) {
            throw new RuntimeException("无法获取或创建单词对象: " + spell);
        }

        // 查找该词在目标词典中的现有释义
        List<MeaningItemDto> existingMeaningsInDict = meaningItemBo.findMeaningsByWordAndDict(word.getId(), dictId);
        if (!existingMeaningsInDict.isEmpty()) {
            if ("SKIP".equalsIgnoreCase(strategy)) {
                logger.info("单词 {} 在词典 {} 中已存在，跳过", spell, dictId);
                return;
            } else if ("RECREATE".equalsIgnoreCase(strategy)) {
                logger.info("单词 {} 在词典 {} 中已存在，执行重刷（删除现有资源）", spell, dictId);
                for (MeaningItemDto mi : existingMeaningsInDict) {
                    // 1. 删除例句并在必要时记录日志
                    if (Constants.COMMON_DICT_ID.equals(dictId)) {
                        List<Sentence> sentences = sentenceBo.findByMeaningItem(mi.getId());
                        for (Sentence s : sentences) {
                            sysDbSyncBo.logOperation("DELETE", "sentence", s.getId(), "{}");
                        }
                    }
                    sentenceBo.deleteByMeaningItem(mi.getId());
                    
                    // 2. 删除释义项
                    meaningItemBo.deleteMeaningItem(mi.getId());
                    
                    // 3. 如果是系统词典，记录删除日志
                    if (Constants.COMMON_DICT_ID.equals(dictId)) {
                        sysDbSyncBo.logOperation("DELETE", "meaning_item", mi.getId(), "{}");
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
            AiResult aiResult = getAiResult(spell, null, contextMeanings);
            saveExtrinsicResources(word, aiResult, Constants.SYS_USER_SYS_ID, Constants.COMMON_DICT_ID);
        } else {
            // 用户导入
            if (manualMeaning != null) {
                // 场景 3：单词+外部释义 (私有)
                AiResult aiResult = getAiResult(spell, manualMeaning, contextMeanings);
                saveExtrinsicResources(word, aiResult, user.getId(), dictId);
            } else {
                // 场景 2：仅单词
                // 如果通用库已有，且不需要强制重刷，则由 DictWord 关联即可。
                // 但如果 strategy 是 RECREATE 或指定了私有词库，我们倾向于生成资源。
                boolean hasCommonMeaning = allExistingMeanings.stream().anyMatch(m -> Constants.COMMON_DICT_ID.equals(m.getDictId()));
                if (!hasCommonMeaning || "RECREATE".equalsIgnoreCase(strategy) || !Constants.COMMON_DICT_ID.equals(dictId)) {
                    AiResult aiResult = getAiResult(spell, null, contextMeanings);
                    saveExtrinsicResources(word, aiResult, user.getId(), dictId);
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
                
                // 更新词书单词计数
                dict = dictWordBo.dictBo.findById(dictId);
                dict.setWordCount(dict.getWordCount() + 1);
                dictWordBo.dictBo.updateEntity(dict);
            }
        }
    }

    private void saveExtrinsicResources(Word word, AiResult aiResult, String ownerId, String dictId) {
        // 创建 MeaningItem
        MeaningItem meaning = new MeaningItem();
        meaning.setWord(word);
        meaning.setCiXing(aiResult.pos);
        meaning.setMeaning(aiResult.meaning);
        meaning.setPopularity(aiResult.popularity);
        
        User owner = new User();
        owner.setId(ownerId != null ? ownerId : Constants.SYS_USER_SYS_ID);
        meaning.setOwner(owner);

        if (dictId != null) {
            Dict dict = new Dict();
            dict.setId(dictId);
            meaning.setDict(dict);
        }
        meaningItemBo.createEntity(meaning);

        // 创建 Sentence
        Sentence sentence = new Sentence();
        sentence.setEnglish(aiResult.sentenceEn);
        sentence.setChinese(aiResult.sentenceCn);
        sentence.setMeaningItem(meaning);
        if (ownerId != null) {
            User author = new User();
            author.setId(ownerId);
            sentence.setAuthor(author);
        }
        sentenceBo.createEntity(sentence);

        // 如果是记录到通用词典（属于系统管理员），则记录同步日志，以便各分布式节点同步
        if (Constants.SYS_USER_SYS_ID.equals(ownerId)) {
            sysDbSyncBo.logOperation("INSERT", "meaning_item", meaning.getId(), JsonUtils.toJson(meaningItemBo.toDto(meaning)));
            sysDbSyncBo.logOperation("INSERT", "sentence", sentence.getId(), JsonUtils.toJson(sentenceBo.toDto(sentence)));
        }
    }

    private AiResult getAiResult(String spell, String manualMeaning, String context) {
        String systemPrompt = "You are a professional English dictionary assistant. Return JSON only.";
        StringBuilder userPrompt = new StringBuilder();
        userPrompt.append(String.format("Generating data for word '%s'. ", spell));
        
        if (context != null && !context.trim().isEmpty()) {
            userPrompt.append(String.format("Existing meanings for reference: [%s]. Try to provide better or complementary info if needed. ", context));
        }

        if (manualMeaning == null) {
            userPrompt.append("{'phonetic': '...', 'pos': '...', 'meaning': '...', 'popularity': 1-10, 'sentenceEn': '...', 'sentenceCn': '...'}. " +
                    "Use <b> word </b> in sentences to highlight the word.");
        } else {
            userPrompt.append(String.format("Given manual meaning '%s', generate phonetics and an example sentence. " +
                    "Return: {'phonetic': '...', 'pos': '...', 'meaning': '%s', 'popularity': 5, 'sentenceEn': '...', 'sentenceCn': '...'}.", 
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
        return res;
    }

    private static class AiResult {
        String phonetic;
        String pos;
        String meaning;
        Integer popularity;
        String sentenceEn;
        String sentenceCn;
    }
}
