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

class _A with WordListActionHandler {
  @override
  void onWordTap(WordWrapper w, int i) {}
  @override
  void onWordLongPress(WordWrapper w, int i) {}
  @override
  void onMasterBtnPressed(WordWrapper w, int i) {}
  @override
  void onUnmasterBtnPressed(WordWrapper w, int i) {}
  @override
  void onDelBtnPressed(WordWrapper w, int i) {}
  @override
  void onEditBtnPressed(WordWrapper w, int i) {}
  @override
  void onResetHint(WordWrapper w) {}
  @override
  void onGiveHint(WordWrapper w) {}
  @override
  void onToggleAnswer(WordWrapper w, int i) {}
  @override
  void onHandwritingPressed(WordWrapper w, int i) {}
  @override
  void onSpellChanged(WordWrapper w, int i, String v) {}
}

void main() {
  testWidgets('两个族：第二个族的组头同样不画线、与首词相接', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final a = _A();

    WordWrapper header(String spell, int n) => WordWrapper(
          WordVo.c2(spell)
            ..id = 'cigen:$spell'
            ..shortDesc = '含义$spell'
            ..meaningStr = '$n 词',
          CigenVo(spell, spell, spell: spell, category: 'ROOT', meaningCn: '含义$spell'),
        );

    WordWrapper member(String spell) => WordWrapper(
          WordVo.c2(spell)
            ..id = 'w_$spell'
            ..meaningItems = [MeaningItemVo.from('v.', '释义$spell')],
          Word(id: 'w_$spell', spell: spell, popularity: 1,
              createTime: DateTime(2026, 1, 1), updateTime: DateTime(2026, 1, 1)),
        );

    Widget item(WordWrapper w, int idx, GroupCardPosition pos, {bool header_ = false}) {
      if (header_) {
        return RootFamilyHeaderItem(
            word: w, index: 0, baseIndex: 0, isDarkMode: false,
            actions: a, groupPosition: pos);
      }
      return ListModeItem(
          word: w, index: idx, baseIndex: 0, isBookmarked: false, isDarkMode: false,
          learningStatus: null, showWordProgress: false, actions: a,
          slidableActions: const [], groupPosition: pos);
    }

    await tester.pumpWidget(ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 第一组：首词是列表首项，无 14px padding（真机 i==0）
              item(header('tend', 7), 0, GroupCardPosition.top, header_: true),
              item(member('extend'), 0, GroupCardPosition.middle),
              item(member('extent'), 1, GroupCardPosition.bottom),
              // 第二组：首词带 14px padding（真机 i>0 走 isGroupStart 分支）
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: item(header('port', 2), 0, GroupCardPosition.top, header_: true),
              ),
              item(member('export'), 2, GroupCardPosition.middle),
              item(member('import'), 3, GroupCardPosition.bottom),
            ],
          ),
        ),
      ),
    ));

    final layouts =
        tester.widgetList<WordListItemLayout>(find.byType(WordListItemLayout)).toList();
    expect(layouts.length, 6);

    // 每个族的「组头」与「其首词」之间都必须无空隙
    final rects = layouts
        .map((w) => tester.getRect(find.byWidget(w)))
        .toList();
    for (final pair in [(0, 1), (3, 4)]) {
      final gap = rects[pair.$2].top - rects[pair.$1].bottom;
      expect(gap, 0.0, reason: '第 $pair 组 组头与首词之间有空隙：$gap');
    }

    // 两个组头都不应画分隔线
    for (final i in [0, 3]) {
      final hairs = tester
          .widgetList<Container>(find.descendant(
            of: find.byWidget(layouts[i]),
            matching: find.byType(Container),
            matchRoot: true,
          ))
          .where((c) => c.constraints?.maxHeight == 0.8)
          .length;
      expect(hairs, 0, reason: '第 $i 个 layout（组头）不应有分隔线');
    }
  });
}
