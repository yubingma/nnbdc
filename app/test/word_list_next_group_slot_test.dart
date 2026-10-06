import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/widget/minimal_flow_button.dart';
import 'package:provider/provider.dart' as provider;

/// 阶段复习（本组小结）底部「下一组」流转按钮的落点：
/// 必须与背单词页「下一词」完全相同（iPad 等宽屏贴右下角、离屏幕右缘 28px），
/// 手机窄屏才居中。宽屏居中会让按钮停在双手拇指都够不到的屏幕中段。
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

/// 背单词页在 List 环节（阶段复习）注入的流转按钮，这里按同样方式注入以便量它的落点
const Key _nextGroupKey = Key('injected_flow_btn');

Future<void> _pumpStageReview(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

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
      onTap: () {},
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

/// 页面 dispose 里用 Timer.run 释放单词资源，收尾推进一帧把它跑掉，避免残留 timer 判失败
Future<void> _settleDispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('iPad 宽屏：阶段复习「下一组」与背单词页「下一词」同落点（离屏幕右缘 28px）', (tester) async {
    await _pumpStageReview(tester, const Size(800, 1000));

    final finder = find.byKey(_nextGroupKey);
    expect(finder, findsOneWidget, reason: '阶段复习页应展示「下一组」流转按钮');

    final rightMargin = 800.0 - tester.getRect(finder).right;
    expect(rightMargin, 28.0,
        reason: '宽屏下「下一组」右边距必须与「下一词」相同为 28.0px，否则缩在屏幕中段拇指够不到');

    // 用户反馈的本体：宽屏下按钮文字必须落在右半屏，而不是屏幕中段
    expect(tester.getCenter(find.text('下一组')).dx, greaterThan(400.0),
        reason: '宽屏下「下一组」必须靠右下角（拇指可达区），不得居中');

    await _settleDispose(tester);
  });

  testWidgets('手机窄屏：阶段复习「下一组」保持居中', (tester) async {
    await _pumpStageReview(tester, const Size(390, 844));

    final finder = find.byKey(_nextGroupKey);
    expect(finder, findsOneWidget, reason: '阶段复习页应展示「下一组」流转按钮');

    final rect = tester.getRect(finder);
    // 页面左右内缩相差 2px（leftPadding 6 / rightPadding 8），居中时相对屏幕中线偏 2px
    expect((rect.left - (390.0 - rect.right)).abs(), lessThan(3.0),
        reason: '手机窄屏下「下一组」应保持居中');
    expect((tester.getCenter(find.text('下一组')).dx - 195.0).abs(), lessThan(3.0),
        reason: '手机窄屏下「下一组」文字应停在屏幕中线附近');

    await _settleDispose(tester);
  });
}
