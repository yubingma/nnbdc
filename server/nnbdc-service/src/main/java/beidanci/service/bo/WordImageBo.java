package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.List;
import java.util.TimeZone;

import org.apache.commons.lang3.tuple.Pair;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.EventType;
import beidanci.api.model.UserVo;
import beidanci.api.model.WordImageVo;
import beidanci.service.SessionData;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Event;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordImage;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.SysParamUtil;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordImageBo extends BaseBo<WordImage> {
    private static final Logger log = LoggerFactory.getLogger(WordImageBo.class);
    private static final int MAX_IMAGES_PER_WORD = 9;
    private static final int MAX_IMAGES_FOR_DISPLAY = 9;

    @Autowired
    WordBo wordBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    EventBo eventBo;

    @Autowired
    UserBo userBo;

    @Autowired
    SysDbSyncBo sysDbLogBo;

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
        sysDbLogBo.logOperation("UPDATE", "word_image", imageId,
                toJsonForLog(image));

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
        sysDbLogBo.logOperation("UPDATE", "word_image", imageId,
                toJsonForLog(image));

        if (image.getFoot() - image.getHand() >= 3) {// 如果该图片被踩的次数比被赞的次数多3（或以上），删除该图片
            deleteWordImage(imageId, user, false);
        } else {
            Event event = new Event(EventType.FootWordImage, user, image);
            eventBo.createEntity(event);
        }

        return new Result<>(true, null, image.getFoot());
    }

    private static void sortWordImages(List<WordImage> wordImages) {
        wordImages.sort((WordImage o1, WordImage o2) -> {
            int score1 = o1.getHand() - o1.getFoot();
            int score2 = o2.getHand() - o2.getFoot();
            if (score1 == score2) {
                return (int) (o2.getCreateTime().getTime() - o1.getCreateTime().getTime());
            } else {
                return score2 - score1;
            }
        });
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

    /**
     * 获取一个单词对应的前10个图片
     */
    public WordImageVo[] getImagesOfWord(String wordId, SessionData sessionData) {

        Word word = wordBo.findById(wordId);
        if (word == null) {
            return new WordImageVo[0];
        }
        List<WordImage> wordImages = listImagesByWordId(wordId);
        // 补齐关联对象的 spell（JDBC 映射只会填充 wordId -> Word{id}）
        for (WordImage img : wordImages) {
            if (img.getWord() != null && img.getWord().getId() != null) {
                img.getWord().setSpell(word.getSpell());
            }
        }
        sortWordImages(wordImages);

        int total = wordImages.size();
        WordImageVo[] images = new WordImageVo[Math.min(total, MAX_IMAGES_FOR_DISPLAY)];
        for (int i = 0; i < images.length; i++) {
            WordImage po = wordImages.get(i);
            WordImageVo vo = BeanUtils.makeVo(po, WordImageVo.class,
                    new String[] { "author", "createTime", "updateTime", "word.^id,spell" });
            UserVo author = new UserVo();
            author.setDisplayNickName(po.getAuthor().getDisplayNickName());
            author.setUserName(po.getAuthor().getUserName());
            author.setId(po.getAuthor().getId());
            vo.setAuthor(author);

            images[i] = vo;
        }

        return images;
    }

    public void addWordImage(WordImage wordImage, User user) throws IllegalArgumentException, IllegalAccessException {
        // 如果单词的配图已经大于等于上限，则把最后一个图片删掉（末位淘汰制）
        Word word = wordImage.getWord();
        if (word == null) {
            throw new IllegalArgumentException("wordImage.word 不能为空");
        }
        if (word.getId() == null) {
            throw new IllegalArgumentException("wordImage.word.id 不能为空");
        }

        // 必须按 wordId 精确查询，避免误查全表导致误删
        List<WordImage> images = listImagesByWordId(word.getId());
        sortWordImages(images);

        while (images.size() >= MAX_IMAGES_PER_WORD) {
            // 删除数据库记录
            WordImage lastImage = images.remove(images.size() - 1);
            Result<Object> del = deleteWordImage(lastImage.getId(), user, false);
            if (del == null || !del.isSuccess()) {
                // 说明：如果 event 表存在外键约束（event.wordImageId -> word_image.id），
                // event 清理失败会导致图片无法删除。此时不再强行淘汰，避免上传失败。
                log.warn("末位淘汰删除失败，临时放宽配图数量限制。wordId={}, imageId={}, msg={}",
                        word.getId(), lastImage.getId(), del != null ? del.getMsg() : "null");
                break;
            }
        }

        // 添加新的单词图片
        createEntity(wordImage);

        // 记录系统数据日志（新增配图）
        sysDbLogBo.logOperation("INSERT", "word_image", wordImage.getId(),
                toJsonForLog(wordImage));

        Event event = new Event(EventType.NewWordImage, user, wordImage);
        eventBo.createEntity(event);
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

        // 删除数据库记录
        // JDBC 模式下不维护 Word.images 这种内存关系，直接删记录即可
        image.setWord(null);
        deleteEntity(image);

        // 记录系统数据日志（删除配图）
        sysDbLogBo.logOperation("DELETE", "word_image", imageId, "{}");

        // 删除图片文件
        File imageFile = new File(sysParamUtil.getImageBaseDir() + "/word/" + image.getImageFile());
        if (!imageFile.delete()) {
            imageFile.deleteOnExit();
        }

        return new Result<>(true, null, null);
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
                    "{\"id\":\"%s\",\"wordId\":\"%s\",\"imageFile\":\"%s\",\"hand\":%d,\"foot\":%d,\"authorId\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                    image.getId(),
                    image.getWord() != null ? image.getWord().getId() : "",
                    image.getImageFile(),
                    image.getHand(),
                    image.getFoot(),
                    image.getAuthor() != null ? image.getAuthor().getId() : "",
                    createTimeStr,
                    updateTimeStr);
        } catch (Exception e) {
            return "{}";
        }
    }
}
