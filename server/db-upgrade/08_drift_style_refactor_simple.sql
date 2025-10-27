

-- 2. 修改字段名为驼峰格式


-- 修改user表字段名（只修改下划线字段）
ALTER TABLE user CHANGE COLUMN wechat_open_id wechatOpenId VARCHAR(100);
ALTER TABLE user CHANGE COLUMN wechat_union_id wechatUnionId VARCHAR(100);
ALTER TABLE user CHANGE COLUMN wechat_nickname wechatNickname VARCHAR(200);
ALTER TABLE user CHANGE COLUMN wechat_avatar wechatAvatar VARCHAR(500);

-- 修改idGens表字段名
ALTER TABLE id_gen CHANGE COLUMN next_val nextVal BIGINT;
ALTER TABLE id_gen CHANGE COLUMN sequence_name sequenceName VARCHAR(50);

-- 修改learningWords表字段名
ALTER TABLE learning_word CHANGE COLUMN AddDay addDay INT;
ALTER TABLE learning_word CHANGE COLUMN AddTime addTime DATETIME(6);
ALTER TABLE learning_word CHANGE COLUMN LastLearningDate lastLearningDate DATETIME(6);
ALTER TABLE learning_word CHANGE COLUMN LearningOrder learningOrder INT;
ALTER TABLE learning_word CHANGE COLUMN LifeValue lifeValue INT;

-- 修改sentences表字段名
ALTER TABLE sentence CHANGE COLUMN chinese_raw chineseRaw VARCHAR(300);
ALTER TABLE sentence CHANGE COLUMN English english VARCHAR(300);
ALTER TABLE sentence CHANGE COLUMN english_raw englishRaw VARCHAR(300);
ALTER TABLE sentence CHANGE COLUMN LastDiyUpdateTime lastDiyUpdateTime DATETIME(6);
ALTER TABLE sentence CHANGE COLUMN temp_sound_url tempSoundUrl VARCHAR(500);
ALTER TABLE sentence CHANGE COLUMN TheType theType VARCHAR(45);

-- 修改sentenceChineses表字段名
ALTER TABLE sentence_chinese CHANGE COLUMN sentenceID sentenceId VARCHAR(32);

-- 修改studyGroupAndManagerLinks表字段名
ALTER TABLE study_group_and_manager_link CHANGE COLUMN groupID groupId VARCHAR(32);

-- 修改sysDbLogs表字段名
ALTER TABLE sys_db_log CHANGE COLUMN record_id recordId VARCHAR(131);
ALTER TABLE sys_db_log CHANGE COLUMN table_ tblName VARCHAR(50);

-- 修改userDbLogs表字段名
ALTER TABLE user_db_log CHANGE COLUMN table_ tblName VARCHAR(50);
ALTER TABLE user_db_log CHANGE COLUMN record record TEXT;

-- 修改userStudySteps表字段名
ALTER TABLE user_study_step CHANGE COLUMN index_ seq INT;

-- 3. 验证重构结果
-- 查看所有表名
SHOW TABLES;

-- 查看主要表结构
DESCRIBE user;
DESCRIBE word;
DESCRIBE dict;
