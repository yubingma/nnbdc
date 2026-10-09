import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';

/// 回归：系统词书补齐必须按 (dictId, wordId) 对账，不能依赖序号。
///
/// 线上真实事故：通用词典元数据 79,473 条、本地只有 61,774 条，健康检查一直红，
/// 点修复也补不回来 —— 因为老修复流程拿"本地实际条数"当拉取上界，缺口永远不会被请求。
void main() {
  group('系统词书 (dictId, wordId) 对账', () {
    test('算出本地缺的与本地多余的', () {
      final diff = diffDictWordIds({'a', 'b', 'c'}, {'b', 'c', 'd'});
      expect(diff.missing, ['a'], reason: '服务端有、本地没有的必须列为待补');
      expect(diff.extra, ['d'], reason: '本地有、服务端没有的必须列为待清');
    });

    test('两侧顺序都稳定（按 wordId 排序），便于分批与断点续传', () {
      final diff = diffDictWordIds({'c', 'a', 'b'}, {});
      expect(diff.missing, ['a', 'b', 'c']);
    });

    test('完全一致时两边都为空', () {
      final diff = diffDictWordIds({'a', 'x'}, {'x', 'a'});
      expect(diff.missing, isEmpty);
      expect(diff.extra, isEmpty);
    });
  });

  group('补齐结果摘要', () {
    test('补完与没补完都要如实报出剩余缺口', () {
      final done = SystemDictRepairResult('0')
        ..serverTotal = 79473
        ..localBefore = 61774
        ..fetched = 17699
        ..removed = 0
        ..remaining = 0;
      expect(done.success, isTrue);
      expect(done.summary(), contains('服务端 79473 条'));
      expect(done.summary(), contains('仍缺 0 条'));

      final partial = SystemDictRepairResult('0')
        ..serverTotal = 79473
        ..localBefore = 61774
        ..fetched = 2000
        ..remaining = 15699;
      expect(partial.summary(), contains('本次补 2000 条'));
      expect(partial.summary(), contains('仍缺 15699 条'),
          reason: '没补完不能报成完成，否则下次不会继续补');
    });

    test('失败摘要带错误原因', () {
      final failed = SystemDictRepairResult('0')..error = '拉取服务端单词清单失败';
      expect(failed.success, isFalse);
      expect(failed.summary(), contains('拉取服务端单词清单失败'));
    });
  });
}
