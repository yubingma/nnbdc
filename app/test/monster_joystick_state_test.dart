import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/widget/game_joystick.dart';
import 'package:nnbdc/widget/monster_sprite.dart';

/// 摇杆 State 的稳定性契约。
///
/// 这不是样式测试，是「按住拖动、杆头立刻弹回中心」那个真机故障的回归测试：
/// `MonsterSprite` 的 `Stack` 里排在摇杆前面的子项数量每帧都在变（怪群进出场、
/// 哭/逃跑姿势、答题 UI 出现消失）。这些 `Positioned` 若没有稳定 key，Flutter 只按
/// 位置顺序匹配 Element，摇杆的 State（手指 id、底盘中心、杆偏移）就会被错位复用/重建。
void main() {
  Widget host() => const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: MonsterSprite(loop: false),
          ),
        ),
      );

  testWidgets('怪群与答题 UI 反复变化时，摇杆的 State 必须保持不变', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final State before = tester.state(find.byType(GameJoystick));
    // 跑满一整轮 6.8 秒：小怪进场、挨打、哭、逃跑、出题/结算都会发生
    for (int i = 0; i < 420; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final State after = tester.state(find.byType(GameJoystick));

    expect(identical(before, after), isTrue,
        reason: '摇杆被重建了，State 里的杆偏移会被清空——真机表现就是「一拖就弹回中心」');
  });

  testWidgets('按住拖动期间，摇杆 State 也不能被重建', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final Rect rect = tester.getRect(find.byType(GameJoystick));
    final State before = tester.state(find.byType(GameJoystick));

    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    for (int i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final State after = tester.state(find.byType(GameJoystick));

    expect(identical(before, after), isTrue,
        reason: '拖动过程中 State 被换掉，杆就会跳回中心、后续移动也收不到');
    await gesture.up();
  });
}
