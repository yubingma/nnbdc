package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.*;
import beidanci.service.bo.*;
import beidanci.service.po.Dict;
import org.springframework.web.context.request.async.DeferredResult;
import java.io.IOException;
import beidanci.service.exception.ParseException;

@RestController
public class SystemController {

    @Autowired
    private DictBo dictBo;

    @Autowired
    private SystemHealthCheckBo systemHealthCheckBo;

    @Autowired
    private AiController aiController;

    @Autowired
    private UserBo userBo;

    @Autowired
    private DictWordBo dictWordBo;

    @Autowired
    private WordBo wordBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    @Autowired
    private SynonymBo synonymBo;

    @Autowired
    private SentenceBo sentenceBo;

    @Autowired
    private WordCoreImageBo wordCoreImageBo;

    @Autowired
    private CigenBo cigenBo;

    /**
     * 系统词书自愈（第一步：对账）：按 word_id 游标分页返回某本词书的单词 ID 清单。
     *
     * 只给 ID、不传 seq —— 序号会被删词前移、也会被修复重排，不能当身份或游标用。
     * 客户端把它与本地 (dictId, wordId) 集合求差，得到真正缺的那些单词。
     */
    @GetMapping("/api/getDictWordIds.do")
    public Result<java.util.Map<String, Object>> getDictWordIds(
            @RequestParam("dictId") String dictId,
            @RequestParam(value = "after", required = false) String afterWordId,
            @RequestParam(value = "limit", defaultValue = "5000") int limit,
            @RequestHeader(value = "X-User-Id", required = false) String userId) {
        String denyReason = dictReadDenyReason(dictId, userId);
        if (denyReason != null) {
            return Result.fail(denyReason);
        }

        int pageSize = Math.max(1, Math.min(limit, 20000));
        List<String> wordIds = dictWordBo.getWordIdsPage(dictId, afterWordId, pageSize);

        java.util.Map<String, Object> data = new java.util.LinkedHashMap<>();
        data.put("wordIds", wordIds);
        data.put("nextAfter", wordIds.isEmpty() ? null : wordIds.get(wordIds.size() - 1));
        // 只在首页带一次权威总数，供客户端判断"本地是否还缺"
        if (afterWordId == null || afterWordId.isEmpty()) {
            data.put("total", dictWordBo.countDictWords(dictId));
        }
        return Result.success(data);
    }

    /**
     * 系统词书自愈（第二步：补内容）：按单词 ID 批次返回 词书关联 / 单词本体 / 释义 / 例句。
     *
     * 按 word_id 取数，走 dict_word 主键与 meaning_item.word_id 索引，与 seq 无关。
     */
    @PostMapping("/api/getDictContentByWordIds.do")
    public Result<DictRes> getDictContentByWordIds(
            @RequestParam("dictId") String dictId,
            @RequestParam("wordIds") String wordIdsJson,
            @RequestHeader(value = "X-User-Id", required = false) String userId) {
        String denyReason = dictReadDenyReason(dictId, userId);
        if (denyReason != null) {
            return Result.fail(denyReason);
        }

        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            List<String> wordIds = mapper.readValue(wordIdsJson,
                    new com.fasterxml.jackson.core.type.TypeReference<List<String>>() {});
            return Result.success(systemHealthCheckBo.getDictContentByWordIds(dictId, wordIds));
        } catch (Exception e) {
            return Result.fail("获取词书补件数据失败: " + e.getMessage());
        }
    }

    /** 系统词书任何人可读；用户自建词书只能本人读 */
    private String dictReadDenyReason(String dictId, String userId) {
        Dict dict = dictBo.findById(dictId);
        if (dict == null) {
            return "词书不存在: " + dictId;
        }
        String ownerId = dict.getOwner() == null ? null : dict.getOwner().getId();
        if (beidanci.util.Constants.SYS_USER_SYS_ID.equals(ownerId)) {
            return null;
        }
        if (userId != null && userId.equals(ownerId)) {
            return null;
        }
        return "无权读取该词书: " + dictId;
    }

    /**
     * 系统词典列表及其统计信息
     * 返回所有系统词典和每个词典被用户选择的数量
     */
    @GetMapping("/getSystemDictsWithStats.do")
    public Result<List<DictStatsVo>> getSystemDictsWithStats() {
        List<DictStatsVo> result = dictBo.getSystemDictsWithStats();
        return Result.success(result);
    }

    /**
     * 获取指定词典的详细统计信息
     */
    @GetMapping("/getDictStats.do")
    public Result<DictStatsVo> getDictStats(@RequestParam("dictId") String dictId) {
        DictStatsVo result = dictBo.getDictStats(dictId);
        return Result.success(result);
    }

    /**
     * 为客户端自愈拉取缺失单词包（非管理员接口）
     */
    @PostMapping("/api/getFallbackWordsData.do")
    public Result<java.util.Map<String, Object>> getFallbackWordsData(
            @RequestParam("wordIds") String wordIdsJson,
            @org.springframework.web.bind.annotation.RequestHeader(value = "X-User-Id", required = false) String userId) {
        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            List<String> ids = mapper.readValue(wordIdsJson, new com.fasterxml.jackson.core.type.TypeReference<List<String>>(){});
            if (ids.isEmpty()) return Result.success(new java.util.HashMap<>());
            
            return Result.success(systemHealthCheckBo.getFallbackWordsData(ids, userId));
        } catch (Exception e) {
            return Result.fail("获取基础补丁数据失败: " + e.getMessage());
        }
    }

    /**
     * 生成 AI 短文 - 遗留接口 (兼容旧版本)
     */
    @PostMapping("/generateAiShortStory.do")
    public DeferredResult<Result<AiStoryVo>> legacyGenerateAiShortStory(
            @RequestParam("wordsJson") String wordsJson,
            @RequestParam(value = "userId", required = false) String userId) {
        if (userId == null || userId.isEmpty()) {
            userId = userBo.getSysUser_sys(false).getId();
        }
        return aiController.generateAiShortStory(wordsJson, userId);
    }

    /**
     * 为客户端提供专项词书部分范围的资源（用于靶向修复数据断层）
     */
    @GetMapping("/api/getDictResRange.do")
    public Result<DictRes> getDictResRange(
            @RequestParam("dictId") String dictId,
            @RequestParam("fromSeq") Integer fromSeq,
            @RequestParam("toSeq") Integer toSeq) throws IOException, ParseException {
        
        // 使用构造函数实例化 DictRes
        DictRes res = new DictRes(
            dictBo.toDto(dictBo.findById(dictId)), // dict
            dictWordBo.getDictWordsOfDictBySeqRange(dictId, fromSeq, toSeq),
            wordBo.getWordsOfDictBySeqRange(dictId, fromSeq, toSeq),
            meaningItemBo.getMeaningItemsOfDictBySeqRange(dictId, fromSeq, toSeq),
            wordBo.getSimilarWordsOfDictBySeqRange(dictId, fromSeq, toSeq),
            synonymBo.getSynonymsOfDictBySeqRange(dictId, fromSeq, toSeq),
            sentenceBo.getSentencesOfDictBySeqRange(dictId, fromSeq, toSeq),
            wordBo.getWordImagesOfDictBySeqRange(dictId, fromSeq, toSeq),
            wordCoreImageBo.getWordCoreImagesOfDictBySeqRange(dictId, fromSeq, toSeq),
            cigenBo.getAllCigenDtos(),
            cigenBo.getCigenWordLinkDtosOfDictBySeqRange(dictId, fromSeq, toSeq)
        );
        
        return Result.success(res);
    }
}
