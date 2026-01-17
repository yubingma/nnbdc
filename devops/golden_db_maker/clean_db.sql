-- 清理脚本：将含有通用词典的数据库转换为“黄金母版”
-- 运行方法：sqlite3 path/to/db.sqlite < clean_db.sql

-- 1. 清理用户相关表 (User Profile & State)
DELETE FROM users;
DELETE FROM user_db_logs;
DELETE FROM user_db_versions;
DELETE FROM local_exceptions;

-- 2. 清理用户学习记录 (Learning Progress)
DELETE FROM learning_dicts;
DELETE FROM learning_words;
DELETE FROM mastered_words;
DELETE FROM user_study_steps;
DELETE FROM user_wrong_words;
DELETE FROM user_cow_dung_logs;
DELETE FROM book_marks;

-- 3. 清理用户行为/互动记录 (Interactions)
DELETE FROM dakas; -- 打卡
DELETE FROM user_opers; -- 操作日志
DELETE FROM voted_sentences;
DELETE FROM voted_word_images;

-- 4. 重置本地参数 (Local Settings)
DELETE FROM local_params;
-- 重新插入默认值
INSERT INTO local_params (name, value) VALUES ('isDarkMode', 'false');

-- 5. 保留但需注意的表
-- user_cow_dung_logs (已删)
-- sys_db_version (保留，用于后续增量更新检查)
-- dicts (保留，这是核心内容)
-- words, dict_words, meaning_items, sentences (保留)
-- dict_groups, group_and_dict_links (保留)

-- 6. 物理压缩数据库文件，释放删除数据占用的空间
VACUUM;
