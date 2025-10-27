package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.io.IOException;
import java.sql.Timestamp;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.slf4j.Logger;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.DigestUtils;

import beidanci.api.Result;
import beidanci.api.model.DictDto;
import beidanci.api.model.DictVo;
import beidanci.api.model.DictStatsVo;
import beidanci.api.model.DictWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningDictId;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;
import beidanci.service.util.JsonUtils;
import beidanci.util.Constants;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictBo extends BaseBo<Dict> {
    private static final Logger log = org.slf4j.LoggerFactory.getLogger(DictBo.class);

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    WordCache wordCache;

    @Autowired
    SysDbLogBo sysDbLogBo;

        @PostConstruct
    public void init() {
        setDao(new BaseDao<Dict>() {
        });
    }

    public void selectDicts(String[] selectedDicts, String userId) throws IllegalAccessException {

        HashSet<String> selectedDictIds = new HashSet<>(Arrays.asList(selectedDicts));

        // 删除用户取消选择的单词书
        User user = userBo.findById(userId);
        for (Iterator<LearningDict> i = user.getLearningDicts().iterator(); i.hasNext();) {
            LearningDict learningDict = i.next();
            if (!selectedDictIds.contains(learningDict.getDict().getId())
                    && !learningDict.getDict().getName().equals("生词本")) {
                learningDictBo.deleteEntity(learningDict);
                i.remove();
                log.info(String.format("用户[%s]取消选择了单词书[%s]", Util.getNickNameOfUser(user),
                        learningDict.getDict().getShortName()));
            }
        }

        // 添加用户新选择的单词书
        for (String dictId : selectedDicts) {
            LearningDictId id = new LearningDictId(user.getId(), dictId);
            LearningDict selectedDict = learningDictBo.findById(id, false);
            if (selectedDict == null) {
                Dict dict = dictBo.findById(dictId, false);
                assert (dict.getIsReady());
                selectedDict = new LearningDict(id, dict, user, false, false);
                learningDictBo.createEntity(selectedDict);
                user.getLearningDicts().add(selectedDict);
                log.info(String.format("用户[%s]选择了单词书[%s]", Util.getNickNameOfUser(user), dict.getShortName()));
            }
        }

        userBo.updateEntity(user);
    }

    // 获取指定用户的所有单词书
    public List<Dict> getOwnDicts(User owner, Integer fetchSize) {
        Session session = getSession();
        String hql = "from Dict where owner=:owner";
        Query<Dict> query = session.createQuery(hql, Dict.class);
        query.setCacheable(true);
        query.setParameter("owner", owner);
        if (fetchSize != null) {
            query.setFetchSize(fetchSize);
        }
        List<Dict> result = query.list();
        return result;
    }

    // 获取指定用户ID的所有单词书
    public List<Dict> getDictsByOwnerId(String ownerId, Integer fetchSize) {
        Session session = getSession();
        String hql = "from Dict d where d.owner.id=:ownerId";
        Query<Dict> query = session.createQuery(hql, Dict.class);
        query.setCacheable(true);
        query.setParameter("ownerId", ownerId);
        if (fetchSize != null) {
            query.setFetchSize(fetchSize);
        }
        List<Dict> result = query.list();
        System.out.println("查询用户ID为 " + ownerId + " 的词典，共找到 " + result.size() + " 条记录");
        return result;
    }

    // 获取所有系统单词书
    public List<Dict> getAllSysDicts(Integer fetchSize) {
        User user = userBo.getByUserName(Constants.SYS_USER_SYS, false);
        return getOwnDicts(user, fetchSize);
    }

    /**
     * 完成对指定单词书的编辑
     *
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public Result<Object> finishEditingDict(int dictId)
            throws IllegalArgumentException, IllegalAccessException {
        Dict dict = dictBo.findById(dictId, false);
        if (dict.getIsReady()) {
            return new Result<>(false, "单词书已处于就绪状态，不可重复操作", null);
        }
        if (dict.getWordCount() < 10) {
            return new Result<>(false, "单词书中的单词数量不能小于10个", null);
        }

        // 对书中的单词进行乱序
        Collections.sort(dict.getDictWords(), (o1, o2) -> {
            String[] excludeFields = new String[] {
                    "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" };
            return DigestUtils.md5DigestAsHex(o1.getWordVo(wordCache, excludeFields).getSpell().getBytes())
                    .compareTo(DigestUtils
                            .md5DigestAsHex(o2.getWordVo(wordCache, excludeFields).getSpell().getBytes()));
        });
        int seq = 1; // 单词排序的顺序号
        for (DictWord dictWord : dict.getDictWords()) {
            dictWord.setSeq(seq);
            dictWordBo.updateEntity(dictWord);
            seq++;
        }

        dict.setWordCount(dict.getDictWords().size());
        dict.setIsReady(true);
        updateEntity(dict);

        return Result.success(null);
    }

    /**
     * 创建新单词书
     *
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public Result<DictVo> createNewDict(String dictName, User user)
            throws IOException, IllegalArgumentException, IllegalAccessException {
        // 检查同名单词书是否已经存在
        List<Dict> allMyDicts = getOwnDicts(user, null);
        for (Dict dict : allMyDicts) {
            if (dict.getShortName().equalsIgnoreCase(dictName)) {
                return new Result<>(false, "同名单词书已经存在", null);
            }
        }

        Dict dict = new Dict();
        dict.setWordCount(0);
        dict.setIsReady(false); // 新单词书处于待编辑状态
        dict.setIsShared(false);
        dict.setVisible(true);
        dict.setName(dictName + "." + new SimpleDateFormat("yyyyMMddHHmmss").format(new Date()));
        dict.setOwner(user);
        createEntity(dict);

        DictVo vo = BeanUtils.makeVo(dict, DictVo.class,
                new String[] { "invitedBy", "studyGroups", "userGames", "dictWords" });

        return new Result<>(true, null, vo);
    }

    public Dict findByName(String dictName) {
        Dict exam = new Dict();
        exam.setName(dictName);
        return queryUnique(exam);
    }

    public Dict getRawWordDict(User user) {
        Dict exam = new Dict();
        exam.setOwner(user);
        exam.setName("生词本");
        return queryUnique(exam);
    }

    public void clearDict(User user, Dict dict) throws IllegalAccessException {
        if (!dict.getOwner().equals(user)) {
            throw new RuntimeException("用户不得删除不属于自己的词书");
        }

        String hql = "delete DictWord where dict=:dict";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("dict", dict);
        query.executeUpdate();

        // 重置词书单词数
        dict.setWordCount(0);
        updateEntity(dict);

        // 重置学习中词书的当前学习位置
        learningDictBo.updateCurrentPositionForUserDict(user, dict.getId(), true);
    }

    public List<Word> getDictWords(Dict dict) {
        String hql = "from Word w where exists (" +
                "from DictWord dw where dw.word.id=w.id and dw.dict=:dict)";
        Query<Word> query = getSession().createQuery(hql, Word.class);
        query.setParameter("dict", dict);
        return query.list();
    }

    public DictDto getDictDto(String dictId) throws ParseException {
        // 通用词典现在是数据库中的实际记录，统一从数据库查询
        String sql = "select id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime from dict where id=:dictId";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", dictId);
        Object[] result = (Object[]) query.uniqueResult();

        if (result == null) {
            return null;
        }

        DictDto dto = new DictDto();
        dto.setId((String) result[0]);
        dto.setName((String) result[1]);
        dto.setOwnerId((String) result[2]);
        dto.setIsShared((Boolean) result[3]);
        dto.setIsReady((Boolean) result[4]);
        dto.setVisible((Boolean) result[5]);
        dto.setWordCount((Integer) result[6]);
        dto.setPopularityLimit((Integer) result[7]);
        dto.setCreateTime((Timestamp) result[8]);
        dto.setUpdateTime((Timestamp) result[9]);
        return dto;
    }

    /**
     * 获取系统词典列表及其统计信息
     */
    public List<DictStatsVo> getSystemDictsWithStats() {
        Session session = getSession();
        
        // 获取系统词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE ownerId = :sysUserId ORDER BY createTime DESC";
        Query<?> dictQuery = session.createNativeQuery(dictSql);
        dictQuery.setParameter("sysUserId", Constants.SYS_USER_SYS_ID);
        List<?> dictResults = dictQuery.list();
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Query<?> totalUsersQuery = session.createNativeQuery(totalUsersSql);
        Long totalUsers = ((Number) totalUsersQuery.uniqueResult()).longValue();
        
        List<DictStatsVo> result = new ArrayList<>();
        
        for (Object dictResult : dictResults) {
            Object[] dictData = (Object[]) dictResult;
            
            DictStatsVo dto = new DictStatsVo();
            dto.setId((String) dictData[0]);
            dto.setName((String) dictData[1]);
            dto.setOwnerId((String) dictData[2]);
            dto.setIsShared((Boolean) dictData[3]);
            dto.setIsReady((Boolean) dictData[4]);
            dto.setVisible((Boolean) dictData[5]);
            dto.setWordCount((Integer) dictData[6]);
            dto.setPopularityLimit((Integer) dictData[7]);
            dto.setCreateTime((Timestamp) dictData[8]);
            dto.setUpdateTime((Timestamp) dictData[9]);
            dto.setTotalUsers(totalUsers);
            
            // 获取该词典被用户选择的数量
            String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
            Query<?> selectionQuery = session.createNativeQuery(selectionSql);
            selectionQuery.setParameter("dictId", dto.getId());
            Long selectionCount = ((Number) selectionQuery.uniqueResult()).longValue();
            dto.setUserSelectionCount(selectionCount);
            
            // 计算选择率
            if (totalUsers > 0) {
                dto.setSelectionRate((double) selectionCount / totalUsers * 100);
            } else {
                dto.setSelectionRate(0.0);
            }
            
            result.add(dto);
        }
        
        return result;
    }
    
    /**
     * 获取指定词典的详细统计信息
     */
    public DictStatsVo getDictStats(String dictId) {
        Session session = getSession();
        
        // 获取词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE id = :dictId";
        Query<?> dictQuery = session.createNativeQuery(dictSql);
        dictQuery.setParameter("dictId", dictId);
        Object[] dictData = (Object[]) dictQuery.uniqueResult();
        
        if (dictData == null) {
            return null;
        }
        
        DictStatsVo dto = new DictStatsVo();
        dto.setId((String) dictData[0]);
        dto.setName((String) dictData[1]);
        dto.setOwnerId((String) dictData[2]);
        dto.setIsShared((Boolean) dictData[3]);
        dto.setIsReady((Boolean) dictData[4]);
        dto.setVisible((Boolean) dictData[5]);
        dto.setWordCount((Integer) dictData[6]);
        dto.setPopularityLimit((Integer) dictData[7]);
        dto.setCreateTime((Timestamp) dictData[8]);
        dto.setUpdateTime((Timestamp) dictData[9]);
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Query<?> totalUsersQuery = session.createNativeQuery(totalUsersSql);
        Long totalUsers = ((Number) totalUsersQuery.uniqueResult()).longValue();
        dto.setTotalUsers(totalUsers);
        
        // 获取该词典被用户选择的数量
        String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
        Query<?> selectionQuery = session.createNativeQuery(selectionSql);
        selectionQuery.setParameter("dictId", dictId);
        Long selectionCount = ((Number) selectionQuery.uniqueResult()).longValue();
        dto.setUserSelectionCount(selectionCount);
        
        // 计算选择率
        if (totalUsers > 0) {
            dto.setSelectionRate((double) selectionCount / totalUsers * 100);
        } else {
            dto.setSelectionRate(0.0);
        }
        
        return dto;
    }

    /**
     * 更新系统词典信息
     */
    public void updateSystemDict(String dictId, String name, boolean isReady, boolean visible, Integer popularityLimit) {
        Dict dict = findById(dictId);
        if (dict == null) {
            throw new RuntimeException("词典不存在: " + dictId);
        }
        
        dict.setName(name);
        dict.setIsReady(isReady);
        dict.setVisible(visible);
        dict.setPopularityLimit(popularityLimit);
        dict.setUpdateTime(new java.sql.Timestamp(System.currentTimeMillis()));
        
        try {
            updateEntity(dict);
            
            // 记录系统数据同步日志，使前端能够感知到词典信息的变更
            DictDto dictDto = new DictDto(
                dict.getId(),
                dict.getName(),
                dict.getOwner().getId(),
                dict.getIsShared(),
                dict.getIsReady(),
                dict.getVisible(),
                dict.getWordCount(),
                dict.getPopularityLimit(),
                dict.getCreateTime(),
                dict.getUpdateTime()
            );
            
            sysDbLogBo.logOperation("UPDATE", "dict", dictId, JsonUtils.toJson(dictDto));
        } catch (Exception e) {
            throw new RuntimeException("更新词典失败: " + e.getMessage(), e);
        }
    }

    /**
     * 更新词典中的单词信息
     */
    public void updateDictWord(String wordId, String spell, String shortDesc, String longDesc,
                              String pronounce, String americaPronounce, String britishPronounce, 
                              Integer popularity) {
        try {
            // 更新word表
            String updateWordSql = """
                UPDATE word SET 
                    spell = ?, 
                    shortDesc = ?, 
                    longDesc = ?, 
                    pronounce = ?, 
                    americaPronounce = ?, 
                    britishPronounce = ?, 
                    popularity = ?, 
                    updateTime = NOW()
                WHERE id = ?
            """;
            
            Session session = getSession();
            session.createNativeQuery(updateWordSql)
                .setParameter(1, spell)
                .setParameter(2, shortDesc)
                .setParameter(3, longDesc)
                .setParameter(4, pronounce)
                .setParameter(5, americaPronounce)
                .setParameter(6, britishPronounce)
                .setParameter(7, popularity)
                .setParameter(8, wordId)
                .executeUpdate();
            
            // 记录系统数据同步日志
            java.util.Map<String, Object> record = new java.util.HashMap<>();
            record.put("id", wordId);
            record.put("spell", spell);
            record.put("shortDesc", shortDesc);
            record.put("longDesc", longDesc);
            record.put("pronounce", pronounce);
            record.put("americaPronounce", americaPronounce);
            record.put("britishPronounce", britishPronounce);
            record.put("popularity", popularity);
            record.put("updateTime", new java.sql.Timestamp(System.currentTimeMillis()));
            
            sysDbLogBo.logOperation("UPDATE", "word", wordId, JsonUtils.toJson(record));
        } catch (Exception e) {
            throw new RuntimeException("更新单词失败: " + e.getMessage(), e);
        }
    }

    /**
     * 从词典中删除单词
     */
    public void removeWordFromDict(String dictId, String wordId) {
        try {
            Session session = getSession();
            
            // 1. 首先获取被删除单词的序号（在删除前获取）
            Integer deletedSeq = null;
            String getDeletedSeqSql = "SELECT seq FROM dict_word WHERE dictId = ? AND wordId = ?";
            try {
                Object deletedSeqResult = session.createNativeQuery(getDeletedSeqSql)
                    .setParameter(1, dictId)
                    .setParameter(2, wordId)
                    .getSingleResult();
                if (deletedSeqResult != null) {
                    deletedSeq = ((Number) deletedSeqResult).intValue();
                }
            } catch (Exception e) {
                // 如果记录不存在，忽略错误
            }
            
            // 2. 删除dict_word表中的记录
            String deleteDictWordSql = "DELETE FROM dict_word WHERE dictId = ? AND wordId = ?";
            session.createNativeQuery(deleteDictWordSql)
                .setParameter(1, dictId)
                .setParameter(2, wordId)
                .executeUpdate();
            
            // 3. 重新排序剩余单词的序号（删除后，让序号大于被删除单词序号的记录都减1）
            if (deletedSeq != null) {
                String decreaseSeqSql = "UPDATE dict_word SET seq = seq - 1 WHERE dictId = ? AND seq > ?";
                session.createNativeQuery(decreaseSeqSql)
                    .setParameter(1, dictId)
                    .setParameter(2, deletedSeq)
                    .executeUpdate();
            }
            
            // 4. 更新词典的单词数量
            String updateCountSql = "UPDATE dict SET wordCount = (SELECT COUNT(*) FROM dict_word WHERE dictId = ?) WHERE id = ?";
            session.createNativeQuery(updateCountSql)
                .setParameter(1, dictId)
                .setParameter(2, dictId)
                .executeUpdate();
            
            // 5. 检查并修复学习进度
            String fixLearningProgressSql = """
                UPDATE learning_dict ld
                JOIN dict d ON ld.dictId = d.id
                SET ld.currentWordSeq = LEAST(ld.currentWordSeq, d.wordCount)
                WHERE ld.dictId = ? AND ld.currentWordSeq > d.wordCount
            """;
            session.createNativeQuery(fixLearningProgressSql)
                .setParameter(1, dictId)
                .executeUpdate();
            
            // 6. 记录系统数据同步日志
            DictWordDto dictWordDto = new DictWordDto();
            dictWordDto.setDictId(dictId);
            dictWordDto.setWordId(wordId);
            dictWordDto.setSeq(deletedSeq);
            dictWordDto.setCreateTime(null);
            dictWordDto.setUpdateTime(new java.sql.Timestamp(System.currentTimeMillis()));
            
            sysDbLogBo.logOperation("DELETE", "dict_word", dictId + "_" + wordId, JsonUtils.toJson(dictWordDto));
        } catch (Exception e) {
            throw new RuntimeException("删除单词失败: " + e.getMessage(), e);
        }
    }

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 获取系统词典ID列表（只包含可见且就绪的词书）
     */
    public List<String> getSystemDictIds() {
        String hql = "SELECT d.id FROM Dict d WHERE d.owner.id = :ownerId AND d.visible = true AND d.isReady = true";
        Query<String> query = getSession().createQuery(hql, String.class);
        query.setParameter("ownerId", Constants.SYS_USER_SYS_ID);
        return query.list();
    }

    /**
     * 获取用户词典ID列表（只包含可见且就绪的词书）
     */
    public List<String> getUserDictIds() {
        String hql = "SELECT d.id FROM Dict d WHERE d.owner.id != :ownerId AND d.visible = true AND d.isReady = true";
        Query<String> query = getSession().createQuery(hql, String.class);
        query.setParameter("ownerId", Constants.SYS_USER_SYS_ID);
        return query.list();
    }

    /**
     * 检查词典单词序号连续性
     */
    public List<Object[]> checkDictWordSequence(String dictId) {
        String hql = """
            SELECT dw.word.id, dw.seq, dw.word.spell
            FROM DictWord dw
            WHERE dw.dict.id = :dictId
            ORDER BY dw.seq ASC
            """;
        Query<Object[]> query = getSession().createQuery(hql, Object[].class);
        query.setParameter("dictId", dictId);
        return query.list();
    }

    /**
     * 获取词典实际单词数量
     */
    public Long getDictWordCount(String dictId) {
        String hql = "SELECT COUNT(*) FROM DictWord dw WHERE dw.dict.id = :dictId";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("dictId", dictId);
        return query.uniqueResult();
    }

    /**
     * 获取词典记录的单词数量
     */
    public Integer getDictRecordedWordCount(String dictId) {
        String hql = "SELECT d.wordCount FROM Dict d WHERE d.id = :dictId";
        Query<Integer> query = getSession().createQuery(hql, Integer.class);
        query.setParameter("dictId", dictId);
        return query.uniqueResult();
    }

    /**
     * 修复词典单词序号
     */
    public void fixDictWordSequence(String dictId) {
        String sql = """
            UPDATE dict_word dw1
            JOIN (
                SELECT dw2.wordId, ROW_NUMBER() OVER (ORDER BY dw2.seq) as new_seq
                FROM dict_word dw2
                WHERE dw2.dictId = :dictId
            ) ranked ON dw1.wordId = ranked.wordId
            SET dw1.seq = ranked.new_seq
            WHERE dw1.dictId = :dictId
            """;
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", dictId);
        query.executeUpdate();
    }

    /**
     * 更新词典单词数量
     */
    public void updateDictWordCount(String dictId, Integer newCount) {
        String hql = "UPDATE Dict d SET d.wordCount = :newCount WHERE d.id = :dictId";
        Query<?> query = getSession().createQuery(hql);
        query.setParameter("newCount", newCount);
        query.setParameter("dictId", dictId);
        query.executeUpdate();
    }

}
