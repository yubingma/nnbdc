import 'package:nnbdc/util/app_clock.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/platform_util.dart';

class AnalyticsUtil {
  // 是否允许采集（基于隐私合规，必须在用户同意隐私协议后才能开启）
  static bool _canTrack = false;

  static void init(bool hasApprovedPrivacy) {
    _canTrack = hasApprovedPrivacy;
  }

  /// 基础事件打点 (兼容 Android/iOS 层面的 Umeng 采集)
  static void trackEvent(String eventId, [Map<String, dynamic>? properties]) {
    if (!_canTrack) return;
    
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      try {
        if (properties != null) {
          // UmengSdk 的 values 建议全部转为 String 避免崩溃
          Map<String, String> strProps = {};
          properties.forEach((key, value) {
            strProps[key] = value.toString();
          });
          UmengCommonSdk.onEvent(eventId, strProps);
        } else {
          UmengCommonSdk.onEvent(eventId, {});
        }
        Global.logger.d('[Analytics] Event: $eventId, Props: $properties');
      } catch (e) {
        Global.logger.e('[Analytics] Failed to track event $eventId: $e');
      }
    }
  }

  // ============================================
  // 下面是针对“泡泡单词”提升留存率的核心埋点事件
  // ============================================

  /// 1. 记录登录/注册来源（判断是游客、微信还是邮箱，方便分析渠道留存）
  static void trackLogin(String method, bool isNewUser) {
    trackEvent('login_success', {
      'method': method, // guest, wechat, email, apple
      'is_new': isNewUser.toString(),
    });
  }

  /// 2. 新手引导：选择词书（看多少人因为找不到想要的词书而流失）
  static void trackSelectBook(String bookCategory, String bookName) {
    trackEvent('select_book', {
      'category': bookCategory,
      'name': bookName,
    });
  }

  /// 3. 学习行为：开始当天的学习（漏斗起点）
  static void trackStartStudy() {
    trackEvent('study_start', {
      'time_of_day': AppClock.now().hour.toString(), // 了解用户偏好学习时段
    });
  }

  /// 4. 学习行为：打卡完成（漏斗终点，计算当日任务完成率）
  static void trackFinishDaka(int cowDungAward, int consecutiveDays) {
    trackEvent('study_finish_daka', {
      'cow_dung': cowDungAward,
      'streak_days': consecutiveDays,
    });
  }

  /// 5. 学习流失点：背到一半退出了（中途流失漏斗）
  static void trackStudyQuitEarly(int wordsLearnedToday, int wordsRemaining) {
    trackEvent('study_quit_early', {
      'words_learned': wordsLearnedToday,
      'words_remaining': wordsRemaining,
    });
  }

  /// 6. 通知授权：用户是否允许发送推送（强关联7日留存率）
  static void trackNotificationPermission(bool isGranted) {
    trackEvent('notification_permission', {
      'granted': isGranted.toString(),
    });
  }

  /// 7. 页面访问留存路径
  static void trackPageView(String pageName) {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      if (_canTrack) {
        UmengCommonSdk.onPageStart(pageName);
      }
    }
  }

  static void trackPageEnd(String pageName) {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      if (_canTrack) {
        UmengCommonSdk.onPageEnd(pageName);
      }
    }
  }
}
