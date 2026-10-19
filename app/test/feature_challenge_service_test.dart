import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/model/feature_challenge.dart';
import 'package:nnbdc/services/feature_challenge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  group('FeatureChallengeService 每日一题与功能秘籍测试', () {
    test('内置题库数量与完整性校验', () {
      final list = FeatureChallengeRepository.allChallenges;
      expect(list.isNotEmpty, true);
      for (final item in list) {
        expect(item.id.isNotEmpty, true);
        expect(item.title.isNotEmpty, true);
        expect(item.question.isNotEmpty, true);
        expect(item.options.length, greaterThanOrEqualTo(2));
        expect(item.correctIndex >= 0 && item.correctIndex < item.options.length, true);
        expect(item.explanation.isNotEmpty, true);
      }
    });

    test('初始状态：无解锁题目，今天未作答', () {
      final service = FeatureChallengeService();
      expect(service.getUnlockedIds(), isEmpty);
      expect(service.hasAnsweredToday(), false);

      final todayChallenge = service.getTodayChallenge();
      expect(todayChallenge.id, equals(FeatureChallengeRepository.allChallenges.first.id));
    });

    test('答错题目：不解锁，不标记今日已答，不发奖励', () async {
      final service = FeatureChallengeService();
      final todayChallenge = service.getTodayChallenge();
      final wrongIndex = (todayChallenge.correctIndex + 1) % todayChallenge.options.length;

      final res = await service.submitAnswer(
        challengeId: todayChallenge.id,
        selectedOptionIndex: wrongIndex,
      );

      expect(res.isCorrect, false);
      expect(res.fruitEarned, 0);
      expect(service.hasAnsweredToday(), false);
      expect(service.getUnlockedIds(), isEmpty);
    });

    test('首次答对题目：解锁成功，标记今日已答，发放 1 颗智慧果奖励并写入历史', () async {
      final service = FeatureChallengeService();
      final todayChallenge = service.getTodayChallenge();

      final res = await service.submitAnswer(
        challengeId: todayChallenge.id,
        selectedOptionIndex: todayChallenge.correctIndex,
      );

      expect(res.isCorrect, true);
      expect(res.isFirstUnlock, true);
      expect(res.fruitEarned, 1);
      expect(res.explanation, equals(todayChallenge.explanation));
      expect(service.hasAnsweredToday(), true);
      expect(service.getUnlockedIds(), contains(todayChallenge.id));

      final history = service.getAnswerHistory();
      expect(history.isNotEmpty, true);
      expect(history.first.challengeId, equals(todayChallenge.id));
      expect(history.first.fruitEarned, equals(1));
    });

    test('已解锁题目再次作答：不限制每道题只能答一次，每次答对均发放 1 颗智慧果', () async {
      final service = FeatureChallengeService();
      final todayChallenge = service.getTodayChallenge();

      // 第一次答对
      await service.submitAnswer(
        challengeId: todayChallenge.id,
        selectedOptionIndex: todayChallenge.correctIndex,
      );

      // 第二次答对
      final res2 = await service.submitAnswer(
        challengeId: todayChallenge.id,
        selectedOptionIndex: todayChallenge.correctIndex,
      );

      expect(res2.isCorrect, true);
      expect(res2.fruitEarned, 1);
    });
  });
}
