import 'dart:math' as math;

import 'package:drift/drift.dart' hide Value, Column;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/privileged_dict_explanation_dialog.dart';

/// 我的书桌板块（完整版）。
///
/// 承载用户正在背的词书：词书总进度条 + 逐本词书的环形进度，
/// 以及「优先取词」「停学」两种学习管理操作。原位于「我」页，
/// 现整体迁至词表页使用。数据自持：接收书桌上的 [LearningDict] 列表，
/// 自行统计同步数据并渲染。
class MyDeskSection extends StatefulWidget {
  final List<LearningDict> learningDicts;
  final VoidCallback? onChanged;

  const MyDeskSection({super.key, required this.learningDicts, this.onChanged});

  @override
  State<MyDeskSection> createState() => _MyDeskSectionState();
}

class _MyDeskSectionState extends State<MyDeskSection> {
  _DeskData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MyDeskSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learningDicts != widget.learningDicts) {
      _load();
    }
  }

  Future<void> _load() async {
    final user = Global.getLoggedInUser();
    final db = MyDatabase.instance;

    if (user == null) {
      if (mounted) setState(() => _data = _DeskData.empty());
      return;
    }

    // 最新添加/更新的词书排在最前面
    final sorted = List<LearningDict>.from(widget.learningDicts)
      ..sort((a, b) => b.updateTime.compareTo(a.updateTime));
    final dictIds = sorted.map((ld) => ld.dictId).toList();

    int totalWords = 0;
    int masteredWords = 0;
    int learningWords = 0;
    final items = <_DeskDictItem>[];

    if (dictIds.isNotEmpty) {
      try {
        totalWords = await db.dictWordsDao.getUniqueWordCountInDicts(dictIds);
      } catch (e, st) {
        Global.logger.w('获取书桌总词数失败: $e', stackTrace: st);
      }
      try {
        masteredWords = await db.masteredWordsDao.getMasteredWordsCountInDicts(user.id, dictIds);
      } catch (e, st) {
        Global.logger.w('获取书桌已掌握词数失败: $e', stackTrace: st);
      }
      try {
        learningWords = await db.learningWordsDao.getLearningWordsCountInDicts(user.id, dictIds);
      } catch (e, st) {
        Global.logger.w('获取书桌学习中词数失败: $e', stackTrace: st);
      }

      for (final ld in sorted) {
        final dictInfo = await _resolveDict(ld.dictId);
        if (dictInfo == null) continue;
        items.add(_DeskDictItem(learningDict: ld, dictInfo: dictInfo));
      }
    }

    if (mounted) {
      setState(() => _data = _DeskData(totalWords, masteredWords, learningWords, items));
    }
  }

  /// 解析词书元数据；本地缺失时尝试从服务端补齐。
  Future<Dict?> _resolveDict(String dictId) async {
    var dictInfo = await MyDatabase.instance.dictsDao.findById(dictId);
    if (dictInfo == null) {
      try {
        final res = await Api.client.getDictInfo(dictId);
        if (res.success && res.data != null) {
          final d = res.data!;
          final newDict = Dict(
            id: d.id,
            isReady: true,
            isShared: true,
            name: d.name,
            wordCount: d.wordCount,
            ownerId: d.ownerId.isNotEmpty ? d.ownerId : Global.sysUserId,
            visible: true,
            editable: d.editable ?? false,
            deletable: d.deletable ?? true,
            baseDictId: d.baseDictId,
            createTime: d.createTime,
            updateTime: d.updateTime,
          );
          await MyDatabase.instance.dictsDao.saveEntity(newDict, false);
          dictInfo = newDict;
        }
      } catch (_) {}
    }
    return dictInfo;
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(20),
        // 与外层卡片一致：摒弃硬描边，边缘靠卡面明度 + 柔和阴影定义
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：左边「我的书桌」 + 右边轻灵「选词书 ›」
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '我的书桌',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => PrivilegedDictExplanationDialog.show(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 14,
                        color: subtitleColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  context.push("/select_book").then((value) {
                    widget.onChanged?.call();
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选词书',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: accentColor.withValues(alpha: 0.8)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 词书总进度条容器
          Builder(builder: (context) {
            final data = _data;
            final totalWords = data?.totalWords ?? 0;
            final masteredWords = data?.masteredWords ?? 0;
            final learningWords = data?.learningWords ?? 0;
            final fetchWords = masteredWords + learningWords;

            final masteryProgress = totalWords > 0 ? masteredWords / totalWords : 0.0;
            final fetchProgress = totalWords > 0 ? fetchWords / totalWords : 0.0;

            final masteryPercentText = (masteryProgress * 100).toStringAsFixed(1);
            final fetchPercentText = (fetchProgress * 100).toStringAsFixed(1);

            final masteredColor = accentColor;
            final fetchColor = accentColor.withValues(alpha: 0.6);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "学习总进度",
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '已掌握 ',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: '$masteryPercentText%',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          TextSpan(
                            text: ' · 已取词 ',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: '$fetchPercentText%',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 3.5,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final clampedMasteryProgress = masteryProgress > 1.0 ? 1.0 : masteryProgress;
                      final clampedFetchProgress = fetchProgress > 1.0 ? 1.0 : fetchProgress;
                      return Stack(
                        children: [
                          if (clampedFetchProgress > 0)
                            Container(
                              width: constraints.maxWidth * clampedFetchProgress,
                              decoration: BoxDecoration(
                                color: fetchColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          if (clampedMasteryProgress > 0)
                            Container(
                              width: constraints.maxWidth * clampedMasteryProgress,
                              decoration: BoxDecoration(
                                color: masteredColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                ),
              ],
            );
          }),
          const SizedBox(height: 12),

          // 词书列表
          if (_data == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_data!.items.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂无词书',
                style: TextStyle(color: subtitleColor, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _data!.items.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 52, right: 4),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                  DictCard(
                    key: ValueKey('desk_learning_dict_${_data!.items[i].learningDict.dictId}'),
                    learningDict: _data!.items[i].learningDict,
                    dictInfo: _data!.items[i].dictInfo,
                    onDictChanged: () => widget.onChanged?.call(),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _DeskData {
  final int totalWords;
  final int masteredWords;
  final int learningWords;
  final List<_DeskDictItem> items;

  const _DeskData(this.totalWords, this.masteredWords, this.learningWords, this.items);

  factory _DeskData.empty() => const _DeskData(0, 0, 0, []);
}

class _DeskDictItem {
  final LearningDict learningDict;
  final Dict dictInfo;

  const _DeskDictItem({required this.learningDict, required this.dictInfo});
}

class DictCard extends StatefulWidget {
  final LearningDict learningDict;
  final Dict dictInfo;
  final VoidCallback onDictChanged;

  const DictCard({
    super.key,
    required this.learningDict,
    required this.dictInfo,
    required this.onDictChanged,
  });

  @override
  State<DictCard> createState() => _DictCardState();
}

class _DictCardState extends State<DictCard> {
  late LearningDict currentLearningDict;
  int? actualWordCount; // 用于存储生词本的实际单词数量
  int learnedCount = 0; // 学习中的单词数
  int masteredCount = 0; // 已掌握的单词数

  @override
  void initState() {
    super.initState();
    currentLearningDict = widget.learningDict;
    _loadActualWordCount();
    _loadLearnedAndMasteredCount();
  }

  @override
  void didUpdateWidget(DictCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learningDict != widget.learningDict) {
      currentLearningDict = widget.learningDict;
      _loadActualWordCount();
      _loadLearnedAndMasteredCount();
    }
  }

  // 加载学习中和已掌握的单词数量
  Future<void> _loadLearnedAndMasteredCount() async {
    final db = MyDatabase.instance;
    final dictId = widget.learningDict.dictId;
    final userId = widget.learningDict.userId;

    // [性能优化] 使用 SQL 在数据库端聚合统计，避免每次渲染都把成千上万个单词拉到内存中进行 Set 操作
    int learned = await db.learningWordsDao.getLearningWordsCountInDicts(userId, [dictId]);
    int mastered = await db.masteredWordsDao.getMasteredWordsCountInDicts(userId, [dictId]);

    if (mounted) {
      setState(() {
        learnedCount = learned;
        masteredCount = mastered;
      });
    }
  }

  // 加载生词本的实际单词数量
  Future<void> _loadActualWordCount() async {
    if (widget.dictInfo.name == '生词本') {
      final count = await ErrorHandler.safeExecute<int>(
        () => MyDatabase.instance.dictWordsDao.getDictWordCount(widget.learningDict.dictId),
        operationName: '获取生词本单词数量',
        showToast: false, // 不显示错误提示，静默失败
      );

      if (mounted) {
        setState(() {
          actualWordCount = count ?? 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalWords = widget.dictInfo.name == '生词本' ? (actualWordCount ?? 0) : widget.dictInfo.wordCount;
    final masteredWords = masteredCount;
    final learningWords = learnedCount;
    final fetchWords = masteredWords + learningWords;

    final masteryProgress = (totalWords > 0 ? masteredWords / totalWords : 0.0).clamp(0.0, 1.0);
    final fetchProgress = (totalWords > 0 ? fetchWords / totalWords : 0.0).clamp(0.0, 1.0);

    final progressPercent = (masteryProgress * 100).toInt();

    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final masteredColor = themeConfig.primaryColor;
    final fetchColor = themeConfig.primaryColor.withValues(alpha: 0.65);
    final cardBg = themeConfig.cardBg;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          try {
            await toDictWordsListPage(currentLearningDict.dictId, false);
            widget.onDictChanged();
          } catch (e) {
            ToastUtil.error("无法打开词书");
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 上半部分：左侧环形进度 + 右侧（词书名称与优先标 + 掌握/取词统计 + 细箭头）
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animValue, child) {
                      return SizedBox(
                        width: 40,
                        height: 40,
                        child: CustomPaint(
                          painter: ThreeSegmentProgressPainter(
                            masteryProgress: masteryProgress * animValue,
                            fetchProgress: fetchProgress * animValue,
                            masteredColor: masteredColor,
                            fetchColor: fetchColor,
                            backgroundColor: isDarkMode ? Colors.white10 : masteredColor.withValues(alpha: 0.1),
                            dividerColor: cardBg,
                            strokeWidth: 3.2,
                          ),
                          child: Center(
                            child: Text(
                              '$progressPercent%',
                              style: TextStyle(
                                fontSize: 10,
                                color: masteredColor,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  // 词书信息区
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.dictInfo.name.replaceAll('.dict', ''),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (currentLearningDict.isPrivileged) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => PrivilegedDictExplanationDialog.show(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: masteredColor.withValues(alpha: isDarkMode ? 0.2 : 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '优先',
                                        style: TextStyle(
                                          color: masteredColor,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '已掌握 $masteredWords · 已取词 $fetchWords / $totalWords 词',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: subtitleColor.withValues(alpha: 0.35),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 2. 下半部分：轻量级微操作栏（对称排版，去框化）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 左侧：优先取词微操作
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      try {
                        final newPrivilegedStatus = await MyDatabase.instance.learningDictsDao
                            .togglePrivileged(currentLearningDict.userId, currentLearningDict.dictId, true);

                        if (mounted) {
                          setState(() {
                            currentLearningDict = LearningDict(
                              userId: currentLearningDict.userId,
                              dictId: currentLearningDict.dictId,
                              isPrivileged: newPrivilegedStatus,
                              fetchMastered: currentLearningDict.fetchMastered,
                              sortAlg: currentLearningDict.sortAlg,
                              createTime: currentLearningDict.createTime,
                              updateTime: currentLearningDict.updateTime,
                            );
                          });
                        }

                        ThrottledDbSyncService().requestSync();
                      } catch (error) {
                        Global.logger.d('切换优先取词状态失败: $error');
                        ToastUtil.error('操作失败，请重试');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            currentLearningDict.isPrivileged ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 12,
                            color: currentLearningDict.isPrivileged ? masteredColor : subtitleColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            currentLearningDict.isPrivileged ? '优先取词中' : '设为优先',
                            style: TextStyle(
                              color: currentLearningDict.isPrivileged ? masteredColor : subtitleColor.withValues(alpha: 0.75),
                              fontSize: 11,
                              fontWeight: currentLearningDict.isPrivileged ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 右侧：移出书桌（停学）
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleDictDataAction(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.remove_circle_outline_rounded,
                            size: 12,
                            color: subtitleColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            '停学',
                            style: TextStyle(
                              color: subtitleColor.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 统一处理词书数据操作（清空单词或删除词书）
  Future<void> _handleDictDataAction() async {
    final db = MyDatabase.instance;
    final user = Global.getLoggedInUser()!;
    final dictName = widget.dictInfo.name.replaceAll('.dict', '');

    // 1. 获取该词书中的所有单词 ID
    final dictWords = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(currentLearningDict.dictId))).get();
    final wordIdsInDict = dictWords.map((dw) => dw.wordId).toSet();

    // 2. 查询用户所有学习中的单词（stability < graduationStability）
    final learningWords = await (db.select(db.learningWords)
          ..where((lw) => lw.userId.equals(user.id) & (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability))))
        .get();

    if (!mounted) return;

    // 3. 获取用户书桌上的所有其他词书 ID
    final otherLearningDicts =
        await (db.select(db.learningDicts)..where((ld) => ld.userId.equals(user.id) & ld.dictId.isNotValue(currentLearningDict.dictId))).get();
    final otherDictIds = otherLearningDicts.map((ld) => ld.dictId).toSet();

    if (!mounted) return;

    // 4. 找出仅在当前词书中的学习单词
    final learningWordsOnlyInThisDict = <LearningWord>[];
    for (final lw in learningWords) {
      if (!wordIdsInDict.contains(lw.wordId)) continue;

      final otherDicts = await (db.select(db.dictWords)
            ..where((dw) => dw.wordId.equals(lw.wordId) & dw.dictId.isIn(otherDictIds.isEmpty ? [''] : otherDictIds.toList())))
          .get();

      if (!mounted) return;
      if (otherDicts.isEmpty) {
        learningWordsOnlyInThisDict.add(lw);
      }
    }

    bool deleteLearningWords = false;
    bool shouldProceed = false;

    // 5. 询问用户
    if (learningWordsOnlyInThisDict.isNotEmpty) {
      final confirmResult = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部警告图标
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  '确认停止学习',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '确定要将词书《$dictName》从书桌移出（停止学习）吗？',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                ),
                const SizedBox(height: 20),
                // 独有学习单词提示卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.orange[800]),
                          const SizedBox(width: 8),
                          Text(
                            '存在学习中单词',
                            style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '该词书中有 ${learningWordsOnlyInThisDict.length} 个单词正在学习。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange[900], fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 操作按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('停止学习并清除学习中单词'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('仅停止学习'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (confirmResult != null) {
        shouldProceed = true;
        deleteLearningWords = confirmResult;
      }
    } else {
      // 没有独有学习词，直接确认
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.remove_circle_outline, color: context.primaryColor, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  '确认操作',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '确实要将词书《$dictName》从书桌移出？',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Colors.grey[800],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('否'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('是'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed == true) {
        shouldProceed = true;
      }
    }

    // 6. 执行核心逻辑
    if (shouldProceed && mounted) {
      await db.learningDictsDao.deleteEntity(currentLearningDict, true);
      widget.onDictChanged();

      // 通知书桌词书发生变化，其他页面（如词表页）刷新
      EventBus.publishLearningDictChanged(const LearningDictChangedEvent());

      // 处理相关学习记录
      if (deleteLearningWords) {
        for (final lw in learningWordsOnlyInThisDict) {
          await db.learningWordsDao.deleteEntity(lw, true);
        }
      }

      ThrottledDbSyncService().requestSync();
    }
  }
}

class ThreeSegmentProgressPainter extends CustomPainter {
  final double masteryProgress;
  final double fetchProgress;
  final Color masteredColor;
  final Color fetchColor;
  final Color backgroundColor;
  final Color dividerColor;
  final double strokeWidth;

  ThreeSegmentProgressPainter({
    required this.masteryProgress,
    required this.fetchProgress,
    required this.masteredColor,
    required this.fetchColor,
    required this.backgroundColor,
    required this.dividerColor,
    this.strokeWidth = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -math.pi / 2; // 从 12 点钟方向开始

    // 1. 绘制背景圆环 (未学习部分)
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // 2. 绘制取词进度圆环 (学习中部分)
    if (fetchProgress > masteryProgress) {
      final learningPaint = Paint()
        ..color = fetchColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      final start = startAngle + masteryProgress * 2 * math.pi;
      final sweep = (fetchProgress - masteryProgress) * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, learningPaint);
    }

    // 3. 绘制已掌握进度圆环 (已掌握部分)
    if (masteryProgress > 0) {
      final masteredPaint = Paint()
        ..color = masteredColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      final sweep = masteryProgress * 2 * math.pi;
      canvas.drawArc(rect, startAngle, sweep, false, masteredPaint);
    }

    // 4. 在交界处绘制分割线 (用 cardBgColor 绘制)
    final dividerPaint = Paint()
      ..color = dividerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final innerRadius = radius - strokeWidth / 2 - 0.5;
    final outerRadius = radius + strokeWidth / 2 + 0.5;

    // 已掌握与学习中的分割线
    if (masteryProgress > 0 && masteryProgress < 1.0 && fetchProgress > masteryProgress) {
      final angle = startAngle + masteryProgress * 2 * math.pi;
      final p1 = Offset(center.dx + math.cos(angle) * innerRadius, center.dy + math.sin(angle) * innerRadius);
      final p2 = Offset(center.dx + math.cos(angle) * outerRadius, center.dy + math.sin(angle) * outerRadius);
      canvas.drawLine(p1, p2, dividerPaint);
    }

    // 学习中与未学习的分割线
    if (fetchProgress > 0 && fetchProgress < 1.0 && fetchProgress != masteryProgress) {
      final angle = startAngle + fetchProgress * 2 * math.pi;
      final p1 = Offset(center.dx + math.cos(angle) * innerRadius, center.dy + math.sin(angle) * innerRadius);
      final p2 = Offset(center.dx + math.cos(angle) * outerRadius, center.dy + math.sin(angle) * outerRadius);
      canvas.drawLine(p1, p2, dividerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ThreeSegmentProgressPainter oldDelegate) {
    return oldDelegate.masteryProgress != masteryProgress ||
        oldDelegate.fetchProgress != fetchProgress ||
        oldDelegate.masteredColor != masteredColor ||
        oldDelegate.fetchColor != fetchColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.dividerColor != dividerColor;
  }
}
