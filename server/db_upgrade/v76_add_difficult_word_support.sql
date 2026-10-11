-- 用户错题本增加累计答错次数与错题本留存状态，支持「我的难词」专项突破与多端同步
ALTER TABLE "user_wrong_word" ADD COLUMN IF NOT EXISTS "wrong_count" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "user_wrong_word" ADD COLUMN IF NOT EXISTS "in_wrong_book" BOOLEAN NOT NULL DEFAULT TRUE;

-- 字段业务注释
COMMENT ON COLUMN "user_wrong_word"."wrong_count" IS '累计答错次数（达到3次及以上自动归入我的难词）';
COMMENT ON COLUMN "user_wrong_word"."in_wrong_book" IS '是否保留在错题本中（从错题本移出时置为false，累计答错计数仍永久保留）';
