import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test fuzzyChineseContains', () {
    String asrResult = "牛以就发奖金右然"; // 核心字: 以, 右
    String meaning = "n. 引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 引用', () {
    String asrResult = "引用";
    String meaning = "n. 引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - phonetic similarity', () {
    String asrResult = "无穷";
    String meaning = "无球"; // Not a real word, but testing the phonetic match
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - dissimilar phrases (non-match)', () {
    String asrResult = "有意义的";
    String meaning = "不明白的";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });
  test('Test fuzzyChineseContains - 没见-媒介', () {
    String asrResult = "没见";
    String meaning = "n. 媒介";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 情况-惊慌', () {
    String asrResult = "情况";
    String meaning = "n. 惊慌";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 这都-战斗', () {
    String asrResult = "这都";
    String meaning = "n. 战斗";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 启禀-曲柄', () {
    String asrResult = "启禀";
    String meaning = "n. 曲柄";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 西-吸引', () {
    String asrResult = "西";
    String meaning = "n. 吸引";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 父也-赋予', () {
    String asrResult = "父也";
    String meaning = "n. 赋予";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 大概-大纲', () {
    String asrResult = "大概";
    String meaning = "n. 大纲";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 博取-夺取', () {
    String asrResult = "博取";
    String meaning = "n. 夺取";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 白本-版本', () {
    String asrResult = "白本";
    String meaning = "n. 版本";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 论论-论文', () {
    String asrResult = "论论";
    String meaning = "n. 论文";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 识别人-使变软', () {
    String asrResult = "识别人";
    String meaning = "n. 使变软";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 美润状-委任状', () {
    String asrResult = "美润状";
    String meaning = "n. 委任状";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 爱尔兰-爱尔兰人', () {
    String asrResult = "爱尔兰";
    String meaning = "爱尔兰人";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 打死-打扫', () {
    String asrResult = "打死";
    String meaning = "v. 打扫";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 巴苦-挖苦', () {
    String asrResult = "巴苦";
    String meaning = "v. 挖苦";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 顺利-视力', () {
    String asrResult = "顺利";
    String meaning = "n. 视力";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 下令-下列', () {
    String asrResult = "下令";
    String meaning = "n. 下列";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 毛型-模型', () {
    String asrResult = "毛型";
    String meaning = "n. 模型";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 此时-四十', () {
    String asrResult = "此时";
    String meaning = "n. 四十";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 毛饭-毛发', () {
    String asrResult = "毛饭";
    String meaning = "n. 毛发";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 大哥-大纲', () {
    String asrResult = "大哥";
    String meaning = "n. 大纲";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
}
