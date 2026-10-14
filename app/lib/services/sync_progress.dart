import 'package:flutter/foundation.dart';

/// 端云同步的实时进度快照。
///
/// 首屏在等端云同步时此前只有一个转圈，用户无法分辨"同步还在推进"和"已经卡死"。
/// 这里把同步当前所处的阶段与已处理条数广播出去，由加载态直接展示：
/// 数字在跳就是在同步，数字长时间不动就是真的卡住了。
@immutable
class SyncProgress {
  const SyncProgress({required this.phase, this.done = 0, this.total = 0});

  /// 空闲：当前没有端云同步在进行。
  const SyncProgress.idle() : phase = '', done = 0, total = 0;

  /// 阶段说明，例如「WRITING LOCAL DATA」；为空表示空闲。
  final String phase;

  /// 当前阶段已处理的条数。
  final int done;

  /// 当前阶段的总条数；未知时为 0。
  final int total;

  bool get isIdle => phase.isEmpty;

  /// 当前阶段是否已知总量（决定 UI 显示「3120 / 8621」还是只显示已处理条数）。
  bool get hasTotal => total > 0;

  @override
  bool operator ==(Object other) =>
      other is SyncProgress && other.phase == phase && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);
}

/// 端云同步进度的全局广播口（同一时刻只会有一轮同步在跑）。
final ValueNotifier<SyncProgress> syncProgress =
    ValueNotifier<SyncProgress>(const SyncProgress.idle());
