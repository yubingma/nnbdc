-- v72：补齐因短语挂在动词变形词上而缺失的原型词短语
--
-- 背景：柯林斯把部分短语挂在形容词/分词形式上（如 bound、tired、injured），
-- 导致原型词（bind、tire、injure）自己查不到搭配。这里为真正同源的 5 个原型词补一份。
--
-- 只补这 5 个。另外 5 个（bathe/bite/byline/rend/unfit）是 verb_tense 表的错误关联：
-- 它们的短语实际属于 bath、bit、line、rent、fit 等另外的词条，复制过来只会固化错误关系。

INSERT INTO "word_phrase"
    ("id", "word_id", "phrase", "part_of_speech", "meaning_cn", "meaning_en",
     "example_en", "example_cn", "source", "display_index", "create_time", "update_time")
SELECT replace(gen_random_uuid()::text, '-', ''),
       ow."id",
       wp."phrase", wp."part_of_speech", wp."meaning_cn", wp."meaning_en",
       wp."example_en", wp."example_cn", wp."source", wp."display_index",
       now(), now()
FROM (VALUES
        ('bind',    'bound'),
        ('injure',  'injured'),
        ('please',  'pleased'),
        ('tire',    'tired'),
        ('balance', 'balanced')
     ) AS m(lemma, inflected)
JOIN "word" ow ON ow."spell" = m.lemma
JOIN "word" iw ON iw."spell" = m.inflected
JOIN "word_phrase" wp ON wp."word_id" = iw."id"
WHERE NOT EXISTS (
    SELECT 1 FROM "word_phrase" x
    WHERE x."word_id" = ow."id" AND x."phrase" = wp."phrase"
);
