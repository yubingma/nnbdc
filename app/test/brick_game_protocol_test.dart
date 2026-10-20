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

    // 7. 答题结果必须用服务端认识的 'true'/'false'；'CORRECT'/'TIMEOUT' 都会被当作"既不对也不错"
    expect(source, contains("_reportAnswer('true')"), reason: '答对必须上报 true');
    expect(source, contains("_reportAnswer('false')"), reason: '答错/触底必须上报 false');
    expect(source, isNot(contains("_reportAnswer('CORRECT')")), reason: '服务端不认识 CORRECT');
    expect(source, isNot(contains("_reportAnswer('TIMEOUT')")), reason: '服务端不认识 TIMEOUT');

    // 8. 对局结束必须监听服务端的 loser 广播；gameResultNotice 只是断线补发文字，不能当结算事件
    expect(source, contains("socket.on('loser'"), reason: '必须监听 loser 才能结束对局');
    expect(source, contains('_endGame(isWin: id != myUserId)'), reason: '由 loser 的 userId 判定胜负');
    expect(source, isNot(contains('_handleGameOver')), reason: '禁止再把 gameResultNotice 当结算事件');
    expect(source, contains('_resultShown'), reason: '本地血尽与服务端 loser 只允许结算一次');

    // 9. 堆叠：错词垒到底部，触底线随堆叠高度上移
    expect(source, contains('class BrickStackRow'), reason: '必须有底部死词层实体');
    expect(source, contains('final List<BrickStackRow> stackRows'), reason: '必须维护底部堆叠层');
    expect(source, contains('b.y + b.height / 2 >= stackTopY'), reason: '触底判定必须用堆叠顶面而非固定防线');
    expect(source, contains('_addStackRows'), reason: '扣血必须同步垒高死词层');
    expect(source, contains('int get myHp => max(0, maxHp - stackRows.length)'), reason: '生命值与堆叠层数必须同源');
    expect(source, contains("socket.on('stackSync'"), reason: '必须接收服务端权威堆叠行数');

    // 10. 竖排血条：stackSync 载荷为 [userId, rows, reason]，对手行数也要落到竖排血条上
    expect(source, contains('data[1] is num'), reason: 'stackSync 的第二项才是堆叠行数');
    expect(source, contains('opponentHp = max(0, maxHp - rows)'), reason: '对手行数必须同步到对手血条');
    expect(source, contains('opponentStackRows'), reason: '对手堆叠行数必须传给画布');
    expect(source, contains('_drawHpRail'), reason: '左右两侧必须绘制竖排防线');

    // 11. 道具库存以服务端 giveProps 为准，不能本地随机各发一套
    expect(source, contains("socket.on('giveProps'"), reason: '必须接收服务端发放的道具');
    expect(source, contains("socket.on('propsUsed'"), reason: '必须处理对手使用道具');
    expect(source, isNot(contains('rand.nextBool()')), reason: '禁止本地随机决定道具类型');

    // 12. 道具语义与站位：治疗给自己放左侧，攻击打对手放右侧
    final int healLabelIdx = source.indexOf("label: '治疗'");
    final int attackLabelIdx = source.indexOf("label: '攻击'");
    expect(healLabelIdx, greaterThan(0), reason: '治疗按钮必须存在');
    expect(attackLabelIdx, greaterThan(healLabelIdx), reason: '治疗在我方左侧，攻击在对手右侧');
  });
}
