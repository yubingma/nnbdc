import 'dart:async';
import 'dart:isolate';

import 'package:nnbdc/db/dict_import_isolate.dart';

/// 常驻后台导入 Worker（非 Web）
///
/// 目的：避免每次导入都 Isolate.spawn 导致 UI 在 20% 附近卡顿 3~4 秒。
class DictImportWorker {
  DictImportWorker._();

  static final DictImportWorker instance = DictImportWorker._();

  SendPort? _workerPort;
  Future<void>? _starting;

  Future<void> ensureStarted() {
    if (_workerPort != null) return Future.value();
    _starting ??= _start();
    return _starting!;
  }

  Future<void> _start() async {
    final readyPort = ReceivePort();
    await Isolate.spawn(dictImportWorkerMain, readyPort.sendPort);
    final sp = await readyPort.first;
    _workerPort = sp as SendPort;
    readyPort.close();
  }

  /// 提交一个导入任务，返回一个消息流（Map）
  ///
  /// 消息格式与 `dict_import_isolate.dart` 一致：
  /// - {type: phase, value: ...}
  /// - {type: progress, value: 0~1}
  /// - {type: done}
  /// - {type: error, message: ...}
  Stream<Map> submit({required String dbPath, required String filePath}) async* {
    await ensureStarted();
    final reply = ReceivePort();
    _workerPort!.send({
      'replyPort': reply.sendPort,
      'dbPath': dbPath,
      'filePath': filePath,
    });

    await for (final msg in reply) {
      if (msg is Map) {
        yield msg;
        final type = msg['type'];
        if (type == 'done' || type == 'error') {
          reply.close();
          break;
        }
      }
    }
  }
}
