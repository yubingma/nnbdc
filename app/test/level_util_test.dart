import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/level_util.dart';

void main() {
  group('LevelUtil 段位阶梯', () {
    test('段位数量与阈值严格递增', () {
      final levels = LevelUtil.allLevels;
      expect(levels.length, 18);
      for (int i = 0; i < levels.length; i++) {
        expect(levels[i].level, i);
        expect(levels[i].minWords, greaterThan(i == 0 ? -1 : levels[i - 1].minWords));
        expect(levels[i].maxWords, greaterThanOrEqualTo(levels[i].minWords));
      }
    });

    test('按词数定位段位', () {
      expect(LevelUtil.getLevelByWordCount(0).name, '毛毛虫');
      expect(LevelUtil.getLevelByWordCount(7).name, '毛毛虫');
      expect(LevelUtil.getLevelByWordCount(8).name, '蜗牛');
      expect(LevelUtil.getLevelByWordCount(120).name, '章鱼');
      expect(LevelUtil.getLevelByWordCount(9999).name, '蓝鲸');
      expect(LevelUtil.getLevelByWordCount(10000).name, '龙');
      expect(LevelUtil.getLevelByWordCount(999999).name, '龙');
    });

    test('段内星级: 进入即有 1 星, 每跨 1/5 区间点亮一颗', () {
      // 皮皮虾区间 [20, 45), 五等分点为 25 / 30 / 35 / 40
      expect(LevelUtil.getStarsByWordCount(20), 1);
      expect(LevelUtil.getStarsByWordCount(24), 1);
      expect(LevelUtil.getStarsByWordCount(25), 2);
      expect(LevelUtil.getStarsByWordCount(30), 3);
      expect(LevelUtil.getStarsByWordCount(35), 4);
      expect(LevelUtil.getStarsByWordCount(40), 5);
      expect(LevelUtil.getStarsByWordCount(44), 5);
      // 满 45 词即晋升仓鼠, 星数重新从 1 开始
      expect(LevelUtil.getStarsByWordCount(45), 1);
    });

    test('星级文本表达', () {
      expect(LevelUtil.starsText(1), '★☆☆☆☆');
      expect(LevelUtil.starsText(3), '★★★☆☆');
      expect(LevelUtil.starsText(5), '★★★★★');
      // 越界收敛, 不产生畸形字符串
      expect(LevelUtil.starsText(0), '☆☆☆☆☆');
      expect(LevelUtil.starsText(9), '★★★★★');
    });

    test('最高段位视为满星且无下一段', () {
      final dragon = LevelUtil.getLevelByWordCount(10000);
      expect(LevelUtil.nextLevelMinWords(dragon.level), isNull);
      expect(LevelUtil.getStarsInLevel(dragon, 10000), LevelUtil.starsPerLevel);
      expect(LevelUtil.getStarsInLevel(dragon, 999999), LevelUtil.starsPerLevel);
    });

    test('LevelVo 与段位数据一致', () {
      final vo = LevelUtil.getLevelVoByWordCount(500);
      final level = LevelUtil.getLevelByWordCount(500);
      expect(vo.level, level.level);
      expect(vo.name, level.name);
      expect(vo.figure, level.icon);
      expect(vo.minScore, level.minWords);
      expect(vo.maxScore, level.maxWords);
    });
  });
}
