import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => [],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('sys_db_version 为空时，DataIntegrityChecker 检出 sys_db_version_integrity 问题', () async {
    final checker = DataIntegrityChecker();
    final result = await checker.performFullCheck();

    expect(result.hasIssue('sys_db_version_integrity'), isTrue,
        reason: '母版库若未初始化 sys_db_version，健康自检必须拦截并报错');
    final issue = result.issues.firstWhere((i) => i.category == 'sys_db_version_integrity');
    expect(issue.type, '系统数据版本未初始化');
  });

  test('sys_db_version 已正确初始化版本号时，sys_db_version_integrity 检查通过', () async {
    await db.sysDbVersionDao.saveVersion(
      SysDbVersionData(
        id: 'singleton',
        version: 714867,
        lastSyncTime: AppClock.now(),
        createTime: AppClock.now(),
        updateTime: AppClock.now(),
      ),
    );

    final checker = DataIntegrityChecker();
    final result = await checker.performFullCheck();

    expect(result.hasIssue('sys_db_version_integrity'), isFalse,
        reason: '已初始化 sys_db_version 的数据库自检不应包含该 issue');
  });
}
