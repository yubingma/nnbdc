import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/game_joystick.dart';

/// 虚拟摇杆的交互契约。
///
/// 这几条都来自 `design/ideas.html` 里 IDEA #010 的真实翻车：
///   - 方向曾经用「手指这一帧滑了多少」算，按住不动被判成停下 → 摇杆自己停住；
///   - 加过缓动想让移动平滑，结果「反应慢、像有惯性」；
///   - 同时按两个摇杆时，第二根手指不能改写第一根的杆位。
void main() {
  const double radius = 60;
  const double side = radius * 2.4;
  const Offset center = Offset(radius * 1.2, radius * 1.2);

  late List<Offset> directions;
  late List<double> magnitudes;
  late int starts;
  late int ends;

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: GameJoystick(
              radius: radius,
              onStart: () => starts++,
              onEnd: () => ends++,
              onChanged: (dir, mag) {
                directions.add(dir);
                magnitudes.add(mag);
              },
            ),
          ),
        ),
      );

  setUp(() {
    directions = [];
    magnitudes = [];
    starts = 0;
    ends = 0;
  });

  testWidgets('死区内的按下不给方向', (tester) async {
    await tester.pumpWidget(host());
    final Offset origin = tester.getCenter(find.byType(GameJoystick));

    final gesture = await tester.startGesture(origin + const Offset(10, 0));
    await tester.pump();

    expect(directions.last, Offset.zero);
    expect(magnitudes.last, 0);
    await gesture.up();
  });

  testWidgets('杆偏离圆心的方向就是输出方向，推到底为满量', (tester) async {
    await tester.pumpWidget(host());
    final Offset origin = tester.getCenter(find.byType(GameJoystick));

    final gesture = await tester.startGesture(origin);
    await gesture.moveTo(origin + const Offset(radius, 0));
    await tester.pump();
    expect(directions.last.dx, closeTo(1, 0.001));
    expect(directions.last.dy, closeTo(0, 0.001));
    expect(magnitudes.last, closeTo(1, 0.001));

    // 往上推：屏幕坐标 y 为负
    await gesture.moveTo(origin + const Offset(0, -radius * 2));
    await tester.pump();
    expect(directions.last.dx, closeTo(0, 0.001));
    expect(directions.last.dy, closeTo(-1, 0.001));
    expect(magnitudes.last, closeTo(1, 0.001), reason: '超出底盘时推杆量应夹在 1');

    await gesture.up();
  });

  testWidgets('按住不动时方向保持，不会因为「这一帧没滑」而停', (tester) async {
    await tester.pumpWidget(host());
    final Offset origin = tester.getCenter(find.byType(GameJoystick));

    final gesture = await tester.startGesture(origin);
    await gesture.moveTo(origin + const Offset(-radius, radius));
    await tester.pump();
    final Offset held = directions.last;
    expect(held.dx, lessThan(0));
    expect(held.dy, greaterThan(0));

    // 手指不动，只让时间过去：摇杆本身不会再收到事件，但最后输出必须仍然是同一个方向
    await tester.pump(const Duration(milliseconds: 500));
    expect(directions.last, held);
    await gesture.up();
  });

  testWidgets('松手归零并回调 onEnd', (tester) async {
    await tester.pumpWidget(host());
    final Offset origin = tester.getCenter(find.byType(GameJoystick));

    final gesture = await tester.startGesture(origin);
    await gesture.moveTo(origin + const Offset(0, -radius));
    await tester.pump();
    expect(starts, 1);

    await gesture.up();
    expect(directions.last, Offset.zero);
    expect(magnitudes.last, 0);
    expect(ends, 1);
  });

  testWidgets('第二根手指按下不夺走第一根的杆位', (tester) async {
    await tester.pumpWidget(host());
    final Offset origin = tester.getCenter(find.byType(GameJoystick));

    final first = await tester.startGesture(origin);
    await first.moveTo(origin + const Offset(radius, 0));
    await tester.pump();
    final Offset firstDir = directions.last;

    final second = await tester.startGesture(origin + const Offset(-side / 2, 0));
    await tester.pump();
    expect(directions.last, firstDir, reason: '第二根手指不应改写正在推的杆');

    await first.up();
    expect(directions.last, Offset.zero);
    await second.up();
  });

  testWidgets('组件尺寸是底盘半径的 2.4 倍，触摸区不会被画成底盘大小', (tester) async {
    await tester.pumpWidget(host());
    final Size size = tester.getSize(find.byType(GameJoystick));
    expect(size.width, closeTo(side, 0.01));
    expect(size.height, closeTo(side, 0.01));
    expect(center, const Offset(72, 72));
  });
}
