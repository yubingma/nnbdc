import 'dart:convert';

class BdcPageArgs {
  /// 从哪个页面进入本页面
  String? fromPage;

  BdcPageArgs(this.fromPage);

  Map<String, dynamic> toMap() {
    return {
      "fromPage": fromPage,
    };
  }

  String toJson() => json.encode(toMap());

  factory BdcPageArgs.fromMap(Map<String, dynamic> map) {
    return BdcPageArgs(
      map["fromPage"],
    );
  }

  factory BdcPageArgs.fromJson(String value) {
    return BdcPageArgs.fromMap(json.decode(value));
  }
}
