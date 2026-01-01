import 'package:flutter/material.dart';

class AnimalTitle {
  final String name;
  final String icon;
  final String quote;
  final Color color;

  const AnimalTitle(this.name, this.icon, this.quote, this.color);
}

class LevelUtil {
  static const List<AnimalTitle> _titles = [
    AnimalTitle('水熊虫', '🐛', '别看我小，我很顽强。', Color(0xFF81C784)),
    AnimalTitle('皮皮虾', '🦐', '先别想着厉害，能多蹦几下就行。', Color(0xFFFF8A65)),
    AnimalTitle('仓鼠', '🐹', '日积月累，我要做个小胖子。', Color(0xFFFFD54F)),
    AnimalTitle('浣熊', '🦝', '也别太努力, 否则会有黑眼圈。', Color(0xFF90A4AE)),
    AnimalTitle('章鱼', '🐙', '这个词有点多义？尽在掌握!', Color(0xFFBA68C8)),
    AnimalTitle('树懒', '🦥', '慢一点也没关系，我本来就不是靠冲刺的。', Color(0xFF9575CD)),
    AnimalTitle('河狸', '🦫', '每天修一点，突然发现我的小房子就要修好了。', Color(0xFFA1887F)),
    AnimalTitle('鲨鱼', '🦈', '一旦进入状态，我是不会轻易停下来的。', Color(0xFF64B5F6)),
    AnimalTitle('长颈鹿', '🦒', '为了成为看得最远的动物, 我努力了千万年。', Color(0xFFFFB74D)),
    AnimalTitle('抹香鲸', '🐳', '世界很大, 我要去看看', Color(0xFF4DB6AC)),
  ];

  static AnimalTitle getTitle(int level) {
    // 假设 level 从 1 开始
    if (level <= 0) return _titles[0];
    if (level > _titles.length) return _titles.last;
    return _titles[level - 1];
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
}
