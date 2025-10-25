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

import beidanci.api.model.WordVo;
import beidanci.api.model.WrongWordDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.WrongWord;
import beidanci.service.store.WordCache;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WrongWordBo extends BaseBo<WrongWord> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<WrongWord>() {
        });
    }

    @Autowired
    WordCache wordCache;

    public int getWrongWordOrder(String userId, String spell) throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[]{
                "SynonymVo.meaningItem", "SynonymVo.word",  "similarWords", "DictVo.dictWords"});
        if (word == null) {
            return -1;
        }

        String hql = String.format("from WrongWord where user.id = :userId and id.wordId = :wordId");
        WrongWord wrongWord = queryUnique(hql,
                new ImmutablePair<>("userId", userId),
                new ImmutablePair<>("wordId", word.getId()));
        if (wrongWord == null) {
            return -1;
        }

        hql = "select count(0) from WrongWord where user.id = :userId " +
                "and createTime<=:createTime";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("userId", userId);
        query.setParameter("createTime", wrongWord.getCreateTime());
        long count = query.uniqueResult();
        return (int) count;
    }

    /**
     * 幂等创建：若已存在则忽略
     */
    public void createIfAbsent(WrongWord wrongWord) throws IllegalAccessException {
        String hql = "from WrongWord where id.userId = :userId and id.wordId = :wordId";
        WrongWord existing = queryUnique(hql,
                new ImmutablePair<>("userId", wrongWord.getId().getUserId()),
                new ImmutablePair<>("wordId", wrongWord.getId().getWordId()));
        if (existing == null) {
            createEntity(wrongWord);
        }
    }

    /**
     * 获取用户所有错词的DTO列表，用于全量同步
     */
    public List<WrongWordDto> getWrongWordDtosOfUser(String userId) {
        String sql = "select userId, wordId, createTime, updateTime from user_wrong_word where userId = :userId order by createTime";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> list = query.setParameter("userId", userId).list();

        List<WrongWordDto> dtos = new ArrayList<>();
        for (Object obj : list) {
            Object[] values = (Object[]) obj;
            WrongWordDto dto = new WrongWordDto();
            dto.setUserId((String) values[0]);
            dto.setWordId((String) values[1]);
            dto.setCreateTime((Date) values[2]);
            dto.setUpdateTime((Date) values[3]);
            dtos.add(dto);
        }

        return dtos;
    }

    /**
     * 批量删除用户的user_wrong_word记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM user_wrong_word WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("wordId")) {
                sql.append(" AND wordId = :wordId");
                parameters.put("wordId", filters.get("wordId"));
            }
            if (filters.containsKey("createTime")) {
                sql.append(" AND createTime = :createTime");
                parameters.put("createTime", filters.get("createTime"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除user_wrong_word记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除user_wrong_word记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除user_wrong_word记录失败: " + e.getMessage(), e);
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
