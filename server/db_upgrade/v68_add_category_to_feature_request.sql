-- 为需求墙表新增分类字段，支持按业务板块划分需求
ALTER TABLE feature_request ADD COLUMN IF NOT EXISTS category VARCHAR(32) NOT NULL DEFAULT 'OTHER';

-- 字段业务中文注释
COMMENT ON COLUMN feature_request.category IS '需求分类：VOCABULARY(背词复习), DICTIONARY(词典查词), INTERACTION(游戏与互动), EXPERIENCE(界面与体验), OTHER(其他建议)';

-- 分类索引
CREATE INDEX IF NOT EXISTS idx_feature_request_category ON feature_request (category);
