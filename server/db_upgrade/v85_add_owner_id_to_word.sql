-- 单词主表增加所有者ID，区分系统词(15118)与用户私有自定义词(用户ID)
ALTER TABLE "word" ADD COLUMN IF NOT EXISTS "owner_id" VARCHAR(32) NOT NULL DEFAULT '15118';

-- 字段注释
COMMENT ON COLUMN "word"."owner_id" IS '单词所有者ID：15118 为系统公共词，用户ID为私有自定义词';

-- 将原本的全局拼写唯一索引升级为按用户隔离的复合唯一索引
ALTER TABLE "word" DROP CONSTRAINT IF EXISTS uk_word_idx_wordspell;
DROP INDEX IF EXISTS idx_wordspell;
CREATE UNIQUE INDEX IF NOT EXISTS idx_word_spell_owner ON "word"(spell, owner_id);
