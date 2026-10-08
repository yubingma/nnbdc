import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:go_router/go_router.dart";
import "package:nnbdc/util/prefs.dart";
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:nnbdc/theme/page_vibrancy.dart';
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
import 'package:nnbdc/services/user_privilege_manager.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/page/subscription.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:provider/provider.dart';

/// 今日计划页可选背景。
///
/// [isDark] 是这张照片的明暗档：卡片只是一层半透明玻璃，字色必须与玻璃成套取色。
/// 只按 App 主题取色的话，遇到明暗和主题相反的照片就会糊字——浅色主题配宝蓝底的「石韵」，
/// 深色字压在宝石蓝玻璃上基本看不清。暗底 = 深色玻璃 + 白字，亮底 = 乳白玻璃 + 深色字。
class PlanWallpaper {
  const PlanWallpaper(this.name, this.path, {required this.isDark});

  final String name;
  final String path;

  /// 照片是不是暗底（暗底配白字，亮底配深色字）。
  final bool isDark;
}

const List<PlanWallpaper> planWallpapers = [
  PlanWallpaper('旷野', 'assets/images/wallpaper/tree.jpg', isDark: true),
  PlanWallpaper('竹韵', 'assets/images/wallpaper/bamboo.jpg', isDark: true),
  PlanWallpaper('枫韵', 'assets/images/wallpaper/maple.jpg', isDark: false),
  PlanWallpaper('石韵', 'assets/images/wallpaper/stone.jpg', isDark: true),
  PlanWallpaper('童趣', 'assets/images/wallpaper/kitty.jpg', isDark: true),
  PlanWallpaper('晨雾', 'assets/images/scenes/mist.jpg', isDark: false),
  PlanWallpaper('湖光', 'assets/images/scenes/river.jpg', isDark: true),
  PlanWallpaper('夏夜', 'assets/images/scenes/night.jpg', isDark: true),
  // 经典 = 不用照片，走主题底，卡片与字色整套跟 App 主题（isDark 不参与）
  PlanWallpaper('经典', 'none', isDark: false),
];

class TodayPlanPage extends StatefulWidget {
  const TodayPlanPage({super.key, this.bottomNavReserve = 0});

  /// 外壳悬浮底栏占用的高度（底栏内容 + 底部安全区），由 IndexPage 注入。
  ///
  /// 页面自己问不出来：外壳的 Scaffold 开着 extendBody，会把 body 的 MediaQuery 底部内边距剥成 0。
  /// 而底栏虽然透明，却实打实占着屏幕最底部那一整块并吞掉点击，所以页面底部必须让开这么多，
  /// "开始学习/继续学习"才不会压在底栏下面点不到。
  final double bottomNavReserve;

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

  /// 背景壁纸
  String _wallpaperPath = 'assets/images/scenes/mist.jpg';

  /// 点击"开始学习"后正在等待今日计划就绪：按钮据此给出"准备中"反馈，
  /// 避免计划准备期间（重装/换端后要等云端数据落地）点击后毫无动静。
  bool _isPreparingStudy = false;

  /// 在途的"今日计划准备"。点击"开始学习"必须等它完成：
  /// 跨天重置就发生在准备流程里，准备没完成就进学习页，昨天残留的进度会被当成今日已完成。
  Future<void>? _loadFuture;
  int _completedStepCount = 0;
  int _totalStepCount = 0;
  List<LearningWord>? _todayWords;

  /// 今日加量批次的词数（打卡后额外追加的那一组）。
  int _extraTotalCount = 0;

  /// 今日加量批次里已学完的词数。
  int _extraCompletedCount = 0;

  /// 加量批次里尚未学完的词数（由总数与已学完派生，避免两处口径打架）。
  /// > 0 表示还有加量要接着学，首页据此把主按钮换成"继续学习（加量）"入口。
  int get _pendingExtraWordCount => _extraTotalCount - _extraCompletedCount;
  Set<String> _masteredWordIds = {};
  /// 正在编辑的学习轨道作用域：null 为显示模式，'new' 为编辑新词轨道，'review' 为编辑旧词轨道。
  /// 用一个状态同时表达"是否在编辑"和"编辑哪条轨道"，避免编辑开关与 tab 索引两处状态互相打架。
  String? _editingTrackScope;
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

  /// 今日计划词（不含打卡后额外追加的加量批次）。
  /// 所有"今日计划"口径（进度环、词数统计、单词量未满提示）都必须用它，
  /// 否则加量会撑大计划分母，把已达成 100% 的进度打回未完成。
  List<LearningWord> get _planWords =>
      (_todayWords ?? const <LearningWord>[]).where((w) => !w.isExtra).toList();

  /// 今日加量词（打卡后额外追加的批次，不计入今日计划）
  List<LearningWord> get _extraWords =>
      (_todayWords ?? const <LearningWord>[]).where((w) => w.isExtra).toList();

  /// 加量批次里的新词数：跟在新词数字后面显示成「5+3」，一眼看出今天额外加了几个
  int get _extraNewCount => _extraWords.where((w) => w.isTodayNewWord).length;

  /// 加量批次里的旧词数
  int get _extraOldCount => _extraWords.length - _extraNewCount;

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
    _wallpaperPath = Prefs.read<String>('today_plan_wallpaper') ?? 'assets/images/wallpaper/tree.jpg';
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

    // 学习页学完（含加量批次）后只重算今日列表进度，不再走取词/削减：
    // 计划此刻已经学完，重新准备计划只会带来副作用。
    _todayStudyListChangedSubscription = EventBus.onTodayStudyListChanged().listen((event) {
      Global.logger.d('TodayPlanPage received TodayStudyListChangedEvent, refreshing data...');
      if (mounted && !_isLoadingData) {
        loadData(isReturnFromStudy: true);
      }
    });
  }

  StreamSubscription? _dakaSubscription;
  StreamSubscription? _wordDeletedSubscription;
  StreamSubscription? _wordMasteredSubscription;
  StreamSubscription? _wordUnMasteredSubscription;
  StreamSubscription? _todayStudyListChangedSubscription;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dakaSubscription?.cancel();
    _wordDeletedSubscription?.cancel();
    _wordMasteredSubscription?.cancel();
    _wordUnMasteredSubscription?.cancel();
    _todayStudyListChangedSubscription?.cancel();
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
    if (!forceSupplement) {
      _hasTriedSupplement = false;
    }
    if (_isLoadingData) {
      // 复用在途的今日计划准备，让调用方（如"开始学习"）能等到它完成
      Global.logger.d('loadData already in progress, awaiting in-flight prepare');
      await _loadFuture;
      return;
    }

    final future = _prepareTodayPlan(forceSupplement: forceSupplement, isReturnFromStudy: isReturnFromStudy);
    _loadFuture = future;
    try {
      await future;
    } finally {
      _loadFuture = null;
    }
  }

  /// 确保今日计划已就绪后再进入学习页：等在途的准备流程结束；若本日计划从未准备过，则主动准备一次。
  /// 任何"计划尚未就绪"的状态都不允许进入学习页——跨天重置尚未执行时，残留进度会被当成今日成绩。
  Future<void> _awaitPlanReady() async {
    if (_loadFuture != null) {
      await _loadFuture;
      return;
    }
    if (prepareResult == null) {
      await loadData();
    }
  }

  /// 今日计划的完整准备流程：本地加载 → 云端同步 → 跨天重置/取词 → 词书资源 → 统计
  Future<void> _prepareTodayPlan({required bool forceSupplement, required bool isReturnFromStudy}) async {
    Global.logger.d('Entering loadData: forceSupplement=$forceSupplement, _isLoadingData=$_isLoadingData');
    _isLoadingData = true;

    try {
      // 1. 第一步：优先从本地数据库快速加载现有数据，以便立刻展示 UI
      final bool isNewDay = await _loadEssentialLocalData();

      // 跨天时本日计划尚未初始化（跨天重置与取词都在第 3 步）；重装/换端后本地更是一份计划词都没有，
      // 计划数据还在云端。这两种情况都必须维持加载态：否则页面会呈现一个 0/0 的"就绪"假象，
      // 用户在计划就绪前点"开始学习"，跨天时还会把昨天残留的进度当成今日已完成。
      // 只有本地确实拿到了今日计划词，才允许提前展示 UI。
      // 注意：准备流程结束时（finally）无条件置 dataLoaded=true，因此这里不会把页面卡在加载态。
      final bool hasLocalPlan = _todayWords?.isNotEmpty ?? false;
      if (mounted) {
        setState(() {
          dataLoaded = !isNewDay && user != null && hasLocalPlan;
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
      for (var word in _planWords) {
        if (word.isTodayNewWord) calcNewWordCount++;
      }
      newWordCount = calcNewWordCount;
      oldWordCount = _planWords.length - newWordCount!;
      todayWordCount = _planWords.length;

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

  /// 快速加载本地基础数据（不涉及网络和复杂的计划准备）。
  /// 返回是否已跨天（跨天时本日计划还没初始化，页面必须保持"未就绪"直到准备流程跑完）。
  Future<bool> _loadEssentialLocalData() async {
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
        return true;
      }

      _todayWords = await LearningService.getTodayLearningWordsFromDb(user!.id!);
      unawaited(_updateProgress());
      
      // 估算今日单词数（基于本地已有数据）
      if (_todayWords != null && _todayWords!.isNotEmpty) {
        int calcNewWordCount = 0;
        for (var word in _planWords) {
          if (word.isTodayNewWord) calcNewWordCount++;
        }
        newWordCount = calcNewWordCount;
        oldWordCount = _planWords.length - newWordCount!;
        todayWordCount = _planWords.length;
      }
    }
    return false;
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
    // 轨道由今天首条评分日志的间隔固化（与 StudyBo 一致）。
    // 业务日窗口 [03:00, 次日03:00) 由 LearningLogsDao.getInBusinessDay 统一给出，
    // 不能用 AppClock.today()（业务日的当地 00:00）当下界，否则前一业务日 00:00~02:59
    // 的评分会被算成今天首条；返回结果按 createTime 正序，故每词首次出现即今天首条。
    final user = Global.getLoggedInUser();
    final today = AppClock.today(); // 业务日（当地 00:00），供 StudyTrack 判定轨道
    Map<String, ({int elapsedDays, int rating})> firstLogs = {};
    if (user != null && _todayWords!.isNotEmpty) {
      final rows = await MyDatabase.instance.learningLogsDao.getInBusinessDay(
          user.id,
          wordIds: _todayWords!.map((w) => w.wordId));
      for (final row in rows) {
        firstLogs.putIfAbsent(row.wordId,
            () => (elapsedDays: row.elapsedDays, rating: row.rating));
      }
    }
    final newCfg = await StudyStepsService().getThreeGroupConfig('new');
    final reviewCfg = await StudyStepsService().getThreeGroupConfig('review');

    // 每词按其自身轨道（计划词与加量词使用同一套轨道规则）推导长度
    int trackLenOf(LearningWord word) {
      final first = firstLogs[word.wordId];
      return StudyTrack.trackOf(
        isTodayNewWord: word.isTodayNewWord,
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
    }

    // 今日计划进度（严格排除加量词，保证打卡后不会因加量而回落）
    _totalStepCount = 0;
    _completedStepCount = 0;
    for (final word in _planWords) {
      final trackLen = trackLenOf(word);
      _totalStepCount += trackLen;
      final completedSteps = word.getCompletedSteps(_masteredWordIds, trackLen);
      _completedStepCount += completedSteps;
    }

    // 加量批次的口径：这一组一共多少词、学完了多少（主按钮是否换成"继续学习（加量）"也据此判定）
    _extraTotalCount = _extraWords.length;
    _extraCompletedCount = 0;
    for (final word in _extraWords) {
      final trackLen = trackLenOf(word);
      if (word.getCompletedSteps(_masteredWordIds, trackLen) >= trackLen) {
        _extraCompletedCount++;
      }
    }
    // 异步计算完成后刷新进度显示（调用方多以 unawaited 方式调用）
    if (mounted) setState(() {});
  }

  Widget _buildBackground(bool isDarkMode, AppThemeStyle themeStyle) {
    final hasWallpaper = _wallpaperPath.isNotEmpty && _wallpaperPath != 'none';
    if (!hasWallpaper) {
      return AppThemeBackground(
        isDarkMode: isDarkMode,
        themeStyle: themeStyle,
        config: PageVibrancy.todayPlan,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _wallpaperPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return AppThemeBackground(
              isDarkMode: isDarkMode,
              themeStyle: themeStyle,
              config: PageVibrancy.todayPlan,
            );
          },
        ),
        // 微渐变暗角光幕：顶部保护顶栏，底部保护仪表盘与按钮，中部通透
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.42),
                Colors.black.withValues(alpha: 0.78),
              ],
              stops: const [0.0, 0.32, 0.68, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopFloatingHeader(AppThemeConfig themeConfig, bool hasWallpaper, bool onDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_isSyncingFromCloud) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                hasWallpaper
                    ? (onDark ? Colors.white70 : const Color(0xFF334155))
                    : (onDark ? Colors.white54 : Colors.black45),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        // 右侧高级设置按钮（遵循极简规范：零多余容器，纯矢量图标轻灵悬浮呈现）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showAdvancedSettingsDialog,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.tune_rounded,
              size: 22,
              color: hasWallpaper
                  ? (onDark ? Colors.white.withValues(alpha: 0.90) : const Color(0xFF0F172A))
                  : themeConfig.textSecondary,
            ),
          ),
        ),
      ],
    );
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
            child: _buildBackground(isDarkMode, themeStyle),
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
                          color: isDarkMode ? Colors.white38 : const Color(0xFF475569),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hasWallpaper = _wallpaperPath.isNotEmpty && _wallpaperPath != 'none';
                      final int planTotalWords = _planWords.length;
                      final bool isDakaStamped = hasDakaToday;
                      final DateTime stampDay = AppClock.today();
                      final String stampDate =
                          '${stampDay.year}.${stampDay.month.toString().padLeft(2, '0')}.${stampDay.day.toString().padLeft(2, '0')}';

                      // 壁纸底与主题底共用这一套布局：顶部悬浮设置 / 中心目标岛 / 底部双任务岛 + 主按钮，
                      // 两种背景只差卡片那一层皮肤（见 _cardSkin），结构与间距完全一致。
                      //
                      // 底部必须给悬浮底栏让位：底栏（透明也一样）占着屏幕最底部且吞掉那一整块点击，
                      // 内容不让开，"开始学习/继续学习"就会被压在底栏下面点不到。
                      // 多让 20：主按钮下沿与底栏命中区之间留出安全距离，又不像 28 那样悬得过高。
                      final double bottomInset = widget.bottomNavReserve + 20;
                      // 字色档：跟壁纸照片的明暗走（无壁纸时等于 App 主题），不与玻璃底色脱钩
                      final bool onDark = _wallpaperIsDark ?? isDarkMode;
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset),
                        child: ConstrainedBox(
                          // 内容比屏幕矮时撑满视口：顶部区块留在设计位置、底部任务岛贴住底栏上沿；
                          // 内容比屏幕高时（小屏/横屏/大字号）整页滚动，按钮始终滚得到。
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 8 - bottomInset).clamp(0.0, double.infinity),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTopFloatingHeader(themeConfig, hasWallpaper, onDark),
                                  SizedBox(height: (constraints.maxHeight * 0.12).clamp(60.0, 110.0)),
                                  _buildStatusIsland(
                                    hasWallpaper: hasWallpaper,
                                    isDarkMode: isDarkMode,
                                    onDark: onDark,
                                    isDakaStamped: isDakaStamped,
                                    stampDate: stampDate,
                                    planTotalWords: planTotalWords,
                                  ),
                                  // 放不下而滚动时的最小间距，避免中心岛与任务岛贴在一起
                                  const SizedBox(height: 16),
                                ],
                              ),
                              _buildBottomTaskIsland(
                                themeConfig: themeConfig,
                                hasWallpaper: hasWallpaper,
                                isDarkMode: isDarkMode,
                                onDark: onDark,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  /// 当前壁纸照片的明暗档；「经典」（无壁纸）返回 null，表示卡片与字色整套跟 App 主题走。
  bool? get _wallpaperIsDark {
    if (_wallpaperPath.isEmpty || _wallpaperPath == 'none') return null;
    for (final wallpaper in planWallpapers) {
      if (wallpaper.path == _wallpaperPath) return wallpaper.isDark;
    }
    assert(false, '壁纸「$_wallpaperPath」没有登记明暗档，请补进 planWallpapers');
    // 未登记的陌生照片按暗底处理：深色玻璃 + 白字压在任何照片上都不会糊
    return true;
  }

  /// 卡片玻璃（保持原来的通透磨砂观感，不随照片改透明度）：
  /// 壁纸底沿用最初的透光白 22% / 深色 #6018202F，经典主题底用全站统一卡片色。
  ({Color bg, Color border, BoxShadow shadow}) _cardGlass({
    required bool hasWallpaper,
    required bool isDarkMode,
  }) {
    if (!hasWallpaper) {
      return (
        bg: context.pageCardBg(PageVibrancy.todayPlan),
        border: context.cardBorder,
        shadow: context.pageCardShadow(PageVibrancy.todayPlan),
      );
    }
    return (
      bg: isDarkMode ? const Color(0x6018202F) : Colors.white.withValues(alpha: 0.22),
      border: Colors.white.withValues(alpha: 0.20),
      shadow: BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    );
  }

  /// 卡片文字三档（主/次/弱）：玻璃保持通透，可读性只靠「按照片挑字色」这一件事。
  ///
  /// [belowScrim] 表示这块内容永远压在屏幕最底部的暗角光幕上（底部双任务卡）：那里永远是深底，
  /// 一律白字黑影最稳（实测 3.9~10.4，换深色字只剩 1.7~4.6）；中心岛浮在照片中段，
  /// 明暗完全由照片决定，只能按照片明暗档取色。
  ({Color primary, Color muted, Color faint}) _cardInk({
    required bool hasWallpaper,
    required bool onDark,
    bool belowScrim = false,
  }) {
    if (!hasWallpaper) {
      return (
        primary: onDark ? Colors.white : const Color(0xFF0F172A),
        muted: onDark ? Colors.white70 : const Color(0xFF475569),
        faint: onDark ? Colors.white60 : const Color(0xFF64748B),
      );
    }
    return (belowScrim || onDark)
        ? (
            primary: Colors.white,
            muted: Colors.white.withValues(alpha: 0.82),
            faint: Colors.white.withValues(alpha: 0.72),
          )
        : (
            primary: const Color(0xFF0F172A),
            muted: const Color(0xFF334155),
            faint: const Color(0xFF334155),
          );
  }

  /// 中心「打卡/日程岛」：高透圆角磨砂卡（对标「不背单词」日历签到卡）
  Widget _buildStatusIsland({
    required bool hasWallpaper,
    required bool isDarkMode,
    required bool onDark,
    required bool isDakaStamped,
    required String stampDate,
    required int planTotalWords,
  }) {
    final skin = _cardGlass(hasWallpaper: hasWallpaper, isDarkMode: isDarkMode);
    final ink = _cardInk(hasWallpaper: hasWallpaper, onDark: onDark);
    final sealColor = onDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        toTodayWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 138,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              color: skin.bg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: skin.border, width: 0.5),
              boxShadow: [skin.shadow],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDakaStamped) ...[
                  Icon(
                    Icons.check_circle_rounded,
                    size: 24,
                    color: sealColor,
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    container: true,
                    key: const Key('today_plan_daka_seal_text'),
                    label: '已打卡',
                    excludeSemantics: true,
                    child: Text(
                      '已打卡',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink.primary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    key: const Key('today_plan_daka_seal_date'),
                    label: stampDate,
                    child: const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 3),
                  ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stampDate,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: ink.muted,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 22,
                    color: ink.muted,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '今日目标',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink.primary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stampDate,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: ink.muted,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '目标 $planTotalWords 词',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: ink.faint,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 任务量未满提示条
  Widget _buildSupplementNoticeBar(AppThemeConfig themeConfig, bool hasWallpaper, bool onDark) {
    // 琥珀胶囊也要跟着照片明暗走：暗底用浅琥珀字，亮底换成深琥珀字，否则亮照片上整条都是糊的
    final Color noticeAccent;
    final Color noticeInk;
    final double noticeBgAlpha;
    final double noticeBorderAlpha;
    if (!hasWallpaper) {
      noticeAccent = themeConfig.warmAccentColor;
      noticeInk = onDark ? const Color(0xFFFED7AA) : themeConfig.warmAccentColor;
      noticeBgAlpha = onDark ? 0.20 : 0.08;
      noticeBorderAlpha = onDark ? 0.35 : 0.18;
    } else if (onDark) {
      noticeAccent = const Color(0xFFF59E0B);
      noticeInk = const Color(0xFFFDE68A);
      noticeBgAlpha = 0.20;
      noticeBorderAlpha = 0.35;
    } else {
      noticeAccent = const Color(0xFFB45309);
      noticeInk = const Color(0xFF92400E);
      noticeBgAlpha = 0.28;
      noticeBorderAlpha = 0.45;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => loadData(forceSupplement: true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: noticeAccent.withValues(alpha: noticeBgAlpha),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: noticeAccent.withValues(alpha: noticeBorderAlpha),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: noticeAccent,
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  '单词量未满',
                  style: TextStyle(
                    color: noticeInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '点击补充 ›',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: noticeAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 任务卡上的数字：有加量批次时跟一个更小的「+N」（今天额外追加的那一组），
  /// 让「今天的量」一眼看全，而不是只看到一个不含加量的计划数。
  Widget _buildTaskCount({
    required int count,
    required int extraCount,
    required Key extraKey,
    required Color color,
  }) {
    const numberStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      fontFamily: 'Roboto',
      letterSpacing: -0.5,
    );
    if (extraCount <= 0) {
      return Text('$count', style: numberStyle.copyWith(color: color));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$count', style: numberStyle.copyWith(color: color)),
        Text(
          ' + $extraCount',
          key: extraKey,
          style: numberStyle.copyWith(fontSize: 15, letterSpacing: -0.3, color: color),
        ),
      ],
    );
  }

  /// 底部「双任务岛与主操作」：扁平横向磨砂卡（对标「不背单词」Learn & Review）
  Widget _buildBottomTaskIsland({
    required AppThemeConfig themeConfig,
    required bool hasWallpaper,
    required bool isDarkMode,
    required bool onDark,
  }) {
    final skin = _cardGlass(hasWallpaper: hasWallpaper, isDarkMode: isDarkMode);
    final ink = _cardInk(hasWallpaper: hasWallpaper, onDark: onDark, belowScrim: true);
    final textMuted = ink.muted;
    final countColor = ink.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 左右并排双毛玻璃任务卡片（对标「不背单词」Learn & Review 结构）
        Row(
          children: [
            // 左卡片：新词
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  toTodayNewWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 62),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: skin.bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: skin.border, width: 0.5),
                        boxShadow: [skin.shadow],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '新词',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _buildTaskCount(
                            count: newWordCount ?? 0,
                            extraCount: _extraNewCount,
                            extraKey: const Key('today_plan_extra_new_count'),
                            color: countColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 右卡片：旧词
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  toTodayOldWordsListPage(true)?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 62),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: skin.bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: skin.border, width: 0.5),
                        boxShadow: [skin.shadow],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '旧词',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _buildTaskCount(
                            count: oldWordCount ?? 0,
                            extraCount: _extraOldCount,
                            extraKey: const Key('today_plan_extra_old_count'),
                            color: countColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // 任务量未满提示条（如有）
        if (prepareResult != null &&
            prepareResult!.success &&
            (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 20) &&
            !_hasTriedSupplement) ...[
          const SizedBox(height: 8),
          _buildSupplementNoticeBar(themeConfig, hasWallpaper, onDark),
        ],

        const SizedBox(height: 10),

        // 主操作按钮
        (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 0)))
            ? renderErrorActions()
            : renderStartButton(),
      ],
    );
  }




  /// 加量主按钮（首页"继续学习（加量）"/"再来一组"）
  Widget _buildExtraStudyButton(
    AppThemeConfig themeConfig,
    bool isDarkMode, {
    Key? key,
    required String label,
    required VoidCallback onPressed,
  }) {
    final hasWallpaper = _wallpaperPath.isNotEmpty && _wallpaperPath != 'none';
    // 主按钮压在屏幕最底部，那里永远有暗角光幕压深（实测白字对比度 7.9~19.9），
    // 所以壁纸底一律白字 + 黑影：跟着亮底照片改深色字的话，按钮区只剩 1.0~2.3，等于看不见。
    final actionColor = hasWallpaper
        ? Colors.white
        : (isDarkMode ? themeConfig.primaryLightColor : themeConfig.primaryColor);
    final actionShadows = hasWallpaper
        ? const [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 1.5))]
        : null;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: actionColor,
                    shadows: actionShadows,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: actionColor,
                  shadows: actionShadows,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 进入学习页（沿用"开始学习"的入口约定）
  Future<void> _gotoStudyPage() async {
    await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
    if (!mounted) return;
    context.push('/bdc').then((value) {
      if (mounted && !_isLoadingData) loadData(isReturnFromStudy: true);
    });
  }

  /// 继续未完成的加量批次：直接回到学习页，绝不追加新词
  /// （学习页按 batchId 顺序会自动定位到未学完的加量批次）
  Future<void> _resumeExtraStudy() => _gotoStudyPage();

  /// 追加一组新的加量单词后进入学习页。加量是会员权益，非会员引导至订阅页。
  Future<void> _startExtraStudy() async {
    if (!UserPrivilegeManager.canExtraStudy) {
      ToastUtil.info('加量是会员专属权益');
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscriptionPage()),
      );
      return;
    }

    final result = await StudyBo().prepareExtraStudy();
    if (!mounted) return;
    if (!result.success) {
      ToastUtil.error(result.msg ?? '加量失败');
      return;
    }

    await _gotoStudyPage();
  }

  Widget renderStartButton() {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;
    final hasWallpaper = _wallpaperPath.isNotEmpty && _wallpaperPath != 'none';

    final bool planFinished =
        _totalStepCount > 0 && _completedStepCount >= _totalStepCount;

    if (hasDakaToday && planFinished) {
      if (_pendingExtraWordCount > 0) {
        return _buildExtraStudyButton(
          themeConfig,
          isDarkMode,
          label: '继续学习（加量）',
          onPressed: _resumeExtraStudy,
        );
      }
      return _buildExtraStudyButton(
        themeConfig,
        isDarkMode,
        key: const Key('today_plan_extra_again_btn'),
        label: '再来一组（加量）',
        onPressed: _startExtraStudy,
      );
    }

    // 同上：底部按钮永远压在暗角光幕上，壁纸底一律白字 + 黑影
    final actionColor = hasWallpaper
        ? Colors.white
        : (isDarkMode ? themeConfig.primaryLightColor : themeConfig.primaryColor);
    final actionShadows = hasWallpaper
        ? const [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 1.5))]
        : null;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            if (_isPreparingStudy) return;
            if (_newCheckStep == null) {
              ToastUtil.error('请选择测评环节');
              return;
            }

            // 必须等今日计划准备完成再进入学习页：跨天重置就发生在准备流程里，
            // 计划没就绪就进去，昨天残留的进度会被当成"今日已完成"而直接跳打卡页。
            if (_loadFuture != null || prepareResult == null) {
              setState(() => _isPreparingStudy = true);
              await _awaitPlanReady();
              if (!mounted) return;
              setState(() => _isPreparingStudy = false);
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
                                '准备好专注背单词了吗？',
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
                  await MyDatabase.instance.usersDao.saveUser(dbUser.copyWith(todayStudyStarted: true), true);
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
          child: Padding(
            // 纵向 15：主按钮命中区高度 ≈52，误触底栏的概率更低
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
            child: _isPreparingStudy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(actionColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在准备今日计划…',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: actionColor,
                          shadows: actionShadows,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user?.todayStudyStarted == true ? '继续学习' : '开始学习',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: actionColor,
                          shadows: actionShadows,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: actionColor,
                        shadows: actionShadows,
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

  Widget renderStudySteps({
    String? currentEditingScope,
    void Function(String scope)? onTapScope,
    VoidCallback? onDone,
    VoidCallback? onMutated,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final editingScope = currentEditingScope ?? _editingTrackScope;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区域标题（每条轨道自带调整入口，这里不再放不区分轨道的汇总按钮）
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
          child: Text(
            '学习轨道',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),

        // 显示模式与编辑模式二选一：编辑态只构建被点击的那一条轨道，视线里不出现需要切换的另一个对象
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: editingScope == null
              ? _buildTrackDisplayCard(isDarkMode, onTapScope: onTapScope)
              : _buildTrackEditCard(editingScope, isDarkMode, onDone: onDone, onMutated: onMutated),
        ),
      ],
    );
  }

  /// 【显示模式】—— 一体化毛玻璃分组卡：纯排版驱动，无盒中盒、无流程导线
  Widget _buildTrackDisplayCard(bool isDarkMode, {void Function(String scope)? onTapScope}) {
    return FrostedGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Column(
        children: [
          // 新词轨道（点这一行就只调整新词轨道）
          _buildTrackDisplayRow(
            scope: 'new',
            checkStep: _newCheckStep ?? 'En2Ch',
            correctSteps: _newCorrectSteps,
            wrongSteps: _newWrongSteps,
            isDarkMode: isDarkMode,
            onTap: onTapScope != null ? () => onTapScope('new') : null,
          ),
          // 发丝分割线（极细、不抢戏）
          Container(height: 0.6, color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.055)),
          // 旧词轨道（点这一行就只调整旧词轨道）
          _buildTrackDisplayRow(
            scope: 'review',
            checkStep: _reviewCheckStep ?? 'En2Ch',
            correctSteps: _reviewCorrectSteps,
            wrongSteps: _reviewWrongSteps,
            isDarkMode: isDarkMode,
            onTap: onTapScope != null ? () => onTapScope('review') : null,
          ),
        ],
      ),
    );
  }

  /// 单个轨道的纯排版展示行：左侧裸排版「轨道名 + 测评起点」，右侧「答对/答错 → 结果流节点」；
  /// 行尾的调节图标是这条轨道自己的调整入口，点击整行即进入该轨道的编辑模式。
  Widget _buildTrackDisplayRow({
    required String scope,
    required String checkStep,
    required List<String> correctSteps,
    required List<String> wrongSteps,
    required bool isDarkMode,
    VoidCallback? onTap,
  }) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final title = scope == 'new' ? '新词' : '旧词';
    final checkDesc = StudyStepExt.fromString(checkStep).description;
    final textPrimary = themeConfig.textPrimary;
    final textMuted = themeConfig.textMuted;
    final successGreen = isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669);
    final errorCoral = isDarkMode ? const Color(0xFFF87171) : const Color(0xFFEF4444);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => setState(() => _editingTrackScope = scope),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：测评起点（微色标签 + 加粗起点名）
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title测评',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: themeConfig.primaryColor,
                      letterSpacing: 0.04,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    checkDesc,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧：分支自适应流式节点
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBranchOutcomeRow(
                    label: '答对',
                    isCorrect: true,
                    steps: correctSteps,
                    color: successGreen,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 8),
                  _buildBranchOutcomeRow(
                    label: '答错',
                    isCorrect: false,
                    steps: wrongSteps,
                    color: errorCoral,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // 这条轨道自己的调整入口：轻量调节图标只做可见线索，点击整行即生效
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: themeConfig.textSecondary.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }

  /// 单条分支结果行：精致微胶囊节点流
  Widget _buildBranchOutcomeRow({
    required String label,
    required bool isCorrect,
    required List<String> steps,
    required Color color,
    required Color textPrimary,
    required Color textMuted,
    required bool isDarkMode,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 状态判定微胶囊
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDarkMode ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isCorrect ? Icons.check_rounded : Icons.close_rounded, size: 12, color: color),
              const SizedBox(width: 2.5),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.arrow_forward_rounded, size: 10, color: textMuted.withValues(alpha: 0.4)),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: steps.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? color.withValues(alpha: isDarkMode ? 0.14 : 0.08)
                          : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.035)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '直接结束',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isCorrect ? FontWeight.w700 : FontWeight.w500,
                        color: isCorrect ? color : textMuted,
                      ),
                    ),
                  )
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (int i = 0; i < steps.length; i++) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.035),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.04),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            StudyStepExt.fromString(steps[i]).description,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                        ),
                        if (i < steps.length - 1)
                          Icon(Icons.chevron_right_rounded, size: 12, color: textMuted.withValues(alpha: 0.4)),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 【编辑模式】—— 只编辑 scope 指定的那一条轨道，顶部明示轨道名并提供「完成」收起
  Widget _buildTrackEditCard(
    String scope,
    bool isDarkMode, {
    VoidCallback? onDone,
    VoidCallback? onMutated,
  }) {
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
                      context.pageCardBg(PageVibrancy.todayPlan),
                      context.pageCardBg(PageVibrancy.todayPlan),
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
              // 正在编辑哪条轨道必须一眼可见（不再有需要来回切换的 tab）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    scope == 'new' ? '新词轨道' : '旧词轨道',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDone ?? () => setState(() => _editingTrackScope = null),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 13, color: context.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '完成',
                          style: TextStyle(
                            color: context.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildReviewStepsInfoCard(scope: scope, isDarkMode: isDarkMode, onMutated: onMutated),
            ],
          ),
        ),
      ),
    );
  }

  /// 规则编辑配置内容（测评下拉 + 答对/答错环节列表与拖拽）
  Widget _buildReviewStepsInfoCard({
    required String scope,
    required bool isDarkMode,
    VoidCallback? onMutated,
  }) {
    final textColor = isDarkMode ? Colors.white : const Color(0xFF111827);
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    const allStepNames = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'ChSentence2En'];
    String desc(String s) => StudyStepExt.fromString(s).description;
    final isNew = scope == 'new';

    String? checkStep() => isNew ? _newCheckStep : _reviewCheckStep;
    List<String> correctSteps() => isNew ? _newCorrectSteps : _reviewCorrectSteps;
    List<String> wrongSteps() => isNew ? _newWrongSteps : _reviewWrongSteps;

    void setCheck(String v) {
      setState(() {
        if (isNew) {
          _newCheckStep = v;
        } else {
          _reviewCheckStep = v;
        }
      });
      onMutated?.call();
    }

    void mutateCorrect(void Function(List<String>) fn) {
      setState(() {
        fn(isNew ? _newCorrectSteps : _reviewCorrectSteps);
      });
      onMutated?.call();
    }

    void mutateWrong(void Function(List<String>) fn) {
      setState(() {
        fn(isNew ? _newWrongSteps : _reviewWrongSteps);
      });
      onMutated?.call();
    }

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
          onAdd: () => _pickReviewStepForBranch(scope, allStepNames, isCorrect: true, onMutated: onMutated),
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
          onAdd: () => _pickReviewStepForBranch(scope, allStepNames, isCorrect: false, onMutated: onMutated),
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
                    color: isDarkMode ? Colors.white38 : const Color(0xFF475569),
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
      {required bool isCorrect, VoidCallback? onMutated}) async {
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
                                  color: isDarkMode ? Colors.white38 : const Color(0xFF475569),
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
      onMutated?.call();
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

  /// 弹出"高级设置"对话框，可配置今日最少新词数量与每组单词数
  void _showAdvancedSettingsDialog() async {
    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;
    final isStarted = user?.todayStudyStarted == true;
    final config = StudyConfig.fromCurrentUser();
    final initialWordsPerDay = user?.effectiveWordsPerDay ?? 20;
    int selectedWordsPerDay = initialWordsPerDay;
    double wordsPerDayDragAccumulator = 0;
    final initialMinNewWords = config.minNewWordsPerDay;
    int selected = initialMinNewWords.clamp(0, selectedWordsPerDay);
    // 每组单词数独立于每日计划词数，上限统一对齐为 500
    const batchSizeLimit = StudyConfig.maxBatchSize;
    final initialBatchSize = config.batchSize;
    int selectedBatchSize =
        initialBatchSize.clamp(1, batchSizeLimit);
    // 常用经典科学心流梯度（5档），整齐对称且自适应
    const batchSizeChips = [5, 10, 20, 30, 50];
    double dragAccumulator = 0;
    double minNewWordsDragAccumulator = 0;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '高级学习设置',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
          void handleSelectWordsPerDay(int v) {
            if (!UserPrivilegeManager.isDailyWordsAllowed(v)) {
              ToastUtil.info('开通会员可选择更多单词数量');
              return;
            }
            setDialogState(() {
              selectedWordsPerDay = v;
              if (selected > selectedWordsPerDay) {
                selected = selectedWordsPerDay;
              }
            });
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
                                const Color(0xB8161B26),
                                const Color(0x9E10141D),
                              ]
                            : [
                                const Color(0xB8FFFFFF),
                                const Color(0x9EFFFFFF),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDarkMode
                            ? const Color(0x33FFFFFF)
                            : const Color(0x80FFFFFF),
                        width: 1.2,
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
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

                      // 1. 今日单词数（第一项配置）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '今日单词数',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          if (isStarted)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ToastUtil.info('今日学习已开始，设置暂时锁定'),
                              child: Container(
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
                                      '$selectedWordsPerDay 词',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDarkMode ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
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
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.65),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildAdvancedStepBtn(
                                icon: Icons.remove_rounded,
                                enabled: selectedWordsPerDay > 2,
                                onTap: () => setDialogState(() {
                                  selectedWordsPerDay = (selectedWordsPerDay - 1).clamp(2, 500);
                                  if (selected > selectedWordsPerDay) {
                                    selected = selectedWordsPerDay;
                                  }
                                }),
                                isDarkMode: isDarkMode,
                                isLargeRange: true,
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    final inputVal = await _showCustomNumberInputDialog(
                                      parentContext: ctx,
                                      title: '自定义今日单词数',
                                      unit: '词',
                                      min: 2,
                                      max: 500,
                                      subtitle: '范围 2 ~ 500 词',
                                      currentValue: selectedWordsPerDay,
                                      primaryColor: primaryColor,
                                      isDarkMode: isDarkMode,
                                    );
                                    if (inputVal != null) {
                                      if (!UserPrivilegeManager.isDailyWordsAllowed(inputVal)) {
                                        ToastUtil.info('开通会员可选择更多单词数量');
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedWordsPerDay = inputVal;
                                        if (selected > selectedWordsPerDay) {
                                          selected = selectedWordsPerDay;
                                        }
                                      });
                                    }
                                  },
                                  onHorizontalDragStart: (_) {
                                    wordsPerDayDragAccumulator = 0;
                                  },
                                  onHorizontalDragUpdate: (details) {
                                    wordsPerDayDragAccumulator += details.primaryDelta ?? 0;
                                    if (wordsPerDayDragAccumulator.abs() >= 8.0) {
                                      final dir = wordsPerDayDragAccumulator > 0 ? 1 : -1;
                                      wordsPerDayDragAccumulator = 0;
                                      final next = (selectedWordsPerDay + dir).clamp(2, 500);
                                      if (next != selectedWordsPerDay) {
                                        if (next > selectedWordsPerDay && !UserPrivilegeManager.isDailyWordsAllowed(next)) {
                                          return;
                                        }
                                        HapticFeedback.selectionClick();
                                        setDialogState(() {
                                          selectedWordsPerDay = next;
                                          if (selected > selectedWordsPerDay) {
                                            selected = selectedWordsPerDay;
                                          }
                                        });
                                      }
                                    }
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '$selectedWordsPerDay',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'Roboto',
                                                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                                ),
                                              ),
                                              TextSpan(
                                                text: ' 词',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _buildAdvancedStepBtn(
                                icon: Icons.add_rounded,
                                enabled: selectedWordsPerDay < 500,
                                onTap: () {
                                  final next = (selectedWordsPerDay + 1).clamp(2, 500);
                                  if (!UserPrivilegeManager.isDailyWordsAllowed(next)) {
                                    ToastUtil.info('开通会员可选择更多单词数量');
                                    return;
                                  }
                                  setDialogState(() {
                                    selectedWordsPerDay = next;
                                  });
                                },
                                isDarkMode: isDarkMode,
                                isLargeRange: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2 行 × 3 列 规整快捷药丸标签（5, 10, 20, 30, 50, 100）
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildAdvancedQuickChip('5词', 5, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('10词', 10, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('20词', 20, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildAdvancedQuickChip('30词', 30, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('50词', 50, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('100词', 100, selectedWordsPerDay, handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              ],
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),

                      // 2. 今日最少新词
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
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
                          ),
                          if (isStarted)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ToastUtil.info('今日学习已开始，设置暂时锁定'),
                              child: Container(
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
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.65),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildAdvancedStepBtn(
                                icon: Icons.remove_rounded,
                                enabled: selected > 0,
                                onTap: () => setDialogState(() => selected = (selected - 1).clamp(0, selectedWordsPerDay)),
                                isDarkMode: isDarkMode,
                                isLargeRange: selectedWordsPerDay > 30,
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    final inputVal = await _showMinNewWordsInputDialog(
                                      ctx,
                                      selected,
                                      selectedWordsPerDay,
                                      primaryColor,
                                      isDarkMode,
                                    );
                                    if (inputVal != null) {
                                      setDialogState(() => selected = inputVal.clamp(0, selectedWordsPerDay));
                                    }
                                  },
                                  onHorizontalDragStart: (_) {
                                    minNewWordsDragAccumulator = 0;
                                  },
                                  onHorizontalDragUpdate: (details) {
                                    minNewWordsDragAccumulator += details.primaryDelta ?? 0;
                                    if (minNewWordsDragAccumulator.abs() >= 8.0) {
                                      final dir = minNewWordsDragAccumulator > 0 ? 1 : -1;
                                      minNewWordsDragAccumulator = 0;
                                      final next = (selected + dir).clamp(0, selectedWordsPerDay);
                                      if (next != selected) {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() => selected = next);
                                      }
                                    }
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: selected == 0 ? '不限制' : '$selected',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: selected == 0 ? null : 'Roboto',
                                                  color: selected == 0
                                                      ? (isDarkMode ? Colors.white70 : const Color(0xFF334155))
                                                      : (isDarkMode ? Colors.white : const Color(0xFF0F172A)),
                                                ),
                                              ),
                                              if (selected > 0)
                                                TextSpan(
                                                  text: ' 词',
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _buildAdvancedStepBtn(
                                icon: Icons.add_rounded,
                                enabled: selected < selectedWordsPerDay,
                                onTap: () => setDialogState(() => selected = (selected + 1).clamp(0, selectedWordsPerDay)),
                                isDarkMode: isDarkMode,
                                isLargeRange: selectedWordsPerDay > 30,
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
                                Expanded(child: _buildAdvancedQuickChip('5词', 5, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: selectedWordsPerDay >= 5)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('10词', 10, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: selectedWordsPerDay >= 10)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildAdvancedQuickChip('20词', 20, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: selectedWordsPerDay >= 20)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('30词', 30, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: selectedWordsPerDay >= 30)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdvancedQuickChip('全学新词', selectedWordsPerDay, selected, (v) => setDialogState(() => selected = v), primaryColor, isDarkMode, enabled: selectedWordsPerDay > 0)),
                              ],
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),

                      // 每组单词数：整组横向推进时一组容纳多少词
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: isStarted ? () => ToastUtil.info('今日学习已开始，设置暂时锁定') : null,
                              child: Text(
                                '每组单词数',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ),
                          if (isStarted)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ToastUtil.info('今日学习已开始，设置暂时锁定'),
                              child: Container(
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
                                      '$selectedBatchSize 词',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDarkMode ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),

                      if (!isStarted) ...[
                        const SizedBox(height: 14),

                        // 步进调节条（支持长按加速、横向滑动与点击精确输入）
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.65),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildAdvancedStepBtn(
                                icon: Icons.remove_rounded,
                                enabled: selectedBatchSize > 1,
                                onTap: () => setDialogState(() => selectedBatchSize = (selectedBatchSize - 1).clamp(1, batchSizeLimit)),
                                isDarkMode: isDarkMode,
                                isLargeRange: true,
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    final inputVal = await _showBatchSizeInputDialog(
                                      ctx,
                                      selectedBatchSize,
                                      primaryColor,
                                      isDarkMode,
                                    );
                                    if (inputVal != null) {
                                      setDialogState(() => selectedBatchSize = inputVal.clamp(1, batchSizeLimit));
                                    }
                                  },
                                  onHorizontalDragStart: (_) {
                                    dragAccumulator = 0;
                                  },
                                  onHorizontalDragUpdate: (details) {
                                    dragAccumulator += details.primaryDelta ?? 0;
                                    final threshold = selectedBatchSize > 50 ? 6.0 : 8.0;
                                    if (dragAccumulator.abs() >= threshold) {
                                      final dir = dragAccumulator > 0 ? 1 : -1;
                                      final step = selectedBatchSize > 100
                                          ? dir * 5
                                          : (selectedBatchSize > 30 ? dir * 2 : dir);
                                      dragAccumulator = 0;
                                      final next = (selectedBatchSize + step).clamp(1, batchSizeLimit);
                                      if (next != selectedBatchSize) {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() => selectedBatchSize = next);
                                      }
                                    }
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '$selectedBatchSize',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'Roboto',
                                                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                                ),
                                              ),
                                              TextSpan(
                                                text: ' 词/组',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _buildAdvancedStepBtn(
                                icon: Icons.add_rounded,
                                enabled: selectedBatchSize < batchSizeLimit,
                                onTap: () => setDialogState(() => selectedBatchSize = (selectedBatchSize + 1).clamp(1, batchSizeLimit)),
                                isDarkMode: isDarkMode,
                                isLargeRange: true,
                              ),
                            ],
                          ),
                        ),

                        // 快捷药丸标签（不超过当日计划词数的档位）
                        if (batchSizeChips.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (int i = 0; i < batchSizeChips.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: _buildAdvancedQuickChip(
                                    '${batchSizeChips[i]}词',
                                    batchSizeChips[i],
                                    selectedBatchSize,
                                    (v) => setDialogState(() => selectedBatchSize = v),
                                    primaryColor,
                                    isDarkMode,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 18),

                      // 3. 学习轨道与规则说明入口
                      _buildAdvancedMenuNavigationItem(
                        title: '学习轨道设置',
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/study_track_settings').then((_) {
                            if (mounted) loadData();
                          });
                        },
                        isDarkMode: isDarkMode,
                      ),
                      const SizedBox(height: 2),
                      _buildAdvancedMenuNavigationItem(
                        title: '学习日期说明',
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/study_date_rules');
                        },
                        isDarkMode: isDarkMode,
                      ),
                      const SizedBox(height: 18),

                      // 4. 本页背景配置
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '本页背景',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 本页背景快速切换药丸标签（两行三列，对称极简）
                      Builder(
                        builder: (ctx) {
                          // 选项与明暗档同源：planWallpapers 是壁纸的唯一登记处
                          const options = planWallpapers;

                          Widget buildPill(PlanWallpaper item) {
                            final isSelected = _wallpaperPath == item.path;
                            return Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () async {
                                  final selectedPath = item.path;
                                  await Prefs.write('today_plan_wallpaper', selectedPath);
                                  setDialogState(() {
                                    _wallpaperPath = selectedPath;
                                  });
                                  if (mounted) {
                                    setState(() {
                                      _wallpaperPath = selectedPath;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? primaryColor
                                        : (isDarkMode
                                            ? Colors.white.withValues(alpha: 0.06)
                                            : Colors.black.withValues(alpha: 0.04)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                        ? primaryColor
                                        : (isDarkMode
                                            ? Colors.white.withValues(alpha: 0.08)
                                            : Colors.black.withValues(alpha: 0.06)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : (isDarkMode ? Colors.white70 : const Color(0xFF334155)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  buildPill(options[0]),
                                  const SizedBox(width: 8),
                                  buildPill(options[1]),
                                  const SizedBox(width: 8),
                                  buildPill(options[2]),
                                  const SizedBox(width: 8),
                                  buildPill(options[3]),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  buildPill(options[4]),
                                  const SizedBox(width: 8),
                                  buildPill(options[5]),
                                  const SizedBox(width: 8),
                                  buildPill(options[6]),
                                  const SizedBox(width: 8),
                                  buildPill(options[7]),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
          );
        },
      );
    },
  );

  // 弹窗关闭后自动保存（Auto-Save：即改即生效）
  if (!isStarted) {
    final hasWordsChanged = selectedWordsPerDay != initialWordsPerDay;
    final hasConfigChanged = selected != initialMinNewWords || selectedBatchSize != initialBatchSize;
    if (hasWordsChanged || hasConfigChanged) {
      if (hasWordsChanged) {
        user!.wordsPerDay = selectedWordsPerDay;
        await MyDatabase.instance.usersDao.updateWordsPerDay(user!.id!, selectedWordsPerDay);
        await Global.loadUserFromDb();
        ThrottledDbSyncService().requestSync();
      }
      if (hasConfigChanged) {
        config.minNewWordsPerDay = selected;
        config.batchSize = selectedBatchSize;
        await config.saveToCurrentUser();
      }
      if (mounted) {
        loadData(forceSupplement: true);
      }
    }
  }
}

  /// 弹出精确定制数字输入框（支持自定义标题、范围与单位）
  Future<int?> _showCustomNumberInputDialog({
    required BuildContext parentContext,
    required String title,
    required String unit,
    required int min,
    required int max,
    required String subtitle,
    required int currentValue,
    required Color primaryColor,
    required bool isDarkMode,
  }) {
    final textController = TextEditingController(text: '$currentValue');
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );
    String? errorText;

    return showGeneralDialog<int>(
      context: parentContext,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setInputState) {
          void submit() {
            final text = textController.text.trim();
            final val = int.tryParse(text);
            if (val == null || val < min || val > max) {
              setInputState(() {
                errorText = '请输入 $min ~ $max 之间的整数';
              });
              return;
            }
            Navigator.of(ctx).pop(val);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDarkMode
                            ? [
                                const Color(0xB8161B26),
                                const Color(0x9E10141D),
                              ]
                            : [
                                const Color(0xB8FFFFFF),
                                const Color(0x9EFFFFFF),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDarkMode
                            ? const Color(0x33FFFFFF)
                            : const Color(0x80FFFFFF),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.white38 : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: textController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Roboto',
                            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: '输入数量',
                            suffixText: unit,
                            suffixStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                            ),
                            errorText: errorText,
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.40),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: primaryColor, width: 1.5),
                            ),
                          ),
                          onSubmitted: (_) => submit(),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDarkMode
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.40),
                                    foregroundColor: isDarkMode ? Colors.white70 : const Color(0xFF475569),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w700)),
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
            ),
          );
        },
      ),
    );
  }

  /// 弹出每组单词数精确定制输入框（支持 1 ~ 500）
  Future<int?> _showBatchSizeInputDialog(
    BuildContext parentContext,
    int currentValue,
    Color primaryColor,
    bool isDarkMode,
  ) {
    return _showCustomNumberInputDialog(
      parentContext: parentContext,
      title: '自定义每组单词数',
      unit: '词/组',
      min: 1,
      max: StudyConfig.maxBatchSize,
      subtitle: '范围 1 ~ ${StudyConfig.maxBatchSize} 词/组',
      currentValue: currentValue,
      primaryColor: primaryColor,
      isDarkMode: isDarkMode,
    );
  }

  /// 弹出今日最少新词精确定制输入框（支持 0 ~ wordsPerDay）
  Future<int?> _showMinNewWordsInputDialog(
    BuildContext parentContext,
    int currentValue,
    int wordsPerDay,
    Color primaryColor,
    bool isDarkMode,
  ) {
    return _showCustomNumberInputDialog(
      parentContext: parentContext,
      title: '自定义今日最少新词',
      unit: '词',
      min: 0,
      max: wordsPerDay,
      subtitle: '范围 0 ~ $wordsPerDay 词 (0 为不限制)',
      currentValue: currentValue,
      primaryColor: primaryColor,
      isDarkMode: isDarkMode,
    );
  }

  Widget _buildAdvancedMenuNavigationItem({
    required String title,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDarkMode ? Colors.white30 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedStepBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required bool isDarkMode,
    bool isLargeRange = false,
  }) {
    return _ContinuousStepButton(
      icon: icon,
      enabled: enabled,
      onStep: onTap,
      isDarkMode: isDarkMode,
      isLargeRange: isLargeRange,
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

    // 解析是否为 "数字 + 单位" 结构（如 "5词", "10词"）
    final match = RegExp(r'^(\d+)(.*)$').firstMatch(label);
    final hasNumericValue = match != null;
    final numPart = hasNumericValue ? match.group(1)! : label;
    final unitPart = hasNumericValue ? match.group(2)! : '';

    return GestureDetector(
      onTap: enabled ? () => onSelect(value) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? (isDarkMode ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.15))
              : isSelected
                  ? primaryColor
                  : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: !enabled
                ? Colors.transparent
                : isSelected
                    ? Colors.transparent
                    : (isDarkMode ? const Color(0x20FFFFFF) : const Color(0x80FFFFFF)),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.32),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: hasNumericValue
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    numPart,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                      color: !enabled
                          ? (isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1))
                          : isSelected
                              ? Colors.white
                              : (isDarkMode ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  if (unitPart.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Text(
                      unitPart,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: !enabled
                            ? (isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1))
                            : isSelected
                                ? Colors.white.withValues(alpha: 0.88)
                                : (isDarkMode ? Colors.white38 : const Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ],
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: !enabled
                      ? (isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1))
                      : isSelected
                          ? Colors.white
                          : (isDarkMode ? Colors.white70 : const Color(0xFF334155)),
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

    showGeneralDialog<void>(
      context: parentCtx,
      barrierDismissible: true,
      barrierLabel: '今日最少新词规则说明',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode
                        ? [
                            const Color(0xB8161B26),
                            const Color(0x9E10141D),
                          ]
                        : [
                            const Color(0xB8FFFFFF),
                            const Color(0x9EFFFFFF),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDarkMode
                        ? const Color(0x33FFFFFF)
                        : const Color(0x80FFFFFF),
                    width: 1.2,
                  ),
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
    ),
  );
}
}



/// 支持长按平滑加速连续步进的轻量按键
class _ContinuousStepButton extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onStep;
  final bool isDarkMode;
  final bool isLargeRange;

  const _ContinuousStepButton({
    required this.icon,
    required this.enabled,
    required this.onStep,
    required this.isDarkMode,
    this.isLargeRange = false,
  });

  @override
  State<_ContinuousStepButton> createState() => _ContinuousStepButtonState();
}

class _ContinuousStepButtonState extends State<_ContinuousStepButton> {
  Timer? _initialTimer;
  Timer? _periodicTimer;
  int _ticks = 0;

  void _startContinuousStep() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onStep();
    _stopContinuousStep();

    _initialTimer = Timer(const Duration(milliseconds: 320), () {
      _periodicTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || !widget.enabled) {
          _stopContinuousStep();
          return;
        }
        _ticks++;
        if (_ticks < 10) {
          // 初始精细微调（约 100ms 触发一次）
          if (_ticks % 2 == 0) {
            widget.onStep();
            HapticFeedback.selectionClick();
          }
        } else if (_ticks < 26) {
          // 加速阶段（约 50ms 触发一次）
          widget.onStep();
          if (_ticks % 2 == 0) HapticFeedback.selectionClick();
        } else {
          // 高速飞跃阶段
          final repeat = widget.isLargeRange ? (_ticks > 50 ? 5 : 2) : 1;
          for (int i = 0; i < repeat; i++) {
            widget.onStep();
          }
          if (_ticks % 3 == 0) HapticFeedback.selectionClick();
        }
      });
    });
  }

  void _stopContinuousStep() {
    _initialTimer?.cancel();
    _initialTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _ticks = 0;
  }

  @override
  void dispose() {
    _stopContinuousStep();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _startContinuousStep() : null,
      onTapUp: (_) => _stopContinuousStep(),
      onTapCancel: () => _stopContinuousStep(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: widget.enabled
              ? (widget.isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.70))
              : (widget.isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.20)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: widget.enabled && !widget.isDarkMode
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
          widget.icon,
          size: 20,
          color: widget.enabled
              ? (widget.isDarkMode ? Colors.white : const Color(0xFF1E293B))
              : (widget.isDarkMode ? Colors.white24 : Colors.black26),
        ),
      ),
    );
  }
}
