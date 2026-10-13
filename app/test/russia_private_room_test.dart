import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/russia.dart';

void main() {
  group('私房（开房）界面判定', () {
    test('我开的房、好友还没来、我也没开始练 → 给开房等人界面', () {
      expect(
        RussiaPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: false, myStarted: false),
        isTrue,
      );
    });

    test('好友已进房 → 交回正常的就绪界面', () {
      expect(
        RussiaPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: true, myStarted: false),
        isFalse,
      );
    });

    test('已经在独自练习 → 不再显示开房等人界面', () {
      expect(
        RussiaPageState.showsPrivateRoomWaiting(
            isPrivateHost: true, isReady: false, myStarted: true),
        isFalse,
      );
    });

    test('大厅匹配进来的 → 绝不显示开房界面', () {
      expect(
        RussiaPageState.showsPrivateRoomWaiting(
            isPrivateHost: false, isReady: false, myStarted: false),
        isFalse,
      );
    });
  });

  group('按房号进房失败', () {
    test('客户端必须监听服务端的 joinRoomFailed，并在退出页面时注销', () {
      final source = File('lib/page/russia.dart').readAsStringSync();

      // 服务端发得出、客户端没监听 = 输错房号后静默卡死，谁都发现不了
      expect(source, contains("socket.on('joinRoomFailed'"),
          reason: '没有监听 joinRoomFailed，进房失败会静默卡住');

      final cleanup = source.substring(source.indexOf('void _cleanupSocketListeners()'));
      expect(cleanup, contains("'joinRoomFailed'"),
          reason: '监听必须在 _cleanupSocketListeners 里注销，否则离开页面后残留');
    });
  });

  group('换房间不能又回到原来那一间', () {
    test('按房号进来的客人点换房 → 走大厅匹配，不再重放那个房号', () {
      expect(
        RussiaPageState.roomEntryFor(switchRoom: true, extraArgs: {'joinRoomId': '1'}),
        RoomEntry.match,
      );
    });

    test('房主点换房 → 也走大厅匹配，不再自动开一间新房', () {
      expect(
        RussiaPageState.roomEntryFor(
            switchRoom: true, extraArgs: {'mode': 'createPrivate'}),
        RoomEntry.match,
      );
    });

    test('首次进入仍按路由意图走：开房 / 按房号进房 / 匹配', () {
      expect(
        RussiaPageState.roomEntryFor(
            switchRoom: false, extraArgs: {'mode': 'createPrivate'}),
        RoomEntry.createPrivate,
      );
      expect(
        RussiaPageState.roomEntryFor(switchRoom: false, extraArgs: {'joinRoomId': '7'}),
        RoomEntry.joinById,
      );
      expect(
        RussiaPageState.roomEntryFor(switchRoom: false, extraArgs: null),
        RoomEntry.match,
      );
    });

    test('换房时排除的房间号就是当前这一间', () {
      expect(
        RussiaPageState.roomToExcludeOnEnter(
            switchRoom: true, currentRoomId: 1, routeExceptRoom: null),
        1,
      );
    });

    test('换房时当前房号还没下发 → 退回路由带来的排除值', () {
      expect(
        RussiaPageState.roomToExcludeOnEnter(
            switchRoom: true, currentRoomId: null, routeExceptRoom: 9),
        9,
      );
    });

    test('首次进入不看当前房号，只认路由带来的排除值', () {
      expect(
        RussiaPageState.roomToExcludeOnEnter(
            switchRoom: false, currentRoomId: 3, routeExceptRoom: null),
        isNull,
      );
    });
  });
}
