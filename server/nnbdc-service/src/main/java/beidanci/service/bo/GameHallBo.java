package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.time.LocalDate;

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
import beidanci.service.socket.system.game.russia.HallWordSampler;
import beidanci.service.po.DictGroup;
import beidanci.service.po.GameHall;
import beidanci.service.po.Word;
import beidanci.service.util.PoVoUtils;
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

    public List<GameHall> findAllHalls() {
        return queryAll(null, false);
    }

    public GameHallVo getGameHallVoById(String id) {
        GameHall gameHall = findById(id);
        GameHallVo vo = PoVoUtils.makeVo(gameHall, GameHallVo.class,
                new String[]{"GameHallVo.hallGroup", "dictWords"});
        return vo;
    }

    @Autowired
    private DictGroupBo dictGroupBo;

    @Autowired
    private MeaningItemBo meaningItemBo;

    /**
     * 取游戏大厅今天要用的单词。
     *
     * 大厅的词来自一组词书，量可以很大，所以不是每次都把全量装进内存：
     * 每天最多用 2000 个词，厅里词数不足 2000 就全都要（抽样规则见 {@link HallWordSampler}，
     * 同一天同一个大厅结果固定，跨天换一批）。
     *
     * @param id  大厅 id
     * @param day 业务日期（自然日）
     * @return 拼写 -&gt; 单词
     */
    public Map<String/*spell*/, WordVo> getGameHallWords(String id, LocalDate day) {
        GameHall gameHall = findById(id);
        DictGroup dictGroup = gameHall.getDictGroup();
        
        // 加载 DictGroup 的 dictGroups 和 dicts 集合（递归加载所有子分组）
        dictGroupBo.loadDictGroupsAndDicts(dictGroup);
        
        List<Dict> dicts = dictGroup.getAllDicts();
        // 过滤出 2024 年及以后创建且 visible = true 的正版词书，彻底排除 2024 年前老旧词书
        List<Dict> validDicts = dicts.stream()
                .filter(d -> Boolean.TRUE.equals(d.getVisible()))
                .filter(d -> d.getCreateTime() != null && d.getCreateTime().getTime() >= 1704038400000L /* 2024-01-01 00:00:00 */)
                .collect(Collectors.toList());
        List<String> dictIds = validDicts.stream().map(d -> d.getId()).collect(Collectors.toList());
        if (dictIds.isEmpty()) {
            return new HashMap<>();
        }
        // 先只把词 id 捞出来（轻），按今天的抽样结果决定要加载哪些词，再连释义一起查
        List<String> allWordIds = namedParameterJdbcTemplate.queryForList(
                "SELECT DISTINCT dw.word_id FROM dict_word dw WHERE dw.dict_id IN (:dictIds)",
                new MapSqlParameterSource("dictIds", dictIds), String.class);
        List<String> wordIds = HallWordSampler.pickWordIds(allWordIds, day, id);
        if (wordIds.isEmpty()) {
            return new HashMap<>();
        }

        String sql = "SELECT DISTINCT w.* FROM word w " +
                "INNER JOIN dict_word dw ON dw.word_id = w.id " +
                "WHERE dw.dict_id IN (:dictIds) AND w.id IN (:wordIds)";
        MapSqlParameterSource params = new MapSqlParameterSource("dictIds", dictIds);
        params.addValue("wordIds", wordIds);
        List<Word> words = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(Word.class));

        // 批量加载这些单词的 meaningItems
        Map<String, List<MeaningItemVo>> meaningItemsByWordId = new HashMap<>();
        if (!wordIds.isEmpty()) {
            // 1. 优先查询当前大厅正版词书集合（dictIds）的专属释义项（教材审定释义）
            String hallDictMeaningSql = "SELECT id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, create_time, update_time FROM meaning_item " +
                    "WHERE word_id IN (:wordIds) AND dict_id IN (:dictIds) ORDER BY popularity ASC NULLS LAST, create_time ASC";
            MapSqlParameterSource hallMeaningParams = new MapSqlParameterSource();
            hallMeaningParams.addValue("wordIds", wordIds);
            hallMeaningParams.addValue("dictIds", dictIds);
            List<MeaningItemDto> hallMeaningItems = namedParameterJdbcTemplate.query(hallDictMeaningSql, hallMeaningParams, (rs, rowNum) -> {
                MeaningItemDto dto = new MeaningItemDto();
                dto.setId(rs.getString("id"));
                dto.setCiXing(rs.getString("ci_xing"));
                dto.setMeaning(rs.getString("meaning"));
                dto.setWordId(rs.getString("word_id"));
                dto.setDictId(rs.getString("dict_id"));
                Integer popularity = rs.getObject("popularity", Integer.class);
                dto.setPopularity(popularity != null ? popularity : 999);
                dto.setCreateTime(rs.getTimestamp("create_time"));
                dto.setUpdateTime(rs.getTimestamp("update_time"));
                dto.setOwnerId(rs.getString("owner_id"));
                return dto;
            });
            for (MeaningItemDto dto : hallMeaningItems) {
                MeaningItemVo vo = new MeaningItemVo();
                vo.setId(dto.getId());
                vo.setCiXing(dto.getCiXing());
                vo.setMeaning(dto.getMeaning());
                vo.setOwnerId(dto.getOwnerId());
                meaningItemsByWordId.computeIfAbsent(dto.getWordId(), k -> new ArrayList<>()).add(vo);
            }

            // 2. 对于大厅词书中没有专属释义的单词，从通用词典（dictId = '0'）查询
            Set<String> wordsWithHallMeaning = new HashSet<>(meaningItemsByWordId.keySet());
            List<String> pendingWordIds = wordIds.stream()
                    .filter(wordId -> !wordsWithHallMeaning.contains(wordId))
                    .collect(Collectors.toList());
            if (!pendingWordIds.isEmpty()) {
                String commonMeaningSql = "SELECT id, ci_xing, meaning, word_id, dict_id, owner_id, popularity, create_time, update_time FROM meaning_item " +
                        "WHERE word_id IN (:pendingWordIds) AND dict_id = '0' ORDER BY popularity ASC NULLS LAST, create_time ASC";
                MapSqlParameterSource commonMeaningParams = new MapSqlParameterSource("pendingWordIds", pendingWordIds);
                List<MeaningItemDto> commonMeaningItems = namedParameterJdbcTemplate.query(commonMeaningSql, commonMeaningParams, (rs, rowNum) -> {
                    MeaningItemDto dto = new MeaningItemDto();
                    dto.setId(rs.getString("id"));
                    dto.setCiXing(rs.getString("ci_xing"));
                    dto.setMeaning(rs.getString("meaning"));
                    dto.setWordId(rs.getString("word_id"));
                    dto.setDictId(rs.getString("dict_id"));
                    Integer popularity = rs.getObject("popularity", Integer.class);
                    dto.setPopularity(popularity != null ? popularity : 999);
                    dto.setCreateTime(rs.getTimestamp("create_time"));
                    dto.setUpdateTime(rs.getTimestamp("update_time"));
                    dto.setOwnerId(rs.getString("owner_id"));
                    return dto;
                });
                for (MeaningItemDto dto : commonMeaningItems) {
                    MeaningItemVo vo = new MeaningItemVo();
                    vo.setId(dto.getId());
                    vo.setCiXing(dto.getCiXing());
                    vo.setMeaning(dto.getMeaning());
                    vo.setOwnerId(dto.getOwnerId());
                    meaningItemsByWordId.computeIfAbsent(dto.getWordId(), k -> new ArrayList<>()).add(vo);
                }
            }

            // 3. 对于仍未命中通用释义的单词，从任意词典中取一条作为兜底
            Set<String> wordsWithMeaning = new HashSet<>(meaningItemsByWordId.keySet());
            List<String> wordsWithoutMeaning = wordIds.stream()
                    .filter(wordId -> !wordsWithMeaning.contains(wordId))
                    .collect(Collectors.toList());
            if (!wordsWithoutMeaning.isEmpty()) {
                List<MeaningItemDto> fallbackMeaningItems = meaningItemBo.getOneMeaningPerWordFromAnyDict(wordsWithoutMeaning);
                for (MeaningItemDto dto : fallbackMeaningItems) {
                    MeaningItemVo vo = new MeaningItemVo();
                    vo.setId(dto.getId());
                    vo.setCiXing(dto.getCiXing());
                    vo.setMeaning(dto.getMeaning());
                    vo.setOwnerId(dto.getOwnerId());
                    meaningItemsByWordId.computeIfAbsent(dto.getWordId(), k -> new ArrayList<>()).add(vo);
                }
            }
        }

        Map<String, WordVo> wordsBySpell = new HashMap<>();
        for (Word word : words) {
            WordVo wordVo = PoVoUtils.makeVo(word, WordVo.class,
                    new String[]{"WordVo.^id,spell,meaningItems", "MeaningItemVo.^ciXing,meaning,dict", "DictVo.^id"});
            
            // 设置 meaningItems
            List<MeaningItemVo> meaningItems = meaningItemsByWordId.getOrDefault(word.getId(), new ArrayList<>());
            wordVo.setMeaningItems(meaningItems);
            
            WordVo wordVo2 = new WordVo();
            org.springframework.beans.BeanUtils.copyProperties(Objects.requireNonNull(wordVo), wordVo2);
            wordVo2 = Util.shrinkWordVo(wordVo2, validDicts, 1, true);
            wordsBySpell.put(wordVo2.getSpell(), wordVo2);
        }
        return wordsBySpell;
    }
}
