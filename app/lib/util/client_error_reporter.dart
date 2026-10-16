import 'package:flutter/foundation.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';

import 'client_type.dart';
import 'study_consistency_checker.dart';

// ============================================================
// 上报分类
//
// 按"故障域"划分，而不是按调用点：服务端按分类独立节流、各自发告警邮件，
// 分得太细会让每一类都占一个 5 分钟窗口，把真正要紧的那类淹掉。
// 具体是哪个场景（"准备学习单词"还是"下载用户词书"）写在 details 里，
// 由 [reportClientFailure] 的 scene 参数负责聚合与去重。
// ============================================================

/// 崩溃与未捕获异常：框架错误、平台/异步错误、Zone 未捕获异常
const String kClientCrashErrorType = 'CLIENT_CRASH';

/// 本地数据库故障：读写失败、外键约束、表缺失、迁移与重建失败
const String kClientDbErrorType = 'CLIENT_DB_ERROR';

/// 网络请求失败（服务端按"瞬时网络抖动"处理：只落库、不发告警邮件）
const String kClientNetworkErrorType = 'CLIENT_NETWORK_ERROR';

/// 发音 / TTS / 音效失败（用户侧表现为"点了喇叭没声音"）
const String kClientAudioErrorType = 'CLIENT_AUDIO_ERROR';

/// 订阅与支付失败（涉及钱，单独归类便于一眼分辨）
const String kClientPaymentErrorType = 'CLIENT_PAYMENT_ERROR';

/// 其余功能失败：取词、词书下载、手写识别、上传等（[reportClientFailure] 的默认分类）
const String kClientFeatureErrorType = 'CLIENT_FEATURE_ERROR';

/// 客户端异常上报服务端的唯一入口。
///
/// 落到服务端 `sys_error` 表（`POST /reportSysError.do`）→ 管理端「服务端异常日志」页，
/// 并按分类触发告警邮件（服务端对每个分类独立节流）。一律带上平台与版本：
/// 这类问题往往集中在某一端某一版上，缺了这两列拿到告警也无法定性。
///
/// 旁路、静默失败：上报只负责把现场留下来，不改变任何业务行为，也不因自己失败影响主流程。
/// 量大会刷屏的场景请改用 [reportClientFailure]（它自带去重与当日上限）。
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

/// 上报一次客户端功能故障，自带两道闸门。
///
/// [scene] 是现场能看懂的短名（如 `准备学习单词`、`下载用户词书`），
/// 它既写进 details，也是去重与聚合的维度：同一个场景同一天只报一条。
///
/// 两道闸门缺一不可 —— 这类故障一旦出现就是成批的（本地库坏掉时同一个场景会连着失败几十次），
/// 不设闸门会瞬间把服务端刷屏、把真正要处理的告警淹掉：
/// 1. 按「分类 + 业务日 + 场景」去重；
/// 2. 每个分类每个业务日的总条数上限。
Future<void> reportClientFailure({
  required String errorType,
  required String scene,
  required String details,
}) async {
  if (claimClientReportSlot(errorType, scene) == null) return;
  await reportClientError(
    errorType: errorType,
    details: '场景=$scene\n$details',
  );
}

/// 每个分类每个业务日最多上报多少条，避免成批故障把服务端刷屏
@visibleForTesting
const int maxClientReportsPerCategoryPerDay = 10;

/// 本次会话内已上报过的「分类|业务日|场景」，同一条故障只报一次
final Set<String> _reportedKeys = {};

/// 各分类今天已上报的条数（跨天自动重置）
final Map<String, int> _reportsTodayByCategory = {};
String? _reportBusinessDay;

/// 领取一次上报额度：按「分类 + 业务日 + 场景」去重，并对每个分类设当日总量上限。
/// 返回 null 表示这次不该报（重复，或该分类当日已达上限）。
@visibleForTesting
String? claimClientReportSlot(String category, String scene) {
  final businessDay =
      DateUtils.businessDayStart(AppClock.now()).toIso8601String();
  if (_reportBusinessDay != businessDay) {
    _reportBusinessDay = businessDay;
    _reportsTodayByCategory.clear();
    _reportedKeys.clear();
  }

  final dedupeKey = '$category|$businessDay|$scene';
  if (_reportedKeys.contains(dedupeKey)) return null;
  final reportedToday = _reportsTodayByCategory[category] ?? 0;
  if (reportedToday >= maxClientReportsPerCategoryPerDay) {
    Global.logger.d('📊 [SysError] 分类 $category 本业务日上报已达上限，跳过: $scene');
    return null;
  }
  _reportedKeys.add(dedupeKey);
  _reportsTodayByCategory[category] = reportedToday + 1;
  return dedupeKey;
}
