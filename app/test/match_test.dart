import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test fuzzyChineseContains', () {
    String asrResult = "和大才";
    String meaning = "n. 喝倒彩";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('asrResult: $asrResult, meaning: $meaning, match: $match');
  });
}
