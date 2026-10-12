-- 客服会话支持「引用回复」：管理员的回复可以指明它是在回用户的哪一条消息。
-- 被引用的消息以自身主键存在 reply_to_id 里；不做多层嵌套，引用不能再被引用。
ALTER TABLE msg ADD COLUMN IF NOT EXISTS reply_to_id VARCHAR(32);

-- 建立索引以支持「这条消息是否被别人引用」的检查（删除消息前要拦一道）
CREATE INDEX IF NOT EXISTS idx_msg_reply_to ON msg(reply_to_id);

-- 表与字段注释
COMMENT ON COLUMN msg.reply_to_id IS '被引用的消息ID；为空表示这条不是对某条消息的针对性回复。仅允许一层引用';
