import 'dart:convert';

import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/prefs.dart';

/// 某个环节里"已经出过题"的词集合（按业务日隔离）。
///
/// 用途只有一个：让学习页「第 N 组 · 轨道 · 环节 x/y」的分子成为**出题进度**，
/// 从而"每见到一个新词就前进一格"，而不是"已走完本环节的词数 + 1"
///（后者在本环节第一个词点「不认识」时会一直停在 1/10，用户看着像序号坏了）。
///
/// 为什么必须单独记录：同一环节里"答错待重练的词"与"还没轮到的词"在 `learning_word`
/// 上完全同态（`todayLearnedTimes` 都等于当前环节序号），评分流水里也没有"第几次出题"，
/// 仅凭库里的数据无法区分两者。
///
/// 边界与取舍：
/// - **只用于显示**，绝不参与调度、判分与进度推进；读写失败一律退化为"没记录过"。
/// - 按业务日隔离，跨天自动作废（读的时候先比对业务日），无需清理历史。
/// - 只在用户完成一个环节、或本组结束时清一次，避免同日重排计划后旧记录残留。
class PhasePresentationTracker {
  PhasePresentationTracker._();

  /// 存储键。内容是 {"businessDay": "...", "presented": {"<第N组#轨道#环节序号>": ["wordId", ...]}}
/// 键里必须带**组号**：同一轨道同一环节序号在不同组里是不同的队列
///（如第 1 组的"新词答对/汉译英"与第 2 组的同名环节），不区分就会把第 2 组的词算进第 1 组。
  static const String _prefsKey = 'presented_words_in_phase';

  /// 把某个词记为"在本轨道本环节已经出过题"（同一业务日内重复调用只会记一次）
  static Future<void> markPresented({
    required int groupNo,
    required String trackName,
    required int stepIndex,
    required String wordId,
  }) async {
    if (trackName.isEmpty || wordId.isEmpty) return;
    try {
      final data = _readRaw();
      final key = setKey(groupNo, trackName, stepIndex);
      final set = Set<String>.from(data[key] ?? const []);
      if (!set.add(wordId)) return; // 已经在里面，不必写盘
      data[key] = set.toList();
      await _writeRaw(data);
    } catch (e) {
      // 展示用记录，失败不影响学习
    }
  }

  /// 该环节已出过题的词数（不含未记录过的词）
  static int presentedCount({
    required int groupNo,
    required String trackName,
    required int stepIndex,
  }) {
    if (trackName.isEmpty) return 0;
    return _readRaw()[setKey(groupNo, trackName, stepIndex)]?.length ?? 0;
  }

  /// 清空全部记录（用户完成一个环节、或本组结束时调用）
  static Future<void> clear() async {
    try {
      await Prefs.remove(_prefsKey);
    } catch (e) {
      // 忽略
    }
  }

  /// 供测试与排查：某环节已出过题的词 id 集合
  static Set<String> presentedWordIds({
    required int groupNo,
    required String trackName,
    required int stepIndex,
  }) {
    return Set<String>.from(_readRaw()[setKey(groupNo, trackName, stepIndex)] ?? const []);
  }

  static String setKey(int groupNo, String trackName, int stepIndex) =>
      '$groupNo#$trackName#$stepIndex';

  /// 读取"今天"的记录；业务日不同（也就是昨天留下的）时直接当空，实现自动作废
  static Map<String, List<String>> _readRaw() {
    try {
      final raw = Prefs.read<String>(_prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      final businessDay = DateUtils.businessDayStart(AppClock.now()).toIso8601String();
      if (decoded['businessDay'] != businessDay) return {};
      final presented = decoded['presented'];
      if (presented is! Map) return {};
      final result = <String, List<String>>{};
      presented.forEach((key, value) {
        if (value is List) {
          result['$key'] = value.map((e) => '$e').toList();
        }
      });
      return result;
    } catch (e) {
      return {};
    }
  }

  static Future<void> _writeRaw(Map<String, List<String>> presented) async {
    final businessDay = DateUtils.businessDayStart(AppClock.now()).toIso8601String();
    await Prefs.write(
      _prefsKey,
      json.encode({'businessDay': businessDay, 'presented': presented}),
    );
  }
}
