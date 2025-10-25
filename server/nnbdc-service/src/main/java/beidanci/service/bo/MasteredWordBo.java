package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.commons.lang3.tuple.ImmutablePair;
import org.hibernate.query.Query;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MasteredWordDto;
import beidanci.api.model.PagedResults;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Dict;
import beidanci.service.po.LearningWord;
import beidanci.service.po.MasteredWord;
import beidanci.service.po.MasteredWordId;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MasteredWordBo extends BaseBo<MasteredWord> {
    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    WordBo wordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    WordCache wordCache;

    @Autowired
    DictBo dictBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<MasteredWord>() {
        });
    }

    public List<MasteredWord> findByUser(User user) {
        MasteredWord exam = new MasteredWord();
        exam.setUser(user);
        return queryAll(exam, false);
    }

    public PagedResults<MasteredWord> getMasteredWordsForAPage2(int fromIndex, int pageSize, User user) {
        String hql = "from MasteredWord where user = :user " +
                "order by masterAtTime asc, id.wordId asc";
        PagedResults<MasteredWord> learningWords = pagedQuery2(hql, fromIndex, pageSize,
                new ImmutablePair<>("user", user));
        return learningWords;
    }

    public void setWordAsMastered(LearningWord learningWord, User user, boolean deleteLearningWord, String userId)
            throws IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException,
            IOException {
        learningWord.setLifeValue(0);
        learningWordBo.updateEntity(learningWord);

        // 添加已掌握单词
        MasteredWordId id = new MasteredWordId(user.getId(), learningWord.getId().getWordId());
        if (findById(id) == null) {
            MasteredWord masteredWord = new MasteredWord(id, user, new Date());
            createEntity(masteredWord);

            // 将用户掌握的单词数+1
            onWordMastered(userBo, user);
        }

        if (deleteLearningWord) {
            learningWordBo.deleteEntity(learningWord);
        }
    }

    private void onWordMastered(UserBo userDAO, User user)
            throws IllegalArgumentException, IllegalAccessException {
        user.setMasteredWordsCount(user.getMasteredWordsCount() + 1);
        userDAO.updateEntity(user);
    }

    /**
     * 删除已掌握单词（并移动到生词本）
     *
     * @param id
     */
    public void deleteMasterdWord(MasteredWordId id, String userId) throws IllegalAccessException, InvalidMeaningFormatException,
            EmptySpellException, IOException, ParseException {
        // 删除已掌握单词
        MasteredWord masteredWord = findById(id);
        deleteEntity(masteredWord);

        // 把已删除的已掌握单词移动到生词本
        Word word = wordBo.findById(masteredWord.getId().getWordId());
        Dict dict = dictBo.getRawWordDict(userBo.findById(id.getUserId()));
        dictWordBo.addWordToDict(word.getSpell(), dict, "delete mastered word", wordCache, wordBo, dictBo);

        // 更新用户信息
        User user = userBo.findById(userId);
        user.setMasteredWordsCount(user.getMasteredWordsCount() - 1);
        userBo.updateEntity(user);
    }

    public int getMasteredWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
        if (word == null) {
            return -1;
        }
        String hql = String.format("from MasteredWord where user.id = :userId and id.wordId = :wordId");
        MasteredWord masteredWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()));
        if (masteredWord == null) {
            return -1;
        }

        hql = "select count(0) from MasteredWord where user.id = :userId and (masterAtTime < :masterAtTime or (masterAtTime = :masterAtTime and id.wordId <= :wordId))";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("masterAtTime", masteredWord.getMasterAtTime());
        query.setParameter("wordId", word.getId());
        Long result = query.uniqueResult();
        long count = result != null ? result : 0L;

        return (int) count;
    }

    /**
     * 获取用户所有已掌握单词的DTO列表，用于全量同步
     */
    public List<MasteredWordDto> getMasteredWordDtosOfUser(String userId) {
        String sql = "select userId, wordId, masterAtTime, createTime, updateTime from mastered_word where userId = :userId order by masterAtTime, wordId";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("userId", userId);
        List<?> results = query.list();

        List<MasteredWordDto> masteredWordDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            MasteredWordDto masteredWordDto = new MasteredWordDto();
            masteredWordDto.setUserId((String) tuple[0]);
            masteredWordDto.setWordId((String) tuple[1]);
            masteredWordDto.setMasterAtTime((Date) tuple[2]);
            masteredWordDto.setCreateTime((Date) tuple[3]);
            masteredWordDto.setUpdateTime((Date) tuple[4]);
            masteredWordDtos.add(masteredWordDto);
        }
        return masteredWordDtos;
    }

    /**
     * 批量删除用户的mastered_word记录
     * @param userId 用户ID
     * @param filtersJson 过滤条件JSON字符串
     */
    public void batchDeleteUserRecords(String userId, String filtersJson) {
        try {
            // 解析过滤条件
            Map<String, Object> filters = new HashMap<>();
            if (filtersJson != null && !filtersJson.trim().isEmpty()) {
                filters = parseFilters(filtersJson);
            }
            
            // 构建删除SQL
            StringBuilder sql = new StringBuilder("DELETE FROM mastered_word WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("wordId")) {
                sql.append(" AND wordId = :wordId");
                parameters.put("wordId", filters.get("wordId"));
            }
            if (filters.containsKey("masterAtTime")) {
                sql.append(" AND masterAtTime = :masterAtTime");
                parameters.put("masterAtTime", filters.get("masterAtTime"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除mastered_word记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除mastered_word记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除mastered_word记录失败: " + e.getMessage(), e);
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
