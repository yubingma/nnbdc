import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/modes/list_mode_item.dart';
import 'package:nnbdc/page/word_list/word_list_actions.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';

class _NoopActions with WordListActionHandler {
  @override
  void onWordTap(WordWrapper word, int index) {}
  @override
  void onWordLongPress(WordWrapper word, int index) {}
  @override
  void onMasterBtnPressed(WordWrapper word, int index) {}
  @override
  void onUnmasterBtnPressed(WordWrapper word, int index) {}
  @override
  void onDelBtnPressed(WordWrapper word, int index) {}
  @override
  void onEditBtnPressed(WordWrapper word, int index) {}
  @override
  void onResetHint(WordWrapper word) {}
  @override
  void onGiveHint(WordWrapper word) {}
  @override
  void onToggleAnswer(WordWrapper word, int index) {}
  @override
  void onHandwritingPressed(WordWrapper word, int index) {}
  @override
  void onSpellChanged(WordWrapper word, int index, String value) {}
}

/// 进度环的显示口径：**在「已掌握」词书里就是满分**。
///
/// 手动标记掌握的词可能稳定度为空、或低于掌握线（例如 30.0，掌握线 120.0），
/// 若拿稳定度数值推断进度，它们会被显示成没背完。本测试锁死"已掌握 ⇒ 满分"，
/// 同时锁死未掌握的词仍按 稳定度 ÷ 满分 展示 —— 界面满分值只能来自
/// wordProgressProvider.getWordProgressMax（掌握线），不得再出现 180.0 这类第二套数。
void main() {
  Future<double?> pumpRingAndReadRatio(
    WidgetTester tester, {
    required bool? learningStatus,
    required double currentProgress,
    required double maxProgress,
  }) async {
    final WordWrapper word = WordWrapper(
      (WordVo.c2('apple')..id = 'w_apple'),
      null,
    )
      ..currentLearningStatus = learningStatus
      ..currentProgress = currentProgress
      ..maxProgress = maxProgress;

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: MaterialApp(
          home: Scaffold(
            body: ListModeItem(
              word: word,
              index: 0,
              baseIndex: 0,
              isBookmarked: false,
              isDarkMode: false,
              learningStatus: learningStatus,
              showWordProgress: true,
              actions: _NoopActions(),
              slidableActions: const [],
            ),
          ),
        ),
      ),
    );

    final rings = tester
        .widgetList<CircularProgressIndicator>(find.byType(CircularProgressIndicator))
        .toList();
    expect(rings.length, 1, reason: '环形熟练度徽章应恰好渲染一个进度环');
    return rings.first.value;
  }

  testWidgets('已掌握词显示满分进度环：稳定度 30.0（低于掌握线）也必须是 100%', (tester) async {
    final ratio = await pumpRingAndReadRatio(tester,
        learningStatus: true, currentProgress: 30.0, maxProgress: 120.0);
    expect(ratio, 1.0, reason: '在「已掌握」词书里即 100%，不得按 30.0 ÷ 120.0 = 25% 显示');
  });

  testWidgets('已掌握词显示满分进度环：稳定度为空也必须是 100%', (tester) async {
    final ratio = await pumpRingAndReadRatio(tester,
        learningStatus: true, currentProgress: 0.0, maxProgress: 120.0);
    expect(ratio, 1.0, reason: '稳定度为空不影响已掌握的满分显示');
  });

  testWidgets('未掌握词仍按 稳定度 ÷ 满分 展示（不是一刀切满分）', (tester) async {
    final ratio = await pumpRingAndReadRatio(tester,
        learningStatus: false, currentProgress: 30.0, maxProgress: 120.0);
    expect(ratio, closeTo(0.25, 1e-9), reason: '学习中：30.0 ÷ 120.0 = 25%');
  });
}
