-- ========================================
-- 将通用词典从虚拟ID改为实际数据库记录
-- 说明：通用词典之前使用虚拟ID "0"，释义项的dictId为NULL
-- 本脚本将：
-- 1. 在dict表中创建id='0'的通用词典记录
-- 2. 将所有meaning_item表中dictId为NULL的记录更新为'0'
-- ========================================

-- 步骤1：在dict表中插入通用词典记录
-- 检查是否已存在，避免重复插入
INSERT INTO bdc.dict (id, name, owner, isShared, isReady, visible, wordCount, createTime, updateTime)
SELECT '0', '通用词典.dict', '15118', 1, 1, 1, 
       (SELECT COUNT(DISTINCT word) FROM bdc.meaning_item WHERE dictId IS NULL),
       '2000-01-01 00:00:00', 
       NOW()
WHERE NOT EXISTS (SELECT 1 FROM bdc.dict WHERE id = '0');

-- 步骤2：更新meaning_item表，将dictId为NULL的记录更新为'0'
-- 这是核心迁移步骤，将虚拟的通用词典ID变为实际的
UPDATE bdc.meaning_item 
SET dictId = '0' 
WHERE dictId IS NULL;

-- 步骤3：验证数据迁移
-- 执行后应该没有dictId为NULL的记录了
SELECT 
    '迁移验证' as status,
    (SELECT COUNT(*) FROM bdc.meaning_item WHERE dictId IS NULL) as null_count,
    (SELECT COUNT(*) FROM bdc.meaning_item WHERE dictId = '0') as common_dict_count,
    (SELECT COUNT(*) FROM bdc.dict WHERE id = '0') as dict_record_count;

