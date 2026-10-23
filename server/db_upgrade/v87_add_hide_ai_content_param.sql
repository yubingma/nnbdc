-- 内容开关：是否隐藏 AI 能力（AI 助教对话、AI 短文、单词解释）。
--
-- 背景：小米应用商店把"应用内容和功能属于深度合成类"的应用判定为特殊行业，
-- 要求提供全国互联网安全管理服务平台审批截图、算法备案与大模型备案。
-- 审核期间可将本参数置为 true 隐藏 AI 能力，过审后再置回 false。
--
-- 客户端每次启动拉取一次（GET /getHideAiContent.do），缓存到本地后决定是否隐藏：
--   word_detail.dart  隐藏「AI 助教」Tab 与 AI 讲解抽屉
--   word_list.dart    隐藏「AI 短文」菜单项
--   me.dart           隐藏「本地 AI 模型配置」入口
--
-- 与 hideK12Content 同一套厂商白名单：白名单品牌（华为/荣耀/OPPO/vivo/三星/魅族）
-- 与非 Android 平台永远显示，小米系、云真机等由本开关决定。
INSERT INTO "sys_param" ("param_name", "param_value", "comment", "create_time", "update_time")
VALUES ('hideAiContent', 'true', '是否在小米渠道隐藏 AI 能力（AI 助教对话、AI 短文、单词解释），true 隐藏 / false 显示', now(), now())
ON CONFLICT ("param_name") DO NOTHING;
