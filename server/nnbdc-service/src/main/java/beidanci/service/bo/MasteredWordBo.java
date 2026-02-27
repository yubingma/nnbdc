package beidanci.service.bo;

import java.io.IOException;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.PagedResults;
import beidanci.api.model.WordVo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;

/**
 * 已掌握单词业务逻辑层
 * 
 * 重构后，已掌握单词不再使用独立的 mastered_word 表，
 * 而是作为一本用户词书（name='已掌握'）存储在 dict + dict_word 体系中。
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class MasteredWordBo {
    private static final Logger logger = LoggerFactory.getLogger(MasteredWordBo.class);

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

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    /**
     * 获取用户的"已掌握"词书，如果不存在则自动创建
     */
    private Dict getMasteredWordDict(User user) {
        Dict dict = dictBo.getMasteredWordDict(user);
        if (dict == null) {
            dict = dictBo.createMasteredWordDictForUser(user);
        }
        return dict;
    }

    /**
     * 获取用户的"已掌握"词书（通过userId），如果不存在则自动创建
     */
    private Dict getMasteredWordDictByUserId(String userId) {
        Dict dict = dictBo.getMasteredWordDictByUserId(userId);
        if (dict == null) {
            User user = userBo.findById(userId);
            if (user != null) {
                dict = dictBo.createMasteredWordDictForUser(user);
            }
        }
        return dict;
    }

    /**
     * 检查单词是否已被用户掌握（在"已掌握"词书中）
     */
    public boolean isWordMastered(String userId, String wordId) {
        Dict dict = getMasteredWordDictByUserId(userId);
        if (dict == null) return false;
        
        String sql = "SELECT COUNT(*) FROM dict_word WHERE dict_id = :dictId AND word_id = :wordId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", dict.getId());
        params.addValue("wordId", wordId);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count != null && count > 0;
    }

    /**
     * 分页获取已掌握单词（现在从"已掌握"词书中的dict_word获取）
     */
    public PagedResults<DictWord> getMasteredWordsForAPage2(int fromIndex, int pageSize, User user) {
        Dict dict = getMasteredWordDict(user);
        String sql = "SELECT * FROM dict_word WHERE dict_id = :dictId ORDER BY seq ASC";
        
        // 获取总数
        String countSql = "SELECT COUNT(*) FROM dict_word WHERE dict_id = :dictId";
        MapSqlParameterSource params = new MapSqlParameterSource("dictId", dict.getId());
        Long total = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
        
        // 获取分页数据
        String pagedSql = sql + " LIMIT :pageSize OFFSET :fromIndex";
        params.addValue("pageSize", pageSize);
        params.addValue("fromIndex", fromIndex);
        
        List<DictWord> dictWords = namedParameterJdbcTemplate.query(pagedSql, params, (rs, rowNum) -> {
            DictWord dw = new DictWord();
            dw.setDict(dictBo.findById(rs.getString("dict_id")));
            dw.setWord(wordBo.findById(rs.getString("word_id")));
            dw.setSeq(rs.getInt("seq"));
            dw.setCreateTime(rs.getTimestamp("create_time"));
            dw.setUpdateTime(rs.getTimestamp("update_time"));
            return dw;
        });
        
        PagedResults<DictWord> results = new PagedResults<>();
        results.setTotal(total != null ? total.intValue() : 0);
        results.setRows(dictWords);
        return results;
    }



    /**
     * 删除已掌握单词（从"已掌握"词书中移除，并移动到生词本）
     */
    public void deleteMasteredWord(String userId, String wordId) throws IllegalAccessException, InvalidMeaningFormatException,
            EmptySpellException, IOException, ParseException {
        Dict masteredDict = getMasteredWordDictByUserId(userId);
        if (masteredDict == null) {
            logger.warn("用户没有已掌握词书: userId={}", userId);
            return;
        }

        // 使用 dictWordBo.removeWordFromDict 来处理删除（包括seq重排和word_count更新）
        dictWordBo.removeWordFromDict(masteredDict.getId(), wordId, userId);

        // 把已删除的已掌握单词移动到生词本
        Word word = wordBo.findById(wordId);
        User user = userBo.findById(userId);
        Dict rawDict = dictBo.getRawWordDict(user);
        dictWordBo.addWordToDict(word.getSpell(), rawDict, "delete mastered word", wordCache, wordBo, dictBo);

        // 更新用户信息
        user.setMasteredWordsCount(Math.max(0, user.getMasteredWordsCount() - 1));
        userBo.updateEntity(user);
    }

    /**
     * 获取已掌握单词在列表中的位置
     */
    public int getMasteredWordOrder(String userId, String spell)
            throws InvalidMeaningFormatException, EmptySpellException, IOException, ParseException {
        WordVo word = wordCache.getWordBySpell(spell, new String[] {
                "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" });
        if (word == null) {
            return -1;
        }

        Dict masteredDict = getMasteredWordDictByUserId(userId);
        if (masteredDict == null) {
            return -1;
        }

        // 检查该单词是否在已掌握词书中
        String checkSql = "SELECT seq FROM dict_word WHERE dict_id = :dictId AND word_id = :wordId";
        MapSqlParameterSource checkParams = new MapSqlParameterSource();
        checkParams.addValue("dictId", masteredDict.getId());
        checkParams.addValue("wordId", word.getId());
        List<Integer> seqs = namedParameterJdbcTemplate.queryForList(checkSql, checkParams, Integer.class);
        if (seqs.isEmpty()) {
            return -1;
        }

        int seq = seqs.get(0);
        // 计算位置：统计 seq <= 当前单词 seq 的记录数
        String countSql = "SELECT COUNT(*) FROM dict_word WHERE dict_id = :dictId AND seq <= :seq";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("dictId", masteredDict.getId());
        params.addValue("seq", seq);
        Long result = namedParameterJdbcTemplate.queryForObject(countSql, params, Long.class);
        long count = result != null ? result : 0L;

        return (int) count;
    }
}
