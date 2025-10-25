package beidanci.service.controller;

import java.io.IOException;
import java.io.PrintWriter;
import java.text.ParseException;
import java.util.List;
import java.util.zip.GZIPOutputStream;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import beidanci.api.Result;
import beidanci.api.model.DictDto;
import beidanci.api.model.DictRes;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.MeaningItemDto;
import beidanci.api.model.SentenceDto;
import beidanci.api.model.SimilarWordDto;
import beidanci.api.model.SynonymDto;
import beidanci.api.model.WordDto;
import beidanci.api.model.WordImageDto;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.MeaningItemBo;
import beidanci.service.bo.SentenceBo;
import beidanci.service.bo.SynonymBo;
import beidanci.service.bo.WordBo;
import beidanci.util.Constants;
import beidanci.util.CountingOutputStream;

@RestController
public class ResController {
    private static final Logger logger = LoggerFactory.getLogger(ResController.class);
    
    @Autowired
    DictBo dictBo;

    @Autowired
    WordBo wordBo;

    @Autowired
    SynonymBo synonymBo;

    @Autowired
    MeaningItemBo meaningItemBo;

    @Autowired
    SentenceBo sentenceBo;

    @Autowired
    DictWordBo dictWordBo;

    @GetMapping("/res/getDictResById.do")
    public void getDictResById(@RequestParam String dictId, HttpServletRequest request, HttpServletResponse response)
            throws IOException, ParseException {
        
        // 设置响应类型，让 Spring Boot 自动处理 chunked 传输
        response.setContentType("application/json;charset=UTF-8");
        
        // 检查客户端是否支持 gzip
        String acceptEncoding = request.getHeader("Accept-Encoding");
        boolean supportsGzip = acceptEncoding != null && acceptEncoding.contains("gzip");
        if (supportsGzip) {
            response.setHeader("Content-Encoding", "gzip");
        }
        
        
        long startTime = System.currentTimeMillis();
        logger.info("🔄 开始查询词典资源, dictId: {}", dictId);
        
        try {
            // 对通用词典先做一次数据库层面的释义补全（幂等）
            if (Constants.COMMON_DICT_ID.equals(dictId)) {
                try {
                    int inserted = meaningItemBo.supplementCommonMeanings();
                    logger.info("🧩 通用词典释义补全完成, 新增条数: {}", inserted);
                } catch (Exception e) {
                    logger.warn("⚠️ 通用释义补全执行失败: {}", e.getMessage());
                }
            }

            // 查询词典基本信息
            DictDto dict = dictBo.getDictDto(dictId);
            
            // 查询词典单词
            List<DictWordDto> dictWords = dictWordBo.getDictWordsOfDict(dictId);
            logger.info("📝 词典单词关系查询完成, 数量: {}", dictWords.size());
            
            // 查询单词详细信息
            List<WordDto> words = wordBo.getWordsOfDict(dictId);
            logger.info("🔍 单词详细信息查询完成, 数量: {}", words.size());
            
            // 查询释义（此时通用释义已在库中补齐）
            List<MeaningItemDto> meaningItems = meaningItemBo.getMeaningItemsOfDict(dictId);
            logger.info("📚 释义信息查询完成, 数量: {}", meaningItems.size());
            
            // 查询同义词
            List<SynonymDto> synonyms = synonymBo.getSynonymsOfDict(dictId);
            logger.info("🔄 同义词查询完成, 数量: {}", synonyms.size());
            
            // 查询相似词
            List<SimilarWordDto> similarWords = wordBo.getSimilarWordsOfDict(dictId);
            logger.info("🔗 相似词查询完成, 数量: {}", similarWords.size());
            
            // 查询例句
            List<SentenceDto> sentences = sentenceBo.getSentencesOfDict(dictId);
            logger.info("💬 例句查询完成, 数量: {}", sentences.size());
            
            // 查询图片
            List<WordImageDto> images = wordBo.getWordImagesOfDict(dictId);
            logger.info("🖼️ 单词图片查询完成, 数量: {}", images.size());
            
            // 构建响应对象
            // 对于通用词典，不返回 dictWords 以减少响应大小
            DictRes dictRes = new DictRes(dict, dictWords, words, meaningItems, similarWords, synonyms, sentences, images);
            Result<DictRes> result = Result.success(dictRes);
            
            // 使用 chunked 模式流式写入 JSON，并统计传输大小
            ObjectMapper mapper = new ObjectMapper();
            mapper.disable(SerializationFeature.FAIL_ON_EMPTY_BEANS);
            // 配置日期序列化为 ISO-8601 字符串格式，而不是时间戳
            mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
            mapper.setDateFormat(new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
            
            // 先计算原始JSON大小
            String originalJson = mapper.writeValueAsString(result);
            long originalSize = originalJson.getBytes("UTF-8").length;
            
            // 声明实际传输字节数变量
            long actualBytes;
            
            // 对于词典资源这种已知大小的响应，使用 Content-Length 模式
            // 这样可以提供准确的进度显示和完整性验证
            if (supportsGzip) {
                // 使用 gzip 压缩时，由于压缩后大小未知，使用 chunked 模式
                logger.info("📦 使用 chunked 模式 + gzip 压缩传输");
                
                CountingOutputStream countingOut = new CountingOutputStream(response.getOutputStream());
                try (GZIPOutputStream gzipOut = new GZIPOutputStream(countingOut)) {
                    mapper.writeValue(gzipOut, result);
                    gzipOut.flush();
                }
                actualBytes = countingOut.getByteCount();
            } else {
                // 不压缩时使用 Content-Length 模式
                response.setHeader("Content-Length", String.valueOf(originalSize));
                logger.info("📦 使用 Content-Length 模式传输");
                
                mapper.writeValue(response.getOutputStream(), result);
                actualBytes = originalSize; // 使用原始大小作为实际传输大小
            }
            
            // 获取实际传输的字节数
            double actualSizeMB = actualBytes / (1024.0 * 1024.0);
            double originalSizeMB = originalSize / (1024.0 * 1024.0);
            
            // 计算压缩率
            double compressionRatio = 0.0;
            if (supportsGzip && originalSize > 0) {
                compressionRatio = (1.0 - (double) actualBytes / originalSize) * 100.0;
            }
            
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;
            
            if (supportsGzip) {
                logger.info("✅ 词典资源查询完成, dictId: {}, 耗时: {}ms, 原始大小: {}MB ({}字节), 压缩后: {}MB ({}字节), 压缩率: {}%, 词典单词关系: {}, 单词: {}, 释义数: {}, 例句数: {}", 
                    dictId, duration, String.format("%.2f", originalSizeMB), originalSize, String.format("%.2f", actualSizeMB), actualBytes, String.format("%.1f", compressionRatio), dictWords.size(), words.size(), meaningItems.size(), sentences.size());
            } else {
                logger.info("✅ 词典资源查询完成, dictId: {}, 耗时: {}ms, 传输大小: {}MB ({}字节), 词典单词关系: {}, 单词: {}, 释义数: {}, 例句数: {}", 
                    dictId, duration, String.format("%.2f", actualSizeMB), actualBytes, dictWords.size(), words.size(), meaningItems.size(), sentences.size());
            }
            
        } catch (IOException | ParseException e) {
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;
            logger.error("❌ 词典资源查询失败, dictId: {}, 耗时: {}ms, 错误: {}", dictId, duration, e.getMessage(), e);
            
            // 返回错误响应
            try {
                Result<Object> errorResult = Result.fail(e.getMessage());
                ObjectMapper mapper = new ObjectMapper();
                String errorJson = mapper.writeValueAsString(errorResult);
                
                PrintWriter writer = response.getWriter();
                writer.write(errorJson);
                writer.flush();
            } catch (IOException ex) {
                logger.error("❌ 生成错误响应失败", ex);
                response.setStatus(500);
            }
        }
    }
}
