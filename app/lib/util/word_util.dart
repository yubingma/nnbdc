import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:nnbdc/util/phoneme_util.dart';
import 'package:nnbdc/global.dart';
import '../api/vo.dart';

/// 自定义 TextEditingController，实现单个字符的实时颜色反馈
class SpellingTextEditingController extends TextEditingController {
  final String? Function() getTargetSpell;
  final Color baseColor;

  SpellingTextEditingController(
      {required this.getTargetSpell, required this.baseColor});

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    return buildSpellingTextSpan(
        text, getTargetSpell() ?? "", baseColor, style);
  }

  /// 静态方法：生成带实时颜色反馈的 TextSpan
  static TextSpan buildSpellingTextSpan(
      String input, String target, Color baseColor, TextStyle? style) {
    final List<TextSpan> children = [];

    for (int i = 0; i < input.length; i++) {
      Color charColor = baseColor;
      if (i < target.length) {
        // 比较单个字符，忽略大小写
        if (input[i].toLowerCase() != target[i].toLowerCase()) {
          charColor = Colors.red;
        }
      } else {
        // 超出目标长度的部分显示红色
        charColor = Colors.red;
      }

      children.add(TextSpan(
        text: input.substring(i, i + 1),
        style: style?.copyWith(color: charColor),
      ));
    }

    return TextSpan(style: style, children: children);
  }
}

class WordWrapper {
  /// 实际的单词相关对象，比如MasteredWord, LearningWord ...
  dynamic tag;

  /// tag中的Word对象
  WordVo word;

  FocusNode? _focusNode;
  FocusNode get focusNode => _focusNode ??= FocusNode();

  /// 默写英文输入框
  TextEditingController? _spellController;
  TextEditingController get spellController => _spellController ??= SpellingTextEditingController(
    getTargetSpell: () => word.spell,
    baseColor: const Color(0xFF0097A7),
  );

  /// 提示字符数量
  int hintLetterCount = 0;

  /// 正确答案是否是系统自动提供的（而不是用户提供的）
  bool isAnswerProvidedBySystem = false;

  /// asr匹配上的释义项子项(一个词性下，被分号分开的多个部分，称为子项)，一个子项由两个坐标确定：（释义项索引，子项索引）
  List<Pair<int, int>> asrMatchedMeaningItemParts = [];

  /// 仅因为单词通过而在UI上自动呈现出的未匹配释义项（以便做颜色区分）
  List<Pair<int, int>> asrRevealedMeaningItemParts = [];

  /// 释义子项的拼音缓存，避免高频打字/手写匹配时重复解析拼音
  final Map<String, List<List<PinyinParser>>> targetPinyinsCache = {};

  /// 说中文 的学习模式下，用户是否已经答出了单词的所有意思
  bool answeredAllMeanings = false;

  /// 是否在“背英文”模式下已经答对（用于揭示英文拼写）
  bool speakEnglishPassed = false;

  /// 初始学习状态（进入词表时的状态）
  bool? initialLearningStatus;

  /// 当前学习状态（UI 展现的状态）
  bool? currentLearningStatus;

  /// 发音评分（背英文/翻译例句模式）
  int? pronunciationScore;

  /// 在“隐藏答案”模式下，答案是否已展示
  bool isAnswerRevealed = false;

  /// 在“翻译例句”模式下当前随机抽中的例句
  SentenceVo? currentSentence;

  /// 在“翻译例句”模式下是否已答对
  bool sentenceTranslatedPassed = false;

  /// 在“翻译例句”模式下是否由大模型裁判判定通过
  bool isAiEvaluatedPassed = false;

  /// 在“翻译例句”模式下大模型裁判是否正在判定中
  bool isAiEvaluating = false;

  /// 大模型裁判认可的用户回答（例如词库为"薪水"，用户回答"工资"被 AI 认可）
  String? aiApprovedAnswer;

  /// 最近一次的语音识别结果（用于展示）
  String? lastAsrResult;

  /// 缓存进度信息，用于 UI 展示
  double? currentProgress;
  double? maxProgress;

  WordWrapper(this.word, this.tag);
  
  /// 标记所有释义项为已被 AI 认可并全部匹配
  void markAllMeaningsAsAiMatched({String? approvedAnswer}) {
    isAiEvaluatedPassed = true;
    aiApprovedAnswer = approvedAnswer;
    answeredAllMeanings = true;
    var meaningItems = word.getMergedMeaningItems();
    for (var i = 0; i < meaningItems.length; i++) {
      var meaningItem = meaningItems[i];
      if (meaningItem.meaning == null) continue;
      var parts = splitMeaning2Parts(meaningItem.meaning!);
      for (var j = 0; j < parts.length; j++) {
        var pair = Pair(i, j);
        if (!asrMatchedMeaningItemParts.contains(pair)) {
          asrMatchedMeaningItemParts.add(pair);
        }
      }
    }
  }
  
  /// 揭示所有尚未匹配的释义项（标记为自动展现）
  void revealAllRemainingMeanings() {
    var meaningItems = word.getMergedMeaningItems();
    for (var i = 0; i < meaningItems.length; i++) {
      var meaningItem = meaningItems[i];
      if (meaningItem.meaning == null) continue;
      var parts = splitMeaning2Parts(meaningItem.meaning!);
      for (var j = 0; j < parts.length; j++) {
        var pair = Pair(i, j);
        if (!asrMatchedMeaningItemParts.contains(pair)) {
          if (!asrRevealedMeaningItemParts.contains(pair)) {
            asrRevealedMeaningItemParts.add(pair);
          }
        }
      }
    }
  }

  WordWrapper clone() {
    return WordWrapper(word, tag)
      ..hintLetterCount = hintLetterCount
      ..isAnswerProvidedBySystem = isAnswerProvidedBySystem
      ..asrMatchedMeaningItemParts = List.from(asrMatchedMeaningItemParts)
      ..asrRevealedMeaningItemParts = List.from(asrRevealedMeaningItemParts)
      ..targetPinyinsCache.addAll(targetPinyinsCache)
      ..answeredAllMeanings = answeredAllMeanings
      ..speakEnglishPassed = speakEnglishPassed
      ..initialLearningStatus = initialLearningStatus
      ..currentLearningStatus = currentLearningStatus
      ..pronunciationScore = pronunciationScore
      ..isAnswerRevealed = isAnswerRevealed
      ..currentSentence = currentSentence
      ..sentenceTranslatedPassed = sentenceTranslatedPassed
      ..isAiEvaluatedPassed = isAiEvaluatedPassed
      ..isAiEvaluating = isAiEvaluating
      ..aiApprovedAnswer = aiApprovedAnswer
      ..lastAsrResult = lastAsrResult
      ..currentProgress = currentProgress
      ..maxProgress = maxProgress;
  }

  /// 释放资源
  void dispose() {
    _focusNode?.dispose();
    _spellController?.dispose();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordWrapper &&
          runtimeType == other.runtimeType &&
          word.id == other.word.id &&
          asrMatchedMeaningItemParts.length == other.asrMatchedMeaningItemParts.length &&
          asrRevealedMeaningItemParts.length == other.asrRevealedMeaningItemParts.length;

  @override
  int get hashCode => word.id.hashCode;
}

/// 把释义项拆分为子项, 并排除为空的情况
List<String> splitMeaning2Parts(String meaning) {
  var parts = meaning.split(RegExp(r"[;；]"));
  return parts.where((part) => part.isNotEmpty).toList();
}

/// 在单词的所有释义项子项，以及给定的中文内容(或多候选列表)之间进行匹配，返回释义项子项总数量/匹配上的释义项子项数量/本次新增匹配数量
MeaningMatchResult matchInputChineseWithMeaningItems(
    WordWrapper wordWrapper, Object asrInput) {
  var count = 0; // 所有释义项子项数量
  var newMatchCount = 0; //本次匹配新匹配上的释义项数量
  var meaningItems = wordWrapper.word.getMergedMeaningItems();

  // 统一转为列表处理
  final List<String> inputs =
      asrInput is List<String> ? asrInput : [asrInput.toString()];

  Global.logger.d('🔍 [ASR-Match] 开始中文匹配。word: ${wordWrapper.word.spell}');
  Global.logger.d('🔍 [ASR-Match] 所有候选词列表 inputs: $inputs');

  for (var i = 0; i < meaningItems.length; i++) {
    // 每个元素对应一个词性
    var meaningItem = meaningItems[i];
    var parts = splitMeaning2Parts(meaningItem.meaning!);
    for (var j = 0; j < parts.length; j++) {
      final part = parts[j];
      // 背中文学习模式：如果子项整体被括号包裹（如"[ ... ]"或"（ ... ）"），忽略之
      if (_isWholeBracketed(part)) {
        continue;
      }
      count++;
      if (!wordWrapper.asrMatchedMeaningItemParts.contains(Pair(i, j))) {
        // 只要任一候选匹配上，就认为该释义项被答对
        bool isMatched = false;
        String? matchedInput;
        for (final input in inputs) {
          if (fuzzyChineseContains(input, part, targetPinyinsCache: wordWrapper.targetPinyinsCache)) {
            isMatched = true;
            matchedInput = input;
            break;
          }
        }

        if (isMatched) {
          newMatchCount++;
          wordWrapper.asrMatchedMeaningItemParts.add(Pair(i, j));
          Global.logger.d('✅ [ASR-Match] 成功匹配！释义项子项 part: "$part"，匹配上的候选词 input: "$matchedInput"');
        } else {
          Global.logger.d('❌ [ASR-Match] 无法匹配。释义项子项 part: "$part" 与所有候选词 inputs 均不匹配');
        }
      } else {
        Global.logger.d('ℹ️ [ASR-Match] 释义项子项 part: "$part" 之前已匹配，跳过');
      }
    }
  }
  Global.logger.d('📊 [ASR-Match] 匹配结束。newMatchCount: $newMatchCount, matchedCount: ${wordWrapper.asrMatchedMeaningItemParts.length}/$count');
  return MeaningMatchResult(
    totalCount: count,
    matchedCount: wordWrapper.asrMatchedMeaningItemParts.length,
    newMatchCount: newMatchCount,
  );
}

/// 判断一个释义子项是否"整体被括号包裹"，用于在背中文模式下忽略
bool _isWholeBracketed(String s) {
  final t = s.trim();
  // 支持中文/英文括号与方括号：(), （）, []
  // 注意这里只判断“整体被包裹”，中间内容不做任何删除
  final patterns = <RegExp>[
    RegExp(r'^\(.*\)$'),
    RegExp(r'^（.*）$'),
    RegExp(r'^\[.*\]$'),
  ];
  for (final p in patterns) {
    if (p.hasMatch(t)) return true;
  }
  return false;
}

List<Widget> renderAsrMeaningItems(WordWrapper word,
    {bool isDarkMode = false}) {
  List<Widget> items = [];

  // 如果是由大模型裁判认可的回答，在顶部展示 AI 认可回显气泡
  if (word.aiApprovedAnswer != null && word.aiApprovedAnswer!.isNotEmpty) {
    items.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
              ),
              const SizedBox(width: 4.5),
              Text(
                'AI 认可释义: "${word.aiApprovedAnswer}"',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MeaningItemVo> meaningItems = word.word.getMergedMeaningItems();
  for (var i = 0; i < meaningItems.length; i++) {
    var meaningItem = meaningItems[i];
    items.add(Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        if ((meaningItem.ciXing ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              meaningItem.ciXing!,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF374151), // 与标准释义颜色一致
                fontWeight: FontWeight.w400, // 从 w600 改为 w400
              ),
            ),
          ),
        ...renderMeaningItemParts(meaningItem.meaning!, i, word.hintLetterCount,
            word.asrMatchedMeaningItemParts, word.asrRevealedMeaningItemParts,
            isDarkMode: isDarkMode),
      ],
    ));
  }
  return items;
}

/// 渲染一个释义项的子项
List<Widget> renderMeaningItemParts(
    String meaning,
    int meaningIndex,
    int hintLetterCount,
    List<Pair<int, int>> asrMatchedMeaningItemParts,
    List<Pair<int, int>> asrRevealedMeaningItemParts,
    {bool isDarkMode = false}) {
  // 把释义拆分为子项
  var partWidgets = <Widget>[];
  var parts = splitMeaning2Parts(meaning);

  // 渲染每个子项
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i];

    // 释义项已经被用户答对
    if (asrMatchedMeaningItemParts.contains(Pair(meaningIndex, i))) {
      var widget = Text(
        part,
        style: TextStyle(
          color: isDarkMode
              ? const Color(0xFF4ADE80)
              : const Color(0xFF16A34A), // 绿色高亮
          fontSize: 14, // 与英文释义字体大小保持一致
          fontWeight: FontWeight.w400,
        ),
      );
      partWidgets.add(widget);
    }
    // 未被用户直接答对，但由于单词通过而自动展现出来的部分（区别标记为蓝色）
    else if (asrRevealedMeaningItemParts.contains(Pair(meaningIndex, i))) {
      var widget = Text(
        part,
        style: TextStyle(
          color: isDarkMode
              ? Colors.white
              : Colors.black, // 黑色显式呈现
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      );
      partWidgets.add(widget);
    }
    // 释义项尚未被用户答对一会儿没事
    else {
      // 根据"给点提示"的数字，展现相应数量的汉字释义
      var displayText =
          part.replaceAll(RegExp(r"[\u4e00-\u9fa5]"), '^'); // 每个汉字用一个^代替
      for (var j = 0; j < hintLetterCount; j++) {
        int pos = displayText.indexOf("^");
        if (pos != -1) {
          displayText = displayText.replaceFirst('^', part[pos]);
        }
      }

      // 构建最终显示文本，使用固定宽度的容器来确保每个汉字位置占用相同空间
      var finalWidgets = <Widget>[];

      for (int i = 0; i < displayText.length; i++) {
        if (displayText[i] == '^') {
          // 未显示的汉字用固定宽度的占位符
          finalWidgets.add(SizedBox(
            width: 15, // 固定宽度，大约等于一个汉字的宽度
            child: Text(
              '＿',
              style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? Colors.white54 : Colors.black38),
              textAlign: TextAlign.center,
            ),
          ));
        } else {
          // 已显示的汉字或其他字符
          finalWidgets.add(Text(
            displayText[i],
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDarkMode
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF374151)), // 与标准释义颜色一致
          ));
        }
      }

      var widget = Wrap(
        children: finalWidgets,
      );
      partWidgets.add(widget);
    }

    // 显示释义项分隔符
    if (i != parts.length - 1) {
      partWidgets.add(Text(
        "；",
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDarkMode ? Colors.white54 : Colors.black38),
      ));
    }
  }
  return partWidgets;
}

/// 计算输入中文与目标中文句子的匹配得分 (0~100)
int getChineseSentenceMatchScore(String input, String target) {
  String clean(String s) => s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
  // 同音字归一化：她/他/它 (tā)、的/地/得 (de) 发音完全相同，语音识别无法区分
  String normalizeHomophones(String s) => s.split('').map((ch) {
    if (ch == '她' || ch == '它') return '他';
    if (ch == '地' || ch == '得') return '的';
    return ch;
  }).join('');
  final cleanInput = normalizeHomophones(clean(input));
  final cleanTarget = normalizeHomophones(clean(target));
  if (cleanTarget.isEmpty) return 0;

  List<List<int>> dp = List.generate(
      cleanInput.length + 1, (_) => List.filled(cleanTarget.length + 1, 0));
  for (int i = 1; i <= cleanInput.length; i++) {
    for (int j = 1; j <= cleanTarget.length; j++) {
      if (cleanInput[i - 1] == cleanTarget[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  final lcs = dp[cleanInput.length][cleanTarget.length];
  final ratio = lcs / cleanTarget.length;
  return (ratio * 100).round();
}

/// 检查用户的中文识别结果中是否说出了目标词释义（参考背单词页面英中模式的判定逻辑，基于 fuzzyChineseContains 与释义项子项匹配）
bool isChineseSentenceCoreKeywordsMatched(
  Object asrInput,
  String targetChinese,
  WordVo word, {
  Map<String, List<List<PinyinParser>>>? targetPinyinsCache,
}) {
  // 1. 优先检查 targetChinese 中的加粗核心词 <b>...</b>
  final boldRegExp = RegExp(r'<b>(.*?)</b>', caseSensitive: false);
  final boldMatches = boldRegExp.allMatches(targetChinese)
      .map((m) => m.group(1)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  for (final boldWord in boldMatches) {
    if (fuzzyChineseContains(asrInput, boldWord, targetPinyinsCache: targetPinyinsCache)) {
      return true;
    }
  }

  // 2. 参考背单词英中模式：检查是否命中目标单词的任意释义子项
  final meaningItems = word.getMergedMeaningItems();
  for (final meaningItem in meaningItems) {
    if (meaningItem.meaning == null) continue;
    final parts = splitMeaning2Parts(meaningItem.meaning!);
    for (final part in parts) {
      if (_isWholeBracketed(part)) continue;
      if (fuzzyChineseContains(asrInput, part, targetPinyinsCache: targetPinyinsCache)) {
        return true;
      }
    }
  }

  // 如果目标句无 <b> 加粗且单词无释义项，默认视为通过
  if (boldMatches.isEmpty && meaningItems.isEmpty) {
    return true;
  }

  return false;
}

/// 检查用户的英文识别结果中是否说出了目标核心词（加粗部分 <b>...</b> 或单词本身拼写）
Future<bool> isEnglishSentenceCoreKeywordsMatched(
  String input,
  String targetEnglish,
  WordVo word,
) async {
  List<String> getWords(String s) {
    return s
        .toLowerCase()
        .split(RegExp(r"[^a-zA-Z\d\u0027]"))
        .where((w) => w.isNotEmpty && (w == 'a' || w == 'i' || (w != "'s" && w != "s" && w.length > 1)))
        .toList();
  }

  final inputWords = getWords(input);
  if (inputWords.isEmpty) return false;

  // 1. 优先提取加粗核心词 <b>...</b>
  final boldRegExp = RegExp(r'<b>(.*?)</b>', caseSensitive: false);
  final boldMatches = boldRegExp
      .allMatches(targetEnglish)
      .map((m) => m.group(1)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  final List<String> coreTargetWords = [];
  if (boldMatches.isNotEmpty) {
    for (final bold in boldMatches) {
      coreTargetWords.addAll(getWords(bold));
    }
  } else {
    coreTargetWords.addAll(getWords(word.spell));
  }

  if (coreTargetWords.isEmpty) return true;

  // 目标中的核心词必须在用户的输入中有字面一致或音素相似（>=75）的对应词
  for (final targetCore in coreTargetWords) {
    bool matched = false;
    for (final inputWord in inputWords) {
      if (inputWord == targetCore) {
        matched = true;
        break;
      }
      final sim = await PhonemeUtil.similarity(inputWord, targetCore);
      if (sim >= 75) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }

  return true;
}

