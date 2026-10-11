import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 自定义词书数量上限：挡住个别用户无限建书把服务端数据撑大。
void main() {
  late MyDatabase db;
  const userId = 'custom_dict_limit_user';

  setUp(() {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
  });

  tearDown(() async {
    // createCustomDict 成功后会安排一次同步定时器，先取消再关库
    ThrottledDbSyncService().reset();
    await db.close();
  });

  Future<void> seedDict(String id, String name) async {
    final now = AppClock.now();
    await db.dictsDao.saveEntity(
      Dict(
        id: id,
        isReady: true,
        isShared: false,
        name: name,
        wordCount: 0,
        ownerId: userId,
        visible: true,
        editable: true,
        deletable: true,
        createTime: now,
        updateTime: now,
      ),
      false,
    );
  }

  /// 直接写库补齐到「上限本自建词书」，避免为了建库反复触发同步
  Future<void> seedCustomDicts(int count) async {
    for (var i = 0; i < count; i++) {
      await seedDict('custom-$i', '自建词书$i');
    }
  }

  test('生词本与已掌握不占自建词书额度', () async {
    await seedDict('raw', '生词本');
    await seedDict('mastered', '已掌握');
    await seedCustomDicts(WordBo.maxCustomDictCount - 1);

    final result = await WordBo().createCustomDict('最后一本', userId);

    expect(result.success, isTrue, reason: '系统词书不该计入上限，这里应该还能建一本');
  });

  test('建满上限后再建被拒绝，提示里带上上限数', () async {
    await seedDict('raw', '生词本');
    await seedDict('mastered', '已掌握');
    await seedCustomDicts(WordBo.maxCustomDictCount);

    final result = await WordBo().createCustomDict('再建一本', userId);

    expect(result.success, isFalse);
    expect(result.msg, contains('${WordBo.maxCustomDictCount}'));
    expect(
      (await (db.select(db.dicts)..where((d) => d.ownerId.equals(userId))).get())
          .where((d) => !WordBo.isSystemOwnedDictName(d.name))
          .length,
      WordBo.maxCustomDictCount,
      reason: '被拒绝后不应留下新词书',
    );
  });
}
