package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.GameHallVo;
import beidanci.api.model.MeaningItemDto;
import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.WordVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.Dict;
import beidanci.service.po.DictGroup;
import beidanci.service.po.GameHall;
import beidanci.service.po.Word;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class GameHallBo extends BaseBo<GameHall> {

        @PostConstruct
    public void init() {
        setDao(new BaseDao<GameHall>() {
        });
    }

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    public GameHallVo getGameHallVoById(String id) {
        GameHall gameHall = findById(id);
        GameHallVo vo = BeanUtils.makeVo(gameHall, GameHallVo.class,
                new String[]{"GameHallVo.hallGroup", "dictWords"});
        return vo;
    }

    @Autowired
    private DictGroupBo dictGroupBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    /**
     * 获游戏大厅所包含的单词书中的所有单词
     *
     * @param id
     * @return
     */
    public Map<String/*spell*/, WordVo> getGameHallWords(String id) {
        GameHall gameHall = findById(id);
        DictGroup dictGroup = gameHall.getDictGroup();
        
        // 加载 DictGroup 的 dictGroups 和 dicts 集合（递归加载所有子分组）
        dictGroupBo.loadDictGroupsAndDicts(dictGroup);
        
        List<Dict> dicts = dictGroup.getAllDicts();
        List<String> dictIds = dicts.stream().map(d -> d.getId()).collect(Collectors.toList());
        String sql = "SELECT DISTINCT w.* FROM word w " +
                "INNER JOIN dict_word dw ON dw.wordId = w.id " +
                "WHERE dw.dictId IN (:dictIds)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictIds", dictIds);
        List<Word> words = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Word.class));

        // 批量加载所有单词的 meaningItems
        List<String> wordIds = words.stream().map(Word::getId).collect(Collectors.toList());
        Map<String, List<MeaningItemVo>> meaningItemsByWordId = new HashMap<>();
        if (!wordIds.isEmpty()) {
            // 优先查询通用词典的释义项（dictId = '0'）
            String meaningSql = "SELECT id, ciXing, meaning, wordId, dictId, popularity, createTime, updateTime FROM meaning_item " +
                    "WHERE wordId IN (:wordIds) AND dictId = '0' ORDER BY popularity ASC";
            MapSqlParameterSource meaningParams = new MapSqlParameterSource("wordIds", wordIds);
            List<MeaningItemDto> commonMeaningItems = namedParameterJdbcTemplate.query(meaningSql, meaningParams, (rs, rowNum) -> {
                MeaningItemDto dto = new MeaningItemDto();
                dto.setId(rs.getString("id"));
                dto.setCiXing(rs.getString("ciXing"));
                dto.setMeaning(rs.getString("meaning"));
                dto.setWordId(rs.getString("wordId"));
                dto.setDictId(rs.getString("dictId"));
                Integer popularity = rs.getObject("popularity", Integer.class);
                dto.setPopularity(popularity != null ? popularity : 999);
                dto.setCreateTime(rs.getTimestamp("createTime"));
                dto.setUpdateTime(rs.getTimestamp("updateTime"));
                return dto;
            });
            
            // 转换为 MeaningItemVo 并按 wordId 分组
            for (MeaningItemDto dto : commonMeaningItems) {
                MeaningItemVo vo = new MeaningItemVo();
                vo.setId(dto.getId());
                vo.setCiXing(dto.getCiXing());
                vo.setMeaning(dto.getMeaning());
                meaningItemsByWordId.computeIfAbsent(dto.getWordId(), k -> new ArrayList<>()).add(vo);
            }
            
            // 对于没有通用释义的单词，从任意词典中取一条作为兜底
            Set<String> wordsWithCommonMeaning = new HashSet<>(meaningItemsByWordId.keySet());
            List<String> wordsWithoutCommonMeaning = wordIds.stream()
                    .filter(wordId -> !wordsWithCommonMeaning.contains(wordId))
                    .collect(Collectors.toList());
            if (!wordsWithoutCommonMeaning.isEmpty()) {
                List<MeaningItemDto> fallbackMeaningItems = meaningItemBo.getOneMeaningPerWordFromAnyDict(wordsWithoutCommonMeaning);
                for (MeaningItemDto dto : fallbackMeaningItems) {
                    MeaningItemVo vo = new MeaningItemVo();
                    vo.setId(dto.getId());
                    vo.setCiXing(dto.getCiXing());
                    vo.setMeaning(dto.getMeaning());
                    meaningItemsByWordId.computeIfAbsent(dto.getWordId(), k -> new ArrayList<>()).add(vo);
                }
            }
        }

        Map<String, WordVo> wordsBySpell = new HashMap<>();
        for (Word word : words) {
            WordVo wordVo = BeanUtils.makeVo(word, WordVo.class,
                    new String[]{"WordVo.^id,spell,meaningItems", "MeaningItemVo.^ciXing,meaning,dict", "DictVo.^id"});
            
            // 设置 meaningItems
            List<MeaningItemVo> meaningItems = meaningItemsByWordId.getOrDefault(word.getId(), new ArrayList<>());
            wordVo.setMeaningItems(meaningItems);
            
            WordVo wordVo2 = new WordVo();
            org.springframework.beans.BeanUtils.copyProperties(Objects.requireNonNull(wordVo), wordVo2);
            wordVo2 = Util.shrinkWordVo(wordVo2, dicts, 1, true);
            wordsBySpell.put(wordVo2.getSpell(), wordVo2);
        }
        return wordsBySpell;
    }
}
