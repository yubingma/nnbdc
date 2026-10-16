-- =========================================================================
-- v84: meaning_item.ci_xing 由 varchar(10) 扩容为 varchar(20)
--
-- 动机：词性字段此前只有 10 字符上限，而客户端存在两条把原始文本原样当词性
-- 写入本地 meaning_item 的路径：
--   1. 「编辑释义」把词性选成「无」后，自由输入框里的内容直接作为 ci_xing；
--   2. 「表格导入」把表格「词性」列的内容原样作为 ci_xing。
-- 一旦超过 10 字符，这条 meaning_item 的 INSERT 会被 PostgreSQL 拒绝
-- （ERROR: value too long for type character varying(10)），
-- 并连带回滚整次用户数据同步事务。
--
-- 本脚本只放宽字段上限；客户端已同步补上长度校验，超长时直接向用户报错，
-- 不再让超长词性进入同步链路。
-- =========================================================================

ALTER TABLE "meaning_item" ALTER COLUMN "ci_xing" TYPE VARCHAR(20);

COMMENT ON COLUMN "meaning_item"."ci_xing" IS '词性标准英文缩写（如 n.名词, v.动词, vt.及物动词, vi.不及物动词, adj.形容词, adv.副词, prep.介词 等），最长 20 字符';
