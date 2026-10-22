import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:nnbdc/global.dart';

class Prefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    pronunciationAccentNotifier.value = pronunciationAccent;
    hiddenBottomNavKeysNotifier.value = hiddenBottomNavKeys;
    bottomNavShortcutKeysNotifier.value = bottomNavShortcutKeys;
    fullScreenNotifier.value = isFullScreen;
    await _migrateFromGetStorage();
    await applyFullScreenMode();
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
    final isStringList = T == _typeOf<List<String>>() || T == _typeOf<List<String>?>();
    if (isStringList) {
      return _prefs!.getStringList(key) as T?;
    }
    final val = _prefs!.get(key);
    if (val is List && isStringList) {
      return val.cast<String>() as T?;
    }
    return val as T?;
  }

  static Type _typeOf<X>() => X;

  static List<String>? getStringList(String key) {
    if (_prefs == null) return null;
    return _prefs!.getStringList(key);
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

  /// 底栏隐藏按键偏好键
  static const String hiddenBottomNavKeysPref = 'hidden_bottom_nav_keys';

  /// 底栏隐藏按键响应式通知器
  static final ValueNotifier<List<String>> hiddenBottomNavKeysNotifier =
      ValueNotifier<List<String>>(hiddenBottomNavKeys);

  /// 读取底栏隐藏按键列表
  static List<String> get hiddenBottomNavKeys {
    if (_prefs == null) return [];
    return _prefs!.getStringList(hiddenBottomNavKeysPref) ?? [];
  }

  /// 保存底栏隐藏按键列表
  static Future<bool> setHiddenBottomNavKeys(List<String> keys) async {
    final ok = await write(hiddenBottomNavKeysPref, keys);
    hiddenBottomNavKeysNotifier.value = List<String>.unmodifiable(keys);
    return ok;
  }

  /// 已放进底栏的唤起型入口偏好键
  static const String bottomNavShortcutKeysPref = 'bottom_nav_shortcut_keys';

  /// 已放进底栏的唤起型入口响应式通知器
  static final ValueNotifier<List<String>> bottomNavShortcutKeysNotifier =
      ValueNotifier<List<String>>(bottomNavShortcutKeys);

  /// 读取已放进底栏的唤起型入口列表
  static List<String> get bottomNavShortcutKeys {
    if (_prefs == null) return [];
    return _prefs!.getStringList(bottomNavShortcutKeysPref) ?? [];
  }

  /// 保存已放进底栏的唤起型入口列表
  static Future<bool> setBottomNavShortcutKeys(List<String> keys) async {
    final ok = await write(bottomNavShortcutKeysPref, keys);
    bottomNavShortcutKeysNotifier.value = List<String>.unmodifiable(keys);
    return ok;
  }

  /// 全屏模式偏好键
  static const String fullScreenModePref = 'full_screen_mode';

  /// 全屏模式响应式通知器
  static final ValueNotifier<bool> fullScreenNotifier =
      ValueNotifier<bool>(isFullScreen);

  /// 读取全屏模式偏好，默认开启
  static bool get isFullScreen => read<bool>(fullScreenModePref) ?? true;

  /// 是否隐藏中小学教育类内容（K12 词书分组与游戏大厅）。
  /// 由服务端参数 hideK12Content 控制，系统管理员在后台开关，客户端启动时拉取。
  static bool get hideK12Content => read<bool>('hideK12Content') ?? false;

  static Future<void> setHideK12Content(bool value) =>
      write('hideK12Content', value);

  /// 设置全屏模式偏好并立即应用
  static Future<bool> setFullScreen(bool enabled) async {
    final ok = await write(fullScreenModePref, enabled);
    if (fullScreenNotifier.value != enabled) {
      fullScreenNotifier.value = enabled;
    }
    await applyFullScreenMode(enabled);
    return ok;
  }

  /// 快速切换全屏模式
  static Future<bool> toggleFullScreen() async {
    final next = !isFullScreen;
    await setFullScreen(next);
    return next;
  }

  /// 应用全屏状态到系统 UI（方案 A：沉浸式粘性全屏 SystemUiMode.immersiveSticky）
  static Future<void> applyFullScreenMode([bool? enabled]) async {
    final isFull = enabled ?? isFullScreen;
    try {
      if (isFull) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (e) {
      Global.logger.w('应用全屏模式失败: $e');
    }
  }
}
