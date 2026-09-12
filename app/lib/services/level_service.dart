import 'package:flutter/widgets.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/level_up_dialog.dart';

/// 段位晋升与段内升星的判定服务 (Offline-First)
///
/// 反馈强度刻意分级:
/// - 跨越段位 → 全屏晋升仪式 + 魔法泡泡奖励 (低频, 值得打断)
/// - 段内升星 → 轻量提示 (高频, 弹窗会变成骚扰)
/// 两者都在答题过程中挂起, 等本次学习结束(离开背单词页)时统一补办。
class LevelService {
  static final LevelService _instance = LevelService._internal();
  factory LevelService() => _instance;
  LevelService._internal();

  /// 晋升一段的魔法泡泡奖励, 段位越高奖励越厚
  static int promotionReward(int level) => 30 * level;

  /// 是否处于背单词答题流程中: 答题过程不打断用户, 进度提示延迟到本次学习结束时补办
  bool _studyInProgress = false;
  Level? _pendingPromotion;
  _StarUp? _pendingStarUp;

  /// 进入背单词答题流程
  void enterStudy() => _studyInProgress = true;

  /// 离开背单词答题流程(学习完成或中途退出), 补办被延迟的进度提示
  void leaveStudy() {
    _studyInProgress = false;
    if (_pendingPromotion == null && _pendingStarUp == null) return;
    // 延后一帧, 避免在页面销毁/路由切换过程中插入新路由.
    // addPostFrameCallback 自身不会调度帧, 必须显式 scheduleFrame, 否则空闲时会一直挂到下一个无关帧
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebratePending());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// 依据掌握词数的前后变化判定段位晋升与段内升星, 返回本次发生的进度变化(无变化返回 null)。
  /// 掌握词数单调递增, 同一次跨越不会重复授予。
  ///
  /// 返回值是"判定结果", UI 提示由本服务直接发出; 拆开是为了让判定逻辑可被独立验证。
  Future<LevelAdvance?> checkProgress({
    required int oldWordCount,
    required int newWordCount,
  }) async {
    if (newWordCount <= oldWordCount) return null;

    final oldLevel = LevelUtil.getLevelByWordCount(oldWordCount);
    final newLevel = LevelUtil.getLevelByWordCount(newWordCount);

    if (newLevel.level > oldLevel.level) {
      final reward = promotionReward(newLevel.level);
      await _rewardBubbles(reward, 'LevelUp:L${newLevel.level}');

      // 晋升后星级归 1, 此前挂起的升星提示已失效
      _pendingStarUp = null;
      if (_studyInProgress) {
        _pendingPromotion = newLevel;
      } else {
        _showPromotion(newLevel);
      }
      Global.logger.i('🎉 段位晋升: L${oldLevel.level}${oldLevel.name} → L${newLevel.level}${newLevel.name}');
      return LevelAdvance.promotion(newLevel);
    }

    final oldStars = LevelUtil.getStarsInLevel(oldLevel, oldWordCount);
    final newStars = LevelUtil.getStarsInLevel(newLevel, newWordCount);
    if (newStars <= oldStars) return null;

    final starUp = _StarUp(newLevel, newStars);
    if (_studyInProgress) {
      _pendingStarUp = starUp;
    } else {
      _showStarUp(starUp);
    }
    Global.logger.i('⭐ 段内升星: ${newLevel.name} $oldStars→$newStars');
    return LevelAdvance.starUp(newLevel, newStars);
  }

  void _celebratePending() {
    final promotion = _pendingPromotion;
    final starUp = _pendingStarUp;
    _pendingPromotion = null;
    _pendingStarUp = null;

    // 有晋级时只办晋级仪式: 星级已归 1, 再叠一条升星提示只会让人困惑
    if (promotion != null) {
      _showPromotion(promotion);
      return;
    }
    if (starUp != null) _showStarUp(starUp);
  }

  /// 提示属于"尽力而为"的副作用: 它的调用方是掌握单词/数据写入链路,
  /// 一旦弹窗或 Toast 抛异常(如宿主未初始化)绝不能把数据写入带崩。
  void _showPromotion(Level level) {
    try {
      final context = DialogService.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      LevelUpDialog.show(context, level: level, rewardBubbles: promotionReward(level.level));
    } catch (e, s) {
      Global.logger.e('展示段位晋升仪式失败: $e', stackTrace: s);
    }
  }

  void _showStarUp(_StarUp starUp) {
    try {
      ToastUtil.success(
        '${starUp.level.icon} ${starUp.level.name} 升为 ${LevelUtil.starsText(starUp.stars)}',
      );
    } catch (e, s) {
      Global.logger.e('展示段内升星提示失败: $e', stackTrace: s);
    }
  }

  /// 发放晋升奖励的魔法泡泡
  Future<void> _rewardBubbles(int bubbles, String reason) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;
    try {
      final now = AppClock.now();
      final newTotal = user.cowDung + bubbles;
      await MyDatabase.instance.userCowDungLogsDao.insertEntity(
        UserCowDungLog(
          id: Util.uuid(),
          userId: user.id,
          delta: bubbles,
          cowDung: newTotal,
          theTime: now,
          reason: reason,
          createTime: now,
          updateTime: now,
        ),
        true,
      );
      await MyDatabase.instance.usersDao.saveUser(user.copyWith(cowDung: newTotal), true);
    } catch (e, s) {
      Global.logger.e('发放段位晋升奖励失败: $e', stackTrace: s);
    }
  }
}

/// 本次判定带来的进度变化
enum AdvanceKind { promotion, starUp }

class LevelAdvance {
  final AdvanceKind kind;
  final Level level;

  /// 升星后当前的星数; 晋升时恒为 1(新段位从 1 星起步)
  final int stars;

  const LevelAdvance.promotion(this.level)
      : kind = AdvanceKind.promotion,
        stars = 1;

  const LevelAdvance.starUp(this.level, this.stars) : kind = AdvanceKind.starUp;

  bool get isPromotion => kind == AdvanceKind.promotion;
}

/// 待提示的段内升星
class _StarUp {
  final Level level;
  final int stars;

  const _StarUp(this.level, this.stars);
}
