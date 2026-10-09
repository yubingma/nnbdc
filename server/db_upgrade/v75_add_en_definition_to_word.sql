-- 单词主表增加分词性简明英英释义字段（提炼自权威开源词库），支持客户端英英/英汉双解学习展示
ALTER TABLE "word" ADD COLUMN IF NOT EXISTS "en_definition" TEXT;

-- 字段注释
COMMENT ON COLUMN "word"."en_definition" IS '分词性简明英英释义（多行文本，每行一个词性定义）；未收录时为 NULL';
