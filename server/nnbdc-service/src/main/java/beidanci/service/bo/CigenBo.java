package beidanci.service.bo;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.CigenWordLink;

@Service
@Transactional(rollbackFor = Throwable.class)
public class CigenBo extends BaseBo<CigenWordLink> {

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Autowired
    private SysDbSyncBo sysDbSyncBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<CigenWordLink>() {
        });
    }

    /**
     * 获取所有带有解析的词根单词关系
     */
    public List<CigenWordLinkDto> getAllCigenWordLinks() {
        String sql = "SELECT cl.cigen_id, cl.word_id, cl.the_explain, w.spell, c.description as cigen_description " +
                     "FROM cigen_word_link cl " +
                     "JOIN word w ON cl.word_id = w.id " +
                     "JOIN cigen c ON cl.cigen_id = c.id";
        
        return namedParameterJdbcTemplate.query(sql, (rs, rowNum) -> {
            CigenWordLinkDto dto = new CigenWordLinkDto();
            dto.setCigenId(rs.getString("cigen_id"));
            dto.setWordId(rs.getString("word_id"));
            dto.setTheExplain(rs.getString("the_explain"));
            dto.setSpell(rs.getString("spell"));
            dto.setCigenDescription(rs.getString("cigen_description"));
            return dto;
        });
    }

    /**
     * 更新词根解析
     */
    public void updateExplain(String cigenId, String wordId, String newExplain) {
        Timestamp now = new Timestamp(System.currentTimeMillis());
        String sql = "UPDATE cigen_word_link SET the_explain = :newExplain, update_time = :updateTime " +
                     "WHERE cigen_id = :cigenId AND word_id = :wordId";
        MapSqlParameterSource params = new MapSqlParameterSource()
            .addValue("newExplain", newExplain)
            .addValue("updateTime", now)
            .addValue("cigenId", cigenId)
            .addValue("wordId", wordId);
        namedParameterJdbcTemplate.update(sql, params);

        // 获取更新后的记录，用于同步日志（确保包含 create_time 等所有必需字段）
        String selectSql = "SELECT * FROM cigen_word_link WHERE cigen_id = :cigenId AND word_id = :wordId";
        Map<String, Object> record = namedParameterJdbcTemplate.queryForMap(selectSql, params);
        
        // 转换日期格式为 ISO-8601 (与 Flutter 兼容)
        java.text.SimpleDateFormat isoFormat = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        isoFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        
        Map<String, Object> logRecord = new java.util.HashMap<>();
        logRecord.put("cigenId", record.get("cigen_id"));
        logRecord.put("wordId", record.get("word_id"));
        logRecord.put("theExplain", record.get("the_explain"));
        logRecord.put("createTime", isoFormat.format(record.get("create_time")));
        logRecord.put("updateTime", isoFormat.format(record.get("update_time")));

        sysDbSyncBo.logOperation("UPDATE", "cigen_word_link", cigenId + "_" + wordId, beidanci.service.util.JsonUtils.toJson(logRecord));
    }

    public static class CigenWordLinkDto {
        private String cigenId;
        private String wordId;
        private String theExplain;
        private String spell;
        private String cigenDescription;

        public String getCigenId() { return cigenId; }
        public void setCigenId(String cigenId) { this.cigenId = cigenId; }
        public String getWordId() { return wordId; }
        public void setWordId(String wordId) { this.wordId = wordId; }
        public String getTheExplain() { return theExplain; }
        public void setTheExplain(String theExplain) { this.theExplain = theExplain; }
        public String getSpell() { return spell; }
        public void setSpell(String spell) { this.spell = spell; }
        public String getCigenDescription() { return cigenDescription; }
        public void setCigenDescription(String cigenDescription) { this.cigenDescription = cigenDescription; }
    }
}
