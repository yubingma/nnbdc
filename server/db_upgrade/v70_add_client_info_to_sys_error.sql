-- sys_error 增加"上报客户端"信息：客户端上报的异常（同步失败、数据不自洽等）需要带上
-- 是"哪一端、哪一版"出的，否则拿到告警无法判断是不是某个平台/某个版本集中出现的问题
-- （这类坏数据往往集中在单一版本上）。
ALTER TABLE sys_error ADD COLUMN IF NOT EXISTS client_version VARCHAR(32);
ALTER TABLE sys_error ADD COLUMN IF NOT EXISTS client_type VARCHAR(20);

COMMENT ON COLUMN sys_error.client_version IS '上报客户端的版本号（客户端 buildNumber，如 26092401）；服务端自身产生或旧版客户端未上报时为空';
COMMENT ON COLUMN sys_error.client_type IS '上报客户端的平台类型：android/ios/macos/windows/linux/browser；服务端自身产生或旧版客户端未上报时为空';

-- 历史记录回填：把 details 里已有的 "客户端版本=xxx" 提取出来（旧版未上报的留空）
UPDATE sys_error
SET client_version = substring(details from '客户端版本=([^ \r\n]+)')
WHERE client_version IS NULL
  AND details LIKE '%客户端版本=%';
