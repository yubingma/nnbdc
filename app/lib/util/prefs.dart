import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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
          final Map<String, dynamic> data = json.decode(content);
          
          for (var entry in data.entries) {
            final key = entry.key;
            final value = entry.value;
            
            // 写入 SharedPreferences
            if (value is String) {
              await _prefs?.setString(key, value);
            } else if (value is int) {
              await _prefs?.setInt(key, value);
            } else if (value is bool) {
              await _prefs?.setBool(key, value);
            } else if (value is double) {
              await _prefs?.setDouble(key, value);
            } else if (value is List) {
              // 尝试转换 List<String>
              try {
                await _prefs?.setStringList(key, value.cast<String>());
              } catch (_) {}
            }
          }
        }
        // 标记迁移完成（不立即删除旧文件，以防万一，但标记状态）
        await write('_gs_migrated', true);
        // 迁移成功后可以考虑重命名文件，防止下次重复处理
        await gsFile.rename('${docDir.path}/GetStorage.gs.bak');
      } else {
        // 如果文件不存在，也标记为已迁移，避免重复检查 IO
        await write('_gs_migrated', true);
      }
    } catch (e) {
      // 记录错误但不中断启动
      print('Migration from GetStorage failed: $e');
    }
  }

  static T? read<T>(String key) {
    if (_prefs == null) return null;
    final value = _prefs!.get(key);
    if (value is T) return value;
    return null;
  }

  static Future<bool> write(String key, dynamic value) async {
    if (_prefs == null) return false;
    if (value is String) return _prefs!.setString(key, value);
    if (value is int) return _prefs!.setInt(key, value);
    if (value is bool) return _prefs!.setBool(key, value);
    if (value is double) return _prefs!.setDouble(key, value);
    if (value is List<String>) return _prefs!.setStringList(key, value);
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
}
