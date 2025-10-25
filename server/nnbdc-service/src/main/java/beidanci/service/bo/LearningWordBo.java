package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.io.IOException;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

import javax.naming.NamingException;
import javax.servlet.http.HttpServletRequest;

import org.apache.commons.lang3.time.DateUtils;
import org.apache.commons.lang3.tuple.ImmutablePair;
import org.hibernate.query.Query;
import org.hibernate.type.StandardBasicTypes;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.SortType;
import beidanci.api.model.LearningWordDto;
import beidanci.api.model.PagedResults;
import beidanci.api.model.WordVo;
import beidanci.service.SessionData;
import beidanci.service.dao.BaseDao;
import beidanci.service.error.ErrorCode;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.NoEnoughWordException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.LearningWord;
import beidanci.service.po.LearningWordId;
import beidanci.service.po.User;
import beidanci.service.po.UserStudyRecord;
import beidanci.service.po.UserStudyRecordId;
import beidanci.service.store.WordCache;
import beidanci.service.util.Util;
import beidanci.util.Utils;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LearningWordBo extends BaseBo<LearningWord> {
    private static final Logger log = LoggerFactory.getLogger(LearningWordBo.class);

    @PostConstruct
    public void init() {
        setDao(new BaseDao<LearningWord>() {
        });
    }

    @Autowired
    UserBo userBo;

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    WordCache wordCache;

    private List<LearningWord> fetchNewWordsToLearn(User user, int todayDayNumber, int countToFetch) {
        if (countToFetch <= 0) {
            return new ArrayList<>(0);
        }

        String sql = "select wordId, min(seq) as minSeq, max(ld.isPrivileged) as is_privileged " +
                "from dict_word dw left join learning_dict ld on dw.dictId = ld.dictId   left join dict d on dw.dictId  = d.id "
                +
                "where ld.userId = :userId " +
                "and (ld.currentWordSeq is null or ld.currentWordSeq < d.wordCount) " +
                "and (dw.seq > ld.currentWordSeq or ld.currentWordSeq is null) " +
                "and (ld.fetchMastered = 1 or not exists (select 0 from mastered_word mw where mw.userId=:userId and mw.wordId=dw.wordId)) "
                +
                "and not exists (select 0 from learning_word lw where lw.userId=:userId and lw.wordId=dw.wordId) " +
                "group by wordId order by is_privileged desc, minSeq asc limit :limit ";
        Query<String> query = getSession().createNativeQuery(sql, String.class)
                .addScalar("wordId", StandardBasicTypes.STRING);
        query.setParameter("userId", user.getId());
        query.setParameter("limit", countToFetch);
        List<String> list = query.list();
        List<LearningWord> learningWords = new ArrayList<>(countToFetch);
        for (String wordId : list) {
            LearningWordId id = new LearningWordId(user.getId(), wordId);
            LearningWord learningWord = new LearningWord(id, user, new Timestamp(new Date().getTime()), todayDayNumber,
                    LearningWord.NEW_LEARNING_WORD_LIFE_VALUE);
            createEntity(learningWord);
            learningWords.add(learningWord);
        }
        return learningWords;
    }

    /**
     * 添加新单词到正在学习的单词列表（本日要学习的单词将从该列表选出）
     *
     * @return
     * @throws ClassNotFoundException
     * @throws NamingException
     * @throws EmptySpellException
     * @throws InvalidMeaningFormatException
     * @throws ParseException
     * @throws IOException
     * @throws SQLException
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    private List<LearningWord> addNewLearningWords(User user, final List<LearningWord> currentLearningWords,
            int todayDayNumber) throws IllegalArgumentException {
        // 计算目前所有的 learning words 的总生命值
        int currentLifeValue = 0;
        for (LearningWord word : currentLearningWords) {
            currentLifeValue += word.getLifeValue();
        }

        // 計算期望的总生命值
        final int expectedTotalLifeValue = user.getWordsPerDay() * 29 / 5;

        // 计算需要添加的新单词数量（以达到期望的总生命值）
        int newWordCount = (int) Math.ceil(expectedTotalLifeValue - currentLifeValue + 0.0)
                / LearningWord.NEW_LEARNING_WORD_LIFE_VALUE;
        int wordsPerDay = user.getWordsPerDay();
        newWordCount = newWordCount <= wordsPerDay ? newWordCount : wordsPerDay;

        // 从词书取新词(不一定能取到足够的词，尽量取)
        Date startTime = new Date();
        List<LearningWord> newLearningWords = fetchNewWordsToLearn(user, todayDayNumber, newWordCount);

        // 更新词书的当前位置
        learningDictBo.updateCurrentPositionForUserDicts(user, false);

        Date endTime = new Date();
        log.info("从单词书取新词，耗时：" + (endTime.getTime() - startTime.getTime()));

        return newLearningWords;
    }

    /**
     * 获取指定的天数以前的那一天加入的learning words
     *
     * @param addDay
     * @return
     */
    private List<LearningWord> getLearningWordsAddedAtDay(int addDay, List<LearningWord> allLearningWords) {
        List<LearningWord> learningWords = new LinkedList<>();

        // 获取该天添加的所有单词
        for (LearningWord learningWord : allLearningWords) {
            if (learningWord.getAddDay() == addDay) {
                learningWords.add(learningWord);
            }
        }

        // 对该天的单词进行排序，生命值大的排在前面，以便被优先选为本日学习单词
        Collections.sort(learningWords, (LearningWord o1, LearningWord o2) -> o2.getLifeValue() - o1.getLifeValue());

        return learningWords;
    }

    /**
     * 将今日的学习单词更新到数据库
     *
     * @param todayLearningWords
     * @throws ClassNotFoundException
     * @throws NamingException
     * @throws SQLException
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    private void updateTodayLearningWords(List<LearningWord> todayLearningWords, Date now)
            throws IllegalArgumentException, IllegalAccessException {
        todayLearningWords.sort((o1, o2) -> o2.getLifeValue() - o1.getLifeValue());
        int learningOrder = 1;
        for (LearningWord learningWord : todayLearningWords) {
            if (!Util.isSameDay(now, learningWord.getLastLearningDate())) {
                learningWord.setLastLearningDate(now);
                learningWord.setIsTodayNewWord(learningWord.getLearnedTimes() == 0);
            }
            learningWord.setLearningOrder(learningOrder);
            learningOrder++;
            updateEntity(learningWord);
        }
    }

    /**
     * 获取最早加入的那些单词，越早加入的单词越靠前
     *
     * @return
     */
    private LearningWord getOldestLearningWord(List<LearningWord> allLearningWords) {
        LearningWord oldestWord = null;
        for (LearningWord learningWord : allLearningWords) {
            if (oldestWord == null
                    || (Util.isSameDay(learningWord.getAddTime(), oldestWord.getAddTime()) && learningWord
                            .getLifeValue() > oldestWord.getLifeValue())
                    || (learningWord.getAddTime().before(oldestWord.getAddTime()) && !Util.isSameDay(
                            learningWord.getAddTime(), oldestWord.getAddTime()))) {
                oldestWord = learningWord;
            }
        }

        return oldestWord;
    }

    /**
     * 产生今天要学习的单词列表，并把该列表更新到数据库
     *
     * @param user
     * @return
     * @throws SQLException
     * @throws IOException
     * @throws ParseException
     * @throws InvalidMeaningFormatException
     * @throws EmptySpellException
     * @throws NamingException
     * @throws ClassNotFoundException
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public List<LearningWord> genTodayWords(User user, final Date now,
            List<LearningWord> todayLearningWords) throws IllegalArgumentException, IllegalAccessException {

        // 删除生命值为0的单词（今日生命值为0的单词不删除）
        Date startTime = new Date();
        userBo.deleteFinishedLearningWordsExceptToday(user);
        Date endTime = new Date();
        log.info("删除生命值为0的单词，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 获取所有正在学习中的单词(作为备选单词列表，将从他们中间选出今日学习的单词)
        startTime = new Date();
        List<LearningWord> allLearningWords = new LinkedList<>();
        allLearningWords.addAll(user.getLearningWords());
        endTime = new Date();
        log.info("获取所有正在学习中的单词，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 通过查询最新加入到学习列表的单词，得知今天是第几天添加单词
        startTime = new Date();
        LearningWord latestWord = null;
        for (LearningWord learningWord : allLearningWords) {
            if (latestWord == null || learningWord.getAddTime().after(latestWord.getAddTime())) {
                latestWord = learningWord;
            }
        }
        int todayDayNumber = 1;
        if (latestWord != null) {
            if (Util.isSameDay(latestWord.getAddTime(), now)) {
                todayDayNumber = latestWord.getAddDay();
            } else {
                todayDayNumber = latestWord.getAddDay() + 1;
            }
        }
        endTime = new Date();
        log.info("判断今天是第几天添加单词，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 从备选单词列表中删除那些已经选为今天学习的单词
        allLearningWords.removeAll(todayLearningWords);

        // 如果需要，添加新单词到learning words
        startTime = new Date();
        List<LearningWord> newLearningWords = addNewLearningWords(user, allLearningWords, todayDayNumber);
        allLearningWords.addAll(newLearningWords);
        endTime = new Date();
        log.info("如果需要，添加新单词到learning words，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 取{ 0, 1, 3, 6, 14 }天之前加入的单词，正常情况下（没有bug，并且用户近期没有调整每日单词量）,
        // 这样取一遍就能得到足够的单词供本日学习了
        startTime = new Date();
        int[] fetchDays = new int[] { 0, 1, 3, 6, 14 };
        for (int day : fetchDays) {
            List<LearningWord> learningWordsOfADay = getLearningWordsAddedAtDay(todayDayNumber - day, allLearningWords);

            for (LearningWord word : learningWordsOfADay) {
                if (!todayLearningWords.contains(word)) {
                    todayLearningWords.add(word);
                    allLearningWords.remove(word);
                    if (todayLearningWords.size() >= user.getWordsPerDay()) {
                        updateTodayLearningWords(todayLearningWords, now);
                        return todayLearningWords;
                    }
                }
            }
        }
        endTime = new Date();
        log.info("取{ 0, 1, 3, 6, 14 }天之前加入的单词，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 如果没有取到足够单词，则从最早的单词一直往前(较新单词的方向)取，这样一定能够取到足够单词（除非单词书中的单词耗尽了），因为:
        // (所有学习中单词的总生命值 L) = 29/5 * N(每日单词量), 所以学习中的单词总数至少有 L/5 = 29/(5*5) * N
        // > N
        startTime = new Date();
        while (todayLearningWords.size() < user.getWordsPerDay()) {
            LearningWord oldestWord = getOldestLearningWord(allLearningWords);

            // 取不到更多单词了，如果单词书中单词耗尽就会出现这样的情况
            if (oldestWord == null) {
                break;
            }

            if (!todayLearningWords.contains(oldestWord)) {
                todayLearningWords.add(oldestWord);
                allLearningWords.remove(oldestWord);
            }
        }
        endTime = new Date();
        log.info("如果没有取到足够单词，则从最早的单词一直往前(较新单词的方向)取，耗时:" + (endTime.getTime() - startTime.getTime()));

        // 将今日的学习单词更新到数据库
        startTime = new Date();
        updateTodayLearningWords(todayLearningWords, now);
        endTime = new Date();
        log.info("将今日的学习单词更新到数据库，耗时:" + (endTime.getTime() - startTime.getTime()));

        return todayLearningWords;
    }

    @Autowired
    StudyRecordBo studyRecordBo;

    /**
     * 学习前准备工作。
     * 准备今天学习的单词，返回新单词和老单词数量
     * 更新session数据，如当前学习位置
     *
     * @param request
     * @param addNewWordsIfNotEnough 如果数据库中本日单词数量不够，是否尝试添加。
     * @return
     * @throws IllegalAccessException
     * @throws ParseException
     * @throws IOException
     * @throws ClassNotFoundException
     * @throws SQLException
     * @throws NamingException
     * @throws EmptySpellException
     * @throws InvalidMeaningFormatException
     */
    public Result<Integer[]> doPrepare(HttpServletRequest request, final boolean addNewWordsIfNotEnough, String userId)
            throws IllegalAccessException, ParseException, IOException, ClassNotFoundException, SQLException,
            NamingException, EmptySpellException, InvalidMeaningFormatException, NoEnoughWordException {
        final Date now = new Date();
        // 如果用户的最近学习日期不是今天，则重置相关数据
        SessionData sessionData = Util.getSessionData(request);
        User user = userBo.findById(userId);
        if (!Util.isSameDay(user.getLastLearningDate(), new Date())) {
            user.setLastLearningDate(Utils.getPureDate(new Date()));
            user.setLearnedDays(user.getLearnedDays() + 1);
            user.setLastLearningPosition(-1);
            user.setLastLearningMode(-1);
            user.setLearningFinished(false);
            user.getWrongWords().clear();
            userBo.updateEntity(user);
        }

        // 尝试直接从数据库中读取今日学习单词(如果今日学习单词已经产生了)
        List<LearningWord> todayWords = getTodayLearningWordsFromDb(user, now);

        // 生成今日要学习的单词列表
        boolean needAddNewWords = todayWords.isEmpty()
                || (todayWords.size() < user.getWordsPerDay() && addNewWordsIfNotEnough);
        if (needAddNewWords) {
            todayWords = genTodayWords(user, now, todayWords);
        }

        // 计算今日新词数
        int newWordCount = 0;
        for (LearningWord word : todayWords) {
            if (word.getIsTodayNewWord()) {
                newWordCount++;
            }
        }

        // 单词是否已经耗尽（词书中没有新词了）
        boolean wordExhausted = (todayWords.size() < user.getWordsPerDay() && needAddNewWords);

        // 写"已开始学习"历史
        UserStudyRecordId id = new UserStudyRecordId(user.getId(), new Date());
        if (studyRecordBo.findById(id) == null) {
            UserStudyRecord userStudyRecord = new UserStudyRecord();
            userStudyRecord.setId(id);
            userStudyRecord.setStartTime(new Date());
            studyRecordBo.createEntity(userStudyRecord);
        }

        sessionData.setWordIndexAndLearningMode(null);
        sessionData.setTodayWords(todayWords);

        Integer[] wordCounts = new Integer[] { newWordCount, todayWords.size() - newWordCount };
        return new Result<>(wordExhausted ? ErrorCode.CODE_WORD_EXHAUSTED : ErrorCode.CODE_SUCCESS, null,
                wordCounts);
    }

    public PagedResults<LearningWord> getLearningWordsForAPage(int pageNo, int pageSize, User user) {
        String hql = "from LearningWord where user = :user and lifeValue > 0 order by lifeValue desc, addTime desc";
        PagedResults<LearningWord> learningWords = pagedQuery(hql, pageNo, pageSize,
                new ImmutablePair<>("user", user));
        return learningWords;
    }

    public PagedResults<LearningWord> getLearningWordsForAPage2(int fromIndex, int pageSize, User user) {
        String hql = "from LearningWord where user = :user and lifeValue > 0 order by DATE_FORMAT(AddTime,'%Y-%m-%d %H:%i:%s') asc, lifeValue asc, md5(wordId) asc";
        PagedResults<LearningWord> learningWords = pagedQuery2(hql, fromIndex, pageSize,
                new ImmutablePair<>("user", user));
        return learningWords;
    }

    public int getLearningWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "WordImageVo.word",
                "images.author.^id,displayNickName" });
        if (word == null) {
            return -1;
        }
        String hql = String
                .format("from LearningWord where user.id = :userId and lifeValue > 0 and id.wordId = :wordId");
        LearningWord learningWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()));
        if (learningWord == null) {
            return -1;
        }

        hql = "select count(0) from LearningWord where user.id = :userId and lifeValue > 0 " +
                "and (" +
                "DATE_FORMAT(addTime,'%Y-%m-%d %H:%i:%s') < :addTime " +
                " or (DATE_FORMAT(addTime,'%Y-%m-%d %H:%i:%s') = :addTime and lifeValue < :lifeValue) " +
                " or (DATE_FORMAT(addTime,'%Y-%m-%d %H:%i:%s') = :addTime and lifeValue = :lifeValue and md5(wordId) <= md5(:wordId) )"
                + ")";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("addTime", new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(learningWord.getAddTime()));
        query.setParameter("lifeValue", learningWord.getLifeValue());
        query.setParameter("wordId", learningWord.getId().getWordId());
        Long result = query.uniqueResult();
        long count = result != null ? result : 0L;

        return (int) count;
    }

    public PagedResults<LearningWord> getTodayWordsForAPage(int pageNo, int pageSize, SortType sortType, User user,
            final Date now) {
        String hql = String.format(
                "from LearningWord where user = :user and lastLearningDate >= :start and lastLearningDate < :end order by learningOrder %s",
                sortType == SortType.Positive ? "asc" : "desc");
        PagedResults<LearningWord> learningWords = pagedQuery(hql, pageNo, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public PagedResults<LearningWord> getTodayNewWordsForAPage(int pageNo, int pageSize, User user, final Date now) {
        String hql = "from LearningWord where user = :user and isTodayNewWord = 1 " +
                "and lastLearningDate >= :start and lastLearningDate < :end order by learningOrder asc";
        PagedResults<LearningWord> learningWords = pagedQuery(hql, pageNo, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public PagedResults<LearningWord> getTodayOldWordsForAPage(int pageNo, int pageSize, User user, final Date now) {
        String hql = "from LearningWord where user = :user and isTodayNewWord = 0 " +
                "and lastLearningDate >= :start and lastLearningDate < :end " +
                "order by learningOrder asc";
        PagedResults<LearningWord> learningWords = pagedQuery(hql, pageNo, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public PagedResults<LearningWord> getTodayWordsForAPage2(int fromIndex, int pageSize, User user, final Date now) {
        String hql = "from LearningWord where user = :user and lastLearningDate >= :start and lastLearningDate < :end order by learningOrder asc";
        PagedResults<LearningWord> learningWords = pagedQuery2(hql, fromIndex, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public int getTodayWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        Date now = new Date();
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "images" });
        if (word == null) {
            return -1;
        }
        String hql = String.format(
                "from LearningWord where user.id = :userId and lastLearningDate >= :start and lastLearningDate < :end and id.wordId = :wordId");
        LearningWord learningWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        if (learningWord == null) {
            return -1;
        }

        hql = "select count(0) from LearningWord where user.id = :userId " +
                "and lastLearningDate >= :start and lastLearningDate < :end " +
                "and learningOrder<=:learningOrder";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("start", DateUtils.truncate(now, Calendar.DATE));
        query.setParameter("end", DateUtils.ceiling(now, Calendar.DATE));
        query.setParameter("learningOrder", learningWord.getLearningOrder());
        Long result = query.uniqueResult();
        long count = result != null ? result : 0L;

        return (int) count;
    }

    public PagedResults<LearningWord> getTodayNewWordsForAPage2(int fromIndex, int pageSize, User user,
            final Date now) {
        String hql = "from LearningWord where user = :user and isTodayNewWord = 1 " +
                "and lastLearningDate >= :start and lastLearningDate < :end order by learningOrder asc";
        PagedResults<LearningWord> learningWords = pagedQuery2(hql, fromIndex, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public int getTodayNewWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        Date now = new Date();
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "WordImageVo.word",
                "images.author.^id,displayNickName" });
        if (word == null) {
            return -1;
        }

        String hql = String.format(
                "from LearningWord where user.id = :userId and isTodayNewWord = 1 and lastLearningDate >= :start and lastLearningDate < :end and id.wordId = :wordId");
        LearningWord learningWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        if (learningWord == null) {
            return -1;
        }

        hql = "select count(0) from LearningWord where user.id = :userId and isTodayNewWord = 1 " +
                "and lastLearningDate >= :start and lastLearningDate < :end " +
                "and learningOrder<=:learningOrder";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("start", DateUtils.truncate(now, Calendar.DATE));
        query.setParameter("end", DateUtils.ceiling(now, Calendar.DATE));
        query.setParameter("learningOrder", learningWord.getLearningOrder());
        Long result = query.uniqueResult();
        long count = result != null ? result : 0L;
        return (int) count;
    }

    public PagedResults<LearningWord> getTodayOldWordsForAPage2(int fromIndex, int pageSize, User user,
            final Date now) {
        String hql = "from LearningWord where user = :user and isTodayNewWord = 0 " +
                "and lastLearningDate >= :start and lastLearningDate < :end " +
                "order by learningOrder asc";
        PagedResults<LearningWord> learningWords = pagedQuery2(hql, fromIndex, pageSize,
                new ImmutablePair<>("user", user),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        return learningWords;
    }

    public int getTodayOldWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        Date now = new Date();
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "WordImageVo.word",
                "images.author.^id,displayNickName" });
        if (word == null) {
            return -1;
        }

        String hql = String.format(
                "from LearningWord where user.id = :userId and isTodayNewWord = 0 and lastLearningDate >= :start and lastLearningDate < :end and id.wordId = :wordId");
        LearningWord learningWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()),
                new ImmutablePair<>("start", DateUtils.truncate(now, Calendar.DATE)),
                new ImmutablePair<>("end", DateUtils.ceiling(now, Calendar.DATE)));
        if (learningWord == null) {
            return -1;
        }

        hql = "select count(0) from LearningWord where user.id = :userId and isTodayNewWord = 0 " +
                "and lastLearningDate >= :start and lastLearningDate < :end " +
                "and learningOrder<=:learningOrder";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("start", DateUtils.truncate(now, Calendar.DATE));
        query.setParameter("end", DateUtils.ceiling(now, Calendar.DATE));
        query.setParameter("learningOrder", learningWord.getLearningOrder());
        Long result = query.uniqueResult();
        long count = result != null ? result : 0L;
        return (int) count;
    }

    /**
     * 从数据库中获取已生成的用户今天要学习的单词列表
     *
     * @param user
     * @return
     */
    public List<LearningWord> getTodayLearningWordsFromDb(User user, Date now) {
        return getTodayWordsForAPage(1, Integer.MAX_VALUE, SortType.Positive, user, now).getRows();
    }

    public List<LearningWordDto> getLearningWordDtosOfUser(String userId) {
        String sql = "select userId, wordId, learningOrder, isTodayNewWord, lifeValue, lastLearningDate, addTime, addDay, learnedTimes, createTime, updateTime from learning_word where userId = :userId";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> list = query.setParameter("userId", userId).list();

        List<LearningWordDto> dtos = new ArrayList<>();
        for (Object obj : list) {
            Object[] values = (Object[]) obj;
            LearningWordDto dto = new LearningWordDto();
            dto.setUserId((String) values[0]);
            dto.setWordId((String) values[1]);
            dto.setLearningOrder((Integer) values[2]);
            dto.setIsTodayNewWord((Boolean) values[3]);
            dto.setLifeValue((Integer) values[4]);
            dto.setLastLearningDate((Date) values[5]);
            dto.setAddTime((Date) values[6]);
            dto.setAddDay((Integer) values[7]);
            dto.setLearnedTimes((Integer) values[8]);
            dto.setCreateTime((Date) values[9]);
            dto.setUpdateTime((Date) values[10]);
            dtos.add(dto);
        }

        return dtos;
    }

    /**
     * 批量删除用户的学习单词记录
     * @param userId 用户ID
     * @param filtersJson 过滤条件JSON字符串
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            // 解析过滤条件
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                // 简单的JSON解析，这里可以根据需要改进
                filters = parseFilters(filtersJson);
            }
            
            // 构建删除SQL
            StringBuilder sql = new StringBuilder("DELETE FROM learning_word WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("wordId")) {
                sql.append(" AND wordId = :wordId");
                parameters.put("wordId", filters.get("wordId"));
            }
            if (filters.containsKey("lifeValue")) {
                sql.append(" AND lifeValue = :lifeValue");
                parameters.put("lifeValue", filters.get("lifeValue"));
            }
            if (filters.containsKey("lastLearningDate")) {
                sql.append(" AND lastLearningDate = :lastLearningDate");
                parameters.put("lastLearningDate", filters.get("lastLearningDate"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            log.info("批量删除学习单词记录完成，用户ID: {}, 删除数量: {}", userId, deletedCount);
            
        } catch (Exception e) {
            log.error("批量删除学习单词记录失败，用户ID: {}, 错误: {}", userId, e.getMessage(), e);
            throw new RuntimeException("批量删除学习单词记录失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 简单的JSON解析方法，将JSON字符串转换为Map
     */
    private Map<String, Object> parseFilters(String filtersJson) {
        Map<String, Object> filters = new HashMap<>();
        try {
            // 移除JSON的大括号
            String content = filtersJson.trim();
            if (content.startsWith("{") && content.endsWith("}")) {
                content = content.substring(1, content.length() - 1);
            }
            
            // 简单的键值对解析
            String[] pairs = content.split(",");
            for (String pair : pairs) {
                String[] keyValue = pair.split(":");
                if (keyValue.length == 2) {
                    String key = keyValue[0].trim().replace("\"", "");
                    String value = keyValue[1].trim().replace("\"", "");
                    filters.put(key, value);
                }
            }
        } catch (Exception e) {
            log.warn("解析过滤条件失败: {}", e.getMessage());
        }
        return filters;
    }

}
