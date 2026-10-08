import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/study_consistency_checker.dart';

/// 客户端"数据自洽"判定口径的测试。
///
/// 判定口径必须与服务端只读体检一致：某业务日内某词的
/// 「今日评分流水条数」不得少于「learning_word.today_learned_times」。
void main() {
  group('judgeDuplicateGrade', () {
    GradeLogSummary log(String id, int rating, double stability, DateTime at) =>
        GradeLogSummary(id: id, rating: rating, stability: stability, createTime: at);

    // 线上真实现场：electronic 的三条流水写在 17 毫秒内，其中两条稳定度完全相同
    final base = DateTime(2026, 10, 1, 5, 23, 24, 36);

    test('只有一条流水时不报', () {
      expect(
        judgeDuplicateGrade(
          wordId: '15407',
          spell: 'electronic',
          logs: [log('a', 4, 5.8, base)],
        ),
        isNull,
      );
    });

    test('相邻两条间隔 5 毫秒且稳定度相同：命中并带出现场数值', () {
      final violation = judgeDuplicateGrade(
        wordId: '15407',
        spell: 'electronic',
        logs: [
          log('a', 4, 5.8, base),
          log('b', 4, 5.8, base.add(const Duration(milliseconds: 5))),
        ],
      );

      expect(violation, isNotNull);
      expect(violation!.gapMilliseconds, 5);
      expect(violation.sameStability, isTrue, reason: '两份流水稳定度一字不差，说明同一前态被算了两遍');
      expect(violation.firstLogId, 'a');
      expect(violation.secondLogId, 'b');
    });

    test('间隔一秒内的不同评分档也命中（同一作答被两条路径分别计分）', () {
      final violation = judgeDuplicateGrade(
        wordId: '15407',
        spell: 'electronic',
        logs: [
          log('a', 4, 5.8, base),
          log('b', 3, 2.4, base.add(const Duration(milliseconds: 900))),
        ],
      );

      expect(violation, isNotNull);
      expect(violation!.sameStability, isFalse, reason: '不同前态算出来的稳定度不同，要如实记录');
    });

    test('正常作答间隔（超过窗口）不报', () {
      expect(
        judgeDuplicateGrade(
          wordId: '15407',
          spell: 'electronic',
          logs: [
            log('a', 4, 5.8, base),
            log('b', 4, 7.9, base.add(const Duration(seconds: 12))),
          ],
        ),
        isNull,
        reason: '人手正常作答的间隔远大于 2 秒，不能被当成重复计分',
      );
    });

    test('三条流水里首尾很近但相邻的都正常时不报（只看相邻两条）', () {
      // 中间隔着一次正常作答：首尾差 4 秒，但相邻间隔都超过窗口
      expect(
        judgeDuplicateGrade(
          wordId: '15407',
          spell: 'electronic',
          logs: [
            log('a', 4, 5.8, base),
            log('b', 3, 2.4, base.add(const Duration(seconds: 3))),
            log('c', 4, 7.9, base.add(const Duration(seconds: 6))),
          ],
        ),
        isNull,
        reason: '判定只取时间上相邻的两条，不能拿首尾去比',
      );
    });

    test('三条流水里命中第一对相邻的就返回', () {
      final violation = judgeDuplicateGrade(
        wordId: '15407',
        spell: 'electronic',
        logs: [
          log('a', 4, 5.8, base),
          log('b', 3, 2.4, base.add(const Duration(milliseconds: 5))),
          log('c', 4, 7.9, base.add(const Duration(seconds: 8))),
        ],
      );

      expect(violation, isNotNull);
      expect(violation!.secondLogId, 'b');
    });

    test('上报文本带规则标识、两条流水、时间差与客户端版本', () {
      final violation = judgeDuplicateGrade(
        wordId: '15407',
        spell: 'electronic',
        logs: [
          log('log_first', 4, 5.8, base),
          log('log_second', 4, 5.8, base.add(const Duration(milliseconds: 5))),
        ],
      )!;

      final message = violation.toMessage('26092401');

      expect(message.contains('duplicate_grade'), isTrue, reason: message);
      expect(message.contains('log_first'), isTrue, reason: message);
      expect(message.contains('log_second'), isTrue, reason: message);
      expect(message.contains('间隔=5ms'), isTrue, reason: message);
      expect(message.contains('26092401'), isTrue, reason: message);
      expect(message.contains('电子'), isFalse, reason: '不得把学习内容带上服务端: $message');
    });
  });

  group('judgeStudyConsistency', () {
    test('进度与流水条数相等且未超轨道时自洽', () {
      expect(judgeStudyConsistency(progress: 3, actualLogCount: 3, trackLenMax: 3), isNull);
    });

    test('进度大于流水条数（如走完List或提前掌握）且未超轨道时属于正常合法状态', () {
      // 走完 List 环节：流水 2 条，进度 3，未超轨道 3
      expect(judgeStudyConsistency(progress: 3, actualLogCount: 2, trackLenMax: 3), isNull);
      // 首答掌握提前毕业：流水 1 条，进度 3，未超轨道 3
      expect(judgeStudyConsistency(progress: 3, actualLogCount: 1, trackLenMax: 3), isNull);
    });

    test('流水条数多于进度时命中 logsExceedProgress', () {
      // 重复计分写了多条流水
      expect(
        judgeStudyConsistency(progress: 1, actualLogCount: 2, trackLenMax: 3),
        StudyConsistencyRule.logsExceedProgress,
      );
    });

    test('进度超过轨道上限时命中 progressExceedsTrack', () {
      // 轨道上限 3，被多推进到 4
      expect(
        judgeStudyConsistency(progress: 4, actualLogCount: 3, trackLenMax: 3),
        StudyConsistencyRule.progressExceedsTrack,
      );
    });

    test('进度为 0 且有流水时不报（跨天复位后的正常状态）', () {
      expect(judgeStudyConsistency(progress: 0, actualLogCount: 4, trackLenMax: 3), isNull);
      expect(judgeStudyConsistency(progress: 0, actualLogCount: 1, trackLenMax: 3), isNull);
    });

    test('进度为 0 且没有流水时自洽（新词还没答过）', () {
      expect(judgeStudyConsistency(progress: 0, actualLogCount: 0, trackLenMax: 3), isNull);
    });
  });

  group('judgeTodayWord', () {
    test('自洽时返回 null', () {
      expect(
        judgeTodayWord(progress: 2, actualLogCount: 2, wordId: '15407', trackLenMax: 3),
        isNull,
      );
    });

    test('进度越界时带出单词与数值', () {
      final violation =
          judgeTodayWord(progress: 4, actualLogCount: 3, wordId: '15407', spell: 'electronic', trackLenMax: 3);

      expect(violation, isNotNull);
      expect(violation!.wordId, '15407');
      expect(violation.spell, 'electronic');
      expect(violation.progress, 4);
      expect(violation.actualLogCount, 3);
      expect(violation.trackLenMax, 3);
      expect(violation.rule, StudyConsistencyRule.progressExceedsTrack);
    });

    test('流水多于进度时命中 logsExceedProgress', () {
      final violation = judgeTodayWord(progress: 1, actualLogCount: 2, wordId: '15407', trackLenMax: 3);

      expect(violation!.rule, StudyConsistencyRule.logsExceedProgress);
      expect(violation.spell, '15407');
    });
  });

  group('StudyConsistencyViolation.toMessage', () {
    test('上报文本带规则标识、实体、实际值、期望值与客户端版本', () {
      const violation = StudyConsistencyViolation(
        rule: StudyConsistencyRule.progressExceedsTrack,
        wordId: '15407',
        spell: 'electronic',
        progress: 4,
        actualLogCount: 3,
        trackLenMax: 3,
      );

      final message = violation.toMessage('26092401');

      expect(message.contains('progress_gt_track'), isTrue,
          reason: '必须带稳定规则标识，服务端按它聚合告警: $message');
      expect(message.contains('electronic (15407)'), isTrue,
          reason: '必须带单词与实体 ID: $message');
      expect(message.contains('progress=4'), isTrue, reason: '必须带实际值: $message');
      expect(message.contains('trackLenMax=3'), isTrue, reason: '必须带实际值: $message');
      expect(message.contains('期望值'), isTrue, reason: '必须写清期望值: $message');
      expect(message.contains('26092401'), isTrue,
          reason: '必须带客户端版本，坏数据往往是单版本集中的: $message');
    });

    test('上报文本不携带单词释义等学习内容', () {
      const violation = StudyConsistencyViolation(
        rule: StudyConsistencyRule.progressExceedsTrack,
        wordId: '15407',
        spell: 'electronic',
        progress: 4,
        actualLogCount: 3,
        trackLenMax: 3,
      );

      final message = violation.toMessage('26092401');

      expect(message.contains('电子'), isFalse, reason: '不得把用户的学习内容带上服务端: $message');
    });
  });
}
