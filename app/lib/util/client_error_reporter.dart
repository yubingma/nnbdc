import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';

import 'client_type.dart';
import 'study_consistency_checker.dart';

/// 客户端异常上报服务端的唯一入口。
///
/// 落到服务端 `sys_error` 表（`POST /reportSysError.do`）→ 管理端「服务端异常日志」页，
/// 并按分类触发告警邮件（服务端对每个分类独立节流）。一律带上平台与版本：
/// 这类问题往往集中在某一端某一版上，缺了这两列拿到告警也无法定性。
///
/// 旁路、静默失败：上报只负责把现场留下来，不改变任何业务行为，也不因自己失败影响主流程。
/// **是否限流由调用方决定** —— 同一台设备反复重试同一件事，不该把服务端告警刷屏。
///
/// 与 `ErrorHandler._recordExceptionToDb` 的分工：那条只把异常留在本机（客户手机上根本看不到），
/// 这条才让它到达服务端。本函数也不做"记录本地"这件事，两者互不替代。
Future<void> reportClientError({
  required String errorType,
  required String details,
}) async {
  try {
    final userId = Global.getLoggedInUser()?.id;
    final clientVersion = await resolveClientVersion();
    final clientType = getClientType().name;
    await Api.client.reportSysError(
        userId, errorType, details, clientVersion, clientType);
    Global.logger.d(
        '🚀 [SysError] 已上报服务端: $errorType ($clientType / $clientVersion)');
  } catch (e) {
    Global.logger.w('⚠️ [SysError] 上报服务端失败（静默忽略）: $e');
  }
}
