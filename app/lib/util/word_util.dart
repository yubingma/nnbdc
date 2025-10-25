import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';

import '../api/vo.dart';

class WordWrapper {
  /// 实际的单词相关对象，比如MasteredWord, LearningWord ...
  dynamic tag;

  /// tag中的Word对象
  WordVo word;

  FocusNode focusNode = FocusNode();

  /// 默写英文输入框
  TextEditingController spellController = TextEditingController();

  /// 提示字符数量
  int hintLetterCount = 0;

  /// 正确答案是否是系统自动提供的（而不是用户提供的）
  bool isAnswerProvidedBySystem = false;

  /// asr匹配上的释义项子项(一个词性下，被分号分开的多个部分，称为子项)，一个子项由两个坐标确定：（释义项索引，子项索引）
  List<Pair<int, int>> asrMatchedMeaningItemParts = [];

  /// 说中文 的学习模式下，用户是否已经答出了单词的所有意思
  bool answeredAllMeanings = false;

  /// 是否在“背英文”模式下已经答对（用于揭示英文拼写）
  bool speakEnglishPassed = false;

  WordWrapper(this.word, this.tag);

  @override
  bool operator ==(Object other) => identical(this, other) || other is WordWrapper && runtimeType == other.runtimeType && word.id == other.word.id;

  @override
  int get hashCode => word.id.hashCode;
}

/// 把释义项拆分为子项, 并排除为空的情况
List<String> splitMeaning2Parts(String meaning) {
  var parts = meaning.split(RegExp(r"[;；]"));
  return parts.where((part) => part.isNotEmpty).toList();
}

/// 在单词的所有释义项子项，以及给定的中文内容之间进行匹配，返回释义项子项总数量/匹配上的释义项子项数量/本次新增匹配数量
Triple<int, int, int> matchInputChineseWithMeaningItems(WordWrapper wordWrapper, String asrResult) {
  var count = 0; // 所有释义项子项数量
  var newMatchCount = 0; //本次匹配新匹配上的释义项数量
  var meaningItems = wordWrapper.word.getMergedMeaningItems();
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
        if (fuzzyChineseContains(asrResult, part)) {
          newMatchCount++;
          wordWrapper.asrMatchedMeaningItemParts.add(Pair(i, j));
        }
      }
    }
  }
  return Triple(count, wordWrapper.asrMatchedMeaningItemParts.length, newMatchCount);
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

List<Widget> renderAsrMeaningItems(WordWrapper word) {
  List<Widget> items = [];
  List<MeaningItemVo> meaningItems = word.word.getMergedMeaningItems();
  for (var i = 0; i < meaningItems.length; i++) {
    var meaningItem = meaningItems[i];
    items.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((meaningItem.ciXing ?? '').isNotEmpty)
          Text(
            meaningItem.ciXing!,
            style: const TextStyle(fontSize: 12),
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          children: renderMeaningItemParts(meaningItem.meaning!, i, word.hintLetterCount, word.asrMatchedMeaningItemParts),
        ),
      ],
    ));
  }
  return items;
}

/// 渲染一个释义项的子项
List<Widget> renderMeaningItemParts(String meaning, int meaningIndex, int hintLetterCount, List<Pair<int, int>> asrMatchedMeaningItemParts) {
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
        style: const TextStyle(color: Colors.green, fontSize: 12),
      );
      partWidgets.add(widget);
    }
    // 释义项尚未被用户答对
    else {
      // 根据"给点提示"的数字，展现相应数量的汉字释义
      var displayText = part.replaceAll(RegExp(r"[\u4e00-\u9fa5]"), '^'); // 每个汉字用一个^代替
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
            width: 14, // 固定宽度，大约等于一个汉字的宽度
            child: Text(
              '＿',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ));
        } else {
          // 已显示的汉字或其他字符
          finalWidgets.add(Text(
            displayText[i],
            style: const TextStyle(fontSize: 12),
          ));
        }
      }

      var widget = Row(
        mainAxisSize: MainAxisSize.min,
        children: finalWidgets,
      );
      partWidgets.add(widget);
    }

    // 显示释义项分隔符
    if (i != parts.length - 1) {
      partWidgets.add(const Text(
        "；",
        style: TextStyle(fontSize: 12),
      ));
    }
  }
  return partWidgets;
}
