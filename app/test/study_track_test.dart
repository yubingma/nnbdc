import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_track.dart';

void main() {
  final today = AppClock.today();
  final yesterday = today.subtract(const Duration(days: 1));
  final List<String> steps3 = ['En2Ch', 'Ch2En', 'List'];
  final List<String> stepsSentenceFirst = ['EnSentence2Ch', 'En2Ch', 'Ch2En', 'List'];
  final List<String> stepsSentenceOnly = ['EnSentence2Ch', 'ChSentence2En', 'List'];

  group('StudyTrack.trackOf 轨道分配', () {
    test('新词（stability null 或 0）走学习轨道', () {
      expect(StudyTrack.trackOf(activeStepNames: steps3, stability: null, today: today), steps3);
      expect(StudyTrack.trackOf(activeStepNames: steps3, stability: 0.0, today: today), steps3);
    });

    test('今天首条评分日志 elapsedDays==0（init，今天新学）→ 学习轨道', () {
      expect(
        StudyTrack.trackOf(
          activeStepNames: steps3,
          stability: 2.4,
          state: FsrsState.review.value,
          lastLearningDate: today,
          todayFirstLogElapsedDays: 0,
          today: today,
        ),
        steps3,
      );
    });

    test('今天首条评分日志 elapsedDays>0（跨天复习/学一半次日）→ 复习轨道', () {
      expect(
        StudyTrack.trackOf(
          activeStepNames: steps3,
          stability: 2.4,
          state: FsrsState.learning.value,
          lastLearningDate: yesterday,
          todayFirstLogElapsedDays: 1,
          today: today,
        ),
        ['En2Ch', 'Ch2En', 'List'],
      );
    });

    test('今天尚无评分且已有进度（到期复习词/学一半词）→ 复习轨道', () {
      for (final state in [FsrsState.learning.value, FsrsState.review.value, FsrsState.relearning.value]) {
        expect(
          StudyTrack.trackOf(
            activeStepNames: steps3,
            stability: 2.4,
            state: state,
            lastLearningDate: yesterday,
            today: today,
          ),
          ['En2Ch', 'Ch2En', 'List'],
        );
      }
    });

    test('轨道固化：今天首条日志为 init 后，即使 state 已是 review 也保持学习轨道', () {
      // 新词今天学完评分环节（state=review），但首条日志 elapsedDays==0 → 学习轨道继续走 List
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

  group('StudyTrack.reviewTrack 复习轨道构造', () {
    test('测评=En2Ch → 重测=Ch2En（方向互补）', () {
      expect(StudyTrack.reviewTrack(steps3), ['En2Ch', 'Ch2En', 'List']);
    });

    test('测评=Ch2En → 重测=En2Ch（方向互补）', () {
      expect(StudyTrack.reviewTrack(['Ch2En', 'En2Ch', 'List']), ['Ch2En', 'En2Ch', 'List']);
    });

    test('测评=例句英→中 → 重测=单词中→英（反向永远成立）', () {
      expect(
        StudyTrack.reviewTrack(stepsSentenceFirst),
        ['EnSentence2Ch', 'Ch2En', 'List'],
      );
    });

    test('测评=例句中→英 → 重测=单词英→中（反向永远成立）', () {
      expect(
        StudyTrack.reviewTrack(['ChSentence2En', 'En2Ch', 'List']),
        ['ChSentence2En', 'En2Ch', 'List'],
      );
    });

    test('仅例句激活（无单词环节）→ 重测仍由方向决定', () {
      expect(
        StudyTrack.reviewTrack(stepsSentenceOnly),
        ['EnSentence2Ch', 'Ch2En', 'List'],
      );
    });
  });

  group('StudyTrack.hasMoreGradedSteps', () {
    test('List 不计入评分环节', () {
      final track = ['En2Ch', 'Ch2En', 'List'];
      expect(StudyTrack.hasMoreGradedSteps(track, 0), true); // En2Ch 后还有 Ch2En
      expect(StudyTrack.hasMoreGradedSteps(track, 1), false); // Ch2En 后仅 List
      expect(StudyTrack.hasMoreGradedSteps(track, 2), false);
    });

    test('学习轨道最后评分环节后无评分环节', () {
      final track = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'List'];
      expect(StudyTrack.hasMoreGradedSteps(track, 0), true);
      expect(StudyTrack.hasMoreGradedSteps(track, 1), true);
      expect(StudyTrack.hasMoreGradedSteps(track, 2), false); // 例句后仅 List
    });
  });
}
