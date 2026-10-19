import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildBrickTopBar({
    required double screenWidth,
    required String hallName,
    int? roomId,
    bool isPlaying = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 800),
          padding: const EdgeInsets.only(top: 16),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F172A),
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
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                      onPressed: () {},
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.grid_view_rounded, color: Color(0xFFF59E0B), size: 14),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '削砖块 · $hallName${roomId != null ? ' · 房号$roomId' : ''}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!isPlaying) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('开始对战', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('削砖块顶部栏在360dp窄屏与长房间名下不产生RenderFlex溢出', (tester) async {
    final exceptions = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => exceptions.add(details);

    try {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(
        buildBrickTopBar(
          screenWidth: 360,
          hallName: '英语专业八级核心高频词汇精选强化版',
          roomId: 123456,
          isPlaying: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(exceptions, isEmpty, reason: '不应产生任何溢出错误');
      expect(find.textContaining('削砖块 · 英语专业八级'), findsOneWidget);
      expect(find.text('开始对战'), findsOneWidget);
    } finally {
      FlutterError.onError = originalOnError;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('削砖块顶部栏在320dp极窄屏下仍自适应且无溢出', (tester) async {
    final exceptions = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => exceptions.add(details);

    try {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      await tester.pumpWidget(
        buildBrickTopBar(
          screenWidth: 320,
          hallName: '超长词书名称测试超长超长超长超长超长',
          roomId: 999999,
          isPlaying: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(exceptions, isEmpty, reason: '极窄屏下不应产生任何溢出错误');
      expect(find.text('开始对战'), findsOneWidget);
    } finally {
      FlutterError.onError = originalOnError;
      await tester.binding.setSurfaceSize(null);
    }
  });
}
