-- Upgrade database to rename AI rate limit params to reflect concurrency and add referee params (v51)

-- 1. Rename existing AI Chat limits (to support concurrency renaming)
UPDATE sys_param SET param_name = 'AiChatGlobalConcurrencyLimit', comment = 'AI 聊天全局并发上限', update_time = CURRENT_TIMESTAMP WHERE param_name = 'AiChatGlobalLimit';
UPDATE sys_param SET param_name = 'AiChatUserConcurrencyLimit', comment = 'AI 聊天单用户并发上限', update_time = CURRENT_TIMESTAMP WHERE param_name = 'AiChatUserLimit';

-- 2. Insert AI Referee parameters
DELETE FROM sys_param WHERE param_name IN ('AiRefereeGlobalConcurrencyLimit', 'AiRefereeUserConcurrencyLimit', 'AiRefereeUserDailyLimit');

INSERT INTO sys_param (param_name, param_value, comment, create_time, update_time) VALUES 
('AiRefereeGlobalConcurrencyLimit', '30', 'AI 裁判全局并发上限', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('AiRefereeUserConcurrencyLimit', '5', 'AI 裁判单用户并发上限', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('AiRefereeUserDailyLimit', '100', 'AI 裁判单用户每日次数上限', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
