package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.io.File;
import java.util.List;

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
    @Autowired
    WordBo wordBo;

    @Autowired
    SysParamUtil sysParamUtil;

    @Autowired
    EventBo eventBo;

    @Autowired
    UserBo userBo;

    @Autowired
    SysDbLogBo sysDbLogBo;

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
     * 获取一个单词对应的前10个图片
     */
    public WordImageVo[] getImagesOfWord(String wordId, SessionData sessionData) {

        // 对图片进行排序，被点赞绝对次数多的排在前面
        Word word = wordBo.findById(wordId);
        List<WordImage> wordImages = word.getImages();
        sortWordImages(wordImages);

        int total = wordImages.size();
        WordImageVo[] images = new WordImageVo[Math.min(total, 10)];
        for (int i = 0; i < images.length; i++) {
            WordImage po = wordImages.get(i);
            WordImageVo vo = BeanUtils.makeVo(po, WordImageVo.class, new String[]{"author", "createTime", "updateTime", "word.^id,spell"});
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
        // 如果单词的配图已经大于等于12个了，则把最后一个图片删掉（末位淘汰制）
        Word word = wordImage.getWord();
        List<WordImage> images = word.getImages();
        sortWordImages(images);
        while (images.size() >= 12) {
            // 删除数据库记录
            WordImage lastImage = images.remove(images.size() - 1);
            deleteWordImage(lastImage.getId(), user, false);
        }

        // 添加新的单词图片
        createEntity(wordImage);
        images.add(wordImage);

        // 记录系统数据日志（新增配图）
        sysDbLogBo.logOperation("INSERT", "word_image", wordImage.getId(), 
            toJsonForLog(wordImage));

        Event event = new Event(EventType.NewWordImage, user, wordImage);
        eventBo.createEntity(event);
    }

    public Result<Object> deleteWordImage(String imageId, User user, boolean checkPermission) {
        WordImage image = findById(imageId);
        if (checkPermission) {
            if (!user.getIsAdmin() && !user.getIsSuper() && (image.getAuthor() == null
                    || !image.getAuthor().getUserName().equalsIgnoreCase(user.getUserName()))) {
                return new Result<>(false, "无权限", null);
            }
        }

        // 删除相关的事件记录
        Event exam = new Event();
        exam.setWordImage(image);
        List<Event> events = eventBo.queryAll(exam, false);
        for (Event event : events) {
            eventBo.deleteEntity(event);
        }

        // 删除数据库记录
        image.getWord().getImages().remove(image);
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
            return String.format(
                "{\"id\":\"%s\",\"wordId\":\"%s\",\"imageFile\":\"%s\",\"hand\":%d,\"foot\":%d,\"author\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                image.getId(),
                image.getWord() != null ? image.getWord().getId() : "",
                image.getImageFile(),
                image.getHand(),
                image.getFoot(),
                image.getAuthor() != null ? image.getAuthor().getId() : "",
                image.getCreateTime() != null ? image.getCreateTime().toString() : "",
                image.getUpdateTime() != null ? image.getUpdateTime().toString() : ""
            );
        } catch (Exception e) {
            return "{}";
        }
    }
}
