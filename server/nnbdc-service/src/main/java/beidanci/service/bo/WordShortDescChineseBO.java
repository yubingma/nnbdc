package beidanci.service.bo;

import java.io.IOException;
import java.util.List;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.EventType;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Event;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordShortDescChinese;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordShortDescChineseBO extends BaseBo<WordShortDescChinese> {
    @Autowired
    WordBo wordBo;

    @Autowired
    EventBo eventBo;

    @Autowired
    UserBo userBo;

    @Autowired
    SysDbLogBo sysDbLogBo;

    public WordShortDescChineseBO() {
        // 移除构造函数中的DAO初始化
    }

    @PostConstruct
    public void init() {
        setDao(new BaseDao<WordShortDescChinese>() {});
    }

    public Result<Object> deleteShortDescChinese(String chineseId, User user, boolean checkPermission) throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordShortDescChinese chinese = findById(chineseId);
        if (checkPermission) {
            if (!user.getIsAdmin() && (chinese.getAuthor() == null
                    || !chinese.getAuthor().getUserName().equalsIgnoreCase(user.getUserName()))) {
                return new Result<>(false, "无权限", null);
            }
        }

        // 删除相关的事件记录
        Event exam = new Event();
        exam.setWordShortDescChinese(chinese);
        List<Event> events = eventBo.queryAll(exam, false);
        for (Event event : events) {
            eventBo.deleteEntity(event);
        }

        // 删除数据库记录
        Word word = chinese.getWord();
        word.getWordShortDescChineses().remove(chinese);
        chinese.setWord(null);
        deleteEntity(chinese);

        // 记录系统数据日志（删除翻译）
        sysDbLogBo.logOperation("DELETE", "word_shortdesc_chinese", chineseId, "{}");

        return Result.success(null);
    }

    public Result<Integer> handShortDescChinese(String chineseId, User user)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordShortDescChinese chinese = findById(chineseId);
        chinese.setHand(chinese.getHand() + 1);
        updateEntity(chinese);

        // 记录系统数据日志（点赞数变化）
        sysDbLogBo.logOperation("UPDATE", "word_shortdesc_chinese", chineseId, toJsonForLog(chinese));

        // 对作者进行奖励
        userBo.adjustCowDung(chinese.getAuthor(), 1, "单词英文讲解UGC翻译得到了赞");

        Event event = new Event(EventType.HandWordShortDescChinese, user, chinese);
        eventBo.createEntity(event);

        return new Result<>(true, null, chinese.getHand());
    }

    public Result<Integer> footShortDescChinese(String chineseId, User user)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException, IOException {
        WordShortDescChinese chinese = findById(chineseId);
        chinese.setFoot(chinese.getFoot() + 1);
        updateEntity(chinese);

        // 记录系统数据日志（踩数变化）
        sysDbLogBo.logOperation("UPDATE", "word_shortdesc_chinese", chineseId, toJsonForLog(chinese));

        // 如果该翻译被踩的次数比被赞的次数多3（或以上），删除该翻译
        if (chinese.getFoot() - chinese.getHand() >= 3) {
            deleteShortDescChinese(chineseId, user, false);
        } else {
            Event event = new Event(EventType.FootWordShortDescChinese, user, chinese);
            eventBo.createEntity(event);
        }

        return new Result<>(true, null, chinese.getFoot());
    }

    public void saveShortDescChinese(Integer wordId, String chinese, User user)
            throws IllegalArgumentException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        // 如果句子的DIY翻译已经大于等于3个了，则把最后一个删掉（末位淘汰制）
        Word word = wordBo.findById(wordId);
        List<WordShortDescChinese> chineses = word.getWordShortDescChineses();
        Util.sortShortDescChineses(chineses);
        while (chineses.size() >= 3) {
            // 删除数据库记录
            WordShortDescChinese lastImage = chineses.remove(chineses.size() - 1);
            deleteShortDescChinese(lastImage.getId(), user, false);
        }

        // 添加新的UGC翻译
        WordShortDescChinese shortDescChinese = new WordShortDescChinese();
        shortDescChinese.setAuthor(user);
        shortDescChinese.setContent(chinese);
        shortDescChinese.setFoot(0);
        shortDescChinese.setHand(0);
        shortDescChinese.setWord(word);
        createEntity(shortDescChinese);

        chineses.add(shortDescChinese);
        wordBo.updateEntity(word);

        // 记录系统数据日志（新增翻译）
        sysDbLogBo.logOperation("INSERT", "word_shortdesc_chinese", shortDescChinese.getId(), toJsonForLog(shortDescChinese));

        Event event = new Event(EventType.NewWordShortDescChinese, user, shortDescChinese);
        eventBo.createEntity(event);

    }

    /**
     * 将WordShortDescChinese转为JSON字符串用于日志
     */
    private String toJsonForLog(WordShortDescChinese chinese) {
        try {
            return String.format(
                "{\"id\":\"%s\",\"wordId\":\"%s\",\"content\":\"%s\",\"hand\":%d,\"foot\":%d,\"author\":\"%s\",\"createTime\":\"%s\",\"updateTime\":\"%s\"}",
                chinese.getId(),
                chinese.getWord() != null ? chinese.getWord().getId() : "",
                chinese.getContent() != null ? chinese.getContent().replace("\"", "\\\"") : "",
                chinese.getHand(),
                chinese.getFoot(),
                chinese.getAuthor() != null ? chinese.getAuthor().getId() : "",
                chinese.getCreateTime() != null ? chinese.getCreateTime().toString() : "",
                chinese.getUpdateTime() != null ? chinese.getUpdateTime().toString() : ""
            );
        } catch (Exception e) {
            return "{}";
        }
    }
}
