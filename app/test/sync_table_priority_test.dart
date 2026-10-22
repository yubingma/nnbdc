import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/sync.dart';
import 'package:nnbdc/util/utils.dart';

void main() {
  // 所有会写入端云同步日志的表（DbLogUtil.logOperation 的第三个参数）。
  // 任何一张漏登记，排序时就会抛 Unknown table name，把整次同步打回。
  const userWritableTables = [
    'users',
    'dicts',
    'dictWords',
    'words',
    'learningDicts',
    'learningWords',
    'bookMarks',
    'dakas',
    'userOpers',
    'userCowDungLogs',
    'userWrongWords',
    'userStudySteps',
    'meaningItems',
    'learningLogs',
    'userStudyDailyStats',
    'userBadges',
  ];

  test('所有上行同步表都有排序优先级', () {
    for (final table in userWritableTables) {
      expect(() => getTableSyncPriority(table), returnsNormally, reason: '$table 缺少同步优先级');
    }
  });

  test('单词先于词条排序，避免词条引用到尚未落库的单词', () {
    expect(getTableSyncPriority('words'), lessThan(getTableSyncPriority('dictWords')));
  });

  test('word 表在客户端双向映射为 words', () {
    expect(Util.remoteTableNameToLocal('word'), 'words');
    expect(Util.localTableNameToRemote('words'), 'word');
  });
}
