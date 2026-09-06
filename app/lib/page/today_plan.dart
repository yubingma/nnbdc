import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import "package:go_router/go_router.dart";
import "package:nnbdc/util/prefs.dart";
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/widget/frosted_glass_card.dart';
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
    final themeConfig = AppThemeConfig.of(themeStyle);
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              '今日学习计划',
                              style: TextStyle(
                                color: isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => StudyDateExplanationDialog.show(context),
                              child: Icon(
                                Icons.help_outline_rounded,
                                size: 16,
                                color: themeConfig.textSecondary.withValues(alpha: 0.45),
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
                        // 右侧高级设置按钮（微透晶莹小圆钮，呼应全页毛玻璃）
                        GestureDetector(
                          onTap: () => _showAdvancedSettingsDialog(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.85),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              size: 17,
                              color: themeConfig.textSecondary,
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
    final textMuted = themeConfig.textMuted;

    return FrostedGlassCard(
      borderRadius: 28,
      bgColor: isDarkMode ? const Color(0xB818202F) : const Color(0x80FFFFFF),
      borderColor: isDarkMode ? const Color(0x33FFFFFF) : const Color(0x24FFFFFF),
      shadow: BoxShadow(
        color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
      sigma: 7,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      child: Column(
        children: [
          // 今日目标超大数字（Roboto 挺拔修长 + 自然伴随轻量单位，告别发闷灰药丸）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isStarted
                ? () => ToastUtil.info('今日学习已开始，单词数已锁定')
                : () => _showWordsSelectionBottomSheet(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${user?.effectiveWordsPerDay ?? 0}',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Roboto',
                      letterSpacing: -1.8,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 单位裸排（告别药丸容器，符合"零多余容器"；baseline 与大数自然贴靠）
                  Text(
                    '词',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : themeConfig.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isStarted) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 13,
                      color: isDarkMode ? Colors.white70 : themeConfig.textSecondary,
                    ),
                  ] else ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 11,
                      color: textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 优雅极细胶囊进度条（先文案后胶囊，视觉平衡）
          SizedBox(
            width: 260,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '今日进度 $_completedStepCount / $_totalStepCount 步',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3.5,
                    backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                    valueColor: AlwaysStoppedAnimation<Color>(themeConfig.primaryColor),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 双列对称纯粹排版数据（新词 | 旧词，彻底去除突兀硬线分割，靠留白呼吸）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatItem('新词', newWordCount ?? 0, const Color(0xFF0EA5E9)),
                _buildStatItem('旧词', oldWordCount ?? 0, const Color(0xFF10B981)),
              ],
            ),
          ),

          // 任务量未满提示条：居中温润微光胶囊（告别生硬全宽横幅）
          if (prepareResult != null &&
              prepareResult!.success &&
              (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 20) &&
              !_hasTriedSupplement)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => loadData(forceSupplement: true),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                    decoration: BoxDecoration(
                      color: themeConfig.warmAccentColor.withValues(alpha: isDarkMode ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: themeConfig.warmAccentColor.withValues(alpha: isDarkMode ? 0.28 : 0.18),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: themeConfig.warmAccentColor,
                          size: 13.5,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '单词量未满',
                          style: TextStyle(
                            color: isDarkMode ? const Color(0xFFFED7AA) : themeConfig.warmAccentColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '点击补充 ›',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: themeConfig.warmAccentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // 主操作按钮
          (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 0)))
              ? renderErrorActions()
              : renderStartButton(),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, [Color? dotColor]) {
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
          } else if (label == '旧词') {
            toTodayOldWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
          }
        },
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
                letterSpacing: -0.8,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (dotColor != null) ...[
                  Container(
                    width: 5.5,
                    height: 5.5,
                    decoration: BoxDecoration(
                      color: dotColor.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 1.5),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 13,
                  color: textMuted.withValues(alpha: 0.45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showWordsSelectionBottomSheet() {
    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;
    final currentValue = user?.effectiveWordsPerDay ?? 20;
    final wordOptions = const [2, 3, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.15),
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDarkMode
                      ? [
                          const Color(0xB8161B26),
                          const Color(0x9910141D),
                        ]
                      : [
                          const Color(0x66FFFFFF),
                          const Color(0x4DFFFFFF),
                        ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? const Color(0x33FFFFFF)
                        : const Color(0x80FFFFFF),
                    width: 1.2,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部居中精致拖拽把手
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white24 : Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 标题栏（主副标题 + 轻圆关闭按钮）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '选择每日学习词数',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '根据每天的时间节奏定制专注目标',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: isDarkMode ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4 列规整网格
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: wordOptions.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 9,
                          crossAxisSpacing: 9,
                          childAspectRatio: 1.9,
                        ),
                        itemBuilder: (context, index) {
                          final v = wordOptions[index];
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
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor
                                    : (isDarkMode
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.white.withValues(alpha: 0.35)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : (isDarkMode
                                          ? const Color(0x20FFFFFF)
                                          : const Color(0x80FFFFFF)),
                                  width: 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: primaryColor.withValues(alpha: 0.32),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$v',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : (isDarkMode ? Colors.white : const Color(0xFF1E293B)),
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                      fontSize: 15,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '词',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white.withValues(alpha: 0.88)
                                          : (isDarkMode ? Colors.white38 : const Color(0xFF94A3B8)),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (isRestricted) ...[
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.workspace_premium_rounded,
                                      color: isSelected ? Colors.white : Colors.amber,
                                      size: 12,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
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

    final buttonFgColor = isDarkMode ? Colors.white : themeConfig.primaryColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? [
                      themeConfig.primaryColor.withValues(alpha: 0.38),
                      themeConfig.primaryColor.withValues(alpha: 0.22),
                    ]
                  : [
                      themeConfig.primaryColor.withValues(alpha: 0.22),
                      themeConfig.primaryColor.withValues(alpha: 0.12),
                    ],
            ),
            border: Border.all(
              color: isDarkMode
                  ? themeConfig.primaryColor.withValues(alpha: 0.50)
                  : themeConfig.primaryColor.withValues(alpha: 0.42),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: themeConfig.primaryColor.withValues(alpha: isDarkMode ? 0.25 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: buttonFgColor,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
        onPressed: () async {
          if (_newCheckStep == null) {
            ToastUtil.error('请选择测评环节');
            return;
          }

          if (!(user?.todayStudyStarted ?? false)) {
            final shouldStart = await showDialog<bool>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.35),
              builder: (ctx) {
                final dialogThemeStyle = ctx.watch<DarkMode>().themeStyle;
                final dialogConfig = AppThemeConfig.of(dialogThemeStyle);
                final isDarkMode = dialogThemeStyle.isDark;
                final cardBorder = isDarkMode
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.88);
                final textMain = dialogConfig.textPrimary;
                final textSub = dialogConfig.textSecondary;
                final subtleBg = isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.45);
                final accentColor = dialogConfig.primaryColor;
                final primarySoft = isDarkMode
                    ? accentColor.withValues(alpha: 0.18)
                    : accentColor.withValues(alpha: 0.12);
                final amberColor = const Color(0xFFF59E0B);

                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDarkMode
                                ? [
                                    const Color(0xFF1C2230).withValues(alpha: 0.84),
                                    const Color(0xFF121722).withValues(alpha: 0.78),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.82),
                                    Colors.white.withValues(alpha: 0.70),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cardBorder, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: buttonFgColor,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: buttonFgColor,
            ),
          ],
        ),
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
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题与轻量化切换模式按钮（纯文字链接，不再抢占主按钮视线）
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isEditingTracks ? Icons.check_rounded : Icons.tune_rounded,
                      size: 13,
                      color: _isEditingTracks ? context.primaryColor : themeConfig.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isEditingTracks ? '完成配置' : '调整轨道',
                      style: TextStyle(
                        color: _isEditingTracks ? context.primaryColor : themeConfig.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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

  /// 【显示模式】—— 极简微透图形化分叉决策树卡片
  Widget _buildTrackDisplayCard(bool isDarkMode) {
    final dividerColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? [
                      const Color(0xB818202F),
                      const Color(0x99121722),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.70),
                      Colors.white.withValues(alpha: 0.56),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.24),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
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
                child: Container(height: 0.6, color: dividerColor),
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
        ),
      ),
    );
  }

  /// 绘制单个轨道的图形化分叉决策树（高精度微节点 + 纤细导线 + 胶囊分支）
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
    final textPrimary = themeConfig.textPrimary;
    final textSecondary = themeConfig.textSecondary;
    final themeAccent = themeConfig.primaryColor;
    final successGreen = isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669);
    final errorCoral = isDarkMode ? const Color(0xFFF87171) : const Color(0xFFEF4444);
    final isNewWord = title.contains('新');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 轨道类型小标签（微圆点指示）
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isNewWord ? const Color(0xFF0EA5E9) : const Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：测评核心芯片节点（微透亚克力高光白边 + 极简科技感）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? themeAccent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: isDarkMode
                      ? themeAccent.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.95),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isDarkMode ? themeAccent : Colors.black).withValues(alpha: isDarkMode ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '测评',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: themeAccent,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    checkDesc,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // 中间：优雅 Bezier 导线
            SizedBox(
              width: 24,
              height: 58,
              child: CustomPaint(
                painter: ForkBezierPainter(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.22)
                      : themeConfig.primaryColor.withValues(alpha: 0.35),
                ),
              ),
            ),

            // 右侧：分叉步进流（胶囊标签 + 纯文字步进）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 答对分支
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: successGreen.withValues(alpha: isDarkMode ? 0.16 : 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 11.5, color: successGreen),
                            const SizedBox(width: 2.5),
                            Text(
                              '答对',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: successGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (correctSteps.isEmpty)
                        Text(
                          '直接结束',
                          style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                        )
                      else
                        ...() {
                          final items = <Widget>[];
                          for (int i = 0; i < correctSteps.length; i++) {
                            items.add(
                              Text(
                                StudyStepExt.fromString(correctSteps[i]).description,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            );
                            if (i < correctSteps.length - 1) {
                              items.add(
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: textSecondary.withValues(alpha: 0.4),
                                ),
                              );
                            }
                          }
                          return items;
                        }(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 答错分支
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: errorCoral.withValues(alpha: isDarkMode ? 0.16 : 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 11.5, color: errorCoral),
                            const SizedBox(width: 2.5),
                            Text(
                              '答错',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: errorCoral,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wrongSteps.isEmpty)
                        Text(
                          '直接结束',
                          style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                        )
                      else
                        ...() {
                          final items = <Widget>[];
                          for (int i = 0; i < wrongSteps.length; i++) {
                            items.add(
                              Text(
                                StudyStepExt.fromString(wrongSteps[i]).description,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            );
                            if (i < wrongSteps.length - 1) {
                              items.add(
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: textSecondary.withValues(alpha: 0.4),
                                ),
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
    final badgeBg = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? [
                      const Color(0xB818202F),
                      const Color(0x99121722),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.70),
                      Colors.white.withValues(alpha: 0.56),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.24),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 紧凑分段标签（新词轨道 / 旧词轨道）
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubtleTabBtn('新词轨道', 0, isDarkMode),
                    _buildSubtleTabBtn('旧词轨道', 1, isDarkMode),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildReviewStepsInfoCard(scope: _studyStepsTab == 0 ? 'new' : 'review', isDarkMode: isDarkMode),
            ],
          ),
        ),
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
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
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
        // 测评环节下拉条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 16,
                    color: themeConfig.primaryColor,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '测评环节',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: checkStep() ?? allStepNames.first,
                  isDense: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: isDarkMode ? Colors.white60 : const Color(0xFF64748B),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                  ),
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
          icon: Icons.check_circle_rounded,
          titleColor: isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669),
          emptyHint: '直接结束',
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
        const SizedBox(height: 12),

        // 答错分支
        _buildReviewBranch(
          title: '答错后环节',
          icon: Icons.cancel_rounded,
          titleColor: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
          emptyHint: '直接结束',
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
    required IconData icon,
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
                Icon(icon, size: 14, color: titleColor),
                const SizedBox(width: 5),
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
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: titleColor.withValues(alpha: isDarkMode ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 12, color: titleColor),
                      const SizedBox(width: 2),
                      Text(
                        '添加环节',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        if (steps.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.done_all_rounded,
                  size: 14,
                  color: isDarkMode ? Colors.white30 : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  emptyHint,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
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
                  margin: const EdgeInsets.symmetric(vertical: 2.5),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    boxShadow: isDarkMode
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(Icons.drag_indicator_rounded, size: 16, color: subColor),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          StudyStepExt.fromString(steps[i]).description,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRemove(steps[i]),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.close_rounded, size: 15, color: subColor),
                        ),
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

    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final titleColor = isCorrect
        ? (isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669))
        : (isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
    final titleText = isCorrect ? '添加答对后环节' : '添加答错后环节';
    final subText = isCorrect ? '单词测评正确后追加的学习环节' : '单词测评错误后追加的强化环节';

    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.25),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF1C2230).withValues(alpha: 0.96),
                          const Color(0xFF121722).withValues(alpha: 0.92),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.97),
                          Colors.white.withValues(alpha: 0.93),
                        ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部标题行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: titleColor.withValues(alpha: isDarkMode ? 0.20 : 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 18,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleText,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 可选环节卡片列表
                  for (int i = 0; i < available.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(ctx, available[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              StudyStepExt.fromString(available[i]).description,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: titleColor.withValues(alpha: isDarkMode ? 0.16 : 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 14,
                                color: titleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;
    final isStarted = user?.todayStudyStarted == true;
    final config = StudyConfig.fromCurrentUser();
    final wordsPerDay = user?.effectiveWordsPerDay ?? 20;
    int selected = config.minNewWordsPerDay.clamp(0, wordsPerDay);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.20),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDarkMode
                          ? [
                              const Color(0xFF1C2230).withValues(alpha: 0.90),
                              const Color(0xFF121722).withValues(alpha: 0.84),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.92),
                              Colors.white.withValues(alpha: 0.84),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.70),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部标题行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: isDarkMode ? 0.20 : 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.tune_rounded, size: 18, color: primaryColor),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '高级学习设置',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: isDarkMode ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 设置项说明与锁定标签
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '今日最少新词',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _showMinNewWordsExplanationDialog(ctx),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.help_outline_rounded,
                                        size: 16,
                                        color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isStarted ? '今日学习已开始，设置暂时锁定' : '优先保证每天的新词输入量',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          if (isStarted)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 13, color: isDarkMode ? Colors.white54 : Colors.black45),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$selected 词',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDarkMode ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      if (!isStarted) ...[
                        const SizedBox(height: 14),

                        // 步进调节条
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildAdvancedStepBtn(
                                icon: Icons.remove_rounded,
                                enabled: selected > 0,
                                onTap: () => setDialogState(() => selected = (selected - 1).clamp(0, wordsPerDay)),
                                isDarkMode: isDarkMode,
                              ),
                              Expanded(
                                child: Center(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: selected == 0 ? '不限制' : '$selected',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'Roboto',
                                            color: primaryColor,
                                          ),
                                        ),
                                        if (selected > 0)
                                          TextSpan(
                                            text: ' 词',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: primaryColor.withValues(alpha: 0.8),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _buildAdvancedStepBtn(
                                icon: Icons.add_rounded,
                                enabled: selected < wordsPerDay,
                                onTap: () => setDialogState(() => selected = (selected + 1).clamp(0, wordsPerDay)),
                                isDarkMode: isDarkMode,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2 行 × 3 列 规整快捷药丸标签
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildAdvancedQuickChip('不限制', 0, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('5词', 5, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: wordsPerDay >= 5)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('10词', 10, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: wordsPerDay >= 10)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildAdvancedQuickChip('20词', 20, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: wordsPerDay >= 20)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('30词', 30, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: wordsPerDay >= 30)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('全学新词', wordsPerDay, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: wordsPerDay > 0)),
                              ],
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),

                      // 底部对称行动条
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: TextButton.styleFrom(
                                  backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                                  foregroundColor: isDarkMode ? Colors.white70 : const Color(0xFF64748B),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: isStarted
                                    ? null
                                    : () async {
                                        config.minNewWordsPerDay = selected;
                                        await config.saveToCurrentUser();
                                        if (ctx.mounted) Navigator.of(ctx).pop();
                                        loadData(forceSupplement: true);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Center(
                                  child: Text('保存设置', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdvancedStepBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled
              ? (isDarkMode ? Colors.white.withValues(alpha: 0.10) : Colors.white)
              : (isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled && !isDarkMode
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? (isDarkMode ? Colors.white : const Color(0xFF1E293B))
              : (isDarkMode ? Colors.white24 : Colors.black26),
        ),
      ),
    );
  }

  Widget _buildAdvancedQuickChip(
    String label,
    int value,
    int selectedValue,
    ValueChanged<int> onSelect,
    Color primaryColor,
    bool isDarkMode, {
    bool enabled = true,
  }) {
    final isSelected = enabled && value == selectedValue;
    return GestureDetector(
      onTap: enabled ? () => onSelect(value) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? (isDarkMode ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF1F5F9))
              : isSelected
                  ? primaryColor.withValues(alpha: isDarkMode ? 0.22 : 0.10)
                  : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: !enabled
                ? Colors.transparent
                : isSelected
                    ? primaryColor
                    : (isDarkMode ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: !enabled
                ? (isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1))
                : isSelected
                    ? primaryColor
                    : (isDarkMode ? Colors.white70 : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  /// 弹出今日最少新词规则说明（作用与负面效果说明）
  void _showMinNewWordsExplanationDialog(BuildContext parentCtx) {
    final darkMode = parentCtx.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;

    showDialog<void>(
      context: parentCtx,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.25),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF1C2230).withValues(alpha: 0.94),
                          const Color(0xFF121722).withValues(alpha: 0.90),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.95),
                          Colors.white.withValues(alpha: 0.90),
                        ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.80),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部标题行（含右上角关闭按钮）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: isDarkMode ? 0.20 : 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.help_outline_rounded, size: 18, color: primaryColor),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '今日最少新词规则说明',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 设置作用区块（轻量通透排版，无多余边框容器）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: isDarkMode ? 0.18 : 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                                const SizedBox(width: 4),
                                const Text(
                                  '设置作用',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '系统默认根据记忆遗忘曲线优先安排复习。当待复习词较多时，今日配额可能全部被复习词占满。设置此项后，系统每天会强制保留至少指定数量的新词，保障背词进度稳步向前。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: isDarkMode ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      height: 0.5,
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),

                  // 潜在负面效果区块
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: isDarkMode ? 0.18 : 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_rounded, size: 12, color: Color(0xFFDC2626)),
                                const SizedBox(width: 4),
                                const Text(
                                  '潜在负面效果',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '每日总词量是固定的，强行增加新词会挤占当天本该复习的单词名额。被挤占的复习词会被延期推迟，若长期新词比例过高，会导致前置单词复习不及时、遗忘率上升，并造成复习负荷滚雪球式积压。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: isDarkMode ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 确认按钮
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Center(
                        child: Text(
                          '我知道了',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制极简纯粹 Bezier 分叉导线（去除冗余端点，保持平滑流动感）
class ForkBezierPainter extends CustomPainter {
  final Color color;
  const ForkBezierPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height / 2;
    // 向上扬起连接正确分支
    final pathUp = Path()
      ..moveTo(0, midY)
      ..cubicTo(size.width * 0.45, midY, size.width * 0.45, 12, size.width, 12);
    canvas.drawPath(pathUp, paint);

    // 向下探入连接错误分支
    final pathDown = Path()
      ..moveTo(0, midY)
      ..cubicTo(size.width * 0.45, midY, size.width * 0.45, size.height - 12, size.width, size.height - 12);
    canvas.drawPath(pathDown, paint);
  }

  @override
  bool shouldRepaint(covariant ForkBezierPainter oldDelegate) => oldDelegate.color != color;
}

