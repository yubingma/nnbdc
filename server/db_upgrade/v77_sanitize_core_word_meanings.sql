-- v77: 系统性校准核心高频功能词与基础词的通用释义（dict_id='0'）常用度排序
-- 
-- 背景：通用词典（dict_id='0'）历史早期导入及部分图表对齐时，将部分多义项的高频短词（尤其是介词、助动词、动词）
-- 的冷僻名词用法（如 in 标为"执政者"、a 标为"英语字母表第一个字母"、into 标为"除"、under 标为"低于"等）
-- 错误赋予了 popularity=1，导致对战大厅及背单词模块的首选释义与朗读出现严重反常。
-- 本脚本对公认最核心的基础功能词与高频词进行权威校准，锁定第一核心常用义为 popularity=1。

BEGIN;

-- 1. in: 核心介词（在…里；在…之内）为 1，冷门政治俚语名词（执政者）降至末尾
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在…里；在…之内', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'in')
  AND ("meaning" LIKE '%在%之内%' OR "meaning" LIKE '%在…里%' OR "ci_xing" = 'prep.');

UPDATE "meaning_item"
SET "popularity" = 12, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'in')
  AND "meaning" = '执政者';

-- 2. into: 核心介词（进入；到…里面）为 1，数学冷门除法义（除）降至末尾
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '进入；到…里面', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'into')
  AND ("meaning" = '进入' OR "meaning" LIKE '%到…里面%');

UPDATE "meaning_item"
SET "popularity" = 9, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'into')
  AND "meaning" = '除';

-- 3. a: 核心不定冠词（一个）为 1，字母名词（英语字母表的第一个字母）降至末尾
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'a')
  AND "meaning" = '一个';

UPDATE "meaning_item"
SET "popularity" = 9, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'a')
  AND "meaning" LIKE '%字母表的第%';

-- 4. do: 核心动词（做；干）为 1，语法术语字面（助动词）降至末尾
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '做，干；进行', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'do')
  AND ("meaning" = '做' OR "meaning" = '做，干；进行');

UPDATE "meaning_item"
SET "popularity" = 9, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'do')
  AND "meaning" = '助动词';

-- 5. under: 核心介词（在…下面；在…下）为 1，次生义（低于）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在…下面；在…之下', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'under')
  AND ("meaning" LIKE '%在%下%' OR "meaning" LIKE '%在…下%');

UPDATE "meaning_item"
SET "popularity" = 6, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'under')
  AND "meaning" = '低于';

-- 6. on: 核心空间介词（在…上面；在…上）为 1，引申义（关于）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在…上面；在…上', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'on')
  AND ("meaning" LIKE '%在%上%' OR "meaning" LIKE '%在…上%');

UPDATE "meaning_item"
SET "popularity" = 6, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'on')
  AND "meaning" = '关于';

-- 7. at: 核心方位介词（在；在…处）为 1，次生义（向）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在；在…处', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'at')
  AND ("meaning" = '在' OR "meaning" = '在；在…处');

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'at')
  AND "meaning" = '向';

-- 8. for: 核心对象介词（为了；给）为 1，次生连词义（因为）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '为了；给', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'for')
  AND ("meaning" = '为' OR "meaning" = '为了；给');

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'for')
  AND "meaning" = '因为';

-- 9. from: 核心来源介词（从；来自）为 1，次生义（由于）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '从；来自', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'from')
  AND ("meaning" = '来自' OR "meaning" = '从；来自');

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'from')
  AND "meaning" = '由于';

-- 10. of: 核心所属介词（…的）为 1，次生义（关于）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'of')
  AND "meaning" = '的';

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'of')
  AND "meaning" = '关于';

-- 11. with: 核心伴随介词（和…一起；用；随着）为 1
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '和…一起；用；随着', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'with')
  AND ("meaning" = '和' OR "meaning" = '和…一起；用；随着');

UPDATE "meaning_item"
SET "popularity" = 6, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'with')
  AND "meaning" = '随着';

-- 12. like: 核心喜好动词（喜欢）为 1，介词（像）为 2
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'like')
  AND "meaning" = '喜欢';

UPDATE "meaning_item"
SET "popularity" = 2, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'like')
  AND "meaning" = '像';

-- 13. meet: 核心相遇动词（遇见；相遇）为 1，引申义（满足需求）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '遇见；相遇', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'meet')
  AND ("meaning" = '遇见' OR "meaning" = '遇见；相遇');

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'meet')
  AND "meaning" = '满足';

-- 14. study: 核心学业动作（学习）为 1，学术名词（研究）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'study')
  AND "meaning" = '学习';

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'study')
  AND "meaning" = '研究';

-- 15. beside: 核心空间介词（在…旁边）为 1，次生比喻义（与…相比）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'beside')
  AND "meaning" LIKE '%旁边%';

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'beside')
  AND "meaning" LIKE '%相比%';

-- 16. behind: 核心空间介词（在…后面）为 1，次生义（落后于）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'behind')
  AND "meaning" LIKE '%后面%';

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'behind')
  AND "meaning" LIKE '%落后%';

-- 17. beneath: 核心空间介词（在…下方；在…之下）为 1，次生比喻义（不值得）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在…下方；在…之下', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'beneath')
  AND ("meaning" LIKE '%在%下%' OR "meaning" LIKE '%在…下%');

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'beneath')
  AND "meaning" LIKE '%不值得%';

-- 18. over: 核心空间介词（在…上方；越过）为 1，形容词义（结束）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '在…上方；越过', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'over')
  AND ("meaning" LIKE '%在%上方%' OR "meaning" LIKE '%在…上方%');

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'over')
  AND "meaning" = '结束';

-- 19. radio: 日常词汇（收音机）为 1，科技术语全称（无线电设备）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'radio')
  AND "meaning" = '收音机';

UPDATE "meaning_item"
SET "popularity" = 3, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'radio')
  AND "meaning" = '无线电设备';

-- 20. star: 日常意象（星星；明星）为 1，天文学术语（恒星）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '星星；明星', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'star')
  AND ("meaning" = '明星' OR "meaning" = '星星；明星');

UPDATE "meaning_item"
SET "popularity" = 4, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'star')
  AND "meaning" = '恒星';

-- 21. woman: 日常通俗（女人；妇女）为 1，生僻学术释义（成年女子）降至其后
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '女人；妇女', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'woman')
  AND ("meaning" = '妇女' OR "meaning" = '女人；妇女');

UPDATE "meaning_item"
SET "popularity" = 3, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'woman')
  AND "meaning" = '成年女子';

-- 22. to: 核心介词（到；向；朝）为 1
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '到；向；朝', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'to')
  AND ("meaning" = '到' OR "meaning" = '到；向；朝');

UPDATE "meaning_item"
SET "popularity" = 5, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'to')
  AND "meaning" = '向';

-- 23. class: 核心教学词（班级；课）为 1，课调为 2
UPDATE "meaning_item"
SET "popularity" = 1, "meaning" = '班级；课；阶级', "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'class')
  AND ("meaning" = '班级' OR "meaning" = '班级；课；阶级');

UPDATE "meaning_item"
SET "popularity" = 2, "update_time" = now()
WHERE "dict_id" = '0' 
  AND "word_id" = (SELECT "id" FROM "word" WHERE "spell" = 'class')
  AND "meaning" = '课';

COMMIT;

