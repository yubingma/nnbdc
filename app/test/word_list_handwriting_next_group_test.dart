import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/widgets/handwriting_overlay.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:nnbdc/widget/minimal_flow_button.dart';
import 'package:provider/provider.dart' as provider;

/// 阶段复习（本组小结）里打开手写后，底部「重写/回退/关闭/提示」那张操作卡
/// 曾经铺满整页宽度，把页面底部的「下一组」遮住大半、并且吃掉它的点击。
///
/// 现在：底部这一条是页面底栏，独占一条纵向空间——手写工具条（重写/回退/关闭/提示）
/// 在左、「下一组」在右，词卡与手写画布都止步于它上沿，谁也不会压到词卡上。
/// 宽屏工具条带文字，窄屏只画图标（更小），两种宽度都能并排放得下。
/// 手写区罩了一层极淡的半透明蒙版，与右侧卡片交互竖条在颜色上分开（原来那条分界线压着画笔）；
/// 蒙版还兼作状态提示：落笔时铺满全宽（右侧竖条此刻也算手写区），停笔约 0.5s 后退回
/// （右侧竖条恢复为可拖动列表/点画笔的区域）。
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
  testWidgets('手写工具条与「下一组」共用底部独立一条，各尺寸都能点；蒙版随书写状态伸缩', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 手写识别通道：本用例只验证蒙版状态，落笔触发的自动识别返回空串即可
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nnbdc/ocr'), (call) async {
      if (call.method == 'recognizeHandwriting') return '';
      return null;
    });

    await _pumpStageReview(tester, const Size(1024, 768));
    await _openHandwriting(tester);
    expect(find.byType(HandwritingOverlay), findsOneWidget,
        reason: '切到手写模式后应出现手写覆盖层');

    // 蒙版本身就是状态提示：
    // 落笔 → 铺满全宽（右侧竖条暂时也算手写区）；停笔约 0.5s → 退回，右侧恢复为可拖动/可点画笔。
    final veil = find.byKey(const Key('handwriting_area_veil'));
    expect(tester.getRect(veil).right, 1024.0 - 76.0,
        reason: '静止状态：右侧 76px 不应罩蒙版，提示这里可以拖动/点画笔');

    final gesture = await tester.startGesture(const Offset(320, 320));
    await gesture.moveBy(const Offset(40, 12));
    await tester.pump(); // 落笔把蒙版目标值改成 0
    await tester.pump(const Duration(milliseconds: 220)); // 180ms 位移过渡
    expect(tester.getRect(veil).right, 1024.0,
        reason: '落笔后：蒙版应铺满全宽，提示右侧竖条此刻也算手写区');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350)); // 停笔后的自动识别落地
    await tester.pump(const Duration(milliseconds: 300)); // 停笔 0.5s → 竖条恢复
    await tester.pump(); // 目标值改回 76，过渡开始
    await tester.pump(const Duration(milliseconds: 220)); // 180ms 位移过渡
    expect(tester.getRect(veil).right, 1024.0 - 76.0,
        reason: '停笔一段时间后：蒙版应退回，重新提示右侧可以拖动/点画笔');

    // 左滑露出「掌握 / 详情」：手写面板必须把整块面板让出来，否则按钮压在画布下点不到。
    // 该词表两颗粒按钮 → 面板宽度 = 0.5 × 卡片行宽；右侧页面内边距 8px 也算在让位里。
    final double paneExposed = 0.5 * (1024 - 14) + 8;
    final slideGesture = await tester.startGesture(const Offset(994, 100));
    await slideGesture.moveBy(const Offset(-400, 0));
    await slideGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // 蒙版 180ms 位移过渡
    expect(tester.getRect(find.byType(HandwritingBoard)).right,
        closeTo(1024.0 - paneExposed, 1.0),
        reason: '左滑面板打开后，画布要让出整块面板');
    expect(tester.getRect(find.byKey(const Key('handwriting_area_veil'))).right,
        closeTo(1024.0 - paneExposed, 1.0),
        reason: '左滑面板打开后，蒙版也要让出整块面板，按钮才是「露出来」的');
    for (final label in ['掌握', '详情']) {
      expect(tester.getRect(find.text(label)).left,
          greaterThanOrEqualTo(1024.0 - paneExposed - 0.5),
          reason: '「$label」按钮必须露在画布之外，否则点不到');
    }

    // 一落笔：露出的面板自动收回，门板重新铺满（书写优先）
    final writeGesture = await tester.startGesture(const Offset(200, 300));
    await writeGesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220)); // 蒙版过渡
    expect(tester.getRect(find.byType(HandwritingBoard)).right, 1024.0,
        reason: '开始书写后，画布应铺满整宽（书写优先）');
    expect(tester.getRect(find.byKey(const Key('handwriting_area_veil'))).right,
        1024.0,
        reason: '开始书写后，蒙版也应向右覆盖');
    await writeGesture.up();
    await tester.pump(const Duration(milliseconds: 350)); // 自动识别 + 面板收起动画落地
    await tester.pump(const Duration(milliseconds: 300)); // 停笔 0.5s → 恢复到默认竖条
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // 蒙版过渡
    expect(tester.getRect(find.byType(HandwritingBoard)).right,
        closeTo(1024.0 - 76.0, 1.0),
        reason: '开始书写已把面板收回，停笔后应回到默认 76px 竖条');
    expect(find.text('掌握'), findsNothing,
        reason: '开始书写后，露出的左滑面板必须自动收回');

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

      // 画布右侧给卡片画笔让出的竖条：画笔图标必须露在画布外（否则点不到）
      final boardRect = tester.getRect(find.byType(HandwritingBoard));
      expect(size.width - boardRect.right, 76.0,
          reason: '$label：画布右侧应为画笔让出 76px 交互竖条');
      final pencil = tester.getRect(find.byIcon(Icons.edit_rounded).first);
      expect(pencil.center.dx, greaterThan(boardRect.right),
          reason: '$label：画笔图标必须落在画布之外的交互竖条里');
      expect(pencil.left - boardRect.right, greaterThanOrEqualTo(20.0),
          reason: '$label：画笔图标与蒙版右沿之间要留出足够的呼吸空间（不能贴着蒙版）');

      // 手写区蒙版：右沿与画布对齐，右侧竖条留白不罩；必须够淡，词卡还要看得清
      final veil = find.byKey(const Key('handwriting_area_veil'));
      expect(veil, findsOneWidget, reason: '$label：手写区应有半透明蒙版');
      expect(tester.getRect(veil).right, size.width - 76.0,
          reason: '$label：蒙版右沿应止于右侧交互竖条左侧，两块区域要靠颜色分开');
      final veilAlpha = tester.widget<ColoredBox>(veil).color.a;
      expect(veilAlpha, greaterThan(0.0), reason: '$label：蒙版不能是透明的');
      expect(veilAlpha, lessThan(0.2),
          reason: '$label：蒙版必须够淡，手写时要看得清当前单词的卡片');

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
