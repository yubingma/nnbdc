-- 撤销 v80 给 msg 加的「消息级需求处理状态」。
--
-- 背景：给用户的消息打「需求」标签，只是给那一条消息贴一个标签，与需求墙（feature_request）
-- 是两套不相干的数据。原实现在打标时凭空写入「投票中」，还把需求墙的阶段概念搬到了
-- 消息级需求上。现在标签就只是标签，不存在处理状态。
--
-- ⚠️ 本脚本不可逆：执行后 msg.req_status 的历史取值（投票中/开发中/已拒绝/已完成）永久丢失。
-- 执行前请确认这些取值不再需要保留。
-- 索引 idx_msg_req_status 依存于该列，随列的删除一并消失，无需单独 DROP。

ALTER TABLE msg DROP COLUMN IF EXISTS req_status;

-- tag 的注释同步纠正：打标不再牵动任何状态
COMMENT ON COLUMN msg.tag IS '管理员业务标注标签（如：需求）；未标注时为 NULL';
