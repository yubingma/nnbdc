-- =====================================================
-- 增加 today_study_started 字段的数据库升级脚本
-- 执行时间: 在应用升级前执行
-- =====================================================

ALTER TABLE "user" ADD COLUMN IF NOT EXISTS today_study_started BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN "user".today_study_started IS '今日学习是否已经开始（点击了“开始学习”按钮）';

-- =====================================================
-- 说明:
-- 增加 today_study_started 字段用于判断学习任务是否已被锁定
-- =====================================================
