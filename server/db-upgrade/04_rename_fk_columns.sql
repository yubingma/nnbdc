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



