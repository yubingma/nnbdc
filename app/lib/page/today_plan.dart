import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import "package:go_router/go_router.dart";
import "package:nnbdc/util/prefs.dart";
import 'package:intl/intl.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/models/bdc_page_args.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:provider/provider.dart';

class TodayPlanPage extends StatefulWidget {
  const TodayPlanPage({super.key});

  @override
  TodayPlanPageState createState() {
    return TodayPlanPageState();
  }
}

class TodayPlanPageState extends State<TodayPlanPage> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  List<LearningWord>? _todayWords;
  DateTime _now = AppClock.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 首页初始化时强制关停 ASR
    Asr().stopAsr();
    WidgetsBinding.instance.addObserver(this);
    // 首页初始化数据由 didChangeDependencies 触发，此处不再重复调用 loadData()，避免并发加载冲突

    // 订阅今日相关的业务事实
    _dakaSubscription = EventBus.onTodayStudyPlanFinished().listen((event) {
      Global.logger.d('TodayPlanPage received TodayStudyPlanFinishedEvent, refreshing data...');
      if (mounted && !_isLoadingData) {
        loadData();
      }
    });

    _wordDeletedSubscription = EventBus.onWordDeletedFromWordList().listen((event) {
      Global.logger.d('TodayPlanPage received WordDeletedFromWordListEvent, refreshing data...');
      if (mounted && !_isLoadingData) {
        loadData();
      }
    });

    _wordMasteredSubscription = EventBus.onWordMastered().listen((event) {
      Global.logger.d('TodayPlanPage received WordMasteredEvent, refreshing data...');
      if (mounted && !_isLoadingData) {
        loadData();
      }
    });

    _wordUnMasteredSubscription = EventBus.onWordUnMastered().listen((event) {
      Global.logger.d('TodayPlanPage received WordUnMasteredEvent, refreshing data...');
      if (mounted && !_isLoadingData) {
        loadData();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = AppClock.now();
        });
      }
    });
  }

  StreamSubscription? _dakaSubscription;
  StreamSubscription? _wordDeletedSubscription;
  StreamSubscription? _wordMasteredSubscription;
  StreamSubscription? _wordUnMasteredSubscription;

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _dakaSubscription?.cancel();
    _wordDeletedSubscription?.cancel();
    _wordMasteredSubscription?.cancel();
    _wordUnMasteredSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Global.logger.d('App resumed, refreshing Today Plan...');
      // 恢复时如果数据已加载，则尝试静默刷新以处理跨天逻辑
      if (mounted && dataLoaded && !_isLoadingData) {
        loadData();
      }
    }
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

  Future<void> loadData({bool forceSupplement = false, bool isReturnFromStudy = false}) async {
    Global.logger.d('Entering loadData: forceSupplement=$forceSupplement, _isLoadingData=$_isLoadingData');
    if (!forceSupplement) {
      _hasTriedSupplement = false;
    }
    if (_isLoadingData) {
      Global.logger.d('loadData already in progress, returning');
      return;
    }
    
    _isLoadingData = true;

    try {
      // 1. 第一步：优先从本地数据库快速加载现有数据，以便立刻展示 UI
      await _loadEssentialLocalData();
      
      // 如果已经有基本数据了，或者不是第一次加载，就直接展示 UI
      if (mounted && (user != null || dataLoaded)) {
        setState(() {
          dataLoaded = true;
        });
      }

      // 2. 第二步：执行云端同步（解决多端不一致）
      if (!Global.isGuest && !_hasTriedSync) {
        Global.logger.i('今日计划尝试从云端同步数据...');
        if (mounted) {
          setState(() {
            _isSyncingFromCloud = true;
          });
        }
        try {
          if (_todayWords == null || _todayWords!.isEmpty) {
            Global.logger.i('今日计划本地为空，发起阻塞式同步...');
            await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
          } else {
            ThrottledDbSyncService().requestSync();
          }
        } catch (e) {
          Global.logger.e('进入页面同步失败: $e');
        } finally {
          _hasTriedSync = true;
          if (mounted) {
            setState(() {
              _isSyncingFromCloud = false;
            });
          }
        }
        
        // 同步完成后，重新加载一次本地用户信息，防止同步覆盖了本地状态
        await _loadEssentialLocalData();
      }

      // 3. 第三步：准备今日学习计划 (处理跨天重置、取词等逻辑)
      if (!isReturnFromStudy || prepareResult == null || !prepareResult!.success) {
        Global.logger.d('Starting prepareForStudy...');
        prepareResult = await StudyBo().prepareForStudy(forceSupplement);
        
        // 重新获取最新的用户信息（prepareForStudy 可能重置了 todayStudyStarted）
        final refreshUserResult = await UserBo().getLoggedInUser();
        if (refreshUserResult.success) {
          user = refreshUserResult.data;
        }
      }

      // 4. 第四步：检查词书资源下载
      await _checkAndDownloadDicts();

      // 5. 第五步：计算进度和统计数据
      if (prepareResult != null && (prepareResult!.success || prepareResult!.code == "NNBDC-0012")) {
        if (forceSupplement) {
          _hasTriedSupplement = true;
        }
        List<int> counts = prepareResult!.data!;
        newWordCount = counts[0];
        oldWordCount = counts[1];
        todayWordCount = newWordCount! + oldWordCount!;
      }

      hasDakaToday = (await UserBo().hasDakaToday(user!.id!)).data!;
      _todayWords = await LearningService.getTodayLearningWordsFromDb(user!.id!);
      
      int calcNewWordCount = 0;
      for (var word in _todayWords!) {
        if (word.isTodayNewWord) calcNewWordCount++;
      }
      newWordCount = calcNewWordCount;
      oldWordCount = _todayWords!.length - newWordCount!;
      todayWordCount = _todayWords!.length;

      _updateProgress();
      Global.logger.d('Progress calculated: $_completedStepCount / $_totalStepCount');

    } catch (e, stackTrace) {
      if (!mounted) return;
      Global.logger.e('加载今日学习计划数据失败: $e', stackTrace: stackTrace);
      ToastUtil.error('加载失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          dataLoaded = true;
          _isLoadingData = false;
        });
      }
    }
  }

  /// 快速加载本地基础数据（不涉及网络和复杂的计划准备）
  Future<void> _loadEssentialLocalData() async {
    final userResult = await UserBo().getLoggedInUser();
    if (userResult.success) {
      user = userResult.data;
    }

    final stepsResult = await StudyBo().getUserStudySteps();
    if (stepsResult.success) {
      studySteps = stepsResult.data?.where((step) => step.studyStep != 'List').toList();
    }

    if (user != null) {
      // 检查是否为新的一天。如果是，则不加载本地已有的旧批次单词，防止 UI 闪烁旧数据
      final today = app_date.DateUtils.pureDate(AppClock.now());
      bool isNewDay = user!.lastLearningDate == null || user!.lastLearningDate != today;
      
      if (isNewDay) {
        Global.logger.d('Detecting new day in local load, clearing stale data');
        _todayWords = [];
        newWordCount = 0;
        oldWordCount = 0;
        todayWordCount = 0;
        _completedStepCount = 0;
        _totalStepCount = 0;
        return;
      }

      _todayWords = await LearningService.getTodayLearningWordsFromDb(user!.id!);
      _updateProgress();
      
      // 估算今日单词数（基于本地已有数据）
      if (_todayWords != null && _todayWords!.isNotEmpty) {
        int calcNewWordCount = 0;
        for (var word in _todayWords!) {
          if (word.isTodayNewWord) calcNewWordCount++;
        }
        newWordCount = calcNewWordCount;
        oldWordCount = _todayWords!.length - newWordCount!;
        todayWordCount = _todayWords!.length;
      }
    }
  }

  /// 检查并下载缺失的词典
  Future<void> _checkAndDownloadDicts() async {
    if (Global.isGuest || user == null) return;
    
    final db = MyDatabase.instance;
    List<LearningDict> learningDicts = await db.learningDictsDao.getLearningDictsOfUser(user!.id!);
    List<DictVo> dictsToDownload = [];
    
    for (var ld in learningDicts) {
      Dict? existing = await db.dictsDao.findById(ld.dictId);
      if (existing == null) {
        dictsToDownload.add(DictVo.c2(ld.dictId));
      } else if (existing.ownerId == "15118" && !(await db.dictWordsDao.hasDictWords(ld.dictId))) {
        if (existing.baseDictId != null && existing.baseDictId!.isNotEmpty) {
          bool baseHasWords = await db.dictWordsDao.hasDictWords(existing.baseDictId!);
          if (!baseHasWords && !dictsToDownload.any((d) => d.id == existing.baseDictId)) {
            dictsToDownload.add(DictVo.c2(existing.baseDictId!));
          }
        }
        if (!dictsToDownload.any((d) => d.id == ld.dictId)) {
          dictsToDownload.add(DictVo.c2(ld.dictId));
        }
      }
    }

    final commonDictId = Global.commonDictId;
    Dict? commonDictExisting = await db.dictsDao.findById(commonDictId);
    if (commonDictExisting == null || !(await db.dictWordsDao.hasDictWords(commonDictId))) {
      dictsToDownload.add(DictVo.c2(commonDictId));
    }

    if (dictsToDownload.isNotEmpty && mounted && !DictDownloadDialog.isShowing) {
      await DictDownloadDialog.show(
        context: context,
        dicts: dictsToDownload,
        onComplete: () {},
      );
      // 词书下载完成后，刷新页面数据以更新学习进度显示
      await loadData();
      prepareResult = await StudyBo().prepareForStudy(false);
    }
  }


  void _updateProgress() {
    final activeStepsCount = selectedSteps().length;
    if (_todayWords == null) {
      _totalStepCount = 0;
      _completedStepCount = 0;
      return;
    }
    
    _totalStepCount = (_todayWords!.length * activeStepsCount).toInt();
    _completedStepCount = 0;
    for (final word in _todayWords!) {
      final bool isMastered = (word.stability != null && word.stability! >= Constants.graduationStability);
          
      if (isMastered) {
        _completedStepCount += activeStepsCount;
      } else {
        _completedStepCount += (word.todayLearnedTimes > activeStepsCount) ? activeStepsCount : word.todayLearnedTimes;
      }
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
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Today\'s Plan',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (_isSyncingFromCloud) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDarkMode ? Colors.white70 : Colors.black45,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_now)} (${DateFormat('yyyy-MM-dd').format(app_date.DateUtils.businessDate(_now))})',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white38 : Colors.black38,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('学习日期说明'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('本应用以凌晨 03:00 作为学习日期的切换点。\n\n如果您在凌晨 3 点前背单词，系统仍会将其计入前一天的学习任务中，以照顾习惯熬夜学习的同学。'),
                                      const SizedBox(height: 16),
                                      Text(
                                        '当前时区: ${_now.timeZoneName} (UTC${_now.timeZoneOffset.isNegative ? '-' : '+'}${_now.timeZoneOffset.inHours.abs()})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDarkMode ? Colors.white38 : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('知道了'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Icon(
                              Icons.help_outline_rounded,
                              size: 12,
                              color: isDarkMode ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                          '${user?.effectiveWordsPerDay ?? 0} 个单词',
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
            child: Column(
              children: [
                Row(
                  children: [
                    _buildStatItem('今日总词', todayWordCount ?? 0, Icons.auto_awesome_rounded, const Color(0xFF0EA5E9)),
                    const SizedBox(width: 8),
                    _buildStatItem('新词', newWordCount ?? 0, Icons.fiber_new_rounded, const Color(0xFF8B5CF6)),
                    const SizedBox(width: 8),
                    _buildStatItem('复习', oldWordCount ?? 0, Icons.history_rounded, const Color(0xFF10B981)),
                  ],
                ),
                if (!(user?.todayStudyStarted ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '未开始学习前，可点击上方数字调整单词',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white54 : Colors.black45,
                        fontSize: 11,
                      ),
                    ),
                  ), 
              ],
            ),
          ),

          // Supplement Hint
          if (prepareResult != null &&
              prepareResult!.success &&
              (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 20) &&
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
            child: (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 0)))
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
            toTodayWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          } else if (label == '新词') {
            toTodayNewWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          } else if (label == '复习') {
            toTodayOldWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
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
            value: user?.effectiveWordsPerDay ?? 20,
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

    if (hasDakaToday && _totalStepCount > 0 && _completedStepCount >= _totalStepCount) {
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
              '今日任务圆满达成',
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
            ToastUtil.error('请选择至少一个学习环节');
            return;
          }

          if (!(user?.todayStudyStarted ?? false)) {
            final shouldStart = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('准备开始今日学习'),
                content: const Text('一旦开始，今日计划将无法修改。\n确认现在开始背单词吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('稍等修改'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('马上开始'),
                  ),
                ],
              ),
            );
            
            if (shouldStart != true) {
              return;
            }

            // [二次校验] 开始学习前，强制断言所有今日单词进度为 0
            final checkWords = await LearningService.getTodayLearningWordsFromDb(user!.id!);
            for (var w in checkWords) {
              assert(w.todayLearnedTimes == 0, '数据不一致：点击开始学习时，发现单词 ${w.wordId} 已有今日进度 (${w.todayLearnedTimes})');
            }
          }

          if (user != null) {
            await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "开始学习");
            final dbUser = await MyDatabase.instance.usersDao.getUserById(user!.id!);
            if (dbUser != null) {
              await MyDatabase.instance.usersDao.saveUser(
                  dbUser.copyWith(todayStudyStarted: true, lastLearningDate: drift.Value(AppClock.today())), true);
            }
            await Global.loadUserFromDb();
            // 立刻发起非阻塞同步，确保状态尽快上传云端
            ThrottledDbSyncService().requestSync(immediate: true);
          }
          await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
          if (!mounted) return;
          context.push('/bdc').then((value) {
            if (mounted && !_isLoadingData) loadData(isReturnFromStudy: true);
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
                onPressed: () => context.push('/select_book').then((v) {
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
                    await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
                    if (!mounted) return;
                    context.push('/bdc');
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
                '学习环节',
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
              // Fast local update for progress
              _updateProgress();
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
