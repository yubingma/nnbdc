import 'dart:async';

import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/models/external_import_file.dart';
import 'package:nnbdc/page/word_list/import_from_excel_page.dart';

import '../router.dart';

/// 接收外部应用通过「用其他应用打开」传入的 Excel 文件。
///
/// 原生侧（Android 的 ACTION_VIEW / ACTION_SEND、iOS 的 document types）
/// 把文件复制到应用私有目录后，通过 MethodChannel 交来路径：
/// - 冷启动：原生先缓存，Flutter 用户态就绪后由 [startHandling] 主动取走；
/// - 热启动：原生通过 `onFileReceived` 推送。
class ExternalFileService {
  const ExternalFileService._();

  static const MethodChannel _channel = MethodChannel('nnbdc/external_file');

  static final StreamController<ExternalImportFile> _received =
      StreamController<ExternalImportFile>.broadcast();

  static StreamSubscription<ExternalImportFile>? _subscription;
  static ExternalImportFile? _deferred;
  static bool _initialized = false;

  /// 注册原生回调。应在 runApp 之前尽早调用，避免热启动推送在 handler 就位前丢失。
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileReceived') {
        final file = _parse(call.arguments);
        if (file != null) _received.add(file);
      }
      return null;
    });
  }

  /// 用户态就绪后调用：响应运行期推送，并处理冷启动遗留下的文件。
  static Future<void> startHandling() async {
    _subscription ??= _received.stream.listen(_handle);

    final deferred = _deferred;
    if (deferred != null) {
      _deferred = null;
      _handle(deferred);
      return;
    }

    final initial = await _takeInitialFile();
    if (initial != null) _handle(initial);
  }

  static Future<ExternalImportFile?> _takeInitialFile() async {
    try {
      return _parse(await _channel.invokeMethod<dynamic>('getInitialFile'));
    } catch (e) {
      Global.logger.w('读取外部导入文件失败: $e');
      return null;
    }
  }

  static ExternalImportFile? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final name = raw['name'];
    if (path is! String || name is! String || path.isEmpty) return null;
    return ExternalImportFile(name: name, path: path);
  }

  static void _handle(ExternalImportFile file) {
    // 登录态未就绪时先暂存，避免把用户刚分享过来的文件丢掉
    if (Global.getLoggedInUser() == null) {
      _deferred = file;
      Global.logger.w('登录态未就绪，暂存外部导入文件: ${file.name}');
      return;
    }
    goRouter.push('/import_from_excel', extra: ExcelImportArgs(file: file));
  }
}
