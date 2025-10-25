import 'dart:core';

import 'package:json_annotation/json_annotation.dart';

part 'result.g.dart';

@JsonSerializable(genericArgumentFactories: true)
class Result<T> {
  String code;
  String? msg;
  bool success;

  T? data;

  Result(this.code, this.msg, this.success);

  factory Result.fromJson(Map<String, dynamic> json, T Function(Object? json) fromJsonT) => _$ResultFromJson(json, fromJsonT);

  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) => _$ResultToJson(this, toJsonT);

  @override
  String toString() {
    return "Result{code: $code, msg: $msg, success: $success, data: $data}";
  }
}

@JsonSerializable(genericArgumentFactories: true)
class PagedResults<T> {
  /// 记录总数（所有数据页的记录总数，而不是当前页的记录数）
  int total;

  /// 当前页的记录
  List<T> rows = [];

  PagedResults(this.total);

  factory PagedResults.fromJson(Map<String, dynamic> json, T Function(Object? json) fromJsonT) =>
      _$PagedResultsFromJson(json, fromJsonT);

  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) => _$PagedResultsToJson(this, toJsonT);
}
