package beidanci.service.bo;

import java.io.IOException;
import java.sql.Timestamp;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import javax.annotation.PostConstruct;

import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.dao.PaginationResults;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.DictWordId;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictWordBo extends BaseBo<DictWord> {
    public static final String WORD_ALREADY_IN_WORD_BOOK = "单词已经在词书中了";

    @Autowired
    DictBo dictBo;

    @Autowired
    WordCache wordCache;

    @Autowired
    UserBo userBo;

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<DictWord>() {
        });
    }

    /**
     * 获取指定的单词在指定词典中的顺序号（基于md5排序）
     *
     * @return 如果找不到，返回-1
     */
    public int getOrderOfWordId(String dictId, String wordId) {
        DictWordId id = new DictWordId(dictId, wordId);
        DictWord dictWord = findById(id);
        Integer seqNo = dictWord == null ? null : dictWord.getSeq();
        return seqNo == null ? -1 : seqNo;
    }

    /**
     * 获取指定的单词在指定词典中的顺序号（基于md5排序）
     *
     * @return 如果找不到，返回-1
     */
    public int getOrderOfWord(String dictId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords", "WordVo.images" });
        if (word == null) {
            return -1;
        }
        DictWordId id = new DictWordId(dictId, word.getId());
        DictWord dictWord = findById(id);
        Integer seqNo = dictWord == null ? null : dictWord.getSeq();
        return seqNo == null ? -1 : seqNo;
    }

    /**
     * 从指定单词书的指定位置获取单词
     *
     * @return
     */
    public WordVo getWordOfOrder(String dictId, int seqNo) {
        // 转换为 SQL
        String sql = "SELECT * FROM dict_word WHERE dictId = :dictId AND seq = :seq";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", dictId);
        params.addValue("seq", seqNo);
        List<DictWord> results = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(DictWord.class));
        if (results.isEmpty()) {
            return null;
        }
        DictWord dictWord = results.get(0);
        return dictWord.getWordVo(wordCache, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
    }

    public int getWordCountOfDict(String dictName) {
        // 查询记录总数
        String sql = "SELECT COUNT(*) FROM dict_word WHERE dictName = :dictName";
        MapSqlParameterSource params = new MapSqlParameterSource("dictName", dictName);
        Integer total = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return total != null ? total : 0;
    }

    /**
     * 读取指定单词书中的所有单词
     *
     * @param dictName
     * @return
     */
    public PaginationResults<DictWord> getDictWords(String dictName, int pageNo, int pageSize, String orderBy) {

        // 查询记录总数
        int total = getWordCountOfDict(dictName);

        // 查询一页数据
        String sql = "SELECT * FROM dict_word WHERE dictName = :dictName " + (orderBy == null ? "" : " ORDER BY " + orderBy) + " LIMIT :limit OFFSET :offset";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictName", dictName);
        int pageCount = total % pageSize == 0 ? total / pageSize : total / pageSize + 1;
        pageNo = pageNo > pageCount ? pageCount : pageNo;
        int offset = (pageSize * (pageNo - 1));
        params.addValue("limit", pageSize);
        params.addValue("offset", offset);
        List<DictWord> dictWords = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(DictWord.class));

        PaginationResults<DictWord> result = new PaginationResults<>();
        result.setTotal(total);
        result.setRows(dictWords);
        return result;
    }

    /**
     * 获取自定义单词书中的所有单词
     */
    public List<String> getWordSpellsOfDict(String dictId) throws IOException {
        String sql = "SELECT w.spell FROM dict_word dw LEFT JOIN word w ON dw.wordId = w.id WHERE dw.dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<String> dictWords = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> rs.getString("spell"));
        return dictWords;
    }

    /**
     * 向指定单词书中添加指定的单词
     */
    public Result<Object> addWordToDict(String dictId, String wordId, boolean ignoreIfExisted, String userId)
            throws IOException, IllegalAccessException {
        // 数据权限
        Dict dict = dictBo.findById(dictId);
        User user = userBo.findById(userId);
        if (!dict.getOwner().equals(user) && !user.getIsInputor()) {
            return Result.fail("你只能编辑自己的词书");
        }

        // 判断单词是否已经在单词书中了
        DictWordId id = new DictWordId(dictId, wordId);
        DictWord existingWord = findById(id);
        if (existingWord != null) {
            if (ignoreIfExisted) {
                return Result.success(null);
            } else {
                String[] excludeFields = new String[] {
                        "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" };
                return new Result<>(false,
                        String.format("%s已经在该单词书中了，不能再次添加",
                                existingWord.getWordVo(wordCache, excludeFields).getSpell()),
                        null);
            }
        } else {
            // 把单词添加到单词书
            DictWord dictWord = new DictWord();
            dictWord.setId(id);
            dictWord.setDict(dict);
            // dictWord.setWord(wordBo.findById(wordId));
            createEntity(dictWord);

            dict.setWordCount(dict.getWordCount() + 1);
            dictBo.updateEntity(dict);

            return Result.success(null);
        }
    }

    /**
     * 把单词从源单词书导入到目标单词书
     */
    public Result<Object> importFromDict(String fromDictId, String toDictId, String userId)
            throws IOException, IllegalAccessException {
        // 判断单词书是否可编辑
        Dict toDict = dictBo.findById(toDictId);
        if (toDict.getIsReady()) {
            return new Result<>(false, "单词书处于就绪状态，不可编辑", null);
        }

        int count = 0;
        Dict fromDict = dictBo.findById(fromDictId);
        for (DictWord dictWord : fromDict.getDictWords()) {
            String[] excludeFields = new String[] {
                    "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" };
            Result<Object> result = addWordToDict(toDictId, dictWord.getWordVo(wordCache, excludeFields).getId(), false,
                    userId);
            if (result.isSuccess()) {
                count++;
            }
        }

        return new Result<>(true, "导入了" + count + "个单词", null);
    }

    public Result<DictWord> addWordToDict(String spell, Dict dict, String createManner, WordCache wordCache,
            WordBo wordBo, DictBo dictBo) throws IllegalAccessException, InvalidMeaningFormatException,
            EmptySpellException, IOException, ParseException {
        if (spell.trim().length() == 0) {
            return Result.fail("单词拼写不能为空");
        }

        // 检查单词是否在词库中存在
        Word word = wordBo.getWordBySpell(spell);
        if (word == null) {
            return Result.fail(String.format("单词在牛牛词库中不存在"));
        }

        // 检查该单词是否已经在词书中了
        boolean alreadyInRawWordBook = isWordInDict(dict, word.getId());
        if (alreadyInRawWordBook) {
            return Result.fail(String.format(WORD_ALREADY_IN_WORD_BOOK));
        }

        // 保存单词到词书
        DictWord dictWord = new DictWord();
        DictWordId id = new DictWordId(dict.getId(), word.getId());
        dictWord.setId(id);
        dictWord.setDict(dict);
        dictWord.setCreateTime(new Timestamp(new Date().getTime()));
        dictWord.setSeq(getMaxSeqNo(dict) + 1);
        createEntity(dictWord);

        // 更新词书单词数
        String sql = "UPDATE dict SET wordCount = wordCount + 1 WHERE id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dict.getId());
        namedParameterJdbcTemplate.update(sql, params);

        return Result.success(dictWord);
    }

    /**
     * 从指定单词书中删除指定的单词
     */
    public Result<Void> removeWordFromDict(String dictId, String wordId, String userId)
            throws IOException, IllegalAccessException {
        // 数据权限
        Dict dict = dictBo.findById(dictId);
        User user = userBo.findById(userId);
        if (!dict.getOwner().equals(user) && !user.getIsInputor()) {
            return Result.fail("你只能编辑自己的词书");
        }

        // 删除单词
        DictWordId id = new DictWordId(dictId, wordId);
        DictWord dictWord = findById(id);
        if (dictWord == null) {
            return Result.fail("词书中无该单词");
        }
        Integer seqNo = dictWord.getSeq();
        if (seqNo == null) {
            return Result.fail("词书中该单词的序号不存在");
        }
        deleteEntity(dictWord);

        // 后面的单词前移
        String sql = "UPDATE dict_word SET seq = seq - 1 WHERE dictId = :dictId AND seq > :seq";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", dictId);
        params.addValue("seq", seqNo);
        namedParameterJdbcTemplate.update(sql, params);

        // 更新词书单词数
        sql = "UPDATE dict SET wordCount = wordCount - 1 WHERE id = :dictId";
        params = new MapSqlParameterSource("dictId", dictId);
        namedParameterJdbcTemplate.update(sql, params);

        // 更新词书的当前学习位置
        learningDictBo.updateCurrentPositionForUserDict(user, dictId, true);
        return Result.success(null);
    }

    /**
     * 清空指定单词书中的所有单词
     */
    public Result<Object> clearWordsOfDict(int dictId) throws IOException, IllegalAccessException {
        Dict dict = dictBo.findById(dictId);
        if (dict.getIsReady()) {
            return new Result<>(false, "单词书处于就绪状态，不可编辑", null);
        }

        DictWord exam = new DictWord();
        exam.setDict(dict);
        List<DictWord> words = queryAll(exam, false);
        for (DictWord word : words) {
            deleteEntity(word);
        }

        dict.setWordCount(0);
        dictBo.updateEntity(dict);

        return Result.success(null);
    }

    public List<DictWord> getWordsByPage(final Dict dict, final int firstRow, final int pageSize, String ascOrDesc) {
        String sql = "SELECT * FROM dict_word WHERE dictId = :dictId ORDER BY seq " + ascOrDesc + " LIMIT :limit OFFSET :offset";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", dict.getId());
        params.addValue("limit", pageSize);
        params.addValue("offset", firstRow);
        return namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(DictWord.class));
    }

    public int getMaxSeqNo(final Dict dict) {
        String sql = "SELECT MAX(seq) FROM dict_word WHERE dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dict.getId());
        Integer result = namedParameterJdbcTemplate.queryForObject(sql, params, Integer.class);
        return result == null ? 0 : result;
    }

    public boolean isWordInDict(Dict dict, String wordId) {
        DictWordId dictWordId = new DictWordId(dict.getId(), wordId);
        return findById(dictWordId) != null;
    }

    public boolean isWordInRawWordDict(User user, String wordId) {
        Dict rawWordDict = dictBo.getRawWordDict(user);
        return isWordInDict(rawWordDict, wordId);
    }

    public List<DictWordDto> getDictWordsOfDict(String dictId) {
        // 通用词典现在也有dict_word记录，统一查询逻辑
        String sql = "SELECT dictId, wordId, seq, createTime, updateTime FROM dict_word WHERE dictId = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dictId);
        List<DictWordDto> dictWordDtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            DictWordDto dictWordDto = new DictWordDto();
            dictWordDto.setDictId(rs.getString("dictId"));
            dictWordDto.setWordId(rs.getString("wordId"));
            dictWordDto.setSeq(rs.getInt("seq"));
            dictWordDto.setCreateTime(rs.getTimestamp("createTime"));
            dictWordDto.setUpdateTime(rs.getTimestamp("updateTime"));
            return dictWordDto;
        });
        return dictWordDtos;
    }

    /**
     * 获取用户所有生词的DTO列表，用于全量同步
     */
    public List<DictWordDto> getDictWordDtosOfUser(String userId) {
        // 查询用户的生词本中的所有单词
        String sql = "SELECT dw.dictId, dw.wordId, dw.seq, dw.createTime, dw.updateTime " +
                "FROM dict_word dw " +
                "INNER JOIN dict d ON dw.dictId = d.id " +
                "WHERE d.ownerId = :userId " +
                "ORDER BY dw.createTime";
        MapSqlParameterSource params = new MapSqlParameterSource("userId", userId);
        List<DictWordDto> dictWordDtos = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> {
            DictWordDto dictWordDto = new DictWordDto();
            dictWordDto.setDictId(rs.getString("dictId"));
            dictWordDto.setWordId(rs.getString("wordId"));
            dictWordDto.setSeq(rs.getInt("seq"));
            dictWordDto.setCreateTime(rs.getTimestamp("createTime"));
            dictWordDto.setUpdateTime(rs.getTimestamp("updateTime"));
            return dictWordDto;
        });
        return dictWordDtos;
    }

    /**
     * 校验指定用户的生词本序号是否从1开始且连续
     * 若发现问题，返回问题描述字符串，否则返回null
     */
    public String validateRawWordOrderOfUser(String userId) {
        // 查找用户的生词本
        Dict rawWordDict = dictBo.getRawWordDict(userBo.findById(userId));
        if (rawWordDict == null) {
            return null;
        }
        // 取出生词本内所有词，按seq排序
        String sql = "SELECT dw.wordId, dw.seq FROM dict_word dw WHERE dw.dictId = :dictId ORDER BY dw.seq";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", rawWordDict.getId());
        List<Object[]> list = namedParameterJdbcTemplate.query(sql, params, (rs, rowNum) -> 
            new Object[]{rs.getString("wordId"), rs.getInt("seq")});
        if (list == null || list.isEmpty()) {
            return null;
        }
        int expected = 1;
        Integer firstIndex = null;
        Integer lastIndex = null;
        for (Object[] tuple : list) {
            Integer indexNo = ((Number) tuple[1]).intValue();
            if (firstIndex == null)
                firstIndex = indexNo;
            lastIndex = indexNo;
            if (indexNo != expected) {
                return String.format("序号不连续: 期望=%d, 实际=%d", expected, indexNo);
            }
            expected++;
        }
        // 额外校验开头是否为1
        if (firstIndex != null && firstIndex != 1) {
            return String.format("不是从1开始: 第一个序号=%d", firstIndex);
        }
        // 校验最大值是否等于数量
        if (lastIndex != null && lastIndex != list.size()) {
            return String.format("最大序号异常: 最大=%d, 总数=%d", lastIndex, list.size());
        }
        return null;
    }

    /**
     * 覆盖指定用户的生词本：先清空服务端生词本，再批量写入客户端传来的词序
     * 返回写入的记录数
     */
    public int overwriteRawDictForUser(String userId, List<DictWordDto> dictWordDtos) throws IllegalAccessException {
        Dict rawWordDict = dictBo.getRawWordDict(userBo.findById(userId));
        if (rawWordDict == null) {
            return 0;
        }
        // 清空
        String deleteSql = "DELETE FROM dict_word WHERE dictId = :dictId";
        MapSqlParameterSource deleteParams = new MapSqlParameterSource("dictId", rawWordDict.getId());
        namedParameterJdbcTemplate.update(deleteSql, deleteParams);

        // 批量插入
        int count = 0;
        String insertSql = "INSERT INTO dict_word (dictId, wordId, seq, createTime, updateTime) " +
                "VALUES (:dictId, :wordId, :seq, :createTime, :updateTime)";
        for (DictWordDto dto : dictWordDtos) {
            MapSqlParameterSource insertParams = new MapSqlParameterSource();
            insertParams.addValue("dictId", dto.getDictId());
            insertParams.addValue("wordId", dto.getWordId());
            insertParams.addValue("seq", dto.getSeq());
            insertParams.addValue("createTime", dto.getCreateTime());
            insertParams.addValue("updateTime", dto.getUpdateTime());
            namedParameterJdbcTemplate.update(insertSql, insertParams);
            count++;
        }

        // 更新词书单词数
        String sql = "UPDATE dict SET wordCount = :cnt WHERE id = :dictId";
        MapSqlParameterSource updateParams = new MapSqlParameterSource();
        updateParams.addValue("cnt", count);
        updateParams.addValue("dictId", rawWordDict.getId());
        namedParameterJdbcTemplate.update(sql, updateParams);

        return count;
    }

    /**
     * 批量删除用户的dict_word记录
     * 
     * @param userId      用户ID（用于安全验证，确保要删除的生词本属于该用户）
     * @param filtersJson 过滤条件JSON字符串
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            // 解析过滤条件
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                filters = parseFilters(filtersJson);
            }
            // 安全校验：过滤参数不允许为空，且必须包含 dictId
            if (filters == null || filters.isEmpty() || !filters.containsKey("dictId")) {
                throw new IllegalArgumentException("批量删除dict_word需要提供过滤条件，且必须包含dictId");
            }
            // 进一步校验 dictId 合法性（非空字符串）
            Object dictIdObj = filters.get("dictId");
            if (dictIdObj == null || String.valueOf(dictIdObj).trim().isEmpty()) {
                throw new IllegalArgumentException("dictId 不能为空");
            }

            // 构建删除SQL - 通过JOIN确保只删除属于该用户的生词本中的记录
            StringBuilder sql = new StringBuilder("DELETE dw FROM dict_word dw ");
            sql.append("INNER JOIN dict d ON dw.dictId = d.id ");
            sql.append("WHERE d.ownerId = :userId");

            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);

            // 添加过滤条件
            sql.append(" AND dw.dictId = :dictId");
            parameters.put("dictId", filters.get("dictId"));

            MapSqlParameterSource params = new MapSqlParameterSource();
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                params.addValue(Objects.requireNonNull(entry.getKey(), "Parameter key cannot be null"), entry.getValue());
            }

            int deletedCount = namedParameterJdbcTemplate.update(Objects.requireNonNull(sql.toString(), "SQL cannot be null"), params);
            System.out.println("批量删除dict_word记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);

        } catch (Exception e) {
            System.err.println("批量删除dict_word记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除dict_word记录失败: " + e.getMessage(), e);
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
            System.err.println("解析过滤条件失败: " + e.getMessage());
        }
        return filters;
    }
}
