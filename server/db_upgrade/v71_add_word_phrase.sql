-- v71：新增单词常用短语搭配表
-- 用途：存放「单词的常用短语搭配」，是单词的附属参考内容，在单词详情页展示。
-- 注意：它与可独立背诵的「短语词条」（word 表里 spell 含空格的词条）是两个不同概念，互不关联。
-- 数据来源：柯林斯词典（经有道词典接口采集），source 字段标记为 collins。

CREATE TABLE IF NOT EXISTS "word_phrase" (
    "id"             VARCHAR(32)  NOT NULL,
    "word_id"        VARCHAR(32)  NOT NULL,
    "phrase"         VARCHAR(200) NOT NULL,
    "part_of_speech" VARCHAR(20),
    "meaning_cn"     VARCHAR(500),
    "meaning_en"     VARCHAR(1000),
    "example_en"     VARCHAR(500),
    "example_cn"     VARCHAR(500),
    "source"         VARCHAR(20)  NOT NULL,
    "display_index"  INTEGER      NOT NULL DEFAULT 0,
    "create_time"    TIMESTAMP    NOT NULL,
    "update_time"    TIMESTAMP    NOT NULL,
    CONSTRAINT "pk_word_phrase_id" PRIMARY KEY ("id"),
    CONSTRAINT "fk_word_phrase_word" FOREIGN KEY ("word_id") REFERENCES "word" ("id")
);

-- 同一个单词下短语不重复
CREATE UNIQUE INDEX IF NOT EXISTS "uk_word_phrase_word_phrase" ON "word_phrase" ("word_id", "phrase");

COMMENT ON TABLE "word_phrase" IS '单词的常用短语搭配（单词的附属参考内容，不是可独立背诵的短语词条）';
COMMENT ON COLUMN "word_phrase"."id" IS '主键，32位UUID';
COMMENT ON COLUMN "word_phrase"."word_id" IS '所属单词ID，外键指向 word.id';
COMMENT ON COLUMN "word_phrase"."phrase" IS '短语原文，可替换成分用 someone/something 占位';
COMMENT ON COLUMN "word_phrase"."part_of_speech" IS '短语所属词性，如 verb、noun';
COMMENT ON COLUMN "word_phrase"."meaning_cn" IS '短语的中文释义';
COMMENT ON COLUMN "word_phrase"."meaning_en" IS '短语的英文释义';
COMMENT ON COLUMN "word_phrase"."example_en" IS '短语例句（英文）';
COMMENT ON COLUMN "word_phrase"."example_cn" IS '短语例句的中文翻译';
COMMENT ON COLUMN "word_phrase"."source" IS '内容来源标记，当前全部为 collins';
COMMENT ON COLUMN "word_phrase"."display_index" IS '同一单词下的展示顺序，值小的排在前面';
COMMENT ON COLUMN "word_phrase"."create_time" IS '创建时间';
COMMENT ON COLUMN "word_phrase"."update_time" IS '更新时间';
