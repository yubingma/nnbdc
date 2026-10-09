-- 意见建议消息表增加管理员标签字段（如：需求），用于沉淀用户提出的产品需求并支持按标签过滤。
ALTER TABLE msg ADD COLUMN IF NOT EXISTS tag VARCHAR(32);

-- 建立索引以支持按标签过滤检索
CREATE INDEX IF NOT EXISTS idx_msg_tag ON msg(tag);

-- 表与字段注释
COMMENT ON COLUMN msg.tag IS '管理员业务标注标签（如：需求）；未标注时为 NULL';
