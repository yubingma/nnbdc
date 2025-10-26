package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.LearningDictDto;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.LearningDict;
import beidanci.service.po.User;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LearningDictBo extends BaseBo<LearningDict> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<LearningDict>() {
        });
    }

    public List<LearningDict> getLearningDictsOfUser(User user) {
        String hql = "from LearningDict where user=:user order by createTime asc";
        Query<LearningDict> query = getSession().createQuery(hql, LearningDict.class);
        query.setParameter("user", user);
        return query.getResultList();
    }

    public LearningDict getLearningDictOfUser(User user, String dictName) {
        String hql = "from LearningDict where user=:user and dict.name=:dictName";
        Query<LearningDict> query = getSession().createQuery(hql, LearningDict.class);
        query.setParameter("user", user);
        query.setParameter("dictName", dictName);
        return query.getSingleResult();
    }

    public boolean needSelectDictBeforeStudy(User user) {
        List<LearningDict> learningDicts = getLearningDictsOfUser(user);
        boolean allDictsFinished = Util.isAllDictsFinished(learningDicts);
        return allDictsFinished;
    }

    /**
     * 判断指定单词是否在用户选择的单词书中
     *
     * @param user
     * @return
     */
    public boolean isWordInMySelectedDicts(WordVo word, User user) {
        // 判断单词是否在用户选择的词书中
        Session session = getSession();
        String baseHql = "from DictWord dw where dw.id.wordId=:wordId and dw.dict.id in (select dict.id from LearningDict where user=:user)";
        String hql = "select count(0) " + baseHql;
        Query<Long> query2 = session.createQuery(hql, Long.class);
        query2.setParameter("user", user);
        query2.setParameter("wordId", word.getId());
        long total = query2.uniqueResult();
        return total > 0;
    }

    /**
     * 更新指定用户的所有单词书的当前已取词位置
     *
     * @Param ignoreCurrent 是否忽略当前取词位置，true：从头计算取词位置 false: 从当前取词位置开始计算新的取词位置
     */
    public void updateCurrentPositionForUserDicts(User user, boolean ignoreCurrent) {
        getSession().flush(); // 调用存储过程前，先把数据flush到db，否则存储过程看不到这些数据
        String sql = "update learning_dict set currentWordSeq = currPosOfLearningDict(userId, dictId, :ignoreCurrent) where userId = :userId";
        Query<Integer> query = getSession().createNativeQuery(sql, Integer.class);
        query.setParameter("userId", user.getId());
        query.setParameter("ignoreCurrent", ignoreCurrent ? 1 : 0);
        query.executeUpdate();
    }

    /**
     * 更新指定用户单词书的当前已取词位置
     *
     * @Param ignoreCurrent 是否忽略当前取词位置，true：从头计算取词位置 false: 从当前取词位置开始计算新的取词位置
     */
    public void updateCurrentPositionForUserDict(User user, String dictId, boolean ignoreCurrent) {
        getSession().flush(); // 调用存储过程前，先把数据flush到db，否则存储过程看不到这些数据
        String sql = "update learning_dict set currentWordSeq = currPosOfLearningDict(userId, dictId, :ignoreCurrent) where userId = :userId and dictId = :dictId";
        Query<Integer> query = getSession().createNativeQuery(sql, Integer.class);
        query.setParameter("userId", user.getId());
        query.setParameter("dictId", dictId);
        query.setParameter("ignoreCurrent", ignoreCurrent ? 1 : 0);
        query.executeUpdate();
    }

    @SuppressWarnings("unchecked")
    public List<LearningDictDto> getLearningDictDtosOfUser(String userId) {
        String sql = "select userId, dictId, currentWordSeq, isPrivileged, currentWordId, fetchMastered, createTime, updateTime from learning_dict where userId = :userId";
        Query<Object[]> query = getSession().createNativeQuery(sql);
        List<Object[]> list = query.setParameter("userId", userId).list();

        List<LearningDictDto> dtos = new ArrayList<>();
        for (Object[] values : list) {
            LearningDictDto dto = new LearningDictDto();
            dto.setUserId((String) values[0]);
            dto.setDictId((String) values[1]);
            dto.setCurrentWordSeq((Integer) values[2]);
            dto.setIsPrivileged((Boolean) values[3]);
            dto.setCurrentWord((String) values[4]);
            dto.setFetchMastered((Boolean) values[5]);
            dto.setCreateTime((Date) values[6]);
            dto.setUpdateTime((Date) values[7]);
            dtos.add(dto);
        }
        return dtos;
    }

    /**
     * 批量删除用户的学习词典记录
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
            StringBuilder sql = new StringBuilder("DELETE FROM learning_dict WHERE userId = :userId");
            Map<String, Object> parameters = new HashMap<>();
            parameters.put("userId", userId);
            
            // 添加过滤条件
            if (filters.containsKey("dictId")) {
                sql.append(" AND dictId = :dictId");
                parameters.put("dictId", filters.get("dictId"));
            }
            if (filters.containsKey("isPrivileged")) {
                sql.append(" AND isPrivileged = :isPrivileged");
                parameters.put("isPrivileged", filters.get("isPrivileged"));
            }
            
            Query<?> query = getSession().createNativeQuery(sql.toString());
            for (Map.Entry<String, Object> entry : parameters.entrySet()) {
                query.setParameter(entry.getKey(), entry.getValue());
            }
            
            int deletedCount = query.executeUpdate();
            System.out.println("批量删除学习词典记录完成，用户ID: " + userId + ", 删除数量: " + deletedCount);
            
        } catch (Exception e) {
            System.err.println("批量删除学习词典记录失败，用户ID: " + userId + ", 错误: " + e.getMessage());
            throw new RuntimeException("批量删除学习词典记录失败: " + e.getMessage(), e);
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

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 查找学习进度异常的记录
     */
    public List<Object[]> findInvalidLearningProgress() {
        String sql = """
            SELECT ld.userId, ld.dictId, ld.currentWordSeq, d.wordCount
            FROM learning_dict ld
            JOIN dict d ON ld.dictId = d.id
            WHERE ld.currentWordSeq > d.wordCount
            ORDER BY ld.userId, ld.dictId
            """;
        Query<Object[]> query = getSession().createNativeQuery(sql, Object[].class);
        return query.list();
    }

    /**
     * 修复学习进度
     */
    public void fixLearningProgress(String userId, String dictId, Integer correctSeq) {
        String sql = """
            UPDATE learning_dict
            SET currentWordSeq = :correctSeq
            WHERE userId = :userId AND dictId = :dictId
            """;
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("correctSeq", correctSeq);
        query.setParameter("userId", userId);
        query.setParameter("dictId", dictId);
        query.executeUpdate();
    }
}
