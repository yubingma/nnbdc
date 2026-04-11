package beidanci.service.bo;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.List;
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
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Event;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
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
     * 异步审核图片逻辑
     */
    @org.springframework.scheduling.annotation.Async
    public void asyncReviewImage(String wordImageId, String spell, String imageFile) {
        log.info("📢 开始异步审核图片: imageId={}, word={}", wordImageId, spell);
        try {
            WordImage image = findById(wordImageId);
            if (image == null) return;

            String absolutePath = sysParamUtil.getImageBaseDir() + "/word/" + imageFile;
            String aiResultJson = aiBo.reviewImage(spell, absolutePath);

            // 解析结果
            if (aiResultJson.contains("DELETE")) {
                log.info("🚫 图片审核失败，执行删除: imageId={}, word={}, result={}", wordImageId, spell, aiResultJson);
                // 删除文件
                File file = new File(absolutePath);
                if (file.exists()) {
                    file.delete();
                }

                // 从 DB 删除 (不抛出异常以防回滚)
                deleteEntity(image);

                // 书写删除日志给客户端同步
                sysDbLogBo.logOperation(image, "DELETE", "word_image", wordImageId, "{}");

                // 联动刷新词书版本
                dictBo.updateDictsUpdateTimeByWord(image.getWord().getId());
            } else {
                log.info("✅ 图片审核通过: imageId={}, word={}", wordImageId, spell);
                image.setStatus(STATUS_APPROVED);
                updateEntity(image);

                // 更新日志，提醒客户端该图片已变为 APPROVED（其实目前客户端只展示已通过的，所以这里的 update 也很关键）
                sysDbLogBo.logOperation(image, "UPDATE", "word_image", wordImageId, toJsonForLog(image));
            }
        } catch (Exception e) {
            log.error("❌ 异步审核图片过程发生异常: " + wordImageId, e);
            // 容错：如果审核过程挂了，保险起见暂时将其设为 APPROVED 或者继续保持 PENDING 等待下次补审
            // 考虑用户体验，这里设为 APPROVED
            try {
                WordImage image = findById(wordImageId);
                if (image != null) {
                    image.setStatus(STATUS_APPROVED);
                    updateEntity(image);
                    sysDbLogBo.logOperation(image, "UPDATE", "word_image", wordImageId, toJsonForLog(image));
                }
            } catch (Exception ignore) {}
        }
    }

    public Result<Object> deleteWordImage(String imageId, User user, boolean checkPermission) {
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

        // 删除图片文件
        File imageFile = new File(sysParamUtil.getImageBaseDir() + "/word/" + image.getImageFile());
        if (!imageFile.delete()) {
            imageFile.deleteOnExit();
        }

        return new Result<>(true, null, null);
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
                    "{\"id\":\"%s\",\"wordId\":\"%s\",\"imageFile\":\"%s\",\"hand\":%d,\"foot\":%d,\"authorId\":\"%s\",\"status\":\"%s\",\"auditReason\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                    image.getId(),
                    image.getWord() != null ? image.getWord().getId() : "",
                    image.getImageFile(),
                    image.getHand(),
                    image.getFoot(),
                    image.getAuthor() != null ? image.getAuthor().getId() : "",
                    image.getStatus() != null ? image.getStatus() : "",
                    image.getAuditReason() != null ? image.getAuditReason() : "",
                    createTimeStr,
                    updateTimeStr);
        } catch (Exception e) {
            return "{}";
        }
    }
}
