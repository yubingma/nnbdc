-- ============================================
-- 系统数据增量同步表结构
-- 创建时间：2025-10-18
-- 用途：支持UGC内容（Sentences、WordImages、WordShortDescChinese）增量同步
-- ============================================

-- 1. 全局系统数据版本表（单例表）
CREATE TABLE IF NOT EXISTS sys_db_version (
    id VARCHAR(36) PRIMARY KEY DEFAULT 'singleton' COMMENT '固定为singleton，单例表',
    version INT NOT NULL DEFAULT 1 COMMENT '当前全局版本号',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='系统数据库版本表（单例）';

-- 初始化版本记录（version=1表示系统已初始化，有静态数据可同步）
-- 前端新安装时本地版本为0，远程版本为1，触发首次全量同步
INSERT INTO sys_db_version (id, version, createTime) 
VALUES ('singleton', 1, NOW())
ON DUPLICATE KEY UPDATE id=id;

-- 2. 系统数据变更日志表
CREATE TABLE IF NOT EXISTS sys_db_log (
    id VARCHAR(36) PRIMARY KEY COMMENT '日志ID',
    version INT NOT NULL COMMENT '日志版本号（递增）',
    operate VARCHAR(20) NOT NULL COMMENT '操作类型：INSERT/UPDATE/DELETE',
    table_ VARCHAR(50) NOT NULL COMMENT '表名：word_image/sentence/word_shortdesc_chinese',
    record_id VARCHAR(131) NOT NULL COMMENT '记录ID',
    record TEXT NOT NULL COMMENT '记录内容（JSON格式）',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间',
    INDEX idx_version (version) COMMENT '按版本查询增量日志',
    INDEX idx_table_record (table_, record_id) COMMENT '查重和查找特定记录'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='系统数据变更日志表';



delete from sys_param where paramName='systemDbVersion';

ALTER TABLE bdc.user 
ADD COLUMN asrPassRule VARCHAR(10) 
COMMENT 'ASR答对判定规则：ONE/HALF/ALL';
-- 如果字段已存在，上面语句会报错，可忽略该错误继续执行后续语句

-- 2. 创建user_oper表（用户操作历史记录表）
CREATE TABLE IF NOT EXISTS bdc.user_oper (
    id VARCHAR(32) NOT NULL COMMENT '主键ID',
    userId VARCHAR(32) NOT NULL COMMENT '用户ID',
    operType VARCHAR(20) NOT NULL COMMENT '操作类型：LOGIN、START_LEARN、DAKA等',
    operTime DATETIME NOT NULL COMMENT '操作时间',
    remark VARCHAR(200) COMMENT '备注信息',
    createTime DATETIME NOT NULL COMMENT '创建时间',
    updateTime DATETIME COMMENT '更新时间',
    PRIMARY KEY (id),
    INDEX idx_userId_operTime (userId, operTime) COMMENT '按用户和时间查询',
    INDEX idx_operType (operType) COMMENT '按操作类型查询',
    CONSTRAINT fk_user_oper_user FOREIGN KEY (userId) REFERENCES user (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin COMMENT='用户操作历史记录表';

-- 创建user_db_version表
CREATE TABLE IF NOT EXISTS user_db_version (
    id VARCHAR(32) NOT NULL,
    userId VARCHAR(32) NOT NULL,
    version INT NOT NULL DEFAULT 0,
    createTime DATETIME NOT NULL,
    updateTime DATETIME ,
    PRIMARY KEY (id),
    UNIQUE KEY unique_userId (userId),
    CONSTRAINT fk_user_db_version_user FOREIGN KEY (userId) REFERENCES user (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_bin;

ALTER TABLE user DROP COLUMN dbVersion;
DROP TABLE IF EXISTS user_stage_word; 


delete from user_study_step uss where uss.studyStep  != 'Meaning' and uss.studyStep != 'Word' ;

ALTER TABLE bdc.`user` DROP COLUMN passIfSpeakOutOneMeaning;

ALTER TABLE bdc.user_db_log MODIFY COLUMN recordId varchar(131) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL;

-- 重命名 dict_word 表的 md5IndexNo 列为 seq
-- 1. 删除旧索引
DROP INDEX idx_dict_md5index ON bdc.dict_word;

-- 2. 重命名列
ALTER TABLE bdc.dict_word CHANGE COLUMN md5IndexNo seq INT NULL COMMENT '单词在单词书中的顺序号，从1开始';

-- 3. 创建新索引
CREATE INDEX idx_dict_seq ON bdc.dict_word (dictId, seq);

-- 重命名 learning_dict 表的 CurrentWordOrder 列为 CurrentWordSeq
ALTER TABLE bdc.learning_dict CHANGE COLUMN CurrentWordOrder currentWordSeq INT NULL COMMENT '当前已取词位置';

-- 删除第三方登录相关字段
ALTER TABLE bdc.`user` DROP COLUMN  fanlaiName;
ALTER TABLE bdc.`user` DROP COLUMN  fanlaiNickName;
ALTER TABLE bdc.`user` DROP COLUMN  fanlaiUserName;
ALTER TABLE bdc.`user` DROP COLUMN  m360FigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  m360NickName;
ALTER TABLE bdc.`user` DROP COLUMN  m360UserID;
ALTER TABLE bdc.`user` DROP COLUMN  qplusFigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  qplusNickName;
ALTER TABLE bdc.`user` DROP COLUMN  qplusOpenKey;
ALTER TABLE bdc.`user` DROP COLUMN  qplusPlatform;
ALTER TABLE bdc.`user` DROP COLUMN  qplusPlatformKey;
ALTER TABLE bdc.`user` DROP COLUMN  qplusUserID;
ALTER TABLE bdc.`user` DROP COLUMN  qqAccessToken;
ALTER TABLE bdc.`user` DROP COLUMN  qqFigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  qqNickName;
ALTER TABLE bdc.`user` DROP COLUMN  qqOpenID;
ALTER TABLE bdc.`user` DROP COLUMN  renrenFigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  renrenNickName;
ALTER TABLE bdc.`user` DROP COLUMN  renrenUserID;
ALTER TABLE bdc.`user` DROP COLUMN  tencentWeiBoAccessToken;
ALTER TABLE bdc.`user` DROP COLUMN  tencentWeiBoNickName;
ALTER TABLE bdc.`user` DROP COLUMN  tencentWeiBoOpenKey;
ALTER TABLE bdc.`user` DROP COLUMN  tencentWeiBoUserID;
ALTER TABLE bdc.`user` DROP COLUMN  tencentWeiBoUserName;
ALTER TABLE bdc.`user` DROP COLUMN  wbAccessToken;
ALTER TABLE bdc.`user` DROP COLUMN  wbFigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  wbNickName;
ALTER TABLE bdc.`user` DROP COLUMN  wbUserID;
ALTER TABLE bdc.`user` DROP COLUMN  xiaoAppFigureUrl;
ALTER TABLE bdc.`user` DROP COLUMN  xiaoAppNickName;
ALTER TABLE bdc.`user` DROP COLUMN  xiaoAppOpenId;

-- 添加微信登录相关字段
ALTER TABLE bdc.`user` ADD COLUMN wechat_open_id VARCHAR(100) NULL COMMENT '微信OpenID' AFTER email;
ALTER TABLE bdc.`user` ADD COLUMN wechat_union_id VARCHAR(100) NULL COMMENT '微信UnionID' AFTER wechat_open_id;
ALTER TABLE bdc.`user` ADD COLUMN wechat_nickname VARCHAR(200) NULL COMMENT '微信昵称' AFTER wechat_union_id;
ALTER TABLE bdc.`user` ADD COLUMN wechat_avatar VARCHAR(500) NULL COMMENT '微信头像URL' AFTER wechat_nickname;

-- 为wechat_open_id添加唯一索引
CREATE UNIQUE INDEX idx_wechat_open_id ON bdc.`user` (wechat_open_id);

-- ========================================
-- 修复所有表的createTime字段：
-- 1. 将NULL值设为 '2000-01-01 00:00:00'
-- 2. 修改字段为 NOT NULL
-- ========================================

-- 修复并设置NOT NULL约束
UPDATE bdc.dict SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.dict_group SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict_group MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.dict_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.learning_dict SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.learning_dict MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.learning_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.learning_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.mastered_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.mastered_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.meaning_item SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.meaning_item MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sentence SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sentence MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word_image SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word_image MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.synonym SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.synonym MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.verb_tense SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.verb_tense MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.cigen SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.cigen MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.cigen_word_link SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.cigen_word_link MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.level SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.level MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_db_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_db_log MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_db_version SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_db_version MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_study_step SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_study_step MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.daka SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.daka MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_oper SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_oper MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_cow_dung_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_cow_dung_log MODIFY COLUMN createTime DATETIME NOT NULL;

-- ========================================
-- 修复所有表的createTime字段：
-- 1. 将NULL值设为 '2000-01-01 00:00:00'
-- 2. 修改字段为 NOT NULL
-- ========================================

-- 修复并设置NOT NULL约束
UPDATE bdc.dict SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.dict_group SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict_group MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.dict_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.dict_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.learning_dict SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.learning_dict MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.learning_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.learning_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.mastered_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.mastered_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.meaning_item SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.meaning_item MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sentence SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sentence MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word_image SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word_image MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.synonym SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.synonym MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.verb_tense SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.verb_tense MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.cigen SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.cigen MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.cigen_word_link SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.cigen_word_link MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.level SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.level MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_db_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_db_log MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_db_version SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_db_version MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_study_step SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_study_step MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.daka SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.daka MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_oper SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_oper MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_cow_dung_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_cow_dung_log MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.user_wrong_word SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.user_wrong_word MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.book_mark SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.book_mark MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.msg SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.msg MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sys_db_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sys_db_log MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sys_db_version SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sys_db_version MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word_shortdesc_chinese SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word_shortdesc_chinese MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.book_mark SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.book_mark MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.msg SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.msg MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sys_db_log SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sys_db_log MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.sys_db_version SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.sys_db_version MODIFY COLUMN createTime DATETIME NOT NULL;

UPDATE bdc.word_shortdesc_chinese SET createTime = '2000-01-01 00:00:00' WHERE createTime IS NULL;
ALTER TABLE bdc.word_shortdesc_chinese MODIFY COLUMN createTime DATETIME NOT NULL;

-- ========================================
-- 将通用词典从虚拟ID改为实际数据库记录
-- 说明：通用词典之前使用虚拟ID "0"，释义项的dictId为NULL
-- 本脚本将：
-- 1. 在dict表中创建id='0'的通用词典记录
-- 2. 将所有meaning_item表中dictId为NULL的记录更新为'0'
-- ========================================

-- 步骤1：在dict表中插入通用词典记录
-- 检查是否已存在，避免重复插入
INSERT INTO bdc.dict (id, name, owner, isShared, isReady, visible, wordCount, createTime, updateTime)
SELECT '0', '通用词典.dict', '15118', 1, 1, 1, 
       (SELECT COUNT(DISTINCT word) FROM bdc.meaning_item WHERE dictId IS NULL),
       '2000-01-01 00:00:00', 
       NOW()
WHERE NOT EXISTS (SELECT 1 FROM bdc.dict WHERE id = '0');

-- 步骤2：更新meaning_item表，将dictId为NULL的记录更新为'0'
-- 这是核心迁移步骤，将虚拟的通用词典ID变为实际的
UPDATE bdc.meaning_item 
SET dictId = '0' 
WHERE dictId IS NULL;

-- 步骤3：验证数据迁移
-- 执行后应该没有dictId为NULL的记录了
SELECT 
    '迁移验证' as status,
    (SELECT COUNT(*) FROM bdc.meaning_item WHERE dictId IS NULL) as null_count,
    (SELECT COUNT(*) FROM bdc.meaning_item WHERE dictId = '0') as common_dict_count,
    (SELECT COUNT(*) FROM bdc.dict WHERE id = '0') as dict_record_count;

-- ========================================
-- 为通用词典创建 dict_word 记录
-- 说明：将通用词典与普通词书统一，为所有有通用释义的单词创建 dict_word 记录
-- ========================================

-- 步骤1：为通用词典中的所有单词创建 dict_word 记录
-- 按单词拼写排序，自动生成序号
INSERT INTO bdc.dict_word (dictId, wordId, seq, createTime, updateTime)
SELECT 
    '0' as dictId,
    w.id as wordId,
    (@row_number := @row_number + 1) as seq,
    NOW() as createTime,
    NOW() as updateTime
FROM 
    bdc.word w,
    (SELECT @row_number := 0) as init
WHERE 
    EXISTS (
        SELECT 1 
        FROM bdc.meaning_item mi 
        WHERE mi.word = w.id AND mi.dictId = '0'
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM bdc.dict_word dw 
        WHERE dw.dictId = '0' AND dw.wordId = w.id
    )
ORDER BY w.spell;

-- 步骤2：更新通用词典的 wordCount 字段为实际单词数
UPDATE bdc.dict 
SET wordCount = (
    SELECT COUNT(*) 
    FROM bdc.dict_word 
    WHERE dictId = '0'
),
updateTime = NOW()
WHERE id = '0';

-- 步骤3：验证数据
SELECT 
    '通用词典dict_word记录数' as item,
    COUNT(*) as count
FROM bdc.dict_word 
WHERE dictId = '0'
UNION ALL
SELECT 
    '通用词典wordCount' as item,
    wordCount as count
FROM bdc.dict 
WHERE id = '0'
UNION ALL
SELECT 
    '通用词典释义项涉及的单词数' as item,
    COUNT(DISTINCT word) as count
FROM bdc.meaning_item 
WHERE dictId = '0';

-- 全量重命名外键列为 *Id 结尾，确保命名统一
-- 目标数据库：bdc（按项目现有脚本惯例）

-- meaning_item
ALTER TABLE bdc.meaning_item CHANGE COLUMN word wordId VARCHAR(32) NOT NULL;

-- dict
ALTER TABLE bdc.dict CHANGE COLUMN owner ownerId VARCHAR(32) NOT NULL;

-- study_group
ALTER TABLE bdc.study_group CHANGE COLUMN grade gradeId VARCHAR(32) NOT NULL;
ALTER TABLE bdc.study_group CHANGE COLUMN creator creatorId VARCHAR(32) NOT NULL;

-- learning_dict
ALTER TABLE bdc.learning_dict CHANGE COLUMN currentWord currentWordId VARCHAR(32);

-- dict_group
ALTER TABLE bdc.dict_group CHANGE COLUMN parent parentId VARCHAR(32);

-- sentence
ALTER TABLE bdc.sentence CHANGE COLUMN author authorId VARCHAR(32) NOT NULL;

-- study_group_post
ALTER TABLE bdc.study_group_post CHANGE COLUMN postCreator postCreatorId VARCHAR(32) NOT NULL;

-- study_group_post_reply
ALTER TABLE bdc.study_group_post_reply CHANGE COLUMN postReplyer postReplyerId VARCHAR(32) NOT NULL;

-- forum_post
ALTER TABLE bdc.forum_post CHANGE COLUMN postCreator postCreatorId VARCHAR(32) NOT NULL;

-- forum_post_reply
ALTER TABLE bdc.forum_post_reply CHANGE COLUMN postReplyer postReplyerId VARCHAR(32) NOT NULL;

-- game_hall
ALTER TABLE bdc.game_hall CHANGE COLUMN dictGroup dictGroupId VARCHAR(32) NOT NULL;
ALTER TABLE bdc.game_hall CHANGE COLUMN hallGroup hallGroupId VARCHAR(32) NOT NULL;

-- msg
ALTER TABLE bdc.msg CHANGE COLUMN fromUser fromUserId VARCHAR(32) NOT NULL;
ALTER TABLE bdc.msg CHANGE COLUMN toUser toUserId VARCHAR(32) NOT NULL;

-- word_shortdesc_chinese
ALTER TABLE bdc.word_shortdesc_chinese CHANGE COLUMN author authorId VARCHAR(32) NOT NULL;

-- word_image
ALTER TABLE bdc.word_image CHANGE COLUMN author authorId VARCHAR(32) NOT NULL;

-- similar_word（中间表）
ALTER TABLE bdc.similar_word CHANGE COLUMN word wordId VARCHAR(32) NOT NULL;
ALTER TABLE bdc.similar_word CHANGE COLUMN similarWord similarWordId VARCHAR(32) NOT NULL;

ALTER TABLE bdc.user CHANGE COLUMN invitedBy invitedById VARCHAR(32);
update bdc.user set level = '1' where level is null;
ALTER TABLE bdc.user CHANGE COLUMN level levelId VARCHAR(32) not null;

-- 为dict表添加popularityLimit字段
-- 该字段用于过滤展示给用户的单词释义，如果某个单词没有该dict的定制释义，
-- 从而只能使用通用词典释义时，popularity大于该设定的通用词典释义项会被用户隐藏
ALTER TABLE dict ADD COLUMN popularityLimit INT NULL COMMENT '过滤展示给用户的通用词典单词释义的popularity阈值';


-- 为msg表添加clientType字段
ALTER TABLE msg ADD COLUMN clientType VARCHAR(20) NULL;

-- 添加索引以提高查询性能
CREATE INDEX idx_msg_client_type ON msg(clientType);




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
