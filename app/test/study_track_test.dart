import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_track.dart';

void main() {
  final today = AppClock.today();
  final yesterday = today.subtract(const Duration(days: 1));

  List<String> trackOfCfg({
    String newCheck = 'En2Ch',
    List<String> newCorrect = const ['Ch2En'],
    List<String> newWrong = const ['Ch2En'],
    String reviewCheck = 'En2Ch',
    List<String> reviewCorrect = const [],
    List<String> reviewWrong = const ['Ch2En'],
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    int? todayFirstLogRating,
  }) =>
      StudyTrack.trackOf(
        stability: stability,
        state: state,
        lastLearningDate: lastLearningDate,
        todayFirstLogElapsedDays: todayFirstLogElapsedDays,
        todayFirstLogRating: todayFirstLogRating,
        newCheck: newCheck,
        newCorrect: newCorrect,
        newWrong: newWrong,
        reviewCheck: reviewCheck,
        reviewCorrect: reviewCorrect,
        reviewWrong: reviewWrong,
        today: today,
      );

  group('StudyTrack.trackOf 轨道分配', () {
    test('新词（stability null 或 0）走学习轨道；测评未提交 → 仅 [测评, List]', () {
      expect(trackOfCfg(stability: null), ['En2Ch', 'List']);
      expect(trackOfCfg(stability: 0.0), ['En2Ch', 'List']);
    });

    test('今天首条评分日志 elapsedDays==0（init，今天新学）→ 学习轨道，答对走答对组', () {
      expect(
        trackOfCfg(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          todayFirstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('今天首条评分日志 elapsedDays==0 且答错 → 学习轨道答错组', () {
      expect(
        trackOfCfg(
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          todayFirstLogRating: FsrsRating.again.value,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('今天首条评分日志 elapsedDays>0（跨天复习）→ 复习轨道，答对组为空 → [测评, List]', () {
      expect(
        trackOfCfg(
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          todayFirstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'List'],
      );
    });

    test('今天首条评分日志 elapsedDays>0 且答错 → 复习轨道答错组', () {
      expect(
        trackOfCfg(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          todayFirstLogRating: FsrsRating.again.value,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('今天尚无评分且已有进度 → 复习轨道（测评未提交，仅 [测评, List]）', () {
      expect(
        trackOfCfg(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
        ),
        ['En2Ch', 'List'],
      );
    });

    test('复习词使用复习三组配置（check/答对组/答错组均为复习自己的）', () {
      expect(
        trackOfCfg(
          reviewCheck: 'EnSentence2Ch',
          reviewCorrect: const ['ChSentence2En'],
          reviewWrong: const ['Ch2En'],
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          todayFirstLogRating: FsrsRating.good.value,
        ),
        ['EnSentence2Ch', 'ChSentence2En', 'List'],
      );
      expect(
        trackOfCfg(
          reviewCheck: 'EnSentence2Ch',
          reviewCorrect: const ['ChSentence2En'],
          reviewWrong: const ['Ch2En'],
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          todayFirstLogRating: FsrsRating.again.value,
        ),
        ['EnSentence2Ch', 'Ch2En', 'List'],
      );
    });

    test('新词答对组为空 → 评分后轨道不扩展（[测评, List]，由 skipGroupSteps +2 直接完成）', () {
      expect(
        trackOfCfg(
          newCorrect: const [],
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          todayFirstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'List'],
      );
    });
  });

  group('StudyTrack.isReviewTrack 轨道判定', () {
    test('无评分且无进度 → 学习轨道', () {
      expect(
        StudyTrack.isReviewTrack(stability: null, today: today),
        false,
      );
      expect(
        StudyTrack.isReviewTrack(stability: 0.0, today: today),
        false,
      );
    });

    test('轨道固化：今天首条日志 elapsedDays==0 时，即使 state 已是 review 也保持学习轨道', () {
      expect(
        StudyTrack.isReviewTrack(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          today: today,
        ),
        false,
      );
    });

    test('今天首条日志 elapsedDays>0 → 复习轨道', () {
      expect(
        StudyTrack.isReviewTrack(
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          today: today,
        ),
        true,
      );
    });

    test('今天尚无评分但已有进度 → 复习轨道', () {
      expect(
        StudyTrack.isReviewTrack(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
          today: today,
        ),
        true,
      );
    });
  });

  group('StudyTrack.oppositeWordStep 反向互补', () {
    test('英→中方向 → Ch2En；中→英方向 → En2Ch', () {
      expect(StudyTrack.oppositeWordStep('En2Ch'), 'Ch2En');
      expect(StudyTrack.oppositeWordStep('EnSentence2Ch'), 'Ch2En');
      expect(StudyTrack.oppositeWordStep('Ch2En'), 'En2Ch');
      expect(StudyTrack.oppositeWordStep('ChSentence2En'), 'En2Ch');
    });
  });

  group('StudyTrack.hasMoreGradedSteps', () {
    test('List 不计入评分环节', () {
      final track = ['En2Ch', 'Ch2En', 'List'];
      expect(StudyTrack.hasMoreGradedSteps(track, 0), true);
      expect(StudyTrack.hasMoreGradedSteps(track, 1), false);
      expect(StudyTrack.hasMoreGradedSteps(track, 2), false);
    });

    test('学习轨道最后评分环节后无评分环节', () {
      final track = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'List'];
      expect(StudyTrack.hasMoreGradedSteps(track, 0), true);
      expect(StudyTrack.hasMoreGradedSteps(track, 1), true);
      expect(StudyTrack.hasMoreGradedSteps(track, 2), false);
    });
  });
}
