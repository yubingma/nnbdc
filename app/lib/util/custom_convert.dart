import 'package:json_annotation/json_annotation.dart';

class CustomDateTimeConverter implements JsonConverter<DateTime, Object> {
  const CustomDateTimeConverter();

  @override
  DateTime fromJson(Object json) {
    if (json is String) {
      return DateTime.parse(json);
    } else if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    }
    throw ArgumentError('Unknown json type: ${json.runtimeType} ($json) for CustomDateTimeConverter');
  }

  @override
  Object toJson(DateTime json) => json.toIso8601String();
}

class NullableDateTimeConverter implements JsonConverter<DateTime?, Object?> {
  const NullableDateTimeConverter();

  @override
  DateTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is String) {
      if (json.isEmpty) return null;
      return DateTime.parse(json);
    } else if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    }
    throw ArgumentError('Unknown json type: ${json.runtimeType} ($json) for NullableDateTimeConverter');
  }

  @override
  Object? toJson(DateTime? json) => json?.toIso8601String();
}
