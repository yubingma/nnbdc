import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI 助教聊天中英文单词识别与转链测试', () {
    final markdownWordReplacerRegex = RegExp(
      r'(```[\s\S]*?```)|(`[^`\n]+`)|(https?://[^\s)]+)|(\[[^\]]+\]\([^\)]+\))|(\b[a-zA-Z]{2,}\b)',
    );

    String linkifyEnglishWords(String markdown) {
      return markdown.replaceAllMapped(markdownWordReplacerRegex, (match) {
        if (match.group(1) != null ||
            match.group(2) != null ||
            match.group(3) != null ||
            match.group(4) != null) {
          return match.group(0)!;
        }
        final word = match.group(5);
        if (word != null) {
          return '[$word](word:$word)';
        }
        return match.group(0)!;
      });
    }

    test('普通搭配与解释中的英文单词能够正确转为 word: 协议链接', () {
      const input = '🔗 搭配 · perimeter fence — 周界围栏';
      final output = linkifyEnglishWords(input);
      expect(
        output,
        '🔗 搭配 · [perimeter](word:perimeter) [fence](word:fence) — 周界围栏',
      );
    });

    test('保护已有的 Markdown 链接不受影响', () {
      const input = '建议：[它和circumference有什么区别?](suggest:)';
      final output = linkifyEnglishWords(input);
      // 已有链接整体保留，不拆解内部单词
      expect(output, '建议：[它和circumference有什么区别?](suggest:)');
    });

    test('保护代码块不受影响', () {
      const input = '不要修改 `const border = 1;` 变量';
      final output = linkifyEnglishWords(input);
      expect(output, '不要修改 `const border = 1;` 变量');
    });

    test('单字母不被转换，避免视觉噪音', () {
      const input = 'a pen and I am';
      final output = linkifyEnglishWords(input);
      // 'a' 与 'I' 为单字母，不转；'pen', 'and', 'am' >= 2 个字母，转
      expect(output, 'a [pen](word:pen) [and](word:and) I [am](word:am)');
    });

    test('带冒号和括号等标点时精准提取词干', () {
      const input = 'perimeter: 任意封闭图形 (circumference)';
      final output = linkifyEnglishWords(input);
      expect(
        output,
        '[perimeter](word:perimeter): 任意封闭图形 ([circumference](word:circumference))',
      );
    });

    test('追问药丸分词正则能够精准提炼英文词', () {
      const suggest = '它和circumference有什么区别?';
      final matches = RegExp(r'\b[a-zA-Z]{2,}\b').allMatches(suggest).toList();
      expect(matches.length, 1);
      expect(matches.first.group(0), 'circumference');
    });
  });
}
