package beidanci.service.controller;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.GZIPOutputStream;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import beidanci.api.Result;
import beidanci.api.model.UserDbLogDto;
import beidanci.service.bo.SyncBo;
import beidanci.service.bo.UserBo;
import beidanci.service.exception.RawWordDataErrorException;
import beidanci.service.exception.DbVersionNotMatchException;
import beidanci.util.CountingOutputStream;

@RestController
public class SyncController {
    private static final Logger log = LoggerFactory.getLogger(SyncController.class);

    @Autowired
    UserBo userBo;

    @Autowired
    SyncBo syncBo;

    /**
     * 获取用户数据库（服务端）的增量日志
     * 使用流式传输模式，支持gzip压缩和chunked传输
     *
     * @param localDbVersion 用户本地数据库当前版本, 将返回服务端在此版本之后的增量日志
     * @param userId 用户ID，用于在客户端未登录时指定要同步的用户
     * @param request HTTP请求对象
     * @param response HTTP响应对象
     */
    @GetMapping("/getNewDbLogs.do")
    public void getNewDbLogs(int localDbVersion, @RequestParam("userId") String userId, 
                           HttpServletRequest request, HttpServletResponse response) throws IOException {
        
        // 设置响应类型，让 Spring Boot 自动处理 chunked 传输
        response.setContentType("application/json;charset=UTF-8");
        
        // 检查客户端是否支持 gzip
        String acceptEncoding = request.getHeader("Accept-Encoding");
        boolean supportsGzip = acceptEncoding != null && acceptEncoding.contains("gzip");
        if (supportsGzip) {
            response.setHeader("Content-Encoding", "gzip");
        }
        
        
        long startTime = System.currentTimeMillis();
        log.info("🔄 开始查询用户数据库日志, userId: {}, localDbVersion: {}", userId, localDbVersion);
        
        try {
            // 查询用户数据库增量日志
            List<UserDbLogDto> logs = userBo.getUserNewDbLogs(userId, localDbVersion);
            log.info("📋 用户数据库增量日志查询完成, 数量: {}", logs.size());
            
            // 构建响应对象
            Result<List<UserDbLogDto>> result = Result.success(logs);
            
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
            
            // 对于数据库日志这种已知大小的响应，使用 Content-Length 模式
            // 这样可以提供准确的进度显示和完整性验证
            if (supportsGzip) {
                // 使用 gzip 压缩时，由于压缩后大小未知，使用 chunked 模式
                log.info("📦 使用 chunked 模式 + gzip 压缩传输");
                
                CountingOutputStream countingOut = new CountingOutputStream(response.getOutputStream());
                try (GZIPOutputStream gzipOut = new GZIPOutputStream(countingOut)) {
                    mapper.writeValue(gzipOut, result);
                    gzipOut.flush();
                }
                actualBytes = countingOut.getByteCount();
            } else {
                // 不压缩时使用 Content-Length 模式
                response.setHeader("Content-Length", String.valueOf(originalSize));
                log.info("📦 使用 Content-Length 模式传输");
                
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
                log.info("✅ 用户数据库日志查询完成, userId: {}, localDbVersion: {}, 耗时: {}ms, 原始大小: {}MB ({}字节), 压缩后: {}MB ({}字节), 压缩率: {}%, 日志数量: {}", 
                    userId, localDbVersion, duration, String.format("%.2f", originalSizeMB), originalSize, String.format("%.2f", actualSizeMB), actualBytes, String.format("%.1f", compressionRatio), logs.size());
            } else {
                log.info("✅ 用户数据库日志查询完成, userId: {}, localDbVersion: {}, 耗时: {}ms, 传输大小: {}MB ({}字节), 日志数量: {}", 
                    userId, localDbVersion, duration, String.format("%.2f", actualSizeMB), actualBytes, logs.size());
            }
            
        } catch (IOException e) {
            long endTime = System.currentTimeMillis();
            long duration = endTime - startTime;
            log.error("❌ 用户数据库日志查询失败, userId: {}, localDbVersion: {}, 耗时: {}ms, 错误: {}", 
                userId, localDbVersion, duration, e.getMessage(), e);
            
            // 返回错误响应
            try {
                Result<Object> errorResult = Result.fail(e.getMessage());
                ObjectMapper mapper = new ObjectMapper();
                String errorJson = mapper.writeValueAsString(errorResult);
                
                PrintWriter writer = response.getWriter();
                writer.write(errorJson);
                writer.flush();
            } catch (IOException ex) {
                log.error("❌ 生成错误响应失败", ex);
                response.setStatus(500);
            }
        }
    }

    /**
     * 用户把本地数据库的最新变更，同步到服务端数据库
     *
     * @param logs                    用户本地库修改日志
     * @param expectedServerDbVersion 期望的服务端数据库版本（如不匹配，则本次同步失败）
     * @param userId                  用户ID，用于在客户端未登录时指定要同步的用户
     * @return 服务端数据库最新版本, 如果为null，表示同步失败
     * @throws DbVersionNotMatchException 
     */
    @PostMapping("/syncUserDb2Back.do")
    public Result<Integer> syncUserDb2Back(@RequestParam("expectedServerDbVersion") int expectedServerDbVersion,
                                 @RequestParam("userId") String userId,
                                 @RequestBody ArrayList<UserDbLogDto> logs) throws IllegalAccessException, DbVersionNotMatchException {
        try {
            int lastVersion = syncBo.syncUserDb2Back(userId, expectedServerDbVersion, logs);
            return Result.success(lastVersion);
        } catch (RawWordDataErrorException e) {
            log.info("", e);
            // 返回特殊错误码，前端用来触发全量覆盖同步
            return new Result<>("RAW_WORD_ORDER_INVALID", e.getMessage(), null);
        }
    }



}
