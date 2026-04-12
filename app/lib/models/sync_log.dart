import 'dart:convert';

/// 同步日志记录
/// 用于记录每次云同步的详细信息
class SyncLog {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMs;
  final bool success;
  final String? errorMessage;
  final int? uploadCount;
  final int? downloadCount;
  final Map<String, dynamic>? uploadDetails;
  final Map<String, dynamic>? downloadDetails;
  final String? userId;
  final int? dbVersion;
  final String? appVersion;

  SyncLog({
    required this.id,
    required this.startTime,
    this.endTime,
    this.durationMs,
    required this.success,
    this.errorMessage,
    this.uploadCount,
    this.downloadCount,
    this.uploadDetails,
    this.downloadDetails,
    this.userId,
    this.dbVersion,
    this.appVersion,
  });

  factory SyncLog.fromJson(Map<String, dynamic> json) {
    return SyncLog(
      id: json['id'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      durationMs: json['durationMs'] as int?,
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
      uploadCount: json['uploadCount'] as int?,
      downloadCount: json['downloadCount'] as int?,
      uploadDetails: json['uploadDetails'] as Map<String, dynamic>?,
      downloadDetails: json['downloadDetails'] as Map<String, dynamic>?,
      userId: json['userId'] as String?,
      dbVersion: json['dbVersion'] as int?,
      appVersion: json['appVersion'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'durationMs': durationMs,
      'success': success,
      'errorMessage': errorMessage,
      'uploadCount': uploadCount,
      'downloadCount': downloadCount,
      'uploadDetails': uploadDetails,
      'downloadDetails': downloadDetails,
      'userId': userId,
      'dbVersion': dbVersion,
      'appVersion': appVersion,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory SyncLog.fromJsonString(String jsonString) {
    return SyncLog.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// 创建一个新的同步日志（开始同步时调用）
  factory SyncLog.start({required String id, required DateTime startTime, String? userId, String? appVersion}) {
    return SyncLog(
      id: id,
      startTime: startTime,
      success: false, // 开始时默认为失败，完成后更新
      userId: userId,
      dbVersion: null,
      appVersion: appVersion,
    );
  }

  /// 完成同步（成功时调用）
  SyncLog complete({
    required DateTime endTime,
    required int uploadCount,
    required int downloadCount,
    Map<String, dynamic>? uploadDetails,
    Map<String, dynamic>? downloadDetails,
    int? dbVersion,
  }) {
    return SyncLog(
      id: id,
      startTime: startTime,
      endTime: endTime,
      durationMs: endTime.difference(startTime).inMilliseconds,
      success: true,
      uploadCount: uploadCount,
      downloadCount: downloadCount,
      uploadDetails: uploadDetails,
      downloadDetails: downloadDetails,
      userId: userId,
      dbVersion: dbVersion,
      appVersion: appVersion,
    );
  }

  /// 标记同步失败
  SyncLog fail({
    required DateTime endTime,
    required String errorMessage,
  }) {
    return SyncLog(
      id: id,
      startTime: startTime,
      endTime: endTime,
      durationMs: endTime.difference(startTime).inMilliseconds,
      success: false,
      errorMessage: errorMessage,
      userId: userId,
      dbVersion: null,
      appVersion: appVersion,
    );
  }

  bool get isWarning => !success && errorMessage != null && errorMessage!.contains('下次修复');

  @override
  String toString() {
    return 'SyncLog(id: $id, startTime: $startTime, success: $success, isWarning: $isWarning, durationMs: $durationMs, upload: $uploadCount, download: $downloadCount, dbVersion: $dbVersion, appVersion: $appVersion, uploadDetails: $uploadDetails, downloadDetails: $downloadDetails)';
  }
}
