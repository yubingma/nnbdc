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

