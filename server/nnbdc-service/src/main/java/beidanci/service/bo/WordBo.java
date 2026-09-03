package beidanci.service.bo;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;

import javax.annotation.PostConstruct;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemDto;
import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.SimilarWordDto;
import beidanci.api.model.WordDto;
import beidanci.api.model.WordImageDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Dict;
import beidanci.service.po.MeaningItem;
import beidanci.service.po.Sentence;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;
import beidanci.util.Constants;
import beidanci.util.Utils;
@Service
@Transactional(rollbackFor = Throwable.class)
public class WordBo extends BaseBo<Word> {
    private static final Logger log = LoggerFactory.getLogger(WordBo.class);

    @Autowired
    WordCache wordCache;

    @Autowired
    MeaningItemBo meaningItemBo;
    @Autowired
    SentenceBo sentenceBo;
    @Autowired
    private SynonymBo synonymBo;
    @Autowired
    SysParamUtil sysParamUtil;
    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;



    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<Word>() {
        });
    }

    /**
     * 获取所有单词，并按照单词拼写升序排列(不区分大小写)
     *
     * @return
     */
    public List<Word> getAllWords() {
        String sql = "SELECT * FROM word ORDER BY LOWER(spell) ASC";
        return namedParameterJdbcTemplate.query(sql, 
            new EntityRowMapper<>(Word.class));
    }

    public WordVo getWordVoById(String wordId, String[] excludeFields) {
        Word word = findById(wordId, false);

        WordVo vo = word2Vo(word, excludeFields);
        return vo;
    }

    public Word getWordBySpell(String spell) {
        String sql = "SELECT * FROM word WHERE spell = :spell";
        MapSqlParameterSource params = new MapSqlParameterSource("spell", spell);
        List<Word> results = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Word.class));
        return results.isEmpty() ? null : results.get(0);
    }

    public WordVo getWordVoBySpell(String spell, String[] excludeFields) {
        Word word = getWordBySpell(spell);

        if (word == null) {
            return null;
        }
        WordVo vo = word2Vo(word, excludeFields);
        return vo;
    }

    private WordVo word2Vo(Word word, String[] excludeFields) {
        WordVo vo = WordCache.genWordVO(word, excludeFields);

        // 不再额外查询数据库，问题应在PO->VO转换链上修复
        return vo;
    }

    public WordVo getWordVoForAdmin(String spell) {
        Word word = getWordBySpell(spell);
        if (word == null) {
            return null;
        }
        WordVo vo = new WordVo();
        vo.setId(word.getId());
        vo.setSpell(word.getSpell());
        vo.setBritishPronounce(word.getBritishPronounce());
        vo.setAmericaPronounce(word.getAmericaPronounce());
        vo.setPronounce(word.getPronounce());
        vo.setShortDesc(word.getShortDesc());

        List<MeaningItemDto> dtos = meaningItemBo.findMeaningsByWord(word.getId());
        List<MeaningItemVo> itemVos = new ArrayList<>();
        for (MeaningItemDto dto : dtos) {
            MeaningItemVo itemVo = new MeaningItemVo();
            itemVo.setId(dto.getId());
            itemVo.setCiXing(dto.getCiXing());
            itemVo.setMeaning(dto.getMeaning());
            itemVo.setPopularity(dto.getPopularity());
            itemVo.setPopularityPercent(dto.getPopularityPercent());
            itemVo.setOwnerId(dto.getOwnerId());
            itemVos.add(itemVo);
        }
        vo.setMeaningItems(itemVos);
        return vo;
    }

    private MeaningItemVo getMeaningItemVoFromList(String meaningItemId, List<MeaningItemVo> meaningItems) {
        for (MeaningItemVo itemVo : meaningItems) {
            if (itemVo.getId() != null && itemVo.getId().equals(meaningItemId)) {
                return itemVo;
            }
        }
        return null;
    }


    public String updateWord(WordVo wordVo, String reason) throws IllegalAccessException, InvalidMeaningFormatException,
            EmptySpellException, IOException, ParseException {
        if (wordVo == null || wordVo.getId() == null) {
            return "单词ID不能为null";
        }
        if (wordVo.getMeaningItems() == null || wordVo.getMeaningItems().isEmpty()) {
            return "单词至少保留一条释义";
        }

        WordVo existingWord = wordCache.getWordBySpell(wordVo.getSpell(), new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
        if (existingWord != null && !existingWord.getId().equals(wordVo.getId())) {
            return String.format("单词%s已存在", wordVo.getSpell());
        }

        Word word = findById(wordVo.getId());
        if (word == null) {
            return String.format("未找到ID为%s的单词", wordVo.getId());
        }

        // 真实从数据库查询当前已有的释义列表（Spring JDBC 下 PO 的集合属性不会被自动加载）
        List<MeaningItem> existingMeaningItems = meaningItemBo.findEntitiesByWord(word.getId());

        // 1. 删除被移除的 meaningItems（级联清理近义词与例句，并记入系统同步日志）
        List<MeaningItem> deletedItems = new ArrayList<>();
        for (MeaningItem item : existingMeaningItems) {
            if (getMeaningItemVoFromList(item.getId(), wordVo.getMeaningItems()) == null) {
                deletedItems.add(item);
            }
        }
        for (MeaningItem item : deletedItems) {
            synonymBo.deleteByMeaningItem(item.getId());
            sentenceBo.deleteByMeaningItem(item.getId());
            meaningItemBo.deleteEntity(item);
            sysDbSyncBo.logOperation("DELETE", "meaning_item", item.getId(), "{}");
        }

        // 2. 更新被修改的 meaningItems
        for (MeaningItem item : existingMeaningItems) {
            MeaningItemVo itemVo = getMeaningItemVoFromList(item.getId(), wordVo.getMeaningItems());
            if (itemVo != null) {
                String ciXing = Util.sanitizeAiString(itemVo.getCiXing());
                String meaning = Util.sanitizeAiString(itemVo.getMeaning());
                if (!Objects.equals(item.getCiXing(), ciXing) || !Objects.equals(item.getMeaning(), meaning)) {
                    item.setCiXing(ciXing);
                    item.setMeaning(meaning);
                    meaningItemBo.updateEntity(item);
                    sysDbSyncBo.logOperation("UPDATE", "meaning_item", item.getId(), JsonUtils.toJson(meaningItemBo.toDto(item)));
                }
            }
        }

        // 3. 添加新增的 meaningItems
        List<MeaningItem> newItems = new ArrayList<>();
        for (MeaningItemVo itemVo : wordVo.getMeaningItems()) {
            if (itemVo.getId() == null) {
                MeaningItem item = new MeaningItem();
                item.setCiXing(Util.sanitizeAiString(itemVo.getCiXing()));
                item.setMeaning(Util.sanitizeAiString(itemVo.getMeaning()));
                item.setWord(word);
                // 释义归属通用词典，保证全员可见
                Dict commonDict = new Dict();
                commonDict.setId(Constants.COMMON_DICT_ID);
                item.setDict(commonDict);

                // 设置所有者：优先使用 Vo 传入的，否则默认为系统管理员
                User owner = new User();
                owner.setId(itemVo.getOwnerId() != null ? itemVo.getOwnerId() : Constants.SYS_USER_SYS_ID);
                item.setOwner(owner);
                item.setPopularity(1);

                meaningItemBo.createEntity(item);
                sysDbSyncBo.logOperation("INSERT", "meaning_item", item.getId(), JsonUtils.toJson(meaningItemBo.toDto(item)));
                newItems.add(item);
            }
        }

        // 更新单词的拼写
        String oldSpell = word.getSpell();
        word.setSpell(wordVo.getSpell());

        updateEntity(word);

        // 更新声音文件（重命名）
        if (!oldSpell.equalsIgnoreCase(wordVo.getSpell())) {
            String[] suffixes = {"", "_uk", "_us"};
            for (String suffix : suffixes) {
                File oldMp3 = new File(sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(oldSpell, suffix) + ".mp3");
                File newMp3 = new File(sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(wordVo.getSpell(), suffix) + ".mp3");
                if (oldMp3.exists()) {
                    File parent = newMp3.getParentFile();
                    if (!parent.exists()) parent.mkdirs();
                    oldMp3.renameTo(newMp3);
                }
            }

            File oldOga = new File(sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(oldSpell) + ".oga");
            File newOga = new File(sysParamUtil.getSoundPath() + "/" + Utils.getFileNameOfWordSound(wordVo.getSpell()) + ".oga");
            if (oldOga.exists()) {
                File parent = newOga.getParentFile();
                if (!parent.exists()) parent.mkdirs();
                oldOga.renameTo(newOga);
            }

            sysDbSyncBo.logOperation("UPDATE", "word", word.getId(), JsonUtils.toJson(toDto(word)));
        }

        // 筛选需要补充例句的释义：新增的释义，或当前在数据库中尚无任何例句的释义（避免修改错别字时重复生成堆叠例句）
        List<MeaningItem> needSentenceItems = new ArrayList<>(newItems);
        for (MeaningItem item : existingMeaningItems) {
            // 如果该已存在释义未被删除，且其在库中无任何例句，则也纳入生成
            if (getMeaningItemVoFromList(item.getId(), wordVo.getMeaningItems()) != null) {
                List<Sentence> existingSentences = sentenceBo.findByMeaningItem(item.getId());
                if (existingSentences == null || existingSentences.isEmpty()) {
                    needSentenceItems.add(item);
                }
            }
        }

        // 异步调用大模型生成配套例句，不占用主数据库事务与阻塞 HTTP 连接
        if (!needSentenceItems.isEmpty()) {
            CompletableFuture.runAsync(() -> {
                generateSentencesForMeanings(word, needSentenceItems);
            });
        }

        return null;
    }

    /**
     * 调用大模型为指定释义各生成一条例句，入库后由 TTS 定时任务自动生成发音文件。
     * 例句生成失败不回滚释义保存，仅记录错误日志暴露问题。
     */
    private void generateSentencesForMeanings(Word word, List<MeaningItem> items) {
        if (items.isEmpty()) {
            return;
        }
        String spell = word.getSpell();
        try {
            StringBuilder meaningsJson = new StringBuilder("[");
            for (MeaningItem item : items) {
                if (meaningsJson.length() > 1) {
                    meaningsJson.append(",");
                }
                meaningsJson.append(String.format("{\"meaningItemId\": \"%s\", \"ciXing\": \"%s\", \"meaning\": \"%s\"}",
                        item.getId(), item.getCiXing(), item.getMeaning()));
            }
            meaningsJson.append("]");

            String systemPrompt = "你是一个词典例句创作专家。请为单词的每个释义项创作一个实用、自然的英文例句及中文翻译。\n"
                    + "要求：\n"
                    + "1. 例句要贴合该释义项的词义与词性，难度适中，长度在 8~20 个单词之间。\n"
                    + "2. 在英文例句和中文翻译中，对目标单词使用 <b>单词</b> 标签进行加粗高亮。\n"
                    + "3. 严格按照以下 JSON 格式返回，不要有任何 Markdown 标注或说明性文字：\n"
                    + "{\"sentences\": [{\"meaningItemId\": \"uuid1\", \"sentenceEn\": \"We should <b>book</b> a table in advance.\", \"sentenceCn\": \"我们应该提前<b>预订</b>一张桌子。\"}]}";
            String userPrompt = String.format("{\"word\": \"%s\", \"meanings\": %s}", spell, meaningsJson);

            String aiOutput = aiBo.generateText(systemPrompt, userPrompt);
            if (aiOutput != null) {
                aiOutput = aiOutput.replaceAll("^```(?:json)?\\s*", "").replaceAll("\\s*```$", "").trim();
            }
            Map<String, Object> aiRes = JsonUtils.parseMap(aiOutput);
            List<?> sentenceList = aiRes == null ? null : (List<?>) aiRes.get("sentences");
            if (sentenceList == null) {
                log.error("为单词 [{}] 的释义生成例句失败: 大模型返回结果解析失败", spell);
                return;
            }

            User systemUser = new User();
            systemUser.setId(Constants.SYS_USER_SYS_ID);
            for (Object obj : sentenceList) {
                if (!(obj instanceof Map)) {
                    continue;
                }
                Map<?, ?> map = (Map<?, ?>) obj;
                String meaningItemId = (String) map.get("meaningItemId");
                String sentenceEn = (String) map.get("sentenceEn");
                String sentenceCn = (String) map.get("sentenceCn");
                MeaningItem item = getMeaningItemFromList(meaningItemId, items);
                if (item == null || sentenceEn == null || sentenceEn.trim().isEmpty()) {
                    continue;
                }

                Sentence sentence = new Sentence();
                sentence.setEnglish(sentenceEn.trim());
                sentence.setChinese(sentenceCn);
                sentence.setWordMeaning(item.getMeaning());
                sentence.setPartOfSpeech(item.getCiXing());
                sentence.setMeaningItem(item);
                sentence.setNeedTts(true); // 触发 TTS 定时任务生成发音文件
                sentence.setTheType(Sentence.WAITTING_TTS);
                sentence.setOwner(systemUser);
                sentence.setAuthor(systemUser);
                sentence.setEnglishDigest(Util.makeSentenceDigest(sentenceEn.trim()));

                sentenceBo.createEntity(sentence);
                sysDbSyncBo.logOperation("INSERT", "sentence", sentence.getId(), JsonUtils.toJson(sentenceBo.toDto(sentence)));
            }
        } catch (Exception e) {
            log.error("为单词 [{}] 的释义生成例句失败", spell, e);
        }
    }

    private MeaningItem getMeaningItemFromList(String meaningItemId, List<MeaningItem> items) {
        for (MeaningItem item : items) {
            if (item.getId() != null && item.getId().equals(meaningItemId)) {
                return item;
            }
        }
        return null;
    }



    public List<WordDto> getWordsOfDict(String dictId) {
        return getWordsOfDictBySeqRange(dictId, null, null);
    }

    public List<WordDto> getWordsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT id, america_pronounce, british_pronounce, group_info, long_desc, short_desc, popularity, pronounce, spell, embedding_1bit, create_time, update_time FROM word w WHERE w.id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            WordDto wordDto = new WordDto();
            String idStr = rs.getString("id");
            assert idStr != null;
            wordDto.setId(idStr);
            wordDto.setAmericaPronounce(rs.getString("america_pronounce"));
            wordDto.setBritishPronounce(rs.getString("british_pronounce"));
            wordDto.setGroupInfo(rs.getString("group_info"));
            wordDto.setLongDesc(rs.getString("long_desc"));
            wordDto.setShortDesc(rs.getString("short_desc"));
            wordDto.setPopularity(rs.getObject("popularity", Integer.class));
            wordDto.setPronounce(rs.getString("pronounce"));
            wordDto.setSpell(rs.getString("spell"));
            wordDto.setEmbedding1bit(rs.getBytes("embedding_1bit"));
            wordDto.setCreateTime(rs.getTimestamp("create_time"));
            wordDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordDto;
        });
    }

    public List<SimilarWordDto> getSimilarWordsOfDict(String dictId) {
        return getSimilarWordsOfDictBySeqRange(dictId, null, null);
    }

    public List<SimilarWordDto> getSimilarWordsOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT sw.word_id, sw.similar_word_id, sw.distance, w.spell, sw.create_time, sw.update_time " +
                     "FROM similar_word sw LEFT JOIN word w ON w.id=sw.similar_word_id " +
                     "WHERE sw.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            SimilarWordDto wordDto = new SimilarWordDto();
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            wordDto.setWordId(wordIdStr);
            String similarWordIdStr = rs.getString("similar_word_id");
            assert similarWordIdStr != null;
            wordDto.setSimilarWordId(similarWordIdStr);
            Integer distance = rs.getObject("distance", Integer.class);
            wordDto.setDistance(distance != null ? distance : 0);
            String spell = rs.getString("spell");
            wordDto.setSimilarWordSpell(spell != null ? spell : "");
            Date createTime = rs.getTimestamp("create_time");
            wordDto.setCreateTime(createTime != null ? createTime : new Date());
            Date updateTime = rs.getTimestamp("update_time");
            wordDto.setUpdateTime(updateTime != null ? updateTime : (createTime != null ? createTime : new Date()));
            return wordDto;
        });
    }

    public List<WordImageDto> getWordImagesOfDict(String dictId) {
        return getWordImagesOfDictBySeqRange(dictId, null, null);
    }

    public List<WordImageDto> getWordImagesOfDictBySeqRange(String dictId, Integer fromSeq, Integer toSeq) {
        StringBuilder sql = new StringBuilder("SELECT id, foot, hand, image_file, author_id, word_id, create_time, update_time FROM word_image wi WHERE wi.word_id IN (SELECT dw.word_id FROM dict_word dw WHERE dw.dict_id=:dictId");
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        if (fromSeq != null) {
            sql.append(" AND dw.seq >= :fromSeq");
            params.addValue("fromSeq", fromSeq);
        }
        if (toSeq != null) {
            sql.append(" AND dw.seq <= :toSeq");
            params.addValue("toSeq", toSeq);
        }
        sql.append(")");
        
        String querySql = java.util.Objects.requireNonNull(sql.toString());
        return namedParameterJdbcTemplate.query(querySql, params, (rs, rowNum) -> {
            WordImageDto wordImageDto = new WordImageDto();
            String idStr = rs.getString("id");
            assert idStr != null;
            wordImageDto.setId(idStr);
            wordImageDto.setFoot(rs.getObject("foot", Integer.class));
            wordImageDto.setHand(rs.getObject("hand", Integer.class));
            wordImageDto.setImageFile(rs.getString("image_file"));
            wordImageDto.setAuthorId(rs.getString("author_id"));
            String wordIdStr = rs.getString("word_id");
            assert wordIdStr != null;
            wordImageDto.setWordId(wordIdStr);
            wordImageDto.setCreateTime(rs.getTimestamp("create_time"));
            wordImageDto.setUpdateTime(rs.getTimestamp("update_time"));
            return wordImageDto;
        });
    }

    /**
     * 下载单词指定口音的发音 mp3 到 sound 目录。
     * 优先有道 dictvoice,失败回退 CosyVoice TTS(按口音附加发音指令)。
     *
     * @param spell        单词拼写
     * @param accentSuffix "_uk"(英音) / "_us"(美音) / null(旧版无后缀)
     * @return 目标文件绝对路径;失败返回 null
     */
    public String downloadWordSound(String spell, String accentSuffix) throws Exception {
        return downloadWordSound(spell, accentSuffix, false);
    }

    /**
     * 下载单词指定口音的发音 mp3 到 sound 目录。
     *
     * @param spell          单词拼写
     * @param accentSuffix   "_uk"(英音) / "_us"(美音) / null(旧版无后缀)
     * @param forceOverwrite 是否强制重新生成并覆盖已有音频文件
     * @return 目标文件绝对路径;失败返回 null
     */
    public String downloadWordSound(String spell, String accentSuffix, boolean forceOverwrite) throws Exception {
        String pureSpell = Utils.uniformSpellForFilename(spell);
        if (pureSpell.isEmpty()) return null;

        String relPath = Utils.getFileNameOfWordSound(spell, accentSuffix);
        File soundFile = new File(sysParamUtil.getSoundPath() + "/" + relPath + ".mp3");
        if (!forceOverwrite && soundFile.exists() && soundFile.length() > 0) {
            return soundFile.getAbsolutePath();
        }

        File dir = soundFile.getParentFile();
        if (!dir.exists()) dir.mkdirs();

        boolean isUk = "_uk".equals(accentSuffix);
        // 有道 dictvoice 官方约定: type=1 为英音, type=2 为美音
        String[] urlStrs = isUk ? new String[]{
                "http://dict.youdao.com/dictvoice?type=1&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                "http://dict.youdao.com/dictvoice?le=eng&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8")
        } : new String[]{
                "http://dict.youdao.com/dictvoice?type=2&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8"),
                "http://dict.youdao.com/dictvoice?le=eng&audio=" + java.net.URLEncoder.encode(pureSpell, "UTF-8")
        };

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
                if (soundFile.length() > 0) {
                    log.info("有道发音下载成功: {} (suffix={})", soundFile.getAbsolutePath(), accentSuffix);
                    return soundFile.getAbsolutePath();
                } else {
                    soundFile.delete();
                }
            }
        }

        String ttsInstruction = isUk
                ? "Speak in a clear British English accent."
                : "Speak in a clear American English accent.";
        try {
            AiBo.TtsResult ttsResult = aiBo.generateSpeech(pureSpell, null, ttsInstruction);
            if (ttsResult.audioData != null && ttsResult.audioData.length > 0) {
                try (java.io.FileOutputStream fos = new java.io.FileOutputStream(soundFile)) {
                    fos.write(ttsResult.audioData);
                    fos.flush();
                }
                log.info("TTS 兜底发音成功: {} (suffix={})", soundFile.getAbsolutePath(), accentSuffix);
                return soundFile.getAbsolutePath();
            }
        } catch (Exception e) {
            log.warn("TTS 兜底发音失败: {} suffix={}", spell, accentSuffix, e);
        }
        if (soundFile.exists() && soundFile.length() == 0) {
            soundFile.delete();
        }
        return null;
    }

    public void regeneratePronunciation(String wordId) throws Exception {
        Word word = findById(wordId);
        if (word == null) {
            throw new RuntimeException("Word not found: " + wordId);
        }

        String spell = word.getSpell();

        downloadWordSound(spell, null, true);
        downloadWordSound(spell, "_uk", true);
        downloadWordSound(spell, "_us", true);

        // 记录同步日志，并更新数据库中的 update_time
        word.setUpdateTime(new Date());
        updateEntity(word);
        sysDbSyncBo.logOperation(word, "UPDATE", "word", word.getId(), beidanci.service.util.JsonUtils.toJson(toDto(word)));
    }

    public WordDto toDto(Word word) {
        WordDto dto = new WordDto();
        dto.setId(word.getId());
        dto.setSpell(word.getSpell());
        dto.setAmericaPronounce(word.getAmericaPronounce());
        dto.setBritishPronounce(word.getBritishPronounce());
        dto.setPronounce(word.getPronounce());
        dto.setPopularity(word.getPopularity());
        dto.setGroupInfo(word.getGroupInfo());
        dto.setShortDesc(word.getShortDesc());
        dto.setLongDesc(word.getLongDesc());
        dto.setEmbedding1bit(word.getEmbedding1bit());
        dto.setCreateTime(word.getCreateTime());
        dto.setUpdateTime(word.getUpdateTime());
        return dto;
    }

    @Transactional(rollbackFor = Throwable.class)
    public void updateWordEmbedding1bit(String wordId, byte[] embedding1bit) throws Exception {
        Word word = findById(wordId);
        if (word != null) {
            word.setEmbedding1bit(embedding1bit);
            word.setUpdateTime(new Date());
            updateEntity(word);
            sysDbSyncBo.logOperation(word, "UPDATE", "word", word.getId(), beidanci.service.util.JsonUtils.toJson(toDto(word)));
        }
    }
}
