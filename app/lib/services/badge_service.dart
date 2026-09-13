import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/dialog_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/badge_award_dialog.dart';
import 'package:nnbdc/widget/badge_svg_assets.dart';

/// 勋章本地规则引擎与实时授勋服务 (Offline-First)
///
/// 勋章按判定方式分两类, 混淆两者会造成漏发或重复授予:
/// - 状态型(已掌握词数 / 连续打卡 / 全书通关): 只依赖当前状态, 任何时候都可对齐补发, 见 [syncStateBadges]
/// - 事件型(打卡时段 / 单次学习表现): 依赖"刚刚发生过什么", 只能在事件发生的那一刻判定一次
///
/// 事件型一旦漏判就再也补不回来, 因此用户进入勋章墙时会走 [healBadges] 按事实源重放历史, 自动补齐。
class BadgeService {
  static final BadgeService _instance = BadgeService._internal();
  factory BadgeService() => _instance;
  BadgeService._internal();

  /// 按条件类型判定并颁发勋章, 自动区分"首次授予"与"可叠层勋章再次获得"。
  /// 判定失败只记日志不外抛, 以便调用方安全地 fire-and-forget。
  Future<List<UserBadgeVo>> checkAndAward({
    required String conditionType,
    required int currentValue,
    bool celebrate = true,
  }) async {
    final user = Global.getLoggedInUser();
    if (user == null) return [];

    try {
      final localRecords = await MyDatabase.instance.userBadgesDao.getBadgesByUserId(user.id);
      final Map<String, UserBadge> existingMap = {
        for (final item in localRecords) item.badgeCode: item,
      };

      final List<UserBadgeVo> newlyAwarded = [];
      for (final def in BadgeSvgAssets.allBadgeDefinitions) {
        if (def['conditionType'] != conditionType) continue;
        if (def['isAvailable'] == false) continue;

        final targetValue = def['targetValue'] as int;
        if (targetValue <= 0 || currentValue < targetValue) continue;

        final code = def['code'] as String;
        final existing = existingMap[code];
        // 不可叠层的勋章只授予一次; 可叠层的每次达标都再进一层
        if (existing == null) {
          final vo = await _grant(user, def, code,
              existing: null, obtainCount: 1, celebrate: celebrate);
          if (vo != null) newlyAwarded.add(vo);
        } else if (def['isStackable'] as bool? ?? false) {
          final vo = await _grant(user, def, code,
              existing: existing, obtainCount: existing.obtainCount + 1, celebrate: celebrate);
          if (vo != null) newlyAwarded.add(vo);
        }
      }
      return newlyAwarded;
    } catch (e, s) {
      Global.logger.e('勋章判定失败: conditionType=$conditionType, $e', stackTrace: s);
      return [];
    }
  }

  /// 词汇量类勋章 (破冰启航 / 千词过海 / 词海踏浪)
  ///
  /// 判定依据是**历史最高掌握词数**而非当前值: 掌握数会因退火重学回落, 但已达成的勋章不该被撤销。
  Future<List<UserBadgeVo>> checkMasteredWords({int? masteredCount, bool celebrate = true}) async {
    final user = Global.getLoggedInUser();
    if (user == null) return [];
    final fresh = await MyDatabase.instance.usersDao.getUserById(user.id);
    final count = masteredCount ?? fresh?.maxMasteredWords ?? fresh?.masteredWordsCount ?? 0;
    return checkAndAward(
      conditionType: 'MASTERED_WORDS',
      currentValue: count,
      celebrate: celebrate,
    );
  }

  /// 连续打卡天数类勋章 (萌芽初醒 / 习惯微光 / 百日筑基 / 星火长明)
  ///
  /// 必须用**历史最长连续天数**而非当前连续天数: 勋章描述的是"曾达成过", 且勋章一旦授予不会撤销。
  /// 用当前连续天数会让连续记录中断的用户在补发时永远拿不到本该属于他的勋章。
  Future<List<UserBadgeVo>> checkStreakDays({bool celebrate = true}) async {
    final user = Global.getLoggedInUser();
    if (user == null) return [];
    final fresh = await MyDatabase.instance.usersDao.getUserById(user.id);
    return checkAndAward(
      conditionType: 'STREAK_DAYS',
      currentValue: fresh?.maxContinuousDakaDayCount ?? 0,
      celebrate: celebrate,
    );
  }

  /// 打卡时段类勋章 (破晓之翼 / 夜行学者): 必须在完成打卡的当下判定, 否则补发会误授
  Future<List<UserBadgeVo>> checkStudyTimeBadge() async {
    final now = AppClock.now();
    final hour = now.hour;
    final minute = now.minute;
    if (hour == 6 || (hour == 7 && minute <= 30)) {
      return checkAndAward(conditionType: 'DAWN_CHECKIN', currentValue: 1);
    }
    if (hour >= 23 || hour < 4) {
      return checkAndAward(conditionType: 'NIGHT_CHECKIN', currentValue: 1);
    }
    return [];
  }

  /// 单次学习表现类勋章: 百发百中(今日全程无答错) / 极速心流(今日连续评为轻松)
  Future<List<UserBadgeVo>> checkStudyPerformance() async {
    final user = Global.getLoggedInUser();
    if (user == null) return [];
    final ratings = await MyDatabase.instance.learningLogsDao.getTodayRatings(user.id);
    if (ratings.isEmpty) return [];

    final List<UserBadgeVo> newlyAwarded = [];
    if (!ratings.contains(FsrsRating.again.value)) {
      newlyAwarded.addAll(
        await checkAndAward(conditionType: 'PERFECT_SCORE', currentValue: 1),
      );
    }
    newlyAwarded.addAll(
      await checkAndAward(
        conditionType: 'EASY_STREAK',
        currentValue: _maxConsecutive(ratings, FsrsRating.easy.value),
      ),
    );
    return newlyAwarded;
  }

  /// 全书通关类勋章: 当前激活词书的单词已全部取进学习/已掌握
  Future<List<UserBadgeVo>> checkBookFinished({bool celebrate = true}) async {
    final user = Global.getLoggedInUser();
    if (user == null) return [];
    return checkAndAward(
      conditionType: 'FINISH_BOOK',
      currentValue: await _bookFinishedValue(user.id),
      celebrate: celebrate,
    );
  }

  /// 对齐全部"状态型"勋章, 补发历史已达标但从未触发过判定的勋章。
  /// 复用各条件类型自己的判定入口, 避免同一指标出现第二份取值逻辑而漂移;
  /// 静默补发不弹窗, 免得老用户一进勋章墙被连续弹窗淹没。
  Future<void> syncStateBadges() async {
    await checkMasteredWords(celebrate: false);
    await checkStreakDays(celebrate: false);
    await checkBookFinished(celebrate: false);
  }

  /// 用户侧自愈入口: 进入勋章墙时静默补齐历史已达标却从未触发过判定的勋章。
  ///
  /// 两条腿互补, 缺一不可:
  /// - [syncStateBadges] 信任 user 表的缓存字段(峰值掌握词数 / 历史最长连续天数), 覆盖原始打卡记录缺失的用户;
  /// - [rebuildBadgesFromFacts] 信任学习日志与打卡原始记录, 覆盖缓存字段被写坏的情况, 并补全全部事件型勋章。
  ///
  /// 两者都"只补不撤"且幂等, 合起来才是用户真实的成就历史。
  /// 因此本方法是唯一入口, 不要只调用其中一条腿。
  Future<void> healBadges() async {
    await syncStateBadges();
    await rebuildBadgesFromFacts();
  }

  /// 按事实源全量重放, 修复全部勋章。
  ///
  /// 与 [syncStateBadges] 的区别: syncStateBadges 只看"当前状态", 本方法额外按用户已保存的历史
  /// **重放事件型勋章**(百发百中/极速心流/破晓/夜行)的达成次数, 因此即使判定逻辑曾经有 bug 导致
  /// 漏发或少发, 也能只靠数据修复。
  ///
  /// 原则: **只补不撤**。事实源可能不完整(早期日志缺失、词书后来扩容、功能上线前无记录),
  /// 撤销用户已得的成就是不可逆损失, 所以只补发缺失勋章、把叠层次数向上校正, 从不降低或删除;
  /// 持有但事实源无法验证的勋章只登记到 [BadgeRebuildResult.unverifiable] 供排查。
  ///
  /// [dryRun] 为 true 时只计算差异不落库, 供体检器"先诊断后修复"使用。
  Future<BadgeRebuildResult> rebuildBadgesFromFacts({bool dryRun = false}) async {
    final result = BadgeRebuildResult();
    final user = Global.getLoggedInUser();
    if (user == null) return result;
    final fresh = await MyDatabase.instance.usersDao.getUserById(user.id);
    if (fresh == null) return result;

    try {
      final existingRecords = await MyDatabase.instance.userBadgesDao.getBadgesByUserId(user.id);
      final existingMap = {for (final item in existingRecords) item.badgeCode: item};

      final ratingsByDay = await MyDatabase.instance.learningLogsDao.getRatingsGroupedByDay(user.id);
      final peakMastered = fresh.maxMasteredWords ?? fresh.masteredWordsCount;
      final longestStreak = await _longestDakaStreak(fresh.id);
      final bookFinished = await _bookFinishedValue(fresh.id);
      final dakas = await MyDatabase.instance.dakasDao.getDakaRecords(fresh.id);

      for (final def in BadgeSvgAssets.allBadgeDefinitions) {
        if (def['isAvailable'] == false) continue;
        final targetValue = def['targetValue'] as int;
        if (targetValue <= 0) continue;

        final factualCount = switch (def['conditionType'] as String) {
          'MASTERED_WORDS' => _reachedOnce(peakMastered, targetValue),
          'STREAK_DAYS' => _reachedOnce(longestStreak, targetValue),
          'FINISH_BOOK' => bookFinished,
          'PERFECT_SCORE' => ratingsByDay.values
              .where((ratings) => !ratings.contains(FsrsRating.again.value))
              .length,
          'EASY_STREAK' => ratingsByDay.values
              .where((ratings) => _maxConsecutive(ratings, FsrsRating.easy.value) >= targetValue)
              .length,
          'DAWN_CHECKIN' => _dakaCountInWindow(dakas, dawn: true),
          'NIGHT_CHECKIN' => _dakaCountInWindow(dakas, dawn: false),
          _ => 0,
        };

        final code = def['code'] as String;
        final existing = existingMap[code];
        final currentCount = existing?.obtainCount ?? 0;
        if (factualCount <= currentCount) {
          if (existing != null && factualCount == 0) result.unverifiable.add(code);
          continue;
        }

        if (existing == null) {
          result.granted.add(code);
        } else {
          result.adjusted[code] = factualCount;
        }
        if (!dryRun) {
          await _grant(user, def, code,
              existing: existing, obtainCount: factualCount, celebrate: false);
        }
      }
    } catch (e, s) {
      Global.logger.e('勋章全量重放失败: $e', stackTrace: s);
    }
    return result;
  }

  /// 激活词书是否已全部取词完毕, 是返回 1 否则 0
  Future<int> _bookFinishedValue(String userId) async {
    final db = MyDatabase.instance;
    final learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);
    final dictIds = learningDicts.map((d) => d.dictId).toList();
    if (dictIds.isEmpty) return 0;

    final rawWordCount = await db.dictWordsDao.getUniqueWordCountInDicts(dictIds);
    if (rawWordCount <= 0) return 0;

    final fetched = await db.learningWordsDao.getLearningWordsCountInDicts(userId, dictIds) +
        await db.masteredWordsDao.getMasteredWordsCountInDicts(userId, dictIds);
    return fetched >= rawWordCount ? 1 : 0;
  }

  /// 达标即计一次(用于不可叠层的成就型勋章)
  static int _reachedOnce(int value, int target) => value >= target ? 1 : 0;

  /// 从打卡记录重算历史最长连续天数。
  /// 刻意不依赖 user.max_continuous_daka_day_count —— 那个字段本身可能被写坏, 重放必须回到原始记录。
  static Future<int> _longestDakaStreak(String userId) async {
    final records = await MyDatabase.instance.dakasDao.getDakaRecords(userId);
    if (records.isEmpty) return 0;

    final days = records.map((r) => DateUtils.businessDate(r.forLearningDate)).toSet().toList()
      ..sort();
    int best = 1;
    int current = 1;
    for (var i = 1; i < days.length; i++) {
      current = days[i].difference(days[i - 1]).inDays == 1 ? current + 1 : 1;
      if (current > best) best = current;
    }
    return best;
  }

  /// 打卡时间落在破晓(6:00~7:30)或夜行(23:00~次日4:00)时段的次数
  static int _dakaCountInWindow(List<Daka> dakas, {required bool dawn}) {
    return dakas.where((daka) {
      final hour = daka.createTime.hour;
      final minute = daka.createTime.minute;
      return dawn ? (hour == 6 || (hour == 7 && minute <= 30)) : (hour >= 23 || hour < 4);
    }).length;
  }

  /// 序列中最长的连续目标值长度
  static int _maxConsecutive(List<int> values, int target) {
    int best = 0;
    int current = 0;
    for (final value in values) {
      current = value == target ? current + 1 : 0;
      if (current > best) best = current;
    }
    return best;
  }

  /// 落库并发放奖励, 必要时弹出授勋弹窗; 返回 null 表示本次未授予。
  ///
  /// [obtainCount] 是目标获得次数而非增量: 实时判定传"已有 +1", 全量重放传事实次数,
  /// 奖励按**本次新增的层数**发放, 因此重放只会补发差额, 不会重复发放。
  Future<UserBadgeVo?> _grant(
    User user,
    Map<String, dynamic> def,
    String code, {
    required UserBadge? existing,
    required int obtainCount,
    required bool celebrate,
  }) async {
    final rewardBubbles = def['rewardBubbles'] as int? ?? 0;
    final targetValue = def['targetValue'] as int;

    final now = AppClock.now();
    final UserBadge record = existing == null
        ? UserBadge(
            id: Util.uuid(),
            userId: user.id,
            badgeCode: code,
            obtainCount: obtainCount,
            starLevel: _starLevelOf(obtainCount),
            unlockedAt: now,
            isEquipped: false,
            isViewed: false,
            createTime: now,
            updateTime: now,
          )
        : existing.copyWith(
            obtainCount: obtainCount,
            starLevel: _starLevelOf(obtainCount),
            updateTime: now,
          );
    await MyDatabase.instance.userBadgesDao.saveEntity(record, true);

    final gainedCount = obtainCount - (existing?.obtainCount ?? 0);
    if (rewardBubbles > 0 && gainedCount > 0) {
      await _rewardBubbles(
        user,
        rewardBubbles * gainedCount,
        existing == null ? 'BadgeUnlock:$code' : 'BadgeStack:$code',
      );
    }

    final vo = UserBadgeVo(
      id: record.id,
      userId: user.id,
      badgeCode: code,
      obtainCount: record.obtainCount,
      starLevel: record.starLevel,
      unlockedAt: record.unlockedAt,
      isEquipped: record.isEquipped,
      isViewed: record.isViewed,
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
        conditionType: def['conditionType'] as String,
      ),
    );

    Global.logger.i(existing == null
        ? '🎉 达成新勋章: ${def['name']} ($code)!'
        : '🎉 勋章再次进阶: ${def['name']} ($code) ×${record.obtainCount}');

    if (celebrate) {
      BadgeAwardDialog.show(DialogService.context, userBadge: vo);
    }
    return vo;
  }

  /// 可叠层勋章按获得次数升级星级
  static int _starLevelOf(int obtainCount) {
    if (obtainCount >= 100) return 5;
    if (obtainCount >= 60) return 4;
    if (obtainCount >= 30) return 3;
    if (obtainCount >= 10) return 2;
    return 1;
  }

  /// 发放魔法泡泡
  Future<void> _rewardBubbles(User user, int bubbles, String reason) async {
    try {
      // 一次判定可能连续授予多枚勋章, 必须取最新余额而非调用方捕获的用户快照, 否则多枚奖励会互相覆盖
      final latest = Global.getLoggedInUser() ?? user;
      final newTotal = latest.cowDung + bubbles;

      final log = UserCowDungLog(
        id: Util.uuid(),
        userId: latest.id,
        delta: bubbles,
        cowDung: newTotal,
        theTime: AppClock.now(),
        reason: reason,
        createTime: AppClock.now(),
        updateTime: AppClock.now(),
      );
      await MyDatabase.instance.userCowDungLogsDao.insertEntity(log, true);
      await MyDatabase.instance.usersDao.saveUser(latest.copyWith(cowDung: newTotal), true);
    } catch (e) {
      Global.logger.w('发放勋章泡泡奖励失败: $e');
    }
  }
}

/// 勋章全量重放的结果报告
class BadgeRebuildResult {
  /// 本次补齐(或按 dryRun 将要补齐)的勋章
  final List<String> granted = [];

  /// 校正了叠层次数的勋章: code -> 校正后的次数
  final Map<String, int> adjusted = {};

  /// 已持有但事实源无法验证的勋章, 只登记不撤销
  final List<String> unverifiable = [];

  bool get hasChange => granted.isNotEmpty || adjusted.isNotEmpty;
}
