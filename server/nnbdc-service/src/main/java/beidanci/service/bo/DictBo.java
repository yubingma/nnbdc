package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.io.IOException;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

import org.slf4j.Logger;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
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

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

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
        String sql = "SELECT * FROM dict WHERE ownerId = :ownerId";
        MapSqlParameterSource params = new MapSqlParameterSource("ownerId", owner.getId());
        List<Dict> result = namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(Dict.class));
        // fetchSize 在 JDBC 中通过 PreparedStatement.setFetchSize 设置，这里暂时忽略
        return result;
    }

    // 获取指定用户ID的所有单词书
    public List<Dict> getDictsByOwnerId(String ownerId, Integer fetchSize) {
        String sql = "SELECT * FROM dict WHERE ownerId = :ownerId";
        MapSqlParameterSource params = new MapSqlParameterSource("ownerId", ownerId);
        List<Dict> result = namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(Dict.class));
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
            String spell1 = o1.getWordVo(wordCache, excludeFields).getSpell();
            String spell2 = o2.getWordVo(wordCache, excludeFields).getSpell();
            if (spell1 == null) spell1 = "";
            if (spell2 == null) spell2 = "";
            byte[] bytes1 = Objects.requireNonNull(spell1.getBytes());
            byte[] bytes2 = Objects.requireNonNull(spell2.getBytes());
            return DigestUtils.md5DigestAsHex(bytes1)
                    .compareTo(DigestUtils.md5DigestAsHex(bytes2));
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

        String sql = "DELETE FROM dict_word WHERE dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dict.getId());
        namedParameterJdbcTemplate.update(sql, params);

        // 重置词书单词数
        dict.setWordCount(0);
        updateEntity(dict);

        // 重置学习中词书的当前学习位置
        learningDictBo.updateCurrentPositionForUserDict(user, dict.getId(), true);
    }

    public List<Word> getDictWords(Dict dict) {
        String sql = "SELECT w.* FROM word w WHERE EXISTS (" +
                "SELECT 1 FROM dict_word dw WHERE dw.wordId = w.id AND dw.dictId = :dictId)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dict.getId());
        return namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(Word.class));
    }

    public DictDto getDictDto(String dictId) throws ParseException {
        // 通用词典现在是数据库中的实际记录，统一从数据库查询
        String sql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime FROM dict WHERE id=:dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<DictDto> results = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            DictDto dto = new DictDto();
            dto.setId(rs.getString("id"));
            dto.setName(rs.getString("name"));
            dto.setOwnerId(rs.getString("ownerId"));
            dto.setIsShared(rs.getBoolean("isShared"));
            dto.setIsReady(rs.getBoolean("isReady"));
            dto.setVisible(rs.getBoolean("visible"));
            dto.setWordCount(rs.getObject("wordCount", Integer.class));
            dto.setPopularityLimit(rs.getObject("popularityLimit", Integer.class));
            dto.setCreateTime(rs.getTimestamp("createTime"));
            dto.setUpdateTime(rs.getTimestamp("updateTime"));
            return dto;
        });
        return results.isEmpty() ? null : results.get(0);
    }

    /**
     * 获取系统词典列表及其统计信息
     */
    public List<DictStatsVo> getSystemDictsWithStats() {
        // 获取系统词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE ownerId = :sysUserId ORDER BY createTime DESC";
        MapSqlParameterSource params = new MapSqlParameterSource("sysUserId", Constants.SYS_USER_SYS_ID);
        List<DictStatsVo> dictResults = namedParameterJdbcTemplate.query(dictSql, params, (rs, rowNum) -> {
            DictStatsVo dto = new DictStatsVo();
            dto.setId(rs.getString("id"));
            dto.setName(rs.getString("name"));
            dto.setOwnerId(rs.getString("ownerId"));
            dto.setIsShared(rs.getBoolean("isShared"));
            dto.setIsReady(rs.getBoolean("isReady"));
            dto.setVisible(rs.getBoolean("visible"));
            dto.setWordCount(rs.getObject("wordCount", Integer.class));
            dto.setPopularityLimit(rs.getObject("popularityLimit", Integer.class));
            dto.setCreateTime(rs.getTimestamp("createTime"));
            dto.setUpdateTime(rs.getTimestamp("updateTime"));
            return dto;
        });
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Long totalUsers = namedParameterJdbcTemplate.getJdbcTemplate().queryForObject(totalUsersSql, Long.class);
        long totalUsersLong = totalUsers != null ? totalUsers : 0L;
        
        List<DictStatsVo> result = new ArrayList<>();
        
        for (DictStatsVo dto : dictResults) {
            dto.setTotalUsers(totalUsersLong);
            
            // 获取该词典被用户选择的数量
            String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
            MapSqlParameterSource selectionParams = new MapSqlParameterSource("dictId", dto.getId());
            Long selectionCount = namedParameterJdbcTemplate.queryForObject(selectionSql, selectionParams, Long.class);
            long selectionCountLong = selectionCount != null ? selectionCount : 0L;
            dto.setUserSelectionCount(selectionCountLong);
            
            // 计算选择率
            if (totalUsersLong > 0) {
                dto.setSelectionRate((double) selectionCountLong / totalUsersLong * 100);
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
        // 获取词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<DictStatsVo> results = namedParameterJdbcTemplate.query(dictSql, params, (rs, rowNum) -> {
            DictStatsVo dto = new DictStatsVo();
            dto.setId(rs.getString("id"));
            dto.setName(rs.getString("name"));
            dto.setOwnerId(rs.getString("ownerId"));
            dto.setIsShared(rs.getBoolean("isShared"));
            dto.setIsReady(rs.getBoolean("isReady"));
            dto.setVisible(rs.getBoolean("visible"));
            dto.setWordCount(rs.getObject("wordCount", Integer.class));
            dto.setPopularityLimit(rs.getObject("popularityLimit", Integer.class));
            dto.setCreateTime(rs.getTimestamp("createTime"));
            dto.setUpdateTime(rs.getTimestamp("updateTime"));
            return dto;
        });
        
        if (results.isEmpty()) {
            return null;
        }
        
        DictStatsVo dto = results.get(0);
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Long totalUsers = namedParameterJdbcTemplate.getJdbcTemplate().queryForObject(totalUsersSql, Long.class);
        long totalUsersLong = totalUsers != null ? totalUsers : 0L;
        dto.setTotalUsers(totalUsersLong);
        
        // 获取该词典被用户选择的数量
        String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
        Long selectionCount = namedParameterJdbcTemplate.queryForObject(selectionSql, params, Long.class);
        long selectionCountLong = selectionCount != null ? selectionCount : 0L;
        dto.setUserSelectionCount(selectionCountLong);
        
        // 计算选择率
        if (totalUsersLong > 0) {
            dto.setSelectionRate((double) selectionCountLong / totalUsersLong * 100);
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
            String updateWordSql = "UPDATE word SET " +
                    "spell = :spell, " +
                    "shortDesc = :shortDesc, " +
                    "longDesc = :longDesc, " +
                    "pronounce = :pronounce, " +
                    "americaPronounce = :americaPronounce, " +
                    "britishPronounce = :britishPronounce, " +
                    "popularity = :popularity, " +
                    "updateTime = NOW() " +
                    "WHERE id = :wordId";
            
            MapSqlParameterSource updateParams = new MapSqlParameterSource();
            updateParams.addValue("spell", spell);
            updateParams.addValue("shortDesc", shortDesc);
            updateParams.addValue("longDesc", longDesc);
            updateParams.addValue("pronounce", pronounce);
            updateParams.addValue("americaPronounce", americaPronounce);
            updateParams.addValue("britishPronounce", britishPronounce);
            updateParams.addValue("popularity", popularity);
            updateParams.addValue("wordId", wordId);
            namedParameterJdbcTemplate.update(updateWordSql, updateParams);
            
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
            // 1. 首先获取被删除单词的序号（在删除前获取）
            Integer deletedSeq = null;
            String getDeletedSeqSql = "SELECT seq FROM dict_word WHERE dictId = :dictId AND wordId = :wordId";
            MapSqlParameterSource params = new MapSqlParameterSource();
            params.addValue("dictId", dictId);
            params.addValue("wordId", wordId);
            try {
                Integer seq = namedParameterJdbcTemplate.queryForObject(getDeletedSeqSql, params, Integer.class);
                if (seq != null) {
                    deletedSeq = seq;
                }
            } catch (Exception e) {
                // 如果记录不存在，忽略错误
            }
            
            // 2. 删除dict_word表中的记录
            String deleteDictWordSql = "DELETE FROM dict_word WHERE dictId = :dictId AND wordId = :wordId";
            namedParameterJdbcTemplate.update(deleteDictWordSql, params);
            
            // 3. 重新排序剩余单词的序号（删除后，让序号大于被删除单词序号的记录都减1）
            if (deletedSeq != null) {
                String decreaseSeqSql = "UPDATE dict_word SET seq = seq - 1 WHERE dictId = :dictId AND seq > :deletedSeq";
                MapSqlParameterSource decreaseParams = new MapSqlParameterSource();
                decreaseParams.addValue("dictId", dictId);
                decreaseParams.addValue("deletedSeq", deletedSeq);
                namedParameterJdbcTemplate.update(decreaseSeqSql, decreaseParams);
            }
            
            // 4. 更新词典的单词数量
            String updateCountSql = "UPDATE dict SET wordCount = (SELECT COUNT(*) FROM dict_word WHERE dictId = :dictId) WHERE id = :dictId";
            namedParameterJdbcTemplate.update(updateCountSql, params);
            
            // 5. 检查并修复学习进度
            String fixLearningProgressSql = "UPDATE learning_dict ld " +
                    "JOIN dict d ON ld.dictId = d.id " +
                    "SET ld.currentWordSeq = LEAST(ld.currentWordSeq, d.wordCount) " +
                    "WHERE ld.dictId = :dictId AND ld.currentWordSeq > d.wordCount";
            namedParameterJdbcTemplate.update(fixLearningProgressSql, params);
            
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
        String sql = "SELECT id FROM dict WHERE ownerId = :ownerId AND visible = true AND isReady = true";
        MapSqlParameterSource params = new MapSqlParameterSource("ownerId", Constants.SYS_USER_SYS_ID);
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> rs.getString("id"));
    }

    /**
     * 安全删除词典（处理外键约束）
     * 在删除词典之前，先删除相关的记录，按照正确的顺序处理外键约束
     */
    @Transactional
    public void deleteDictSafely(String dictId) {
        try {
            MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
            
            // 1. 先删除 sentence 表中的关联记录（sentence -> meaning_item -> dict）
            String deleteSentencesSql = "DELETE FROM sentence " +
                    "WHERE meaningItemId IN (" +
                    "    SELECT id FROM meaning_item WHERE dictId = :dictId" +
                    ")";
            int deletedSentences = namedParameterJdbcTemplate.update(deleteSentencesSql, params);
            
            // 2. 删除 meaning_item 表中的关联记录
            String deleteMeaningItemsSql = "DELETE FROM meaning_item WHERE dictId = :dictId";
            int deletedMeaningItems = namedParameterJdbcTemplate.update(deleteMeaningItemsSql, params);
            
            // 3. 删除 learning_dict 表中的关联记录
            String deleteLearningDictsSql = "DELETE FROM learning_dict WHERE dictId = :dictId";
            int deletedLearningDicts = namedParameterJdbcTemplate.update(deleteLearningDictsSql, params);
            
            // 4. 删除 dict_word 表中的关联记录
            String deleteDictWordsSql = "DELETE FROM dict_word WHERE dictId = :dictId";
            int deletedDictWords = namedParameterJdbcTemplate.update(deleteDictWordsSql, params);
            
            // 5. 最后删除词典本身
            String deleteDictSql = "DELETE FROM dict WHERE id = :dictId";
            int deletedDicts = namedParameterJdbcTemplate.update(deleteDictSql, params);
            
            log.info("安全删除词典完成: dictId={}, 删除sentence={}条, meaning_item={}条, learning_dict={}条, dict_word={}条, dict={}条", 
                dictId, deletedSentences, deletedMeaningItems, deletedLearningDicts, deletedDictWords, deletedDicts);
                
        } catch (Exception e) {
            log.error("安全删除词典失败: dictId={}, 错误: {}", dictId, e.getMessage(), e);
            throw new RuntimeException("删除词典失败: " + e.getMessage(), e);
        }
    }

    /**
     * 获取用户词典ID列表（只包含可见且就绪的词书）
     */
    public List<String> getUserDictIds() {
        String sql = "SELECT id FROM dict WHERE ownerId != :ownerId AND visible = true AND isReady = true";
        MapSqlParameterSource params = new MapSqlParameterSource("ownerId", Constants.SYS_USER_SYS_ID);
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> rs.getString("id"));
    }

    /**
     * 检查词典单词序号连续性
     */
    public List<Object[]> checkDictWordSequence(String dictId) {
        String sql = "SELECT dw.wordId, dw.seq, w.spell " +
                "FROM dict_word dw " +
                "INNER JOIN word w ON dw.wordId = w.id " +
                "WHERE dw.dictId = :dictId " +
                "ORDER BY dw.seq ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        return namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
            new Object[]{
                rs.getString("wordId"),
                rs.getObject("seq"),
                rs.getString("spell")
            });
    }

    /**
     * 获取词典实际单词数量
     */
    public Long getDictWordCount(String dictId) {
        String sql = "SELECT COUNT(*) FROM dict_word WHERE dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        return namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
    }

    /**
     * 获取词典记录的单词数量
     */
    public Integer getDictRecordedWordCount(String dictId) {
        String sql = "SELECT wordCount FROM dict WHERE id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        return namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
    }

    /**
     * 修复词典单词序号
     */
    public void fixDictWordSequence(String dictId) {
        String sql = "UPDATE dict_word dw1 " +
                "JOIN (" +
                "    SELECT dw2.wordId, ROW_NUMBER() OVER (ORDER BY dw2.seq) as new_seq " +
                "    FROM dict_word dw2 " +
                "    WHERE dw2.dictId = :dictId" +
                ") ranked ON dw1.wordId = ranked.wordId " +
                "SET dw1.seq = ranked.new_seq " +
                "WHERE dw1.dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        namedParameterJdbcTemplate.update(sql, params);
    }

    /**
     * 更新词典单词数量
     */
    public void updateDictWordCount(String dictId, Integer newCount) {
        String sql = "UPDATE dict SET wordCount = :newCount WHERE id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("newCount", newCount);
        params.addValue("dictId", dictId);
        namedParameterJdbcTemplate.update(sql, params);
    }

}
