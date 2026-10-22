import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/brick.dart';

/// 消砖块私房（大厅点「开房」→ 房号 → 好友「进房」）。
///
/// 用户反馈："消砖块的开房好像没有实现"。查下去确实只有半截：
/// 服务端能建房、也能按房号进房，但客户端既没有「房间已开好 + 房号」的等待界面，
/// 「开始对战」还在房里只有一个人时就发 START_GAME（WaitState 不认这条指令），
/// 同时自己把按钮翻成「已就绪」——房主被锁在空棋盘上，好友进来也开不了局。
void main() {
  group('开房等人界面判定', () {
    test('我开的房、好友还没来、我也没开始 → 给开房等人界面', () {
      expect(
        BrickPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: false, myStarted: false),
        isTrue,
      );
    });

    test('好友已进房 → 交回正常的就绪界面', () {
      expect(
        BrickPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: true, myStarted: false),
        isFalse,
      );
    });

    test('我已经点了开始 → 不再显示开房等人界面', () {
      expect(
        BrickPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: false, myStarted: true),
        isFalse,
      );
    });

    test('大厅匹配进来的 → 绝不显示开房界面', () {
      expect(
        BrickPageState.showsPrivateRoomWaiting(
            isPrivateHost: false, isReady: false, myStarted: false),
        isFalse,
      );
    });
  });

  group('房里还没对手时不许发 START_GAME', () {
    test('只有一个人 → 服务端是 WaitState，不认 START_GAME，按钮不能可变可点', () {
      expect(
        BrickPageState.canStartBattle(gameState: 'waiting', opponentUserId: ''),
        isFalse,
      );
    });

    test('好友按房号进来了 → 服务端进 ReadyState，可以开局', () {
      expect(
        BrickPageState.canStartBattle(gameState: 'ready', opponentUserId: 'u2'),
        isTrue,
      );
    });

    test('已收到对手用户ID但状态还没翻到 ready → 也可以开局', () {
      expect(
        BrickPageState.canStartBattle(gameState: 'waiting', opponentUserId: 'u2'),
        isTrue,
      );
    });
  });

  group('大厅匹配中的「开始单人练习」出口', () {
    test('刚进房、没人、也不在等好友 → 给匹配浮层（含练习出口）', () {
      expect(
        BrickPageState.showsMatchingOverlay(
            isPlaying: false,
            myStarted: false,
            hasOpponent: false,
            privateRoomWaiting: false),
        isTrue,
      );
    });

    test('已经有对手 → 不再显示匹配浮层', () {
      expect(
        BrickPageState.showsMatchingOverlay(
            isPlaying: false,
            myStarted: false,
            hasOpponent: true,
            privateRoomWaiting: false),
        isFalse,
      );
    });

    test('正在练习 → 不再显示匹配浮层', () {
      expect(
        BrickPageState.showsMatchingOverlay(
            isPlaying: true,
            myStarted: true,
            hasOpponent: false,
            privateRoomWaiting: false),
        isFalse,
      );
    });

    test('私房房主等人 → 交给开房面板，不叠匹配浮层', () {
      expect(
        BrickPageState.showsMatchingOverlay(
            isPlaying: false,
            myStarted: false,
            hasOpponent: false,
            privateRoomWaiting: true),
        isFalse,
      );
    });
  });

  group('开赛前的双方就绪浮层', () {
    test('房里有对手、还没开打 → 显示双方就绪浮层', () {
      expect(
        BrickPageState.showsReadinessOverlay(isPlaying: false, hasOpponent: true),
        isTrue,
      );
    });

    test('正在对局 → 不显示', () {
      expect(
        BrickPageState.showsReadinessOverlay(isPlaying: true, hasOpponent: true),
        isFalse,
      );
    });

    test('房里只有我 → 交给匹配/开房浮层，不叠就绪浮层', () {
      expect(
        BrickPageState.showsReadinessOverlay(isPlaying: false, hasOpponent: false),
        isFalse,
      );
    });
  });

  group('按房号进房失败', () {
    test('客户端必须监听服务端的 joinRoomFailed，并在退出页面时注销', () {
      final source = File('lib/page/brick.dart').readAsStringSync();

      // 输错房号时人已被摘出原房间：不监听就只能停在空棋盘上干等
      expect(source, contains("socket.on('joinRoomFailed'"),
          reason: '没有监听 joinRoomFailed，进房失败会静默卡住');

      final cleanup =
          source.substring(source.indexOf('void _cleanupSocketListeners()'));
      expect(cleanup, contains("'joinRoomFailed'"),
          reason: '监听必须在 _cleanupSocketListeners 里注销，否则离开页面后残留');
    });
  });
}
