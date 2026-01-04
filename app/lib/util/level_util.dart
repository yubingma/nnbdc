import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';

class Level {
  final String name;
  final String icon;
  final String quote;
  final Color color;
  final int level;
  final int minScore;
  final int maxScore;
  final String style;

  const Level({
    required this.name,
    required this.icon,
    required this.quote,
    required this.color,
    required this.level,
    required this.minScore,
    required this.maxScore,
    this.style = "",
  });
}

class LevelUtil {
  static const List<Level> _levels = [
    Level(
      name: '毛毛虫',
      icon: '🐛',
      quote: '我是一条向往天空的虫。',
      color: Color(0xFF81C784),
      level: 0,
      minScore: 0,
      maxScore: 0,
      style: "color:gray;",
    ),
    Level(
      name: '皮皮虾',
      icon: '🦐',
      quote: '先别想着厉害，能多蹦几下就行。',
      color: Color(0xFFFF8A65),
      level: 1,
      minScore: 1,
      maxScore: 100,
      style: "color:black;",
    ),
    Level(
      name: '仓鼠',
      icon: '🐹',
      quote: '日积月累，我要做个知识小胖子。',
      color: Color(0xFFFFD54F),
      level: 2,
      minScore: 101,
      maxScore: 500,
      style: "color:darkcyan;",
    ),
    Level(
      name: '章鱼',
      icon: '🐙',
      quote: '这个词有点多义？尽在掌握!',
      color: Color(0xFFBA68C8),
      level: 3,
      minScore: 501,
      maxScore: 1200,
      style: "color:blue;",
    ),
    Level(
      name: '树懒',
      icon: '🦥',
      quote: '慢一点也没关系，我本来就不是靠冲刺的。',
      color: Color(0xFF9575CD),
      level: 4,
      minScore: 1201,
      maxScore: 2500,
      style: "color:coral;",
    ),
    Level(
      name: '浣熊',
      icon: '🦝',
      quote: '也别太努力, 否则会有黑眼圈。',
      color: Color(0xFF90A4AE),
      level: 5,
      minScore: 2501,
      maxScore: 5000,
      style: "color:darkgoldenrod;",
    ),
    Level(
      name: '河狸',
      icon: '🦫',
      quote: '每天修一点，突然发现我的小房子就要修好了。',
      color: Color(0xFFA1887F),
      level: 6,
      minScore: 5001,
      maxScore: 10000,
      style: "color:darkmagenta;",
    ),
    Level(
      name: '鲨鱼',
      icon: '🦈',
      quote: '一旦进入状态，我是不会轻易停下来的。',
      color: Color(0xFF64B5F6),
      level: 7,
      minScore: 10001,
      maxScore: 25000,
      style: "color:midnightblue;",
    ),
    Level(
      name: '长颈鹿',
      icon: '🦒',
      quote: '为了成为看得最远的动物, 我努力了千万年。',
      color: Color(0xFFFFB74D),
      level: 8,
      minScore: 25001,
      maxScore: 60000,
      style: "color:peru;",
    ),
    Level(
      name: '虎鲸',
      icon: '🐋',
      quote: '我不靠蛮力取胜。',
      color: Color(0xFF455A64),
      level: 9,
      minScore: 60001,
      maxScore: 150000,
      style: "color:purple;",
    ),
    Level(
      name: '蓝鲸',
      icon: '🐳',
      quote: '世界很大, 我要去看看',
      color: Color(0xFF4DB6AC),
      level: 10,
      minScore: 150001,
      maxScore: 99999999,
      style: "color:rosybrown;",
    ),
  ];

  static Level getTitle(int level) {
    if (level < 0) return _levels[0];
    if (level >= _levels.length) return _levels.last;
    return _levels[level];
  }

  static String getTitleName(int level) {
    return getTitle(level).name;
  }

  static String getTitleIcon(int level) {
    return getTitle(level).icon;
  }

  static String getTitleQuote(int level) {
    return getTitle(level).quote;
  }

  static Color getTitleColor(int level) {
    return getTitle(level).color;
  }

  static Level getLevelByScore(int score) {
    for (int i = _levels.length - 1; i >= 0; i--) {
      if (score >= _levels[i].minScore) {
        return _levels[i];
      }
    }
    return _levels[0]; // 默认返回最低等级
  }

  static LevelVo getLevelVoByScore(int score) {
    Level level = getLevelByScore(score);
    LevelVo levelVo = LevelVo(level.level.toString())
      ..level = level.level
      ..name = level.name
      ..figure = level.icon
      ..minScore = level.minScore
      ..maxScore = level.maxScore
      ..style = level.style;
    return levelVo;
  }
}
