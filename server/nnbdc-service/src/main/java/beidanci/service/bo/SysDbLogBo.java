package beidanci.service.bo;

import beidanci.api.model.SysDbLogDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.SysDbLog;
import beidanci.service.po.SysDbVersion;
import beidanci.service.util.JsonUtils;
import beidanci.service.util.Util;
import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.PostConstruct;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 系统数据日志业务类
 * 用于记录和查询UGC内容的变更日志
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class SysDbLogBo extends BaseBo<SysDbLog> {

    @PostConstruct
    public void init() {
        setDao(new BaseDao<SysDbLog>() {
        });
    }

    /**
     * 记录系统数据操作日志
     * 
     * @param operate 操作类型：INSERT/UPDATE/DELETE
     * @param table 表名：word_image/sentence/word_shortdesc_chinese
     * @param recordId 记录ID
     * @param record 记录内容（JSON格式）
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
        String hql = "FROM SysDbVersion WHERE id = 'singleton'";
        Query<SysDbVersion> query = getSession().createQuery(hql, SysDbVersion.class);
        SysDbVersion version = query.uniqueResult();
        return version != null ? version.getVersion() : 0;
    }

    /**
     * 递增全局版本号
     * 
     * @param newVersion 新版本号
     */
    private void incrementSysDbVersion(int newVersion) {
        String hql = "FROM SysDbVersion WHERE id = 'singleton'";
        Query<SysDbVersion> query = getSession().createQuery(hql, SysDbVersion.class);
        SysDbVersion version = query.uniqueResult();

        if (version == null) {
            // 首次创建版本记录
            version = new SysDbVersion("singleton", newVersion);
            version.setCreateTime(new Date());
            getSession().save(version);
        } else {
            // 更新版本号
            version.setVersion(newVersion);
            version.setUpdateTime(new Date());
            getSession().update(version);
        }
    }

    /**
     * 获取增量日志（支持全量生成）
     * 
     * @param fromVersion 起始版本号（不包含）
     * @return 增量日志列表，按版本号升序排列
     */
    public List<SysDbLogDto> getNewSysDbLogs(int fromVersion) {
        int currentVersion = getSysDbVersion();
        
        // 如果客户端版本过旧（>10个版本差距），或者是首次同步（fromVersion=0），生成全量日志
        if (fromVersion == 0 || currentVersion > fromVersion + 10 || !hasVersionLogs(fromVersion)) {
            return generateFullSysDbLogs(currentVersion);
        } else {
            // 增量同步
            String hql = "FROM SysDbLog WHERE version > :fromVersion ORDER BY version ASC";
            Query<SysDbLog> query = getSession().createQuery(hql, SysDbLog.class);
            query.setParameter("fromVersion", fromVersion);
            
            List<SysDbLog> logs = query.list();
            return logs.stream().map(this::toDto).collect(Collectors.toList());
        }
    }
    
    /**
     * 检查是否存在指定版本的日志
     */
    private boolean hasVersionLogs(int fromVersion) {
        String hql = "SELECT COUNT(*) FROM SysDbLog WHERE version > :fromVersion";
        Query<Long> query = getSession().createQuery(hql, Long.class);
        query.setParameter("fromVersion", fromVersion);
        Long count = query.uniqueResult();
        return count != null && count > 0;
    }
    
    /**
     * 生成系统数据全量日志（动态生成）
     * 用于首次同步或版本差距过大时
     */
    private List<SysDbLogDto> generateFullSysDbLogs(int currentVersion) {
        List<SysDbLogDto> logs = new ArrayList<>();
        
        // === 静态元数据 ===
        // 1. Levels
        logs.addAll(generateLevelLogs(currentVersion));
        
        // 2. DictGroups
        logs.addAll(generateDictGroupLogs(currentVersion));
        
        // 3. GroupAndDictLinks
        logs.addAll(generateGroupAndDictLinkLogs(currentVersion));
        
        // 4. Dicts（只包含系统词典）
        logs.addAll(generateDictLogs(currentVersion));
        
        // sentence/word_image/word_shortdesc_chinese的数据, 不需要全量同步, 因为数据量太大, 而且用户下载所需词书的时候, 已经包含所需的这些数据了
        
        return logs;
    }
    
    private List<SysDbLogDto> generateLevelLogs(int version) {
        // 动态生成Level的INSERT日志
        String sql = "SELECT id, level, name, figure, minScore, maxScore, style, createTime, updateTime FROM level";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.list();
        
        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTable_("level");
            log.setRecordId((String) tuple[0]);
            java.text.SimpleDateFormat isoFormat = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
            isoFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            java.util.Map<String, Object> record = new java.util.HashMap<>();
            record.put("id", tuple[0]);
            record.put("level", tuple[1]);
            record.put("name", tuple[2]);
            record.put("figure", tuple[3]);
            record.put("minScore", tuple[4]);
            record.put("maxScore", tuple[5]);
            record.put("style", tuple[6]);
            record.put("createTime", tuple[7] != null ? isoFormat.format(tuple[7]) : null);
            record.put("updateTime", tuple[8] != null ? isoFormat.format(tuple[8]) : null);
            log.setRecord(JsonUtils.toJson(record));
            log.setCreateTime(new Date());
            logs.add(log);
        }
        return logs;
    }
    
    private List<SysDbLogDto> generateDictGroupLogs(int version) {
        String sql = "SELECT id, name, parentId, displayIndex FROM dict_group";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.list();
        
        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTable_("dict_group");
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
        String sql = "SELECT groupId, dictId FROM group_and_dict_link";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.list();
        
        List<SysDbLogDto> logs = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SysDbLogDto log = new SysDbLogDto();
            log.setId(Util.uuid());
            log.setVersion(version);
            log.setOperate("INSERT");
            log.setTable_("group_and_dict_link");
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
        String sql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime FROM dict WHERE ownerId='15118'";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.list();
        
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
            log.setTable_("dict");
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
        dto.setTable_(log.getTable());
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
        String hql = "DELETE FROM SysDbLog WHERE createTime < :date";
        Query<?> query = getSession().createQuery(hql);
        query.setParameter("date", thirtyDaysAgo);
        int deletedCount = query.executeUpdate();
        return deletedCount;
    }
}

