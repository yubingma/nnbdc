-- 消息级需求：被管理员标记为「需求」的那条消息，需要一个处理状态才能当待办推进。
-- 档位与需求墙（feature_request.status）保持一致，管理员不用另学一套。
ALTER TABLE msg ADD COLUMN IF NOT EXISTS req_status VARCHAR(20);

-- 建立索引以支持按状态检索需求列表
CREATE INDEX IF NOT EXISTS idx_msg_req_status ON msg(req_status);

-- 表与字段注释
COMMENT ON COLUMN msg.req_status IS '消息级需求的处理状态：VOTING投票中/IN_PROGRESS开发中/REJECTED已拒绝/COMPLETED已完成；仅当 tag=''需求'' 时有效，取消需求标记时应置回 NULL';
COMMENT ON COLUMN msg.tag IS '管理员业务标注标签（如：需求）；未标注时为 NULL。标记为需求时应同时写入 req_status';
