import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/monster.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

/// 小馋怪页面是**横屏**游戏页。
///
/// 这不是样式偏好：守桥的构图是「一条向纵深收拢的桥 + 两侧水面」，
/// 竖屏下桥只能占中间窄窄一条、两侧全是空白，答案箱也没地方摆。
/// 因此页面自己锁横屏、并在退出时恢复竖屏。这条断言拦住的是
/// 「以后有人顺手把方向锁删掉或改成竖屏」——那种回归在竖屏真机上才发现就太晚了。
void main() {
  testWidgets('进入页面锁横屏（沉浸全屏），退出恢复竖屏', (tester) async {
    final List<String> orientations = <String>[];
    final List<String> uiModes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.addAll((call.arguments as List).cast<String>());
        } else if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          uiModes.add(call.arguments.toString());
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: const MaterialApp(home: MonsterPage()),
    ));
    await tester.pump();

    expect(
      orientations.where((o) => o.contains('landscape')).length,
      2,
      reason: '进页面必须锁定横屏两个方向（不锁单侧，方便用户随手翻转），实到 $orientations',
    );
    expect(uiModes.any((m) => m.contains('immersive')), isTrue,
        reason: '横屏游戏页应进入沉浸全屏，实到 $uiModes');

    // 退出页面：必须把方向还给竖屏，否则整个 App 的其它页面都会被留在横屏
    orientations.clear();
    await tester.pumpWidget(ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));
    await tester.pump();
    expect(orientations.any((o) => o.contains('portrait')), isTrue,
        reason: '退出页面必须恢复竖屏，实到 $orientations');
  });
}
