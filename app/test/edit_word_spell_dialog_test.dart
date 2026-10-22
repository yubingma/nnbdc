import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/edit_meaning_dialog.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:toastification/toastification.dart';

class _NoopWordModifier implements WordModifier {
  @override
  Future<bool> addWord(String wordId) async => false;

  @override
  Future<DictImportStats> addWords(List<DictWordImportItem> items, {bool updateMeanings = false}) async =>
      const DictImportStats();

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

  late MyDatabase db;
  const userId = 'user_1';
  const wordId = 'word_1';
  final now = DateTime(2026, 10, 21, 20);

  User buildUser() => User(
        id: userId,
        userName: 'tester',
        password: '',
        nickName: 'Tester',
        email: '',
        gameScore: 0,
        dakaScore: 0,
        learnedDays: 0,
        learningFinished: false,
        inviteAwardTaken: false,
        isSuperAdmin: false,
        isAdmin: false,
        isInputor: true,
        cowDung: 0,
        throwDiceChance: 0,
        wordsPerDay: 5,
        dakaDayCount: 0,
        masteredWordsCount: 0,
        maxContinuousDakaDayCount: 0,
        continuousDakaDayCount: 0,
        todayStudyStarted: false,
        totalLearningSeconds: 0,
        todayLearningSeconds: 0,
        createTime: now,
        updateTime: now,
      );

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    final user = buildUser();
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
  });

  tearDown(() async {
    Global.currentUserId = null;
    await db.close();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(ToastificationWrapper(
      child: MaterialApp(
        home: EditMeaningDialog(
          word: WordWrapper(WordVo.c2('aple')..id = wordId, null),
          wordModifier: _NoopWordModifier(),
          onSuccess: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('自建词的编辑弹窗显示拼写输入', (tester) async {
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'aple',
          popularity: 1,
          ownerId: userId,
          createTime: now,
          updateTime: now,
        ));

    await pumpDialog(tester);

    expect(find.text('拼写'), findsOneWidget);
    expect(find.text('编辑单词: aple'), findsOneWidget);
  });

  testWidgets('系统词的编辑弹窗不显示拼写输入', (tester) async {
    await db.into(db.words).insert(Word(
          id: wordId,
          spell: 'apple',
          popularity: 1,
          ownerId: Global.sysUserId,
          createTime: now,
          updateTime: now,
        ));

    await pumpDialog(tester);

    expect(find.text('拼写'), findsNothing);
    expect(find.text('编辑释义: aple'), findsOneWidget);
  });
}
