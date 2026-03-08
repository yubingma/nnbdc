import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test fuzzyChineseContains', () {
    String asrResult = "个性的";
    String meaning = "n. 人称的";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('asrResult: $asrResult, meaning: $meaning, match: $match');
  });
}
