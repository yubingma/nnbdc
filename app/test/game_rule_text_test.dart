import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PK 大厅「对战玩法规则」弹窗的文案口径。
///
/// 用户反馈：道具改名后规则文案没跟着改。查下去发现问题比改名大得多——
/// 整段规则还停在旧版俄罗斯方块时代（"单词下落""消除方块""＋顶起对手方块"），
/// 而实际玩法早就是泡泡升腾点选 + 10 格生命 + 水雷/海星道具了。
void main() {
  /// 只截取规则弹窗那一段，避免误伤页面上的其它文案
  String rulesSection() {
    final source = File('lib/page/game.dart').readAsStringSync();
    final start = source.indexOf("'对战玩法规则'");
    final end = source.indexOf('我知道了');
    expect(start, greaterThan(0), reason: '找不到规则弹窗标题');
    expect(end, greaterThan(start), reason: '找不到规则弹窗的关闭按钮');
    return source.substring(start, end);
  }

  group('PK 大厅玩法规则文案', () {
    test('不得再出现旧版俄罗斯方块的玩法措辞', () {
      final rules = rulesSection();
      for (final obsolete in ['下落答题', '方块', '堆叠', '顶起', '＋', '－']) {
        expect(rules, isNot(contains(obsolete)),
            reason: '规则里还留着旧玩法措辞：$obsolete');
      }
    });

    test('道具与生命规则必须与实现口径一致', () {
      final rules = rulesSection();
      // 连对 3 题必掉 1 个（服务端 correctCount % 3），水雷/海星各 50%
      expect(rules, contains('海星'));
      expect(rules, contains('水雷'));
      expect(rules, contains('连续答对 3 题'));
      // 10 格生命（maxHp）
      expect(rules, contains('10 格生命'));
    });
  });
}
