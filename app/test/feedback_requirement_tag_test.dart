import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';

void main() {
  group('MsgVo 需求标签序列化与反序列化测试', () {
    test('正确解析带有 tag 的 JSON', () {
      final json = {
        'id': 'msg_1',
        'fromUserName': 'alice',
        'fromUserNickName': 'Alice',
        'toUserName': 'admin',
        'toUserNickName': '管理员',
        'content': '希望能支持横屏左右分栏背单词',
        'createTimeForDisplay': '5分钟前',
        'msgType': 'Advice',
        'clientType': 'android',
        'fromUser': {
          'id': 'user_1',
          'userName': 'alice',
          'nickName': 'Alice',
          'isCowDungAwardedToday': false,
        },
        'toUser': {
          'id': 'admin_1',
          'userName': 'admin',
          'isCowDungAwardedToday': false,
        },
        'createTime': '2026-10-09T20:53:00.000Z',
        'viewed': true,
        'tag': '需求',
      };

      final vo = MsgVo.fromJson(json);
      expect(vo.id, 'msg_1');
      expect(vo.content, '希望能支持横屏左右分栏背单词');
      expect(vo.tag, '需求');
      expect(vo.viewed, isTrue);

      final outJson = vo.toJson();
      expect(outJson['tag'], '需求');
    });

    test('当 JSON 不包含 tag 字段时正常兼容解析为 null', () {
      final json = {
        'id': 'msg_2',
        'fromUserName': 'bob',
        'content': '打卡打卡',
        'msgType': 'Advice',
        'fromUser': {
          'id': 'user_2',
          'userName': 'bob',
          'isCowDungAwardedToday': false,
        },
        'toUser': {
          'id': 'admin_1',
          'userName': 'admin',
          'isCowDungAwardedToday': false,
        },
        'createTime': '2026-10-09T20:55:00.000Z',
        'viewed': false,
      };

      final vo = MsgVo.fromJson(json);
      expect(vo.id, 'msg_2');
      expect(vo.tag, isNull);
    });

    test('按需求标签过滤筛选列表', () {
      final user = UserVo('u1', 'user1');
      final msgs = [
        MsgVo('1', 'u1', null, 'adm', null, '普通闲聊', null, 'Advice', null, user, user, DateTime.now(), true),
        MsgVo('2', 'u2', null, 'adm', null, '希望加入平板适配', null, 'Advice', null, user, user, DateTime.now(), true, '需求'),
        MsgVo('3', 'u3', null, 'adm', null, '希望支持暗黑模式快捷切换', null, 'Advice', null, user, user, DateTime.now(), false, '需求'),
        MsgVo('4', 'u4', null, 'adm', null, '我是小可爱', null, 'Advice', null, user, user, DateTime.now(), true),
      ];

      final requirementMsgs = msgs.where((m) => m.tag == '需求').toList();
      expect(requirementMsgs.length, 2);
      expect(requirementMsgs.map((m) => m.id).toList(), ['2', '3']);
    });
  });
}
