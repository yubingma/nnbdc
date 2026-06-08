package beidanci.service.bo;

import beidanci.api.model.WordDto;
import beidanci.service.config.AliyunAiProperties;
import beidanci.service.po.Word;
import beidanci.service.po.WordEmbedding;
import beidanci.service.util.JsonUtils;
import beidanci.util.Constants;
import com.google.gson.Gson;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.http.client.OkHttp3ClientHttpRequestFactory;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;

import javax.annotation.PostConstruct;
import java.io.File;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.*;

@Service
@Transactional(rollbackFor = Throwable.class)
public class EmbeddingBo {

    private static final Logger log = LoggerFactory.getLogger(EmbeddingBo.class);

    public static final String CURRENT_MODEL_NAME = "text-embedding-v3";

    @Autowired
    private WordBo wordBo;

    @Autowired
    private WordEmbeddingBo wordEmbeddingBo;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @Autowired
    private AliyunAiProperties aliyunAiProperties;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    private float[] mean;
    private float[][] components;
    private int fittedWordCount;

    private RestTemplate restTemplate;

    // 重构相关的状态控制
    private volatile String reconstructStatus = "IDLE"; // IDLE, RUNNING, SUCCESS, FAILED
    private volatile String reconstructMsg = "";
    private volatile double reconstructProgress = 0.0;

    @PostConstruct
    public void init() {
        loadPcaConfig();
    }

    /**
     * 加载 PCA 配置：优先从数据库加载，若无则使用默认内置资源
     */
    private void loadPcaConfig() {
        try {
            // 1. 尝试从数据库加载
            String sql = "SELECT config_json FROM pca_projection_config WHERE id = 'latest'";
            List<String> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> rs.getString("config_json"));
            String jsonStr = null;
            if (!results.isEmpty()) {
                jsonStr = results.get(0);
                log.info("从数据库中成功加载最新的 PCA 配置。");
            }

            // 2. 降级从资源文件加载
            if (jsonStr == null) {
                try (InputStream is = getClass().getClassLoader().getResourceAsStream("pca_config.json")) {
                    if (is != null) {
                        jsonStr = new String(is.readAllBytes(), StandardCharsets.UTF_8);
                        log.info("从内置资源包中加载默认的 PCA 配置。");
                    }
                }
            }

            if (jsonStr == null) {
                log.warn("未找到任何有效 PCA 降维配置，PCA 投影将不可用。");
                return;
            }

            Gson gson = new Gson();
            PcaConfig config = gson.fromJson(jsonStr, PcaConfig.class);
            this.fittedWordCount = config.getFittedWordCount();

            List<Float> meanList = config.getMean();
            this.mean = new float[meanList.size()];
            for (int i = 0; i < meanList.size(); i++) {
                this.mean[i] = meanList.get(i);
            }

            List<List<Float>> compList = config.getComponents();
            this.components = new float[compList.size()][];
            for (int i = 0; i < compList.size(); i++) {
                List<Float> row = compList.get(i);
                this.components[i] = new float[row.size()];
                for (int j = 0; j < row.size(); j++) {
                    this.components[i][j] = row.get(j);
                }
            }
            log.info("PCA 降维矩阵配置解析完成。维度: mean={}, components={}x{}",
                    this.mean.length, this.components.length, this.components[0].length);
        } catch (Exception e) {
            log.error("加载 PCA 配置失败", e);
        }
    }

    private RestTemplate getRestTemplate() {
        if (restTemplate == null) {
            okhttp3.OkHttpClient client = new okhttp3.OkHttpClient.Builder()
                    .connectTimeout(java.time.Duration.ofSeconds(60))
                    .readTimeout(java.time.Duration.ofSeconds(60))
                    .build();
            restTemplate = new RestTemplate(new OkHttp3ClientHttpRequestFactory(client));
        }
        return restTemplate;
    }

    /**
     * 1024 维到 3 维投影
     */
    public float[] projectTo3D(float[] embedding) {
        if (mean == null || components == null) {
            log.error("PCA 投影未正确初始化");
            return new float[]{0f, 0f, 0f};
        }
        assert embedding.length == mean.length : "输入的向量维度必须为 " + mean.length;

        // 1. 减去均值
        float[] centered = new float[embedding.length];
        for (int i = 0; i < embedding.length; i++) {
            centered[i] = embedding[i] - mean[i];
        }

        // 2. 矩阵相乘 centered * components
        float[] result = new float[3];
        for (int col = 0; col < 3; col++) {
            float sum = 0f;
            for (int row = 0; row < centered.length; row++) {
                sum += centered[row] * components[row][col];
            }
            result[col] = sum;
        }
        return result;
    }

    /**
     * 批量获取通义千问 Embeddings (每次最多 10 词)
     */
    public List<float[]> getEmbeddings(List<String> spells) {
        String apiKey = aliyunAiProperties.getApiKey();
        if (apiKey == null || apiKey.isEmpty() || apiKey.startsWith("${")) {
            throw new RuntimeException("AI 调用失败: 请设置 dashscope_api_key");
        }

        String url = "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings";
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + apiKey);
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, Object> body = new HashMap<>();
        body.put("model", CURRENT_MODEL_NAME);
        body.put("input", spells);
        body.put("dimensions", 1024);

        HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
        try {
            ResponseEntity<Map> response = getRestTemplate().postForEntity(url, entity, Map.class);
            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                Map resBody = response.getBody();
                List<Map> dataList = (List<Map>) resBody.get("data");
                if (dataList != null) {
                    List<float[]> results = new ArrayList<>();
                    // OpenAI 兼容格式下，可能乱序，需要按照 index 进行排序装填
                    dataList.sort((a, b) -> Integer.compare((int) a.get("index"), (int) b.get("index")));
                    for (Map data : dataList) {
                        List<Number> embList = (List<Number>) data.get("embedding");
                        float[] emb = new float[embList.size()];
                        for (int i = 0; i < embList.size(); i++) {
                            emb[i] = embList.get(i).floatValue();
                        }
                        results.add(emb);
                    }
                    return results;
                }
            }
            throw new RuntimeException("API 响应无效: status=" + response.getStatusCode());
        } catch (Exception e) {
            log.error("调用通义千问 Embedding API 失败", e);
            throw new RuntimeException("获取词嵌入向量失败: " + e.getMessage(), e);
        }
    }

    /**
     * 补全单词书中缺失词嵌入的单词
     */
    @Transactional(rollbackFor = Throwable.class)
    public void completeEmbeddingsForDict(String dictId) {
        log.info("开始增量补全词典 [{}] 中缺失词嵌入的单词...", dictId);

        // 1. 查询所有缺少 vec_x, vec_y, vec_z，或者其高维嵌入模型不匹配当前配置的单词
        String sql = "SELECT w.id, w.spell FROM word w " +
                "INNER JOIN dict_word dw ON dw.word_id = w.id " +
                "LEFT JOIN word_embedding we ON we.id = w.id " +
                "WHERE dw.dict_id = :dictId " +
                "AND (we.embedding IS NULL OR we.model_name <> :modelName)";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", dictId);
        params.addValue("modelName", CURRENT_MODEL_NAME);
        List<Map<String, Object>> missingWords = namedParameterJdbcTemplate.queryForList(sql, params);

        if (missingWords.isEmpty()) {
            log.info("词典 [{}] 所有单词词嵌入坐标已补全，无需处理。", dictId);
            return;
        }

        log.info("发现词典 [{}] 中有 {} 个单词缺失词嵌入坐标，准备批量获取...", dictId, missingWords.size());

        List<String> spellsBatch = new ArrayList<>();
        List<String> idsBatch = new ArrayList<>();

        for (int i = 0; i < missingWords.size(); i++) {
            Map<String, Object> wMap = missingWords.get(i);
            spellsBatch.add((String) wMap.get("spell"));
            idsBatch.add((String) wMap.get("id"));

            // 凑满 10 个或者到了最后一个
            if (spellsBatch.size() == 10 || i == missingWords.size() - 1) {
                try {
                    List<float[]> embeddingsList = getEmbeddings(spellsBatch);
                    assert embeddingsList.size() == spellsBatch.size() : "获取的 Embeddings 数量与请求不匹配";

                    for (int j = 0; j < spellsBatch.size(); j++) {
                        String wordId = idsBatch.get(j);
                        String spell = spellsBatch.get(j);
                        float[] floats = embeddingsList.get(j);

                        // 1. 保存到 word_embedding 表
                        byte[] byteArr = floatArrayToByteArray(floats);
                        WordEmbedding existing = wordEmbeddingBo.findById(wordId);
                        if (existing != null) {
                            existing.setEmbedding(byteArr);
                            existing.setDimension(1024);
                            existing.setModelName(CURRENT_MODEL_NAME);
                            existing.setUpdateTime(new Date());
                            wordEmbeddingBo.updateEntity(existing);
                        } else {
                            WordEmbedding wordEmbedding = new WordEmbedding(wordId, byteArr, 1024, CURRENT_MODEL_NAME);
                            wordEmbedding.setCreateTime(new Date());
                            wordEmbedding.setUpdateTime(new Date());
                            wordEmbeddingBo.createEntity(wordEmbedding);
                        }

                        // 2. 降维投影
                        float[] coords = projectTo3D(floats);

                        // 3. 更新 Word 并产生同步日志
                        wordBo.updateWordVectors(wordId, coords[0], coords[1], coords[2]);
                        log.debug("成功补全单词 [{}], 降维坐标: [{}, {}, {}]", spell, coords[0], coords[1], coords[2]);
                    }
                } catch (Exception e) {
                    log.error("批量补全词嵌入任务失败，跳过该批次 " + spellsBatch, e);
                } finally {
                    spellsBatch.clear();
                    idsBatch.clear();
                }
            }
        }
        log.info("词典 [{}] 增量词嵌入补全任务执行完毕。", dictId);
    }

    /**
     * 自动补全数据库中全局缺失的 1024 维高维向量并保存到 word_embedding 表中
     */
    @Transactional(rollbackFor = Throwable.class)
    public void completeEmbeddingsForMissingWords() {
        log.info("开始增量下载全局缺失的高维词嵌入向量...");
        String sql = "SELECT w.id, w.spell FROM word w " +
                "LEFT JOIN word_embedding we ON we.id = w.id " +
                "WHERE we.embedding IS NULL OR we.model_name <> :modelName";
        MapSqlParameterSource params = new MapSqlParameterSource("modelName", CURRENT_MODEL_NAME);
        List<Map<String, Object>> missingWords = namedParameterJdbcTemplate.queryForList(sql, params);

        if (missingWords.isEmpty()) {
            log.info("没有缺失高维词嵌入的单词。");
            return;
        }

        log.info("发现全局有 {} 个单词缺失高维词嵌入，开始分批向通义千问 API 申请...", missingWords.size());

        List<String> spellsBatch = new ArrayList<>();
        List<String> idsBatch = new ArrayList<>();

        for (int i = 0; i < missingWords.size(); i++) {
            Map<String, Object> wMap = missingWords.get(i);
            spellsBatch.add((String) wMap.get("spell"));
            idsBatch.add((String) wMap.get("id"));

            if (spellsBatch.size() == 10 || i == missingWords.size() - 1) {
                try {
                    List<float[]> embeddingsList = getEmbeddings(spellsBatch);
                    assert embeddingsList.size() == spellsBatch.size() : "获取的 Embeddings 数量与请求不匹配";

                    for (int j = 0; j < spellsBatch.size(); j++) {
                        String wordId = idsBatch.get(j);
                        float[] floats = embeddingsList.get(j);
                        byte[] byteArr = floatArrayToByteArray(floats);

                        WordEmbedding existing = wordEmbeddingBo.findById(wordId);
                        if (existing != null) {
                            existing.setEmbedding(byteArr);
                            existing.setDimension(1024);
                            existing.setModelName(CURRENT_MODEL_NAME);
                            existing.setUpdateTime(new Date());
                            wordEmbeddingBo.updateEntity(existing);
                        } else {
                            WordEmbedding wordEmbedding = new WordEmbedding(wordId, byteArr, 1024, CURRENT_MODEL_NAME);
                            wordEmbedding.setCreateTime(new Date());
                            wordEmbedding.setUpdateTime(new Date());
                            wordEmbeddingBo.createEntity(wordEmbedding);
                        }
                    }
                } catch (Exception e) {
                    log.error("增量下载高维词嵌入批次失败: " + spellsBatch, e);
                } finally {
                    spellsBatch.clear();
                    idsBatch.clear();
                }
            }
        }
        log.info("全局缺失词嵌入向量补全下载完毕。");
    }

    /**
     * 一键重构 PCA 降维投影空间 (异步任务)
     */
    public void reconstructProjectionSpaceAsync() {
        if ("RUNNING".equals(reconstructStatus)) {
            throw new RuntimeException("重构任务正在执行中，请勿重复提交");
        }

        reconstructStatus = "RUNNING";
        reconstructMsg = "任务已启动...";
        reconstructProgress = 0.0;

        new Thread(() -> {
            File tempInputFile = null;
            File tempOutputFile = null;
            try {
                // 1. 自动增量下载全局缺失的高维向量
                reconstructMsg = "正在自动补全缺失的高维向量...";
                reconstructProgress = 0.05;
                try {
                    completeEmbeddingsForMissingWords();
                } catch (Exception e) {
                    log.error("自动补全全局缺失向量失败", e);
                }

                // 2. 导出全量 1024D 原始向量
                reconstructMsg = "正在导出数据库原始词嵌入...";
                reconstructProgress = 0.1;
                log.info("一键重构：开始读取数据库中所有高维向量...");

                String sql = "SELECT id, embedding FROM word_embedding WHERE model_name = :modelName";
                MapSqlParameterSource sqlParams = new MapSqlParameterSource("modelName", CURRENT_MODEL_NAME);
                List<Map<String, Object>> rows = namedParameterJdbcTemplate.queryForList(sql, sqlParams);
                if (rows.isEmpty()) {
                    throw new RuntimeException("数据库中没有任何词嵌入数据，重构中止。");
                }

                List<Map<String, Object>> exportData = new ArrayList<>();
                for (Map<String, Object> row : rows) {
                    String wordId = (String) row.get("id");
                    byte[] bytes = (byte[]) row.get("embedding");
                    float[] floats = byteArrayToFloatArray(bytes);

                    Map<String, Object> item = new HashMap<>();
                    item.put("id", wordId);
                    item.put("embedding", floats);
                    exportData.add(item);
                }

                tempInputFile = File.createTempFile("pca_input", ".json");
                tempOutputFile = File.createTempFile("pca_output", ".json");

                Gson gson = new Gson();
                Files.writeString(tempInputFile.toPath(), gson.toJson(exportData), StandardCharsets.UTF_8);

                // 2. 自动定位 Python 执行路径
                reconstructMsg = "正在查找 Python 环境...";
                reconstructProgress = 0.3;
                log.info("一键重构：正在寻找 Python 环境...");

                String pythonPath = "python3";
                String[] possiblePaths = {
                        "../.venv/bin/python",
                        "../.venv/Scripts/python.exe",
                        ".venv/bin/python",
                        ".venv/Scripts/python.exe",
                        "python3",
                        "python"
                };
                for (String path : possiblePaths) {
                    try {
                        Process process = Runtime.getRuntime().exec(new String[]{path, "--version"});
                        if (process.waitFor() == 0) {
                            pythonPath = path;
                            log.info("成功定位 Python 运行路径: {}", pythonPath);
                            break;
                        }
                    } catch (Exception ignore) {}
                }

                // 3. 执行 Python 重构脚本
                reconstructMsg = "正在进行 PCA 降维拟合...";
                reconstructProgress = 0.5;
                log.info("一键重构：启动 Python 执行矩阵重新拟合...");

                String scriptPath = "scratch/reconstruct_pca.py";
                ProcessBuilder pb = new ProcessBuilder(pythonPath, scriptPath, tempInputFile.getAbsolutePath(), tempOutputFile.getAbsolutePath());
                pb.redirectErrorStream(true);
                Process process = pb.start();

                // 异步读取 Python 脚本的输出以防止进程阻塞挂起
                try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        log.info("[Python] " + line);
                    }
                }

                int exitCode = process.waitFor();
                if (exitCode != 0) {
                    throw new RuntimeException("Python 脚本执行失败，退出码: " + exitCode);
                }

                // 4. 解析结果
                reconstructMsg = "正在写回新投影矩阵与坐标...";
                reconstructProgress = 0.8;
                log.info("一键重构：解析 Python 结果并写回数据库...");

                String outputJsonStr = Files.readString(tempOutputFile.toPath(), StandardCharsets.UTF_8);
                ReconstructOutput output = gson.fromJson(outputJsonStr, ReconstructOutput.class);

                // 更新数据库的投影配置表
                String deleteSql = "DELETE FROM pca_projection_config WHERE id = 'latest'";
                namedParameterJdbcTemplate.getJdbcTemplate().update(deleteSql);

                // 重新将结果写入 pca_projection_config，包含 mean 和 components
                Map<String, Object> newConfig = new HashMap<>();
                newConfig.put("mean", output.mean);
                newConfig.put("components", output.components);
                newConfig.put("fittedWordCount", output.fittedWordCount);

                String insertSql = "INSERT INTO pca_projection_config (id, config_json, update_time) VALUES ('latest', :configJson, :updateTime)";
                MapSqlParameterSource configParams = new MapSqlParameterSource();
                configParams.addValue("configJson", gson.toJson(newConfig));
                configParams.addValue("updateTime", new Date());
                namedParameterJdbcTemplate.update(insertSql, configParams);

                // 重新加载本地缓存的投影矩阵
                loadPcaConfig();

                // 5. 批量更新 word 表的坐标
                reconstructMsg = "正在全局刷新所有单词坐标...";
                reconstructProgress = 0.9;
                log.info("一键重构：开始批量更新 word 坐标...");

                List<Map.Entry<String, List<Float>>> coordEntries = new ArrayList<>(output.word_coords.entrySet());
                String updateWordSql = "UPDATE word SET vec_x = ?, vec_y = ?, vec_z = ?, update_time = ? WHERE id = ?";
                namedParameterJdbcTemplate.getJdbcTemplate().batchUpdate(updateWordSql, new BatchPreparedStatementSetter() {
                    @Override
                    public void setValues(PreparedStatement ps, int i) throws SQLException {
                        Map.Entry<String, List<Float>> entry = coordEntries.get(i);
                        String wordId = entry.getKey();
                        List<Float> coords = entry.getValue();
                        ps.setFloat(1, coords.get(0));
                        ps.setFloat(2, coords.get(1));
                        ps.setFloat(3, coords.get(2));
                        ps.setTimestamp(4, new Timestamp(System.currentTimeMillis()));
                        ps.setString(5, wordId);
                    }

                    @Override
                    public int getBatchSize() {
                        return coordEntries.size();
                    }
                });

                // 6. 批量产生客户端更新日志
                log.info("一键重构：批量产生同步更新日志，更新量: {}", coordEntries.size());
                for (Map.Entry<String, List<Float>> entry : coordEntries) {
                    String wordId = entry.getKey();
                    List<Float> coords = entry.getValue();

                    // 只同步关键坐标改变
                    WordDto wDto = new WordDto();
                    wDto.setId(wordId);
                    wDto.setVecX(coords.get(0));
                    wDto.setVecY(coords.get(1));
                    wDto.setVecZ(coords.get(2));
                    wDto.setUpdateTime(new Date());

                    // 系统同步日志，因为单词本身是系统所有
                    sysDbSyncBo.logOperation(wDto, "UPDATE", "word", wordId, JsonUtils.toJson(wDto));
                }

                reconstructStatus = "SUCCESS";
                reconstructMsg = "重构成功！";
                reconstructProgress = 1.0;
                log.info("一键重构：投影空间重构完成。");
            } catch (Exception e) {
                log.error("一键重构降维投影任务失败", e);
                reconstructStatus = "FAILED";
                reconstructMsg = "重构失败: " + e.getMessage();
                reconstructProgress = 1.0;
            } finally {
                // 清理临时文件
                try {
                    if (tempInputFile != null && tempInputFile.exists()) tempInputFile.delete();
                    if (tempOutputFile != null && tempOutputFile.exists()) tempOutputFile.delete();
                } catch (Exception ignore) {}
            }
        }).start();
    }

    /**
     * 判断是否需要重构（未参与当前主成分拟合的词占比是否超过 30%）
     */
    public boolean isReconstructionNeeded() {
        int totalEmbeddings = getTotalWordCount();
        if (totalEmbeddings == 0) return false;
        if (fittedWordCount == 0) return true; // 如果从未训练过

        double unreconstructedRatio = (double) (totalEmbeddings - fittedWordCount) / totalEmbeddings;
        return unreconstructedRatio >= 0.30;
    }

    public int getTotalWordCount() {
        String countSql = "SELECT COUNT(1) FROM word_embedding";
        Integer total = namedParameterJdbcTemplate.getJdbcTemplate().queryForObject(countSql, Integer.class);
        return total != null ? total : 0;
    }

    public String getReconstructStatus() {
        return reconstructStatus;
    }

    public String getReconstructMsg() {
        return reconstructMsg;
    }

    public double getReconstructProgress() {
        return reconstructProgress;
    }

    public int getFittedWordCount() {
        return fittedWordCount;
    }

    public static byte[] floatArrayToByteArray(float[] floats) {
        ByteBuffer buffer = ByteBuffer.allocate(floats.length * 4);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        for (float f : floats) {
            buffer.putFloat(f);
        }
        return buffer.array();
    }

    public static float[] byteArrayToFloatArray(byte[] bytes) {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        float[] floats = new float[bytes.length / 4];
        for (int i = 0; i < floats.length; i++) {
            floats[i] = buffer.getFloat();
        }
        return floats;
    }

    // 内部类，映射配置结构
    public static class PcaConfig {
        private List<Float> mean;
        private List<List<Float>> components;
        private int fittedWordCount;

        public List<Float> getMean() { return mean; }
        public void setMean(List<Float> mean) { this.mean = mean; }
        public List<List<Float>> getComponents() { return components; }
        public void setComponents(List<List<Float>> components) { this.components = components; }
        public int getFittedWordCount() { return fittedWordCount; }
        public void setFittedWordCount(int fittedWordCount) { this.fittedWordCount = fittedWordCount; }
    }

    // 内部类，映射重构计算输出的临时 JSON 文件
    public static class ReconstructOutput {
        private List<Float> mean;
        private List<List<Float>> components;
        private Map<String, List<Float>> word_coords;
        private int fittedWordCount;
    }
}
