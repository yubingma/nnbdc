import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/daka_stamp_badge.dart';

void main() {
  group('DakaStampBadge 测试', () {
    testWidgets('普通打卡状态：正确渲染"已打卡"印章主体与英文标示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DakaStampBadge(
                size: 80,
                isExtraRound: false,
                animate: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DakaStampBadge), findsOneWidget);
      expect(find.text('已打卡'), findsOneWidget);
      expect(find.text('PAOPAO'), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
    });

    testWidgets('加量达成状态：正确渲染"已加量"印章主体与SUPER HERO标示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DakaStampBadge(
                size: 80,
                isExtraRound: true,
                animate: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DakaStampBadge), findsOneWidget);
      expect(find.text('已加量'), findsOneWidget);
      expect(find.text('PAOPAO'), findsOneWidget);
      expect(find.text('SUPER HERO'), findsOneWidget);
    });

    testWidgets('自定义颜色与尺寸：无渲染溢出且样式正常生效', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DakaStampBadge(
                size: 60,
                color: Colors.amber,
                animate: false,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(DakaStampBadge), findsOneWidget);
    });
  });
}
