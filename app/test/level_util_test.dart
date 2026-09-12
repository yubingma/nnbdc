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

    test('段内星级: 进入即有 1 星, 满 3 星后晋级', () {
      // 皮皮虾区间 [20, 45), 三等分点为 28.33 / 36.67
      expect(LevelUtil.getStarsByWordCount(20), 1);
      expect(LevelUtil.getStarsByWordCount(28), 1);
      expect(LevelUtil.getStarsByWordCount(29), 2);
      expect(LevelUtil.getStarsByWordCount(36), 2);
      expect(LevelUtil.getStarsByWordCount(37), 3);
      expect(LevelUtil.getStarsByWordCount(44), 3);
      // 满 45 词即晋升仓鼠, 重新从 1 星开始
      expect(LevelUtil.getStarsByWordCount(45), 1);
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
