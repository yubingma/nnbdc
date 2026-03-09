import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test fuzzyChineseContains', () {
    String asrResult = "牛以就发奖金右然"; // 核心字: 以, 右
    String meaning = "n. 引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 引用', () {
    String asrResult = "引用";
    String meaning = "n. 引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContainsiong - iu', () {
    String asrResult = "无穷";
    String meaning = "无球"; // Not a real word, but testing the phonetic match
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
}
