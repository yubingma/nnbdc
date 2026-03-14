import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';

import 'bdc.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/util/learning_service.dart';

class BeforeBdcPage extends StatefulWidget {
  const BeforeBdcPage({super.key});

  @override
  BeforeBdcPageState createState() {
    return BeforeBdcPageState();
  }
}

class BeforeBdcPageState extends State<BeforeBdcPage> with TickerProviderStateMixin {
  List<UserStudyStepVo>? studySteps;
  int? newWordCount;
  int? oldWordCount;
  int? todayWordCount;
  bool dataLoaded = false;
  UserVo? user;
  bool hasDakaToday = false;
  Result<List<int>>? prepareResult;
  bool _hasTriedSync = false;
  bool _isSyncingFromCloud = false;
  bool _hasTriedSupplement = false;
  bool _isLoadingData = false;
  int _completedStepCount = 0;
  int _totalStepCount = 0;

  @override
  void initState() {
    super.initState();
    Timer.run(() {
      if (mounted) {
        loadData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && !dataLoaded && !_isLoadingData) {
      Timer.run(() {
        if (mounted && !dataLoaded && !_isLoadingData) {
          loadData();
        }
      });
    }
  }

  Future<void> loadData({bool forceSupplement = false}) async {
    if (!forceSupplement) {
      _hasTriedSupplement = false;
    }
    if (_isLoadingData) return;
    _isLoadingData = true;

    Api.setLoadingDisabled(true);
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      var result0 = await UserBo().getLoggedInUser();
      if (result0.success) {
        user = result0.data;
      } else {
        ToastUtil.error(result0.msg!);
        return;
      }

      var result = await StudyBo().getUserStudySteps();
      if (result.success) {
        studySteps = [];
        List<UserStudyStepVo> userStudySteps = result.data!;
        for (UserStudyStepVo step in userStudySteps) {
          if (step.studyStep != 'List') {
            studySteps!.add(step);
          }
        }
      } else {
        ToastUtil.error(result.msg!);
        return;
      }

      try {
        prepareResult = await StudyBo().prepareForStudy(forceSupplement);
        
        // 如果准备数据失败（提示词书不足/没词书）或者学习环节为空，且是正式用户，且还没尝试过同步
        // 这种情况通常发生在新安装 App 并登录后，后台同步尚未完成
        if ((prepareResult!.code == "NNBDC-0012" || (studySteps?.isEmpty ?? true)) && !Global.isGuest && !_hasTriedSync) {
          Global.logger.i('今日计划单词量不足且尚未同步，尝试从云端同步数据...');
          setState(() {
            _isSyncingFromCloud = true;
          });
          
          try {
            // 立即触发一次同步并等待完成
            await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
            _hasTriedSync = true;
            
            // 同步完成后重试加载用户信息和学习步骤
            var refreshUserResult = await UserBo().getLoggedInUser();
            if (refreshUserResult.success) {
              user = refreshUserResult.data;
            }
            
            var refreshStepsResult = await StudyBo().getUserStudySteps();
            if (refreshStepsResult.success) {
              studySteps = [];
              List<UserStudyStepVo> userStudySteps = refreshStepsResult.data!;
              for (UserStudyStepVo step in userStudySteps) {
                if (step.studyStep != 'List') {
                  studySteps!.add(step);
                }
              }
            }

            // 同步完成后重试准备逻辑
            prepareResult = await StudyBo().prepareForStudy(forceSupplement || true);
          } catch (e) {
            Global.logger.e('尝试自动同步失败: $e');
          } finally {
            if (mounted) {
              setState(() {
                _isSyncingFromCloud = false;
              });
            }
          }
        }

        // 检查是否缺少词书资源并下载
        if (!Global.isGuest && user != null) {
          final db = MyDatabase.instance;
          List<LearningDict> learningDicts = await db.learningDictsDao.getLearningDictsOfUser(user!.id!);
          List<DictVo> dictsToDownload = [];
          for (var ld in learningDicts) {
            Dict? existing = await db.dictsDao.findById(ld.dictId);
            if (existing == null) {
              dictsToDownload.add(DictVo.c2(ld.dictId));
            } else if (existing.ownerId == "15118" && !(await db.dictWordsDao.hasDictWords(ld.dictId))) {
              dictsToDownload.add(DictVo.c2(ld.dictId));
            }
          }

          // 检查并下载通用词典 (ID 为 "0")
          final commonDictId = Global.commonDictId;
          Dict? commonDictExisting = await db.dictsDao.findById(commonDictId);
          if (commonDictExisting == null) {
            dictsToDownload.add(DictVo.c2(commonDictId));
          } else if (!(await db.dictWordsDao.hasDictWords(commonDictId))) {
            dictsToDownload.add(DictVo.c2(commonDictId));
          }

          if (dictsToDownload.isNotEmpty && mounted) {
            Global.logger.i('发现缺少的词书资源，准备下载: ${dictsToDownload.map((e) => e.id).toList()}');
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => DictDownloadDialog(
                dicts: dictsToDownload,
                onComplete: () {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            );
            // 下载完成后重新准备数据
            prepareResult = await StudyBo().prepareForStudy(forceSupplement);
          }
        }

        if (prepareResult!.success || prepareResult!.code == "NNBDC-0012") {
          if (forceSupplement) {
            _hasTriedSupplement = true;
          }
          List<int> counts = prepareResult!.data!;
          newWordCount = counts[0];
          oldWordCount = counts[1];
          todayWordCount = newWordCount! + oldWordCount!;
        } else {
          ToastUtil.error(prepareResult!.msg!);
          return;
        }
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace, logPrefix: '准备学习失败', userMessage: '准备学习失败，请稍后重试', showToast: true);
        return;
      }

      hasDakaToday = (await UserBo().hasDakaToday(user!.id!)).data!;

      // Calculate progress
      final activeStepsCount = selectedSteps().length;
      final todayWords = await LearningService.getTodayLearningWordsFromDb(user!.id!);
      _totalStepCount = (todayWords.length * activeStepsCount).toInt();
      _completedStepCount = 0;
      for (final word in todayWords) {
        _completedStepCount += (word.todayLearnedTimes > activeStepsCount) ? activeStepsCount : word.todayLearnedTimes;
      }

      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
      }
    } finally {
      Api.setLoadingDisabled(false);
      _isLoadingData = false;
    }
  }

  void reorderData(int oldIndex, int newIndex) {
    if (!mounted) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = studySteps!.removeAt(oldIndex);
      studySteps!.insert(newIndex, items);
      for (var i = 0; i < studySteps!.length; i++) {
        studySteps![i].seq = i;
      }
      saveStudyStep();
    });
  }

  List<UserStudyStepVo> selectedSteps() {
    return studySteps?.where((s) => s.state == StudyStepState.active.json).toList() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: (!dataLoaded)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF0EA5E9))),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isSyncingFromCloud ? 'SYNCING FROM CLOUD...' : 'LOADING PLAN',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: backgroundColor,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  centerTitle: true,
                  toolbarHeight: 56,
                  title: Text(
                    'Today\'s Plan',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                      height: 1,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        renderMissionCard(),
                        const SizedBox(height: 16),
                        renderStudySteps(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget renderMissionCard() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardBg = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final progress = _totalStepCount > 0 ? (_completedStepCount / _totalStepCount) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Goal Setting
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日目标',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : const Color(0xFF64748B),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${user?.wordsPerDay ?? 0} 个单词',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (user?.todayStudyStarted == true) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline_rounded,
                            color: isDarkMode ? Colors.white38 : Colors.black26,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                renderGoalDropdown(),
              ],
            ),
          ),

          // Progress Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '进度: $_completedStepCount / $_totalStepCount',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white60 : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF0891B2),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? const Color(0xFF06B6D4) : const Color(0xFF0891B2),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                _buildStatItem('今日总词', todayWordCount ?? 0, Icons.auto_awesome_rounded, const Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                _buildStatItem('新词', newWordCount ?? 0, Icons.fiber_new_rounded, const Color(0xFF8B5CF6)),
                const SizedBox(width: 8),
                _buildStatItem('复习', oldWordCount ?? 0, Icons.history_rounded, const Color(0xFF10B981)),
              ],
            ),
          ),

          // Supplement Hint
          if (prepareResult != null &&
              prepareResult!.success &&
              (todayWordCount ?? 0) < (user?.wordsPerDay ?? 20) &&
              !(user?.todayStudyStarted ?? false) &&
              !_hasTriedSupplement)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '任务量不足，建议补充单词',
                        style: TextStyle(
                          color: isDarkMode ? Colors.orange.shade300 : Colors.orange.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                        foregroundColor: isDarkMode ? Colors.white : Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => loadData(forceSupplement: true),
                      child: const Text('补充'),
                    ),
                  ],
                ),
              ),
            ),

          // Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.wordsPerDay ?? 0)))
                ? renderErrorActions()
                : renderStartButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color accentColor) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (label == '今日总词') {
            toTodayWordsListPage(true)?.then((_) => loadData());
          } else if (label == '新词') {
            toTodayNewWordsListPage(true)?.then((_) => loadData());
          } else if (label == '复习') {
            toTodayOldWordsListPage(true)?.then((_) => loadData());
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: accentColor.withValues(alpha: 0.8)),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget renderGoalDropdown() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final bool isStarted = user?.todayStudyStarted == true;

    return GestureDetector(
      onTap: isStarted ? () => ToastUtil.info('今日学习已开始，无法修改计划数量') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: (() {
              final isPremium = SubscriptionUtil.isPremium();
              final raw = user?.wordsPerDay ?? 20;
              if (!isPremium && raw > 20) return 20;
              return raw;
            })(),
            isDense: true,
            icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
            dropdownColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            style: TextStyle(
              color: isDarkMode ? (isStarted ? Colors.white54 : Colors.white) : (isStarted ? Colors.black26 : const Color(0xFF1E293B)),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
            onChanged: isStarted
                ? null
                : (value) async {
                    if (value == null) return;
                    if (!SubscriptionUtil.isPremium() && value > 20) {
                      ToastUtil.info('开通会员可选择更多单词数量');
                      return;
                    }
                    setState(() {
                      user!.wordsPerDay = value;
                      dataLoaded = false;
                    });
                    await MyDatabase.instance.usersDao.updateWordsPerDay(user!.id!, value);
                    await Global.loadUserFromDb();
                    ThrottledDbSyncService().requestSync();
                    loadData(forceSupplement: false);
                  },
            items: [10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500].map((v) {
              final isPremium = SubscriptionUtil.isPremium();
              final isRestricted = !isPremium && v > 20;
              return DropdownMenuItem<int>(
                value: v,
                enabled: !isRestricted,
                child: Row(
                  children: [
                    Text('$v'),
                    if (isRestricted) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 14),
                      const SizedBox(width: 2),
                      const Text(
                        '会员',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget renderStartButton() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    if (hasDakaToday) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stars_rounded, color: isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669), size: 24),
            const SizedBox(width: 12),
            Text(
              '今日任务已圆满达成',
              style: TextStyle(
                color: isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDarkMode ? [const Color(0xFF0891B2), const Color(0xFF0EA5E9)] : [const Color(0xFF06B6D4), const Color(0xFF0EA5E9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: () async {
          if (selectedSteps().isEmpty) {
            ToastUtil.error('请选择至少一种学习模式');
            return;
          }
          if (user != null) {
            await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "开始学习");
            await (MyDatabase.instance.update(MyDatabase.instance.users)..where((u) => u.id.equals(user!.id!))).write(UsersCompanion(
              todayStudyStarted: const drift.Value(true),
            ));
            await Global.loadUserFromDb();
          }
          await GetStorage().write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
          Get.toNamed('/bdc')?.then((value) {
            if (mounted && !_isLoadingData) loadData();
          });
        },
        child: Text(
          user?.todayStudyStarted == true ? '继续学习' : '开始学习',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  Widget renderErrorActions() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('词书单词量不足', style: TextStyle(color: Colors.orange, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                  side: BorderSide(color: isDarkMode ? Colors.white24 : Colors.black12),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Get.toNamed('/select_book')?.then((v) {
                  if (mounted) loadData(forceSupplement: true);
                }),
                child: const Text('选择词书'),
              ),
            ),
            if (todayWordCount! > 0) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                    foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await GetStorage().write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
                    Get.toNamed('/bdc');
                  },
                  child: const Text('就这样吧'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget renderStudySteps() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '学习模式',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '拖动 ⠿ 排序',
                  style: TextStyle(
                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ReorderableListView(
          buildDefaultDragHandles: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: reorderData,
          children: [
            for (int i = 0; i < studySteps!.length; i++) _buildStepTile(studySteps![i], i),
          ],
        ),
      ],
    );
  }

  Widget _buildStepTile(UserStudyStepVo step, int index) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final isActive = step.state == StudyStepState.active.json;

    String stepName = StudyStepExt.fromString(step.studyStep).description;
    if (isActive) {
      int activeIndex = 0;
      for (var s in studySteps!) {
        if (s.state == StudyStepState.active.json) {
          if (s == step) {
            if (activeIndex == 0) {
              stepName += ' (测评)';
            } else if (activeIndex == 1) {
              stepName += ' (巩固)'; 
            }
            break;
          }
          activeIndex++;
        }
      }
    }

    return Container(
      key: ValueKey(step.studyStep),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: const Color(0xFF0EA5E9).withValues(alpha: isDarkMode ? 0.1 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
        border: Border.all(
          color: isActive
              ? (isDarkMode ? const Color(0xFF0EA5E9).withValues(alpha: 0.5) : const Color(0xFF0EA5E9).withValues(alpha: 0.3))
              : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              step.state = isActive ? StudyStepState.inactive.json : StudyStepState.active.json;
              saveStudyStep();
              // Re-calculate progress since steps changed
              final activeStepsCount = selectedSteps().length;
              _totalStepCount = (todayWordCount ?? 0) * activeStepsCount;
              loadData(); // Re-fetch to be safe
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? (isDarkMode ? const Color(0xFF0EA5E9).withValues(alpha: 0.2) : const Color(0xFFE0F2FE)) : Colors.transparent,
                  ),
                  child: Icon(
                    isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: isActive ? const Color(0xFF0EA5E9) : (isDarkMode ? Colors.white24 : Colors.black12),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    stepName,
                    style: TextStyle(
                      color: isActive ? (isDarkMode ? Colors.white : const Color(0xFF1E293B)) : (isDarkMode ? Colors.white38 : Colors.black26),
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: isDarkMode ? Colors.white38 : Colors.black26,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> saveStudyStep() async {
    await StudyBo().saveUserStudySteps(studySteps!);
  }
}
