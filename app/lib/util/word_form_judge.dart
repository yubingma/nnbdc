import 'package:nnbdc/util/phoneme_util.dart';
import 'package:nnbdc/util/word_form.dart';

/// 识别词与目标词的词形关系。
///
/// 判题分两层：先看"是不是同一个词"，再看"发音像不像"。音素分只负责后者，
/// 不能把"同词干的另一个词形"当成"发音不准"放过去。
enum WordFormRelation {
  /// 拼写相同（忽略大小写与标点）。
  same,

  /// 发音完全相同：拼写变体（colour / color）或同音词（right / write）。
  /// 识别层本来就分不出来，判错等于惩罚用户控制不了的事。
  sameSound,

  /// 目标词比识别词多一个纯辅音尾巴（不含元音），属于词尾被吞。
  /// 例如目标 walked、识别 walk；目标 studies、识别 study。
  swallowedTail,

  /// 同一个词干的不同词形：多说词尾、少一个音节、或换成派生词。
  /// 例如目标 walk、识别 walked；目标 nation、识别 national。
  differentForm,

  /// 不同词干，交给音素分与 AI 裁判继续做口音容错。
  unrelated,
}

/// 词形判断：回答"识别词是不是目标词本身"，不回答"发音有多像"。
///
/// 只对两侧都在音素词典里的真实单词做判断。查不到的碎片、拼写错误
/// 一律返回 [WordFormRelation.unrelated]，继续走原有音素分与 AI 裁判，
/// 避免把"识别坏掉的半截词"误判成另一个词形。
class WordFormJudge {
  static final RegExp _nonLetters = RegExp(r'[^a-z]');
  static final RegExp _stressDigit = RegExp(r'\d');

  /// 只包含元音的"尾巴"就是一个音节，不算被吞；纯辅音尾巴才算。
  static const Set<String> _vowelBases = {
    'AA', 'AE', 'AH', 'AO', 'AW', 'AY',
    'EH', 'ER', 'EY', 'IH', 'IY',
    'OW', 'OY', 'UH', 'UW',
  };

  /// 没有共同词尾的不规则屈折。数量很小，单独列出来；
  /// 不补这张表，men / man、mice / mouse 这类会继续靠音素分混过去。
  static const Map<String, String> _irregularGroups = {
    'man': 'man', 'men': 'man',
    'woman': 'woman', 'women': 'woman',
    'child': 'child', 'children': 'child',
    'person': 'person', 'people': 'person',
    'mouse': 'mouse', 'mice': 'mouse',
    'goose': 'goose', 'geese': 'goose',
    'foot': 'foot', 'feet': 'foot',
    'tooth': 'tooth', 'teeth': 'tooth',
    'ox': 'ox', 'oxen': 'ox',
    'go': 'go', 'went': 'go', 'gone': 'go',
    'be': 'be', 'am': 'be', 'is': 'be', 'are': 'be',
    'was': 'be', 'were': 'be', 'been': 'be', 'being': 'be',
    'have': 'have', 'has': 'have', 'had': 'have', 'having': 'have',
    'do': 'do', 'does': 'do', 'did': 'do', 'done': 'do', 'doing': 'do',
    'good': 'good', 'better': 'good', 'best': 'good',
    'bad': 'bad', 'worse': 'bad', 'worst': 'bad',
    'far': 'far', 'farther': 'far', 'farthest': 'far',
    'further': 'far', 'furthest': 'far',
  };

  /// 英式/美式同词异拼（读音相同），音素词典可能给出不一致的元音，单独列出。
  /// 只收"同一个词的不同拼写"，不收 advice / advise 这类读音不同的两个词。
  static const Map<String, String> _spellingVariantGroups = {
    'practice': 'practice', 'practise': 'practice',
    'licence': 'licence', 'license': 'licence',
    'defence': 'defence', 'defense': 'defence',
    'offence': 'offence', 'offense': 'offence',
    'pretence': 'pretence', 'pretense': 'pretence',
  };

  /// 判断 [heard]（识别词）与 [target]（目标词）的词形关系。
  static Future<WordFormRelation> judge(String heard, String target) async {
    final h = _normalize(heard);
    final t = _normalize(target);
    if (h.isEmpty || t.isEmpty) return WordFormRelation.unrelated;
    if (h == t) return WordFormRelation.same;

    final variantGroup = _spellingVariantGroups[h];
    if (variantGroup != null && variantGroup == _spellingVariantGroups[t]) {
      return WordFormRelation.sameSound;
    }

    final heardVariants = await PhonemeUtil.lookup(h);
    final targetVariants = await PhonemeUtil.lookup(t);
    if (heardVariants.isEmpty || targetVariants.isEmpty) {
      return WordFormRelation.unrelated;
    }

    if (_anyVariantEqual(heardVariants, targetVariants)) {
      return WordFormRelation.sameSound;
    }
    if (!_isSameStem(h, t)) {
      return WordFormRelation.unrelated;
    }
    if (_isConsonantTailSwallowed(targetVariants, heardVariants)) {
      return WordFormRelation.swallowedTail;
    }
    return WordFormRelation.differentForm;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_nonLetters, '');

  /// 同一个词干：先用项目已有的屈折变形归并与词族归并，
  /// 再用不规则词形表与长公共前缀补漏。
  static bool _isSameStem(String a, String b) {
    final group = _irregularGroups[a];
    if (group != null && group == _irregularGroups[b]) return true;

    if (isSameWordFamily(a, b)) return true;

    // 拼写变化较大的派生对（success / succeed、product / produce）没有干净的
    // 共同词尾，用"长公共前缀 + 两端残余都很短"补一刀。
    int lcp = 0;
    final max = a.length < b.length ? a.length : b.length;
    while (lcp < max && a.codeUnitAt(lcp) == b.codeUnitAt(lcp)) {
      lcp++;
    }
    final minLcp = max < 4 ? max : 4;
    return lcp >= minLcp && a.length - lcp <= 4 && b.length - lcp <= 4;
  }

  static bool _anyVariantEqual(
    List<List<String>> a,
    List<List<String>> b,
  ) {
    for (final x in a) {
      for (final y in b) {
        if (_listEquals(x, y)) return true;
      }
    }
    return false;
  }

  /// 目标词的音素序列是否以识别词开头，且多出来的尾巴不含元音。
  static bool _isConsonantTailSwallowed(
    List<List<String>> targetVariants,
    List<List<String>> heardVariants,
  ) {
    for (final target in targetVariants) {
      for (final heard in heardVariants) {
        if (target.length <= heard.length) continue;
        bool prefixMatched = true;
        for (int i = 0; i < heard.length; i++) {
          if (target[i] != heard[i]) {
            prefixMatched = false;
            break;
          }
        }
        if (!prefixMatched) continue;
        final tail = target.sublist(heard.length);
        if (!tail.any(_isVowel)) return true;
      }
    }
    return false;
  }

  static bool _isVowel(String phoneme) =>
      _vowelBases.contains(phoneme.replaceAll(_stressDigit, ''));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
