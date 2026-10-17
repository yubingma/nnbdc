// 用户宠物的台词库。
//
// 设计原则（用户明确要求）：
//   台词不是卖萌，而是**解释宠物的逻辑**——它一天吃几颗智慧果、背篓里的数量
//   为什么是现在这个数、什么情况下它会开心、什么情况下会委屈。
//   所以每一句都要能让用户读懂「它现在为什么是这个样子」。
//
// 按四态分组，与首页 `_petAssetPath` 的选择完全一致：
//   sleepy  → 今天还没开始（背篓 1 颗）
//   happy   → 已经开始学习（背篓 2 颗）
//   excited → 已完成打卡（袋里 2 颗 + 嘴边 1 颗）
//   sad     → 断更（空篓，只剩拣来的菜叶）
//
// 抽台词时避开"上一句"，见 [PetSpeech.pick]。

/// 宠物的四种状态，与首页选图一一对应。
enum PetMood { sleepy, happy, excited, sad }

class PetSpeech {
  PetSpeech._();

  /// 第一次点它时说的那句：先把「我是谁、我吃什么」讲清楚。
  static const String firstMeet = '我一天吃两颗智慧果。你背单词，我才有得吃——所以咱俩是一条船上的。';

  /// 各状态的台词：先把逻辑讲明白，但用玩笑和温话讲，别像说明书。
  static const Map<PetMood, List<String>> _lines = {
    PetMood.sleepy: [
      '就剩一颗了，省着点吃。你一开始学，我就能再得一颗。',
      '别看我闭着眼，我在算今天的账：这一颗够撑到晚饭。',
      '这颗是昨天的剩货，不新鲜了。要不……开始学？',
      '我一天的配额是两颗，现在只有一颗。差的那颗，在你手里。',
      '你不动，我不动，咱俩就这么耗着？',
    ],
    PetMood.happy: [
      '两颗到手，今天饿不着了。',
      '你多背一个词，我就能多嚼一口。',
      '我一天就吃两颗，多的不要——留给你明天表现用。',
      '看在我这两颗的份上，今天尽量别断更哈。',
      '说实话吧，我就是来蹭你背单词的。',
    ],
    PetMood.excited: [
      '学完了！袋里两颗归我，嘴边这颗算奖励。',
      '吃掉一颗，剩一颗过夜——明天醒来又是一颗。我这日子规划得挺明白。',
      '今天没饿肚子，心情不错。',
      '你要是断更，我可就得吃菜叶了。别让我吃菜叶。',
      '明天也来啊，我胃口好着呢。',
    ],
    PetMood.sad: [
      '菜叶。又是菜叶。你说说，这合理吗？',
      '我不是生气，我就是饿。',
      '果子断供了，背篓比我的心情还空。',
      '你回来学一下，我就能重新长果子——不骗你。',
      '饿了好几天，但我没跑。你说我是不是有点傻。',
    ],
  };

  /// 随机抽一句解释型台词。
  ///
  /// [lastIndex] 是上一次抽到的下标：同一状态下不连着说同一句
  /// （两句备选时会自动换到另一句，而不是让人听两遍）。
  static ({String text, int index}) pick(PetMood mood, {int? lastIndex}) {
    final lines = _lines[mood] ?? const <String>[];
    if (lines.isEmpty) return (text: firstMeet, index: 0);
    if (lines.length == 1) return (text: lines.first, index: 0);

    var index = DateTime.now().microsecondsSinceEpoch % lines.length;
    if (lastIndex != null && index == lastIndex) {
      index = (index + 1) % lines.length;
    }
    return (text: lines[index], index: index);
  }
}
