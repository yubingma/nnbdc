import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/widgets/core_image_orbit_layout.dart';
import 'package:nnbdc/page/bdc/widgets/word_core_image_card.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 造一批和真机相近的尺寸（两行框）：
/// 释义框约 36×32，线上文字约 34×23
List<OrbitNodeMetrics> _metrics(int n) {
  return List.generate(
    n,
    (_) => const OrbitNodeMetrics(
      boxHalfW: 18,
      boxHalfH: 16,
      textHalfW: 17,
      textHalfH: 11.5,
    ),
  );
}

OrbitLayoutResult _layout(int n, {Size canvas = const Size(329, 430)}) {
  return CoreImageOrbitLayout.compute(
    canvas: canvas,
    metrics: _metrics(n),
    labelSize: const Size(45, 14),
  );
}

WordCoreImage _card(int n) => WordCoreImage(
      id: 'test-$n',
      wordId: 'test-$n',
      word: 'about',
      coreImage: '绕心打转',
      schemaDesc: 'about 的核心画面是绕着某个东西的外围转。',
      topologyJson: jsonEncode({
        'branches': [
          for (var i = 0; i < n; i++)
            {
              'pos': i.isEven ? 'prep' : 'adv',
              'meaning': '释义$i',
              'relation': '围绕主题外缘关联',
            }
        ],
      }),
      imageUrl: '',
      isApplicable: true,
    );

Future<void> _pumpCard(WidgetTester tester, int n) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => DarkMode(),
      child: MaterialApp(
        theme: AppTheme.getThemeData(AppThemeStyle.emerald),
        home: Scaffold(
          body: SingleChildScrollView(child: WordCoreImageCard(item: _card(n))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('核心意象环绕布局', () {
    test('分支少时中心图足够大，且标签全部落在画布内', () {
      final r = _layout(5);

      expect(r.nodes.length, 5);
      expect(r.feasible, isTrue, reason: '5 条不应出现叠压');
      // 记录实际值，用于回归对比
      debugPrint('5 条：中心图 ⌀${r.imageDiameter.toStringAsFixed(0)} 禁区 ±${r.forbiddenDeg}° 占用 ${(r.sectorUsage * 100).toStringAsFixed(0)}%');
      // 5 条是本形态的舒适区，中心图不该被压到比释义框还小
      expect(r.imageDiameter, greaterThan(100));

      for (final n in r.nodes) {
        expect(n.boxCenter.dx, inInclusiveRange(0, 329));
        expect(n.boxCenter.dy, inInclusiveRange(0, 430));
        expect((n.lineEnd - n.lineStart).distance, greaterThan(0));
      }
    });

    test('分支变多时中心图单调变小', () {
      final d5 = _layout(5).imageDiameter;
      final d8 = _layout(8).imageDiameter;

      expect(d8, lessThan(d5), reason: '8 条应比 5 条更挤');
      expect(_layout(8).feasible, isTrue);
    });

    test('分支越多中心图越小、扇区越挤（超过阈值由卡片层降级）', () {
      final r5 = _layout(5);
      final r11 = _layout(11);

      expect(r11.nodes.length, 11);
      expect(r11.imageDiameter, lessThan(r5.imageDiameter));
      expect(r11.sectorUsage, greaterThan(r5.sectorUsage));
    });

    test('连线方向朝外：终点比起点更远离圆心', () {
      final r = _layout(5);
      for (final n in r.nodes) {
        final startD = (n.lineStart - r.center).distance;
        final endD = (n.lineEnd - r.center).distance;
        expect(endD, greaterThan(startD));
      }
    });

    test('核心意象文字放在圆心下方，且放得进圆内弦宽', () {
      final r = _layout(5);
      expect(r.labelCenter.dy, greaterThan(r.center.dy));
      expect(r.labelFits, isTrue);
    });

    test('画布变窄时布局仍然成立（不抛出、不产生 NaN）', () {
      for (final w in [280.0, 329.0, 412.0]) {
        final r = _layout(5, canvas: Size(w, 430));
        expect(r.imageDiameter.isFinite, isTrue);
        for (final n in r.nodes) {
          expect(n.boxCenter.dx.isFinite, isTrue);
          expect(n.textCenter.dy.isFinite, isTrue);
        }
      }
    });
  });

  group('核心意象环绕卡片', () {
    for (final n in [5, 8]) {
      testWidgets('$n 条分支：环绕形态渲染不抛异常、不溢出', (tester) async {
        await _pumpCard(tester, n);
        // 溢出在 flutter_test 里会记成异常，显式断言把它兜出来
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('11 条分支：降级为竖排列表，不再画环绕图', (tester) async {
      await _pumpCard(tester, 11);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('释义引申脉络'), findsOneWidget);
    });
  });

  group('relation 断行', () {
    test('按 4 字一行显式切分，不交给引擎自动断行', () {
      // 引擎对 CJK 的断行位置不可控，实测会出现 4+2+2 的碎裂断法
      expect(WordCoreImageCard.wrapRelation('围绕主题外缘关联'), '围绕主题\n外缘关联');
      expect(WordCoreImageCard.wrapRelation('绕到目标快到了'), '绕到目标\n快到了');
      expect(WordCoreImageCard.wrapRelation('没对准中心在外围晃'), '没对准中\n心在外围\n晃');
      expect(WordCoreImageCard.wrapRelation(''), '');
    });
  });
}
