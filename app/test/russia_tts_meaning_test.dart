import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/russia.dart';

void main() {
  group('Russia TTS Meaning Alignment Tests', () {
    test('should extract first meaning strictly aligned with display text (pepper case)', () {
      final pepper = WordVo.c2('pepper')
        ..meaningStr = 'n. 胡椒；胡椒粉；辣椒；vt. 布满；加胡椒粉'
        // 模拟 meaningItems 排序与 meaningStr 不一致（例如第一项是辣椒）
        ..meaningItems = [
          MeaningItemVo.from('n.', '辣椒'),
          MeaningItemVo.from('n.', '胡椒'),
        ];

      // 断言：必须与屏幕展示的 meaningStr 首项“胡椒”严格对齐，绝不能读“辣椒”
      final ttsWord = RussiaPageState.extractFirstMeaningForTts(pepper);
      expect(ttsWord, '胡椒');
    });

    test('should handle words with parenthesis and multiple pos prefixes', () {
      final aha = WordVo.c2('aha')
        ..meaningStr = 'int. 啊哈（表示惊喜、得意等）';
      expect(RussiaPageState.extractFirstMeaningForTts(aha), '啊哈');

      final run = WordVo.c2('run')
        ..meaningStr = 'vt.&vi. 跑；奔跑；运转';
      expect(RussiaPageState.extractFirstMeaningForTts(run), '跑');

      final book = WordVo.c2('book')
        ..meaningStr = 'n. 书，书籍；vt. 预订';
      expect(RussiaPageState.extractFirstMeaningForTts(book), '书');
    });

    test('should fallback to getMeaningStr when meaningStr is empty', () {
      final word = WordVo.c2('cat')
        ..meaningStr = ''
        ..meaningItems = [
          MeaningItemVo.from('n.', '猫；猫科动物'),
        ];
      expect(RussiaPageState.extractFirstMeaningForTts(word), '猫');
    });
  });
}
