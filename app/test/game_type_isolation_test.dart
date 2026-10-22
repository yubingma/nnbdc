import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/brick.dart';
import 'package:nnbdc/page/russia.dart';

/// 游戏大厅匹配与私房都要带"游戏类型"。
///
/// 两款游戏共用服务端同一套房间与对局逻辑（socket 上都叫 `system: 'russia'`），
/// 服务端只能靠入口指令尾部这个参数分辨：不带就会被当成老客户端单独成池，
/// 结果是"戳泡泡的人和消砖块的人配进同一间房，各打各的"。
void main() {
  group('客户端声明的游戏类型', () {
    test('消砖块是 brick，戳泡泡是 russia', () {
      expect(BrickPageState.gameType, 'brick');
      expect(RussiaPageState.gameType, 'russia');
    });
  });

  group('三条入口指令必须带上游戏类型', () {
    /// 截取某条指令的调用片段（从指令名到该调用的收尾括号）
    String callOf(String source, String cmd) {
      final start = source.indexOf("sendUserCmd('$cmd'");
      expect(start, greaterThan(0), reason: '找不到 $cmd 指令');
      final end = source.indexOf(');', start);
      return source.substring(start, end);
    }

    const pages = {
      '消砖块': 'lib/page/brick.dart',
      '戳泡泡': 'lib/page/russia.dart',
    };

    for (final entry in pages.entries) {
      test('${entry.key}：开房、按房号进房、大厅匹配都带 gameType', () {
        final source = File(entry.value).readAsStringSync();
        for (final cmd in ['CREATE_PRIVATE_ROOM', 'JOIN_ROOM_BY_ID', 'ENTER_GAME_HALL']) {
          expect(callOf(source, cmd), contains('gameType'),
              reason: '${entry.key} 的 $cmd 没有带上游戏类型');
        }
      });
    }
  });
}
