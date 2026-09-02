import 'dart:collection';
import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../api/vo.dart';
import '../config.dart';
import '../global.dart';
import '../theme/app_theme.dart';
import 'app_clock.dart';

class Util {
  /// 某些文件命中含有单词拼写（如单词的声音文件，例句声音文件），所以需要对单词的一些特殊字符做处理
  ///
  /// @param spell
  /// @return
  static String uniformSpellForFilename(String spell) {
    // 字母、数字、空格、连字符、单引号建议保留，剔除其它文件系统敏感字符
    spell = spell.replaceAll(RegExp(r"[?!:#/\\><|]"), "").toLowerCase();
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

  static final Set<String> _punctuationChars = {
    '《', '》', '〈', '〉', '（', '）', '(', ')', '[', ']', '【', '】', '〔', '〕', '{', '}', '「', '」', '『', '』',
    '"', "'", '“', '”', '‘', '’', '‹', '›', '«', '»', '…', '—', '-', '_', '+', '=', '|', r'\', '/', '~', '`',
    '!', '@', '#', r'$', '%', '^', '&', '*', '•', '·', ',', '.', ':', ';', '?', '！', '￥', '、', '；', '：', '？',
    ' ', '\t', '\n', '\r'
  };

  /// 安全获取用于头像/封面展示的首个有效字符（跳过书名号《》、括号、引号等标点符号，提取首个汉字/字母/数字/Emoji）
  static String getInitial(String? text, {String fallback = 'U'}) {
    if (text == null || text.trim().isEmpty) return fallback;
    final trimmed = text.trim();
    for (final char in trimmed.characters) {
      if (!_punctuationChars.contains(char) && char.trim().isNotEmpty) {
        return char.toUpperCase();
      }
    }
    return trimmed.characters.isNotEmpty ? trimmed.characters.first.toUpperCase() : fallback;
  }

  static String getShortName(String name) {
    if (name.endsWith(".dict")) {
      return name.substring(0, name.lastIndexOf("."));
    } else {
      return name;
    }
  }

  static String getFileNameOfWordSound(String spell) {
    spell = uniformSpellForFilename(spell);
    if (spell.codeUnitAt(0) >= 'a'.codeUnitAt(0) && spell.codeUnitAt(0) <= 'z'.codeUnitAt(0)) {
      return "${spell[0]}/$spell";
    } else {
      return "other/$spell";
    }
  }

  /// 获取指定单词对应的发音文件Url
  /// 基础发音库均为无后缀文件（美音）；若偏好英音则优先 _uk，否则使用基础库
  static String getWordSoundUrl(String spell, {WordVo? word, String? accent}) {
    final a = accent ?? Prefs.pronunciationAccent;
    final suffix = a == 'uk' ? '_uk' : '';
    String url = "${Config.soundBaseUrl}${Util.getFileNameOfWordSound(spell)}$suffix.mp3";
    if (word != null && word.updateTime != null) {
      url += "?v=${word.updateTime!.millisecondsSinceEpoch}";
    }
    return url;
  }

  /// 单词发音 URL 回退序列:
  /// - 英音模式: 基础库无后缀 → 美音 _us
  /// - 美音模式: 美音 _us → 英音 _uk
  static List<String> getWordSoundFallbackUrls(String spell) {
    final base = Util.getFileNameOfWordSound(spell);
    final isUk = Prefs.pronunciationAccent == 'uk';
    if (isUk) {
      return [
        "${Config.soundBaseUrl}$base.mp3",
        "${Config.soundBaseUrl}${base}_us.mp3",
      ];
    } else {
      return [
        "${Config.soundBaseUrl}${base}_us.mp3",
        "${Config.soundBaseUrl}${base}_uk.mp3",
      ];
    }
  }

  /// 获取指定的例句对应的发音文件Url
  static String getSentenceSoundUrl(String englishDigest) {
    return "${Config.soundBaseUrl}sentence/$englishDigest.mp3";
  }

  /// 获取指定的 AI 短文对应的发音文件Url (英文版)
  static String getAiStoryEnSoundUrl(String wordsHash) {
    return "${Config.soundBaseUrl}ai_story/${wordsHash}_en.mp3";
  }

  /// 获取指定的 AI 短文对应的发音文件Url (中文版)
  static String getAiStoryCnSoundUrl(String wordsHash) {
    return "${Config.soundBaseUrl}ai_story/${wordsHash}_cn.mp3";
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

  static String translateCiXing(String ciXing) {
    if (ciXing.isEmpty) return "";
    var lower = ciXing.toLowerCase().replaceAll('.', '').trim();
    String translated;
    switch (lower) {
      case 'n':
        translated = '名';
        break;
      case 'v':
        translated = '动';
        break;
      case 'adj':
        translated = '形';
        break;
      case 'adv':
        translated = '副';
        break;
      case 'prep':
        translated = '介';
        break;
      case 'conj':
        translated = '连';
        break;
      case 'pron':
        translated = '代';
        break;
      case 'num':
        translated = '数';
        break;
      case 'art':
        translated = '冠';
        break;
      case 'int':
        translated = '叹';
        break;
      case 'vt':
        translated = '及物';
        break;
      case 'vi':
        translated = '不及物';
        break;
      case 'phrase':
        translated = '短语';
        break;
      case 'aux':
        translated = '助';
        break;
      case 'pref':
        translated = '前缀';
        break;
      case 'suff':
        translated = '后缀';
        break;
      default:
        translated = ciXing.replaceAll('.', '');
    }
    return '[$translated]';
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
  static Widget makeChineseSpanText(String chinese, BuildContext context,
      {TextStyle? style, TextAlign textAlign = TextAlign.start}) {
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
      color: style?.color ?? (context.watch<DarkMode>().isDarkMode ? Colors.grey[300] : Colors.grey[700]),
    );

    return Text.rich(
      TextSpan(children: <InlineSpan>[
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: boldWordIndices.contains(i)
                ? baseStyle.copyWith(color: context.primaryColor, fontWeight: FontWeight.bold)
                : baseStyle,
          )
      ]),
      textAlign: textAlign,
    );
  }

  /// 把英文句子的每个单词转换为相应的widget，形成一个RichText
  static Text makeEnglishSpanText(
      String words,
      String highlightWord,
      bool highlightWordHasBeenTaged,
      BuildContext context,
      bool maskHighlightWord,
      SizedBox? maskTextField,
      bool isHighlightWordUnClickable,
      FontWeight fontWeight, {
    double fontSize = 14,
    TextAlign textAlign = TextAlign.left,
    Color? color,
  }) {
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
            text: token,
            style: TextStyle(
                color: boldWordIndices.contains(i) ? context.primaryColor : null,
                fontSize: fontSize,
                fontWeight: boldWordIndices.contains(i) ? FontWeight.bold : fontWeight)));
      } else {
        // 单词
        spans.add(boldWordIndices.contains(i) && maskTextField != null
            ? WidgetSpan(
                child: maskTextField,
              )
            : TextSpan(
                text: boldWordIndices.contains(i) && maskHighlightWord ? ''.padRight(token.length, '_') : token,
                style: TextStyle(
                    color: boldWordIndices.contains(i) ? context.primaryColor : null,
                    fontSize: fontSize,
                    fontWeight: boldWordIndices.contains(i) ? FontWeight.bold : fontWeight),
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
                      StudyAudioSessionController().playWordSound(searchResult.word!);

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
                                            StudyAudioSessionController().playWordSound(searchResult.word!);
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
                                                    StudyAudioSessionController().playAddSuccessSound();
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

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
  }

  static String getWordDefaultPronounce(WordVo word) {
    return getWordPronounceWithAccent(word).$1;
  }

  /// 获取单词音标及其实际所属口音（例如 '英', '美'）
  /// 返回 (pronounce, accentLabel, isFallback)
  /// - pronounce: 音标内容，如 'ˈskedʒuːl'
  /// - accentLabel: '英' 或 '美' 或 ''
  /// - isFallback: 是否发生了口音降级（例如用户偏好英音，但展示的是美音音标）
  static (String pronounce, String accentLabel, bool isFallback) getWordPronounceWithAccent(WordVo word) {
    final isUkPref = Prefs.pronunciationAccent == 'uk';
    if (isUkPref) {
      if (word.britishPronounce != null && word.britishPronounce!.isNotEmpty) {
        return (word.britishPronounce!, '英', false);
      }
      if (word.pronounce != null && word.pronounce!.isNotEmpty) {
        return (word.pronounce!, '', false);
      }
      if (word.americaPronounce != null && word.americaPronounce!.isNotEmpty) {
        return (word.americaPronounce!, '美', true);
      }
    } else {
      if (word.americaPronounce != null && word.americaPronounce!.isNotEmpty) {
        return (word.americaPronounce!, '美', false);
      }
      if (word.pronounce != null && word.pronounce!.isNotEmpty) {
        return (word.pronounce!, '', false);
      }
      if (word.britishPronounce != null && word.britishPronounce!.isNotEmpty) {
        return (word.britishPronounce!, '英', true);
      }
    }
    return ('', '', false);
  }

  /// 尝试本地查询单词及其变体形式
  /// 现在只使用本地查词，不再调用后端
  static Future<SearchWordResult> _searchWordWithVariants(String spell) async {
    // 使用本地搜索方法，本地已包含通用词典的所有单词
    return await WordBo().searchWordLocalOnly(spell);
  }


  /// 关闭输入法
  static void closeIme() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  static Future<String?> networkImageToBase64(String imageUrl) async {
    try {
      http.Response response = await http.get(Uri.parse(imageUrl));

      // 检查响应状态码
      if (response.statusCode != 200) {
        Global.logger.w('networkImageToBase64: 请求失败，状态码: ${response.statusCode}, URL: $imageUrl');
        return null;
      }

      final bytes = response.bodyBytes;

      // 验证数据不为空
      if (bytes.isEmpty) {
        Global.logger.w('networkImageToBase64: 图像数据为空, URL: $imageUrl');
        return null;
      }

      // 基本验证：检查是否是有效的图像格式（通过文件头）
      if (bytes.length < 4) {
        Global.logger.w('networkImageToBase64: 图像数据过短, URL: $imageUrl');
        return null;
      }

      // 检查常见的图像文件头
      bool isValidImage = false;
      // JPEG: FF D8 FF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        isValidImage = true;
      }
      // PNG: 89 50 4E 47
      else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        isValidImage = true;
      }
      // GIF: 47 49 46 38
      else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
        isValidImage = true;
      }
      // WebP: RIFF...WEBP
      else if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        isValidImage = true;
      }

      if (!isValidImage) {
        Global.logger
            .w('networkImageToBase64: 不是有效的图像格式, URL: $imageUrl, 前4字节: ${bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        // 不直接返回 null，因为可能还有其他格式，让调用方决定
        // 但记录警告日志
      }

      return base64Encode(bytes);
    } catch (e, stackTrace) {
      Global.logger.e('networkImageToBase64: 获取图像失败, URL: $imageUrl', error: e, stackTrace: stackTrace);
      return null;
    }
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
      'meaningItems': 'meaning_item',
      'learningLogs': 'learning_log',
      'words': 'word',
      'dictGroups': 'dict_group',
      'groupAndDictLinks': 'group_and_dict_link',
      'cigens': 'cigen',
      'cigenWordLinks': 'cigen_word_link',
      'sentences': 'sentence',
      'wordImages': 'word_image',
      'userStudyDailyStats': 'user_study_daily_stat',
      'pcaProjectionConfigs': 'pca_projection_config',
      'userBadges': 'user_badge',
      // word_shortdesc_chineses 已删除，不再映射
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
      'users': 'users', // 兼容历史异常数据
      'book_mark': 'bookMarks',
      'mastered_word': 'masteredWords',
      'user_cow_dung_log': 'userCowDungLogs',
      'user_wrong_word': 'userWrongWords',
      'dict_word': 'dictWords',
      'dict': 'dicts',
      'meaning_item': 'meaningItems',
      'learning_log': 'learningLogs',
      'word': 'words',
      'dict_group': 'dictGroups',
      'group_and_dict_link': 'groupAndDictLinks',
      'cigen': 'cigens',
      'cigen_word_link': 'cigenWordLinks',
      'sentence': 'sentences',
      'word_image': 'wordImages',
      'user_study_daily_stat': 'userStudyDailyStats',
      'pca_projection_config': 'pcaProjectionConfigs',
      'user_badge': 'userBadges',
      // word_shortdesc_chinese 表已删除，映射到特殊标记而不是实际表，同步时将被跳过
      'word_shortdesc_chinese': 'IGNORED',
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

  /// 兼容性修复：将 JSON 中的各种日期格式转换为 ISO8601 字符串
  static void fixJsonDates(Map<String, dynamic> json) {
    for (var key in ['createTime', 'updateTime']) {
      var val = json[key];
      if (val == null) {
        // 如果字段缺失或为null，使用当前时间
        json[key] = AppClock.now().toIso8601String();
      } else if (val is int) {
        // 毫秒时间戳转换为字符串
        json[key] = DateTime.fromMillisecondsSinceEpoch(val).toIso8601String();
      } else if (val is String && val.isNotEmpty) {
        // 尝试解析各种字符串格式（如 "2026-04-11 22:03:08.636"）
        try {
          // 如果已经是 ISO8601 (含 T)，则继续处理下一个字段
          if (val.contains('T')) continue;

          // 处理 "yyyy-MM-dd HH:mm:ss.SSS" 格式
          String fixed = val.replaceFirst(' ', 'T');
          DateTime.parse(fixed); // 验证格式
          json[key] = fixed;
        } catch (e) {
          Global.logger.w("⚠️ 日期格式解析失败 ($key): $val");
          json[key] = AppClock.now().toIso8601String(); // 解析失败也给个默认值，防止 crash
        }
      }
    }
  }

  /// 从 pubspec.yaml 获取版本更新说明列表
  static Future<List<String>> getAppChanges() async {
    try {
      final content = await rootBundle.loadString('pubspec.yaml');
      return parseChangesFromPubspec(content);
    } catch (e) {
      return [];
    }
  }

  /// 解析 pubspec.yaml 文本中的 changes 列表
  static List<String> parseChangesFromPubspec(String yamlContent) {
    final lines = yamlContent.split('\n');
    bool inChanges = false;
    List<String> changes = [];
    for (var line in lines) {
      if (RegExp(r'^\s*changes\s*:').hasMatch(line)) {
        inChanges = true;
        continue;
      }
      if (inChanges) {
        if (line.trim().isEmpty) continue;
        if (RegExp(r'^\s+-\s*').hasMatch(line)) {
          var item = line.trim();
          item = item.replaceFirst(RegExp(r'^-\s*'), '');
          if ((item.startsWith('"') && item.endsWith('"')) ||
              (item.startsWith("'") && item.endsWith("'"))) {
            item = item.substring(1, item.length - 1);
          }
          if (item.isNotEmpty) {
            changes.add(item);
          }
        } else if (!line.trim().startsWith('#')) {
          break;
        }
      }
    }
    return changes;
  }
}
