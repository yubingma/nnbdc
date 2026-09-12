import 'package:flutter/widgets.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/level_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/level_up_dialog.dart';

/// 段位晋升判定与授勋服务 (Offline-First)
class LevelService {
  static final LevelService _instance = LevelService._internal();
  factory LevelService() => _instance;
  LevelService._internal();

  /// 晋升一段的魔法泡泡奖励, 段位越高奖励越厚
  static int promotionReward(int level) => 30 * level;

  /// 是否处于背单词答题流程中: 答题过程不打断用户, 晋升仪式延迟到本次学习结束时补办
  bool _studyInProgress = false;
  Level? _pendingLevel;

  /// 进入背单词答题流程
  void enterStudy() => _studyInProgress = true;

  /// 离开背单词答题流程(学习完成或中途退出), 补办被延迟的晋升仪式
  void leaveStudy() {
    _studyInProgress = false;
    if (_pendingLevel == null) return;
    // 延后一帧, 避免在页面销毁/路由切换过程中插入新路由.
    // addPostFrameCallback 自身不会调度帧, 必须显式 scheduleFrame, 否则空闲时会一直挂到下一个无关帧
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebratePending());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// 依据掌握词数的前后变化判定段位跃迁, 仅在真正跨越段位时举行晋升仪式。
  /// 掌握词数单调递增, 同一次跨越不会重复授予。
  Future<void> checkPromotion({required int oldWordCount, required int newWordCount}) async {
    if (newWordCount <= oldWordCount) return;

    final oldLevel = LevelUtil.getLevelByWordCount(oldWordCount);
    final newLevel = LevelUtil.getLevelByWordCount(newWordCount);
    if (newLevel.level <= oldLevel.level) return;

    final reward = promotionReward(newLevel.level);
    await _rewardBubbles(reward, 'LevelUp:L${newLevel.level}');

    if (_studyInProgress) {
      // 答题中先记账, 待本次学习结束后再举行仪式
      _pendingLevel = newLevel;
    } else {
      _showDialog(newLevel);
    }
    Global.logger.i('🎉 段位晋升: L${oldLevel.level}${oldLevel.name} → L${newLevel.level}${newLevel.name}');
  }

  void _celebratePending() {
    final level = _pendingLevel;
    _pendingLevel = null;
    if (level != null) _showDialog(level);
  }

  void _showDialog(Level level) {
    final context = DialogService.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    LevelUpDialog.show(context, level: level, rewardBubbles: promotionReward(level.level));
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
