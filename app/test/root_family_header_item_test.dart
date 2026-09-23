import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/modes/root_family_header_item.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 词根组头行的布局契约与窄宽溢出回归：
/// 1) 词根完整显示（仅在超长时收缩），中间剩余空间全部让给释义 —— 放得下就完整显示、
///    确实放不下才省略号；
/// 2) 词数固定在行尾右对齐；
/// 3) 超长词根/含义在窄屏下不得触发 RenderFlex overflow。
void main() {
  const headerWidth = 375.0;
  const horizontalPadding = 12.0; // 与实现内边距一致

  /// 渲染组头行并返回其外框
  Future<Rect> pumpHeader(
    WidgetTester tester, {
    double width = headerWidth,
    required String spell,
    String? meaning,
    String? count,
  }) async {
    tester.view.physicalSize = Size(width, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>(
        create: (_) => DarkMode(),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Builder(
                  builder: (context) => buildRootFamilyHeaderContent(
                    cigen: CigenVo('c1', spell,
                        spell: spell, category: 'ROOT', meaningCn: meaning),
                    spell: spell,
                    count: count,
                    isDarkMode: false,
                    themeConfig: AppThemeConfig.of(context.watch<DarkMode>().themeStyle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return tester.getRect(find.byKey(headerContentKey));
  }

  /// 词数是否贴着行尾右边界（内容区，减去右内边距）
  bool countIsRightAligned(WidgetTester tester, Rect header, String countText) {
    return (header.right - horizontalPadding - tester.getRect(find.text(countText)).right)
            .abs() <
        1.0;
  }

  /// 该文本是否被省略号截断（Flutter 在超出 maxLines 时置位）
  bool isEllipsized(WidgetTester tester, String text) {
    final paragraph =
        tester.renderObject<RenderParagraph>(find.text(text, findRichText: true));
    return paragraph.didExceedMaxLines;
  }

  testWidgets('空间充足时释义完整显示（无省略号）', (tester) async {
    await pumpHeader(tester, spell: 'spect', meaning: '看', count: '22 词');

    expect(tester.takeException(), isNull);
    expect(isEllipsized(tester, '看'), false);
  });

  testWidgets('中段空间全部让给释义：长释义在 375 宽下仍不省略', (tester) async {
    const meaning = '站立，立定，使稳固';
    await pumpHeader(tester, spell: 'st', meaning: meaning, count: '29 词');

    expect(tester.takeException(), isNull);
    expect(isEllipsized(tester, meaning), false,
        reason: '词根很短时，中间空间应足够完整显示该释义');
  });

  testWidgets('极端长释义确实放不下时才省略号（且不溢出）', (tester) async {
    const meaning = '一再，加强意义，表示反复与强调，用于构成大量动词';
    await pumpHeader(
      tester,
      spell: 'ab,ac,ad,af,ag,an,ap,ar,as,at',
      meaning: meaning,
      count: '131 词',
    );

    expect(tester.takeException(), isNull);
    expect(isEllipsized(tester, meaning), true);
  });

  testWidgets('词数固定贴行尾右对齐', (tester) async {
    final header =
        await pumpHeader(tester, spell: 'spect', meaning: '看', count: '22 词');

    expect(tester.takeException(), isNull);
    expect(countIsRightAligned(tester, header, '22 词'), true,
        reason: '行右内容边界=${header.right - horizontalPadding} '
            '词数右边界=${tester.getRect(find.text('22 词')).right}');
  });

  testWidgets('词数右边界在不同词数/词根下保持一致（列宽固定）', (tester) async {
    final headerA =
        await pumpHeader(tester, spell: 'spect', meaning: '看', count: '5 词');
    expect(countIsRightAligned(tester, headerA, '5 词'), true);

    final headerB = await pumpHeader(
      tester,
      spell: 'form',
      meaning: '形成，构成',
      count: '131 词',
    );
    expect(countIsRightAligned(tester, headerB, '131 词'), true);
  });

  testWidgets('超长词根 + 超长含义在窄屏(320)下不溢出', (tester) async {
    await pumpHeader(
      tester,
      width: 320,
      spell: 'st,sta,stat,stit,sist',
      meaning: '站立，立定，使稳固，持续存在下去',
      count: '46 词',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('极窄屏(240) + 超长内容不溢出，词数仍右对齐', (tester) async {
    final header = await pumpHeader(
      tester,
      width: 240,
      spell: 'ab,ac,ad,af,ag,an,ap,ar,as,at',
      meaning: '一再，加强意义，表示反复与强调',
      count: '131 词',
    );

    expect(tester.takeException(), isNull);
    expect(countIsRightAligned(tester, header, '131 词'), true);
  });

  testWidgets('无含义时词数仍右对齐，且不渲染空文本', (tester) async {
    final header = await pumpHeader(tester, spell: 'fac', count: '46 词');

    expect(tester.takeException(), isNull);
    expect(find.text('fac'), findsOneWidget);
    expect(countIsRightAligned(tester, header, '46 词'), true);
  });

  testWidgets('无词数时释义仍占满剩余空间且不省略', (tester) async {
    await pumpHeader(tester, spell: 'spect', meaning: '看，观察，审视，展望');

    expect(tester.takeException(), isNull);
    expect(find.text('词根'), findsOneWidget);
    expect(find.text('spect'), findsOneWidget);
    expect(isEllipsized(tester, '看，观察，审视，展望'), false);
  });
}
