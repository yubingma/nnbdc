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
    String meaning = "意识到的";
    
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
}
