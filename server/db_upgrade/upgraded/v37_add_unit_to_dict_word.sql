-- 数据库升级脚本: 为 dict_word 表增加 unit 字段
-- 适用环境: 生产环境 (MySQL/MariaDB/PostgreSQL)

-- 1. 增加字段 (默认值为 0)
ALTER TABLE dict_word ADD COLUMN unit INTEGER NOT NULL DEFAULT 0;

-- 2. (可选) 为 unit 字段增加索引，以优化分组查询性能
CREATE INDEX idx_dict_unit ON dict_word (dict_id, unit);
