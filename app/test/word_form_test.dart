import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/word_form.dart';

void main() {
  group('isSameWordForm - 同一单词的屈折变形', () {
    const sameForms = <List<String>>[
      ['confuse', 'confused'],
      ['confuse', 'confusing'],
      ['confused', 'confusing'],
      ['happy', 'happily'],
      ['happy', 'happier'],
      ['happy', 'happiest'],
      ['study', 'studies'],
      ['study', 'studied'],
      ['study', 'studying'],
      ['carry', 'carrying'],
      ['try', 'trying'],
      ['run', 'running'],
      ['stop', 'stopped'],
      ['box', 'boxes'],
      ['wish', 'wishes'],
      ['bus', 'buses'],
      ['hard', 'hardly'],
      ['true', 'truly'],
      ['like', 'likely'],
      ['wide', 'widely'],
      ['use', 'used'],
      ['make', 'making'],
      ['happen', 'happening'],
      ['note', 'notes'],
      ['House', 'house'],
    ];

    for (final pair in sameForms) {
      test('${pair[0]} ↔ ${pair[1]} 判为同词变形', () {
        expect(isSameWordForm(pair[0], pair[1]), isTrue);
        expect(isSameWordForm(pair[1], pair[0]), isTrue);
      });
    }
  });

  group('isSameWordForm - 不同单词不得误并', () {
    const differentForms = <List<String>>[
      ['hop', 'hope'],
      ['thin', 'thine'],
      ['range', 'rang'],
      ['liver', 'live'],
      ['only', 'one'],
      ['hard', 'hardy'],
      ['nation', 'national'],
      ['confuse', 'confusion'],
      ['happy', 'happiness'],
      ['notes', 'not'],
      ['interest', 'interment'],
      ['stripe', 'stripped'],
      ['corps', 'corpse'],
      ['cat', 'cart'],
      ['house', 'horse'],
      ['form', 'from'],
      ['happy birthday', 'happy birthday!'],
      ['', 'word'],
    ];

    for (final pair in differentForms) {
      test('${pair[0]} ↔ ${pair[1]} 不判为同词变形', () {
        expect(isSameWordForm(pair[0], pair[1]), isFalse);
        expect(isSameWordForm(pair[1], pair[0]), isFalse);
      });
    }
  });

  group('isSameWordFamily - 同一词族的派生词与拼写变体', () {
    const sameFamily = <List<String>>[
      // 用户反馈的场景：fertilizer 的题里不得再出现 fertilize / fertilise
      ['fertilizer', 'fertilize'],
      ['fertilizer', 'fertilise'],
      ['fertilize', 'fertilise'],
      ['fertilizer', 'fertilization'],
      ['fertile', 'fertilizer'],
      // 屈折变形同样算同族
      ['confuse', 'confused'],
      ['study', 'studying'],
      // 派生词
      ['confuse', 'confusion'],
      ['nation', 'national'],
      ['nation', 'nationality'],
      ['happy', 'happiness'],
      ['organize', 'organization'],
      ['danger', 'dangerous'],
      ['beauty', 'beautiful'],
      ['create', 'creation'],
      ['inform', 'information'],
      ['teach', 'teacher'],
      ['visit', 'visitor'],
      ['simple', 'simplify'],
      ['Fertilizer', 'fertilize'],
    ];

    for (final pair in sameFamily) {
      test('${pair[0]} ↔ ${pair[1]} 判为同一词族', () {
        expect(isSameWordFamily(pair[0], pair[1]), isTrue);
        expect(isSameWordFamily(pair[1], pair[0]), isTrue);
      });
    }
  });

  group('isSameWordFamily - 形近但不同族不得误并', () {
    const differentFamily = <List<String>>[
      ['liver', 'live'],
      ['only', 'one'],
      ['hard', 'hardy'],
      ['interest', 'interment'],
      ['nation', 'nature'],
      ['cat', 'cart'],
      ['house', 'horse'],
      ['form', 'from'],
      ['notes', 'not'],
      // 形近词干扰项必须保留（形近词策略的既有用例依赖它们）
      ['confuse', 'confute'],
      ['confuse', 'consume'],
      ['confuse', 'confess'],
      ['confuse', 'confer'],
      ['change', 'charge'],
      ['change', 'chance'],
      ['change', 'orange'],
      ['happy birthday', 'happy birthday!'],
      ['', 'word'],
    ];

    for (final pair in differentFamily) {
      test('${pair[0]} ↔ ${pair[1]} 不判为同一词族', () {
        expect(isSameWordFamily(pair[0], pair[1]), isFalse);
        expect(isSameWordFamily(pair[1], pair[0]), isFalse);
      });
    }
  });
}
