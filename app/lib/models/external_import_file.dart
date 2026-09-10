import 'dart:io';
import 'dart:typed_data';

/// 外部应用（微信、文件管理器等）通过「用其他应用打开」传入的文件。
///
/// 原生侧会把文件复制到应用私有缓存目录，这里只持有副本路径，
/// 避免受 Android 分区存储（content:// URI 不可直接读）影响。
class ExternalImportFile {
  final String name;
  final String path;

  const ExternalImportFile({required this.name, required this.path});

  Future<Uint8List> readBytes() => File(path).readAsBytes();
}
