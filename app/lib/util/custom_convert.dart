import 'package:json_annotation/json_annotation.dart';

class CustomDateTimeConverter implements JsonConverter<DateTime, String> {
  const CustomDateTimeConverter();

  @override
  DateTime fromJson(String json) {
    // 直接解析，避免无意义的条件判断
    return DateTime.parse(json).add(const Duration(hours: 8));
  }

  @override
  String toJson(DateTime json) => json.toIso8601String();
}
