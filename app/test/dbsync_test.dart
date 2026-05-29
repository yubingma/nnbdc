import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/sync.dart';

void main() {
  group('数据库同步 - mergeChanges函数', () {
    // 辅助函数，创建带有DateTime类型时间戳的变更记录
    Map<String, dynamic> createChange(String table, String recordId, String operation, DateTime updateTime, Map<String, dynamic> record) {
      return {
        'tblName': table,
        'recordId': recordId,
        'operate': operation,
        'updateTime': updateTime,
        'createTime': updateTime,
        'record': record
      };
    }

    test('简单同步场景：没有冲突的记录', () {
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      var now = AppClock.now();
      
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
      expect(result.first.any((change) => change['tblName'] == 'users'), true);
      expect(result.first.any((change) => change['tblName'] == 'dakas'), true);
      expect(result.second.any((change) => change['tblName'] == 'learningDicts'), true);
      expect(result.second.any((change) => change['tblName'] == 'userStudySteps'), true);
    });

    test('合并操作移除多余记录', () {
      var now = AppClock.now();
      
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
      var now = AppClock.now();
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

    test('时区时差冲突校验（防止时光倒流式覆盖）', () {
      // 1. 构造一个绝对物理时刻
      // 本地发生修改是在北京时间 20:01:43
      // 其绝对毫秒数为 1780056103000
      var localUpdateTime = DateTime.fromMillisecondsSinceEpoch(1780056103000); // 对应 20:01:43 Local
      
      // 2. 构造本地用户的修改日志 (UPDATE)
      List<Map<String, dynamic>> localChanges = [
        createChange('users', '1', 'UPDATE', localUpdateTime, {
          'id': '1',
          'lastLearningDate': '2026-05-29T00:00:00.000', // 设为今天
          'todayStudyStarted': true,
        }),
      ];

      // 3. 场景A：服务端由于 Bug 丢失了 UTC 时区配置，导致本该是稍早前 20:00:00 的旧数据，
      // 被错误反序列化为 UTC 的 20:00:00.000Z（物理上变成了北京时间次日 04:00:00，比本地晚了 8 小时）
      var buggyBackendUpdateTime = DateTime.parse('2026-05-29T20:00:00.000Z'); // 绝对物理上对应北京时间次日 04:00
      List<Map<String, dynamic>> buggyBackendChanges = [
        createChange('users', '1', 'UPDATE', buggyBackendUpdateTime, {
          'id': '1',
          'lastLearningDate': '2026-05-28T00:00:00.000', // 昨天（旧数据）
          'todayStudyStarted': true,
        }),
      ];

      var buggyResult = mergeChanges(localChanges, buggyBackendChanges);
      
      // 漏洞展现：由于时区时差误判，错误的“未来”旧数据把本地最新数据无情覆盖了！
      // 验证在没有时区对齐时，确实会发生“时光倒流式覆盖”，把本地上传拦截，并把后端旧数据强加到本地！
      expect(buggyResult.first.length, 0); // 本地修改被阻止上传
      expect(buggyResult.second.length, 1); // 强制把服务端的旧数据同步到本地覆盖！
      expect(buggyResult.second[0]['record']['lastLearningDate'], '2026-05-28T00:00:00.000'); // 覆盖为了昨天

      // 4. 场景B：当服务端根治了时区 Bug 后，服务端的旧记录被正确表示为 UTC 的 12:00:00.000Z（即北京时间 20:00:00）
      var correctBackendUpdateTime = DateTime.parse('2026-05-29T12:00:00.000Z'); // 物理上早于本地 1 分 43 秒
      List<Map<String, dynamic>> correctBackendChanges = [
        createChange('users', '1', 'UPDATE', correctBackendUpdateTime, {
          'id': '1',
          'lastLearningDate': '2026-05-28T00:00:00.000', // 昨天（旧数据）
          'todayStudyStarted': true,
        }),
      ];
      var correctResult = mergeChanges(localChanges, correctBackendChanges);

      // 根治验证：当后端时区修复后，本地最新修改理所应当被保留并上传，后端旧记录被安全抛弃！
      expect(correctResult.first.length, 1); // 本地修改顺利上传到后端
      expect(correctResult.first[0]['record']['lastLearningDate'], '2026-05-29T00:00:00.000'); // 保持为今天
      expect(correctResult.second.length, 0); // 服务端旧记录被安全阻断，没有同步到本地覆盖！
    });
  });
}
