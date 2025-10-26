package beidanci.service.bo;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.PostConstruct;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.MeaningItemDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.MeaningItem;

@Service
@Transactional(rollbackFor = Throwable.class)
public class MeaningItemBo extends BaseBo<MeaningItem> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<MeaningItem>() {
        });
    }

    /** 获取指定词书的所有单词释义项，通用词典ID为'0' */
    public List<MeaningItemDto> getMeaningItemsOfDict(String dictId) {
        // 通用词典现在是数据库中的实际记录，统一查询
        String sql = "select id, ciXing, meaning, wordId, dictId, popularity, createTime, updateTime from meaning_item where dictId = :dictId";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.setParameter("dictId", dictId).list();

        List<MeaningItemDto> meaningItemDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            MeaningItemDto meaningItemDto = new MeaningItemDto();
            meaningItemDto.setId((String) tuple[0]);
            meaningItemDto.setCiXing((String) tuple[1]);
            meaningItemDto.setMeaning((String) tuple[2]);
            meaningItemDto.setWordId((String) tuple[3]);
            meaningItemDto.setDictId((String) tuple[4]);
            // 处理 popularity 可能为 NULL 的情况，默认值为 999
            meaningItemDto.setPopularity(tuple[5] != null ? (Integer) tuple[5] : 999);
            meaningItemDto.setCreateTime((Timestamp) tuple[6]);
            meaningItemDto.setUpdateTime((Timestamp) tuple[7]);
            meaningItemDtos.add(meaningItemDto);
        }
        return meaningItemDtos;
    }

    /**
     * 为给定的 wordId 集合，从任意词典中各取一条释义作为兜底（仅当该词在通用词典中无释义时使用）。
     */
    public List<MeaningItemDto> getOneMeaningPerWordFromAnyDict(List<String> wordIds) {
        if (wordIds == null || wordIds.isEmpty()) {
            return new ArrayList<>();
        }

        // 使用原生SQL一次性取回所有候选，再在内存中按 word 聚合取第一条
        String sql = "select id, ciXing, meaning, wordId, dictId, popularity, createTime, updateTime from meaning_item " +
                     "where dictId is not null and wordId in (:ids) order by updateTime desc";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameterList("ids", wordIds);
        List<?> results = query.list();

        List<MeaningItemDto> picked = new ArrayList<>();
        java.util.HashSet<String> seen = new java.util.HashSet<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            String wordId = (String) tuple[3];
            if (seen.contains(wordId)) {
                continue;
            }
            MeaningItemDto dto = new MeaningItemDto();
            dto.setId((String) tuple[0]);
            dto.setCiXing((String) tuple[1]);
            dto.setMeaning((String) tuple[2]);
            dto.setWordId(wordId);
            dto.setDictId((String) tuple[4]);
            // 处理 popularity 可能为 NULL 的情况，默认值为 999
            dto.setPopularity(tuple[5] != null ? (Integer) tuple[5] : 999);
            dto.setCreateTime((Timestamp) tuple[6]);
            dto.setUpdateTime((Timestamp) tuple[7]);
            picked.add(dto);
            seen.add(wordId);
            if (seen.size() == wordIds.size()) {
                break;
            }
        }
        return picked;
    }

    /**
     * 在数据库中为缺失通用释义（dictId = '0'）的单词，补充一条通用释义。
     * 逻辑：从任意词典的释义中拷贝一条，写入为通用释义（dictId='0'）。
     * 仅补充缺失项（NOT EXISTS 保证幂等）。
     * 返回插入的行数。
     */
    public int supplementCommonMeanings() {
        String sql =
                "INSERT INTO meaning_item (id, ciXing, meaning, wordId, dictId, popularity, createTime, updateTime) " +
                "SELECT REPLACE(UUID(),'-',''), mi.ciXing, mi.meaning, mi.wordId, '0', mi.popularity, NOW(6), NOW(6) " +
                "FROM meaning_item mi " +
                "LEFT JOIN meaning_item cm ON cm.wordId = mi.wordId AND cm.dictId = '0' " +
                "WHERE mi.dictId != '0' AND cm.id IS NULL";
        Query<?> query = getSession().createNativeQuery(sql);
        return query.executeUpdate();
    }

    // ============================================
    // 系统健康检查相关方法
    // ============================================

    /**
     * 查找缺少释义项的单词
     */
    public List<String> findWordsWithoutMeanings(String dictId) {
        String sql = """
            SELECT dw.wordId
            FROM dict_word dw
            WHERE dw.dictId = :dictId
            AND dw.wordId NOT IN (
                SELECT mi.wordId
                FROM meaning_item mi
                WHERE mi.dictId = :dictId
            )
            """;
        Query<String> query = getSession().createNativeQuery(sql, String.class);
        query.setParameter("dictId", dictId);
        return query.list();
    }
}
