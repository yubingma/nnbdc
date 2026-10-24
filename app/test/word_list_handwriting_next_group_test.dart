import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/widgets/handwriting_overlay.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/widget/minimal_flow_button.dart';
import 'package:provider/provider.dart' as provider;

/// 阶段复习（本组小结）里打开手写后，底部「重写/回退/关闭/提示」那条操作栏
/// 曾经铺满整页宽度，把页面底部的「下一组」遮住大半、并且吃掉它的点击。
///
/// 现在的分工：手写覆盖层只铺满内容区（body），「下一组」留在 Scaffold 的底栏里。
/// 这个用例在 iPad 横屏、iPad 竖屏、常规手机、小屏手机上逐一量：
/// 按钮必须整个落在手写覆盖层之外，并且手写面板开着时照样点得动。
///
/// 只保留一个 testWidgets：手写模式的入场会等一次音频会话释放，而音频会话是
/// 进程级单例，同一个测试文件里反复进出会把它的队列拖住（后续用例卡在
/// 「模式切换中…」）。所以这里只进一次手写，再改视口尺寸覆盖各形态。
class _NoWordProvider with WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async =>
      PagedResults<WordWrapper>(0);

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => true;

  @override
  Future<int> getWordIndex(String spell) async => -1;
}

class _NoBookMarkProvider implements BookMarkProvider {
  @override
  String? get bookMarkName => null;

  @override
  Future<BookMarkVo?> getBookMark() async => null;

  @override
  Future<bool> saveBookMark(BookMarkVo value) async => true;
}

class _NoProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(dynamic wordTag) => 0.0;

  @override
  double getWordProgressMax(dynamic wordTag) => 1.0;
}

const Key _nextGroupKey = Key('injected_flow_btn');

var _nextGroupTapped = false;

Future<void> _pumpStageReview(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  final args = WordListPageArgs(
    '本组小结',
    _NoWordProvider(),
    true,
    false,
    false,
    '',
    _NoProgressProvider(),
    _NoBookMarkProvider(),
    MinimalFlowButton(
      tapKey: _nextGroupKey,
      label: '下一组',
      onTap: () => _nextGroupTapped = true,
    ),
  );

  final router = GoRouter(
    initialLocation: '/word_list',
    initialExtra: args,
    routes: [
      GoRoute(
        path: '/word_list',
        builder: (context, routerState) => const WordListPage(),
      ),
    ],
  );

  await tester.pumpWidget(
    provider.ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // 页面常驻呼吸动画，pumpAndSettle 永远不会返回，只能逐帧推进到数据加载完成
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 从「更多」菜单切到「拼写(手写)」：手写覆盖层随即铺开
Future<void> _openHandwriting(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  // 菜单入场动画只有 160ms，但同样不能用 pumpAndSettle（页面呼吸动画常驻）
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.tap(find.text('拼写(手写)'));
  // 先让菜单退场、切模式的状态落地，再等「模式切换中…」浮层撤掉
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  for (var i = 0; i < 80 && find.text('模式切换中...').evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('模式切换中...'), findsNothing,
      reason: '切到手写模式后「模式切换中…」浮层必须撤掉，否则页面上的按钮都点不动');
}

void main() {
  testWidgets('手写面板打开时「下一组」不被操作栏遮挡，且横竖屏、小屏手机都能点', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpStageReview(tester, const Size(1024, 768));
    await _openHandwriting(tester);
    expect(find.byType(HandwritingOverlay), findsOneWidget,
        reason: '切到手写模式后应出现手写覆盖层');

    for (final size in const <Size>[
      Size(1024, 768), // iPad 横屏
      Size(768, 1024), // iPad 竖屏
      Size(844, 390), // 手机横屏（内容区最矮）
      Size(390, 844), // 常规手机竖屏
      Size(320, 568), // 小屏手机
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();

      final overlayRect = tester.getRect(find.byType(HandwritingOverlay));
      final buttonRect = tester.getRect(find.byKey(_nextGroupKey));
      expect(overlayRect.width, size.width,
          reason: '${size.width.toInt()}×${size.height.toInt()}：手写覆盖层应铺满内容区宽度');
      expect(buttonRect.top, greaterThanOrEqualTo(overlayRect.bottom),
          reason: '${size.width.toInt()}×${size.height.toInt()}：'
              '「下一组」必须整个落在手写覆盖层之外（操作栏不得压到它上面）');
      expect(tester.getRect(find.text('重写')).bottom,
          lessThanOrEqualTo(overlayRect.bottom),
          reason: '${size.width.toInt()}×${size.height.toInt()}：'
              '手写操作栏的「重写」必须留在手写覆盖层内');
      expect(buttonRect.bottom, lessThanOrEqualTo(size.height),
          reason: '「下一组」不能被挤出屏幕底部');

      _nextGroupTapped = false;
      await tester.tap(find.byKey(_nextGroupKey));
      await tester.pump(const Duration(milliseconds: 20));
      expect(_nextGroupTapped, isTrue,
          reason: '${size.width.toInt()}×${size.height.toInt()}：'
              '手写面板打开时「下一组」仍然要能点');
    }

    // 页面 dispose 里用 Timer.run 释放单词资源，收尾推进一帧把它跑掉，避免残留 timer 判失败
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
