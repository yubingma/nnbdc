package beidanci.service.controller;

import java.io.IOException;
import java.io.PrintWriter;
import java.security.MessageDigest;
import java.text.ParseException;
import java.util.Date;
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
            
            // 获取词典更新时间，用于CDN缓存控制
            Date updateTime = dict != null ? dict.getUpdateTime() : null;
            if (updateTime == null) {
                updateTime = new Date(); // 如果没有更新时间，使用当前时间
            }
            
            // 生成ETag（基于dictId和updateTime）
            String etag = generateETag(dictId, updateTime);
            
            // 设置Last-Modified头（HTTP日期格式）
            long lastModified = updateTime.getTime();
            response.setDateHeader("Last-Modified", lastModified);
            response.setHeader("ETag", etag);
            
            // 设置Cache-Control头
            // 缓存机制说明：
            // - max-age: 客户端（浏览器/App）的缓存时间，过期后客户端会重新请求
            // - s-maxage: CDN节点的缓存时间，过期后CDN会回源检查资源是否更新
            // - stale-while-revalidate: CDN缓存过期后，在后台异步更新缓存的同时，继续使用旧缓存服务请求
            //   这样可以避免缓存过期瞬间的大量回源请求，让流量完全落在CDN上
            // - stale-if-error: 当源站异常时，CDN可以继续使用过期缓存提供服务
            // - 当CDN缓存过期回源时，如果资源未修改（ETag/Last-Modified匹配），服务器返回304，
            //   304响应只包含响应头（约200-300字节），没有响应体，回源成本极低
            // - 如果资源已更新，服务器返回200和新内容，CDN更新缓存
            // 统一配置：
            //   - CDN缓存1小时（s-maxage=3600），过期后继续服务旧内容7天（stale-while-revalidate=604800）
            //   - 源站异常时继续服务旧内容7天（stale-if-error=604800）
            //   - 客户端缓存5分钟（max-age=300）
            // 为什么1小时缓存不会有问题：
            // 1. 1小时内所有请求都在CDN，不回源
            // 2. 1小时后回源检查，如果词典未更新（常见情况），返回304（只有响应头，约200-300字节）
            // 3. 304响应成本极低，不会对服务器造成压力
            // 4. 如果CDN支持stale-while-revalidate，即使缓存过期，流量也完全落在CDN上
            response.setHeader("Cache-Control", "public, max-age=300, s-maxage=3600, stale-while-revalidate=604800, stale-if-error=604800");
            
            // 检查条件请求（If-None-Match和If-Modified-Since）
            String ifNoneMatch = request.getHeader("If-None-Match");
            long ifModifiedSince = request.getDateHeader("If-Modified-Since");
            
            // 如果ETag匹配或资源未修改，返回304 Not Modified
            boolean notModified = false;
            if (ifNoneMatch != null && ifNoneMatch.equals(etag)) {
                notModified = true;
                logger.debug("📋 ETag匹配，返回304, dictId: {}, ETag: {}", dictId, etag);
            } else if (ifModifiedSince > 0 && lastModified <= ifModifiedSince) {
                notModified = true;
                logger.debug("📋 Last-Modified未变化，返回304, dictId: {}, Last-Modified: {}", dictId, new Date(lastModified));
            }
            
            if (notModified) {
                response.setStatus(HttpServletResponse.SC_NOT_MODIFIED);
                logger.info("✅ 词典资源未修改，返回304, dictId: {}", dictId);
                return;
            }
            
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
    
    /**
     * 生成ETag（基于dictId和updateTime）
     * ETag格式: "dict-{dictId}-{updateTime的毫秒数}"
     * 为了更安全，使用MD5生成短ETag
     */
    private String generateETag(String dictId, Date updateTime) {
        try {
            String content = dictId + "-" + updateTime.getTime();
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] hash = md.digest(content.getBytes("UTF-8"));
            StringBuilder sb = new StringBuilder();
            sb.append("\"");
            for (byte b : hash) {
                sb.append(String.format("%02x", b));
            }
            sb.append("\"");
            return sb.toString();
        } catch (Exception e) {
            logger.warn("生成ETag失败，使用简单格式, dictId: {}", dictId, e);
            // 如果MD5失败，使用简单格式
            return "\"dict-" + dictId + "-" + updateTime.getTime() + "\"";
        }
    }
}
