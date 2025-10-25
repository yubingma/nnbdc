-- 为dict表添加popularityLimit字段
-- 该字段用于过滤展示给用户的单词释义，如果某个单词没有该dict的定制释义，
-- 从而只能使用通用词典释义时，popularity大于该设定的通用词典释义项会被用户隐藏
ALTER TABLE dict ADD COLUMN popularityLimit INT NULL COMMENT '过滤展示给用户的通用词典单词释义的popularity阈值';
