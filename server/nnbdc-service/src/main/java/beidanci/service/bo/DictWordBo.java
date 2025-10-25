package beidanci.service.bo;

import java.io.IOException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;

import org.hibernate.Session;
import org.hibernate.query.NativeQuery;
import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.api.model.DictWordDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
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
        String hql = "from DictWord where dict.id=:dictId and seq=:seq";
        Query<DictWord> query = getSession().createQuery(hql, DictWord.class);
        query.setParameter("dictId", dictId);
        query.setParameter("seq", seqNo);
        query.setCacheable(true);
        DictWord dictWord = query.uniqueResult();
        return dictWord.getWordVo(wordCache, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
    }

    public int getWordCountOfDict(String dictName) {
        // 查询记录总数
        Session session = getSession();
        String hql = "select count(0) from DictWord where dictName=:dictName";
        Query<Long> query = session.createQuery(hql, Long.class);
        query.setParameter("dictName", dictName);
        query.setCacheable(true);
        int total = query.uniqueResult().intValue();
        return total;
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
        Session session = getSession();
        String sql = "from DictWord where dictName=:dictName " + (orderBy == null ? "" : " order by " + orderBy);
        Query<DictWord> query = session.createQuery(sql, DictWord.class);
        query.setParameter("dictName", dictName);
        int pageCount = total % pageSize == 0 ? total / pageSize : total / pageSize + 1;
        pageNo = pageNo > pageCount ? pageCount : pageNo;
        int offset = (pageSize * (pageNo - 1));
        query.setFirstResult(offset);
        query.setMaxResults(pageSize);
        List<DictWord> dictWords = query.list();

        PaginationResults<DictWord> result = new PaginationResults<>();
        result.setTotal(total);
        result.setRows(dictWords);
        return result;
    }

    /**
     * 获取自定义单词书中的所有单词
     */
    public List<String> getWordSpellsOfDict(String dictId) throws IOException {
        Session session = getSession();
        String sql = "select w.spell from dict_word dw left join word w on dw.wordId=w.id where dw.dictId=:dictId ";
        NativeQuery<String> query = session.createNativeQuery(sql, String.class);
        query.setParameter("dictId", dictId);

        List<String> dictWords = query.list();
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
        String hql = "update Dict set wordCount=wordCount+1 where id=:dictId";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("dictId", dict.getId());
        query.executeUpdate();

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
        String hql = "update DictWord set seq = seq - 1 where dict.id=:dictId and seq > :seq";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("dictId", dictId);
        query.setParameter("seq", seqNo);
        query.executeUpdate();

        // 更新词书单词数
        hql = "update Dict set wordCount=wordCount-1 where id=:dictId";
        query = getSession().createQuery(hql);
        query.setParameter("dictId", dictId);
        query.executeUpdate();

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
        Query<DictWord> query = getSession()
                .createQuery(" from DictWord where dict = :dict" + " order by seq " + ascOrDesc, DictWord.class);
        query.setParameter("dict", dict);
        query.setFirstResult(firstRow);
        query.setMaxResults(pageSize);
        return query.list();
    }

    public int getMaxSeqNo(final Dict dict) {
        Query<Integer> query = getSession().createQuery("select max(seq) from DictWord where dict = :dict",
                Integer.class);
        query.setParameter("dict", dict);
        Integer result = query.uniqueResult();
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
        String sql = "select dictId, wordId, seq, createTime, updateTime from dict_word where dictId = :dictId";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", dictId);
        List<?> results = query.list();
        List<DictWordDto> dictWordDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            DictWordDto dictWordDto = new DictWordDto();
            dictWordDto.setDictId((String) tuple[0]);
            dictWordDto.setWordId((String) tuple[1]);
            dictWordDto.setSeq((Integer) tuple[2]);
            dictWordDto.setCreateTime((Timestamp) tuple[3]);
            dictWordDto.setUpdateTime((Timestamp) tuple[4]);
            dictWordDtos.add(dictWordDto);
        }
        return dictWordDtos;
    }

    /**
     * 获取用户所有生词的DTO列表，用于全量同步
     */
    public List<DictWordDto> getDictWordDtosOfUser(String userId) {
        // 查询用户的生词本中的所有单词
        String sql = "select dw.dictId, dw.wordId, dw.seq, dw.createTime, dw.updateTime " +
                "from dict_word dw " +
                "inner join dict d on dw.dictId = d.id " +
                "where d.ownerId = :userId " +
                "order by dw.createTime";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("userId", userId);
        List<?> results = query.list();

        List<DictWordDto> dictWordDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            DictWordDto dictWordDto = new DictWordDto();
            dictWordDto.setDictId((String) tuple[0]);
            dictWordDto.setWordId((String) tuple[1]);
            dictWordDto.setSeq((Integer) tuple[2]);
            dictWordDto.setCreateTime((Date) tuple[3]);
            dictWordDto.setUpdateTime((Date) tuple[4]);
            dictWordDtos.add(dictWordDto);
        }
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
        String sql = "select dw.wordId, dw.seq from dict_word dw where dw.dictId = :dictId order by dw.seq";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", rawWordDict.getId());
        List<?> list = query.list();
        if (list == null || list.isEmpty()) {
            return null;
        }
        int expected = 1;
        Integer firstIndex = null;
        Integer lastIndex = null;
        for (Object row : list) {
            Object[] tuple = (Object[]) row;
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
        javax.persistence.Query delQuery = getSession().createNativeQuery(deleteSql);
        delQuery.setParameter("dictId", rawWordDict.getId());
        delQuery.executeUpdate();

        // 批量插入
        int count = 0;
        String insertSql = "INSERT INTO dict_word (dictId, wordId, seq, createTime, updateTime) " +
                "VALUES (:dictId, :wordId, :seq, :createTime, :updateTime)";
        for (DictWordDto dto : dictWordDtos) {
            javax.persistence.Query ins = getSession().createNativeQuery(insertSql);
            ins.setParameter("dictId", dto.getDictId());
            ins.setParameter("wordId", dto.getWordId());
            ins.setParameter("seq", dto.getSeq());
            ins.setParameter("createTime", dto.getCreateTime());
            ins.setParameter("updateTime", dto.getUpdateTime());
            ins.executeUpdate();
            count++;
        }

        // 更新词书单词数
        String hql = "update Dict set wordCount = :cnt where id=:dictId";
        javax.persistence.Query q = getSession().createQuery(hql);
        q.setParameter("cnt", count);
        q.setParameter("dictId", rawWordDict.getId());
        q.executeUpdate();

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

            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }

            int deletedCount = query.executeUpdate();
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
