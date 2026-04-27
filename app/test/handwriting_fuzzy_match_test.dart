import 'package:flutter_test/flutter_test.dart';

// 1. NLP 锚点距离感知算法函数
String getProcessedText(String target, String text) {
  String processedText = "";
  final String lowerTarget = target.toLowerCase();
  
  List<Map<String, dynamic>> anchors = [];
  for (int i = 0; i < lowerTarget.length; i++) {
    if (lowerTarget[i] == 'd') {
      anchors.add({'idx': i, 'type': 'd'});
    } else if (lowerTarget[i] == 'c' && (i + 1) < lowerTarget.length && lowerTarget[i + 1] == 'l') {
      anchors.add({'idx': i, 'type': 'cl'});
    } else if (lowerTarget[i] == 'h') {
      anchors.add({'idx': i, 'type': 'h'});
    } else if (lowerTarget[i] == 'n') {
      anchors.add({'idx': i, 'type': 'n'});
    }
  }
  
  for (int idx = 0; idx < text.length; idx++) {
    final iChar = text[idx].toLowerCase();
    if ((iChar == 'd' || iChar == 'h' || iChar == 'n') && anchors.isNotEmpty) {
      Map<String, dynamic> nearestAnchor = anchors[0];
      int minDistance = (idx - (anchors[0]['idx'] as int)).abs();
      
      for (final anchor in anchors) {
        final int dist = (idx - (anchor['idx'] as int)).abs();
        if (dist < minDistance) {
          minDistance = dist;
          nearestAnchor = anchor;
        }
      }
      
      if (iChar == 'd' && nearestAnchor['type'] == 'cl') {
        processedText += (text[idx] == 'D') ? 'CL' : 'cl';
        continue;
      }
      if (iChar == 'h' && nearestAnchor['type'] == 'n') {
        processedText += (text[idx] == 'H') ? 'N' : 'n';
        continue;
      }
      if (iChar == 'n' && nearestAnchor['type'] == 'h') {
        processedText += (text[idx] == 'N') ? 'H' : 'h';
        continue;
      }
    }
    processedText += text[idx];
  }
  return processedText;
}

// 2. 超级模糊结算判定函数
bool isSuperMatch(String target, String input) {
  final String normalizedTarget = target.replaceAll(RegExp(r'[\s\-]'), '').toLowerCase();
  final String normalizedInput = input.replaceAll(RegExp(r'[\s\-]'), '').toLowerCase();
  
  final String fuzzyTarget = normalizedTarget.replaceAll('cl', 'd');
  
  return normalizedTarget == normalizedInput || fuzzyTarget == normalizedInput;
}

void main() {
  group('手写 D 与 CL 连写智能容错测试', () {
    
    test('场景 A：单纯的 cl 被认作 d (如 cliff)', () {
      final target = 'cliff';
      final rawInput = 'diff'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText, 'cliff'); 
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true); 
    });

    test('场景 B：既有真 D，又有 CL 的长词 (如 disclose)', () {
      final target = 'disclose';
      final rawInput = 'disdose'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText, 'disclose'); 
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true);
    });

    test('场景 C：动词过去式末尾带真 D (如 closed)', () {
      final target = 'closed';
      final rawInput = 'dosed'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText, 'closed'); 
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true);
    });

    test('场景 D：复杂连写 (如 cyclical)', () {
      final target = 'cyclical';
      final rawInput = 'cy d i c a l'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText.replaceAll(' ', ''), 'cyclical');
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true);
    });
    
    test('场景 E：作弊与公正性防线测试', () {
      final target = 'apple';
      final rawInput = 'dpple'; 
      
      final processedText = getProcessedText(target, rawInput);
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, false); 
    });

    test('场景 F：手写 H 被误认为 N (如 hat)', () {
      final target = 'hat';
      final rawInput = 'nat'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText, 'hat'); 
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true); 
    });

    test('场景 G：手写 N 被误认为 H (如 nice)', () {
      final target = 'nice';
      final rawInput = 'hice'; 
      
      final processedText = getProcessedText(target, rawInput);
      expect(processedText, 'nice'); 
      
      final isMatch = isSuperMatch(target, processedText);
      expect(isMatch, true); 
    });
  });
}
