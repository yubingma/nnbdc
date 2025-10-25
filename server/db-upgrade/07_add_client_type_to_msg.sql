-- 为msg表添加clientType字段
ALTER TABLE msg ADD COLUMN clientType VARCHAR(20) NULL;

-- 添加索引以提高查询性能
CREATE INDEX idx_msg_client_type ON msg(clientType);
