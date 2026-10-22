-- 内容开关：是否隐藏中小学教育类内容（K12 词书分组与游戏大厅）。
--
-- 背景：小米应用商店把"含中小学教材词书"的应用判定为特殊行业（中小学教育类），
-- 要求提供省级教育行政部门的教育移动应用备案（app.eduyun.cn）。
-- 审核期间可将本参数置为 true 全局隐藏 K12 内容，过审后再置回 false。
--
-- 客户端每次启动拉取一次（GET /getHideK12Content.do），缓存到本地后决定是否过滤：
--   select_book.dart  隐藏「小学 / 初中 / 高中」三个词书一级分组
--   game.dart         隐藏同名游戏大厅分组
INSERT INTO "sys_param" ("param_name", "param_value", "comment", "create_time", "update_time")
VALUES ('hideK12Content', 'true', '是否在小米渠道隐藏中小学教育类内容（K12 词书分组与游戏大厅），true 隐藏 / false 显示', now(), now())
ON CONFLICT ("param_name") DO NOTHING;
