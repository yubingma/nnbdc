import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 削砖块游戏生命周期与网络通信契约测试
void main() {
  test('削砖块指令与服务端协议严格保持一致', () {
    final source = File('lib/page/brick.dart').readAsStringSync();

    // 1. sendUserCmd 必须为 Map 结构，禁止发 List
    expect(source, contains("'system': 'russia'"), reason: '必须声明 system 为 russia');
    expect(source, isNot(contains("[user.id, 'russia'")), reason: '禁止以 List 格式发射 userCmd');

    // 2. 退出指令必须为 LEAVE_HALL，禁止使用后端不存在的 EXIT_GAME_HALL
    expect(source, contains("sendUserCmd('LEAVE_HALL'"), reason: '必须使用 LEAVE_HALL 指令');
    expect(source, isNot(contains("EXIT_GAME_HALL")), reason: '后端不存在 EXIT_GAME_HALL');

    // 3. 道具命令必须为 USE_PROPS，禁止使用 PROPS
    expect(source, contains("sendUserCmd('USE_PROPS'"), reason: '道具指令必须为 USE_PROPS');

    // 4. 禁止在 initState 中直接调用 GoRouterState.of(context)
    final initStateIdx = source.indexOf('void initState()');
    final didChangeIdx = source.indexOf('void didChangeDependencies()');
    expect(initStateIdx, greaterThan(0));
    expect(didChangeIdx, greaterThan(initStateIdx));
    final initStateBlock = source.substring(initStateIdx, didChangeIdx);
    expect(initStateBlock, isNot(contains('GoRouterState.of(context)')),
        reason: '禁止在 initState 中依赖 InheritedWidget 获取路由参数');

    // 5. 必须在 didChangeDependencies 中调用数据加载
    final didChangeBlock = source.substring(didChangeIdx, source.indexOf('Future<void> _loadData()'));
    expect(didChangeBlock, contains('_loadData()'), reason: '必须在 didChangeDependencies 中加载参数与数据');

    // 6. 还原为经典英选中玩法：下落英文单词大方块 + 底部 3 个中文释义卡片
    expect(source, contains('class BrickOption'), reason: '必须声明中文选项实体 BrickOption');
    expect(source, contains('final List<BrickOption> currentOptions'), reason: '必须维护当前中文释义选项列表');
    expect(source, contains('_onOptionTapped'), reason: '必须提供中文释义点击事件');
    expect(source, contains("'TIMEOUT'"), reason: '方块触底需判定超时并扣除防线生命');
  });
}
