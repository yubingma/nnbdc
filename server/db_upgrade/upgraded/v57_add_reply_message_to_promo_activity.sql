-- Add reply_message to promo_activity table
-- 活动应答消息模板，支持占位符 {name} / {duration}；为空时使用代码内置默认文案
ALTER TABLE promo_activity ADD COLUMN IF NOT EXISTS reply_message TEXT;
