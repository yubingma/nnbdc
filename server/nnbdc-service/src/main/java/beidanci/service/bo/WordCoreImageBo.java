package beidanci.service.bo;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;

import beidanci.service.dao.EntityRowMapper;
import beidanci.service.dao.WordCoreImageDao;
import beidanci.service.po.MeaningItem;
import beidanci.service.po.Word;
import beidanci.service.po.WordCoreImage;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordCoreImageBo extends BaseBo<WordCoreImage> {

    private static final Logger log = LoggerFactory.getLogger(WordCoreImageBo.class);

    @Resource
    private WordCoreImageDao wordCoreImageDao;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private MeaningItemBo meaningItemBo;

    @Autowired
    private AiBo aiBo;

    @Autowired
    private SysParamUtil sysParamUtil;

    private RestTemplate restTemplate = new RestTemplate();

    @PostConstruct
    public void init() {
        setDao(wordCoreImageDao);
        ensureTableExists();
    }

    private void ensureTableExists() {
        String sql = "CREATE TABLE IF NOT EXISTS `word_core_image` ("
                + "`id` VARCHAR(32) NOT NULL,"
                + "`word_id` VARCHAR(32) NOT NULL,"
                + "`word` VARCHAR(100) NOT NULL,"
                + "`is_applicable` TINYINT(1) NOT NULL DEFAULT 0,"
                + "`not_applicable_reason` VARCHAR(255) DEFAULT NULL,"
                + "`core_image` VARCHAR(255) DEFAULT NULL,"
                + "`schema_desc` VARCHAR(1000) DEFAULT NULL,"
                + "`topology_json` MEDIUMTEXT DEFAULT NULL,"
                + "`image_prompt` TEXT DEFAULT NULL,"
                + "`image_url` VARCHAR(500) DEFAULT NULL,"
                + "`image_status` VARCHAR(32) DEFAULT NULL,"
                + "`image_model` VARCHAR(100) DEFAULT NULL,"
                + "`create_time` DATETIME NOT NULL,"
                + "`update_time` DATETIME NOT NULL,"
                + "PRIMARY KEY (`id`),"
                + "UNIQUE KEY `idx_wci_word_id` (`word_id`),"
                + "KEY `idx_wci_word` (`word`)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
        try {
            jdbcTemplate.execute(sql);
            log.info("word_core_image 数据表检查/初始化完成");
        } catch (Exception e) {
            log.error("初始化 word_core_image 数据表失败: ", e);
        }
    }

    public WordCoreImage findByWordId(String wordId) {
        String sql = "SELECT * FROM word_core_image WHERE word_id = :wordId LIMIT 1";
        Map<String, Object> params = new HashMap<>();
        params.put("wordId", wordId);
        List<WordCoreImage> list = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(WordCoreImage.class));
        return list.isEmpty() ? null : list.get(0);
    }

    public int countTotalWords() {
        String sql = "SELECT COUNT(*) FROM word";
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class);
        return count != null ? count : 0;
    }

    public int countProcessedWords() {
        String sql = "SELECT COUNT(*) FROM word_core_image";
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class);
        return count != null ? count : 0;
    }

    public int countApplicableWords() {
        String sql = "SELECT COUNT(*) FROM word_core_image WHERE is_applicable = 1";
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class);
        return count != null ? count : 0;
    }

    public int countSkippedWords() {
        String sql = "SELECT COUNT(*) FROM word_core_image WHERE is_applicable = 0";
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class);
        return count != null ? count : 0;
    }

    public List<Map<String, Object>> getRecentSuccessRecords(int limit) {
        String sql = "SELECT word, core_image, image_url, image_status, is_applicable, not_applicable_reason, update_time "
                + "FROM word_core_image ORDER BY update_time DESC LIMIT :limit";
        Map<String, Object> params = new HashMap<>();
        params.put("limit", limit);
        return namedParameterJdbcTemplate.queryForList(sql, params);
    }

    public List<Word> findNextUnprocessedWords(int limit) {
        String sql = "SELECT w.* FROM word w "
                + "LEFT JOIN word_core_image wci ON w.id = wci.word_id "
                + "WHERE wci.id IS NULL "
                + "ORDER BY w.popularity DESC, w.spell ASC "
                + "LIMIT :limit";
        Map<String, Object> params = new HashMap<>();
        params.put("limit", limit);
        return namedParameterJdbcTemplate.query(sql, params, new EntityRowMapper<>(Word.class));
    }

    /**
     * 对单个单词进行全流程处理：1.评估与提取拓扑 2.驱动生图模型
     */
    public WordCoreImage processWord(Word word) {
        if (word == null) {
            return null;
        }

        // 先检查是否已经存在记录
        WordCoreImage existing = findByWordId(word.getId());
        if (existing != null && existing.getIsApplicable() != null) {
            if (!existing.getIsApplicable()) {
                // 不适合的词之前已经判定过了，直接返回
                return existing;
            }
            if ("SUCCESS".equalsIgnoreCase(existing.getImageStatus()) && existing.getImageUrl() != null) {
                // 已经生成完毕，跳过
                return existing;
            }
            // 适合但图片尚未成功，直接驱动生图
            generateImage(existing);
            return existing;
        }

        // 1. 获取该单词的所有释义
        List<MeaningItem> meanings = meaningItemBo.findEntitiesByWord(word.getId());
        if (meanings == null || meanings.isEmpty()) {
            WordCoreImage wci = new WordCoreImage();
            wci.setId(Util.uuid());
            wci.setWordId(word.getId());
            wci.setWord(word.getSpell());
            wci.setIsApplicable(false);
            wci.setNotApplicableReason("词库中无释义数据");
            wci.setImageStatus("SKIPPED");
            wci.setCreateTime(new Date());
            wci.setUpdateTime(new Date());
            createEntity(wci);
            return wci;
        }

        // 2. 调用大模型判断与提取拓扑
        WordCoreImage wci = evaluateAndExtract(word, meanings);

        // 3. 如果适合，驱动生图模型
        if (Boolean.TRUE.equals(wci.getIsApplicable())) {
            generateImage(wci);
        }

        return wci;
    }

    private WordCoreImage evaluateAndExtract(Word word, List<MeaningItem> meanings) {
        StringBuilder meaningText = new StringBuilder();
        for (MeaningItem m : meanings) {
            meaningText.append("- [")
                    .append(m.getCiXing() != null ? m.getCiXing() : "")
                    .append("] ")
                    .append(m.getMeaning())
                    .append("\n");
        }

        String systemPrompt = "你是一位精通认知语言学与词源学的专家，擅长为背单词用户提取「一词多义的核心意象/动力学图式（Core Schema）」并串联看似无关的多个释义。\n"
                + "【核心任务】\n"
                + "判断给定的英语单词是否适合提取「一词多义核心意象」，若适合则构建结构化拓扑网络与现代极简动势生图提示词。\n\n"
                + "【判定标准】\n"
                + "1. 适合 (is_applicable=true)：该单词有 2 个以上看似不同但内在同源或具备明显物理/空间引申逻辑的多重释义（例如 spring: 春天/泉水/弹簧/跳跃；charge: 充电/收费/指控/冲锋；bank: 银行/河岸/倾斜转弯）。\n"
                + "2. 不适合 (is_applicable=false)：单一具体实物名词、专有名词、无引申空间的生僻词（例如 apple, chlorine, monday, desk）。\n\n"
                + "【输出约束】\n"
                + "必须返回纯 JSON 格式对象（以 { 开头，以 } 结尾），严禁输出 markdown 代码块标记（如 ```json），严禁输出任何前后闲聊或解释文本。\n"
                + "JSON 字段规范：\n"
                + "{\n"
                + "  \"is_applicable\": true 或 false,\n"
                + "  \"not_applicable_reason\": \"若不适合时的简明原因，适合时留空\",\n"
                + "  \"core_image\": \"4-10字核心意象短语（必须脱离单词的具体释义，表达单词最初的/最核心的词源内涵和概念）\",\n"
                + "  \"schema_desc\": \"50-100字认知语言学图式深度剖析\",\n"
                + "  \"branches\": [\n"
                + "    {\n"
                + "      \"pos\": \"词性，如 n. 或 v.\",\n"
                + "      \"meaning\": \"释义名称\",\n"
                + "      \"relation\": \"该释义如何脱胎于核心动势的极简纽带标签（8-14字）\",\n"
                + "      \"desc\": \"详细引申逻辑说明\",\n"
                + "      \"example\": \"英文典型例句\"\n"
                + "    }\n"
                + "  ],\n"
                + "  \"image_prompt\": \"英文提示词。必须基于以下准则：A clean, minimalist modern visual abstraction capturing the core dynamic essence of [core_image]. Matte dark void background with generous negative space. Base/Anchor: [compressed/stored potential energy in warm amber-gold]. Burst/Trajectory: [explosive release in vibrant emerald-green and turquoise luminescence]. Minimalist modern conceptual art, elegant few strokes, subtle glowing energy, crisp vectors. CRITICAL: Absolutely NO realistic objects, NO [word meanings like springs/water/trees], NO characters, NO faces. Only pure abstract kinetic forces, tension and momentum.\"\n"
                + "}";

        String userPrompt = "待分析单词：" + word.getSpell() + "\n释义列表：\n" + meaningText.toString();

        WordCoreImage wci = new WordCoreImage();
        wci.setId(Util.uuid());
        wci.setWordId(word.getId());
        wci.setWord(word.getSpell());
        wci.setCreateTime(new Date());
        wci.setUpdateTime(new Date());

        try {
            String aiResult = aiBo.generateText(systemPrompt, userPrompt);
            if (aiResult != null) {
                String cleanedJson = JsonUtils.repairAiJson(aiResult);
                Map<String, Object> map = JsonUtils.parseAiMap(cleanedJson);
                Boolean isApplicable = (Boolean) map.get("is_applicable");
                wci.setIsApplicable(Boolean.TRUE.equals(isApplicable));

                if (!wci.getIsApplicable()) {
                    wci.setNotApplicableReason((String) map.get("not_applicable_reason"));
                    wci.setImageStatus("SKIPPED");
                } else {
                    wci.setCoreImage((String) map.get("core_image"));
                    wci.setSchemaDesc((String) map.get("schema_desc"));
                    wci.setImagePrompt((String) map.get("image_prompt"));
                    wci.setTopologyJson(cleanedJson);
                    wci.setImageStatus("PENDING");
                }
            } else {
                wci.setIsApplicable(false);
                wci.setNotApplicableReason("AI 文本生成未返回内容");
                wci.setImageStatus("FAILED");
            }
        } catch (Exception e) {
            log.error("AI 评估提取单词核心意象失败: " + word.getSpell(), e);
            wci.setIsApplicable(false);
            wci.setNotApplicableReason("解析异常: " + e.getMessage());
            wci.setImageStatus("FAILED");
        }

        createEntity(wci);
        return wci;
    }

    /**
     * 调用图像生成大模型驱动生图
     */
    public void generateImage(WordCoreImage item) {
        if (item == null || !Boolean.TRUE.equals(item.getIsApplicable())) {
            return;
        }

        String prompt = item.getImagePrompt();
        if (prompt == null || prompt.trim().isEmpty()) {
            prompt = "A clean, minimalist modern visual abstraction capturing the core dynamic essence of "
                    + item.getCoreImage()
                    + ". Matte dark void background with generous negative space. Base: compressed stored potential energy in warm amber-gold. Burst: explosive release in vibrant emerald-green and turquoise. Minimalist modern conceptual art, elegant few strokes, subtle glowing energy. Absolutely NO realistic objects, NO characters, NO text.";
        }

        String volcKey = System.getenv("VOLC_API_KEY");
        String siliconKey = System.getenv("SILICONFLOW_API_KEY");

        String imageUrl = null;
        String modelName = null;

        // 1. 首选火山引擎豆包 Seedream 4.0
        if (volcKey != null && !volcKey.isEmpty()) {
            try {
                log.info("正在使用火山引擎豆包 Seedream 4.0 生成单词意象图: {}", item.getWord());
                imageUrl = callVolcImageApi(prompt, volcKey);
                modelName = "doubao-seedream-4-0-250828";
            } catch (Exception e) {
                log.warn("火山引擎生图失败，尝试降级: ", e);
            }
        }

        // 2. 次选硅基流动 Kolors
        if (imageUrl == null && siliconKey != null && !siliconKey.isEmpty()) {
            try {
                log.info("正在使用硅基流动 Kolors 生成单词意象图: {}", item.getWord());
                imageUrl = callSiliconflowImageApi(prompt, siliconKey);
                modelName = "Kwai-Kolors/Kolors";
            } catch (Exception e) {
                log.warn("硅基流动生图失败: ", e);
            }
        }

        if (imageUrl != null) {
            // 下载图片落盘
            try {
                String savedRelativePath = downloadAndSaveImage(imageUrl, item.getWord());
                item.setImageUrl(savedRelativePath);
                item.setImageStatus("SUCCESS");
                item.setImageModel(modelName);
                item.setUpdateTime(new Date());
                saveOrUpdate(item);
                log.info("单词 {} 意象图生成并存储成功: {}", item.getWord(), savedRelativePath);
            } catch (Exception e) {
                log.error("保存单词意象图本地文件失败: " + item.getWord(), e);
                item.setImageUrl(imageUrl); // 降级为远程 URL
                item.setImageStatus("SUCCESS");
                item.setImageModel(modelName);
                item.setUpdateTime(new Date());
                saveOrUpdate(item);
            }
        } else {
            item.setImageStatus("FAILED");
            item.setUpdateTime(new Date());
            saveOrUpdate(item);
            log.error("单词 {} 意象图生成全部降级失败", item.getWord());
        }
    }

    private void saveOrUpdate(WordCoreImage item) {
        try {
            updateEntity(item);
        } catch (Exception e) {
            throw new RuntimeException("更新 WordCoreImage 异常: " + item.getWord(), e);
        }
    }

    private String callVolcImageApi(String prompt, String apiKey) throws Exception {
        String url = "https://ark.cn-beijing.volces.com/api/v3/images/generations";
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + apiKey);
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, Object> body = new HashMap<>();
        body.put("model", "doubao-seedream-4-0-250828");
        body.put("prompt", prompt);
        body.put("size", "1024x1024");
        body.put("response_format", "url");

        HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(body, headers);
        ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                url, HttpMethod.POST, requestEntity,
                new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});

        Map<String, Object> respBody = response.getBody();
        if (respBody != null && respBody.containsKey("data")) {
            List<?> dataList = (List<?>) respBody.get("data");
            if (dataList != null && !dataList.isEmpty()) {
                Map<?, ?> first = (Map<?, ?>) dataList.get(0);
                return (String) first.get("url");
            }
        }
        throw new RuntimeException("火山引擎未返回有效的图片 URL: " + respBody);
    }

    private String callSiliconflowImageApi(String prompt, String apiKey) throws Exception {
        String url = "https://api.siliconflow.cn/v1/images/generations";
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + apiKey);
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, Object> body = new HashMap<>();
        body.put("model", "Kwai-Kolors/Kolors");
        body.put("prompt", prompt);
        body.put("image_size", "1024x1024");

        HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(body, headers);
        ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                url, HttpMethod.POST, requestEntity,
                new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});

        Map<String, Object> respBody = response.getBody();
        if (respBody != null && respBody.containsKey("images")) {
            List<?> images = (List<?>) respBody.get("images");
            if (images != null && !images.isEmpty()) {
                Map<?, ?> first = (Map<?, ?>) images.get(0);
                return (String) first.get("url");
            }
        }
        throw new RuntimeException("硅基流动未返回有效的图片 URL: " + respBody);
    }

    private String downloadAndSaveImage(String remoteUrl, String word) throws Exception {
        String baseDir = null;
        try {
            baseDir = sysParamUtil.getImageBaseDir();
        } catch (Exception ignored) {
        }
        if (baseDir == null || baseDir.trim().isEmpty()) {
            baseDir = "/Volumes/ssd/ppdc/design/ui/assets";
        }

        File targetFolder = new File(baseDir, "core_images");
        if (!targetFolder.exists()) {
            targetFolder.mkdirs();
        }

        String fileName = "core_" + word.toLowerCase() + ".jpeg";
        File targetFile = new File(targetFolder, fileName);

        URL u = new URL(remoteUrl);
        HttpURLConnection conn = (HttpURLConnection) u.openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent", "Mozilla/5.0");

        try (InputStream in = conn.getInputStream(); FileOutputStream out = new FileOutputStream(targetFile)) {
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) != -1) {
                out.write(buf, 0, len);
            }
        }

        return "assets/core_images/" + fileName;
    }
}
