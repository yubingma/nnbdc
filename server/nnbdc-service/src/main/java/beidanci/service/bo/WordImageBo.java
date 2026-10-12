package beidanci.service.bo;

import java.io.File;
import java.net.URI;
import java.net.URISyntaxException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;

import javax.annotation.PostConstruct;

import org.apache.commons.lang3.tuple.Pair;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.EventType;
import beidanci.service.config.AliyunCdnProperties;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Event;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
import beidanci.service.util.CdnUtil;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.SysParamUtil;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordImageBo extends BaseBo<WordImage> {
    private static final Logger log = LoggerFactory.getLogger(WordImageBo.class);
    private static final int MAX_IMAGES_PER_WORD = 2;

    public static final String STATUS_PENDING = "PENDING";
    public static final String STATUS_APPROVED = "APPROVED";
    public static final String STATUS_REJECTED = "REJECTED";

    @Autowired
    WordBo wordBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    EventBo eventBo;

    @Autowired
    UserBo userBo;

    @Autowired
    SysDbSyncBo sysDbLogBo;

    @Autowired
    CdnUtil cdnUtil;

    @Autowired
    AliyunCdnProperties cdnProperties;

    @Autowired
    AiBo aiBo;

    @Autowired
    @org.springframework.context.annotation.Lazy
    private WordImageBo self; // Self-injection for @Async proxying

    @PostConstruct
    public void init() {
        setDao(new BaseDao<WordImage>() {
        });
    }

    public Result<Integer> handImage(String imageId, User user)
            throws IllegalArgumentException, IllegalAccessException {
        WordImage image = findById(imageId);
        image.setHand(image.getHand() + 1);
        updateEntity(image);

        // 记录系统数据日志（点赞数变化）
        sysDbLogBo.logOperation(image, "UPDATE", "word_image", imageId, toJsonForLog(image));

        // 对作者进行奖励
        userBo.adjustCowDung(image.getAuthor(), 1, "单词配图UGC得到了赞");

        Event event = new Event(EventType.HandWordImage, user, image);
        eventBo.createEntity(event);

        return new Result<>(true, null, image.getHand());
    }

    public Result<Integer> footImage(String imageId, User user)
            throws IllegalArgumentException, IllegalAccessException {
        WordImage image = findById(imageId);
        image.setFoot(image.getFoot() + 1);
        updateEntity(image);

        // 记录系统数据日志（踩数变化）
        sysDbLogBo.logOperation(image, "UPDATE", "word_image", imageId, toJsonForLog(image));

        if (image.getFoot() - image.getHand() >= 3) {// 如果该图片被踩的次数比被赞的次数多3（或以上），删除该图片
            deleteWordImage(imageId, user, false);
        } else {
            Event event = new Event(EventType.FootWordImage, user, image);
            eventBo.createEntity(event);
        }

        return new Result<>(true, null, image.getFoot());
    }

    /**
     * 注意：BaseDao.pagedQuery(preciseEntity) 会跳过关联对象字段（Po类型字段），
     * 例如 WordImage.word（对应 wordId）不会进入 WHERE 条件。
     * 因此这里必须用显式 SQL 按 wordId 查询，避免误查全表导致“末位淘汰”误删。
     */
    private List<WordImage> listImagesByWordId(String wordId) {
        return pagedQuery("SELECT * FROM word_image WHERE word_id = :wordId",
                1,
                Integer.MAX_VALUE,
                Pair.of("wordId", wordId)).getRows();
    }



    public Result<WordImage> addWordImage(WordImage wordImage, User user) throws IllegalArgumentException, IllegalAccessException {
        // 如果单词的配图已经达到上限，则不再允许添加配图
        Word word = wordImage.getWord();
        if (word == null) {
            throw new IllegalArgumentException("wordImage.word 不能为空");
        }
        if (word.getId() == null) {
            throw new IllegalArgumentException("wordImage.word.id 不能为空");
        }

        // 检查配图数量限制：如果已经有两张图片了，就不允许再添加配图了
        List<WordImage> images = listImagesByWordId(word.getId());
        if (images.size() >= MAX_IMAGES_PER_WORD) {
            return Result.fail("每个单词最多只能有 " + MAX_IMAGES_PER_WORD + " 张配图");
        }

        // 设置初始状态
        if (!user.getIsAdmin() && !user.getIsSuperAdmin()) {
            wordImage.setStatus(STATUS_PENDING);
        } else {
            wordImage.setStatus(STATUS_APPROVED); // 管理员上传直接通过
        }

        wordImage.setOwner(user);
        
        // 入库
        createEntity(wordImage);

        // 记录系统数据日志（初始状态）
        sysDbLogBo.logOperation(wordImage, "INSERT", "word_image", wordImage.getId(),
                toJsonForLog(wordImage));

        // 联动刷新词书版本，确保资源清单同步
        dictBo.updateDictsUpdateTimeByWord(word.getId());

        Event event = new Event(EventType.NewWordImage, user, wordImage);
        eventBo.createEntity(event);

        // 如果是普通用户上传，启动异步审核
        if (STATUS_PENDING.equals(wordImage.getStatus())) {
            self.asyncReviewImage(wordImage.getId(), word.getSpell(), wordImage.getImageFile());
        }

        return Result.success(wordImage);
    }

    /**
     * 异步审核图片逻辑（上传后立即触发）
     */
    @org.springframework.scheduling.annotation.Async
    public void asyncReviewImage(String wordImageId, String spell, String imageFile) throws IllegalAccessException {
        reviewImageAndApply(wordImageId, spell, imageFile);
    }

    /**
     * 送 AI 审一张配图并按结论处理：
     * <ul>
     * <li>判删（action=DELETE）→ 走 {@link #deleteWordImage} 删除；</li>
     * <li>判过（action=KEEP）→ 置为 APPROVED 并下发同步日志，客户端这时才看得到这张图；</li>
     * <li>没结论（AI 调用失败/返回解析不出来）→ 保持 PENDING，交给 {@link #reviewStuckPendingImages} 稍后重试。</li>
     * </ul>
     *
     * 以前审核失败会直接置为 APPROVED，等于"审都没审就发给用户看"；现在宁可让它停在审核中，
     * 也不能把没审过的图放出去。
     *
     * @return AI 的原始结论（含 action / reason）；没结论时返回 null
     */
    public Map<String, Object> reviewImageAndApply(String wordImageId, String spell, String imageFile)
            throws IllegalAccessException {
        return reviewImageAndApply(wordImageId, spell, imageFile, false);
    }

    /**
     * @param deferCdnRefresh 判删时是否把 CDN 缓存刷新推迟给调用方去做。批量审核传 true：一轮会删几千张，
     *                        逐张刷 URL 会被阿里云每天 2000 条的 URL 刷新配额卡死，改由任务收尾统一刷一次
     *                        目录（见 {@link #refreshWordImageCdnDirectory}）。
     */
    public Map<String, Object> reviewImageAndApply(String wordImageId, String spell, String imageFile,
            boolean deferCdnRefresh) throws IllegalAccessException {
        if (spell == null || spell.trim().isEmpty()) {
            // 没有单词就无从判断这张图合不合适，宁可留在审核中，也不能拿"null"去让 AI 猜
            log.error("配图对应的单词查不到，跳过审核: imageId={}", wordImageId);
            return null;
        }
        log.info("📢 开始审核图片: imageId={}, word={}", wordImageId, spell);
        WordImage image = findById(wordImageId);
        if (image == null) {
            return null;
        }
        Map<String, Object> verdict;
        try {
            String absolutePath = sysParamUtil.getImageBaseDir() + "/word/" + imageFile;
            String aiResultJson = aiBo.reviewImage(spell, absolutePath);
            if (aiResultJson == null) {
                log.error("❌ 审图没拿到结论（AI 调用失败），保持审核中等待重试: imageId={}, word={}", wordImageId, spell);
                return null;
            }
            verdict = JsonUtils.parseAiMap(aiResultJson);
        } catch (Exception e) {
            log.error("❌ 审图过程异常，保持审核中等待重试: imageId=" + wordImageId, e);
            return null;
        }

        String action = verdict.get("action") == null ? null : String.valueOf(verdict.get("action"));
        if ("DELETE".equals(action)) {
            log.info("🚫 图片审核不通过，执行删除: imageId={}, word={}, 原因={}", wordImageId, spell, verdict.get("reason"));
            Result<Object> deleteResult = deleteWordImage(wordImageId, null, false, deferCdnRefresh);
            if (!deleteResult.isSuccess()) {
                log.error("图片审核不通过但删除失败: imageId={}, msg={}", wordImageId, deleteResult.getMsg());
            }
            return verdict;
        }
        if ("KEEP".equals(action)) {
            log.info("✅ 图片审核通过: imageId={}, word={}", wordImageId, spell);
            image.setStatus(STATUS_APPROVED);
            updateEntity(image);
            // 通过之后才下发，客户端这时才拿到这张图（未通过的图不下发，见 SysDbSyncBo.logOperation 的闸门）
            sysDbLogBo.logOperation(image, "UPDATE", "word_image", wordImageId, toJsonForLog(image));
            return verdict;
        }

        log.error("❌ 审图返回无法识别的结论，保持审核中等待重试: imageId={}, word={}, 返回={}", wordImageId, spell, verdict);
        return null;
    }

    /**
     * 重新送审卡在「审核中」的配图。
     *
     * 上传时的异步审核可能因服务重启、进程被杀而半途而废，那张图就会永远停在 PENDING
     * （实测有卡了两周多的图），既不通过也不删除。这里按"审核中且超过指定时长"把它们捞出来重审。
     *
     * @param olderThanMinutes 只重审创建时间早于「现在 - 该分钟数」的图，避免打断正在进行的审核
     * @return 本次实际送审的条数
     */
    public int reviewStuckPendingImages(int olderThanMinutes, int limit) throws IllegalAccessException {
        Date cutoff = new Date(System.currentTimeMillis() - olderThanMinutes * 60_000L);
        String sql = "SELECT wi.id, wi.image_file, w.spell FROM word_image wi JOIN word w ON w.id = wi.word_id "
                + "WHERE wi.status = ? AND wi.create_time < ? ORDER BY wi.create_time LIMIT ?";
        List<Object[]> rows = getJdbcTemplate().query(sql,
                (rs, rowNum) -> new Object[] { rs.getString("id"), rs.getString("image_file"), rs.getString("spell") },
                STATUS_PENDING, cutoff, limit);
        for (Object[] row : rows) {
            reviewImageAndApply((String) row[0], (String) row[2], (String) row[1]);
        }
        if (!rows.isEmpty()) {
            log.info("🔁 自动重审卡在审核中的配图: {} 条", rows.size());
        }
        return rows.size();
    }

    public Result<Object> deleteWordImage(String imageId, User user, boolean checkPermission) {
        return deleteWordImage(imageId, user, checkPermission, false);
    }

    /**
     * @param deferCdnRefresh 是否把 CDN 缓存刷新推迟给调用方，见
     *                        {@link #reviewImageAndApply(String, String, String, boolean)}
     */
    public Result<Object> deleteWordImage(String imageId, User user, boolean checkPermission,
            boolean deferCdnRefresh) {
        WordImage image = findById(imageId);
        if (image == null) {
            return new Result<>(true, null, null);
        }
        if (checkPermission) {
            if (!user.getIsAdmin() && !user.getIsSuperAdmin() && (image.getAuthor() == null
                    || !image.getAuthor().getUserName().equalsIgnoreCase(user.getUserName()))) {
                return new Result<>(false, "无权限", null);
            }
        }

        // 删除相关的事件记录
        // 直接按 wordImageId 批量删除，减少查询与逐行删除带来的锁竞争。
        // 注意：如果数据库存在外键约束（event.wordImageId -> word_image.id），则必须先删 event 才能删图片。
        boolean eventsDeleted = eventBo.deleteEventsByWordImageId(image.getId());
        if (!eventsDeleted) {
            return new Result<>(false, "系统繁忙，请稍后再试", null);
        }

        String wordId = image.getWord().getId();

        // 删除数据库记录
        // JDBC 模式下不维护 Word.images 这种内存关系，直接删记录即可
        image.setWord(null);
        deleteEntity(image);

        // 记录系统数据日志（删除配图）
        sysDbLogBo.logOperation(image, "DELETE", "word_image", imageId, "{}");

        // 联动刷新词书版本
        dictBo.updateDictsUpdateTimeByWord(wordId);

        // 删除物理文件并刷新 CDN
        deleteImageFile(image.getImageFile(), deferCdnRefresh);

        return new Result<>(true, null, null);
    }

    /**
     * 删掉一张配图的物理文件，并刷新它在 CDN 上的缓存。
     *
     * 客户端取图走 CDN（imgBaseUrl + word/文件名），只删源站磁盘文件时 CDN 上仍缓存着旧副本
     * （实测可留 29 天），用户手里只要还有这张图的记录就照样能显示，所以必须主动刷新。
     * 配图记录被删除、以及磁盘上有文件但数据库里已无对应记录（孤儿文件）时，都走这里。
     */
    public void deleteImageFile(String imageFileName) {
        deleteImageFile(imageFileName, false);
    }

    /**
     * @param deferCdnRefresh 是否把 CDN 缓存刷新推迟给调用方，见
     *                        {@link #reviewImageAndApply(String, String, String, boolean)}
     */
    public void deleteImageFile(String imageFileName, boolean deferCdnRefresh) {
        File imageFile = new File(sysParamUtil.getImageBaseDir() + "/word/" + imageFileName);
        if (!imageFile.delete()) {
            imageFile.deleteOnExit();
        }
        if (!deferCdnRefresh) {
            refreshImageCdn(imageFileName);
        }
    }

    /**
     * 刷一次整个配图目录（`img/word/`）的 CDN 缓存。
     *
     * 批量审核一轮会删掉几千张配图，逐张刷 URL 会被阿里云每天 2000 条的 URL 刷新配额卡死
     * （实测 2026-10-12：21:12 打满 2000 条后全线报 QuotaExceeded.Refresh，之后删掉的 1100 多张
     * 图的旧副本一直留在 CDN 上）。目录刷新是另一份独立的配额（100 条/天），一次就能把这些残留全清掉，
     * 代价是整个配图目录的缓存失效、下次访问集中回源一次。
     */
    public void refreshWordImageCdnDirectory() {
        try {
            URI base = new URI(cdnProperties.getImageBaseUrl());
            String dirUrl = new URI(base.getScheme(), base.getAuthority(), base.getPath() + "word/", null)
                    .toASCIIString();
            String result = cdnUtil.refreshDirectory(dirUrl);
            if (!"OK".equals(result)) {
                log.error("配图目录 CDN 缓存刷新失败: url={}, result={}", dirUrl, result);
            } else {
                log.info("配图目录 CDN 缓存刷新已提交: {}", dirUrl);
            }
        } catch (URISyntaxException e) {
            log.error("配图目录 CDN 地址配置非法: base={}", cdnProperties.getImageBaseUrl(), e);
        }
    }

    /**
     * 刷新一张配图在 CDN 上的缓存。
     *
     * 刷新失败不回滚删除动作（图片记录与物理文件已删），但必须留下错误日志暴露出来。
     */
    private void refreshImageCdn(String imageFileName) {
        String url;
        try {
            URI base = new URI(cdnProperties.getImageBaseUrl());
            // 文件名可能含空格、感叹号、逗号等（实测 4748 个文件名带空格），
            // 必须按 URI 规则转义，才能和客户端 Uri.encodeFull 请求的地址一致
            url = new URI(base.getScheme(), base.getAuthority(), base.getPath() + "word/" + imageFileName, null)
                    .toASCIIString();
        } catch (URISyntaxException e) {
            log.error("配图 CDN 地址配置非法，无法刷新缓存: base={}, imageFile={}", cdnProperties.getImageBaseUrl(),
                    imageFileName, e);
            return;
        }
        String result = cdnUtil.refreshUrl(url);
        if (!"OK".equals(result)) {
            log.error("配图 CDN 缓存刷新失败: url={}, result={}", url, result);
        }
    }
    
    public void deleteAllImagesOfWord(String wordId, User user) {
        List<WordImage> images = listImagesByWordId(wordId);
        for (WordImage img : images) {
            deleteWordImage(img.getId(), user, false);
        }
    }

    /**
     * 将WordImage转为JSON字符串用于日志
     */
    private String toJsonForLog(WordImage image) {
        try {
            // 用于格式化日期为ISO-8601格式
            SimpleDateFormat isoFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
            isoFormat.setTimeZone(TimeZone.getTimeZone("UTC"));

            String createTimeStr = image.getCreateTime() != null ? isoFormat.format(image.getCreateTime()) : "";
            String updateTimeStr = image.getUpdateTime() != null ? isoFormat.format(image.getUpdateTime()) : "";

            return String.format(
                    "{\"id\":\"%s\",\"wordId\":\"%s\",\"imageFile\":\"%s\",\"hand\":%d,\"foot\":%d,\"authorId\":\"%s\",\"ownerId\":\"%s\",\"status\":\"%s\",\"auditReason\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                    image.getId(),
                    image.getWord() != null ? image.getWord().getId() : "",
                    image.getImageFile(),
                    image.getHand(),
                    image.getFoot(),
                    image.getAuthor() != null ? image.getAuthor().getId() : "",
                    image.getOwnerId(),
                    image.getStatus() != null ? image.getStatus() : "",
                    image.getAuditReason() != null ? image.getAuditReason() : "",
                    createTimeStr,
                    updateTimeStr);
        } catch (Exception e) {
            return "{}";
        }
    }
}
