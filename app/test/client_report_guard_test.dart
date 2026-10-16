import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/client_error_reporter.dart';

/// 客户端故障上报闸门的测试。
///
/// 被测行为：[claimClientReportSlot] 负责"按分类+业务日+场景去重"与"每个分类每业务日总量上限"。
/// 它是关键保护：这类问题一旦出现就是成批的（真实现场是 17 毫秒里命中 18 个词；
/// 本地库坏掉时同一个场景会连着失败几十次），没有它会把服务端刷屏、把真正要处理的告警淹掉。
///
/// 每次用例前把时钟拨到不同的业务日，用来重置模块内的当日计数（这个状态没有对外暴露重置接口）。
void main() {
  const category = 'CLIENT_DATA_INCONSISTENT';

  /// 用"换一个业务日"来获得干净的上报额度
  void freshBusinessDay(int day) {
    AppClock.setClock(FakeClock(DateTime(2026, 10, day, 10, 0)));
  }

  tearDown(AppClock.reset);

  test('同一个场景同一个分类只放行一次', () {
    freshBusinessDay(1);

    expect(claimClientReportSlot(category, 'progress_gt_logs|word_1'), isNotNull,
        reason: '第一次应放行');
    expect(claimClientReportSlot(category, 'progress_gt_logs|word_1'), isNull,
        reason: '同一条问题重复出现，不应重复上报');
  });

  test('不同场景、不同分类各自放行', () {
    freshBusinessDay(2);

    expect(claimClientReportSlot(category, 'progress_gt_logs|word_1'), isNotNull);
    expect(claimClientReportSlot(category, 'progress_gt_logs|word_2'), isNotNull,
        reason: '同一个词只去重一次，别的词照常上报');
    expect(claimClientReportSlot(category, 'duplicate_grade|word_1'), isNotNull,
        reason: '场景不同，不能互相压制');
    expect(claimClientReportSlot('CLIENT_DB_ERROR', 'progress_gt_logs|word_1'), isNotNull,
        reason: '分类不同（各自有独立额度），同样不能互相压制');
  });

  test('每个分类每个业务日有总量上限，超出的丢弃', () {
    freshBusinessDay(3);

    var allowed = 0;
    for (var i = 0; i < maxClientReportsPerCategoryPerDay + 5; i++) {
      if (claimClientReportSlot(category, 'scene_$i') != null) allowed++;
    }

    expect(allowed, maxClientReportsPerCategoryPerDay,
        reason: '一个批量问题不能把服务端刷屏，上限外的一律丢弃');
  });

  test('一个分类用满额度不影响另一个分类', () {
    freshBusinessDay(6);

    for (var i = 0; i < maxClientReportsPerCategoryPerDay; i++) {
      claimClientReportSlot(category, 'scene_$i');
    }
    expect(claimClientReportSlot(category, 'scene_extra'), isNull,
        reason: '该分类当天额度已用完');

    expect(claimClientReportSlot('CLIENT_CRASH', 'scene_extra'), isNotNull,
        reason: '崩溃这类告警不能被数据不一致的刷屏压掉');
  });

  test('跨业务日后额度重新计算', () {
    freshBusinessDay(4);

    for (var i = 0; i < maxClientReportsPerCategoryPerDay; i++) {
      claimClientReportSlot(category, 'scene_$i');
    }
    expect(claimClientReportSlot(category, 'scene_extra'), isNull,
        reason: '当天额度已用完');

    // 进入下一个业务日：计数与去重集合都应重置
    freshBusinessDay(5);
    expect(claimClientReportSlot(category, 'scene_extra'), isNotNull,
        reason: '跨天后额度应重新计算');
    expect(claimClientReportSlot(category, 'scene_0'), isNotNull,
        reason: '跨天后去重集合也应清空');
  });
}
