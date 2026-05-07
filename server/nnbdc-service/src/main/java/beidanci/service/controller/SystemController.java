package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.*;
import beidanci.service.bo.*;
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

    /**
     * 获取系统词典列表及其统计信息
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
            wordBo.getWordImagesOfDictBySeqRange(dictId, fromSeq, toSeq)
        );
        
        return Result.success(res);
    }
}
