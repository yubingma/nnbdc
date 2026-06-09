-- v46: 补充 word_embedding 表的 create_time 字段，兼容继承自 Po 基类的持久化要求
ALTER TABLE word_embedding ADD COLUMN create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;
