import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_track.dart';

void main() {
  final today = AppClock.today();
  final yesterday = today.subtract(const Duration(days: 1));
  final List<String> steps3 = ['En2Ch', 'Ch2En', 'List'];
  final List<String> stepsSentenceOnly = ['EnSentence2Ch', 'ChSentence2En', 'List'];

  List<String> trackOfNew({
    List<String> activeStepNames = const ['En2Ch', 'Ch2En', 'List'],
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    List<String> reviewCheckSteps = const [],
    List<String> reviewCorrectSteps = const [],
    List<String> reviewWrongSteps = const [],
    int? todayFirstLogRating,
  }) =>
      StudyTrack.trackOf(
        activeStepNames: activeStepNames,
        stability: stability,
        state: state,
        lastLearningDate: lastLearningDate,
        todayFirstLogElapsedDays: todayFirstLogElapsedDays,
        reviewCheckSteps: reviewCheckSteps,
        reviewCorrectSteps: reviewCorrectSteps,
        reviewWrongSteps: reviewWrongSteps,
        todayFirstLogRating: todayFirstLogRating,
        today: today,
      );

  group('StudyTrack.trackOf 轨道分配', () {
    test('新词（stability null 或 0）走学习轨道', () {
      expect(trackOfNew(stability: null), steps3);
      expect(trackOfNew(stability: 0.0), steps3);
    });

    test('今天首条评分日志 elapsedDays==0（init，今天新学）→ 学习轨道', () {
      expect(
        trackOfNew(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
        ),
        steps3,
      );
    });

    test('今天首条评分日志 elapsedDays>0（跨天复习/学一半次日）→ 复习轨道', () {
      // 未设置回退：答对组为空 → good 评分后轨道 [测评, List]
      expect(
        trackOfNew(
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          todayFirstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'List'],
      );
    });

    test('今天尚无评分且已有进度 → 复习轨道（测评未提交，仅测评+List）', () {
      expect(
        trackOfNew(
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: yesterday,
        ),
        ['En2Ch', 'List'],
      );
    });

    test('轨道固化：今天首条日志为 init 后，即使 state 已是 review 也保持学习轨道', () {
      expect(
        StudyTrack.isReviewTrack(
          activeStepNames: steps3,
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          today: today,
        ),
        false,
      );
    });
  });

  group('StudyTrack.reviewTrack 三组显式规则', () {
    test('已设置：测评+答对组（首条日志 good）', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: ['En2Ch'],
          reviewCorrectSteps: ['Ch2En'],
          reviewWrongSteps: ['EnSentence2Ch'],
          fallbackActiveStepNames: steps3,
          firstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('已设置：测评+答错组（首条日志 again）', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: ['En2Ch'],
          reviewCorrectSteps: ['Ch2En'],
          reviewWrongSteps: ['EnSentence2Ch'],
          fallbackActiveStepNames: steps3,
          firstLogRating: FsrsRating.again.value,
        ),
        ['En2Ch', 'EnSentence2Ch', 'List'],
      );
    });

    test('已设置：答对组为空 → 测评后直接 List（评分后轨道）', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: ['En2Ch'],
          reviewCorrectSteps: [],
          reviewWrongSteps: ['Ch2En'],
          fallbackActiveStepNames: steps3,
          firstLogRating: FsrsRating.good.value,
        ),
        ['En2Ch', 'List'],
      );
    });

    test('未设置（空配置）回退：测评=新词第1、答错=[反向互补]', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: [],
          reviewCorrectSteps: [],
          reviewWrongSteps: [],
          fallbackActiveStepNames: steps3,
          firstLogRating: FsrsRating.again.value,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('未设置且测评是例句中→英 → 回退答错=[英→中]', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: [],
          reviewCorrectSteps: [],
          reviewWrongSteps: [],
          fallbackActiveStepNames: stepsSentenceOnly,
          firstLogRating: FsrsRating.again.value,
        ),
        ['EnSentence2Ch', 'Ch2En', 'List'],
      );
    });

    test('测评未提交 → 仅 [测评, List]（评分后轨道扩展）', () {
      expect(
        StudyTrack.reviewTrack(
          reviewCheckSteps: ['En2Ch'],
          reviewCorrectSteps: ['Ch2En'],
          reviewWrongSteps: ['EnSentence2Ch'],
          fallbackActiveStepNames: steps3,
          firstLogRating: null,
        ),
        ['En2Ch', 'List'],
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
