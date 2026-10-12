import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/word_pack_queue.dart';

/// 造一段形如 [索引] 的词条，方便断言取到的是哪一题
List<String> _pack(int from, int count) =>
    List.generate(count, (i) => 'w${from + i}');

void main() {
  group('WordPackQueue 本地出题词包', () {
    test('开局首包可以按索引依次出题', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));

      expect(queue.wordAt(0), 'w0');
      expect(queue.wordAt(1), 'w1');
      expect(queue.wordAt(49), 'w49');
      expect(queue.wordAt(50), isNull);
    });

    test('包尾提前预取下一包，且同一段不会重复要', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));

      expect(queue.packRequestFor(40), isNull, reason: '余量充足时不该补包');
      expect(queue.packRequestFor(42), 50, reason: '剩余 8 个时开始预取下一包');
      expect(queue.packRequestFor(43), isNull, reason: '同一段只允许要一次');
    });

    test('预取的下一包在当前包用尽后无缝接管', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));
      queue.accept(50, _pack(50, 50));

      expect(queue.wordAt(49), 'w49');
      expect(queue.wordAt(50), 'w50');
      expect(queue.wordAt(51), 'w51');
      expect(queue.packRequestFor(92), 100, reason: '接管后继续按新包预取');
    });

    test('没预取到时用当前索引请求补包', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));

      expect(queue.wordAt(50), isNull);
      expect(queue.packRequestFor(50), 50);
      expect(queue.packRequestFor(50), isNull, reason: '在途请求不重复发');
    });

    test('断线重连后按当前索引重新对齐，预取的下包仍然有效', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));
      queue.accept(50, _pack(50, 50));

      // 重连后服务端按当前题目索引重新下发一段
      queue.accept(42, _pack(42, 50));

      expect(queue.wordAt(42), 'w42');
      expect(queue.wordAt(43), 'w43');
      expect(queue.wordAt(91), 'w91', reason: '重连前预取的下包不该被丢掉');
    });

    test('重连后允许对同一段再要一次（在途请求可能已经丢了）', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));
      queue.markRequested(50);

      expect(queue.packRequestFor(50), isNull);
      queue.forgetRequested();
      expect(queue.packRequestFor(50), 50);
    });

    test('reset 清空上一局的词包', () {
      final queue = WordPackQueue()..accept(0, _pack(0, 50));
      queue.reset();

      expect(queue.wordAt(0), isNull);
      expect(queue.packRequestFor(0), 0);
    });
  });
}
