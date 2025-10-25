-- ========================================
-- 为通用词典创建 dict_word 记录
-- 说明：将通用词典与普通词书统一，为所有有通用释义的单词创建 dict_word 记录
-- ========================================

-- 步骤1：为通用词典中的所有单词创建 dict_word 记录
-- 按单词拼写排序，自动生成序号
INSERT INTO bdc.dict_word (dictId, wordId, seq, createTime, updateTime)
SELECT 
    '0' as dictId,
    w.id as wordId,
    (@row_number := @row_number + 1) as seq,
    NOW() as createTime,
    NOW() as updateTime
FROM 
    bdc.word w,
    (SELECT @row_number := 0) as init
WHERE 
    EXISTS (
        SELECT 1 
        FROM bdc.meaning_item mi 
        WHERE mi.word = w.id AND mi.dictId = '0'
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM bdc.dict_word dw 
        WHERE dw.dictId = '0' AND dw.wordId = w.id
    )
ORDER BY w.spell;

-- 步骤2：更新通用词典的 wordCount 字段为实际单词数
UPDATE bdc.dict 
SET wordCount = (
    SELECT COUNT(*) 
    FROM bdc.dict_word 
    WHERE dictId = '0'
),
updateTime = NOW()
WHERE id = '0';

-- 步骤3：验证数据
SELECT 
    '通用词典dict_word记录数' as item,
    COUNT(*) as count
FROM bdc.dict_word 
WHERE dictId = '0'
UNION ALL
SELECT 
    '通用词典wordCount' as item,
    wordCount as count
FROM bdc.dict 
WHERE id = '0'
UNION ALL
SELECT 
    '通用词典释义项涉及的单词数' as item,
    COUNT(DISTINCT word) as count
FROM bdc.meaning_item 
WHERE dictId = '0';

