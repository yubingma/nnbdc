package beidanci.service.bo;

import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.Assert;

import beidanci.api.model.SysDbLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.SysDbLog;
import beidanci.service.po.SysDbVersion;
import beidanci.api.model.Ownerable;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.Util;

/**
 * 系统数据日志业务类
 * 用于记录和查询UGC内容的变更日志
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class SysDbSyncBo extends BaseBo<SysDbLog> {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(SysDbSyncBo.class);
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<SysDbLog>() {
        });
    }

    /**
     * 记录系统数据操作日志 (增强安全性版本，包含对象所有权校验)
     */
    public void logOperation(Object entity, String operate, String table, String recordId, String record) {
        if (entity instanceof Ownerable) {
            String ownerId = ((Ownerable) entity).getOwnerId();
            Assert.isTrue(beidanci.util.Constants.SYS_USER_SYS_ID.equals(ownerId),
                "SECURITY ALERT: Attempted to log private data to global sync log! table=" + table + ", ownerId=" + ownerId);
        }
        logOperation(operate, table, recordId, record);
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
        // 断言：核心参数不能为空，且在 INSERT/UPDATE 时 record JSON 不能为空
        Assert.hasText(operate, "SysDbSync: operate must not be blank");
        Assert.hasText(table, "SysDbSync: table must not be blank");
        Assert.hasText(recordId, "SysDbSync: recordId must not be blank");
        Assert.hasText(record, "SysDbSync: record content must not be blank");

        record = JsonUtils.enrichRecordJson(record);

        // 针对核心表的业务级预校验 (及早发现由于 DTO 映射导致的数据缺失)
        if (!operate.equals("DELETE")) {
            if (table.equals("dict")) {
                Assert.isTrue(record.contains("\"ownerId\"") || record.contains("\"owner_id\""), 
                    "SysDbSync [dict] MUST contain ownerId, but got: " + record);
                Assert.isTrue(record.contains("\"name\""), 
                    "SysDbSync [dict] MUST contain name, but got: " + record);
            }
        }

        // 在同一事务中完成：1）记录日志 2）递增版本号
        int currentVersion = getSysDbVersion();
        int nextVersion = currentVersion + 1;

        // 创建日志
        Date now= new Date();
        SysDbLog sysDbLog = new SysDbLog();
        sysDbLog.setId(Util.uuid());
        sysDbLog.setVersion(nextVersion);
        sysDbLog.setOperate(operate);
        sysDbLog.setTable(table);
        sysDbLog.setRecordId(recordId);
        sysDbLog.setRecord(record);
        sysDbLog.setCreateTime(now);
        sysDbLog.setUpdateTime(now);

        log.info("Recording SysDbLog: tbl={}, recordId={}, version={}, operate={}", table, recordId, nextVersion, operate);
        createEntity(sysDbLog);

        // 递增版本号
        incrementSysDbVersion(nextVersion);
        log.info("SysDbVersion incremented to: {}", nextVersion);
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
        if (versions.isEmpty()) {
            return 0;
        }
        Integer version = versions.get(0).getVersion();
        return version != null ? version : 0;
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
    public List<SysDbLogDto> getSysDbLogs(int fromVersion) {
        int currentVersion = getSysDbVersion();

        // 1. 首次同步
        if (fromVersion == 0) {
            return generateFullSysDbLogs(currentVersion);
        }

        // 对于已经初始化的客户端（fromVersion > 0）：
        // 绝对不能回退到全量同步 (generateFullSysDbLogs)！
        // 因为 generateFullSysDbLogs 因数据量过大，专门不包含 word_image, sentence, meaning等核心明细和UGC数据的日志，
        // 如果 fromVersion > 0 的客户端接收到包含元数据的“残缺”全量同步日志，它把本地版本号提升到最新，
        // 从而永久跳过并丢失原本该下发所有缺失版本的修改和「删除」日志。
        // 这会导致客户端本地数据库出现大量无法清理的孤儿数据（如已经被服务端删除的配图和例句不断闪烁/残留）。

        // 所以，即使日志数量过多，或者过旧被清理导致出现了断层缝隙，
        // 我们也只能下发当前库里所剩的所有增量日志，通过增量同步尽最大可能保持一致。
        // （已移除 "日志时间过旧" 和 "找不到对应版本" 以及 "超过5w条限制" 回退全量同步的核心错误逻辑）

        // 2. 增量同步 (SQL 层面进行 Compaction 优化)
        // 策略：取每个实体在版本范围内的最后一次变更数据，但按照该实体在该范围内第一次出现的顺序进行排序。
        // 这样既能合并冗余的 UPDATE，又能保证关联表之间的引用完整性（例如先插入父表再插入子表）。
        String sql = "SELECT s.* FROM sys_db_log s " +
                "INNER JOIN ( " +
                "  SELECT tbl_name, record_id, MAX(version) as last_v, MIN(version) as first_v " +
                "  FROM sys_db_log " +
                "  WHERE version > :fromVersion " +
                "  GROUP BY tbl_name, record_id " +
                ") m ON s.version = m.last_v " +
                "ORDER BY m.first_v ASC";
        MapSqlParameterSource params = new MapSqlParameterSource("fromVersion", fromVersion);
        List<SysDbLog> logs = namedParameterJdbcTemplate.query(sql, params,
                new EntityRowMapper<>(SysDbLog.class));
        log.info("Fetched {} compacted incremental sys_db_logs from version {}", logs.size(), fromVersion);
        return logs.stream().map(this::toDto).collect(Collectors.toList());
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
        String sql = "SELECT id, name, parent_id, display_index, create_time, update_time FROM dict_group";
        List<Object[]> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> new Object[] {
                rs.getString("id"),
                rs.getString("name"),
                rs.getString("parent_id"),
                rs.getObject("display_index"),
                rs.getTimestamp("create_time"),
                rs.getTimestamp("update_time")
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

            Map<String, Object> record = buildRecordMap(tuple, 4,
                "id", "0",
                "name", "1",
                "parentId", "2",
                "displayIndex", "3"
            );

            Assert.notNull(tuple[0], "DictGroup ID must not be null");
            Assert.notNull(tuple[1], "DictGroup Name must not be null");

            log.setRecord(JsonUtils.toJson(record));
            Date now = new Date();
            log.setCreateTime(now);
            log.setUpdateTime(now);
            logs.add(log);
        }
        return logs;
    }

    private List<SysDbLogDto> generateGroupAndDictLinkLogs(int version) {
        String sql = "SELECT group_id, dict_id, create_time, update_time FROM group_and_dict_link";
        List<Object[]> results = namedParameterJdbcTemplate.getJdbcTemplate().query(sql, (rs, rowNum) -> new Object[] {
                rs.getString("group_id"),
                rs.getString("dict_id"),
                rs.getTimestamp("create_time"),
                rs.getTimestamp("update_time")
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

            Map<String, Object> record = buildRecordMap(tuple, 2,
                "groupId", "0",
                "dictId", "1"
            );

            Assert.notNull(tuple[0], "GroupAndDictLink groupId must not be null");
            Assert.notNull(tuple[1], "GroupAndDictLink dictId must not be null");

            log.setRecord(JsonUtils.toJson(record));
            Date now = new Date();
            log.setCreateTime(now);
            log.setUpdateTime(now);
            logs.add(log);
        }
        return logs;
    }

    private List<SysDbLogDto> generateDictLogs(int version) {
        // 只生成系统词典的日志
        String sql = "SELECT id, name, owner_id, is_shared, is_ready, visible, word_count, popularity_limit, create_time, update_time, editable, deletable FROM dict WHERE owner_id='15118'";
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
                rs.getTimestamp("update_time"),
                rs.getObject("editable"),
                rs.getObject("deletable")
        });

        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTblName("dict");
            log.setRecordId((String) tuple[0]);

            Map<String, Object> record = buildRecordMap(tuple, 8,
                "id", "0",
                "name", "1",
                "ownerId", "2",
                "isShared", "3",
                "isReady", "4",
                "visible", "5",
                "wordCount", "6",
                "popularityLimit", "7",
                "editable", "10",
                "deletable", "11"
            );

            Assert.notNull(tuple[0], "Dict ID must not be null");
            Assert.notNull(tuple[1], "Dict Name must not be null");
            Assert.notNull(tuple[2], "Dict Owner ID must not be null");

            log.setRecord(JsonUtils.toJson(record));
            Date now = new Date();
            log.setCreateTime(now);
            log.setUpdateTime(now);
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

    private static final java.text.SimpleDateFormat ISO_FMT;
    static {
        ISO_FMT = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
        ISO_FMT.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
    }

    private Map<String, Object> buildRecordMap(Object[] tuple, int timeStartIdx, String... keyValuePairs) {
        Map<String, Object> record = new LinkedHashMap<>();
        for (int i = 0; i < keyValuePairs.length; i += 2) {
            String key = keyValuePairs[i];
            int idx = Integer.parseInt(keyValuePairs[i + 1]);
            record.put(key, tuple[idx]);
        }
        String ct = tuple[timeStartIdx] != null ? ISO_FMT.format(tuple[timeStartIdx]) : ISO_FMT.format(new Date());
        String ut = tuple[timeStartIdx + 1] != null ? ISO_FMT.format(tuple[timeStartIdx + 1]) : ISO_FMT.format(new Date());
        record.put("createTime", ct);
        record.put("updateTime", ut);
        return record;
    }

    /**
     * 清理旧日志（保留最近10天）
     */
    public int cleanOldLogs() {
        Date cutoff = new Date(System.currentTimeMillis() - 10L * 24 * 60 * 60 * 1000);
        // 为确保版本完整性，如果一个版本中任何一条记录过期，则删除该全局版本的所有记录
        String sql = "DELETE FROM sys_db_log " +
                "WHERE version IN (" +
                "  SELECT DISTINCT version FROM sys_db_log WHERE create_time < :date" +
                ")";
        MapSqlParameterSource params = new MapSqlParameterSource("date", cutoff);
        return namedParameterJdbcTemplate.update(sql, params);
    }

    /**
     * 执行数据库维护 (VACUUM ANALYZE)
     */
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public void vacuumAnalyze() {
        jdbcTemplate.execute("VACUUM ANALYZE sys_db_log");
    }
}
