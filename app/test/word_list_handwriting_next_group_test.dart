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

/// 阶段复习（本组小结）里打开手写后，底部「重写/回退/关闭/提示」那张操作卡
/// 曾经铺满整页宽度，把页面底部的「下一组」遮住大半、并且吃掉它的点击。
///
/// 现在：底部这一条是页面底栏，独占一条纵向空间——手写工具条（重写/回退/关闭/提示）
/// 在左、「下一组」在右，词卡与手写画布都止步于它上沿，谁也不会压到词卡上。
/// 宽屏工具条带文字，窄屏只画图标（更小），两种宽度都能并排放得下。
///
/// 只保留一个 testWidgets：手写模式的入场会等一次音频会话释放，而音频会话是
/// 进程级单例，同一个测试文件里反复进出会把它的队列拖住（后续用例卡在
/// 「模式切换中…」）。所以这里只进一次手写，再改视口尺寸覆盖各形态。
class _WordsProvider with WordsProvider {
  final List<WordWrapper> items;

  _WordsProvider(this.items);

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final result = PagedResults<WordWrapper>(items.length);
    result.rows = items;
    return result;
  }

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
const Key _handwritingCardKey = Key('handwriting_control_card');

var _nextGroupTapped = false;

Future<void> _pumpStageReview(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  final args = WordListPageArgs(
    '本组小结',
    _WordsProvider(
      List.generate(4, (i) => WordWrapper(WordVo.c2('apple')..id = 'id_$i', null)),
    ),
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
  testWidgets('手写工具条与「下一组」共用底部独立一条：不压词卡/画布，各尺寸都能点', (tester) async {
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

      final String label = '${size.width.toInt()}×${size.height.toInt()}';
      final bool wide = size.width >= 560;
      final overlayRect = tester.getRect(find.byType(HandwritingOverlay));
      final buttonRect = tester.getRect(find.byKey(_nextGroupKey));
      final cardRect = tester.getRect(find.byKey(_handwritingCardKey));

      expect(overlayRect.width, size.width, reason: '$label：手写覆盖层应铺满宽度');
      // 底部这一条是内容区之外的独立空间：画布/词卡止步于它的上沿
      expect(overlayRect.bottom, lessThan(size.height),
          reason: '$label：画布不能再铺到屏幕最底，底部要留出工具条和按钮的独立空间');
      expect(overlayRect.bottom, lessThanOrEqualTo(cardRect.top),
          reason: '$label：手写工具条必须整块落在画布之外（不能再压在书写区/词卡上）');
      expect(overlayRect.bottom, lessThanOrEqualTo(buttonRect.top),
          reason: '$label：「下一组」也必须整块落在画布之外');
      // 工具条与「下一组」在同一行，左右分开
      expect(cardRect.overlaps(buttonRect), isFalse,
          reason: '$label：「下一组」被手写工具条盖住了');
      expect(cardRect.right, lessThanOrEqualTo(buttonRect.left),
          reason: '$label：工具条必须在「下一组」左侧');
      expect(cardRect.width, lessThan(size.width * 0.75),
          reason: '$label：工具条应缩成一小块，不能铺满整行');
      expect(size.height - cardRect.bottom, 24.0,
          reason: '$label：工具条与「下一组」同一条底线（离屏幕底 24px）');
      expect(cardRect.left, 16.0, reason: '$label：工具条贴左缘 16px');
      // 宽屏按钮贴右 28px；窄屏工具条只画图标，按钮也收在右边
      expect(size.width - buttonRect.right, wide ? 28.0 : 16.0,
          reason: '$label：「下一组」右边距不对');

      // 卡片右端的画笔按钮必须整颗待在右侧竖条里，且和分界线之间留出呼吸空间
      final lineRect = tester.getRect(find.byKey(const Key('handwriting_right_zone_line')));
      expect(size.width - lineRect.left, 92.0,
          reason: '$label：右侧交互竖条的宽度应为 92px（76px 画笔位 + 16px 呼吸）');
      final pencil = tester.getRect(find.byIcon(Icons.edit_rounded).first);
      expect(pencil.left - lineRect.right, greaterThanOrEqualTo(20.0),
          reason: '$label：分界线与画笔图标贴得太近');
      expect(pencil.center.dx - 25.0, greaterThan(lineRect.right),
          reason: '$label：画笔按钮左半截不能压在画布下面（否则点不到）');

      _nextGroupTapped = false;
      await tester.tap(find.byKey(_nextGroupKey));
      await tester.pump(const Duration(milliseconds: 20));
      expect(_nextGroupTapped, isTrue,
          reason: '$label：手写面板打开时「下一组」仍然要能点');
    }

    // 页面 dispose 里用 Timer.run 释放单词资源，收尾推进一帧把它跑掉，避免残留 timer 判失败
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
