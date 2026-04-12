import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/pinyin.dart';

void main() {
  group('PinyinParser', () {
    test('parses regular pinyin with tone', () {
      var parser = PinyinParser('zhong1');
      expect(parser.shengMu, 'zh');
      expect(parser.yunMu, 'ong');
      expect(parser.tone, 1);
    });

    test('parses pinyin without tone', () {
      var parser = PinyinParser('bai');
      expect(parser.shengMu, 'b');
      expect(parser.yunMu, 'ai');
      expect(parser.tone, 0);
    });

    test('parses double shengmu', () {
      var parser1 = PinyinParser('chuang4');
      expect(parser1.shengMu, 'ch');
      expect(parser1.yunMu, 'uang');
      expect(parser1.tone, 4);

      var parser2 = PinyinParser('shuang3');
      expect(parser2.shengMu, 'sh');
      expect(parser2.yunMu, 'uang');
      expect(parser2.tone, 3);
    });

    test('parses zero shengmu', () {
      var parser1 = PinyinParser('a');
      expect(parser1.shengMu, '');
      expect(parser1.yunMu, 'a');
      expect(parser1.tone, 0);

      var parser2 = PinyinParser('en1');
      expect(parser2.shengMu, '');
      expect(parser2.yunMu, 'en');
      expect(parser2.tone, 1);
    });

    test('parses special zero shengmu (yi, wu, yu)', () {
      var parser1 = PinyinParser('yi1');
      expect(parser1.shengMu, 'y');
      expect(parser1.yunMu, 'i');
      expect(parser1.tone, 1);

      var parser2 = PinyinParser('wu2');
      expect(parser2.shengMu, 'w');
      expect(parser2.yunMu, 'u');
      expect(parser2.tone, 2);

      var parser3 = PinyinParser('yue4');
      expect(parser3.shengMu, 'y');
      expect(parser3.yunMu, 'ue');
      expect(parser3.tone, 4);

      var parser4 = PinyinParser('yuan2');
      expect(parser4.shengMu, 'y');
      expect(parser4.yunMu, 'uan');
      expect(parser4.tone, 2);
    });
  });

  group('Similarity Calculators', () {
    test('shengmu similarity', () {
      expect(similarityOf2ShengMu('b', 'b'), 1.0);
      expect(similarityOf2ShengMu('b', 'p'), 0.85); // checking map logic
      expect(similarityOf2ShengMu('zh', 'ch'), 0.70);
      expect(similarityOf2ShengMu('g', 'k'), 0.85);
      expect(similarityOf2ShengMu('b', 'x'), 0.0); // no entry in map
    });

    test('yunmu similarity', () {
      expect(similarityOf2YunMu('ang', 'ang'), 1.0);
      expect(similarityOf2YunMu('an', 'ang'), 0.75);
      expect(similarityOf2YunMu('in', 'ing'), 0.80);
      expect(similarityOf2YunMu('ui', 'uei'), 0.95);
      expect(similarityOf2YunMu('a', 'o'), 0.0); // no entry in map
    });

    test('tone similarity', () {
      expect(similarityOf2Tone(1, 1), 1.0);
      expect(similarityOf2Tone(1, 2), 0.0);
      expect(similarityOf2Tone(0, 0), 1.0);
    });
  });

  group('Pinyin Similarity', () {
    test('identical pinyin', () {
      expect(similarityOf2Pinyin('zhong1', 'zhong1'), 1.0);
    });

    test('different shengmu, same yunmu and tone', () {
      // zh -> ch (sim: 0.7)
      // weight: 0.4 * 0.7 + 0.5 * 1.0 + 0.1 * 1.0 = 0.28 + 0.5 + 0.1 = 0.88
      expect(similarityOf2Pinyin('zhong1', 'chong1'), closeTo(0.88, 0.001));
    });

    test('different yunmu, same shengmu and tone', () {
      // an -> ang (sim: 0.75)
      // weight: 0.4 * 1.0 + 0.5 * 0.75 + 0.1 * 1.0 = 0.4 + 0.375 + 0.1 = 0.875
      expect(similarityOf2Pinyin('ban1', 'bang1'), closeTo(0.875, 0.001));
    });

    test('different tone', () {
      // weight: 0.4 * 1.0 + 0.5 * 1.0 + 0.1 * 0 = 0.9
      expect(similarityOf2Pinyin('ma1', 'ma2'), closeTo(0.9, 0.001));
    });

    test('both zero shengmu but different yunmu', () {
      // an -> ang (sim: 0.75)
      // Formula: (0.75 * 0.5 + 1.0 * 0.1) / 0.6 = (0.375 + 0.1) / 0.6 = 0.475 / 0.6 = 0.791666...
      expect(similarityOf2Pinyin('an1', 'ang1'), closeTo(0.7917, 0.001));
    });

    test('special "de5" handler', () {
      expect(similarityOf2Pinyin('de5', 'de5'), 1.0);
    });

    test('empty string handler', () {
      expect(similarityOf2Pinyin('', 'a'), 0.0);
      expect(similarityOf2Pinyin('a', ''), 0.0);
    });
  });

  group('Chinese To Pinyin Utils', () {
    test('hanziToPinyin', () {
      var result = hanziToPinyin('好');
      expect(result.isNotEmpty, true);
      expect(result.contains('hao3'), true);
      
      // Special chars
      expect(hanziToPinyin('嗯').contains('en1'), true); // Translated to 恩
    });

    test('chineseToPinyin handles single word', () {
      var pinyins = chineseToPinyin('中国');
      expect(pinyins.isNotEmpty, true);
    });
  });

  group('Fuzzy Chinese Contains', () {
    test('exact match', () {
      expect(fuzzyChineseContains('苹果', '苹果'), true);
    });

    test('substring match', () {
      expect(fuzzyChineseContains('我爱吃苹果', '苹果'), true);
      expect(fuzzyChineseContains('苹果真好吃', '苹果'), true);
    });

    test('ignore non-chinese characters in target', () {
      expect(fuzzyChineseContains('苹果', '水果（苹果）'), false); // Target target is 水果苹果, user said 苹果 -> "苹果" contains "水果苹果"? No, the target is 苹果? Wait. 
      // chinese2 (target meaning) is "水果（苹果）" -> bracket removed -> "水果苹果". user needs to match "水果苹果" which they didn't. 
    });

    test('bracket removal works', () {
      // chinese2 target: "苹果(水果)", parsed as "苹果". If user says "苹果", should match.
      expect(fuzzyChineseContains('苹果', '苹果(水果)'), true);
    });

    test('handles list of candidates', () {
      expect(fuzzyChineseContains(['香蕉', '平果'], '苹果'), true); // '平果' has same pinyin as '苹果'
    });

    test('fuzzy pronunciation match', () {
      // zhong1 guo2 vs chong1 guo2 - highly similar
      expect(fuzzyChineseContains('虫国', '中国'), true);
      // hu jian vs fu jian
      expect(fuzzyChineseContains('胡建', '福建'), true); // h & f: 0.35 shengmu sim. weight: 0.35*0.4 + 1*0.5 + 0*0.1 = 0.14+0.5=0.64. Threshold length<=3 is 0.6. 0.64 is barely true! Wait, hu vs fu tone 2 vs 2 is 1 (0.1). 0.14+0.5+0.1 = 0.74 > 0.6.
    });

    test('does not match completely different words', () {
      expect(fuzzyChineseContains('香蕉', '苹果'), false);
      expect(fuzzyChineseContains('汽车', '自行车'), false);
    });
  });
}
