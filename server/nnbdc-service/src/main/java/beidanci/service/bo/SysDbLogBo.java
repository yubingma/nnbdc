package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.SysDbLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.SysDbLog;
import beidanci.service.po.SysDbVersion;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.Util;

/**
 * 系统数据日志业务类
 * 用于记录和查询UGC内容的变更日志
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class SysDbLogBo extends BaseBo<SysDbLog> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<SysDbLog>() {
        });
    }

    /**
     * 记录系统数据操作日志
     * 
     * @param operate  操作类型：INSERT/UPDATE/DELETE
     * @param table    表名：word_image/sentence/word_shortdesc_chinese
     * @param recordId 记录ID
     * @param record   记录内容（JSON格式）
     */
    public void logOperation(String operate, String table, String recordId, String record) {
        // 在同一事务中完成：1）记录日志 2）递增版本号
        int currentVersion = getSysDbVersion();
        int nextVersion = currentVersion + 1;

        // 创建日志
        SysDbLog log = new SysDbLog();
        log.setId(Util.uuid());
        log.setVersion(nextVersion);
        log.setOperate(operate);
        log.setTable(table);
        log.setRecordId(recordId);
        log.setRecord(record);
        log.setCreateTime(new Date());

        createEntity(log);

        // 递增版本号
        incrementSysDbVersion(nextVersion);
    }

    /**
     * 获取当前全局版本号
     * 
     * @return 当前版本号，若不存在则返回0
     */
    public int getSysDbVersion() {
        String sql = "SELECT * FROM sys_db_version WHERE id = 'singleton'";
        List<SysDbVersion> versions = namedParameterJdbcTemplate.query(sql,
                new EntityRowMapper<>(SysDbVersion.class));
        return versions.isEmpty() ? 0 : versions.get(0).getVersion();
    }

    /**
     * 递增全局版本号
     * 
     * @param newVersion 新版本号
     */
    private void incrementSysDbVersion(int newVersion) {
        String sql = "SELECT * FROM sys_db_version WHERE id = 'singleton'";
        List<SysDbVersion> versions = namedParameterJdbcTemplate.query(sql,
                new EntityRowMapper<>(SysDbVersion.class));

        if (versions.isEmpty()) {
            // 首次创建版本记录
            String insertSql = "INSERT INTO sys_db_version (id, version, create_time) VALUES ('singleton', :version, :createTime)";
            MapSqlParameterSource params = new MapSqlParameterSource();
            params.addValue("version", newVersion);
            params.addValue("createTime", new Date());
            namedParameterJdbcTemplate.update(insertSql, params);
        } else {
            // 更新版本号
            String updateSql = "UPDATE sys_db_version SET version = :version, update_time = :updateTime WHERE id = 'singleton'";
            MapSqlParameterSource params = new MapSqlParameterSource();
            params.addValue("version", newVersion);
            params.addValue("updateTime", new Date());
            namedParameterJdbcTemplate.update(updateSql, params);
        }
    }

    /**
     * 获取增量日志（支持全量生成）
     * 
     * 判断逻辑（按优先级）：
     * 1. 首次同步（fromVersion=0）：全量同步
     * 2. 找不到对应版本的日志：全量同步（日志可能已被清理）
     * 3. 日志时间过旧（超过30天）：全量同步（避免使用可能已清理的日志）
     * 4. 增量日志数量过大（超过1000条）：全量同步（性能考虑）
     * 5. 其他情况：增量同步
     * 
     * @param fromVersion 起始版本号（不包含）
     * @return 增量日志列表，按版本号升序排列
     */
    public List<SysDbLogDto> getNewSysDbLogs(int fromVersion) {
        int currentVersion = getSysDbVersion();

        // 1. 首次同步
        if (fromVersion == 0) {
            return generateFullSysDbLogs(currentVersion);
        }

        // 2. 检查是否存在对应版本的日志
        if (!hasVersionLogs(fromVersion)) {
            return generateFullSysDbLogs(currentVersion);
        }

        // 3. 检查 fromVersion 对应的日志时间是否过旧（超过30天，可能已被清理）
        // 获取 fromVersion + 1 的第一条日志的创建时间
        Date firstLogTime = getFirstLogTimeAfterVersion(fromVersion);
        if (firstLogTime != null) {
            Date thirtyDaysAgo = new Date(System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000);
            if (firstLogTime.before(thirtyDaysAgo)) {
                // 日志时间超过30天，可能已被清理，使用全量同步
                return generateFullSysDbLogs(currentVersion);
            }
        }

        // 4. 检查增量日志数量（如果数量过大，全量同步可能更快）
        long incrementalLogCount = getIncrementalLogCount(fromVersion);
        if (incrementalLogCount > 1000) {
            // 增量日志数量超过1000条，使用全量同步
            return generateFullSysDbLogs(currentVersion);
        }

        // 5. 增量同步
        String sql = "SELECT * FROM sys_db_log WHERE version > :fromVersion ORDER BY version ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("fromVersion", fromVersion);
        List<SysDbLog> logs = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(SysDbLog.class));
        return logs.stream().map(this::toDto).collect(Collectors.toList());
    }

    /**
     * 检查是否存在指定版本的日志
     */
    private boolean hasVersionLogs(int fromVersion) {
        String sql = "SELECT COUNT(*) FROM sys_db_log WHERE version > :fromVersion";
        MapSqlParameterSource params = new MapSqlParameterSource("fromVersion", fromVersion);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count != null && count > 0;
    }

    /**
     * 获取 fromVersion 之后第一条日志的创建时间
     * 用于判断日志是否过旧，可能已被清理
     * 
     * @param fromVersion 起始版本号（不包含）
     * @return 第一条日志的创建时间，如果不存在则返回 null
     */
    private Date getFirstLogTimeAfterVersion(int fromVersion) {
        String sql = "SELECT create_time FROM sys_db_log WHERE version > :fromVersion ORDER BY version ASC LIMIT 1";
        MapSqlParameterSource params = new MapSqlParameterSource("fromVersion", fromVersion);
        try {
            Date createTime = namedParameterJdbcTemplate.queryForObject(sql, params, Date.class);
            return createTime;
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            return null;
        }
    }

    /**
     * 获取增量日志数量
     * 
     * @param fromVersion 起始版本号（不包含）
     * @return 增量日志数量
     */
    private long getIncrementalLogCount(int fromVersion) {
        String sql = "SELECT COUNT(*) FROM sys_db_log WHERE version > :fromVersion";
        MapSqlParameterSource params = new MapSqlParameterSource("fromVersion", fromVersion);
        Long count = namedParameterJdbcTemplate.queryForObject(sql, params, Long.class);
        return count != null ? count : 0L;
    }

    /**
     * 生成系统数据全量日志（动态生成）
     * 用于首次同步或版本差距过大时
     */
    private List<SysDbLogDto> generateFullSysDbLogs(int currentVersion) {
        List<SysDbLogDto> logs = new ArrayList<>();

        // === 静态元数据 ===
        // 1. Levels - 已移除，由前端LevelUtil处理

        // 2. DictGroups
        logs.addAll(generateDictGroupLogs(currentVersion));

        // 3. GroupAndDictLinks
        logs.addAll(generateGroupAndDictLinkLogs(currentVersion));

        // 4. Dicts（只包含系统词典）
        logs.addAll(generateDictLogs(currentVersion));

        // sentence/word_image/word_shortdesc_chinese的数据, 不需要全量同步, 因为数据量太大,
        // 而且用户下载所需词书的时候, 已经包含所需的这些数据了

        return logs;
    }

    private List<SysDbLogDto> generateDictGroupLogs(int version) {
        String sql = "SELECT id, name, parent_id, display_index FROM dict_group";
        List<Object[]> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> new Object[] {
                rs.getString("id"),
                rs.getString("name"),
                rs.getString("parent_id"),
                rs.getObject("display_index")
        });

        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTblName("dict_group");
            log.setRecordId((String) tuple[0]);
            java.util.Map<String, Object> record = new java.util.HashMap<>();
            record.put("id", tuple[0]);
            record.put("name", tuple[1]);
            record.put("parentId", tuple[2]);
            record.put("displayIndex", tuple[3]);
            log.setRecord(JsonUtils.toJson(record));
            log.setCreateTime(new Date());
            logs.add(log);
        }
        return logs;
    }

    private List<SysDbLogDto> generateGroupAndDictLinkLogs(int version) {
        String sql = "SELECT group_id, dict_id FROM group_and_dict_link";
        List<Object[]> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> new Object[] {
                rs.getString("group_id"),
                rs.getString("dict_id")
        });

        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTblName("group_and_dict_link");
            log.setRecordId(tuple[0] + "-" + tuple[1]);
            java.util.Map<String, Object> record = new java.util.HashMap<>();
            record.put("groupId", tuple[0]);
            record.put("dictId", tuple[1]);
            log.setRecord(JsonUtils.toJson(record));
            log.setCreateTime(new Date());
            logs.add(log);
        }
        return logs;
    }

    private List<SysDbLogDto> generateDictLogs(int version) {
        // 只生成系统词典的日志
        String sql = "SELECT id, name, owner_id, is_shared, is_ready, visible, word_count, popularity_limit, create_time, update_time FROM dict WHERE owner_id='15118'";
        List<Object[]> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> new Object[] {
                rs.getString("id"),
                rs.getString("name"),
                rs.getString("owner_id"),
                rs.getObject("is_shared"),
                rs.getObject("is_ready"),
                rs.getObject("visible"),
                rs.getObject("word_count"),
                rs.getObject("popularity_limit"),
                rs.getTimestamp("create_time"),
                rs.getTimestamp("update_time")
        });

        // 用于格式化日期为ISO-8601格式
        java.text.SimpleDateFormat isoFormat = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        isoFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));

        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTblName("dict");
            log.setRecordId((String) tuple[0]);

            // 格式化日期字段
            String createTimeStr = tuple[8] != null ? isoFormat.format(tuple[8]) : null;
            String updateTimeStr = tuple[9] != null ? isoFormat.format(tuple[9]) : null;

            java.util.Map<String, Object> record = new java.util.HashMap<>();
            record.put("id", tuple[0]);
            record.put("name", tuple[1]);
            record.put("ownerId", tuple[2]);
            record.put("isShared", tuple[3]);
            record.put("isReady", tuple[4]);
            record.put("visible", tuple[5]);
            record.put("wordCount", tuple[6]);
            record.put("popularityLimit", tuple[7]);
            record.put("createTime", createTimeStr);
            record.put("updateTime", updateTimeStr);
            log.setRecord(JsonUtils.toJson(record));
            log.setCreateTime(new Date());
            logs.add(log);
        }
        return logs;
    }

    /**
     * 转换PO为DTO
     */
    private SysDbLogDto toDto(SysDbLog log) {
        SysDbLogDto dto = new SysDbLogDto();
        dto.setId(log.getId());
        dto.setVersion(log.getVersion());
        dto.setOperate(log.getOperate());
        dto.setTblName(log.getTable());
        dto.setRecordId(log.getRecordId());
        dto.setRecord(log.getRecord());
        dto.setCreateTime(log.getCreateTime());
        dto.setUpdateTime(log.getUpdateTime());
        return dto;
    }

    /**
     * 清理旧日志（保留最近30天）
     * 建议通过定时任务调用
     */
    public int cleanOldLogs() {
        Date thirtyDaysAgo = new Date(System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000);
        // 为确保版本完整性，如果一个版本中任何一条记录过期，则删除该全局版本的所有记录
        String sql = "DELETE FROM sys_db_log " +
                "WHERE version IN (" +
                "  SELECT DISTINCT version FROM sys_db_log WHERE create_time < :date" +
                ")";
        MapSqlParameterSource params = new MapSqlParameterSource("date", thirtyDaysAgo);
        return namedParameterJdbcTemplate.update(sql, params);
    }
}
