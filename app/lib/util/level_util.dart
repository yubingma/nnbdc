import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';

class Level {
  final String name;
  final String icon;
  final List<String> quotes;
  final Color color;
  final int level;
  final int minScore;
  final int maxScore;
  final String style;

  const Level({
    required this.name,
    required this.icon,
    required this.quotes,
    required this.color,
    required this.level,
    required this.minScore,
    required this.maxScore,
    this.style = "",
  });
}

class LevelUtil {
  static List<Level> get allLevels => _levels;

  static const List<Level> _levels = [
    Level(
      name: '毛毛虫',
      icon: '🐛',
      quotes: [
        '我是一条向往天空的虫。',
        '现在慢一点，是为了以后飞得高一点。',
        '我梦见自己变成了美丽的蝴蝶。',
        '世界很大，我先从一小步开始。',
        '别催我，变化正在悄悄发生。',
      ],
      color: Color(0xFF81C784),
      level: 0,
      minScore: 0,
      maxScore: 50,
      style: "color:gray;",
    ),
    Level(
      name: '皮皮虾',
      icon: '🦐',
      quotes: [
        '先别想着厉害，能多蹦几下就行。',
        '别看我小，我蹦得还挺勤。',
        '每天进步一点点，也算在发力。',
        '别管姿势对不对，先动起来。',
        '蹦就对了，踩空算惊喜。',
      ],
      color: Color(0xFFFF8A65),
      level: 1,
      minScore: 51,
      maxScore: 200,
      style: "color:black;",
    ),
    Level(
      name: '仓鼠',
      icon: '🐹',
      quotes: [
        '日积月累，我要做个小胖子。',
        '一颗一颗往腮帮里塞，总会满的。',
        '今天又存了一点点。',
        '别看我小，我的库存很惊人。',
        '慢慢囤，迟早用得上。',
      ],
      color: Color(0xFFFFD54F),
      level: 2,
      minScore: 201,
      maxScore: 800,
      style: "color:darkcyan;",
    ),
    Level(
      name: '章鱼',
      icon: '🐙',
      quotes: [
        '这个词有点多义？尽在掌握!',
        '放心，我还有手没用完。',
        '复杂的东西，我会拆开来理解。',
        '我习惯同时抓住重点。',
        '看起来乱，其实都在我脑子里。',
      ],
      color: Color(0xFFBA68C8),
      level: 3,
      minScore: 801,
      maxScore: 2000,
      style: "color:blue;",
    ),
    Level(
      name: '树懒',
      icon: '🦥',
      quotes: [
        '慢一点也没关系，我本来就不是靠冲刺的。',
        '只要没停下，就不算慢。',
        '慢慢来，反而更稳。',
        '今天不多，但我每天都在。',
        '我不赶时间，时间会帮我。',
      ],
      color: Color(0xFF9575CD),
      level: 4,
      minScore: 2001,
      maxScore: 4000,
      style: "color:coral;",
    ),
    Level(
      name: '浣熊',
      icon: '🦝',
      quotes: [
        '也别太努力, 否则会有黑眼圈。',
        '我只是看起来在摸鱼，其实没掉队。',
        '我不是偷懒，我是在续航。',
        '先歇会儿，脑子也需要缓冲。',
        '人生是长跑，不是爆肝赛。',
      ],
      color: Color(0xFF90A4AE),
      level: 5,
      minScore: 4001,
      maxScore: 8000,
      style: "color:darkgoldenrod;",
    ),
    Level(
      name: '河狸',
      icon: '🦫',
      quotes: [
        '每天修一点，突然发现我的小房子就要修好了。',
        '我擅长把大工程拆成小任务。',
        '今天也为系统添了一块木头。',
        '结构对了，后面就快了。',
        '成果，是堆出来的。',
      ],
      color: Color(0xFFA1887F),
      level: 6,
      minScore: 8001,
      maxScore: 15000,
      style: "color:darkmagenta;",
    ),
    Level(
      name: '鲨鱼',
      icon: '🦈',
      quotes: [
        '一旦进入状态，我是不会轻易停下来的。',
        '目标在前，我只管向前。',
        '我不回头，也不减速。',
        '犹豫会减速，行动才是力量。',
        '在深海里，专注就是一切。',
      ],
      color: Color(0xFF64B5F6),
      level: 7,
      minScore: 15001,
      maxScore: 25000,
      style: "color:midnightblue;",
    ),
    Level(
      name: '长颈鹿',
      icon: '🦒',
      quotes: [
        '为了成为看得最远的动物, 我努力了千万年。',
        '脖子长了，看的东西自然不一样。',
        '看得远一点，走路就不容易撞墙。',
        '有些答案，要等视野打开才会出现。',
        '高处的树叶，总是更好吃。',
      ],
      color: Color(0xFFFFB74D),
      level: 8,
      minScore: 25001,
      maxScore: 40000,
      style: "color:peru;",
    ),
    Level(
      name: '虎鲸',
      icon: '🐋',
      quotes: [
        '我不靠蛮力取胜。',
        '力量有了方向，事情就简单了。',
        '真正的强者，懂得选择战场。',
        '我用策略，节省能量。',
        '安静，但致命。',
      ],
      color: Color(0xFF455A64),
      level: 9,
      minScore: 40001,
      maxScore: 60000,
      style: "color:purple;",
    ),
    Level(
      name: '蓝鲸',
      icon: '🐳',
      quotes: [
        '世界很大, 我要去看看。',
        '我已经不急着证明什么了。',
        '深度，来自长期的积累。',
        '我在自己的节奏里，探索世界。',
        '越深的地方，越安静。',
      ],
      color: Color(0xFF4DB6AC),
      level: 10,
      minScore: 60001,
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
    Level levelObj = getTitle(level);
    if (levelObj.quotes.isEmpty) {
      return "";
    }
    // 随机选择一个台词
    Random random = Random();
    int randomIndex = random.nextInt(levelObj.quotes.length);
    return levelObj.quotes[randomIndex];
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