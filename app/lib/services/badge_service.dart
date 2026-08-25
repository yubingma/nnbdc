import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/widget/badge_award_dialog.dart';
import 'package:nnbdc/widget/badge_svg_assets.dart';

/// 勋章本地规则引擎与实时授勋服务 (Offline-First)
class BadgeService {
  static final BadgeService _instance = BadgeService._internal();
  factory BadgeService() => _instance;
  BadgeService._internal();

  /// 检查并判定掌握单词类勋章 (VOCAB_100, VOCAB_1000, VOCAB_5000)
  Future<List<UserBadgeVo>> checkMasteredWords({BuildContext? context}) async {
    final user = Global.getLoggedInUser();
    final userId = user?.id;
    if (user == null || userId == null) return [];

    try {
      // 1. 获取当前用户掌握的单词总数
      final masteredWords = await MyDatabase.instance.masteredWordsDao.getMasteredWordsForUser(userId);
      final count = masteredWords.length;

      return await _checkAndAwardConditions(
        context: context ?? DialogService.context,
        user: user,
        conditionType: 'MASTERED_WORDS',
        currentValue: count,
      );
    } catch (e, s) {
      Global.logger.e('检查掌握单词勋章失败: $e', stackTrace: s);
      return [];
    }
  }

  /// 检查并判定连续打卡天数类勋章 (STREAK_3, STREAK_21, STREAK_100, STREAK_365)
  Future<List<UserBadgeVo>> checkStreakDays({BuildContext? context}) async {
    final user = Global.getLoggedInUser();
    final userId = user?.id;
    if (user == null || userId == null) return [];

    try {
      final streakDays = user.continuousDakaDayCount;
      final newlyAwarded = await _checkAndAwardConditions(
        context: context ?? DialogService.context,
        user: user,
        conditionType: 'STREAK_DAYS',
        currentValue: streakDays,
      );

      // 额外检查早起与夜行学者勋章
      final now = DateTime.now();
      final hour = now.hour;
      final minute = now.minute;
      if (hour == 6 || (hour == 7 && minute <= 30)) {
        final dawnList = await awardStackableBadge('DAWN_LEARN');
        newlyAwarded.addAll(dawnList);
      } else if (hour >= 23 || hour < 4) {
        final nightList = await awardStackableBadge('NIGHT_LEARN');
        newlyAwarded.addAll(nightList);
      }

      return newlyAwarded;
    } catch (e, s) {
      Global.logger.e('检查打卡勋章失败: $e', stackTrace: s);
      return [];
    }
  }

  /// 颁发/叠层可重复达成的精进类勋章 (如 PERFECT_SCORE, EASY_FLOW, DAWN_LEARN, NIGHT_LEARN)
  Future<List<UserBadgeVo>> awardStackableBadge(String badgeCode, {BuildContext? context}) async {
    final user = Global.getLoggedInUser();
    final userId = user?.id;
    if (user == null || userId == null) return [];

    final def = BadgeSvgAssets.allBadgeDefinitions.firstWhere(
      (d) => d['code'] == badgeCode,
      orElse: () => {},
    );
    if (def.isEmpty) return [];

    try {
      final existing = await MyDatabase.instance.userBadgesDao.getBadgeByUserAndCode(userId, badgeCode);
      int obtainCount = 1;
      int starLevel = 1;
      final rewardBubbles = def['rewardBubbles'] as int? ?? 0;

      if (existing != null) {
        obtainCount = existing.obtainCount + 1;
        // 计算星级
        if (obtainCount >= 100) {
          starLevel = 5;
        } else if (obtainCount >= 60) {
          starLevel = 4;
        } else if (obtainCount >= 30) {
          starLevel = 3;
        } else if (obtainCount >= 10) {
          starLevel = 2;
        } else {
          starLevel = 1;
        }

        final updated = existing.copyWith(
          obtainCount: obtainCount,
          starLevel: starLevel,
          updateTime: DateTime.now(),
        );
        await MyDatabase.instance.userBadgesDao.saveEntity(updated, true);
      } else {
        final newId = '${userId}_$badgeCode';
        final newUb = UserBadge(
          id: newId,
          userId: userId,
          badgeCode: badgeCode,
          obtainCount: 1,
          starLevel: 1,
          unlockedAt: DateTime.now(),
          isEquipped: false,
          isViewed: false,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
        await MyDatabase.instance.userBadgesDao.saveEntity(newUb, true);
      }

      // 发放魔法泡泡
      if (rewardBubbles > 0) {
        await _rewardBubbles(user, rewardBubbles, 'BadgeAward:$badgeCode');
      }

      final vo = UserBadgeVo(
        userId: userId,
        badgeCode: badgeCode,
        obtainCount: obtainCount,
        starLevel: starLevel,
        isUnlocked: true,
        unlockedAt: DateTime.now(),
        progressCurrent: def['targetValue'] as int? ?? 1,
        progressTarget: def['targetValue'] as int? ?? 1,
        progressPercent: 1.0,
        badge: BadgeVo(
          code: badgeCode,
          name: def['name'] as String,
          category: def['category'] as String,
          tier: def['tier'] as String,
          isStackable: true,
          rewardBubbles: rewardBubbles,
          description: def['description'] as String,
        ),
      );

      // 实时弹出全屏高光仪式感弹窗
      final targetContext = context ?? DialogService.context;
      if (targetContext != null && targetContext.mounted) {
        BadgeAwardDialog.show(targetContext, userBadge: vo);
      }

      return [vo];
    } catch (e, s) {
      Global.logger.e('颁发精进勋章失败: $e', stackTrace: s);
      return [];
    }
  }

  /// 内部通用条件判定与弹窗
  Future<List<UserBadgeVo>> _checkAndAwardConditions({
    required BuildContext? context,
    required User user,
    required String conditionType,
    required int currentValue,
  }) async {
    final userId = user.id;
    final List<UserBadgeVo> newlyAwarded = [];

    // 查询该用户已有的勋章
    final localRecords = await MyDatabase.instance.userBadgesDao.getBadgesByUserId(userId);
    final Map<String, UserBadge> existingMap = {for (var item in localRecords) item.badgeCode: item};

    for (final def in BadgeSvgAssets.allBadgeDefinitions) {
      final code = def['code'] as String;
      final type = def['conditionType'] as String;
      final targetValue = def['targetValue'] as int;
      final rewardBubbles = def['rewardBubbles'] as int? ?? 0;

      if (type != conditionType) continue;

      // 如果尚未解锁且当前值满足条件
      if (!existingMap.containsKey(code) && targetValue > 0 && currentValue >= targetValue) {
        try {
          final newId = '${userId}_$code';
          final newUb = UserBadge(
            id: newId,
            userId: userId,
            badgeCode: code,
            obtainCount: 1,
            starLevel: 1,
            unlockedAt: DateTime.now(),
            isEquipped: false,
            isViewed: false,
            createTime: DateTime.now(),
            updateTime: DateTime.now(),
          );

          // 本地入库并生成同步日志 (通过 sync.dart 自动同步到后端)
          await MyDatabase.instance.userBadgesDao.saveEntity(newUb, true);
          existingMap[code] = newUb;

          // 发放魔法泡泡奖励
          if (rewardBubbles > 0) {
            await _rewardBubbles(user, rewardBubbles, 'BadgeUnlock:$code');
          }

          final vo = UserBadgeVo(
            id: newId,
            userId: userId,
            badgeCode: code,
            obtainCount: 1,
            starLevel: 1,
            unlockedAt: newUb.unlockedAt,
            isEquipped: false,
            isViewed: false,
            isUnlocked: true,
            progressCurrent: targetValue,
            progressTarget: targetValue,
            progressPercent: 1.0,
            badge: BadgeVo(
              code: code,
              name: def['name'] as String,
              category: def['category'] as String,
              tier: def['tier'] as String,
              isStackable: def['isStackable'] as bool? ?? false,
              rewardBubbles: rewardBubbles,
              description: def['description'] as String,
              targetValue: targetValue,
              conditionType: conditionType,
            ),
          );
          newlyAwarded.add(vo);

          Global.logger.i('🎉 达成新勋章: ${def['name']} ($code)!');

          // 🌟 实时弹出全屏授勋仪式弹窗
          if (context != null && context.mounted) {
            BadgeAwardDialog.show(context, userBadge: vo);
          }
        } catch (e, s) {
          Global.logger.e('自动解锁勋章失败: $code, $e', stackTrace: s);
        }
      }
    }

    return newlyAwarded;
  }

  /// 发放魔法泡泡
  Future<void> _rewardBubbles(User user, int bubbles, String reason) async {
    try {
      final userId = user.id;
      final current = user.cowDung;
      final newTotal = current + bubbles;

      final log = UserCowDungLog(
        id: '${userId}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        delta: bubbles,
        cowDung: newTotal,
        theTime: DateTime.now(),
        reason: reason,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      await MyDatabase.instance.userCowDungLogsDao.insertEntity(log, true);
      await MyDatabase.instance.usersDao.saveUser(user.copyWith(cowDung: newTotal), true);
    } catch (e) {
      Global.logger.w('发放勋章泡泡奖励失败: $e');
    }
  }
}
