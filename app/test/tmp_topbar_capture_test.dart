// 临时像素取证：把学习页顶栏渲染成 PNG，客观核对「更多」按钮区域的形态。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
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

(WordVo, GetWordResult) _createTestData() {
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
  final mockGetWordResult = GetWordResult(
    testLw, 0, null, [1, 10], null, false, false, [], [], [], null, [], [], [],
    false, false,
  );
  return (testWord, mockGetWordResult);
}

final GlobalKey _rootKey = GlobalKey();

Widget _buildPage(_MockNotifier notifier) {
  return provider.ChangeNotifierProvider<DarkMode>(
    create: (_) => DarkMode(),
    child: ProviderScope(
      overrides: [bdcNotifierProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(key: _rootKey, child: const BdcPage()),
        ),
      ),
    ),
  );
}

Future<void> _dump(String name) async {
  final RenderRepaintBoundary boundary =
      _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('/Volumes/ssd/ppdc/tmp/$name').writeAsBytes(
    data!.buffer.asUint8List(),
  );
}

void main() {
  setUp(() {
    PlatformUtils.asrSupportedOverride = true;
    PlatformUtils.englishAsrSupportedOverride = true;
    PlatformUtils.isDesktopOverride = false;
  });
  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    PlatformUtils.englishAsrSupportedOverride = null;
    PlatformUtils.isDesktopOverride = null;
  });

  testWidgets('capture study top bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    final (testWord, mockResult) = _createTestData();
    final state = const BdcState().copyWith(
      dataLoaded: true,
      word: testWord,
      currentGetWordResult: mockResult,
      wordWrapper: WordWrapper(testWord, null),
      studyStep: StudyStep.en2Ch.json,
      showAnswerButtons: true,
      canLeaveCurrWord: true,
    );
    await tester.pumpWidget(_buildPage(_MockNotifier(state)));
    await tester.pumpAndSettle();

    // 清掉测试环境缺失插件带来的异常噪声
    for (int i = 0; i < 8; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      // ignore: avoid_print
      print('NOISE: $e');
    }

    // 各控件几何
    final moreRect = tester.getRect(find.byIcon(Icons.more_vert_rounded));
    final masteredRect =
        tester.getRect(find.byIcon(Icons.check_circle_outline_rounded));
    final backRect =
        tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded));
    final rowRect = tester.getRect(find.byType(Wrap).first);
    // ignore: avoid_print
    print('GEOM more=$moreRect mastered=$masteredRect back=$backRect wrap=$rowRect');
    // ignore: avoid_print
    print('SCREEN=${tester.view.physicalSize} TOPPAD=${tester.view.padding.top}');

    // 「更多」按钮自身的可点区域（PopupMenuButton 的 InkWell/Padding）
    final moreHit = tester.getRect(find.byType(PopupMenuButton<dynamic>));
    final masteredHit = tester.getRect(find.byKey(const Key('bdc_mastered_btn')));
    // ignore: avoid_print
    print('HIT moreBox=$moreHit masteredBox=$masteredHit');

    await tester.runAsync(() async {
      await _dump('topbar_rest.png');
    });

    // 按下态：观察水波纹/热区
    final gesture = await tester.press(find.byIcon(Icons.more_vert_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await _dump('topbar_pressed.png');
    });
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
