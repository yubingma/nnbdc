-- 修正 user_study_step 表 scope / state 两个字段的错误注释
--
-- 数据库方言: PostgreSQL
--
-- 背景: v62_add_table_and_column_comments.sql 给这两个字段写的取值，与代码实际使用的
-- 完全不符（原始错误内容见该文件第 895、896 行），会误导后续维护者：
--   v62 写的是 scope = 'LEARNING' / 'REVIEW'          → 实际是 'new' / 'review'
--   v62 写的是 state = 'WAITING'/'DOING'/'FINISHED'   → 实际是 'Active' / 'Inactive'
-- 服务端 Java 代码全文搜不到 LEARNING、WAITING、DOING、FINISHED 这几个取值。
--
-- 取值依据（以代码为准）:
--   scope: server/nnbdc-service/src/main/java/beidanci/service/bo/UserStudyStepBo.java
--          initUserStudySteps() 的注释原文即「scope='new' 新词 + scope='review' 旧词」
--   state: server/nnbdc-api/src/main/java/beidanci/api/model/StudyStepState.java
--          Active("激活"), Inactive("非激活")
--
-- 说明: 本脚本仅修正注释文字，不改动任何表结构与数据。

COMMENT ON COLUMN "user_study_step"."scope" IS '业务学习流程作用域：new（每日新词学习流程）/ review（旧词复习巩固流程）';
COMMENT ON COLUMN "user_study_step"."state" IS '该学习步骤当前执行状态：Active（激活）/ Inactive（非激活）';
