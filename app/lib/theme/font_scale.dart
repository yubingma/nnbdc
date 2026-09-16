import 'package:flutter/painting.dart';

/// 全局字体大小档位（小 / 中 / 大）。
///
/// [factor] 在系统字号之上叠加：中档为 1.0，系统字号为默认值时完全不改变既有排版。
enum AppFontScale {
  small('small', '小', 0.9),
  medium('medium', '中', 1.0),
  large('large', '大', 1.15);

  final String code;
  final String label;
  final double factor;

  const AppFontScale(this.code, this.label, this.factor);

  static AppFontScale fromCode(String? code) {
    for (final scale in AppFontScale.values) {
      if (scale.code == code) return scale;
    }
    return AppFontScale.medium;
  }

  /// 在 [base]（系统字号）之上叠加本档位系数，得到全局生效的 [TextScaler]。
  ///
  /// 逐字号委派而非套用 [TextScaler.linear]：后者会丢弃系统非线性字号的逐字号信息。
  static TextScaler compose(TextScaler base, AppFontScale scale) {
    if (scale.factor == 1.0) return base;
    return _ScaledTextScaler(base, scale.factor);
  }
}

final class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
