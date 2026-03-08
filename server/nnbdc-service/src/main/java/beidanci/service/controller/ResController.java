package beidanci.service.controller;

import java.io.IOException;
import java.io.PrintWriter;
import java.security.MessageDigest;
import java.text.ParseException;
import java.util.Date;
import java.util.List;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.ObjectMapper;

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
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WordBo;
import beidanci.service.po.User;
import beidanci.service.util.MyImage;
import beidanci.service.util.SysParamUtil;
import beidanci.util.Constants;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.multipart.MultipartFile;
import java.io.File;

@RestController
public class ResController {
    private static final Logger logger = LoggerFactory.getLogger(ResController.class);

    /**
     * 词典资源类型：
     * - SYS：系统/公共词典资源（允许 CDN 缓存）
     * - USER：用户个人词典资源（不建议 CDN 缓存）
     */
    private enum DictResType {
        SYS,
        USER
    }
    
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

    @Autowired
    UserBo userBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    private ObjectMapper objectMapper;

    @GetMapping("/res/getSysDictResById.do")
    public void getSysDictResById(@RequestParam String dictId, HttpServletRequest request, HttpServletResponse response)
            throws IOException, ParseException {
        getDictResByIdInternal(dictId, request, response, DictResType.SYS);
    }

    @GetMapping("/res/getUserDictResById.do")
    public void getUserDictResById(@RequestParam String dictId, HttpServletRequest request, HttpServletResponse response)
            throws IOException, ParseException {
        getDictResByIdInternal(dictId, request, response, DictResType.USER);
    }

    private void getDictResByIdInternal(String dictId, HttpServletRequest request, HttpServletResponse response, DictResType dictResType)
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
        logger.info("开始查询词典资源, dictId: {}, type: {}", dictId, dictResType);

        try {
            // 对通用词典先做一次数据库层面的释义补全（幂等）
            if (Constants.COMMON_DICT_ID.equals(dictId)) {
                try {
                    int inserted = meaningItemBo.supplementCommonMeanings();
                    logger.info("通用词典释义补全完成, 新增条数: {}", inserted);
                } catch (Exception e) {
                    logger.warn("通用释义补全执行失败: {}", e.getMessage());
                }
            }

            // 查询词典基本信息
            DictDto dict = dictBo.getDictDto(dictId);

            // 获取词典更新时间，用于缓存控制
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
            if (dictResType == DictResType.SYS) {
                // 系统/公共资源：允许 CDN 缓存
                response.setHeader("Cache-Control", "public, max-age=300, s-maxage=3600, stale-while-revalidate=604800, stale-if-error=604800");
            } else {
                // 用户资源：避免 CDN 缓存（仍允许客户端短期缓存）
                response.setHeader("Cache-Control", "private, max-age=300");
            }

            // 检查条件请求（If-None-Match和If-Modified-Since）
            String ifNoneMatch = request.getHeader("If-None-Match");
            long ifModifiedSince = request.getDateHeader("If-Modified-Since");

            // 如果ETag匹配或资源未修改，返回304 Not Modified
            boolean notModified = false;
            if (ifNoneMatch != null && ifNoneMatch.equals(etag)) {
                notModified = true;
                logger.debug("ETag匹配，返回304, dictId: {}, ETag: {}", dictId, etag);
            } else if (ifModifiedSince > 0 && lastModified <= ifModifiedSince) {
                notModified = true;
                logger.debug("Last-Modified未变化，返回304, dictId: {}, Last-Modified: {}", dictId, new Date(lastModified));
            }

            if (notModified) {
                response.setStatus(HttpServletResponse.SC_NOT_MODIFIED);
                logger.info("词典资源未修改，返回304, dictId: {}, type: {}", dictId, dictResType);
                return;
            }

            // 查询词典单词
            List<DictWordDto> dictWords = dictWordBo.getDictWordsOfDict(dictId);
            logger.info("词典单词关系查询完成, 数量: {}", dictWords.size());

            // 查询单词详细信息
            List<WordDto> words = wordBo.getWordsOfDict(dictId);
            logger.info("单词详细信息查询完成, 数量: {}", words.size());

            // 查询释义（此时通用释义已在库中补齐）
            List<MeaningItemDto> meaningItems = meaningItemBo.getMeaningItemsOfDict(dictId);
            logger.info("释义信息查询完成, 数量: {}", meaningItems.size());

            // 查询同义词
            List<SynonymDto> synonyms = synonymBo.getSynonymsOfDict(dictId);
            logger.info("同义词查询完成, 数量: {}", synonyms.size());

            // 查询相似词
            List<SimilarWordDto> similarWords = wordBo.getSimilarWordsOfDict(dictId);
            logger.info("相似词查询完成, 数量: {}", similarWords.size());

            // 查询例句
            List<SentenceDto> sentences = sentenceBo.getSentencesOfDict(dictId);
            logger.info("例句查询完成, 数量: {}", sentences.size());

            // 查询图片
            List<WordImageDto> images = wordBo.getWordImagesOfDict(dictId);
            logger.info("单词图片查询完成, 数量: {}", images.size());

            // 构建响应对象
            // 对于通用词典，不返回 dictWords 以减少响应大小
            DictRes dictRes = new DictRes(dict, dictWords, words, meaningItems, similarWords, synonyms, sentences, images);
            Result<DictRes> result = Result.success(dictRes);

            // 使用全局 ObjectMapper（已配置正确的时区和日期格式）

            // 先计算原始JSON大小
            String originalJson = objectMapper.writeValueAsString(result);
            long originalSize = originalJson.getBytes("UTF-8").length;

            // 声明实际传输字节数变量
            long actualBytes;

            // 为了让客户端显示“真实下载进度”，必须有 Content-Length。
            // - 不压缩：Content-Length = 原始 JSON 大小
            // - gzip：先在服务端完成压缩，得到压缩后字节数组，再设置 Content-Length
            //   这样压缩对外透明（只前后端知道），且进度条可以使用 total 计算百分比。
            if (supportsGzip) {
                logger.info("使用 gzip + Content-Length 模式传输（服务端预压缩以获得真实进度）");

                // 注意：这里会额外占用一次压缩后字节数组的内存。
                // 若后续发现内存压力，可改为：写入临时文件后再按文件长度流式输出，或引入缓存复用压缩结果。
                java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream((int) Math.min(Integer.MAX_VALUE, originalSize));
                try (java.util.zip.GZIPOutputStream gzipOut = new java.util.zip.GZIPOutputStream(baos)) {
                    objectMapper.writeValue(gzipOut, result);
                    gzipOut.finish();
                }

                byte[] gzipped = baos.toByteArray();
                response.setHeader("Content-Length", String.valueOf(gzipped.length));
                response.getOutputStream().write(gzipped);
                response.getOutputStream().flush();
                actualBytes = gzipped.length;
            } else {
                response.setHeader("Content-Length", String.valueOf(originalSize));
                logger.info("使用 Content-Length 模式传输");

                objectMapper.writeValue(response.getOutputStream(), result);
                actualBytes = originalSize;
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
                logger.info("词典资源查询完成, dictId: {}, 耗时: {}ms, 原始大小: {}MB ({}字节), 压缩后: {}MB ({}字节), 压缩率: {}%, 词典单词关系: {}, 单词: {}, 释义数: {}, 例句数: {}",
                    dictId, duration, String.format("%.2f", originalSizeMB), originalSize, String.format("%.2f", actualSizeMB), actualBytes, String.format("%.1f", compressionRatio), dictWords.size(), words.size(), meaningItems.size(), sentences.size());
            } else {
                logger.info("词典资源查询完成, dictId: {}, 耗时: {}ms, 传输大小: {}MB ({}字节), 词典单词关系: {}, 单词: {}, 释义数: {}, 例句数: {}",
                    dictId, duration, String.format("%.2f", actualSizeMB), actualBytes, dictWords.size(), words.size(), meaningItems.size(), sentences.size());
            }

        } catch (IOException | ParseException e) {
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;
            logger.error("词典资源查询失败, dictId: {}, 耗时: {}ms, 错误: {}", dictId, duration, e.getMessage(), e);

            // 返回错误响应
            try {
                Result<Object> errorResult = Result.fail(e.getMessage());
                String errorJson = objectMapper.writeValueAsString(errorResult);

                PrintWriter writer = response.getWriter();
                writer.write(errorJson);
                writer.flush();
            } catch (IOException ex) {
                logger.error("生成错误响应失败", ex);
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

    @PostMapping(value = "/uploadImg.do")
    public Result<String> uploadImg(@RequestParam("file") MultipartFile file, @RequestParam("userId") String userId) throws Exception {
        logger.info("收到图片上传请求, userId: {}, 文件名: {}, 大小: {}", userId, file.getOriginalFilename(), file.getSize());

        if (file.getSize() > 1024 * 1024) {
            return Result.fail("图片大小不能超过 1MB");
        }

        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("游客不能上传图片");
        }

        // 生成唯一文件名
        String baseName = "u_" + userId + "_" + System.currentTimeMillis();
        File tempTargetFile = new File(sysParamUtil.getImageBaseDir() + "/tmp/tmp_" + baseName);
        if (!tempTargetFile.getParentFile().exists()) {
            tempTargetFile.getParentFile().mkdirs();
        }

        file.transferTo(tempTargetFile);

        // 探测真实格式并决定目标文件名
        String fmt = null;
        try {
            fmt = MyImage.getImageFormat(tempTargetFile);
            if (fmt == null) {
                fmt = MyImage.detectFormat(tempTargetFile);
            }
        } catch (IOException ignore) { }
        String ext = MyImage.normalizeExtByFormat(fmt);
        String fileName = baseName + "." + ext;
        File targetFile = new File(sysParamUtil.getImageBaseDir() + "/word/" + fileName);

        // 通过图像缩放生成大图
        int targetWidth = 200;
        int targetHeight = 200;
        try {
            if (fmt != null && MyImage.canWriteFormat(fmt)) {
                MyImage.resizeImage(tempTargetFile, targetFile, targetWidth, targetHeight, fmt, true);
            } else {
                org.apache.commons.io.FileUtils.copyFile(tempTargetFile, targetFile);
            }
        } catch (IOException ex) {
            org.apache.commons.io.FileUtils.copyFile(tempTargetFile, targetFile);
        }

        // 删除临时文件
        if (!tempTargetFile.delete()) {
            tempTargetFile.deleteOnExit();
        }

        return Result.success(fileName);
    }
}
