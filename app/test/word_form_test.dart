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
}
