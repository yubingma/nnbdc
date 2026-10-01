import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/study_consistency_checker.dart';

/// 客户端"数据自洽"判定口径的测试。
///
/// 判定口径必须与服务端只读体检一致：某业务日内某词的
/// 「今日评分流水条数」不得少于「learning_word.today_learned_times」。
void main() {
  group('judgeStudyConsistency', () {
    test('进度与流水条数相等时自洽', () {
      expect(judgeStudyConsistency(progress: 3, actualLogCount: 3), isNull);
    });

    test('流水条数多于进度时不算客户端不自洽（重复写流水由服务端体检发现）', () {
      // 例如 3 条流水但进度只有 1：这类"流水多于进度"的方向不在这里判，
      // 避免与服务端的判定口径冲突产生两套标准
      expect(judgeStudyConsistency(progress: 1, actualLogCount: 3), isNull);
    });

    test('进度大于流水条数时命中 progressExceedsLogs', () {
      // 线上真实形态：3 条流水、进度被推到 4
      expect(
        judgeStudyConsistency(progress: 4, actualLogCount: 3),
        StudyConsistencyRule.progressExceedsLogs,
      );
      expect(
        judgeStudyConsistency(progress: 2, actualLogCount: 1),
        StudyConsistencyRule.progressExceedsLogs,
      );
    });

    test('进度不为 0 但今天没有任何流水时命中', () {
      expect(
        judgeStudyConsistency(progress: 1, actualLogCount: 0),
        StudyConsistencyRule.progressExceedsLogs,
      );
    });

    test('进度为 0 且没有流水时自洽（新词还没答过）', () {
      expect(judgeStudyConsistency(progress: 0, actualLogCount: 0), isNull);
    });
  });

  group('judgeTodayWord', () {
    test('自洽时返回 null', () {
      expect(
        judgeTodayWord(progress: 2, actualLogCount: 2, wordId: '15407'),
        isNull,
      );
    });

    test('不自洽时带出单词与数值', () {
      final violation =
          judgeTodayWord(progress: 4, actualLogCount: 3, wordId: '15407', spell: 'electronic');

      expect(violation, isNotNull);
      expect(violation!.wordId, '15407');
      expect(violation.spell, 'electronic');
      expect(violation.progress, 4);
      expect(violation.actualLogCount, 3);
      expect(violation.rule, StudyConsistencyRule.progressExceedsLogs);
    });

    test('拿不到拼写时退回词 ID，不产生空标签', () {
      final violation = judgeTodayWord(progress: 1, actualLogCount: 0, wordId: '15407');

      expect(violation!.spell, '15407');
    });
  });

  group('StudyConsistencyViolation.toMessage', () {
    test('上报文本带规则标识、实体、实际值、期望值与客户端版本', () {
      const violation = StudyConsistencyViolation(
        rule: StudyConsistencyRule.progressExceedsLogs,
        wordId: '15407',
        spell: 'electronic',
        progress: 4,
        actualLogCount: 3,
      );

      final message = violation.toMessage('26092401');

      expect(message.contains('progress_gt_logs'), isTrue,
          reason: '必须带稳定规则标识，服务端按它聚合告警: $message');
      expect(message.contains('electronic (15407)'), isTrue,
          reason: '必须带单词与实体 ID: $message');
      expect(message.contains('progress=4'), isTrue, reason: '必须带实际值: $message');
      expect(message.contains('businessDayLogs=3'), isTrue, reason: '必须带实际值: $message');
      expect(message.contains('期望值'), isTrue, reason: '必须写清期望值: $message');
      expect(message.contains('26092401'), isTrue,
          reason: '必须带客户端版本，坏数据往往是单版本集中的: $message');
    });

    test('上报文本不携带单词释义等学习内容', () {
      const violation = StudyConsistencyViolation(
        rule: StudyConsistencyRule.progressExceedsLogs,
        wordId: '15407',
        spell: 'electronic',
        progress: 4,
        actualLogCount: 3,
      );

      final message = violation.toMessage('26092401');

      expect(message.contains('电子'), isFalse, reason: '不得把用户的学习内容带上服务端: $message');
    });
  });
}
