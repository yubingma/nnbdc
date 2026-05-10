import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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
