update user_study_step set studyStep = 'En2Ch' where studyStep = 'Word';
update user_study_step set studyStep = 'Ch2En' where studyStep = 'Meaning';

-- 创建需求墙举报表
CREATE TABLE IF NOT EXISTS `feature_request_report` (
  `id` VARCHAR(32) NOT NULL COMMENT '主键ID',
  `reporterId` VARCHAR(32) NOT NULL COMMENT '举报人ID',
  `featureRequestId` VARCHAR(32) NOT NULL COMMENT '被举报的需求ID',
  `content` VARCHAR(2000) NOT NULL COMMENT '举报内容',
  `createTime` DATETIME NOT NULL COMMENT '创建时间',
  `updateTime` DATETIME DEFAULT NULL COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_reporterId` (`reporterId`),
  KEY `idx_featureRequestId` (`featureRequestId`),
  KEY `idx_createTime` (`createTime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='需求墙举报表';