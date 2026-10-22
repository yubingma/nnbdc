import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 戳泡泡顶部栏：返回键 / 房间名胶囊 / 换房键 三件套。
///
/// 线上报错：`A RenderFlex overflowed by 21 pixels on the right`，
/// 出错行就是房间名胶囊里那一行。根因是外层把可用宽度用
/// `Spacer + Flexible + Spacer` 三等分，胶囊最多只拿到 1/3；
/// 一旦「练习模式」徽标出现，图标（13）+ 间距（4+6）+ 徽标（约 55）
/// 这些**不可压缩**的固定宽度就超过了这份额度，文字再怎么省略也救不回来，
/// 于是整行右侧溢出。改成 Expanded + Center 之后，胶囊拿到两个按钮之间的全部余量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildRussiaTopBar({
    required double screenWidth,
    required String hallName,
    int? roomId,
    bool isExercise = false,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 800),
          padding: const EdgeInsets.only(top: 16),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF03142B),
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 20,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 22),
                      onPressed: () {},
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bubble_chart_rounded,
                                  color: Color(0xFF38BDF8), size: 13),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '$hallName${roomId != null ? ' · 房号$roomId' : ''}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              if (isExercise) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF34D399)
                                          .withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    '练习模式',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6EE7B7),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz_rounded,
                          color: Colors.white, size: 22),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> expectNoOverflow(
    WidgetTester tester, {
    required double screenWidth,
    required String hallName,
    int? roomId,
    required bool isExercise,
    double textScale = 1.0,
  }) async {
    final exceptions = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => exceptions.add(details);
    try {
      await tester.binding.setSurfaceSize(Size(screenWidth, 800));
      await tester.pumpWidget(buildRussiaTopBar(
        screenWidth: screenWidth,
        hallName: hallName,
        roomId: roomId,
        isExercise: isExercise,
        textScale: textScale,
      ));
      await tester.pumpAndSettle();
      expect(exceptions, isEmpty, reason: '不应产生任何溢出错误');
    } finally {
      FlutterError.onError = originalOnError;
      await tester.binding.setSurfaceSize(null);
    }
  }

  testWidgets('练习模式徽标 + 长词书名在 360dp 窄屏下不溢出', (tester) async {
    await expectNoOverflow(
      tester,
      screenWidth: 360,
      hallName: '英语专业八级核心高频词汇精选强化版',
      roomId: 123456,
      isExercise: true,
    );
  });

  testWidgets('练习模式徽标 + 超长词书名在 320dp 极窄屏下不溢出', (tester) async {
    await expectNoOverflow(
      tester,
      screenWidth: 320,
      hallName: '超长词书名称测试超长超长超长超长超长超长',
      roomId: 999999,
      isExercise: true,
    );
  });

  testWidgets('系统大字号（2 倍）下徽标与房间名仍不溢出', (tester) async {
    await expectNoOverflow(
      tester,
      screenWidth: 360,
      hallName: '大学英语四级核心词汇乱序版',
      roomId: 8888,
      isExercise: true,
      textScale: 2.0,
    );
  });
}
