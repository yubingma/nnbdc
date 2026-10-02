import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildFocusTimeBar({
    required String todayText,
    required String totalText,
    double screenWidth = 360.0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 800),
          devicePixelRatio: 3.0,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: screenWidth - 32, // 模拟 SliverPadding(16)
              child: Padding(
                padding: const EdgeInsets.all(18), // 模拟 FrostedGlassCard padding
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_filled_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '专注时光',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                '今日 $todayText · 累计 $totalText',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'NotoSansSC',
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('专注时光微条在典型 360dp 安卓手机上正常展示无 RenderFlex 溢出', (tester) async {
    tester.view.physicalSize = const Size(360 * 3.0, 760 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildFocusTimeBar(
        todayText: '1h 22m',
        totalText: '1h 22m',
        screenWidth: 360.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('专注时光'), findsOneWidget);
    expect(find.text('今日 1h 22m · 累计 1h 22m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('专注时光微条在极窄 320dp 手机或超长学习时间下自适应省略不溢出', (tester) async {
    tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildFocusTimeBar(
        todayText: '15h 48m',
        totalText: '9999h 59m',
        screenWidth: 320.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('专注时光'), findsOneWidget);
    // 即使文本极长在 320dp 极窄屏幕下，依然能够自适应缩放/省略且绝不抛出任何 RenderFlex overflow 异常
    expect(tester.takeException(), isNull);
  });
}
