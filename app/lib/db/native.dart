import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

MyDatabase constructDb() {
  final db = LazyDatabase(() async {
    Directory dbFolder;
    dbFolder = await getApplicationDocumentsDirectory();

    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    void setupDb(rawDb) {
      rawDb.execute('PRAGMA journal_mode=WAL;');
      rawDb.execute('PRAGMA busy_timeout=5000;');
    }

    // 在调试模式 (kDebugMode) 或非 Android 平台下直接打开原生数据库。
    // 1. 彻底解决 VS Code 调试器在后台子 Isolate 启动时触发 "ENTRY 已暂停" 导致启动挂住的问题；
    // 2. 消除调试期间跨 Isolate 通信与序列化开销，启动速度大幅提升；
    // 3. 仅在 Android 生产/Release 环境中启用独立后台 Isolate，避免合并 UI 线程导致的 fsync ANR。
    if (kDebugMode || !Platform.isAndroid) {
      return NativeDatabase(file, setup: setupDb);
    }

    return NativeDatabase.createInBackground(
      file,
      setup: setupDb,
    );
  });
  return MyDatabase(db);
}
