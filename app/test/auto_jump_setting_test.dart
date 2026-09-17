import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/util/study_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('极速模式设置与跳转判定测试', () {
    test('BdcState.autoJumpAfterCorrect 正确响应 4 种题型对应的极速模式开关', () {
      final state = BdcState(
        autoJumpAfterCorrectCh2En: true,
        autoJumpAfterCorrectEn2Ch: false,
        autoJumpAfterCorrectChSentence2En: true,
        autoJumpAfterCorrectEnSentence2Ch: false,
      );

      expect(
        state.copyWith(studyStep: StudyStep.ch2En.json).autoJumpAfterCorrect,
        isTrue,
        reason: '汉译英应读取 autoJumpAfterCorrectCh2En',
      );

      expect(
        state.copyWith(studyStep: StudyStep.en2Ch.json).autoJumpAfterCorrect,
        isFalse,
        reason: '英译汉应读取 autoJumpAfterCorrectEn2Ch',
      );

      expect(
        state.copyWith(studyStep: StudyStep.chSentence2En.json).autoJumpAfterCorrect,
        isTrue,
        reason: '例句汉译英应读取 autoJumpAfterCorrectChSentence2En',
      );

      expect(
        state.copyWith(studyStep: StudyStep.enSentence2Ch.json).autoJumpAfterCorrect,
        isFalse,
        reason: '例句英译汉应读取 autoJumpAfterCorrectEnSentence2Ch',
      );
    });

    test('BdcNotifier.applyStudyConfig 能够原子同步所有学习设置（含例句英译汉与例句汉译英极速模式）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(bdcNotifierProvider.notifier);

      // 初始状态默认为全关闭或默认值
      final config = StudyConfig(
        autoJumpAfterCorrectCh2En: true,
        autoJumpAfterCorrectEn2Ch: true,
        autoJumpAfterCorrectChSentence2En: true,
        autoJumpAfterCorrectEnSentence2Ch: true,
        asrPassRule: 'ALL',
        showWordDetailAfterCorrect: true,
      );

      notifier.applyStudyConfig(config);

      final state = container.read(bdcNotifierProvider);
      expect(state.autoJumpAfterCorrectCh2En, isTrue);
      expect(state.autoJumpAfterCorrectEn2Ch, isTrue);
      expect(state.autoJumpAfterCorrectChSentence2En, isTrue);
      expect(state.autoJumpAfterCorrectEnSentence2Ch, isTrue);
      expect(state.asrPassRuleCache, 'ALL');
      expect(state.showWordDetailAfterCorrect, isTrue);

      // 验证例句英译汉在此配置下 autoJumpAfterCorrect 为 true
      final enSentenceState = state.copyWith(studyStep: StudyStep.enSentence2Ch.json);
      expect(enSentenceState.autoJumpAfterCorrect, isTrue);

      // 将例句英译汉单独关闭
      final updatedConfig = StudyConfig(
        autoJumpAfterCorrectCh2En: true,
        autoJumpAfterCorrectEn2Ch: true,
        autoJumpAfterCorrectChSentence2En: true,
        autoJumpAfterCorrectEnSentence2Ch: false,
      );
      notifier.applyStudyConfig(updatedConfig);

      final updatedState = container.read(bdcNotifierProvider);
      expect(updatedState.autoJumpAfterCorrectEnSentence2Ch, isFalse);
      final updatedEnSentenceState = updatedState.copyWith(studyStep: StudyStep.enSentence2Ch.json);
      expect(updatedEnSentenceState.autoJumpAfterCorrect, isFalse);
    });
  });
}
