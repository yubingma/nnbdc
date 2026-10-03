// 临时探针：把回看模式学习页渲染成 PNG，用于人工核对横幅与顶部按钮的版面关系。
// 核对完即删，不属于正式测试。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart' as provider;

class _MockNotifier extends BdcNotifier {
  final BdcState initialState;
  _MockNotifier(this.initialState);

  @override
  BdcState build() => initialState;

  @override
  bool get hasSeenAnswer => true;

  @override
  Future<void> loadData(BuildContext? context, {bool isAutoTest = false}) async {}
}

void main() {
  testWidgets('渲染回看模式学习页 PNG', (tester) async {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
    PlatformUtils.isDesktopOverride = false;
    addTearDown(() {
      PlatformUtils.asrSupportedOverride = null;
      PlatformUtils.englishAsrSupportedOverride = null;
      PlatformUtils.isDesktopOverride = null;
    });

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    final testWord = WordVo.c2('apple')
      ..id = 'w_apple'
      ..setMeaningStr('n. 苹果');
    testWord.meaningItems = [MeaningItemVo('mi_1', 'n.', '苹果', null, null, [])];
    final testLw = LearningWordVo(
      UserVo.c2('user1'),
      DateTime.now(),
      1,
      DateTime.now(),
      1,
      0,
      testWord,
    );
    final mockResult = GetWordResult(
      testLw,
      0,
      null,
      [1, 10],
      null,
      false,
      false,
      [],
      [],
      [],
      null,
      [],
      [],
      [],
      false,
      false,
    );
    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: WordWrapper(testWord, null),
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: true,
      hasFinishedAnswering: true,
      history: [mockResult],
      historyIndex: 0,
    );

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: provider.ChangeNotifierProvider<DarkMode>(
          create: (_) => DarkMode(),
          child: ProviderScope(
            overrides: [
              bdcNotifierProvider.overrideWith(() => _MockNotifier(state)),
            ],
            child: const MaterialApp(
              home: Scaffold(body: BdcPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/Volumes/ssd/ppdc/tmp/review_banner_after.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
