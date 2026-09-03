import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:nnbdc/global.dart';

class Prefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    pronunciationAccentNotifier.value = pronunciationAccent;
    await _migrateFromGetStorage();
  }

  /// 一次性迁移逻辑：从 GetStorage.gs 文件读取旧数据并存入 SharedPreferences
  static Future<void> _migrateFromGetStorage() async {
    // 如果已经迁移过，直接返回
    if (read<bool>('_gs_migrated') == true) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final gsFile = File('${docDir.path}/GetStorage.gs');

      if (await gsFile.exists()) {
        final content = await gsFile.readAsString();
        if (content.isNotEmpty) {
          final dynamic data = jsonDecode(content);
          if (data is Map<String, dynamic>) {
            for (final entry in data.entries) {
              final key = entry.key;
              final val = entry.value;
              if (val is String) {
                await write(key, val);
              } else if (val is int) {
                await write(key, val);
              } else if (val is double) {
                await write(key, val);
              } else if (val is bool) {
                await write(key, val);
              } else if (val is List) {
                // 如果是字符串列表
                if (val.every((e) => e is String)) {
                  await write(key, val.cast<String>());
                } else {
                  // 其他复杂对象暂转 json 字符串
                  await write(key, jsonEncode(val));
                }
              } else {
                await write(key, jsonEncode(val));
              }
            }
          }
        }
      }
      // 标记迁移完成
      await write('_gs_migrated', true);
    } catch (e) {
      Global.logger.e('Failed to migrate from GetStorage: $e');
    }
  }

  static T? read<T>(String key) {
    if (_prefs == null) return null;
    return _prefs!.get(key) as T?;
  }

  static Future<bool> write(String key, dynamic value) async {
    if (_prefs == null) return false;
    if (value is String) return await _prefs!.setString(key, value);
    if (value is int) return await _prefs!.setInt(key, value);
    if (value is double) return await _prefs!.setDouble(key, value);
    if (value is bool) return await _prefs!.setBool(key, value);
    if (value is List<String>) return await _prefs!.setStringList(key, value);
    return false;
  }

  static Future<bool> remove(String key) async {
    if (_prefs == null) return false;
    return _prefs!.remove(key);
  }

  static Future<bool> clear() async {
    if (_prefs == null) return false;
    return _prefs!.clear();
  }

  static bool hasKey(String key) {
    if (_prefs == null) return false;
    return _prefs!.containsKey(key);
  }

  /// 发音口音偏好键:"us"(美音,默认) / "uk"(英音)
  static const String pronunciationAccentKey = 'pronunciation_accent';

  /// 发音口音响应式通知器
  static final ValueNotifier<String> pronunciationAccentNotifier =
      ValueNotifier<String>(pronunciationAccent);

  /// 读取发音口音偏好,默认美音
  static String get pronunciationAccent => read<String>(pronunciationAccentKey) ?? 'us';

  /// 设置发音口音偏好
  static Future<bool> setPronunciationAccent(String accent) async {
    final ok = await write(pronunciationAccentKey, accent);
    if (pronunciationAccentNotifier.value != accent) {
      pronunciationAccentNotifier.value = accent;
    }
    return ok;
  }

  /// 快速切换发音口音偏好 (us <-> uk)
  static Future<String> togglePronunciationAccent() async {
    final next = pronunciationAccent == 'uk' ? 'us' : 'uk';
    await setPronunciationAccent(next);
    return next;
  }
}
