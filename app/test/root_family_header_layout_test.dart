import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/modes/list_mode_item.dart';
import 'package:nnbdc/page/word_list/modes/root_family_header_item.dart';
import 'package:nnbdc/page/word_list/modes/word_list_item_layout.dart';
import 'package:nnbdc/page/word_list/word_list_actions.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';

/// 组头与族首词必须**无缝相接成一张卡**（组头 bottom:0 + 首词 top:0）。
/// 用像素测量而非肉眼判断：一旦两者之间出现空隙，本测试失败。
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

void main() {
  testWidgets('组头与族首词无缝相接（无空隙）', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final headerWord = WordWrapper(
      WordVo.c2('tend')
        ..id = 'cigen:tend'
        ..shortDesc = '伸展'
        ..meaningStr = '7 词',
      CigenVo('tend', 'tend', spell: 'tend', category: 'ROOT', meaningCn: '伸展'),
    );
    final memberWord = WordWrapper(
      WordVo.c2('extend')
        ..id = 'w_extend'
        ..meaningItems = [MeaningItemVo.from('v.', '延伸')],
      Word(  // tag 任意，ListModeItem 只用 word
        id: 'w_extend',
        spell: 'extend',
        popularity: 1,
        createTime: DateTime(2026, 1, 1),
        updateTime: DateTime(2026, 1, 1),
      ),
    );
    final actions = _NoopActions();

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RootFamilyHeaderItem(
                    word: headerWord,
                    index: 0,
                    baseIndex: 0,
                    isDarkMode: false,
                    actions: actions,
                    groupPosition: GroupCardPosition.top,
                  ),
                  ListModeItem(
                    word: memberWord,
                    index: 0,
                    baseIndex: 0,
                    isBookmarked: false,
                    isDarkMode: false,
                    learningStatus: null,
                    showWordProgress: false,
                    actions: actions,
                    slidableActions: const [],
                    // 与生产一致：组头之下的首词用 middle（保留底部分隔线）
                    groupPosition: GroupCardPosition.middle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 两张卡片的外框（WordListItemLayout 的 Container）
    final rects = tester
        .widgetList(find.byType(WordListItemLayout))
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList()
      ..sort((a, b) => a.top.compareTo(b.top));

    expect(rects.length, 2, reason: '应有组头 + 首词两个布局');
    final gap = rects[1].top - rects[0].bottom;
    expect(gap, 0.0,
        reason: '组头与族首词之间不应有空隙（实际 gap=$gap，'
            '说明两者的 margin 没有对接：组头 bottom 应为 0、首词 top 应为 0）');

    // 圆角方向：组头必须是「上圆角 + 下直角」，首词是「上直角 + 下圆角」，
    // 否则两张卡的边缘各自闭合，视觉上依然割裂
    BorderRadius? radiusOf(int i) {
      final container = find.descendant(
        of: find.byWidget(tester.widgetList(find.byType(WordListItemLayout)).elementAt(i)),
        matching: find.byType(Container),
        matchRoot: true,
      );
      final decoration = tester.widget<Container>(container.first).decoration;
      return decoration is BoxDecoration ? decoration.borderRadius as BorderRadius? : null;
    }

    final headerLayouts =
        tester.widgetList<WordListItemLayout>(find.byType(WordListItemLayout)).toList();
    final headerIndex = headerLayouts.indexWhere((w) => w.headerContent != null);
    final memberIndex = headerLayouts.indexWhere((w) => w.headerContent == null);
    final headerRadius = radiusOf(headerIndex);
    final memberRadius = radiusOf(memberIndex);
    expect(headerRadius?.bottomLeft, Radius.zero, reason: '组头下角必须是直角');
    expect(headerRadius?.bottomRight, Radius.zero, reason: '组头下角必须是直角');
    expect(memberRadius?.topLeft, Radius.zero, reason: '首词上角必须是直角');
    expect(memberRadius?.topRight, Radius.zero, reason: '首词上角必须是直角');
    expect(headerRadius?.topLeft.x, greaterThan(0), reason: '组头上角应为圆角');

    // 组头不得投影：与首词共处一张卡，接缝处两道阴影会看起来像两张卡
    BoxDecoration? decoOf(int i) {
      final container = find.descendant(
        of: find.byWidget(tester.widgetList<WordListItemLayout>(
            find.byType(WordListItemLayout)).elementAt(i)),
        matching: find.byType(Container),
        matchRoot: true,
      );
      final d = tester.widget<Container>(container.first).decoration;
      return d is BoxDecoration ? d : null;
    }

    final headerDeco = decoOf(headerIndex);
    expect(headerDeco?.boxShadow ?? const <BoxShadow>[], isEmpty,
        reason: '组头不应有阴影（否则与首词接缝处会形成分离线）');

    // 组头底部不得有组内分隔线：那条线是给「词与词之间」用的，
    // 画在组头下缘会把卡片切成两半
    final headerContainer = find.descendant(
      of: find.byWidget(headerLayouts[headerIndex]),
      matching: find.byType(Container),
      matchRoot: true,
    );
    final hairlineCount = tester
        .widgetList<Container>(headerContainer)
        .where((c) => c.constraints?.maxHeight == 0.8)
        .length;
    expect(hairlineCount, 0, reason: '组头底部不应渲染分隔线');

    // 首词底部**应有**分隔线（与组内下一个词之间），仅组头那条要抑制
    final memberHairlines = tester
        .widgetList<Container>(find.descendant(
          of: find.byWidget(headerLayouts[memberIndex]),
          matching: find.byType(Container),
          matchRoot: true,
        ))
        .where((c) => c.constraints?.maxHeight == 0.8)
        .length;
    expect(memberHairlines, 1, reason: '族首词底部应保留分隔线');
    // 首词用 middle（下方还有组内词），下角保持直角——圆角只出现在组尾
    expect(memberRadius?.bottomLeft, Radius.zero,
        reason: '首词不在组尾时下角应为直角');
  });
}
