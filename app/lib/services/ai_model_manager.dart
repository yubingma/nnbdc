import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AiModelProfile {
  mobileLite,
  desktopFull,
}

class AiModelMeta {
  final String id;
  final AiModelProfile profile;
  final String version;
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final String checksum;

  AiModelMeta({
    required this.id,
    required this.profile,
    required this.version,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.checksum,
  });

  factory AiModelMeta.fromJson(Map<String, dynamic> json, AiModelProfile profile) {
    return AiModelMeta(
      id: json['id'] as String? ?? '',
      profile: profile,
      version: json['version'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'model.bin',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : int.tryParse('${json['sizeBytes']}') ?? 0,
      checksum: json['checksum'] as String? ?? '',
    );
  }
}

class AiModelLocalState {
  final String id;
  final String version;
  final AiModelProfile profile;
  final String localPath;
  final int sizeBytes;

  AiModelLocalState({
    required this.id,
    required this.version,
    required this.profile,
    required this.localPath,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'profile': profile.name,
      'localPath': localPath,
      'sizeBytes': sizeBytes,
    };
  }

  factory AiModelLocalState.fromJson(Map<String, dynamic> json) {
    final profileName = json['profile'] as String? ?? AiModelProfile.mobileLite.name;
    final profile = AiModelProfile.values.firstWhere(
      (e) => e.name == profileName,
      orElse: () => AiModelProfile.mobileLite,
    );
    return AiModelLocalState(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      profile: profile,
      localPath: json['localPath'] as String? ?? '',
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : int.tryParse('${json['sizeBytes']}') ?? 0,
    );
  }
}

class AiModelManager {
  static final AiModelManager _instance = AiModelManager._internal();

  factory AiModelManager() => _instance;

  AiModelManager._internal();

  AiModelLocalState? _cachedState;

  Future<Directory> _getModelRootDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(supportDir.path, 'ai_models'));
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }
    return modelsDir;
  }

  Future<File> _getStateFile() async {
    final dir = await _getModelRootDir();
    return File(p.join(dir.path, 'model_state.json'));
  }

  String get _metaUrl {
    // 生产环境：使用服务器配置的 URL
    Global.logger.d('使用服务器模型元数据: ${Config.aiModelUrl}');
    return Config.aiModelUrl;
  }

  Future<Map<AiModelProfile, AiModelMeta>> fetchRemoteMeta() async {
    final result = <AiModelProfile, AiModelMeta>{};
    try {
      final metaUrl = _metaUrl;
      String jsonContent;

      if (metaUrl.startsWith('file://')) {
        final filePath = metaUrl.substring(7);
        final file = File(filePath);
        if (!file.existsSync()) {
          Global.logger.w('本地模型元数据文件不存在: $filePath');
          return result;
        }
        jsonContent = await file.readAsString();
      } else {
        final uri = Uri.parse(metaUrl);
        final resp = await http.get(uri);
        if (resp.statusCode != 200) {
          Global.logger.w('获取 AI 模型元数据失败，状态码: ${resp.statusCode}');
          return result;
        }
        jsonContent = resp.body;
      }

      final data = jsonDecode(jsonContent);
      if (data is Map<String, dynamic>) {
        for (final profile in AiModelProfile.values) {
          final key = profile.name;
          final value = data[key];
          if (value is Map<String, dynamic>) {
            result[profile] = AiModelMeta.fromJson(value, profile);
          }
        }
      }
    } catch (e, st) {
      Global.logger.e('获取 AI 模型元数据异常', error: e, stackTrace: st);
    }
    return result;
  }

  Future<AiModelLocalState?> loadLocalState() async {
    if (_cachedState != null) {
      return _cachedState;
    }
    try {
      final file = await _getStateFile();
      if (!file.existsSync()) {
        return null;
      }
      final content = await file.readAsString();
      if (content.isEmpty) {
        return null;
      }
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      _cachedState = AiModelLocalState.fromJson(jsonMap);
      return _cachedState;
    } catch (e, st) {
      Global.logger.e('读取本地 AI 模型状态失败', error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> _saveLocalState(AiModelLocalState state) async {
    try {
      final file = await _getStateFile();
      await file.writeAsString(jsonEncode(state.toJson()));
      _cachedState = state;
    } catch (e, st) {
      Global.logger.e('保存本地 AI 模型状态失败', error: e, stackTrace: st);
    }
  }

  Future<AiModelLocalState?> ensureModel(
    AiModelProfile profile, {
    void Function(double progress, int downloaded, int total)? onProgress,
  }) async {
    final current = await loadLocalState();
    if (current != null && current.profile == profile && current.localPath.isNotEmpty) {
      final file = File(current.localPath);
      if (file.existsSync()) {
        return current;
      }
    }

    final remoteMetas = await fetchRemoteMeta();
    final meta = remoteMetas[profile];
    if (meta == null) {
      Global.logger.w('远端未提供 profile=${profile.name} 的模型元数据');
      return null;
    }

    final localPath = await _downloadModel(meta, onProgress: onProgress);
    if (localPath == null) {
      return null;
    }

    final file = File(localPath);
    final size = await file.length();
    final state = AiModelLocalState(
      id: meta.id,
      version: meta.version,
      profile: profile,
      localPath: localPath,
      sizeBytes: size,
    );
    await _saveLocalState(state);
    return state;
  }

  Future<String?> _downloadModel(
    AiModelMeta meta, {
    void Function(double progress, int downloaded, int total)? onProgress,
  }) async {
    try {
      final dir = await _getModelRootDir();
      final filePath = p.join(dir.path, meta.fileName);
      final file = File(filePath);

      // 如果是本地文件 URL (file://...)，直接复制
      if (meta.downloadUrl.startsWith('file://')) {
        final sourcePathStr = meta.downloadUrl.substring(7);
        final sourceFile = File(sourcePathStr);
        if (!sourceFile.existsSync()) {
          Global.logger.w('本地模型文件不存在: $sourcePathStr');
          return null;
        }
        // 如果目标文件已存在且大小一致，直接返回
        if (file.existsSync()) {
          final existingSize = await file.length();
          final sourceSize = await sourceFile.length();
          if (existingSize == sourceSize) {
            Global.logger.i('模型文件已存在且完整: $filePath');
            return filePath;
          }
        }
        // 复制文件
        Global.logger.i('复制本地模型文件: $sourcePathStr -> $filePath');
        await sourceFile.copy(filePath);
        return filePath;
      }

      // 网络下载
      // 检查文件是否已存在且大小正确
      if (file.existsSync()) {
        final existingSize = await file.length();
        if (existingSize == meta.sizeBytes) {
          Global.logger.i('模型文件已存在且大小正确，跳过下载: $filePath');
          return filePath;
        } else {
          Global.logger.w('模型文件大小不匹配，重新下载。期望: ${meta.sizeBytes}, 实际: $existingSize');
          await file.delete();
        }
      }

      Global.logger.i('开始下载模型: ${meta.downloadUrl}');
      Global.logger.i('目标路径: $filePath');
      Global.logger.i('文件大小: ${(meta.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');

      final uri = Uri.parse(meta.downloadUrl);
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        Global.logger.w('下载 AI 模型失败，状态码: ${response.statusCode}');
        return null;
      }

      final sink = file.openWrite();
      var downloaded = 0;
      var lastLogTime = DateTime.now();
      var lastCallbackTime = DateTime.now();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        
        final now = DateTime.now();
        
        // 每 100ms 回调一次进度（给 UI 更新）
        if (onProgress != null && now.difference(lastCallbackTime).inMilliseconds >= 100) {
          final progress = downloaded / meta.sizeBytes;
          onProgress(progress, downloaded, meta.sizeBytes);
          lastCallbackTime = now;
        }
        
        // 每秒输出一次日志
        if (now.difference(lastLogTime).inSeconds >= 1) {
          final progress = (downloaded / meta.sizeBytes * 100).toStringAsFixed(1);
          final downloadedMB = (downloaded / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (meta.sizeBytes / 1024 / 1024).toStringAsFixed(1);
          Global.logger.i('下载进度: $progress% ($downloadedMB/$totalMB MB)');
          lastLogTime = now;
        }
      }

      // 最后一次进度回调
      if (onProgress != null) {
        onProgress(1.0, meta.sizeBytes, meta.sizeBytes);
      }

      await sink.flush();
      await sink.close();

      final finalSize = await file.length();
      Global.logger.i('模型下载完成！最终大小: ${(finalSize / 1024 / 1024).toStringAsFixed(1)} MB');

      return filePath;
    } catch (e, st) {
      Global.logger.e('下载 AI 模型异常', error: e, stackTrace: st);
      return null;
    }
  }
}
