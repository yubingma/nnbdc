import 'dart:collection';
import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../api/vo.dart';
import '../config.dart';
import '../global.dart';

class Util {
  /// 某些文件命中含有单词拼写（如单词的声音文件，例句声音文件），所以需要对单词的一些特殊字符做处理
  ///
  /// @param spell
  /// @return
  static String uniformSpellForFilename(String spell) {
    spell = spell.replaceAll("?", "").toLowerCase();
    spell = uniformString(spell);
    return spell;
  }

  /// 清除字符串中多余的空格及制表符、回车等
  ///
  /// @return
  static String uniformString(String str) {
    str = str.replaceAll(RegExp(r"\t"), " ");
    str = str.replaceAll(RegExp(r"\n"), " ");
    str = replaceDoubleSpace(str);
    return str.trim();
  }

  static String replaceDoubleSpace(String str) {
    while (str.contains("  ")) {
      str = str.replaceAll(RegExp(r"  "), " ");
    }
    return str;
  }

  /// 获取用户昵称（与后端 Util.getNickNameOfUser 一致的策略）
  static String getNickNameOfUser(UserVo? user) {
    if (user == null) {
      return '';
    }
    var nickName = user.userName ?? '';
    if (user.nickName != null && user.nickName!.trim().isNotEmpty) {
      nickName = user.nickName!.trim();
    }
    return nickName == '系统用户' ? '泡泡' : nickName;
  }

  static String getFileNameOfWordSound(String spell) {
    spell = uniformSpellForFilename(spell);
    if (spell.codeUnitAt(0) >= 'a'.codeUnitAt(0) && spell.codeUnitAt(0) <= 'z'.codeUnitAt(0)) {
      return "${spell[0]}/$spell";
    } else {
      return "other/$spell";
    }
  }

  /// 获取指定单词对应的发音文件Url（
  static String getWordSoundUrl(String spell) {
    return "${Config.soundBaseUrl}${Util.getFileNameOfWordSound(spell)}.mp3";
  }

  /// 获取指定的例句对应的发音文件Url
  static String getSentenceSoundUrl(String englishDigest) {
    return "${Config.soundBaseUrl}sentence/$englishDigest.mp3";
  }

  static bool equalsIgnoreCase(String? string1, String? string2) {
    return string1?.toLowerCase() == string2?.toLowerCase();
  }

  static bool isEnglish(String str) {
    var bytes = utf8.encode(str);
    var i = bytes.length; // i为字节长度
    var j = str.length; // j为字符长度
    return i == j;
  }

  /// 判断指定的char是否是英文字母
  static bool isEnglishLetter(int char) {
    return (char >= "a".codeUnitAt(0) && char <= "z".codeUnitAt(0)) || (char >= "A".codeUnitAt(0) && char <= "Z".codeUnitAt(0));
  }

  static String pureMeaningStr(WordVo word) {
    var meaningStr = word.getMeaningStr();
    meaningStr = meaningStr
        .replaceAll("n.", "")
        .replaceAll("adj.", "")
        .replaceAll("adv.", "")
        .replaceAll("prep.", "")
        .replaceAll("v.", "")
        .replaceAll("vi.", "")
        .replaceAll("vt.", "")
        .replaceAll("num.", "")
        .replaceAll("int.", "")
        .replaceAll("conj.", "")
        .replaceAll("pron.", "")
        .replaceAll("abbr.", "")
        .replaceAll("art.", "")
        .replaceAll("aux.", "")
        .replaceAll("pref.", "")
        .replaceAll("pl.", "")
        .replaceAll("vbl.", "")
        .replaceAll("vt.&vi.", "")
        .replaceAll("n.&vi.", "")
        .replaceAll("aux.v.", "")
        .replaceAll("phr.", "");
    return meaningStr;
  }

  static String pureSentenceChinese(String sentenceChinese) {
    return sentenceChinese.replaceAll("<b>", "").replaceAll("</b>", "");
  }

  static void showFullScreenDialog(BuildContext context, Widget content) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 0),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation,
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              padding: const EdgeInsets.all(0),
              color: Colors.white,
              child: content),
        );
      },
    );
  }

  static String purifySpell(String spell) {
    bool isPhase = spell.trim().contains(" "); // 是否是短语
    if (isPhase) {
      return spell;
    }

    // 如果单词以逗号、句号等结束，首先将这些符号去掉
    while (spell.endsWith(",") || spell.endsWith("?") || spell.endsWith(".") || spell.endsWith("\"") || spell.endsWith(""") ||
        spell.endsWith("'") ||
        spell.endsWith(")") ||
        spell.endsWith(":") ||
        spell.endsWith("!") ||
        spell.endsWith(";")) {
      spell = spell.substring(0, spell.length - 1);
    }

    // 如果单词以引号、括号等开始，首先将这些符号去掉
    while (spell.startsWith("\"") ||
        spell.startsWith(""") || spell.startsWith("'") || spell.startsWith("(")) {
      spell = spell.substring(1, spell.length);
    }

    return spell;
  }

  /// 获取一个单词所有可能的变体形式
  ///
  /// @param spell
  /// @return
  static List<String> getAllPossibleFormsOfWord(String spell) {
    List<String> words = [];
    words.add(spell);
    words.add("${spell}s");
    words.add("${spell}es");
    words.add("$spell's");
    words.add("$spell's");
    if (spell.endsWith("y")) {
      words.add("${spell.substring(0, spell.length - 1)}ies");
    }

    if (spell.endsWith("e")) {
      words.add("${spell}d");
    } else {
      words.add("${spell}ed");
    }

    if (spell.endsWith("e")) {
      words.add("${spell.substring(0, spell.length - 1)}ing");
    } else {
      words.add("${spell}ing");
    }
    return words;
  }

  static double getTextWidth(String text, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.size.width;
  }

  static List<int> getBoldCharIndices(String sentence) {
    List<int> indices = [];
    bool insideBold = false; // 用于标记是否在 <b> 和 </b> 之间
    int plainIdx = 0; // 纯文本中的索引（不包括 HTML 标签）

    int i = 0;
    while (i < sentence.length) {
      String char = sentence[i];

      // 遇到 <b> 标签，开始加粗区域
      if (i + 3 < sentence.length && sentence.substring(i, i + 3) == "<b>") {
        insideBold = true;
        i += 3; // 跳过 <b> 标签
        continue;
      }

      // 遇到 </b> 标签，结束加粗区域
      if (i + 4 < sentence.length && sentence.substring(i, i + 4) == "</b>") {
        insideBold = false;
        i += 4; // 跳过 </b> 标签
        continue;
      }

      // 跳过 HTML 标签
      if (char == "<") {
        while (i < sentence.length && sentence[i] != ">") {
          i++;
        }
        i++; // 跳过 ">"
        continue;
      }

      // 如果在加粗区域，记录纯文本的索引
      if (insideBold) {
        indices.add(plainIdx);
      }

      // 更新纯文本索引（标点符号也算作字符）
      if (char != "<" && char != ">" && char != "/") {
        plainIdx++;
      }

      // 移动到下一个字符
      i++;
    }

    // 去除重复的索引并返回
    return indices.toSet().toList()..sort();
  }

  /// 将英文文本分割成单词和标点符号
  static List<String> splitEnglishText(String text) {
    List<String> tokens = [];
    String currentWord = '';

    for (var i = 0; i < text.length; i++) {
      var char = text[i];
      if (char == ' ') {
        if (currentWord.isNotEmpty) {
          tokens.add(currentWord);
          currentWord = '';
        }
        continue;
      }

      if ('.,!?;:"()[]{}\''.contains(char)) {
        if (currentWord.isNotEmpty) {
          tokens.add(currentWord);
          currentWord = '';
        }
        tokens.add(char);
      } else {
        currentWord += char;
      }
    }

    if (currentWord.isNotEmpty) {
      tokens.add(currentWord);
    }

    return tokens;
  }

  static List<int> getBoldWordIndices(String sentence) {
    // 使用正则表达式匹配 <b> 标签中的内容
    final RegExp boldTagPattern = RegExp(r"<b>(.*?)</b>");
    final Iterable<Match> matches = boldTagPattern.allMatches(sentence);

    // 提取所有 <b> 包裹的短语
    List<String> boldPhrases = matches.map((match) => match.group(1) ?? "").toList();

    // 去掉 HTML 标签
    String plainText = sentence.replaceAll(RegExp(r"<.*?>"), "");

    // 使用分词函数处理文本
    List<String> words = splitEnglishText(plainText);

    // 结果索引列表
    List<int> indices = [];
    int wordCounter = 0;

    // 查找加粗单词的索引
    for (String phrase in boldPhrases) {
      // 使用相同的分词方法处理加粗短语
      List<String> boldWords = splitEnglishText(phrase);
      for (String boldWord in boldWords) {
        while (wordCounter < words.length) {
          if (words[wordCounter] == boldWord) {
            indices.add(wordCounter);
            wordCounter++;
            break;
          }
          wordCounter++;
        }
      }
    }

    return indices;
  }

  /// 把中文句子中的高亮文字(已用html标签加粗)转换为相应的widget，形成一个RichText
  static Widget makeChineseSpanText(String chinese, BuildContext context, {TextStyle? style}) {
    // 根据句子里的html加粗标签，获得高亮文字的下标
    var boldWordIndices = Util.getBoldCharIndices(chinese);

    // 去掉句子中的加粗标签
    chinese = chinese.replaceAll("<b>", "").replaceAll("</b>", "");

    // 迭代句子里的每个字符，为每个字符生成相应的widget
    var parts = chinese.split('');

    final baseStyle = (style ??
            const TextStyle(
              fontSize: 14,
              height: 1.4,
            ))
        .copyWith(
      fontFamily: 'NotoSansSC',
      color: context.watch<DarkMode>().isDarkMode ? Colors.grey[300] : Colors.grey[700],
    );

    return Text.rich(
      TextSpan(children: <InlineSpan>[
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: boldWordIndices.contains(i) ? baseStyle.copyWith(color: Global.highlight) : baseStyle,
          )
      ]),
    );
  }

  /// 把英文句子的每个单词转换为相应的widget，形成一个RichText
  static Text makeEnglishSpanText(String words, String highlightWord, bool highlightWordHasBeenTaged, BuildContext context, bool maskHighlightWord,
      SizedBox? maskTextField, bool isHighlightWordUnClickable, FontWeight fontWeight) {
    words = words.trim();

    // 获得所有高亮(加粗)单词的下标
    var boldWordIndices = []; // 高亮单词的下标
    if (highlightWordHasBeenTaged && words.contains("<b>")) {
      // 根据句子里的html加粗标签，获得高亮单词的下标
      boldWordIndices = Util.getBoldWordIndices(words);

      // 去掉句子中的加粗标签
      words = words.replaceAll("<b>", "").replaceAll("</b>", "");
    } else {
      // 根据单词的拼写，在居中匹配单词，匹配上的单词即为要高亮的单词
      var tokens = splitEnglishText(words);
      for (var i = 0; i < tokens.length; i++) {
        if (!('.,!?;:"()[]{}\''.contains(tokens[i])) && // 不是标点符号
            Util.getAllPossibleFormsOfWord(highlightWord.toLowerCase()).contains(Util.purifySpell(tokens[i].toLowerCase()))) {
          boldWordIndices.add(i);
        }
      }
    }

    // 分词并生成对应的widget
    var tokens = splitEnglishText(words);
    List<InlineSpan> spans = [];

    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      var isPunctuation = '.,!?;:"()[]{}\''.contains(token);

      if (isPunctuation) {
        // 标点符号
        spans.add(TextSpan(
            text: token, style: TextStyle(color: boldWordIndices.contains(i) ? Global.highlight : null, fontSize: 14, fontWeight: fontWeight)));
      } else {
        // 单词
        spans.add(boldWordIndices.contains(i) && maskTextField != null
            ? WidgetSpan(
                child: maskTextField,
              )
            : TextSpan(
                text: boldWordIndices.contains(i) && maskHighlightWord ? ''.padRight(token.length, '_') : token,
                style: TextStyle(color: boldWordIndices.contains(i) ? Global.highlight : null, fontSize: 14, fontWeight: fontWeight),
                recognizer: TapGestureRecognizer()
                  ..onTap = () async {
                    // 高亮单词禁止点击查词
                    if (Util.getAllPossibleFormsOfWord(highlightWord.toLowerCase()).contains(Util.purifySpell(token.toLowerCase())) &&
                        isHighlightWordUnClickable) {
                      return;
                    }

                    // 保存当前context
                    final currentContext = context;

                    // 先尝试本地查询，包括单词的不同变体形式
                    var searchResult = await _searchWordWithVariants(token);

                    // 检查context是否仍然有效
                    if (!currentContext.mounted) return;

                    if (searchResult.word == null) {
                      ToastUtil.info("查不到单词: $token");
                    } else if (searchResult.word != null) {
                      // 播放单词发音
                      SoundUtil.playPronounceSound(searchResult.word!);

                      // 在底部显示单词详情对话框
                      showGeneralDialog(
                        context: currentContext,
                        barrierDismissible: true,
                        barrierLabel: '',
                        transitionDuration: const Duration(milliseconds: 100),
                        transitionBuilder: (context, animation, secondaryAnimation, child) {
                          return FractionalTranslation(
                              translation: Offset(0, 1 - animation.value), // 从底部出现
                              child: child);
                        },
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return Align(
                            alignment: const Alignment(0, 1),
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  maxHeight: 280,
                                  minHeight: 120,
                                ),
                                decoration: BoxDecoration(
                                  color: context.read<DarkMode>().isDarkMode ? const Color(0xff333333) : Colors.white,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, -2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            searchResult.word!.spell,
                                            style: const TextStyle(
                                              color: Global.highlight,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 22,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () {
                                            // 使用持久的 AudioPlayer 实例
                                            SoundUtil.playPronounceSound2(searchResult.word!, SoundUtil.pronouncePlayer);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: context.read<DarkMode>().isDarkMode ? const Color(0xff444444) : const Color(0xfff5f5f5),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '[${Util.getWordDefaultPronounce(searchResult.word!)}]',
                                                  style: TextStyle(
                                                    color: context.read<DarkMode>().isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                                    fontFamily: 'NotoSans',
                                                    fontSize: 14,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.volume_down_rounded,
                                                  size: 20,
                                                  color: context.read<DarkMode>().isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Divider(
                                        height: 1, color: context.read<DarkMode>().isDarkMode ? Colors.grey[700] : Colors.grey[300], thickness: 0.2),
                                    const SizedBox(height: 4),
                                    Flexible(
                                      child: ListView(
                                        shrinkWrap: true,
                                        padding: EdgeInsets.zero,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // 合并同词性释义并去重
                                              for (var meaningItem in Util.mergeMeaningItems(searchResult.word!.meaningItems!))
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 3),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        width: 40,
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                        margin: const EdgeInsets.only(right: 6, top: 1),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(3),
                                                        ),
                                                        child: Text(
                                                          meaningItem.ciXing ?? '',
                                                          style: const TextStyle(
                                                            color: Color(0xFF4A90E2),
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                          textAlign: TextAlign.center,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          meaningItem.meaning!,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            height: 1.2,
                                                            color: context.read<DarkMode>().isDarkMode ? Colors.grey[300] : Colors.black87,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                          maxLines: 2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        searchResult.isInRawWordDict!
                                            ? ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  backgroundColor: Colors.orange,
                                                  minimumSize: const Size(80, 32),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                  textStyle: const TextStyle(fontSize: 14),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                onPressed: () async {
                                                  final dialogContext = context;
                                                  var res = await WordBo().deleteRawWord(searchResult.word!.id!);
                                                  if (!dialogContext.mounted) return;
                                                  if (res.success) {
                                                    ToastUtil.info("移出成功");
                                                  } else {
                                                    ToastUtil.error(res.msg!);
                                                  }
                                                },
                                                child: const Text('移出生词本'),
                                              )
                                            : ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  backgroundColor: Global.highlight,
                                                  minimumSize: const Size(80, 32),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                  textStyle: const TextStyle(fontSize: 14),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                child: const Text('加入生词本'),
                                                onPressed: () async {
                                                  final dialogContext = context;
                                                  var res = await WordBo().addRawWord(searchResult.word!.spell, '手工添加');
                                                  if (!dialogContext.mounted) return;
                                                  if (res.success) {
                                                    ToastUtil.info("添加成功");
                                                  } else {
                                                    ToastUtil.error(res.msg!);
                                                  }
                                                },
                                              ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }
                  }));

        // 在单词后面添加空格（如果不是最后一个token且下一个token不是标点符号）
        if (i < tokens.length - 1 && !('.,!?;:"()[]{}\''.contains(tokens[i + 1]))) {
          spans.add(TextSpan(text: ' '));
        }
      }
    }

    return Text.rich(TextSpan(children: spans));
  }

  static String getWordDefaultPronounce(WordVo word) {
    var pronounce = word.pronounce;
    if (pronounce == null || pronounce.isEmpty) {
      pronounce = word.americaPronounce;
    }
    if (pronounce == null || pronounce.isEmpty) {
      pronounce = word.britishPronounce;
    }
    return pronounce ?? '';
  }

  /// 尝试本地查询单词及其变体形式
  /// 现在只使用本地查词，不再调用后端
  static Future<SearchWordResult> _searchWordWithVariants(String spell) async {
    // 使用本地搜索方法，本地已包含通用词典的所有单词
    return await WordBo().searchWordLocalOnly(spell);
  }

  /// 根据单词的生命值计算下次学习该单词应在多少天之后
  ///
  /// @param lifeValue
  /// @return
  static int calcuNextStudyDayByLifeValue(int lifeValue) {
    var nextDay = 0;
    if (lifeValue == 5) {
      nextDay = 1;
    } else if (lifeValue == 4) {
      nextDay = 2;
    } else if (lifeValue == 3) {
      nextDay = 3;
    } else if (lifeValue == 2) {
      nextDay = 8;
    }
    return nextDay;
  }

  /// 关闭输入法
  static void closeIme() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  static Future<String?> networkImageToBase64(String imageUrl) async {
    http.Response response = await http.get(Uri.parse(imageUrl));
    final bytes = response.bodyBytes;
    return base64Encode(bytes);
  }

  static Color sentenceChineseColor(BuildContext context) {
    return context.read<DarkMode>().isDarkMode ? const Color(0xff888888) : const Color(0xff666666);
  }

  static Color voteColorEnabled(BuildContext context) {
    return context.read<DarkMode>().isDarkMode ? Colors.teal : Colors.teal;
  }

  static Color voteColorDisabled(BuildContext context) {
    return context.read<DarkMode>().isDarkMode ? const Color(0x55888888) : const Color(0x55666666);
  }

  static List<MeaningItemVo> mergeMeaningItems(final List<MeaningItemVo> meaningItems) {
    List<MeaningItemVo> meaningItemVos = [];
    for (MeaningItemVo meaningItemVo in meaningItems) {
      // 尝试查找现有的具有相同词性的释义项
      MeaningItemVo? existingItemWithSameCiXing;
      for (MeaningItemVo itemVo in meaningItemVos) {
        if (itemVo.ciXing == (meaningItemVo.ciXing)) {
          existingItemWithSameCiXing = itemVo;
        }
      }

      if (existingItemWithSameCiXing != null) {
        //融合相同词性的释义项
        LinkedHashSet<String> partsSet = LinkedHashSet();
        List<String> parts = existingItemWithSameCiXing.meaning!.split(RegExp("[;|；]"));
        partsSet.addAll(parts);
        parts = meaningItemVo.meaning!.split(RegExp("[;|；]"));
        partsSet.addAll(parts);
        String sb = "";
        LinkedHashSet<String> addedPartItems = LinkedHashSet(); // 用于去掉重复释义
        for (String part in partsSet) {
          List<String> partItems = part.split(RegExp("[，|,]"));
          List<String> purifiedPartItems = [];
          for (var item in partItems) {
            item = item.trim();
            if (!addedPartItems.contains(item) && item.isNotEmpty) {
              purifiedPartItems.add(item);
            }
          }
          if (purifiedPartItems.isNotEmpty) {
            for (var i = 0; i <= purifiedPartItems.length - 1; i++) {
              var item = purifiedPartItems[i];
              sb += item + (i == purifiedPartItems.length - 1 ? "" : "，");
            }
            sb += "；";
            addedPartItems.addAll(purifiedPartItems);
          }
        }
        if (sb.isNotEmpty) {
          sb = sb.substring(0, sb.length - 1);
        }
        MeaningItemVo mergedItem = MeaningItemVo.from(existingItemWithSameCiXing.ciXing, sb.toString());
        if (existingItemWithSameCiXing.synonyms != null || meaningItemVo.synonyms != null) {
          Set<SynonymVo> synonyms = {};
          if (existingItemWithSameCiXing.synonyms != null) {
            synonyms.addAll(existingItemWithSameCiXing.synonyms!);
          }
          if (meaningItemVo.synonyms != null) {
            synonyms.addAll(meaningItemVo.synonyms!);
          }
          mergedItem.synonyms = List.from(synonyms);
        }
        meaningItemVos.remove(existingItemWithSameCiXing);
        meaningItemVos.add(mergedItem);
      } else {
        // 添加释义项
        meaningItemVos.add(meaningItemVo);
      }
    }
    return meaningItemVos;
  }

  static Future<String> getTempFilePath(fileName) async {
    String path = '';
    Directory dir = await getTemporaryDirectory();
    path = '${dir.path}/$fileName';
    return path;
  }

  /// 生成一个uuid (32位)
  static String uuid() {
    var uuid = Uuid();
    String uuidWithHyphens = uuid.v4();
    String uuid32 = uuidWithHyphens.replaceAll('-', '');
    return uuid32;
  }

  /// 将本地表名转换为服务端表名, 比如 learningWords -> learning_word
  static String localTableNameToRemote(String localTableName) {
    Map<String, String> tableNameMapping = {
      'dakas': 'daka',
      'userStudySteps': 'user_study_step',
      'userOpers': 'user_oper',
      'learningWords': 'learning_word',
      'learningDicts': 'learning_dict',
      'users': 'user',
      'bookMarks': 'book_mark',
      'masteredWords': 'mastered_word',
      'userCowDungLogs': 'user_cow_dung_log',
      'userWrongWords': 'user_wrong_word',
      'dictWords': 'dict_word',
      'dicts': 'dict',
    };

    if (tableNameMapping.containsKey(localTableName)) {
      return tableNameMapping[localTableName]!;
    }
    throw Exception('不支持的本地表名: $localTableName');
  }

  /// 将服务端表名转换为本地表名, 比如 learning_word -> learningWords
  static String remoteTableNameToLocal(String remoteTableName) {
    // 特殊情况处理
    Map<String, String> specialMappings = {
      'daka': 'dakas',
      'user_study_step': 'userStudySteps',
      'user_oper': 'userOpers',
      'learning_word': 'learningWords',
      'learning_dict': 'learningDicts',
      'user': 'users',
      'book_mark': 'bookMarks',
      // 'user_stage_word': 'userStageWords', // UserStageWords table has been removed
      'mastered_word': 'masteredWords',
      'user_cow_dung_log': 'userCowDungLogs',
      'user_wrong_word': 'userWrongWords',
      'dict_word': 'dictWords',
    };

    if (specialMappings.containsKey(remoteTableName)) {
      return specialMappings[remoteTableName]!;
    }
    throw Exception('不支持的后端表名: $remoteTableName');
  }

  /// 把对象转化为json字符串
  static String toJson(Object object) {
    return jsonEncode(object);
  }

  /// 把ISO 8601 格式的字符串转换为数字时间戳
  static DateTime iso8601ToTimestamp(String iso8601) {
    return DateTime.parse(iso8601);
  }

  // 格式化日期为yyyyMMdd字符串
  static String formatDate(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }
}
