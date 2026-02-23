-- 为词书表添加 editable 字段
-- 生词本和自定义词书（可以通过 owner_id 判断）默认 editable 为 true
ALTER TABLE dict ADD COLUMN editable BOOLEAN NOT NULL DEFAULT FALSE;

-- 更新现有数据：生词本和自定义词书（owner_id 不为 15118 的）设为可编辑
UPDATE dict SET editable = TRUE WHERE name = '生词本' OR owner_id != '15118';
