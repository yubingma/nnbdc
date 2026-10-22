import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/meaning_render_util.dart';
import 'package:nnbdc/util/word_util.dart';

void main() {
  group('MeaningRenderUtil 规格与判定测试', () {
    test('getDotSpec: 常用度百分比档位映射正确', () {
      // 核心高频 >= 60%
      final spec80 = MeaningRenderUtil.getDotSpec(80);
      expect(spec80.size, 6.0);
      expect(spec80.opacity, 0.88);

      final spec60 = MeaningRenderUtil.getDotSpec(60);
      expect(spec60.size, 6.0);

      // 常见 25%~59%
      final spec50 = MeaningRenderUtil.getDotSpec(50);
      expect(spec50.size, 4.5);
      expect(spec50.opacity, 0.65);

      // 次要 5%~24%
      final spec15 = MeaningRenderUtil.getDotSpec(15);
      expect(spec15.size, 3.2);
      expect(spec15.opacity, 0.45);

      // 生僻 < 5%
      final spec2 = MeaningRenderUtil.getDotSpec(2);
      expect(spec2.size, 2.2);
      expect(spec2.opacity, 0.28);

      // null 兜底
      final specNull = MeaningRenderUtil.getDotSpec(null);
      expect(specNull.size, 2.2);
    });

    test('hasMultipleMeanings: 单释义词判定为 false', () {
      final singleItemWord = [
        MeaningItemVo('1', 'n.', '苹果', null, null, null, 100)
          ..parts = [const MeaningPartVo('苹果', 100)],
      ];
      expect(MeaningRenderUtil.hasMultipleMeanings(singleItemWord), isFalse);
    });

    test('hasMultipleMeanings: 同一词性多义项判定为 true', () {
      final multiPartsWord = [
        MeaningItemVo('1', 'v.', '跑；运转', null, null, null, 85)
          ..parts = [
            const MeaningPartVo('跑', 80),
            const MeaningPartVo('运转', 15),
          ],
      ];
      expect(MeaningRenderUtil.hasMultipleMeanings(multiPartsWord), isTrue);
    });

    test('hasMultipleMeanings: 多词性判定为 true', () {
      final multiPosWord = [
        MeaningItemVo('1', 'v.', '跑', null, null, null, 85)
          ..parts = [const MeaningPartVo('跑', 85)],
        MeaningItemVo('2', 'n.', '赛程', null, null, null, 15)
          ..parts = [const MeaningPartVo('赛程', 15)],
      ];
      expect(MeaningRenderUtil.hasMultipleMeanings(multiPosWord), isTrue);
    });
  });

  group('MeaningRenderUtil 渲染 Spans 测试', () {
    const defaultStyle = TextStyle(fontSize: 14, color: Colors.black);
    const dotColor = Colors.black;

    test('单释义词 (showDots = false): 不加小圆点，保留纯净文本', () {
      final singleItem = MeaningItemVo('1', 'n.', '苹果', null, null, null, 100)
        ..parts = [const MeaningPartVo('苹果', 100)];

      final spans = MeaningRenderUtil.buildMeaningSpans(
        item: singleItem,
        meaningStyle: defaultStyle,
        dotColor: dotColor,
        showDots: false,
      );

      // 仅包含 1 个纯文本 TextSpan，无 WidgetSpan 圆点
      expect(spans.length, 1);
      expect(spans.first, isA<TextSpan>());
      expect((spans.first as TextSpan).text, '苹果');
    });

    test('多释义词 (showDots = true): 释义末尾带圆点并取代分号', () {
      final multiItem = MeaningItemVo('1', 'v.', '跑；运转', null, null, null, 85)
        ..parts = [
          const MeaningPartVo('跑', 80),
          const MeaningPartVo('运转', 15),
        ];

      final spans = MeaningRenderUtil.buildMeaningSpans(
        item: multiItem,
        meaningStyle: defaultStyle,
        dotColor: dotColor,
        showDots: true,
      );

      // 应当包含：TextSpan(跑) -> WidgetSpan(圆点) -> TextSpan(运转) -> WidgetSpan(圆点)
      expect(spans.length, 4);
      expect((spans[0] as TextSpan).text, '跑');
      expect(spans[1], isA<WidgetSpan>());
      expect((spans[2] as TextSpan).text, '运转');
      expect(spans[3], isA<WidgetSpan>());

      // 验证没有多余的中文分号
      for (final span in spans) {
        if (span is TextSpan) {
          expect(span.text?.contains('；'), isFalse);
          expect(span.text?.contains(';'), isFalse);
        }
      }
    });

    test('buildInlineMeaningSpans: 完整词表多词性带圆点流式排版', () {
      final word = WordVo.c2('run')
        ..meaningItems = [
          MeaningItemVo('1', 'v.', '跑', null, null, null, 80),
          MeaningItemVo('2', 'v.', '运转', null, null, null, 15),
          MeaningItemVo('3', 'n.', '奔跑', null, null, null, 5),
        ];

      final spans = MeaningRenderUtil.buildInlineMeaningSpans(
        word: word,
        meaningStyle: defaultStyle,
        posStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        dotColor: dotColor,
      );

      expect(spans, isNotEmpty);
      // 包含词性、释义、圆点以及词性间隔空格
      final hasWidgetSpan = spans.any((s) => s is WidgetSpan);
      expect(hasWidgetSpan, isTrue);
    });

    test('buildInlineMeaningSpans: 常用度不同则圆点直径不同（防止百分比丢失后全等）', () {
      // 词书单词列表曾只拷 ciXing + meaning，丢掉 popularityPercent，
      // 导致所有圆点都退化成最小尺寸、看起来一样大。
      final word = WordVo.c2('deny')
        ..meaningItems = [
          MeaningItemVo('1', 'vt.', '否认', null, null, null, 90),
          MeaningItemVo('2', 'vt.', '拒绝', null, null, null, 8),
        ];

      final spans = MeaningRenderUtil.buildInlineMeaningSpans(
        word: word,
        meaningStyle: defaultStyle,
        posStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        dotColor: dotColor,
      );

      final dotDiameters = spans.whereType<WidgetSpan>().map((span) {
        final padding = span.child as Padding;
        final circle = padding.child as Container;
        return circle.constraints!.minWidth;
      }).toList();

      expect(dotDiameters, [6.0, 3.2]);
    });
  });

  group('WordVo.getMergedMeaningItems 结构验证', () {
    test('正确将同词性项归并在 parts 中并保留各自的 popularityPercent', () {
      final word = WordVo.c2('run')
        ..meaningItems = [
          MeaningItemVo('1', 'v.', '跑', null, null, null, 80),
          MeaningItemVo('2', 'v.', '运转', null, null, null, 15),
          MeaningItemVo('3', 'n.', '奔跑', null, null, null, 5),
        ];

      final merged = word.getMergedMeaningItems();
      expect(merged.length, 2);

      // v. 项
      final vItem = merged.firstWhere((m) => m.ciXing == 'v.');
      expect(vItem.parts, isNotNull);
      expect(vItem.parts!.length, 2);
      expect(vItem.parts![0].text, '跑');
      expect(vItem.parts![0].popularityPercent, 80);
      expect(vItem.parts![1].text, '运转');
      expect(vItem.parts![1].popularityPercent, 15);

      // n. 项
      final nItem = merged.firstWhere((m) => m.ciXing == 'n.');
      expect(nItem.parts, isNotNull);
      expect(nItem.parts!.length, 1);
      expect(nItem.parts![0].text, '奔跑');
      expect(nItem.parts![0].popularityPercent, 5);
    });
  });

  group('MeaningRenderUtil.resolveParts 与合并释义对齐', () {
    test('子项文本与分号拆分一一对应，并保留各自常用度', () {
      final word = WordVo.c2('run')
        ..meaningItems = [
          MeaningItemVo('1', 'v.', '跑', null, null, null, 80),
          MeaningItemVo('2', 'v.', '运转；经营', null, null, null, 15),
        ];

      final vItem = word
          .getMergedMeaningItems()
          .firstWhere((item) => item.ciXing == 'v.');
      final parts = MeaningRenderUtil.resolveParts(vItem);

      expect(parts.map((p) => p.text).toList(),
          splitMeaning2Parts(vItem.meaning!));
      expect(parts.map((p) => p.popularityPercent).toList(), [80, 15, 15]);
    });
  });

  group('英译汉答案区的常用度圆点', () {
    bool isDotWidget(Widget widget) =>
        widget is Padding &&
        widget.child is SizedBox &&
        (widget.child as SizedBox).height == 17;

    test('多义项：每个释义子项末尾各带一个圆点', () {
      final word = WordVo.c2('run')
        ..meaningItems = [
          MeaningItemVo('1', 'v.', '跑', null, null, null, 80),
          MeaningItemVo('2', 'v.', '运转', null, null, null, 15),
        ];
      final wrapper = WordWrapper(word, null);

      final wraps = renderAsrMeaningItems(wrapper);
      expect(wraps.length, 1);
      final children = (wraps.single as Wrap).children;

      // 词性 + 释义 + 圆点 + 释义 + 圆点（圆点取代分号，不再额外渲染「；」）
      expect(children.length, 5);
      expect(children.where(isDotWidget).length, 2);
      expect(children.where((w) => w is Text && w.data == '；'), isEmpty);
    });

    test('单义词：答案区保持纯净，不加圆点', () {
      final word = WordVo.c2('run')
        ..meaningItems = [
          MeaningItemVo('1', 'v.', '跑', null, null, null, 80),
        ];
      final wrapper = WordWrapper(word, null);

      final children = (renderAsrMeaningItems(wrapper).single as Wrap).children;

      // 词性 + 释义
      expect(children.length, 2);
      expect(children.where(isDotWidget), isEmpty);
    });
  });
}
