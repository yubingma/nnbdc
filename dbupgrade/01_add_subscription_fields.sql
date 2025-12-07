-- 数据库升级脚本：添加iOS订阅相关字段
-- 版本：从当前版本升级到支持订阅功能
-- 日期：2025-12-07
-- 说明：添加iOS平台的订阅字段（Android平台订阅待未来实现）

-- 添加iOS订阅字段
ALTER TABLE `user` 
ADD COLUMN `isPremiumIOS` TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'iOS是否为会员' AFTER `enableAllWrong`;

ALTER TABLE `user` 
ADD COLUMN `subscriptionExpireDateIOS` DATETIME NULL COMMENT 'iOS订阅到期时间' AFTER `isPremiumIOS`;

ALTER TABLE `user` 
ADD COLUMN `subscriptionTypeIOS` VARCHAR(20) NULL COMMENT 'iOS订阅类型：monthly/annual' AFTER `subscriptionExpireDateIOS`;

ALTER TABLE `user` 
ADD COLUMN `subscriptionStatusIOS` VARCHAR(20) NULL COMMENT 'iOS订阅状态：active/expired/cancelled' AFTER `subscriptionTypeIOS`;

ALTER TABLE `user` 
ADD COLUMN `lastReceiptDataIOS` TEXT NULL COMMENT 'iOS最后验证的收据数据（用于恢复购买）' AFTER `subscriptionStatusIOS`;
