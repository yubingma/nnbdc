import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/game_joystick.dart';

/// 虚拟摇杆的交互契约（浮动底盘版，照王者荣耀做的）。
///
/// 这几条都来自真机上的真实反馈：
///   - 原来底盘钉死在左下角，玩家按在盘子边上时，按下那一刻就按「手指相对底盘中心」算出
///     一个满力方向、杆头还从中心跳到手指上——一碰就走，手感完全不对；
///   - 方向曾经用「手指这一帧滑了多少」算，按住不动会被判成停下；
///   - 同时按两个摇杆时，第二根手指不能改写第一根的杆位。
void main() {
  const double radius = 56;
  const double width = 320;
  const double height = 280;
  const double maxTravel = radius * 0.62;

  late List<Offset> directions;
  late List<double> magnitudes;
  late int ends;

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: GameJoystick(
                radius: radius,
                onChanged: (dir, mag) {
                  directions.add(dir);
                  magnitudes.add(mag);
                },
                onEnd: () => ends++,
              ),
            ),
          ),
        ),
      );

  setUp(() {
    directions = [];
    magnitudes = [];
    ends = 0;
  });

  /// 组件内的局部坐标 → 屏幕坐标（组件在测试屏里居中）。
  Offset at(WidgetTester tester, double x, double y) =>
      tester.getTopLeft(find.byType(GameJoystick)) + Offset(x, y);

  testWidgets('按下不产生方向：手指只是搭上去，摇杆不该立刻带着人走', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 200, 140));
    await tester.pump();

    expect(directions.last, Offset.zero);
    expect(magnitudes.last, 0);
    await gesture.up();
  });

  testWidgets('抖动没过准备阈值就不输出方向', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 200, 140));
    await gesture.moveTo(at(tester, 206, 140)); // 6px，低于 10px 阈值
    await tester.pump();

    expect(directions.last, Offset.zero);
    expect(magnitudes.last, 0);
    await gesture.up();
  });

  testWidgets('越过阈值后，方向 = 手指相对按下点的方向，力度随手移动放大', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 200, 140));
    await gesture.moveTo(at(tester, 220, 140));
    await tester.pump();
    expect(directions.last.dx, closeTo(1, 0.001));
    expect(directions.last.dy, closeTo(0, 0.001));
    expect(magnitudes.last, closeTo(20 / maxTravel, 0.02));

    // 往正下方拖：屏幕坐标 y 向下为正
    await gesture.moveTo(at(tester, 200, 200));
    await tester.pump();
    expect(directions.last.dx, closeTo(0, 0.001));
    expect(directions.last.dy, closeTo(1, 0.001));
    await gesture.up();
  });

  testWidgets('推到再远也只算满力，杆头不会甩出底盘', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 200, 140));
    await gesture.moveTo(at(tester, 400, 140));
    await tester.pump();

    expect(magnitudes.last, 1.0);
    expect(directions.last.dx, closeTo(1, 0.001));
    await gesture.up();
  });

  testWidgets('按下点贴边时底盘中心被夹回区域里，且仍然不产生方向', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 0, 0));
    await tester.pump();
    expect(directions.last, Offset.zero);

    // 中心被夹到 (radius+4, radius+4)，手指从 (0,0) 拖到 (90,90) 相对中心是右下
    await gesture.moveTo(at(tester, 90, 90));
    await tester.pump();
    expect(directions.last.dx, greaterThan(0));
    expect(directions.last.dy, greaterThan(0));
    expect(magnitudes.last, greaterThan(0));
    await gesture.up();
  });

  testWidgets('松手归零并回调 onEnd', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(at(tester, 200, 140));
    await gesture.moveTo(at(tester, 240, 140));
    await tester.pump();

    await gesture.up();
    expect(directions.last, Offset.zero);
    expect(magnitudes.last, 0);
    expect(ends, 1);
  });

  testWidgets('第二根手指按下不夺走第一根的杆位', (tester) async {
    await tester.pumpWidget(host());
    final first = await tester.startGesture(at(tester, 200, 140));
    await first.moveTo(at(tester, 240, 140));
    await tester.pump();
    final Offset firstDir = directions.last;

    final second = await tester.startGesture(at(tester, 80, 80));
    await tester.pump();
    expect(directions.last, firstDir, reason: '第二根手指不应改写正在推的杆');

    await first.up();
    expect(directions.last, Offset.zero);
    await second.up();
  });
}
