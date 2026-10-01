import 'dart:convert';

import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/prefs.dart';

/// 某个环节里"已经出过题"的词，以及这些词的出题先后（按业务日隔离）。
///
/// 用途有两个：
/// 1. 让学习页「第 N 组 · 轨道 · 环节 x/y」的分子成为**出题进度**，
///    从而"每见到一个新词就前进一格"，而不是"已走完本环节的词数 + 1"
///    （后者在本环节第一个词点「不认识」时会一直停在 1/10，用户看着像序号坏了）。
/// 2. 让**同一个环节里的多个错词轮流重练**：按"最久没出过题的先出"排队，
///    而不是永远先出组内序号最小的那个错词（见 StudyBo._compareBatchWords）。
///
/// 为什么必须单独记录：同一环节里"答错待重练的词"与"还没轮到的词"在 `learning_word`
/// 上完全同态（`todayLearnedTimes` 都等于当前环节序号），评分流水里也没有"第几次出题"；
/// 而且**重练答错不写任何库**，所以"这个词刚刚被重练过"在库里同样没有痕迹 ——
/// 仅凭库里的数据既分不出"出过没出过"，也排不出先后。
///
/// 边界与取舍：
/// - 只服务于"出题进度显示"与"出题先后排序"，绝不参与判分与进度推进；
///   读写失败一律退化为"没记录过"，此时先后回落到按组内序号 `learningOrder`
///   （与没有这份记录时的行为完全一致）。
/// - 按业务日隔离，跨天自动作废（读的时候先比对业务日），无需清理历史。
/// - 只在用户完成一个环节、或本组结束时清一次，避免同日重排计划后旧记录残留。
class PhasePresentationTracker {
  PhasePresentationTracker._();

  /// 存储键。内容是
  /// `{"businessDay": "...", "presented": {"<第N组#轨道#环节序号>": ["wordId", ...]}, "order": ["wordId", ...]}`
  ///
  /// `presented` 的键里必须带**组号**：同一轨道同一环节序号在不同组里是不同的队列
  ///（如第 1 组的"新词答对/汉译英"与第 2 组的同名环节），不区分就会把第 2 组的词算进第 1 组。
  /// `order` 是全局的出题先后（最后出过题的词在末尾），服务"错词轮流重练"的排队。
  static const String _prefsKey = 'presented_words_in_phase';
  static const String _orderKey = 'order';

  /// 把某个词记为"在本轨道本环节已经出过题"，并把它挪到出题先后的末尾。
  ///
  /// 注意：**每次出题都要记**（含重练）。同一个词再次出题时 `presented` 集合不变，
  /// 但出题先后必须更新 —— 那正是"刚出过的词排到最后、先让其它待重练的词过一遍"的依据。
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
      final set = Set<String>.from(data.presented[key] ?? const []);
      final bool newlyAdded = set.add(wordId);
      // 已经在末尾且集合里也有它：记录与先后都没变，不必写盘
      if (!newlyAdded && data.order.isNotEmpty && data.order.last == wordId) return;
      final order = List<String>.from(data.order)
        ..remove(wordId)
        ..add(wordId);
      data.presented[key] = set.toList();
      await _writeRaw(data.presented, order);
    } catch (e) {
      // 展示与排序用记录，失败不影响学习
    }
  }

  /// 该环节已出过题的词数（不含未记录过的词）
  static int presentedCount({
    required int groupNo,
    required String trackName,
    required int stepIndex,
  }) {
    if (trackName.isEmpty) return 0;
    return _readRaw().presented[setKey(groupNo, trackName, stepIndex)]?.length ?? 0;
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
    return Set<String>.from(
        _readRaw().presented[setKey(groupNo, trackName, stepIndex)] ?? const []);
  }

  /// 出题先后：词 id → 名次（数字越小＝越久没出过题；表里没有＝本环节还没出过题）。
  static Map<String, int> presentationRanks() {
    final order = _readRaw().order;
    return <String, int>{for (var i = 0; i < order.length; i++) order[i]: i};
  }

  static String setKey(int groupNo, String trackName, int stepIndex) =>
      '$groupNo#$trackName#$stepIndex';

  /// 读取"今天"的记录；业务日不同（也就是昨天留下的）时直接当空，实现自动作废
  static ({Map<String, List<String>> presented, List<String> order}) _readRaw() {
    try {
      final raw = Prefs.read<String>(_prefsKey);
      if (raw == null || raw.isEmpty) return (presented: {}, order: []);
      final decoded = json.decode(raw);
      if (decoded is! Map) return (presented: {}, order: []);
      final businessDay = DateUtils.businessDayStart(AppClock.now()).toIso8601String();
      if (decoded['businessDay'] != businessDay) return (presented: {}, order: []);
      final presented = <String, List<String>>{};
      final rawPresented = decoded['presented'];
      if (rawPresented is Map) {
        rawPresented.forEach((key, value) {
          if (value is List) {
            presented['$key'] = value.map((e) => '$e').toList();
          }
        });
      }
      final order = <String>[];
      final rawOrder = decoded[_orderKey];
      if (rawOrder is List) {
        order.addAll(rawOrder.map((e) => '$e'));
      }
      return (presented: presented, order: order);
    } catch (e) {
      return (presented: {}, order: []);
    }
  }

  static Future<void> _writeRaw(
      Map<String, List<String>> presented, List<String> order) async {
    final businessDay = DateUtils.businessDayStart(AppClock.now()).toIso8601String();
    await Prefs.write(
      _prefsKey,
      json.encode({
        'businessDay': businessDay,
        'presented': presented,
        _orderKey: order,
      }),
    );
  }
}
