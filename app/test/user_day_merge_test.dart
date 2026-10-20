import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/user_extensions.dart';

/// 回归：云端整行 user 快照不得把「最近学习业务日」拽回更早的一天。
///
/// 现场事故：客户端 19:02 完成跨天重置（last_learning_date → 10-20），
/// 该变更还在 10 分钟同步节流队列里；19:07 服务端一局俄罗斯方块结算整行回写了 user，
/// 快照里 last_learning_date 仍是 10-19。次日（实际是当天剩余时间）每次点开始学习
/// 都被 StudyBo.getWord 判成 NEW_DAY，一整天进不了学习页。
void main() {
  final now = DateTime(2026, 10, 20, 21, 30);

  User buildUser({required DateTime? lastLearningDate, int gameScore = 0}) {
    return User(
      id: 'u1',
      userName: 'mock_user',
      password: '',
      nickName: 'Tester',
      email: '',
      gameScore: gameScore,
      dakaScore: 0,
      learnedDays: 44,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 50,
      dakaDayCount: 11,
      masteredWordsCount: 419,
      maxContinuousDakaDayCount: 2,
      continuousDakaDayCount: 2,
      todayStudyStarted: false,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: DateTime(2026, 5, 7),
      updateTime: now,
      lastLearningDate: lastLearningDate,
    );
  }

  test('云端快照的业务日早于本地时，保留本地业务日（其余字段照常采用云端）', () {
    final local = buildUser(lastLearningDate: DateTime(2026, 10, 20));
    final incoming = buildUser(lastLearningDate: DateTime(2026, 10, 19), gameScore: 35);

    final merged = mergeLatestLearningDay(local, incoming);

    expect(merged.lastLearningDate, DateTime(2026, 10, 20));
    expect(merged.gameScore, 35, reason: '积分等其它字段仍应采信云端');
  });

  test('云端确实推进了业务日（多设备场景）时，采信云端', () {
    final local = buildUser(lastLearningDate: DateTime(2026, 10, 19));
    final incoming = buildUser(lastLearningDate: DateTime(2026, 10, 20));

    final merged = mergeLatestLearningDay(local, incoming);

    expect(merged.lastLearningDate, DateTime(2026, 10, 20));
  });

  test('同一天时不做干预，直接采信云端对象', () {
    final local = buildUser(lastLearningDate: DateTime(2026, 10, 20));
    final incoming = buildUser(lastLearningDate: DateTime(2026, 10, 20));

    expect(identical(mergeLatestLearningDay(local, incoming), incoming), isTrue);
  });

  test('本地从未学过时，采信云端', () {
    final local = buildUser(lastLearningDate: null);
    final incoming = buildUser(lastLearningDate: DateTime(2026, 10, 19));

    expect(identical(mergeLatestLearningDay(local, incoming), incoming), isTrue);
  });

  test('本地有业务日而云端为空时，保留本地', () {
    final local = buildUser(lastLearningDate: DateTime(2026, 10, 20));
    final incoming = buildUser(lastLearningDate: null);

    expect(mergeLatestLearningDay(local, incoming).lastLearningDate, DateTime(2026, 10, 20));
  });
}
