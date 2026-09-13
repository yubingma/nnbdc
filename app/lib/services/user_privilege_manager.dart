import 'package:flutter/foundation.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/subscription_util.dart';

/// 用户权限与能力管理器
/// 统一管理用户会员/身份状态到业务功能权限与配额（Capabilities / Permissions）的映射，
/// 将业务代码与底层订阅/支付/会员的具体判断解耦。
class UserPrivilegeManager {
  /// 测试专用覆盖项（null = 默认走底层判定）
  @visibleForTesting
  static bool? isPremiumOverrideForTesting;

  @visibleForTesting
  static bool? isIOSOverrideForTesting;

  /// 非会员每日单词上限
  static const int nonPremiumMaxDailyWords = 20;

  /// 会员无限制单词上限（逻辑极大值）
  static const int unlimitedDailyWords = 99999;

  /// 底层会员有效性判定（优先使用测试覆盖，默认代理至 SubscriptionUtil.isPremium()）
  static bool get isPremium => isPremiumOverrideForTesting ?? SubscriptionUtil.isPremium();

  /// 获取当前用户每日允许的最大单词数配额
  static int get maxDailyWords {
    return isPremium ? unlimitedDailyWords : nonPremiumMaxDailyWords;
  }

  /// 检查指定的每日单词数是否在当前用户配额允许范围内
  static bool isDailyWordsAllowed(int count) {
    return count <= maxDailyWords;
  }

  /// 规范化每日单词数（若超限则截断为允许的上限；非正数保持原样）
  static int sanitizeDailyWords(int requested) {
    if (requested <= 0) return requested;
    final limit = maxDailyWords;
    return requested > limit ? limit : requested;
  }

  /// 检查并强制执行会员限制（例如：非会员每日单词限额为 20）
  static Future<void> checkAndEnforceMemberLimits() async {
    final user = Global.getLoggedInUser();
    if (user == null || Global.isGuest) {
      return;
    }

    if (!isDailyWordsAllowed(user.wordsPerDay)) {
      Global.logger.i('用户超出当前权限每日单词限额 $nonPremiumMaxDailyWords（原设为 ${user.wordsPerDay}），执行重置');

      // 更新本地数据库
      await MyDatabase.instance.usersDao.updateWordsPerDay(user.id, nonPremiumMaxDailyWords);

      // 更新内存缓存
      final updatedUser = user.copyWith(wordsPerDay: nonPremiumMaxDailyWords);
      Global.updateUserCache(updatedUser);

      // 触发同步到云端
      ThrottledDbSyncService().requestSync();
    }
  }

  /// 是否具备学习加量（打卡后或在今日计划中追加新词批次）的权限
  static bool get canExtraStudy => isPremium;

  /// 是否具备自定义词书管理权限（创建、选中/切换、编辑）
  /// iOS 平台非会员受限；非 iOS 平台（Android/Web/macOS等）或会员开放
  static bool get canManageCustomDict {
    final isIOS = isIOSOverrideForTesting ?? PlatformUtils.isIOS;
    if (!isIOS) return true;
    return isPremium;
  }

  /// 是否允许使用 AI 助手功能（管理员或会员）
  static bool get canUseAiAssistant {
    final user = Global.getLoggedInUser();
    if (user?.isAdmin == true || user?.isSuperAdmin == true) {
      return true;
    }
    return isPremium;
  }
}

