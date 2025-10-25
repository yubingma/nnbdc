import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/sync.dart';

void main() {
  group('数据库同步 - mergeChanges函数', () {
    // 辅助函数，创建带有DateTime类型时间戳的变更记录
    Map<String, dynamic> createChange(String table, String recordId, String operation, DateTime updateTime, Map<String, dynamic> record) {
      return {
        'table_': table,
        'recordId': recordId,
        'operate': operation,
        'updateTime': updateTime,
        'createTime': updateTime,
        'record': record
      };
    }

    test('简单同步场景：没有冲突的记录', () {
      var now = DateTime.now();
      
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'INSERT', now.subtract(Duration(minutes: 5)), {'id': '1', 'name': 'Alice'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '2', 'INSERT', now.subtract(Duration(minutes: 3)), {'id': '2', 'name': 'Bob'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地记录应该同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      
      // 后端记录应该同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '2');
    });

    test('本地和后端都有相同记录但操作不同 - INSERT vs UPDATE', () {
      var now = DateTime.now();
      
      // 场景：本地插入记录，后端更新同一记录，但本地时间更新
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'INSERT', now, {'id': '1', 'name': 'Alice (local)'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '1', 'UPDATE', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (server)'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地插入记录应该转换为UPDATE并同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      expect(result.first[0]['operate'], 'UPDATE');
      
      // 后端不应该有需要同步到本地的
      expect(result.second.length, 0);
      
      // 反转时间，这次后端时间更新
      localChanges = [
        createChange('users', '1', 'INSERT', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (local)'}),
      ];

      backendChanges = [
        createChange('users', '1', 'UPDATE', now, {'id': '1', 'name': 'Alice (server)'}),
      ];

      result = mergeChanges(localChanges, backendChanges);
      
      // 本地不应该有需要同步到后端的
      expect(result.first.length, 0);
      
      // 后端更新应该同步到本地并保持为UPDATE
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '1');
      expect(result.second[0]['operate'], 'UPDATE');
    });

    test('本地和后端都有相同记录但操作不同 - UPDATE vs DELETE', () {
      var now = DateTime.now();
      
      // 场景：本地更新记录，后端删除同一记录，但本地时间更新
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'UPDATE', now, {'id': '1', 'name': 'Alice (updated)'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '1', 'DELETE', now.subtract(Duration(minutes: 1)), {'id': '1'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地更新应该转换为INSERT并同步到后端（因为后端已删除）
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      expect(result.first[0]['operate'], 'INSERT');
      
      // 后端不应该有需要同步到本地的
      expect(result.second.length, 0);
      
      // 反转时间，这次后端时间更新
      localChanges = [
        createChange('users', '1', 'UPDATE', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (updated)'}),
      ];

      backendChanges = [
        createChange('users', '1', 'DELETE', now, {'id': '1'}),
      ];

      result = mergeChanges(localChanges, backendChanges);
      
      // 本地不应该有需要同步到后端的，因为后端的删除操作有更高优先级
      expect(result.first.length, 0);
      
      // 后端删除应该同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '1');
      expect(result.second[0]['operate'], 'DELETE');
    });

    test('本地和后端都有相同记录且操作相同 - UPDATE vs UPDATE', () {
      var now = DateTime.now();
      
      // 场景：本地和后端都更新记录，但本地时间更新
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'UPDATE', now, {'id': '1', 'name': 'Alice (local update)'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '1', 'UPDATE', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (server update)'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地更新应该同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      expect(result.first[0]['operate'], 'UPDATE');
      
      // 后端不应该有需要同步到本地的
      expect(result.second.length, 0);
      
      // 反转时间，这次后端时间更新
      localChanges = [
        createChange('users', '1', 'UPDATE', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (local update)'}),
      ];

      backendChanges = [
        createChange('users', '1', 'UPDATE', now, {'id': '1', 'name': 'Alice (server update)'}),
      ];

      result = mergeChanges(localChanges, backendChanges);
      
      // 本地不应该有需要同步到后端的
      expect(result.first.length, 0);
      
      // 后端更新应该同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '1');
      expect(result.second[0]['operate'], 'UPDATE');
    });

    test('本地和后端都有相同记录但操作不同 - INSERT vs INSERT', () {
      var now = DateTime.now();
      
      // 场景：本地和后端都插入记录，但本地时间更新
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'INSERT', now, {'id': '1', 'name': 'Alice (local)'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '1', 'INSERT', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (server)'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地插入应该转换为UPDATE并同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      expect(result.first[0]['operate'], 'UPDATE');
      
      // 后端不应该有需要同步到本地的
      expect(result.second.length, 0);
      
      // 反转时间，这次后端时间更新
      localChanges = [
        createChange('users', '1', 'INSERT', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (local)'}),
      ];

      backendChanges = [
        createChange('users', '1', 'INSERT', now, {'id': '1', 'name': 'Alice (server)'}),
      ];

      result = mergeChanges(localChanges, backendChanges);
      
      // 本地不应该有需要同步到后端的
      expect(result.first.length, 0);
      
      // 后端插入应该转换为UPDATE并同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '1');
      expect(result.second[0]['operate'], 'UPDATE');
    });

    test('本地和后端都有相同记录但操作不同 - INSERT vs DELETE', () {
      var now = DateTime.now();
      
      // 场景：本地插入记录，后端删除同一记录，但本地时间更新
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'INSERT', now, {'id': '1', 'name': 'Alice (local)'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '1', 'DELETE', now.subtract(Duration(minutes: 1)), {'id': '1'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地插入应该同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], '1');
      expect(result.first[0]['operate'], 'INSERT');
      
      // 后端不应该有需要同步到本地的
      expect(result.second.length, 0);
      
      // 反转时间，这次后端时间更新
      localChanges = [
        createChange('users', '1', 'INSERT', now.subtract(Duration(minutes: 1)), {'id': '1', 'name': 'Alice (local)'}),
      ];

      backendChanges = [
        createChange('users', '1', 'DELETE', now, {'id': '1'}),
      ];

      result = mergeChanges(localChanges, backendChanges);
      
      // 本地不应该有需要同步到后端的
      expect(result.first.length, 0);
      
      // 后端删除应该同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], '1');
      expect(result.second[0]['operate'], 'DELETE');
    });

    test('多表同步', () {
      var now = DateTime.now();
      
      // 场景：同步多个表的记录
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'INSERT', now, {'id': '1', 'name': 'Alice'}),
        createChange('dakas', '1-20230101', 'INSERT', now, {'user_id': '1', 'date': '20230101', 'text': 'Daka record'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('learningDicts', '1-dict1', 'INSERT', now, {'user_id': '1', 'dict_id': 'dict1'}),
        createChange('userStudySteps', '1-Word', 'UPDATE', now, {'user_id': '1', 'study_step': 'Word', 'state': 'Active'}),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地应该有2条记录同步到后端
      expect(result.first.length, 2);
      
      // 后端应该有2条记录同步到本地
      expect(result.second.length, 2);
      
      // 验证每个表是否都有正确的记录
      expect(result.first.any((change) => change['table_'] == 'users'), true);
      expect(result.first.any((change) => change['table_'] == 'dakas'), true);
      expect(result.second.any((change) => change['table_'] == 'learningDicts'), true);
      expect(result.second.any((change) => change['table_'] == 'userStudySteps'), true);
    });

    test('合并操作移除多余记录', () {
      var now = DateTime.now();
      
      // 场景：合并操作应该移除多余的记录
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'UPDATE', now.subtract(Duration(minutes: 10)), {'id': '1', 'name': 'Old update'}),
        createChange('users', '1', 'UPDATE', now, {'id': '1', 'name': 'New update'}), // 这应该保留
        createChange('users', '2', 'DELETE', now, {'id': '2'}),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('users', '3', 'INSERT', now, {'id': '3', 'name': 'Charlie'}),
        createChange('users', '4', 'UPDATE', now.subtract(Duration(minutes: 5)), {'id': '4', 'name': 'Old Dave'}),
        createChange('users', '4', 'UPDATE', now, {'id': '4', 'name': 'New Dave'}), // 这应该保留
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地应该有2条记录同步到后端 (用户1和2)
      expect(result.first.length, 2);
      
      // 验证用户1的记录是较新的
      var user1Record = result.first.firstWhere((change) => change['recordId'] == '1');
      expect(user1Record['record']['name'], 'New update');
      
      // 后端应该有2条记录同步到本地 (用户3和4)
      expect(result.second.length, 2);
      
      // 验证用户4的记录是较新的
      var user4Record = result.second.firstWhere((change) => change['recordId'] == '4');
      expect(user4Record['record']['name'], 'New Dave');
    });

    test('打卡记录同步', () {
      var now = DateTime.now();
      var yesterday = now.subtract(Duration(days: 1));
      
      // 创建打卡记录ID
      String formatDate(DateTime date) {
        return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
      }
      
      String todayId = '1-${formatDate(now)}';
      String yesterdayId = '1-${formatDate(yesterday)}';
      
      // 场景：同步打卡记录
      List<Map<String, dynamic>> localChanges = [
        createChange('dakas', todayId, 'INSERT', now, {
          'user_id': '1',
          'for_learning_date': now.toIso8601String(),
          'text': '今天的打卡记录'
        }),
      ];

      List<Map<String, dynamic>> backendChanges = [
        createChange('dakas', yesterdayId, 'INSERT', yesterday, {
          'user_id': '1',
          'for_learning_date': yesterday.toIso8601String(),
          'text': '昨天的打卡记录'
        }),
      ];

      var result = mergeChanges(localChanges, backendChanges);
      
      // 本地应该有1条今天的打卡记录同步到后端
      expect(result.first.length, 1);
      expect(result.first[0]['recordId'], todayId);
      
      // 后端应该有1条昨天的打卡记录同步到本地
      expect(result.second.length, 1);
      expect(result.second[0]['recordId'], yesterdayId);
    });
  });
}
