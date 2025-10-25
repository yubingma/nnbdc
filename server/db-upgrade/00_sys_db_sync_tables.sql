-- ============================================
-- 系统数据增量同步表结构
-- 创建时间：2025-10-18
-- 用途：支持UGC内容（Sentences、WordImages、WordShortDescChinese）增量同步
-- ============================================

-- 1. 全局系统数据版本表（单例表）
CREATE TABLE IF NOT EXISTS sys_db_version (
    id VARCHAR(36) PRIMARY KEY DEFAULT 'singleton' COMMENT '固定为singleton，单例表',
    version INT NOT NULL DEFAULT 1 COMMENT '当前全局版本号',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='系统数据库版本表（单例）';

-- 初始化版本记录（version=1表示系统已初始化，有静态数据可同步）
-- 前端新安装时本地版本为0，远程版本为1，触发首次全量同步
INSERT INTO sys_db_version (id, version, createTime) 
VALUES ('singleton', 1, NOW())
ON DUPLICATE KEY UPDATE id=id;

-- 2. 系统数据变更日志表
CREATE TABLE IF NOT EXISTS sys_db_log (
    id VARCHAR(36) PRIMARY KEY COMMENT '日志ID',
    version INT NOT NULL COMMENT '日志版本号（递增）',
    operate VARCHAR(20) NOT NULL COMMENT '操作类型：INSERT/UPDATE/DELETE',
    table_ VARCHAR(50) NOT NULL COMMENT '表名：word_image/sentence/word_shortdesc_chinese',
    record_id VARCHAR(131) NOT NULL COMMENT '记录ID',
    record TEXT NOT NULL COMMENT '记录内容（JSON格式）',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间',
    INDEX idx_version (version) COMMENT '按版本查询增量日志',
    INDEX idx_table_record (table_, record_id) COMMENT '查重和查找特定记录'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='系统数据变更日志表';



delete from sys_param where paramName='systemDbVersion';

ALTER TABLE bdc.user 
ADD COLUMN asrPassRule VARCHAR(10) 
COMMENT 'ASR答对判定规则：ONE/HALF/ALL';
-- 如果字段已存在，上面语句会报错，可忽略该错误继续执行后续语句

-- 2. 创建user_oper表（用户操作历史记录表）
CREATE TABLE IF NOT EXISTS bdc.user_oper (
    id VARCHAR(32) NOT NULL COMMENT '主键ID',
    userId VARCHAR(32) NOT NULL COMMENT '用户ID',
    operType VARCHAR(20) NOT NULL COMMENT '操作类型：LOGIN、START_LEARN、DAKA等',
    operTime DATETIME NOT NULL COMMENT '操作时间',
    remark VARCHAR(200) COMMENT '备注信息',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间',
    PRIMARY KEY (id),
    INDEX idx_userId_operTime (userId, operTime) COMMENT '按用户和时间查询',
    INDEX idx_operType (operType) COMMENT '按操作类型查询',
    CONSTRAINT fk_user_oper_user FOREIGN KEY (userId) REFERENCES user (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='用户操作历史记录表';

