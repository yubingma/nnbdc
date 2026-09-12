import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';

class Level {
  final String name;
  final String icon;
  final List<String> quotes;
  final Color color;
  final int level;
  final int minWords;
  final int maxWords;
  final String style;

  const Level({
    required this.name,
    required this.icon,
    required this.quotes,
    required this.color,
    required this.level,
    required this.minWords,
    required this.maxWords,
    this.style = "",
  });
}

class LevelUtil {
  /// 每个段位内可点亮的星数。点亮满星后走完最后一段即晋升下一段位
  static const int starsPerLevel = 5;

  static List<Level> get allLevels => _levels;

  /// 段位阶梯按真实用户词量分布校准: 前密后疏, 0-650 词即含 9 个段位,
  /// 顶端封顶在 10000 词 (覆盖 GRE 量级), 避免出现永远够不到的段位.
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
      minWords: 0,
      maxWords: 7,
      style: "color:gray;",
    ),
    Level(
      name: '蜗牛',
      icon: '🐌',
      quotes: [
        '慢，但我从没停过。',
        '我把家背在背上，走到哪算哪。',
        '别人跑一天，我走十天，也到了。',
        '壳重一点没关系，那是我自己攒的。',
        '不看终点，只吃眼前这片叶子。',
      ],
      color: Color(0xFFAED581),
      level: 1,
      minWords: 8,
      maxWords: 19,
      style: "color:darkolivegreen;",
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
      level: 2,
      minWords: 20,
      maxWords: 44,
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
      level: 3,
      minWords: 45,
      maxWords: 79,
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
      level: 4,
      minWords: 80,
      maxWords: 129,
      style: "color:blue;",
    ),
    Level(
      name: '乌龟',
      icon: '🐢',
      quotes: [
        '稳，是我的超能力。',
        '我不跟兔子比速度，我跟自己比耐力。',
        '缩进壳里休息，不代表我认输。',
        '路很长，但我走得也久。',
        '一步一个脚印，脚印多了就是路。',
      ],
      color: Color(0xFF4DB6AC),
      level: 5,
      minWords: 130,
      maxWords: 199,
      style: "color:seagreen;",
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
      level: 6,
      minWords: 200,
      maxWords: 299,
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
      level: 7,
      minWords: 300,
      maxWords: 449,
      style: "color:darkgoldenrod;",
    ),
    Level(
      name: '河狸',
      icon: '🦫',
      quotes: [
        '每天修一点，突然发现我的小水坝就快修好了。',
        '我擅长把大工程拆成小任务。',
        '今天也为系统添了一块木头。',
        '结构对了，后面就快了。',
        '成果，是堆出来的。',
      ],
      color: Color(0xFFA1887F),
      level: 8,
      minWords: 450,
      maxWords: 649,
      style: "color:darkmagenta;",
    ),
    Level(
      name: '兔子',
      icon: '🐰',
      quotes: [
        '耳朵竖起来，机会才跑不掉。',
        '跳得高不算本事，跳得准才算。',
        '我跑得快，但我也知道停下来吃草。',
        '警惕四周，也别忘了向前。',
        '今天多蹦两级台阶。',
      ],
      color: Color(0xFFF06292),
      level: 9,
      minWords: 650,
      maxWords: 899,
      style: "color:sienna;",
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
      level: 10,
      minWords: 900,
      maxWords: 1249,
      style: "color:midnightblue;",
    ),
    Level(
      name: '狐狸',
      icon: '🦊',
      quotes: [
        '聪明不是捷径，是少走弯路。',
        '我闻得到答案的方向。',
        '狡猾一点，是对困难的尊重。',
        '换条路走，也是一样的抵达。',
        '眼睛亮着，脑子就没停过。',
      ],
      color: Color(0xFFFF8A3D),
      level: 11,
      minWords: 1250,
      maxWords: 1699,
      style: "color:orangered;",
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
      level: 12,
      minWords: 1700,
      maxWords: 2299,
      style: "color:peru;",
    ),
    Level(
      name: '狼',
      icon: '🐺',
      quotes: [
        '一个人也能跑，一群人才叫远征。',
        '我盯着目标，不盯着别人的速度。',
        '夜里出发，天亮了就到。',
        '忍耐是狼的第二种牙齿。',
        '风往哪吹，我就往哪追。',
      ],
      color: Color(0xFF78909C),
      level: 13,
      minWords: 2300,
      maxWords: 3199,
      style: "color:dimgray;",
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
      level: 14,
      minWords: 3200,
      maxWords: 4499,
      style: "color:purple;",
    ),
    Level(
      name: '鹰',
      icon: '🦅',
      quotes: [
        '站得高，是因为我摔过很多次。',
        '风越大，我飞得越省力。',
        '我看得远，所以我不慌。',
        '收起翅膀是休息，不是放弃。',
        '从高空看，难题都很小。',
      ],
      color: Color(0xFF8D6E63),
      level: 15,
      minWords: 4500,
      maxWords: 6499,
      style: "color:teal;",
    ),
    Level(
      name: '蓝鲸',
      icon: '🐳',
      quotes: [
        '世界很大, 我想去看看。',
        '我已经不急着证明什么了。',
        '深度，来自长期的积累。',
        '我在自己的节奏里，探索世界。',
        '越深的地方，越安静。',
      ],
      color: Color(0xFF42A5F5),
      level: 16,
      minWords: 6500,
      maxWords: 9999,
      style: "color:rosybrown;",
    ),
    Level(
      name: '龙',
      icon: '🐉',
      quotes: [
        '从一条虫到一条龙，我用了很久。',
        '我不需要证明什么了，我只是在飞。',
        '云层之上，是我习惯的高度。',
        '传说，是一天天熬出来的。',
        '终点不是我的对手，天空才是。',
      ],
      color: Color(0xFFE53935),
      level: 17,
      minWords: 10000,
      maxWords: 99999999,
      style: "color:crimson;",
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

  static Level getLevelByWordCount(int wordCount) {
    for (int i = _levels.length - 1; i >= 0; i--) {
      if (wordCount >= _levels[i].minWords) {
        return _levels[i];
      }
    }
    return _levels[0]; // 默认返回最低等级
  }

  /// 下一段位的入门词数; 已是最高段位时返回 null
  static int? nextLevelMinWords(int level) {
    if (level < 0 || level >= _levels.length - 1) return null;
    return _levels[level + 1].minWords;
  }

  /// 当前段位内已点亮的星数 (1 ~ starsPerLevel)。
  /// 进入段位即为 1 星, 每跨过 1/starsPerLevel 的区间再点亮一颗;
  /// 点亮满星后剩下的最后一段走完即晋升下一段位。
  static int getStarsInLevel(Level level, int wordCount) {
    final nextMin = nextLevelMinWords(level.level);
    if (nextMin == null || nextMin <= level.minWords) return starsPerLevel;
    final progress = (wordCount - level.minWords) / (nextMin - level.minWords);
    return ((progress * starsPerLevel).floor() + 1).clamp(1, starsPerLevel);
  }

  static int getStarsByWordCount(int wordCount) {
    return getStarsInLevel(getLevelByWordCount(wordCount), wordCount);
  }

  /// 星级的文本表达, 如 ★★★☆☆
  static String starsText(int stars) {
    final lit = stars.clamp(0, starsPerLevel);
    return '★' * lit + '☆' * (starsPerLevel - lit);
  }

  static LevelVo getLevelVoByWordCount(int wordCount) {
    Level level = getLevelByWordCount(wordCount);
    LevelVo levelVo = LevelVo(level.level.toString())
      ..level = level.level
      ..name = level.name
      ..figure = level.icon
      ..minScore = level.minWords
      ..maxScore = level.maxWords
      ..style = level.style;
    return levelVo;
  }
}
