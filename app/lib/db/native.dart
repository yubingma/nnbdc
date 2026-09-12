import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

MyDatabase constructDb() {
  final db = LazyDatabase(() async {
    Directory dbFolder;
    dbFolder = await getApplicationDocumentsDirectory();

    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    // 数据库放到独立 isolate: Flutter 在 Android 已将 UI 线程合并到主线程,
    // 在主 isolate 打开数据库会让事务提交的 fsync 直接阻塞主线程(表现为 ANR)
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode=WAL;');
        rawDb.execute('PRAGMA busy_timeout=5000;');
      },
    );
  });
  return MyDatabase(db);
}
