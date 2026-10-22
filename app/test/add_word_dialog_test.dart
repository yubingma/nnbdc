import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/add_word_dialog.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:toastification/toastification.dart';

class _RecordingWordModifier implements WordModifier {
  final List<String> addedWordIds = [];
  final List<DictWordImportItem> addedItems = [];

  @override
  Future<bool> addWord(String wordId) async {
    addedWordIds.add(wordId);
    return true;
  }

  @override
  Future<DictImportStats> addWords(List<DictWordImportItem> items, {bool updateMeanings = false}) async {
    addedItems.addAll(items);
    return DictImportStats(inserted: items.length);
  }

  @override
  Future<bool> updateMeanings(String wordId, List<MeaningUpdateItem> meanings) async => false;

  @override
  Future<bool> deleteMeaning(String wordId) async => false;

  @override
  String? get targetDictId => null;

  @override
  Future<String?> resolveTargetDictId() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase database;

  setUp(() {
    database = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> openDialog(
    WidgetTester tester,
    _RecordingWordModifier modifier, {
    required VoidCallback onAdded,
  }) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AddWordDialog(
                  wordModifier: modifier,
                  onAdded: () async => onAdded(),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('通用词典已收录：直接加入词表', (tester) async {
    final now = DateTime.now();
    await database.into(database.words).insert(Word(
          id: 'w1',
          spell: 'ability',
          popularity: 1,
          createTime: now,
          updateTime: now,
        ));

    final modifier = _RecordingWordModifier();
    var added = 0;
    await openDialog(tester, modifier, onAdded: () => added++);

    await tester.enterText(find.byType(TextField).first, 'ability');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    expect(modifier.addedWordIds, ['w1']);
    expect(modifier.addedItems, isEmpty);
    expect(added, 1);
    expect(find.byType(AddWordDialog), findsNothing);
  });

  testWidgets('通用词典未收录：补释义后按新词加入', (tester) async {
    final modifier = _RecordingWordModifier();
    var added = 0;
    await openDialog(tester, modifier, onAdded: () => added++);

    await tester.enterText(find.byType(TextField).first, 'floccinaucinihilipilification');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    // 未收录时先展开释义输入，不凭空建词
    expect(find.textContaining('通用词典中没有这个词'), findsOneWidget);
    expect(modifier.addedItems, isEmpty);

    await tester.enterText(find.byType(TextField).last, '滑稽地;无价值地');
    await tester.tap(find.widgetWithText(TextButton, '加入词表'));
    await tester.pumpAndSettle();

    expect(modifier.addedWordIds, isEmpty);
    expect(modifier.addedItems, hasLength(1));
    expect(modifier.addedItems.single.newSpell, 'floccinaucinihilipilification');
    expect(modifier.addedItems.single.meaning, '滑稽地;无价值地');
    expect(modifier.addedItems.single.partOfSpeech, 'n.');
    expect(added, 1);

    // 等成功提示自动收起，避免测试结束时仍有 Toast 定时器
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('词典未收录且释义为空：不建词', (tester) async {
    final modifier = _RecordingWordModifier();
    await openDialog(tester, modifier, onAdded: () {});

    await tester.enterText(find.byType(TextField).first, 'zzzznotaword');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '加入词表'));
    await tester.pumpAndSettle();

    expect(modifier.addedItems, isEmpty);
    expect(modifier.addedWordIds, isEmpty);
    expect(find.byType(AddWordDialog), findsOneWidget);

    // 等错误提示自动收起，避免测试结束时仍有 Toast 定时器
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('中文不能当单词：直接拒绝，不展开释义也不建词', (tester) async {
    final modifier = _RecordingWordModifier();
    await openDialog(tester, modifier, onAdded: () {});

    await tester.enterText(find.byType(TextField).first, '苹果');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.textContaining('通用词典中没有这个词'), findsNothing);
    expect(modifier.addedWordIds, isEmpty);
    expect(modifier.addedItems, isEmpty);
    expect(find.byType(AddWordDialog), findsOneWidget);

    // 等错误提示自动收起，避免测试结束时仍有 Toast 定时器
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('通用词典已收录的词带尾部标点：仍按原口径加入', (tester) async {
    final now = DateTime.now();
    await database.into(database.words).insert(Word(
          id: 'w2',
          spell: 'apple',
          popularity: 1,
          createTime: now,
          updateTime: now,
        ));

    final modifier = _RecordingWordModifier();
    await openDialog(tester, modifier, onAdded: () {});

    await tester.enterText(find.byType(TextField).first, 'apple,');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    expect(modifier.addedWordIds, ['w2']);
    expect(modifier.addedItems, isEmpty);
  });
}
