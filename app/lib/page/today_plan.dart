import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
import 'package:nnbdc/services/sync_progress.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/phoneme_util.dart';
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

/// 任务卡上主数字与加量徽标的基准字号（测量自然宽与真实渲染共用这一份，避免两头各写一个数）

/// 今日计划页里几个定宽/定距的常量。
///
/// 提成单一来源是因为「卡内数字要等大」这件事必须在 build 阶段**反推**出
/// 左卡一格的可用宽（去做文字测量），反推用的数字必须和真正参与布局的是同一套，
/// 否则量出来的宽和实际不符，等大就会失去意义。
const double _planPageHPadding = 20; // 页面左右内边距（SingleChildScrollView 的 padding）

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
  // 第 1 排：质感光影与水韵
  PlanWallpaper('星砂', 'assets/images/wallpaper/star_sand.jpg', isDark: true),
  PlanWallpaper('琥珀', 'assets/images/wallpaper/amber.jpg', isDark: true),
  PlanWallpaper('水趣', 'assets/images/wallpaper/kitty_blue.jpg', isDark: true),
  PlanWallpaper('粉梦', 'assets/images/wallpaper/kitty_pink.jpg', isDark: false),
  // 第 2 排：自然生机与流光
  PlanWallpaper('绿荫', 'assets/images/wallpaper/tree_green.jpg', isDark: false),
  PlanWallpaper('流光', 'assets/images/wallpaper/halo.jpg', isDark: true),
  PlanWallpaper('竹韵', 'assets/images/wallpaper/bamboo.jpg', isDark: false),
  PlanWallpaper('绚光', 'assets/images/wallpaper/aurora.jpg', isDark: true),
  // 第 3 排：晨昏静谧场景
  PlanWallpaper('清雅', 'assets/images/wallpaper/vase.jpg', isDark: false),
  PlanWallpaper('熊趣', 'assets/images/wallpaper/bears.jpg', isDark: false),
  PlanWallpaper('粉滩', 'assets/images/wallpaper/beach.jpg', isDark: false),
  PlanWallpaper('孤帆', 'assets/images/wallpaper/sailboat.jpg', isDark: false),
  // 第 4 排：山原温润色调
  PlanWallpaper('琉璃', 'assets/images/wallpaper/glaze.jpg', isDark: true),
  PlanWallpaper('秋林', 'assets/images/wallpaper/autumn.jpg', isDark: false),
  PlanWallpaper('碧屿', 'assets/images/wallpaper/island.jpg', isDark: false),
  PlanWallpaper('雄关', 'assets/images/wallpaper/great_wall.jpg', isDark: true),
  // 第 5 排：原野、素简、经典与随机（最后一个固定为随机）
  PlanWallpaper('青峦', 'assets/images/wallpaper/azure_peak.jpg', isDark: false),
  PlanWallpaper('微光', 'assets/images/wallpaper/glimmer.jpg', isDark: true),
  PlanWallpaper('经典', 'none', isDark: false),
  PlanWallpaper('随机', 'random', isDark: true),
];

/// 中心岛上那行日期：**只显示「月/日 + 周几」，不显示年份**。
///
/// 年份对"今天"这类信息没有增量（页面本来就只讲今天），去掉后字符串更短、视线更聚焦；
/// 补上周几是因为"今天周几"直接影响学习安排，这也是对标不背单词首页的做法。
/// 周几用**英文缩写**（形如 `10/14 Wed.`）：整串都是 Latin，能统一由 Roboto 渲染，
/// 不会出现"数字走 Roboto、周几掉回系统中文字体"的字体混排。
///
/// 这里是这个日期串的**单一来源**：页面与测试都从这里取，避免各写一份拼接。
String planIslandDateLabel(DateTime day) {
  const weekNames = ['Sun.', 'Mon.', 'Tue.', 'Wed.', 'Thu.', 'Fri.', 'Sat.'];
  return '${day.month}/${day.day} ${weekNames[day.weekday % 7]}';
}

/// 今日计划页此刻真正压在身下的那张壁纸的明暗档；null 表示「经典」（无壁纸），
/// 此时整套配色跟 App 主题走。
///
/// 外壳底栏在今日计划页是整条透明的，图标直接压在照片上，所以它必须跟这张照片
/// 同明暗。底栏自己拿不到照片，只能由持有照片的本页单向发布、由底栏订阅消费。
final ValueNotifier<bool?> planWallpaperIsDark = ValueNotifier<bool?>(null);

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

  /// 首屏等待端云同步的上限：超过就先用本地数据展示。
  ///
  /// 首屏不能被一次同步无限期占住；同步本身仍会在后台继续，进度由 [syncProgress] 展示。
  static const Duration _cloudSyncWaitTimeout = Duration(seconds: 60);

  /// 新用户（本地从未选过壁纸）的默认壁纸：琥珀（暗底照片，底栏会自动改配白图标）。
  static const String _defaultWallpaperPath = 'assets/images/wallpaper/amber.jpg';

  /// 背景壁纸（支持 'random' 与 'none' 及具体图片路径）
  String _wallpaperPath = _defaultWallpaperPath;

  /// 当壁纸设置为 'random' 时用于实际渲染的具体壁纸路径
  String? _randomResolvedPath;

  /// 获取并确定今日的随机壁纸路径（按业务天固定，跨天自动轮换）
  String _resolveDailyRandomWallpaper({bool forceNew = false}) {
    final concreteWallpapers = planWallpapers
        .where((w) => w.path != 'random' && w.path != 'none')
        .map((w) => w.path)
        .toList();
    if (concreteWallpapers.isEmpty) return 'assets/images/wallpaper/star_sand.jpg';

    final today = app_date.DateUtils.businessDate(AppClock.now());
    final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final cachedDate = Prefs.read<String>('today_plan_daily_random_wallpaper_date');
    final cachedPath = Prefs.read<String>('today_plan_daily_random_wallpaper_path');

    if (!forceNew && cachedDate == todayKey && cachedPath != null && concreteWallpapers.contains(cachedPath)) {
      return cachedPath;
    }

    // 随机抽取一张（如果有多张可选，优先避开上一张）
    final pool = (concreteWallpapers.length > 1 && cachedPath != null)
        ? concreteWallpapers.where((p) => p != cachedPath).toList()
        : concreteWallpapers;
    final chosen = pool[math.Random().nextInt(pool.length)];

    Prefs.write('today_plan_daily_random_wallpaper_date', todayKey);
    Prefs.write('today_plan_daily_random_wallpaper_path', chosen);
    return chosen;
  }

  /// 检查并按需更新跨天的每日随机壁纸
  void _checkAndUpdateDailyWallpaper() {
    if (_wallpaperPath == 'random') {
      final current = _resolveDailyRandomWallpaper();
      if (_randomResolvedPath != current) {
        setState(() {
          _randomResolvedPath = current;
        });
      }
    }
  }

  /// 当前是否为宽屏形态（iPad/平板/桌面/横屏等，宽高比 >= 0.62 或宽度 >= 600）。
  /// 手机壁纸资源在宽屏下会被拉伸变形，因此宽屏下强制仅生效经典（无壁纸）背景。
  bool get _isWideScreen {
    final size = MediaQuery.sizeOf(context);
    return size.width / size.height >= 0.62 || size.width >= 600;
  }

  /// 实际参与渲染与明暗判定的有效壁纸路径。
  /// 宽屏形态下壁纸资源未适配，强制仅生效经典（无壁纸）。
  String get _effectiveWallpaperPath {
    if (_isWideScreen) {
      return 'none';
    }
    if (_wallpaperPath == 'random') {
      return _randomResolvedPath ??= _resolveDailyRandomWallpaper();
    }
    return _wallpaperPath;
  }

  /// 当前是否有有效壁纸（非经典且非空）
  bool get _hasEffectiveWallpaper {
    final path = _effectiveWallpaperPath;
    return path.isNotEmpty && path != 'none';
  }

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

  /// 现有轨道里本版本不认识的环节（更高版本的 App 新增的题型）。
  /// 非空时轨道不能在本页编辑：本版本没有这些环节的选项，一保存就会把它们从配置里删掉。
  List<String> _unsupportedSteps = const [];

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
    final savedWallpaper = Prefs.read<String>('today_plan_wallpaper');
    final validPaths = planWallpapers.map((w) => w.path).toSet();
    _wallpaperPath = (savedWallpaper != null && validPaths.contains(savedWallpaper))
        ? savedWallpaper
        : _defaultWallpaperPath;
    if (_wallpaperPath == 'random') {
      _randomResolvedPath = _resolveDailyRandomWallpaper();
    }
    // 首页初始化时强制关停 ASR，同时在后台静默预加载语音识别模型，避免点击“开始学习”进入单词页面时因加载模型而产生阻塞卡顿
    Asr().stopMicrophone();
    // 串行预热：先语音识别模型，再音素词典（发音相似度比对用）。两者峰值内存都不小，
    // 串起来避免叠加成内存尖峰；提前到首页完成，用户进单词页开口时就已经就绪。
    unawaited(Asr().preloadModels().then((_) => PhonemeUtil.load()));
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
      _checkAndUpdateDailyWallpaper();
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
    _checkAndUpdateDailyWallpaper();
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
            await ThrottledDbSyncService()
                .requestSyncAndWait(immediate: true)
                .timeout(_cloudSyncWaitTimeout);
          } else {
            ThrottledDbSyncService().requestSync();
          }
        } on TimeoutException {
          Global.logger.e('等待端云同步超过 ${_cloudSyncWaitTimeout.inSeconds} 秒仍未结束，'
              '先用本地数据展示；同步仍在后台继续（进度见首屏加载态）');
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

    _unsupportedSteps = <String>{
      ...newCfg.unsupported,
      ...reviewCfg.unsupported,
    }.toList()
      ..sort();

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
    if (!_hasEffectiveWallpaper) {
      return AppThemeBackground(
        isDarkMode: isDarkMode,
        themeStyle: themeStyle,
        config: PageVibrancy.todayPlan,
      );
    }

    return Image.asset(
      _effectiveWallpaperPath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return AppThemeBackground(
          isDarkMode: isDarkMode,
          themeStyle: themeStyle,
          config: PageVibrancy.todayPlan,
        );
      },
    );
  }

  Widget _buildTopFloatingHeader(AppThemeConfig themeConfig, bool hasWallpaper, bool onDark) {
    final iconColor = hasWallpaper
        ? (onDark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF0F172A))
        : themeConfig.textSecondary;
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
        // 右侧高级设置按钮（遵循极简规范：零多余容器，纯矢量图标悬浮呈现；壁纸底附带局部微磨砂托底，几何盒模型严格 38x38 对齐）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showAdvancedSettingsDialog,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: hasWallpaper
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: onDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.50),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: onDark
                                  ? Colors.white.withValues(alpha: 0.20)
                                  : Colors.white.withValues(alpha: 0.70),
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: iconColor,
                          ),
                        ),
                      ),
                    )
                  : Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: iconColor,
                    ),
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

    _publishWallpaperIsDark();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildBackground(isDarkMode, themeStyle),
          ),
          (!dataLoaded)
              ? Center(
                  child: ValueListenableBuilder<SyncProgress>(
                    valueListenable: syncProgress,
                    builder: (context, progress, _) {
                      return Column(
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
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.0,
                            ),
                          ),
                          // 同步进度：数字在跳说明同步还在推进，长时间不动就是真的卡住了
                          if (_isSyncingFromCloud && !progress.isIdle) ...[
                            const SizedBox(height: 10),
                            Text(
                              progress.hasTotal
                                  ? '${progress.phase} ${progress.done} / ${progress.total}'
                                  : progress.phase,
                              style: TextStyle(
                                color: isDarkMode ? Colors.white30 : const Color(0xFF94A3B8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1.2,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                )
              : SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hasWallpaper = _hasEffectiveWallpaper;

                      // 壁纸底与主题底共用这一套布局：顶部悬浮设置 / 中心目标岛 / 底部双任务岛 + 主按钮，
                      // 两种背景只差卡片那一层皮肤（见 _cardSkin），结构与间距完全一致。
                      //
                      // 底部必须给悬浮底栏让位：底栏（透明也一样）占着屏幕最底部且吞掉那一整块点击，
                      // 内容不让开，"开始学习/继续学习"就会被压在底栏下面点不到。
                      // 多让 16：主按钮下沿与底栏命中区之间留一点安全距离，按钮整体压得更低、离底栏更近。
                      // 卡底离屏幕底的距离按「不背单词」首页实测摆：它的任务卡下沿落在 0.863H
                      //（实测 y=1968/2280），我们原来贴到 0.913H，卡片整体偏低 38dp，
                      // 中间那条「岛上沿→卡上沿」的空隙就比它宽出 76dp、显得空旷。
                      final double bottomInset =
                          widget.bottomNavReserve + constraints.maxHeight * 0.07;
                      // 字色档：跟壁纸照片的明暗走（无壁纸时等于 App 主题），不与玻璃底色脱钩
                      final bool onDark = _wallpaperIsDark ?? isDarkMode;
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(_planPageHPadding, 8, _planPageHPadding, bottomInset),
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
                                  // 中心岛同步下移：让「岛下沿 → 卡上沿」的空隙与它一致（实测 0.372H = 282dp）
                                  SizedBox(height: (constraints.maxHeight * 0.168).clamp(60.0, 150.0)),
                                  _buildTrackFlow(
                                    hasWallpaper: hasWallpaper,
                                    isDarkMode: isDarkMode,
                                    onDark: onDark,
                                    pageWidth: constraints.maxWidth,
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
                                pageWidth: constraints.maxWidth,
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

  /// 把当前壁纸的明暗档交给外壳底栏（见 [planWallpaperIsDark]）。
  ///
  /// 只能在当前帧画完之后发布：本页 build 期间直接改这个值，会同步通知到作为
  /// 祖先的底栏并让它 markNeedsBuild，Flutter 会当场报
  /// 「setState() or markNeedsBuild() called during build」。
  void _publishWallpaperIsDark() {
    final isDark = _wallpaperIsDark;
    if (planWallpaperIsDark.value == isDark) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      planWallpaperIsDark.value = isDark;
    });
  }

  /// 当前壁纸照片的明暗档；「经典」（无壁纸）返回 null，表示卡片与字色整套跟 App 主题走。
  bool? get _wallpaperIsDark {
    final effectivePath = _effectiveWallpaperPath;
    if (effectivePath.isEmpty || effectivePath == 'none') return null;
    for (final wallpaper in planWallpapers) {
      if (wallpaper.path == effectivePath) return wallpaper.isDark;
    }
    // 未登记的陌生照片按暗底处理：深色玻璃 + 白字压在任何照片上都不会糊
    return true;
  }

  /// 卡片玻璃（保持原来的通透磨砂观感，不随照片改透明度）：
  /// 壁纸底沿用最初的透光白 22% / 深色 #6018202F，经典主题底用全站统一卡片色。
  /// 描边统一取《现代极简美学规范》给第一层毛玻璃卡的那一档（白 14%，仅一丝呼吸）：
  /// 亮底照片上卡边靠"白纱与照片的亮度差"定义，绝不打一圈看得见的高光边。
  ({Color bg, Color border, BoxShadow shadow}) _cardGlass({
    required bool hasWallpaper,
    required bool isDarkMode,
    bool onDark = true,
  }) {
    if (!hasWallpaper) {
      return (
        bg: context.pageCardBg(PageVibrancy.todayPlan),
        border: context.cardBorder,
        shadow: context.pageCardShadow(PageVibrancy.todayPlan),
      );
    }
    return (
      // 亮底白纱 32%：不背单词首页卡面实测 α≈0.25~0.34（沿边走相邻像素反解），
      // 我们原来 45% 明显更厚、照片透不出来，这里对齐到它的量级。
      bg: onDark
          ? (isDarkMode ? const Color(0x6018202F) : Colors.black.withValues(alpha: 0.28))
          : Colors.white.withValues(alpha: 0.32),
      border: const Color(0x24FFFFFF),
      shadow: BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    );
  }

  /// 卡片文字三档（主/次/弱）：
  /// 可读性由「壁纸明暗档挑字色 + 局部磨砂底托」保障，彻底去除对全屏暗幕的依赖。
  ({Color primary, Color muted, Color faint}) _cardInk({
    required bool hasWallpaper,
    required bool onDark,
  }) {
    if (!hasWallpaper) {
      return (
        primary: onDark ? Colors.white : const Color(0xFF0F172A),
        muted: onDark ? Colors.white70 : const Color(0xFF475569),
        faint: onDark ? Colors.white60 : const Color(0xFF64748B),
      );
    }
    return onDark
        ? (
            primary: Colors.white,
            muted: Colors.white.withValues(alpha: 0.85),
            faint: Colors.white.withValues(alpha: 0.72),
          )
        : (
            primary: const Color(0xFF0F172A),
            muted: const Color(0xFF334155),
            faint: const Color(0xFF475569),
          );
  }

  // ==================== 今日轨道图 ====================
  //
  // 把「新词数 / 旧词数」当成两条学习轨道的起点，自上而下画到「单词列表」：
  // 数字 → 测评 → 答对 / 答错分叉 → 各自后续环节 → 汇合到单词列表。
  // 与 design/ui/today_plan_track_flow_preview.html 同构。
  //
  // 分叉与汇合用「只带两条边框 + 一个圆角」的方块拼出来（Border + BorderRadius.only），
  // 而不是自定义绘制：这样它天然跟着主题色，也没有绘制坐标算错的风险。

  /// 两条轨道的数字行共用一个缩放比：要缩就一起缩，不会一个新词 30sp、一个旧词 22sp。
  ///
  /// 必须把系统字号缩放（textScaler）算进来，否则「字号 2.0x」时测出来的宽度只有实际的一半，
  /// 缩了等于没缩、照样溢出。
  double _sharedTrackCountScale({
    required BuildContext context,
    required double maxWidth,
    required List<({int count, int extra})> rows,
    double baseFontSize = 32,
    double extraFontSize = 11,
  }) {
    if (maxWidth <= 0 || rows.isEmpty) return 1;
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1, textScaler: scaler);
    double widest = 0;
    for (final row in rows) {
      painter.text = TextSpan(
        children: [
          TextSpan(
            text: '${row.count}',
            style: TextStyle(
              fontSize: baseFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.1,
              fontFamily: 'Roboto',
            ),
          ),
          if (row.extra > 0)
            TextSpan(
              text: ' + ${row.extra}',
              style: TextStyle(fontSize: extraFontSize, fontWeight: FontWeight.w600, fontFamily: 'Roboto'),
            ),
        ],
      );
      painter.layout();
      if (painter.width > widest) widest = painter.width;
    }
    // 实测在「刚好等于可用宽」时仍会溢出 1~3px：TextPainter 量的是文字本身，
    // 不含 Row 里基线与加量小字之间的对齐余量。留 4% 安全余量。
    const double safety = 0.96;
    if (widest <= maxWidth * safety) return 1;
    return (maxWidth * safety / widest).clamp(0.35, 1.0);
  }

  /// 连线颜色。
  ///
  /// 壁纸模式下必须比主题模式明显更亮/更实：照片底纹一直在变，
  /// 22% 透明度的 1px 细线压在上面基本等于隐形（实装第一版就是这样，用户完全看不到连线）。
  Color _trackLineColor({required bool hasWallpaper, required bool onDark}) {
    if (!hasWallpaper) return const Color(0xFF241A14).withValues(alpha: 0.17);
    if (onDark) return Colors.white.withValues(alpha: 0.55);
    return const Color(0xFF241A14).withValues(alpha: 0.42);
  }

  Widget _trackVLine(double height, Color color) =>
      Container(width: 1.5, height: height, color: color);

  /// 一个轨道节点。环节用淡底，`直接结束` 用灰字表示到此为止。
  Widget _trackNode({
    required String text,
    required Color inkColor,
    Color? bg,
    Color? borderColor,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    List<Shadow>? shadows,
    Key? key,
  }) {
    return Container(
      key: key,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? Colors.transparent, width: 0.8),
      ),
      // 分支列可能只有七八十宽，「例句汉译英」「直接结束」这类文字放不下时必须等比缩，
      // 绝不能用省略号截断：截断后屏幕上会出现「直接结…」，用户根本读不出这是"直接结束"。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: inkColor,
            height: 1,
            shadows: shadows,
          ),
        ),
      ),
    );
  }

  /// 分叉：中线落下来，左右各拐一个圆角接到两条支路上。
  Widget _trackFork({required double height, required Color leftColor, required Color rightColor}) {
    Widget half(Color color, {required bool left}) {
      return Expanded(
        child: FractionallySizedBox(
          widthFactor: 0.5,
          alignment: left ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: color, width: 1.5),
                left: left ? BorderSide(color: color, width: 1.5) : BorderSide.none,
                right: left ? BorderSide.none : BorderSide(color: color, width: 1.5),
              ),
              borderRadius: left
                  ? const BorderRadius.only(topLeft: Radius.circular(9))
                  : const BorderRadius.only(topRight: Radius.circular(9)),
            ),
          ),
        ),
      );
    }

    // 这里的间隙必须与下面「两条支路」那行的 SizedBox(width: 10) 完全一致：
    // 否则分叉竖线落在 25%/75%，支路竖线落在 25%-2.5 / 75%+7.5，两者差几个像素，
    // 就是用户截图里那种「答错那根线歪到标签右边」的错位。
    return Row(
      children: [
        half(leftColor, left: true),
        const SizedBox(width: 10),
        half(rightColor, left: false),
      ],
    );
  }


  /// 一条支路：答对 / 答错标签 → 环节依次往下串（环节多就往下长）。
  Widget _trackBranch({
    required String label,
    required Color labelColor,
    required Color lineColor,
    required List<String> steps,
    required Color inkColor,
    required Color nodeBg,
    required Color nodeBorder,
    required List<Shadow>? shadows,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: labelColor, height: 1),
        ),
        const SizedBox(height: 6),
        _trackVLine(16, lineColor),
        if (steps.isEmpty)
          _trackNode(
            text: '直接结束',
            inkColor: inkColor.withValues(alpha: 0.62),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            shadows: shadows,
          )
        else
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) _trackVLine(14, lineColor),
            _trackNode(
              text: StudyStepExt.displayName(steps[i]),
              inkColor: inkColor,
              bg: nodeBg,
              borderColor: nodeBorder,
              shadows: shadows,
            ),
          ],
      ],
    );
  }

  /// 一条完整轨道（新词或旧词）。
  Widget _buildTrackColumn({
    required String title,
    required int count,
    required int extraCount,
    required Key countKey,
    required Key extraKey,
    required String checkStep,
    required List<String> correctSteps,
    required List<String> wrongSteps,
    required ({Color primary, Color muted, Color faint}) ink,
    required Color line,
    required Color ok,
    required Color no,
    required Color okLine,
    required Color noLine,
    required Color nodeBg,
    required Color nodeBorder,
    required List<Shadow>? shadows,
    required VoidCallback onTapCount,
    required double countScale,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 起点：今天要学的词数（点它进对应词表）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapCount,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 数字行按「两条轨道共用的缩放比」缩小字号（而不是各自 FittedBox），
              // 这样新词与旧词的数字渲染高度始终一致，大字号 + 四位数字时也不会溢出。
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$count',
                    key: countKey,
                    style: TextStyle(
                      fontSize: 32 * countScale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.1,
                      height: 1,
                      color: ink.primary,
                      fontFamily: 'Roboto',
                    ),
                  ),
                    if (extraCount > 0) ...[
                      const SizedBox(width: 3),
                      Text(
                        ' + $extraCount',
                        key: extraKey,
                        style: TextStyle(
                          fontSize: 11 * countScale,
                          fontWeight: FontWeight.w600,
                          color: ink.faint,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 3),
              Text(
                title,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: ink.faint, letterSpacing: 1.4),
              ),
            ],
          ),
        ),
        _trackVLine(20, line),
        Text(
          '测评',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: ink.faint, letterSpacing: 1.6),
        ),
        const SizedBox(height: 2),
        _trackNode(
          text: StudyStepExt.displayName(checkStep),
          inkColor: ok,
          bg: ok.withValues(alpha: 0.075),
          borderColor: ok.withValues(alpha: 0.24),
          fontSize: 12.5,
          shadows: shadows,
        ),
        _trackVLine(18, line),
        _trackFork(height: 26, leftColor: okLine, rightColor: noLine),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _trackBranch(
                label: '答对',
                labelColor: ok,
                lineColor: okLine,
                steps: correctSteps,
                inkColor: ink.primary,
                nodeBg: nodeBg,
                nodeBorder: nodeBorder,
                shadows: shadows,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _trackBranch(
                label: '答错',
                labelColor: no,
                lineColor: noLine,
                steps: wrongSteps,
                inkColor: ink.primary,
                nodeBg: nodeBg,
                nodeBorder: nodeBorder,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 轨道图整体：两条轨道并排，下面是打卡状态。
  Widget _buildTrackFlow({
    required bool hasWallpaper,
    required bool isDarkMode,
    required bool onDark,
    required double pageWidth,
  }) {
    final ink = _cardInk(hasWallpaper: hasWallpaper, onDark: onDark);
    final line = _trackLineColor(hasWallpaper: hasWallpaper, onDark: onDark);
    final ok = onDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final no = onDark ? const Color(0xFFF87171) : const Color(0xFFC4552F);
    final okLine = ok.withValues(alpha: hasWallpaper ? 0.8 : 0.55);
    final noLine = no.withValues(alpha: hasWallpaper ? 0.8 : 0.55);
    // 壁纸底：节点要有真的底与描边，否则节点文字直接压在照片纹理上；
    // 暗底再加一层黑色投影、亮底加白色投影，保证在明暗交界处也读得出来。
    final nodeBg = !hasWallpaper
        ? (onDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFF241A14).withValues(alpha: 0.035))
        : (onDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.62));
    final nodeBorder = !hasWallpaper
        ? (onDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF241A14).withValues(alpha: 0.055))
        : (onDark ? Colors.white.withValues(alpha: 0.26) : Colors.white.withValues(alpha: 0.9));
    final List<Shadow>? shadows = !hasWallpaper
        ? null
        : (onDark
            ? [Shadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 6)]
            : [Shadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 6)]);

    final double gap = (pageWidth * 0.075).clamp(18.0, 34.0);

    Widget track({required bool isNew, required double countScale}) {
      return _buildTrackColumn(
        title: isNew ? '新词' : '旧词',
        count: (isNew ? newWordCount : oldWordCount) ?? 0,
        extraCount: isNew ? _extraNewCount : _extraOldCount,
        countKey: Key(isNew ? 'today_plan_new_count_number' : 'today_plan_old_count_number'),
        extraKey: Key(isNew ? 'today_plan_extra_new_count' : 'today_plan_extra_old_count'),
        checkStep: (isNew ? _newCheckStep : _reviewCheckStep) ?? 'En2Ch',
        correctSteps: isNew ? _newCorrectSteps : _reviewCorrectSteps,
        wrongSteps: isNew ? _newWrongSteps : _reviewWrongSteps,
        ink: ink,
        line: line,
        ok: ok,
        no: no,
        okLine: okLine,
        noLine: noLine,
        nodeBg: nodeBg,
        nodeBorder: nodeBorder,
        shadows: shadows,
        countScale: countScale,
        onTapCount: () {
          final future = isNew ? toTodayNewWordsListPage(true) : toTodayOldWordsListPage(true);
          future?.then((_) => Future.delayed(Duration.zero, () => loadData(isReturnFromStudy: true)));
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 两条轨道共用一个数字缩放比，保证新词与旧词的数字一样大、且都不溢出。
        final double perTrack = ((constraints.maxWidth - gap) / 2).clamp(40.0, double.infinity);
        final double countScale = _sharedTrackCountScale(
          context: context,
          maxWidth: perTrack,
          rows: [
            (count: newWordCount ?? 0, extra: _extraNewCount),
            (count: oldWordCount ?? 0, extra: _extraOldCount),
          ],
        );
        // 整张轨道图包在一张毛玻璃卡里：壁纸底纹一直在变，不隔绝一层的话
        // 连线与节点文字会跟照片纹理糊在一起（实装后用户反馈"还是看不清楚"）。
        final skin = _cardGlass(hasWallpaper: hasWallpaper, isDarkMode: isDarkMode, onDark: onDark);
        return FrostedGlassCard(
          bgColor: skin.bg,
          borderColor: skin.border,
          shadow: skin.shadow,
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: track(isNew: true, countScale: countScale)),
                  SizedBox(width: gap),
                  Expanded(child: track(isNew: false, countScale: countScale)),
                ],
              ),
              const SizedBox(height: 12),
              _buildDakaStatusLine(ink: ink, onDark: onDark),
            ],
          ),
        );
      },
    );
  }

  /// 轨道图底部的打卡状态：已打卡就盖一枚「已打卡 · MM-DD」，没打卡就写今日目标。
  Widget _buildDakaStatusLine({
    required ({Color primary, Color muted, Color faint}) ink,
    required bool onDark,
  }) {
    final date = planIslandDateLabel(AppClock.today());
    final sealColor = onDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    // 大字号下「日期 + 已打卡/今日目标 + 词数」会撑破屏宽（实测 110px），
    // 整行按可用宽度等比缩，宁可小一点也不许溢出。
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDakaToday) ...[
          Icon(Icons.check_circle_outline_rounded, size: 14, color: sealColor),
          const SizedBox(width: 5),
          Text(
            '已打卡',
            key: const Key('today_plan_daka_seal_text'),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ink.muted),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          date,
          key: hasDakaToday ? const Key('today_plan_daka_seal_date') : null,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ink.faint, fontFamily: 'Roboto'),
        ),
        if (!hasDakaToday) ...[
          const SizedBox(width: 8),
          Text(
            '今日目标',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ink.faint),
          ),
          const SizedBox(width: 4),
          Text(
            '${_planWords.length} 词',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ink.faint, fontFamily: 'Roboto'),
          ),
        ],
      ],
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






  /// 底部「双任务岛与主操作」：
  /// 左卡片并排新词 / 旧词两项任务量（各自点进对应词表），右卡片装主操作按钮。
  Widget _buildBottomTaskIsland({
    required AppThemeConfig themeConfig,
    required bool hasWallpaper,
    required bool isDarkMode,
    required bool onDark,
    required double pageWidth,
  }) {
    // 词书单词量不足：主操作让位给补救操作（选择词书 / 就这样吧）
    final bool bookShortage = prepareResult?.code == "NNBDC-0012" ||
        (_hasTriedSupplement && (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 0));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 任务量未满提示条（如有）
        if (prepareResult != null &&
            prepareResult!.success &&
            (todayWordCount ?? 0) < (user?.effectiveWordsPerDay ?? 20) &&
            !_hasTriedSupplement) ...[
          _buildSupplementNoticeBar(themeConfig, hasWallpaper, onDark),
          const SizedBox(height: 8),
        ],

        // 新词 / 旧词的数量已经上移成两条轨道的起点（见 _buildTrackFlow），
        // 底部这里只留唯一的行动点：开始 / 继续 / 加量。
        if (!bookShortage) renderStartButton(),

        // 词书单词量不足：选择词书 / 就这样吧
        if (bookShortage) ...[
          const SizedBox(height: 10),
          renderErrorActions(),
        ],
      ],
    );
  }

  /// 底部任务岛里的毛玻璃卡壳：左右两张卡共用同一套玻璃与圆角，
  /// 卡壳只管玻璃与命中层，里面装什么由调用方决定。
  Widget _buildIslandCard({
    required ({Color bg, Color border, BoxShadow shadow}) skin,
    Key? key,
    VoidCallback? onTap,
    required Widget child,
  }) {
    // 圆角 12：对齐「不背单词」底部那两张卡的面板感（实测其圆角 ≈12dp，
    // 原来 18dp 在 75dp 高的卡上偏"糖果"，一张卡比参考圆一圈）
    const double radius = 12;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          decoration: BoxDecoration(
            color: skin.bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: skin.border, width: 0.5),
            boxShadow: [skin.shadow],
          ),
          child: Material(
            color: Colors.transparent,
            child: onTap == null
                ? child
                : InkWell(
                    key: key,
                    borderRadius: BorderRadius.circular(radius),
                    onTap: onTap,
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _wrapActionButton({
    Key? key,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final hasWallpaper = _hasEffectiveWallpaper;
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final onDark = _wallpaperIsDark ?? isDarkMode;
    return _buildIslandCard(
      skin: _cardGlass(hasWallpaper: hasWallpaper, isDarkMode: isDarkMode, onDark: onDark),
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
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
    final hasWallpaper = _hasEffectiveWallpaper;
    final onDark = _wallpaperIsDark ?? isDarkMode;
    final actionColor = hasWallpaper
        ? (onDark ? Colors.white : const Color(0xFF0F172A))
        : (isDarkMode ? themeConfig.primaryLightColor : themeConfig.primaryColor);
    return _wrapActionButton(
      key: key,
      onTap: onPressed,
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
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: actionColor,
          ),
        ],
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
    final hasWallpaper = _hasEffectiveWallpaper;

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

    final onDark = _wallpaperIsDark ?? isDarkMode;
    final actionColor = hasWallpaper
        ? (onDark ? Colors.white : const Color(0xFF0F172A))
        : (isDarkMode ? themeConfig.primaryLightColor : themeConfig.primaryColor);

    Future<void> onStartTap() async {
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
          }

    final buttonContent = _isPreparingStudy
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
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: actionColor,
              ),
            ],
          );

    return _wrapActionButton(
      onTap: onStartTap,
      child: buttonContent,
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

        // 轨道里有本版本不认识的环节时，说清"现在为什么不能在这里改"
        if (_unsupportedSteps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, top: 10),
            child: Text(
              '轨道里有本版本不支持的环节（${_unsupportedSteps.join('、')}），'
              '暂时不能在这里调整，请升级 App。',
              style: TextStyle(
                color: isDarkMode ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                fontSize: 12,
                height: 1.5,
              ),
            ),
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
    final checkDesc = StudyStepExt.displayName(checkStep);
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
                            StudyStepExt.displayName(steps[i]),
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
    // 可选题型清单的唯一来源在 StudyStepExt.selectableSteps，本页不再自带一份
    const allStepNames = StudyStepExt.selectableSteps;
    String desc(String s) => StudyStepExt.displayName(s);
    final isNew = scope == 'new';
    // 轨道里有本版本不认识的环节时只读：本版本没有那些环节的选项，一保存就会把它们删掉
    final readOnly = _unsupportedSteps.isNotEmpty;

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
                    // 不认识的现有环节也要在列表里出现：否则 DropdownButton 找不到当前值，
                    // 用户也看不到自己的轨道到底配了什么
                    for (final s in <String>[...allStepNames, ..._unsupportedSteps])
                      DropdownMenuItem(value: s, child: Text(desc(s))),
                  ],
                  onChanged: readOnly
                      ? null
                      : (v) {
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
          readOnly: readOnly,
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
          readOnly: readOnly,
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
    required bool readOnly,
    required bool isDarkMode,
    required VoidCallback onAdd,
    required void Function(String) onRemove,
    required void Function(int, int) onReorder,
  }) {
    final textColor = isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final subColor = isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final bool canAdd = !readOnly && allStepNames.any((s) => !steps.contains(s));

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
                      if (!readOnly)
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(Icons.drag_indicator_rounded, size: 16, color: subColor),
                          ),
                        )
                      else
                        const SizedBox(width: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          StudyStepExt.displayName(steps[i]),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (!readOnly)
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
                              StudyStepExt.displayName(available[i]),
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

  /// 弹出"高级设置"对话框
  void _showAdvancedSettingsDialog() async {
    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;
    final config = StudyConfig.fromCurrentUser();
    final wordsPerDay = user?.effectiveWordsPerDay ?? 20;
    final minNewWordsDesc = config.minNewWordsPerDay == 0 ? '不限制' : '${config.minNewWordsPerDay}词';
    final planSummary = '$wordsPerDay 词/天 · 新词$minNewWordsDesc · ${config.batchSize} 词/组';

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
                            const SizedBox(height: 16),

                            // 1. 每日计划与词量设置（二级设置入口）
                            _buildAdvancedMenuNavigationItem(
                              title: '每日计划与词量设置',
                              subtitle: planSummary,
                              onTap: () {
                                Navigator.pop(ctx);
                                context.push('/study_plan_settings').then((_) {
                                  if (mounted) loadData(forceSupplement: true);
                                });
                              },
                              isDarkMode: isDarkMode,
                            ),
                            const SizedBox(height: 2),

                            // 2. 学习轨道设置
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

                            // 3. 学习日期说明
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

                            // 本页背景快速切换药丸标签（宽屏下对用户隐藏手机壁纸，只保留经典）
                            Builder(
                              builder: (ctx) {
                                Widget buildPill(PlanWallpaper item, {bool? forceSelected, VoidCallback? customOnTap}) {
                                  final isSelected = forceSelected ?? (_wallpaperPath == item.path);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: customOnTap ?? () async {
                                      final selectedPath = item.path;
                                      if (selectedPath == 'random') {
                                        _randomResolvedPath = _resolveDailyRandomWallpaper(forceNew: true);
                                      }
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
                                      height: 35,
                                      decoration: BoxDecoration(
                                        // 奶白玉块配方：白 35% 底提亮，再压白 50% 细描边当高光；
                                        // 选中态实心主题色、去描边、加主题色外发光。
                                        color: isSelected
                                            ? primaryColor
                                            : (isDarkMode
                                                ? Colors.white.withValues(alpha: 0.05)
                                                : Colors.white.withValues(alpha: 0.35)),
                                        borderRadius: BorderRadius.circular(10),
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
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                  );
                                }

                                if (_isWideScreen) {
                                  final classicItem = planWallpapers.firstWhere(
                                    (w) => w.path == 'none',
                                    orElse: () => const PlanWallpaper('经典', 'none', isDark: false),
                                  );
                                  return Row(
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: buildPill(
                                          classicItem,
                                          forceSelected: true,
                                          customOnTap: () async {
                                            await Prefs.write('today_plan_wallpaper', 'none');
                                            setDialogState(() {
                                              _wallpaperPath = 'none';
                                            });
                                            if (mounted) {
                                              setState(() {
                                                _wallpaperPath = 'none';
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '壁纸仅适配手机竖屏，宽屏暂仅支持经典背景',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                const options = planWallpapers;
                                return Column(
                                  children: [
                                    for (int row = 0; row < 5; row++) ...[
                                      if (row > 0) const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          for (int col = 0; col < 4; col++) ...[
                                            if (col > 0) const SizedBox(width: 8),
                                            Expanded(
                                              child: buildPill(options[row * 4 + col]),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
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
  }

  Widget _buildAdvancedMenuNavigationItem({
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode ? Colors.white38 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
}


