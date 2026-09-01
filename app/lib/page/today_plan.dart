import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import "package:go_router/go_router.dart";
import "package:nnbdc/util/prefs.dart";
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc/models/bdc_page_args.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/util/learning_service.dart';
import 'package:nnbdc/util/study_track.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:nnbdc/widget/study_date_explanation_dialog.dart';
import 'package:provider/provider.dart';

class TodayPlanPage extends StatefulWidget {
  const TodayPlanPage({super.key});

  @override
  TodayPlanPageState createState() {
    return TodayPlanPageState();
  }
}

class TodayPlanPageState extends State<TodayPlanPage> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  Set<String> _masteredWordIds = {};
  /// 学习环节设置 tab：0=新词（学习轨道配置），1=旧词（复习轨道配置）
  int _studyStepsTab = 0;
  /// 学习轨道是否处于编辑模式（默认 false 为极简图形化显示模式，true 为完整配置编辑模式）
  bool _isEditingTracks = false;
  /// 新词三组规则（显式设置）；_newConfigSaved=false 表示未落库（当前为默认规则）
  String? _newCheckStep;
  List<String> _newCorrectSteps = [];
  List<String> _newWrongSteps = [];
  bool _newConfigSaved = false;
  /// 旧词三组规则（显式设置）；_reviewConfigSaved=false 表示未落库（当前为默认规则）
  String? _reviewCheckStep;
  List<String> _reviewCorrectSteps = [];
  List<String> _reviewWrongSteps = [];
  bool _reviewConfigSaved = false;

  /// 近期已下载/尝试下载的词书 ID 集合（防止导入后异步可见性延迟导致的循环）
  static final Map<String, DateTime> _recentlyDownloadedAt = {};
  static const Duration _reDownloadCooldown = Duration(seconds: 30);

  bool _isRecentlyDownloaded(String dictId) {
    final lastAt = _recentlyDownloadedAt[dictId];
    if (lastAt == null) return false;
    if (AppClock.now().difference(lastAt) > _reDownloadCooldown) {
      _recentlyDownloadedAt.remove(dictId);
      return false;
    }
    return true;
  }

  void _markDictsDownloaded(List<DictVo> dicts) {
    final now = AppClock.now();
    for (final d in dicts) {
      _recentlyDownloadedAt[d.id] = now;
    }
  }

  @override
  void initState() {
    super.initState();
    // 首页初始化时强制关停 ASR，同时在后台静默预加载语音识别模型，避免点击“开始学习”进入单词页面时因加载模型而产生阻塞卡顿
    Asr().stopMicrophone();
    unawaited(Asr().preloadModels());
    // 后台静默预加载并激活手写识别模型，避免后续使用手写板时产生冷启动延迟
    unawaited(OcrService.prepareModel());
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
  }

  StreamSubscription? _dakaSubscription;
  StreamSubscription? _wordDeletedSubscription;
  StreamSubscription? _wordMasteredSubscription;
  StreamSubscription? _wordUnMasteredSubscription;

  @override
  void dispose() {
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
      
      final db = MyDatabase.instance;
      _masteredWordIds = await StudyCacheManager().getMasteredWordIds(db, user!.id!);

      int calcNewWordCount = 0;
      for (var word in _todayWords!) {
        if (word.isTodayNewWord) calcNewWordCount++;
      }
      newWordCount = calcNewWordCount;
      oldWordCount = _todayWords!.length - newWordCount!;
      todayWordCount = _todayWords!.length;

      unawaited(_updateProgress());
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

    // 加载新旧词三组规则；未配置时使用默认值（不落库）
    final newCfg = await StudyStepsService().getThreeGroupConfig('new');
    _newConfigSaved = await _dbHasScopeConfig('new');
    _newCheckStep = newCfg.check;
    _newCorrectSteps = List.of(newCfg.correct);
    _newWrongSteps = List.of(newCfg.wrong);

    final reviewCfg = await StudyStepsService().getThreeGroupConfig('review');
    _reviewConfigSaved = await _dbHasScopeConfig('review');
    _reviewCheckStep = reviewCfg.check;
    _reviewCorrectSteps = List.of(reviewCfg.correct);
    _reviewWrongSteps = List.of(reviewCfg.wrong);

    if (user != null) {
      final db = MyDatabase.instance;
      _masteredWordIds = await StudyCacheManager().getMasteredWordIds(db, user!.id!);

      // 检查是否为新的一天。如果是，则不加载本地已有的旧批次单词，防止 UI 闪烁旧数据
      final today = app_date.DateUtils.businessDate(AppClock.now());
      bool isNewDay = user!.lastLearningDate == null ||
          !app_date.DateUtils.isSameBusinessDay(user!.lastLearningDate!, today);
      
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
      unawaited(_updateProgress());
      
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
      // 跳过近期刚下载过的词书（防止导入后数据库延迟可见导致的循环）
      if (_isRecentlyDownloaded(ld.dictId)) continue;

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
    if (!_isRecentlyDownloaded(commonDictId)) {
      Dict? commonDictExisting = await db.dictsDao.findById(commonDictId);
      if (commonDictExisting == null || !(await db.dictWordsDao.hasDictWords(commonDictId))) {
        dictsToDownload.add(DictVo.c2(commonDictId));
      }
    }

    if (dictsToDownload.isNotEmpty && mounted && !DictDownloadDialog.isShowing) {
      // 预标记：在对话框显示前标记为"已尝试下载"，防止对话框被其他页面弹窗拦截时漏标记
      _markDictsDownloaded(dictsToDownload);
      await DictDownloadDialog.show(
        context: context,
        dicts: dictsToDownload,
        onComplete: () {
          _markDictsDownloaded(dictsToDownload);
          // 通知其他页面（如"我"页面）词书下载完成，以便刷新数据
          EventBus.publishDictDownloadCompleted(DictDownloadCompletedEvent(
            dictIds: dictsToDownload.map((d) => d.id).toList(),
          ));
        },
      );
      // 词书下载完成后，刷新页面数据以更新学习进度显示
      await loadData();
      prepareResult = await StudyBo().prepareForStudy(false);
    }
  }


  Future<void> _updateProgress() async {
    if (_todayWords == null) {
      _totalStepCount = 0;
      _completedStepCount = 0;
      return;
    }

    // 每词按其自身轨道（学习轨道/复习轨道）的环节数贡献进度；
    // 轨道由今天首条评分日志的间隔固化（与 StudyBo 一致）
    final user = Global.getLoggedInUser();
    final today = AppClock.today();
    Map<String, ({int elapsedDays, int rating})> firstLogs = {};
    if (user != null && _todayWords!.isNotEmpty) {
      final db = MyDatabase.instance;
      final rows = await (db.select(db.learningLogs)
            ..where((l) =>
                l.userId.equals(user.id) &
                l.wordId.isIn(_todayWords!.map((w) => w.wordId)) &
                l.createTime.isBiggerOrEqualValue(today)))
          .get();
      final earliestTime = <String, DateTime>{};
      for (final row in rows) {
        final prev = earliestTime[row.wordId];
        if (prev == null || row.createTime.isBefore(prev)) {
          earliestTime[row.wordId] = row.createTime;
          firstLogs[row.wordId] =
              (elapsedDays: row.elapsedDays, rating: row.rating);
        }
      }
    }
    final newCfg = await StudyStepsService().getThreeGroupConfig('new');
    final reviewCfg = await StudyStepsService().getThreeGroupConfig('review');
    _totalStepCount = 0;
    _completedStepCount = 0;
    for (final word in _todayWords!) {
      final first = firstLogs[word.wordId];
      final trackLen = StudyTrack.trackOf(
        stability: word.stability,
        state: word.state,
        lastLearningDate: word.lastLearningDate,
        todayFirstLogElapsedDays: first?.elapsedDays,
        todayFirstLogRating: first?.rating,
        newCheck: newCfg.check,
        newCorrect: newCfg.correct,
        newWrong: newCfg.wrong,
        reviewCheck: reviewCfg.check,
        reviewCorrect: reviewCfg.correct,
        reviewWrong: reviewCfg.wrong,
        today: today,
      ).length;
      _totalStepCount += trackLen;
      _completedStepCount += word.getCompletedSteps(_masteredWordIds, trackLen);
    }
    // 异步计算完成后刷新进度显示（调用方多以 unawaited 方式调用）
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final darkModeState = context.watch<DarkMode>();
    final isDarkMode = darkModeState.isDarkMode;
    final themeStyle = darkModeState.themeStyle;
    final backgroundColor = isDarkMode ? const Color(0xFF090B10) : const Color(0xFFF9FAFB);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: AppThemeBackground(
              isDarkMode: isDarkMode,
              themeStyle: themeStyle,
            ),
          ),
          (!dataLoaded)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDarkMode ? Colors.white70 : const Color(0xFF111827),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isSyncingFromCloud ? 'SYNCING FROM CLOUD...' : 'LOADING PLAN',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  bottom: false,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // 极简顶栏（与原型 1:1 对齐：TODAY'S PLAN + 今日学习计划 + 右侧高级设置图标）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => StudyDateExplanationDialog.show(context),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "TODAY'S PLAN",
                                    style: TextStyle(
                                      color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.help_outline_rounded,
                                    size: 11,
                                    color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '今日学习计划',
                                  style: TextStyle(
                                    color: isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                if (_isSyncingFromCloud) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDarkMode ? Colors.white54 : Colors.black45,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        // 右侧高级设置按钮（圆形微容器）
                        GestureDetector(
                          onTap: () => _showAdvancedSettingsDialog(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.subtleBg,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.cardBorder,
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: context.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // 核心大仪表盘
                    renderMissionCard(),

                    const SizedBox(height: 22),

                    // 学习轨道区域
                    renderStudySteps(),

                    const SizedBox(height: 20),

                    // 底部辅助说明
                    Center(
                      child: Text(
                        '学习未开始前可随时调整目标 · 开始后将自动锁定',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget renderMissionCard() {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final isDarkMode = themeStyle.isDark;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final progress = _totalStepCount > 0 ? (_completedStepCount / _totalStepCount) : 0.0;
    final isStarted = user?.todayStudyStarted == true;

    final textPrimary = themeConfig.textPrimary;
    final textSecondary = themeConfig.textSecondary;
    final textMuted = themeConfig.textMuted;
    final cardBg = themeConfig.cardBg;
    final cardBorder = themeConfig.cardBorder;
    final subtleBg = themeConfig.subtleBg;
    final cardShadows = themeConfig.cardShadows;
    final dividerColor = themeStyle.isDark ? Colors.white.withValues(alpha: 0.06) : themeConfig.primaryColor.withValues(alpha: 0.12);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: cardShadows,
      ),
      child: Column(
        children: [
          // 今日目标超大数字（点击整个数字或胶囊均可修改词数）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isStarted
                ? () => ToastUtil.info('今日学习已开始，单词数已锁定')
                : () => _showWordsSelectionBottomSheet(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${user?.effectiveWordsPerDay ?? 0}',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      fontFamilyFallback: const ['.SF Pro Display', 'SF Pro Display', 'Helvetica Neue', 'Roboto', 'PingFang SC', 'sans-serif'],
                      letterSpacing: -1.5,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: subtleBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'WORDS',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 2),
                        if (!isStarted)
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 14,
                            color: textSecondary,
                          )
                        else
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 11,
                            color: textMuted,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 极细进度条（260px 宽度，5px 高度，扇贝绿填充）
          SizedBox(
            width: 260,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: isDarkMode ? Colors.white12 : themeConfig.primaryColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(themeConfig.primaryColor),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '今日进度 $_completedStepCount / $_totalStepCount',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 双列对称纯色数据（新词 | 复习）
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: dividerColor),
                bottom: BorderSide(color: dividerColor),
              ),
            ),
            child: Row(
              children: [
                _buildStatItem('新词', newWordCount ?? 0),
                Container(width: 1, height: 22, color: dividerColor),
                _buildStatItem('复习', oldWordCount ?? 0),
              ],
            ),
          ),

          // 任务量不足提示
          if (prepareResult != null &&
              prepareResult!.success &&
              (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 20) &&
              !_hasTriedSupplement)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2E1A05) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '任务量不足，建议补充单词',
                        style: TextStyle(
                          color: isDarkMode ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        foregroundColor: isDarkMode ? Colors.white : Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => loadData(forceSupplement: true),
                      child: const Text('补充', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // 主操作按钮（50px 高度扇贝绿大胶囊）
          (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 0)))
              ? renderErrorActions()
              : renderStartButton(),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final textPrimary = themeConfig.textPrimary;
    final textMuted = themeConfig.textMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (label == '今日总词') {
            toTodayWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          } else if (label == '新词') {
            toTodayNewWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          } else if (label == '复习') {
            toTodayOldWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          }
        },
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFamilyFallback: const ['.SF Pro Display', 'SF Pro Display', 'Helvetica Neue', 'Roboto', 'PingFang SC', 'sans-serif'],
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWordsSelectionBottomSheet() {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final currentValue = user?.effectiveWordsPerDay ?? 20;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF11141D) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择每日学习词数',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDarkMode ? Colors.white : const Color(0xFF111827),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [2, 3, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500].map((v) {
                    final isSelected = v == currentValue;
                    final isPremium = SubscriptionUtil.isPremium();
                    final isRestricted = !isPremium && v > 20;

                    return GestureDetector(
                      onTap: () async {
                        if (isRestricted) {
                          ToastUtil.info('开通会员可选择更多单词数量');
                          return;
                        }
                        Navigator.pop(ctx);
                        setState(() {
                          user!.wordsPerDay = v;
                          dataLoaded = false;
                        });
                        await MyDatabase.instance.usersDao.updateWordsPerDay(user!.id!, v);
                        await Global.loadUserFromDb();
                        ThrottledDbSyncService().requestSync();
                        loadData(forceSupplement: false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDarkMode ? Colors.white : const Color(0xFF111827))
                              : (isDarkMode ? const Color(0xFF181C28) : const Color(0xFFF3F4F6)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$v 词',
                              style: TextStyle(
                                color: isSelected
                                    ? (isDarkMode ? Colors.black : Colors.white)
                                    : (isDarkMode ? Colors.white : const Color(0xFF111827)),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            if (isRestricted) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 13),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget renderStartButton() {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    if (hasDakaToday && _totalStepCount > 0 && _completedStepCount >= _totalStepCount) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: themeConfig.subtleBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: themeConfig.cardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: themeConfig.primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              '今日目标已达成',
              style: TextStyle(
                color: themeConfig.primaryColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: themeConfig.primaryColor,
          foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
          elevation: 2,
          shadowColor: themeConfig.primaryColor.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        onPressed: () async {
          if (_newCheckStep == null) {
            ToastUtil.error('请选择测评环节');
            return;
          }

          if (!(user?.todayStudyStarted ?? false)) {
            final shouldStart = await showDialog<bool>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.55),
              builder: (ctx) {
                final dialogThemeStyle = ctx.watch<DarkMode>().themeStyle;
                final dialogConfig = AppThemeConfig.of(dialogThemeStyle);
                final isDarkMode = dialogThemeStyle.isDark;
                final cardBg = dialogConfig.cardBg;
                final cardBorder = dialogConfig.cardBorder;
                final textMain = dialogConfig.textPrimary;
                final textSub = dialogConfig.textSecondary;
                final subtleBg = dialogConfig.subtleBg;
                final accentColor = dialogConfig.primaryColor;
                final primarySoft = dialogConfig.subtleBg;
                final amberColor = const Color(0xFFF59E0B);

                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.5 : 0.12),
                          blurRadius: 36,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 顶部火箭图标展台
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: primarySoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cardBorder, width: 1),
                          ),
                          child: Icon(
                            Icons.rocket_launch_rounded,
                            size: 26,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 标题
                        Text(
                          '开启今日学习旅程',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: textMain,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 副标题
                        Text(
                          '今日学习计划已就绪，准备好专注背单词了吗？',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textSub,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 锁定规则提示微卡片
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: subtleBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorder, width: 0.8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: amberColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '一旦开启，今日的单词量与测评环节将锁定生效，助你保持专注节奏。',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: textSub,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // 双操作按钮
                        Row(
                          children: [
                            // 取消按钮
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: subtleBg,
                                    foregroundColor: textSub,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                      side: BorderSide(color: cardBorder, width: 1),
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(
                                    '稍等修改',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: textSub,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // 确认按钮
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                                    elevation: 2,
                                    shadowColor: accentColor.withValues(alpha: 0.35),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '马上开始',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 14,
                                        color: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );

            if (shouldStart != true) {
              return;
            }
          }

          if (user != null) {
            try {
              await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "开始学习");
              final dbUser = await MyDatabase.instance.usersDao.getUserById(user!.id!);
              if (dbUser != null) {
                await MyDatabase.instance.usersDao.saveUser(
                    dbUser.copyWith(todayStudyStarted: true, lastLearningDate: drift.Value(AppClock.today())), true);
              }
              await Global.loadUserFromDb();

              unawaited(() async {
                try {
                  ThrottledDbSyncService().requestSync(immediate: true);
                } catch (e) {
                  Global.logger.e('开始学习发起网络同步失败: $e');
                }
              }());
            } catch (e, st) {
              Global.logger.e('记录开始学习状态失败', error: e, stackTrace: st);
            }
          }
          await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
          if (!mounted) return;
          if (PlatformUtils.isIOS || PlatformUtils.isAndroid) {
            unawaited(Asr().warmupMicrophone());
          }
          context.push('/bdc').then((value) {
            if (mounted && !_isLoadingData) loadData(isReturnFromStudy: true);
          });
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              user?.todayStudyStarted == true ? '继续学习' : '开始学习',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            const Text('➔', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
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
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text('词书单词量不足', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                  side: BorderSide(color: isDarkMode ? Colors.white24 : Colors.black12),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => context.push('/select_book').then((v) {
                  if (mounted) loadData(forceSupplement: true);
                }),
                child: const Text('选择词书', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if ((todayWordCount ?? 0) > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.white : const Color(0xFF111827),
                    foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
                    if (!mounted) return;
                    if (PlatformUtils.isIOS || PlatformUtils.isAndroid) {
                      unawaited(Asr().warmupMicrophone());
                    }
                    context.push('/bdc');
                  },
                  child: const Text('就这样吧', style: TextStyle(fontWeight: FontWeight.bold)),
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
        // 标题与切换模式按钮
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '学习轨道',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _isEditingTracks = !_isEditingTracks),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.subtleBg,
                    border: Border.all(
                      color: context.cardBorder,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isEditingTracks ? Icons.check_rounded : Icons.settings_rounded,
                        size: 12,
                        color: context.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isEditingTracks ? '完成配置' : '调整轨道',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 显示模式 vs 编辑模式
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _isEditingTracks ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: _buildTrackDisplayCard(isDarkMode),
          secondChild: _buildTrackEditCard(isDarkMode),
        ),
      ],
    );
  }

  /// 【显示模式】—— 极简纯无框图形化决策树卡片
  Widget _buildTrackDisplayCard(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final dividerColor = isDarkMode ? Colors.white.withValues(alpha: 0.06) : themeConfig.primaryColor.withValues(alpha: 0.12);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: themeConfig.cardBorder, width: 1),
        boxShadow: themeConfig.cardShadows,
      ),
      child: Column(
        children: [
          // 新词轨道（点击精准定位至新词轨道配置 Tab）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _studyStepsTab = 0;
              _isEditingTracks = true;
            }),
            child: _buildVisualForkTree(
              title: '新词轨道',
              checkStep: _newCheckStep ?? 'En2Ch',
              correctSteps: _newCorrectSteps,
              wrongSteps: _newWrongSteps,
              isDarkMode: isDarkMode,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(height: 1, color: dividerColor),
          ),
          // 旧词轨道（点击精准定位至旧词轨道配置 Tab）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _studyStepsTab = 1;
              _isEditingTracks = true;
            }),
            child: _buildVisualForkTree(
              title: '旧词轨道',
              checkStep: _reviewCheckStep ?? 'En2Ch',
              correctSteps: _reviewCorrectSteps,
              wrongSteps: _reviewWrongSteps,
              isDarkMode: isDarkMode,
            ),
          ),
        ],
      ),
    );
  }

  /// 绘制单个轨道的纯无框图形化分叉树（1:1 对齐原型）
  Widget _buildVisualForkTree({
    required String title,
    required String checkStep,
    required List<String> correctSteps,
    required List<String> wrongSteps,
    required bool isDarkMode,
  }) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final checkDesc = StudyStepExt.fromString(checkStep).description;
    final subColor = themeConfig.textMuted;
    final badgeBg = themeConfig.subtleBg;
    final textPrimary = themeConfig.textPrimary;
    final textSecondary = themeConfig.textSecondary;
    final themeAccent = themeConfig.primaryColor;
    final themeAccentBg = isDarkMode ? themeConfig.primaryColor.withValues(alpha: 0.22) : themeConfig.primaryColor.withValues(alpha: 0.12);
    final errorCoral = const Color(0xFFEF4444);
    final errorCoralBg = isDarkMode ? const Color(0x28EF4444) : const Color(0xFFFEF2F2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：测评节点
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: themeConfig.cardBorder,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '测评',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: themeAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    checkDesc,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // 中间：Bezier 曲线导线
            SizedBox(
              width: 22,
              height: 64,
              child: CustomPaint(
                painter: ForkBezierPainter(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.15) : themeConfig.primaryColor.withValues(alpha: 0.25),
                ),
              ),
            ),

            // 右侧：纯胶囊自适应流（零多余大外框）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 答对分支
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: themeAccentBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: themeAccent,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '答对',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: themeAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (correctSteps.isEmpty)
                        Text(
                          '直接完成',
                          style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                        )
                      else
                        ...() {
                          final items = <Widget>[];
                          for (int i = 0; i < correctSteps.length; i++) {
                            items.add(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  StudyStepExt.fromString(correctSteps[i]).description,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                                ),
                              ),
                            );
                            if (i < correctSteps.length - 1) {
                              items.add(
                                Text('➔', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: subColor)),
                              );
                            }
                          }
                          return items;
                        }(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 答错分支
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: errorCoralBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: errorCoral,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '答错',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: errorCoral,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wrongSteps.isEmpty)
                        Text(
                          '明日重现',
                          style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                        )
                      else
                        ...() {
                          final items = <Widget>[];
                          for (int i = 0; i < wrongSteps.length; i++) {
                            items.add(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  StudyStepExt.fromString(wrongSteps[i]).description,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                                ),
                              ),
                            );
                            if (i < wrongSteps.length - 1) {
                              items.add(
                                Text('➔', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: subColor)),
                              );
                            }
                          }
                          return items;
                        }(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 【编辑模式】—— 完整新旧词规则配置卡片
  Widget _buildTrackEditCard(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final badgeBg = themeConfig.subtleBg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: themeConfig.cardBorder, width: 1),
        boxShadow: themeConfig.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab 切换（新词配置 / 旧词配置）
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSubtleTabBtn('新词轨道配置', 0, isDarkMode),
                _buildSubtleTabBtn('旧词轨道配置', 1, isDarkMode),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildReviewStepsInfoCard(scope: _studyStepsTab == 0 ? 'new' : 'review', isDarkMode: isDarkMode),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeConfig.primaryColor,
                foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => setState(() => _isEditingTracks = false),
              child: const Text('完成配置', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtleTabBtn(String title, int tabIndex, bool isDarkMode) {
    final isSelected = _studyStepsTab == tabIndex;
    final selectedColor = context.primaryColor;
    final textMuted = context.textSecondary;

    return GestureDetector(
      onTap: () => setState(() => _studyStepsTab = tabIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDarkMode ? context.subtleBg : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? selectedColor : textMuted,
          ),
        ),
      ),
    );
  }

  /// 规则编辑配置内容（测评下拉 + 答对/答错环节列表与拖拽）
  Widget _buildReviewStepsInfoCard({required String scope, required bool isDarkMode}) {
    final textColor = isDarkMode ? Colors.white : const Color(0xFF111827);
    const allStepNames = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'ChSentence2En'];
    String desc(String s) => StudyStepExt.fromString(s).description;
    final isNew = scope == 'new';

    String? checkStep() => isNew ? _newCheckStep : _reviewCheckStep;
    List<String> correctSteps() => isNew ? _newCorrectSteps : _reviewCorrectSteps;
    List<String> wrongSteps() => isNew ? _newWrongSteps : _reviewWrongSteps;

    void setCheck(String v) => setState(() {
          if (isNew) {
            _newCheckStep = v;
          } else {
            _reviewCheckStep = v;
          }
        });
    void mutateCorrect(void Function(List<String>) fn) => setState(() {
          fn(isNew ? _newCorrectSteps : _reviewCorrectSteps);
        });
    void mutateWrong(void Function(List<String>) fn) => setState(() {
          fn(isNew ? _newWrongSteps : _reviewWrongSteps);
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 测评环节下拉
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF181C28) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '测评环节',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: checkStep() ?? allStepNames.first,
                  isDense: true,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor),
                  dropdownColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final s in allStepNames)
                      DropdownMenuItem(value: s, child: Text(desc(s))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setCheck(v);
                      unawaited(saveReviewConfig(scope));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 答对分支
        _buildReviewBranch(
          title: '答对后环节',
          titleColor: isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669),
          emptyHint: isNew ? '空：测评答对即完成' : '空：答对即完成',
          steps: correctSteps(),
          allStepNames: allStepNames,
          isDarkMode: isDarkMode,
          onAdd: () => _pickReviewStepForBranch(scope, allStepNames, isCorrect: true),
          onRemove: (s) {
            mutateCorrect((list) => list.remove(s));
            unawaited(saveReviewConfig(scope));
          },
          onReorder: (oldIdx, newIdx) {
            mutateCorrect((list) {
              if (newIdx > oldIdx) newIdx--;
              final item = list.removeAt(oldIdx);
              list.insert(newIdx, item);
            });
            unawaited(saveReviewConfig(scope));
          },
        ),
        const SizedBox(height: 10),

        // 答错分支
        _buildReviewBranch(
          title: '答错后环节',
          titleColor: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
          emptyHint: isNew ? '空：测评答错即结束，明日重现' : '空：答错即结束，明日重现',
          steps: wrongSteps(),
          allStepNames: allStepNames,
          isDarkMode: isDarkMode,
          onAdd: () => _pickReviewStepForBranch(scope, allStepNames, isCorrect: false),
          onRemove: (s) {
            mutateWrong((list) => list.remove(s));
            unawaited(saveReviewConfig(scope));
          },
          onReorder: (oldIdx, newIdx) {
            mutateWrong((list) {
              if (newIdx > oldIdx) newIdx--;
              final item = list.removeAt(oldIdx);
              list.insert(newIdx, item);
            });
            unawaited(saveReviewConfig(scope));
          },
        ),
      ],
    );
  }

  Widget _buildReviewBranch({
    required String title,
    required Color titleColor,
    required String emptyHint,
    required List<String> steps,
    required List<String> allStepNames,
    required bool isDarkMode,
    required VoidCallback onAdd,
    required void Function(String) onRemove,
    required void Function(int, int) onReorder,
  }) {
    final textColor = isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final subColor = isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final bool canAdd = allStepNames.any((s) => !steps.contains(s));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: titleColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            if (canAdd)
              GestureDetector(
                onTap: onAdd,
                child: Text(
                  '+ 添加',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(emptyHint, style: TextStyle(fontSize: 11, color: subColor)),
          )
        else
          ReorderableListView(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // ignore: deprecated_member_use
            onReorder: onReorder,
            children: [
              for (int i = 0; i < steps.length; i++)
                Container(
                  key: ValueKey('review_${title}_$i'),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF181C28) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    ),
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_indicator_rounded, size: 16, color: subColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          StudyStepExt.fromString(steps[i]).description,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onRemove(steps[i]),
                        child: Icon(Icons.close_rounded, size: 16, color: subColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// 分支"添加环节"：弹窗列出该分支未添加的环节
  Future<void> _pickReviewStepForBranch(
      String scope, List<String> allStepNames,
      {required bool isCorrect}) async {
    final isNew = scope == 'new';
    final current = isCorrect
        ? (isNew ? _newCorrectSteps : _reviewCorrectSteps)
        : (isNew ? _newWrongSteps : _reviewWrongSteps);
    final available = allStepNames.where((s) => !current.contains(s)).toList();
    if (available.isEmpty) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isCorrect ? '添加"答对后"环节' : '添加"答错后"环节'),
        children: [
          for (final s in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(StudyStepExt.fromString(s).description),
            ),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isCorrect) {
          (isNew ? _newCorrectSteps : _reviewCorrectSteps).add(picked);
        } else {
          (isNew ? _newWrongSteps : _reviewWrongSteps).add(picked);
        }
      });
      unawaited(saveReviewConfig(scope));
    }
  }

  /// 表内是否已有该 scope 的配置（用于"默认规则"提示）
  Future<bool> _dbHasScopeConfig(String scope) async {
    final user = Global.getLoggedInUser();
    if (user == null) return false;
    final steps = await MyDatabase.instance.userStudyStepsDao.getStepsOfScope(user.id, scope);
    return steps.isNotEmpty;
  }

  Future<void> saveReviewConfig(String scope) async {
    final isNew = scope == 'new';
    final check = isNew ? _newCheckStep : _reviewCheckStep;
    if (check == null) return;
    try {
      await StudyStepsService().saveThreeGroupConfig(
        scope: scope,
        check: check,
        correct: isNew ? _newCorrectSteps : _reviewCorrectSteps,
        wrong: isNew ? _newWrongSteps : _reviewWrongSteps,
      );
      if (mounted) {
        if (isNew && !_newConfigSaved) {
          setState(() => _newConfigSaved = true);
        } else if (!isNew && !_reviewConfigSaved) {
          setState(() => _reviewConfigSaved = true);
        }
      }
    } catch (e, s) {
      Global.logger.e('保存学习规则失败', error: e, stackTrace: s);
      ToastUtil.error('保存学习规则失败');
    }
  }

  /// 弹出"高级设置"对话框，可配置今日最少新词数量
  void _showAdvancedSettingsDialog() {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final isStarted = user?.todayStudyStarted == true;
    final config = StudyConfig.fromCurrentUser();
    final wordsPerDay = user?.effectiveWordsPerDay ?? 20;
    int selected = config.minNewWordsPerDay.clamp(0, wordsPerDay);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF11141D) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, size: 20),
              SizedBox(width: 8),
              Text('高级设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日最少新词数量',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.white70 : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isStarted)
                    Row(
                      children: [
                        Text(
                          '$selected',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: '今日学习已开始，无法修改最少新词数量',
                          triggerMode: TooltipTriggerMode.tap,
                          preferBelow: false,
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: isDarkMode ? Colors.white38 : Colors.black26,
                          ),
                        ),
                      ],
                    )
                  else
                    DropdownButton<int>(
                      value: selected,
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                      dropdownColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selected = value);
                      },
                      items: [
                        for (int v = 0; v <= wordsPerDay; v++)
                          DropdownMenuItem(
                            value: v,
                            child: Text(v == 0 ? '0（不限制）' : '$v'),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: isStarted
                  ? null
                  : () async {
                      config.minNewWordsPerDay = selected;
                      await config.saveToCurrentUser();
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      loadData(forceSupplement: true);
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 绘制极简 Bezier 分叉导线
class ForkBezierPainter extends CustomPainter {
  final Color color;
  const ForkBezierPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height / 2;
    // 向上扬起连接正确分支
    final pathUp = Path()
      ..moveTo(0, midY)
      ..cubicTo(size.width * 0.5, midY, size.width * 0.5, 12, size.width, 12);
    canvas.drawPath(pathUp, paint);

    // 向下探入连接错误分支
    final pathDown = Path()
      ..moveTo(0, midY)
      ..cubicTo(size.width * 0.5, midY, size.width * 0.5, size.height - 12, size.width, size.height - 12);
    canvas.drawPath(pathDown, paint);
  }

  @override
  bool shouldRepaint(covariant ForkBezierPainter oldDelegate) => oldDelegate.color != color;
}

