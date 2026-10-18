
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/model/feature_challenge.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/utils.dart';

class ChallengeResult {
  final bool isCorrect;
  final bool isFirstUnlock;
  final int fruitEarned;
  final String explanation;

  const ChallengeResult({
    required this.isCorrect,
    required this.isFirstUnlock,
    required this.fruitEarned,
    required this.explanation,
  });
}

class FeatureChallengeService {
  static final FeatureChallengeService _instance = FeatureChallengeService._internal();
  factory FeatureChallengeService() => _instance;
  FeatureChallengeService._internal();

  static const String _prefUnlockedIds = 'feature_challenge_unlocked_ids';
  static const String _prefLastAnswerDate = 'feature_challenge_last_answer_date';
  static const String _prefTodayChallengeId = 'feature_challenge_today_id';
  static const String _prefTodayAssignedDate = 'feature_challenge_today_assigned_date';

  /// 读取已解锁的所有题目 ID 列表
  List<String> getUnlockedIds() {
    final list = Prefs.read<List<dynamic>>(_prefUnlockedIds);
    if (list == null) return [];
    return list.map((e) => e.toString()).toList();
  }

  /// 检查今天是否已经作答过
  bool hasAnsweredToday() {
    final today = _currentDateStr();
    final lastDate = Prefs.read<String>(_prefLastAnswerDate);
    return lastDate == today;
  }

  /// 获取当天的挑战题目（每天固定 1 道，优先从未解锁题目中选出）
  FeatureChallenge getTodayChallenge() {
    final today = _currentDateStr();
    final assignedDate = Prefs.read<String>(_prefTodayAssignedDate);
    final savedTodayId = Prefs.read<String>(_prefTodayChallengeId);

    // 如果今天已经分配过且该题目存在，直接沿用今天的题目
    if (assignedDate == today && savedTodayId != null) {
      final existing = FeatureChallengeRepository.allChallenges
          .where((c) => c.id == savedTodayId)
          .firstOrNull;
      if (existing != null) return existing;
    }

    // 重新选出今天的题目：从未解锁的题目中取第一道
    final unlocked = getUnlockedIds().toSet();
    FeatureChallenge? selected = FeatureChallengeRepository.allChallenges
        .where((c) => !unlocked.contains(c.id))
        .firstOrNull;

    // 如果全部题目都已解锁，则按日期循环温习
    if (selected == null) {
      final dayOfYear = AppClock.now().difference(DateTime(AppClock.now().year, 1, 1)).inDays;
      final idx = dayOfYear % FeatureChallengeRepository.allChallenges.length;
      selected = FeatureChallengeRepository.allChallenges[idx];
    }

    // 记录分配结果
    Prefs.write(_prefTodayAssignedDate, today);
    Prefs.write(_prefTodayChallengeId, selected.id);

    return selected;
  }

  /// 提交作答
  Future<ChallengeResult> submitAnswer({
    required String challengeId,
    required int selectedOptionIndex,
  }) async {
    final challenge = FeatureChallengeRepository.allChallenges
        .where((c) => c.id == challengeId)
        .firstOrNull;

    if (challenge == null) {
      return const ChallengeResult(
        isCorrect: false,
        isFirstUnlock: false,
        fruitEarned: 0,
        explanation: '题目不存在',
      );
    }

    final isCorrect = selectedOptionIndex == challenge.correctIndex;
    if (!isCorrect) {
      return const ChallengeResult(
        isCorrect: false,
        isFirstUnlock: false,
        fruitEarned: 0,
        explanation: '',
      );
    }

    // 答对了！
    final today = _currentDateStr();
    await Prefs.write(_prefLastAnswerDate, today);

    final unlocked = getUnlockedIds().toSet();
    final isFirstUnlock = !unlocked.contains(challengeId);
    if (isFirstUnlock) {
      unlocked.add(challengeId);
      await Prefs.write(_prefUnlockedIds, unlocked.toList());
    }

    // 不限制每道题只能答一次，每次答对均发放奖励
    const int fruitAwarded = 3;
    await _awardFruits(fruitAwarded, '完成功能秘籍挑战「${challenge.title}」');

    return ChallengeResult(
      isCorrect: true,
      isFirstUnlock: isFirstUnlock,
      fruitEarned: fruitAwarded,
      explanation: challenge.explanation,
    );
  }

  /// 发放智慧果奖励
  Future<void> _awardFruits(int count, String reason) async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) return;

      final newTotal = user.cowDung + count;
      final log = UserCowDungLog(
        id: Util.uuid(),
        userId: user.id,
        delta: count,
        cowDung: newTotal,
        theTime: AppClock.now(),
        reason: reason,
        createTime: AppClock.now(),
        updateTime: AppClock.now(),
      );

      await MyDatabase.instance.userCowDungLogsDao.insertEntity(log, true);
      await MyDatabase.instance.usersDao.saveUser(user.copyWith(cowDung: newTotal), true);
    } catch (e) {
      Global.logger.w('发放智慧果奖励失败: $e');
    }
  }

  String _currentDateStr() {
    return AppClock.now().toString().substring(0, 10);
  }
}
