import 'package:json_annotation/json_annotation.dart';

class CustomDateTimeConverter implements JsonConverter<DateTime?, String?> {
  const CustomDateTimeConverter();

  @override
  DateTime? fromJson(String? json) {
    if (json == null) return null;
    // Backend now returns ISO8601 with timezone (e.g. +08:00)
    // DateTime.parse handles it correctly. No manual offset needed.
    return DateTime.parse(json);
  }

  @override
  String? toJson(DateTime? json) => json?.toIso8601String();
}
