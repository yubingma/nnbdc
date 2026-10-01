import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';

void main() {
  group('FeatureRequestWall 分类与排序测试', () {
    test('FeatureRequestVo 序列化与反序列化支持 category 字段', () {
      final json = {
        'id': 'req-1',
        'title': '生词本支持导出 PDF',
        'content': '方便打印复习',
        'status': 'VOTING',
        'category': 'VOCABULARY',
        'voteCount': 42,
        'createTime': '2026-09-30 10:00:00.000',
      };

      final vo = FeatureRequestVo.fromJson(json);
      expect(vo.id, 'req-1');
      expect(vo.title, '生词本支持导出 PDF');
      expect(vo.category, 'VOCABULARY');
      expect(vo.voteCount, 42);

      final serialized = vo.toJson();
      expect(serialized['category'], 'VOCABULARY');
      expect(serialized['voteCount'], 42);
    });

    test('分类筛选与排序：最新排序能让票数少的新需求排在首位', () {
      final oldHotReq = FeatureRequestVo(
        'req-old-hot',
        '老高赞需求',
        '早就提了',
        'VOTING',
        'VOCABULARY',
        100,
        null,
        DateTime.parse('2026-01-01 12:00:00'),
      );

      final newColdReq = FeatureRequestVo(
        'req-new-cold',
        '刚才提的新建议',
        '刚刚提交，票数少',
        'VOTING',
        'VOCABULARY',
        1,
        null,
        DateTime.parse('2026-09-30 14:00:00'),
      );

      final otherCatReq = FeatureRequestVo(
        'req-other-cat',
        'UI 视觉改动',
        '暗色模式微调',
        'VOTING',
        'EXPERIENCE',
        50,
        null,
        DateTime.parse('2026-05-01 12:00:00'),
      );

      final allRequests = [oldHotReq, newColdReq, otherCatReq];

      // 1. 分类筛选：仅筛选 VOCABULARY
      final vocabRequests = allRequests.where((r) => r.category == 'VOCABULARY').toList();
      expect(vocabRequests.length, 2);
      expect(vocabRequests.any((r) => r.id == 'req-other-cat'), isFalse);

      // 2. 最热排序（HOT）：老高赞排在前面，新冷门沉底
      final hotSorted = List<FeatureRequestVo>.from(vocabRequests)
        ..sort((a, b) {
          final countCmp = (b.voteCount ?? 0).compareTo(a.voteCount ?? 0);
          if (countCmp != 0) return countCmp;
          return b.createTime.compareTo(a.createTime);
        });
      expect(hotSorted.first.id, 'req-old-hot');
      expect(hotSorted.last.id, 'req-new-cold');

      // 3. 最新排序（NEWEST）：新冷门排在最前面，彻底打破被淹没
      final newestSorted = List<FeatureRequestVo>.from(vocabRequests)
        ..sort((a, b) => b.createTime.compareTo(a.createTime));
      expect(newestSorted.first.id, 'req-new-cold');
      expect(newestSorted.last.id, 'req-old-hot');
    });

    test('需求删除后从列表中同步移除', () {
      final list = [
        FeatureRequestVo('req-1', '需求1', '内容1', 'VOTING', 'FEATURE', 10, null, DateTime.now()),
        FeatureRequestVo('req-2', '需求2', '内容2', 'VOTING', 'FEATURE', 20, null, DateTime.now()),
      ];

      expect(list.length, 2);
      list.removeWhere((r) => r.id == 'req-1');
      expect(list.length, 1);
      expect(list.first.id, 'req-2');
    });
  });
}
