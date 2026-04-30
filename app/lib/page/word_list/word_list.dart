import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../api/api.dart';
import '../../api/bo/word_bo.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../state.dart';
import '../../theme/app_theme.dart';
import '../../util/app_clock.dart';
import '../../util/phoneme_util.dart';
import '../../util/platform_util.dart';
import '../../util/sound.dart';
import '../../util/word_util.dart';
import '../index.dart';
import '../walkman.dart';
import '../word_detail.dart';
import 'dict_words.dart';
import 'edit_meaning_dialog.dart';
import 'import_from_book_page.dart';
import 'import_from_scan_page.dart';

const String menuWordList = '浏览词表';
const String menuWalkman = '随身听';
const String menuSpeakChinese = '说中文';
const String menuSpeakEnglish = '说英文';
const String menuWriteSpellTyping = '拼写(打字)';
const String menuWriteSpellHandwriting = '拼写(手写)';
const String menuImportFromBook = '从词书导入';
const String menuImportFromScan = '扫描导入';
const String menuAiStory = 'AI短文';
const String menuSettings = '学习设置';
const String menuLegend = '学习状态图例';
const String menuHideChinese = '隐藏中文';
const String menuHideEnglish = '隐藏英文';


mixin WordsProvider {
  Future<PagedResults<WordWrapper>> getAPageOfWords(
      int fromIndex, int pageSize);

  Future<bool> deleteWord(WordWrapper wordWrapper);

  Future<bool> masterWord(WordWrapper wordWrapper) async => false;

  /// 取消掌握单词
  Future<bool> unmasterWord(WordWrapper wordWrapper) async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return false;
    final result = await WordBo().deleteMasteredWord(userId, wordWrapper.word.id!);
    return result.success;
  }

  /// 获取指定单词在所有单词中的位置, 如果指定单词不存在，返回-1
  Future<int> getWordIndex(String spell);

  /// 获取单词的学习状态：null=未学习, true=已掌握, false=学习中
  Future<bool?> getWordLearningStatus(String wordId) async => null;

  /// 批量获取单词的学习状态
  Future<Map<String, bool?>> getWordsLearningStatus(List<String> wordIds) async {
    final Map<String, bool?> results = {};
    for (final id in wordIds) {
      results[id] = await getWordLearningStatus(id);
    }
    return results;
  }

  /// 当单词被标记为“掌握”时，是否保留在当前UI列表中（不自动移除）
  bool get keepWordsOnMaster => false;
}

abstract class WordModifier {
  Future<bool> addWord(String wordId);
  Future<bool> updateMeanings(String wordId, List<MeaningUpdateItem> meanings);
  Future<bool> deleteMeaning(String wordId);
  String? get targetDictId => null;
}

abstract class WordProgressProvider {
  double getWordProgress(dynamic wordTag);

  double getWordProgressMax(dynamic wordTag);
}

abstract class BookMarkProvider {
  Future<BookMarkVo?> getBookMark();

  Future<bool> saveBookMark(BookMarkVo bookMark);
}

abstract class WordListListener {
  void wordCountChanged(int currentCount, int totalCount);

  void onWordDeletedFromList(
      WordWrapper wordWrapper, bool alreadyDeletedOnServer);
}

class WordListPageArgs {
  bool showBackBtn;
  String appBarTitle;
  WordsProvider wordsProvider;
  bool showDelBtn;
  bool showWordProgress;
  String wordProgressLabel;
  WordProgressProvider wordProgressProvider;
  BookMarkProvider bookMarkProvider;
  Widget? injectedBtn;
  bool canAddWord = false;
  bool canEditWord = false;
  bool showAiStory;

  WordListPageArgs(
      this.appBarTitle,
      this.wordsProvider,
      this.showBackBtn,
      this.showDelBtn,
      this.showWordProgress,
      this.wordProgressLabel,
      this.wordProgressProvider,
      this.bookMarkProvider,
      this.injectedBtn,
      {this.showAiStory = false});

  @override
  String toString() {
    return 'WordListParams{appBarTitle: $appBarTitle, wordsProvider: $wordsProvider, showDelBtn: $showDelBtn, showWordProgress: $showWordProgress, wordProgressLabel: $wordProgressLabel, wordProgressProvider: $wordProgressProvider}';
  }
}

class WordListPage extends StatefulWidget {
  const WordListPage({super.key});

  @override
  WordListPageState createState() {
    return WordListPageState();
  }
}

class WordListPageState extends State<WordListPage>
    with
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin {
  static const double leftPadding = 6;
  static const double rightPadding = 8;
  static const double delBtnSize = 24;
  static const int _pageSize = 30;
  static const double bookMarkBorderWidth = 2;
  static const double _handwritingScrollAlignment = 0.3;

  /// 当列表中的单词数量小于此值时, 将触发加载数据动作。因为加载数据主要是由滚动事件触发的，
  /// 而删除动作可能会使滚动条消失，所以删除动作需要主动检测此值
  static const int minWordCount = 30;

  /// 两次查询的最小时间间隔，单位毫秒
  static const int minQueryInterval = 300;

  var studyMode = WordListStudyMode.list;
  bool _isHandwritingOverlayOpen = true;
  int? _tempHandwritingSelectedIndex;
  final GlobalKey<HandwritingBoardState> _handwritingBoardKey = GlobalKey<HandwritingBoardState>();
  int _renderWordCallCount = 0;
  final ValueNotifier<int> activeWordIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<bool> _rightZoneVisible = ValueNotifier<bool>(true);
  double _handwritingRightPadding = 60.0;
  Timer? _handwritingPaddingTimer;

  /// 语音识别通过规则：'ONE' (说出一个), 'HALF' (说出半数), 'ALL' (说出全部)
  String get asrPassRule => GetStorage().read('wordListAsrPassRule') ?? 'ONE';

   late WordListPageArgs args;
  bool dataLoaded = false;
  bool _showList = false; // 用于延迟渲染列表，提升进入动画流畅度
  bool isQuerying = false;
  int totalWordCount = -1;
  BookMarkVo? bookMark;

  /// 是否可以离开当前单词（用户回答正确的释义数量达到要求）
  bool canLeaveCurrWord = false;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  /// 单词列表界面最上方那个单词在所有单词中（包括那些在服务端，还未加载的）的序号（需要这个值是为了支持从中间某个位置加载单词列表）
  int? baseIndex;

  /// 加载到界面的单词列表（其中第一个单词在所有单词中的序号为 baseIndex)
  List<WordWrapper> words = [];


  /// 是否显示返回到顶部按钮

  DateTime? lastQueryTime;

  Offset floatBtnPosition = const Offset(20.0, 20.0);

  dynamic asrResult;

  late Asr asr;
  // 音量电平（0..1）通知器与订阅
  final ValueNotifier<double> _meterLevelNotifier = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _meterSub;
  static const int _waveCapacity = 16; // 更短窗口，提升实时感（~0.35s）
  final List<double> _waveLevels = <double>[];

  Timer? _meterTimer;
  double _lastMeterLevel = 0.0;
  DateTime? _lastMeterAt;
  bool _meterTickFlip = false;

  // ASR模型加载状态与动画控制器
  bool _isAsrModelLoading = false; // 控制UI显示（大脑动画）
  bool _isAsrProcessing = false; // 逻辑锁，防止重复启动（无论是否显示动画）
  late AnimationController _asrModelLoadingController;
  late AnimationController _glowController;
  AsrLanguage? _lastAsrLanguage;

  /// "请勿查询"标志，当此标志为true时，如果本来有查询动作（比如滚动到顶部或底部），该动作也不再执行
  bool doNotQueryPlease = false;

  /// 是否显示新手引导
  bool showGuide = false;

  /// 菜单是否打开（用于控制iPad上的弹出菜单稳定性）
  bool isMenuOpen = false;

  /// 已生成的 AI 短文缓存
  String? _aiStory;

  /// 识别出的“写错但合法”的单词，用于显示释义提示
  WordVo? _detectedSimilarWord;

  @override
  bool get wantKeepAlive => true; // 保持状态，避免页面重建

  /// 用于获取右上角菜单按钮的坐标
  final GlobalKey _menuKey = GlobalKey();
  OverlayEntry? _guideOverlay;
  Rect? _menuRect;
  final GlobalKey _overlayKey = GlobalKey();

  /// 音频播放器实例（测试环境下为 MockAudioPlayer）
  final AudioPlayer audioPlayer = AudioPlayer();

  /// AudioPlayer 是否已被释放的标志
  bool _audioPlayerDisposed = false;

  clearQueryResult() {
    //清空当前查询结果
    words.clear();
    // baseIndex = null;
    _aiStory = null; // 刷新时也清空已缓存的 AI 短文
  }

  Future<void> loadData() async {
    final swTotal = Stopwatch()..start();
    final swInit = Stopwatch()..start();
    
    // 并行获取书签和权限检查
    final results = await Future.wait([
      checkArgs(),
      args.bookMarkProvider.getBookMark(),
    ]);

    Global.logger.d('WordListPage: checkArgs and getBookMark took ${swInit.elapsedMilliseconds}ms');
    swInit.reset();

    if (!(results[0] as bool)) {
      return;
    }
    bookMark = results[1] as BookMarkVo?;

    if (isBookMarkValid(bookMark)) {
      // 有书签：加载书签所在的那一页单词
      final swIdx = Stopwatch()..start();
      var wordIndex = await args.wordsProvider.getWordIndex(bookMark!.spell);
      Global.logger.d('WordListPage: getWordIndex took ${swIdx.elapsedMilliseconds}ms');
      
      if (wordIndex != -1) {
        // 计算书签所在页的起始位置
        baseIndex = (wordIndex ~/ _pageSize) * _pageSize;
        await doQuery(true, baseIndex!, _pageSize, false);

        // 滚动到书签位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final bookMarkUiPos = getBookMarkUiPosition();
          if (bookMarkUiPos >= 0 && bookMarkUiPos < words.length) {
            itemScrollController.scrollTo(
                index: bookMarkUiPos,
                duration: const Duration(milliseconds: 300),
                alignment: _handwritingScrollAlignment); // 显示在屏幕偏上部
          }
        });
      } else {
        // 书签无效，从第一页开始
        baseIndex = 0;
        await doQuery(true, baseIndex!, _pageSize, false);
      }
    } else {
      // 没有书签：从第一页开始
      baseIndex = 0;
      await doQuery(true, baseIndex!, _pageSize, false);
      // 自动设置首位书签：如果词表不为空且当前确实没有书签
      if (words.isNotEmpty && bookMark == null) {
        bookMark = BookMarkVo(0, words[0].word.spell);
        args.bookMarkProvider.saveBookMark(bookMark!);
      }
    }

    setState(() {
      dataLoaded = true;
    });
    
    Global.logger.d('WordListPage: loadData total completed in ${swTotal.elapsedMilliseconds}ms');

    // 数据加载完成后，如果当前是语音模式，启动ASR
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _restoreAsrIfNeeded('loadData');
        }
      });
    }
    Global.logger.d('WordListPage: loadData completed in ${swTotal.elapsedMilliseconds}ms (baseIndex=$baseIndex)');
  }

  doQuery(bool clearCurrent, int fromIndex, final int pageSize,
      bool jumpToTailWhenReady) async {
    /// 如果正在查询，或者当前时间和最后一次查询时间之差小于规定毫秒数，则不查询（保护服务端和UI性能）
    fromIndex = fromIndex < 0 ? 0 : fromIndex;

    if (isQuerying ||
        doNotQueryPlease ||
        (totalWordCount >= 0 && fromIndex >= totalWordCount) ||
        (!clearCurrent &&
            totalWordCount >= 0 &&
            words.length >= totalWordCount &&
            words.isNotEmpty) ||
        fromIndex < 0 ||
        (lastQueryTime != null &&
            AppClock.now().difference(lastQueryTime!).inMilliseconds <
                minQueryInterval)) {
      return;
    }

    // 标记开始查询
    isQuerying = true;

    // 更新最后查询时间
    lastQueryTime = AppClock.now();

    //清除当前的查询结果
    if (clearCurrent) {
      clearQueryResult();
    }

    //查询
    await loadAPageOfWords(fromIndex, pageSize, jumpToTailWhenReady);

    // 标记结束查询
    isQuerying = false;
  }

  loadAPageOfWords(
      final int fromIndex, final int pageSize, bool jumpToTailWhenReady) async {
    try {
      // 获取一页单词
      final result =
          await args.wordsProvider.getAPageOfWords(fromIndex, pageSize);

      // 即使没有单词，也要更新totalWordCount
      if (result.rows.isEmpty) {
        setState(() {
          totalWordCount = result.total;
        });
        return;
      }

      // 在setState之前计算所有需要的值，减少setState中的计算工作
      int newTotalWordCount = result.total;
      List<WordWrapper> newWords = List.from(words); // 创建新列表以避免直接修改原列表
      int? newBaseIndex = baseIndex;

      if (fromIndex < baseIndex!) {
        // 向上滚动加载，从头部插入新数据
        Global.logger.d(
            '向上加载数据: fromIndex=$fromIndex, baseIndex=$baseIndex, 当前words长度=${words.length}');
        var beforeLen = newWords.length;
        var newData =
            result.rows.where((element) => !words.contains(element)).toList();
        Global.logger.d('向上加载新数据: 新数据数量=${newData.length}');
        newWords.insertAll(0, newData);
        // 更新baseIndex
        var lenDelta = newWords.length - beforeLen;
        newBaseIndex = baseIndex! - lenDelta;
        Global.logger
            .d('向上加载完成: 新baseIndex=$newBaseIndex, 新words长度=${newWords.length}');

        // 向上加载后，需要调整滚动位置，避免连续触发向上加载
        if (jumpToTailWhenReady == false) {
          // 延迟调整滚动位置，确保UI更新完成
          SchedulerBinding.instance.addPostFrameCallback((_) {
            // 滚动到新插入数据的末尾位置，保持用户当前查看的内容在相同位置
            itemScrollController.scrollTo(
                index: lenDelta,
                duration: const Duration(milliseconds: 100),
                alignment: 0.5); // 显示在屏幕中部
          });
        }
      } else {
        // 向下滚动加载，从尾部添加新数据
        newWords
            .addAll(result.rows.where((element) => !words.contains(element)));
      }

      // 更新状态
      setState(() {
        totalWordCount = newTotalWordCount;
        words = newWords;
        baseIndex = newBaseIndex;

        if (jumpToTailWhenReady) {
          SchedulerBinding.instance.addPostFrameCallback((_) =>
              itemScrollController.scrollTo(
                  index: (words.length - 1),
                  duration: const Duration(milliseconds: 300),
                  alignment: _handwritingScrollAlignment)); // 显示在屏幕偏上部
        }
      });

      // 异步加载学习状态和预取音频
      _loadLearningStatusForWords(result.rows);
      _prefetchAudioForWords(result.rows);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace,
          logPrefix: '加载单词失败', showToast: false);
    }
  }

  Future<void> _loadLearningStatusForWords(List<WordWrapper> newWords) async {
    final wordIds = newWords
        .where((w) => w.word.id != null && w.initialLearningStatus == null)
        .map((w) => w.word.id!)
        .toList();
    if (wordIds.isEmpty) return;

    final statusMap = await args.wordsProvider.getWordsLearningStatus(wordIds);
    if (statusMap.isEmpty) return;

    bool hasUpdates = false;
    for (var wordWrapper in newWords) {
      final wordId = wordWrapper.word.id;
      if (wordId != null && statusMap.containsKey(wordId)) {
        final status = statusMap[wordId];
        if (status != null) {
          wordWrapper.initialLearningStatus = status;
          wordWrapper.currentLearningStatus = status;
          hasUpdates = true;
        }
      }
    }

    if (mounted && hasUpdates) {
      setState(() {});
    }
  }

  void _prefetchAudioForWords(List<WordWrapper> newWords) {
    if (newWords.isEmpty) return;
    try {
      final urls = newWords.map((w) => Util.getWordSoundUrl(w.word.spell, word: w.word)).toList();
      SoundUtil.prefetchSounds(urls);
    } catch (e) {
      Global.logger.w('预取音频失败: $e');
    }
  }

  /// 获取第一个（最上方）可见的元素，没有则返回-1
  int getFirstVisibleListItem() {
    int? min;
    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // Determine the first visible item by finding the item with the
      // smallest trailing edge that is greater than 0.  i.e. the first
      // item whose trailing edge in visible in the viewport.
      min = positions
          .where((ItemPosition position) => position.itemTrailingEdge > 0)
          .reduce((ItemPosition min, ItemPosition position) =>
              position.itemTrailingEdge < min.itemTrailingEdge ? position : min)
          .index;
    }
    return min ?? -1;
  }

  Widget _audioLevelBar({bool showDebugValue = false}) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    const barCount = 8; // 更易辨识的紧凑柱数
    return SizedBox(
      height: 48, // 高度再加倍
      child: ValueListenableBuilder<double>(
        valueListenable: _meterLevelNotifier,
        builder: (context, _, __) {
          // 取最后 N 个样本，分桶至 barCount（每柱代表一个时间桶最大值）
          final List<double> samples = List<double>.from(_waveLevels);
          if (samples.isEmpty) {
            return _wavePlaceholder(isDarkMode);
          }
          final int n = samples.length;
          final int bars = barCount;
          final double bucketSize = n / bars;
          final List<double> buckets = List<double>.generate(bars, (i) {
            final start = (i * bucketSize).floor();
            final end = (((i + 1) * bucketSize).ceil()).clamp(start + 1, n);
            double maxv = 0.0;
            for (int k = start; k < end; k++) {
              if (samples[k] > maxv) maxv = samples[k];
            }
            return maxv;
          });

          final barsRow = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(bars, (i) {
              final v = buckets[i].clamp(0.0, 1.0);
              final h = 1.0 + v * 47.0; // 1..48 px 高度（v=0 时几乎不可见）
              final isReady = asr.state == AsrState.started;
              return Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: h,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      color: isReady
                          ? Color.lerp(AppTheme.gradientStartColor,
                              AppTheme.gradientEndColor, v)
                          : (isDarkMode ? Colors.white10 : Colors.black12),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: isReady && v > 0.5
                          ? [
                              BoxShadow(
                                color: AppTheme.gradientStartColor
                                    .withValues(alpha: 0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            }),
          );

          if (!showDebugValue) return barsRow;
          // 叠加调试值显示
          return Stack(
            children: [
              barsRow,
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    color: Colors.transparent,
                    child: Text(
                      _meterLevelNotifier.value.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 9,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _wavePlaceholder(bool isDarkMode) {
    return Row(
      children: List.generate(
          16,
          (i) => Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                    color: asr.state == AsrState.started
                        ? AppTheme.gradientStartColor.withValues(alpha: 0.3)
                        : (isDarkMode
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFEAEAEA)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
    );
  }

  /// 获取最后一个（最下方）可见的元素，没有则返回-1
  int getLastVisibleListItem() {
    int? max;
    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // Determine the last visible item by finding the item with the
      // greatest leading edge that is less than 1.  i.e. the last
      // item whose leading edge in visible in the viewport.
      max = positions
          .where((ItemPosition position) => position.itemLeadingEdge < 1)
          .reduce((ItemPosition max, ItemPosition position) =>
              position.itemLeadingEdge > max.itemLeadingEdge ? position : max)
          .index;
    }
    return max ?? -1;
  }

  /// 订阅音量计数据
  void _subscribeMeterIfNeeded() {
    // 使用 ASR 单例的 meter 订阅管理，避免重复订阅
    _meterSub ??= asr.getOrCreateMeterSubscription((level) {
      _lastMeterLevel = level.clamp(0.0, 1.0);
      _lastMeterAt = AppClock.now();
    });
    _meterTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (isMenuOpen) return; // 菜单打开时暂停更新，避免UI重绘
      final now = AppClock.now();
      final active = _lastMeterAt != null &&
          now.difference(_lastMeterAt!).inMilliseconds < 150;
      final v = (active ? _lastMeterLevel : 0.0).clamp(0.0, 1.0);
      _waveLevels.add(v);
      if (_waveLevels.length > _waveCapacity) {
        _waveLevels.removeRange(0, _waveLevels.length - _waveCapacity);
      }
      // 强制触发重绘：在数值附近加入极小扰动，避免相等不通知
      _meterTickFlip = !_meterTickFlip;
      final bump = _meterTickFlip ? 1e-6 : -1e-6;
      _meterLevelNotifier.value = (v + bump).clamp(0.0, 1.0);
    });
  }

  void _unsubscribeMeter() {
    _meterSub?.cancel();
    _meterSub = null;
    _meterTimer?.cancel();
    _meterTimer = null;
    _meterLevelNotifier.value = 0.0;
    _waveLevels.clear();
    _lastMeterLevel = 0.0;
    _lastMeterAt = null;
  }

  @override
  void initState() {
    final sw = Stopwatch()..start();
    super.initState();
    // 异步预加载音素字典，避免用户说话时才开始解析导致的延迟
    unawaited(PhonemeUtil.load());
    _asrModelLoadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);

    doInit();
    // 立即开始异步加载数据，不再等待首帧完成，减少白屏/加载态感知时间
    loadData();
    
    // 延迟显示列表内容，给路由过渡动画留出呼吸空间
    // 从 150ms 缩减到 20ms，提升进入速度的感知，同时仍保留一帧缓冲
    Future.delayed(const Duration(milliseconds: 20), () {
      if (mounted) {
        setState(() {
          _showList = true;
        });
      }
    });
    _checkAndShowGuide();
    Global.logger.d('WordListPage: initState completed in ${sw.elapsedMilliseconds}ms');
  }

  /// 检查并显示新手引导
  Future<void> _checkAndShowGuide() async {
    try {
      final storage = GetStorage();
      final cacheKey = 'wordListGuideShown_${Global.currentUserId}';

      // 优先从缓存读取，极快
      bool hasShown = storage.read<bool>(cacheKey) ?? false;

      if (!hasShown) {
        // 只有缓存没有时才查数据库
        hasShown = await MyDatabase.instance.localParamsDao.getWordListGuideShown();
        if (hasShown) {
          storage.write(cacheKey, true);
        }
      }

      Global.logger.d('新手引导检查: hasShown=$hasShown');
      if (!hasShown) {
        // 延迟到下一帧，待布局完成后计算菜单按钮位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 再次延迟，确保菜单按钮完全渲染
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;

            try {
              final RenderBox? rb =
                  _menuKey.currentContext?.findRenderObject() as RenderBox?;
              final Offset? topLeft = rb?.localToGlobal(Offset.zero);
              if (rb != null && topLeft != null) {
                _menuRect = Rect.fromLTWH(
                    topLeft.dx, topLeft.dy, rb.size.width, rb.size.height);
                Global.logger.d('菜单按钮位置: $_menuRect');
              } else {
                Global.logger.w('未能获取菜单按钮位置: rb=$rb, topLeft=$topLeft');
              }
            } catch (e) {
              Global.logger.e('获取菜单按钮位置失败: $e');
            }

            Global.logger.d(
                '准备显示引导: mounted=$mounted, dataLoaded=$dataLoaded, _menuRect=$_menuRect');
            if (mounted) {
              setState(() {
                showGuide = true;
              });
              Global.logger.d('已设置 showGuide=true');
            }
          });
        });
      }
    } catch (e) {
      Global.logger.e('检查新手引导失败: $e');
    }
  }

  /// 关闭新手引导（不标记为已显示）
  void _closeGuide() {
    try {
      setState(() {
        showGuide = false;
      });
      // 同时移除可能存在的覆盖层
      _guideOverlay?.remove();
      _guideOverlay = null;
    } catch (e) {
      Global.logger.e('关闭新手引导失败: $e');
    }
  }

  /// 关闭新手引导并标记为不再显示
  Future<void> _dismissGuideForever() async {
    try {
      setState(() {
        showGuide = false;
      });
      // 同时移除可能存在的覆盖层
      _guideOverlay?.remove();
      _guideOverlay = null;
      // 标记为已显示
      await MyDatabase.instance.localParamsDao.setWordListGuideShown(true);
      GetStorage().write('wordListGuideShown_${Global.currentUserId}', true);
    } catch (e) {
      Global.logger.e('关闭新手引导失败: $e');
    }
  }

  /// 正在进行匹配的asr输入，防止重复处理，影响性能
  var handlingAsrChinese = "";

  onAsrResult(event) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    Global.logger.d("~~~~~收到语音识别原始结果: $event");
    if (!mounted) return;

    // 解析逻辑移出 setState
    String processedEvent = "";
    try {
      // 尝试解析JSON格式的候选结果
      Map<String, dynamic>? resultData;
      try {
        resultData = jsonDecode(event);
      } catch (e) {
        // 如果不是JSON格式，当作单个结果处理
        resultData = null;
      }

      if (studyMode == WordListStudyMode.speakEnglish) {
        // ===== 背英文模式：启用音素模糊匹配 =====
        final curr = getBookMarkUiPosition();
        final target =
            (curr >= 0 && curr < words.length) ? words[curr].word.spell : '';

        if (resultData != null && resultData.containsKey('candidates')) {
          // 处理多个候选结果
          List<dynamic> candidates = resultData['candidates'];
          List<String> candidateStrings =
              candidates.map((e) => e.toString()).toList();

          // 结合拼写相似度和音素相似度的智能选择 (Async)
          // 结合拼写相似度和音素相似度的智能选择 (Async)
          final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
              candidateStrings, target);
          // 记录评分到当前单词
          if (curr >= 0 && curr < words.length) {
            words[curr].pronunciationScore = result.score;
          }
          // 进一步进行英文预处理
          processedEvent = AsrUtil.preprocessEnglish(result.text, target);
          Global.logger.d(
              '~~~~~ASR (Phoneme): Selected & Preprocessed: "$processedEvent" (candidates: ${candidateStrings.length}, target: $target, score: ${result.score})');
        } else {
          // 单个结果处理
          // 即使是单结果，也尝试与目标词进行音素匹配 check
          // 先做一次预处理
          final pre = AsrUtil.preprocessEnglish(event, target);
          // 再通过音素匹配确认（把预处理结果作为唯一候选传进去）
          final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
              [pre], target);
          processedEvent = result.text;
          if (curr >= 0 && curr < words.length) {
            words[curr].pronunciationScore = result.score;
          }
          Global.logger.d(
              '~~~~~ASR (Phoneme): Single result: "$event" -> "$processedEvent" (target: $target, score: ${result.score})');
        }

        // 最后确保做一次标准英文预处理（通常上面的步骤已经覆盖，但为了保险再做一次）
        processedEvent = AsrUtil.preprocessEnglish(processedEvent, target);
      } else {
        // ===== 其他模式 (背中文等) =====
        // 直接使用最高排名的候选词，追求极致响应速度，不做二次筛选
        if (resultData != null && resultData.containsKey('candidates')) {
          List<dynamic> candidates = resultData['candidates'];
          processedEvent = resultData['best'] ?? candidates.first.toString();
        } else {
          processedEvent = event;
        }
      }
    } catch (e) {
      Global.logger.e("语音识别结果处理错误: $e");
      processedEvent = event;
    }

    if (!mounted) return;

    // 如果当前有弹出层（如菜单、对话框）或新手引导正在显示，忽略语音结果，
    // 避免频繁的 setState 导致 iPad 上的 Popover (弹出菜单) 失去锚点并关闭。
    if (isMenuOpen || showGuide) {
      return;
    }

    // 计算新的 asrResult
    String newAsrResult = "";
    if (studyMode == WordListStudyMode.speakEnglish) {
      newAsrResult = processedEvent;
    } else {
      // 背中文等模式：进行中文预处理
      newAsrResult = AsrUtil.preprocess(processedEvent);
    }

    Global.logger.d("~~~~~语音识别最终结果: $newAsrResult (耗时: ${DateTime.now().millisecondsSinceEpoch - startTime}ms)");
    
    // 仅当结果变化时才触发 setState，减少UI重建
    if (newAsrResult != asrResult) {
      setState(() {
        asrResult = newAsrResult;
        int activeIdx = getBookMarkUiPosition();
        if (activeIdx >= 0 && activeIdx < words.length) {
          words[activeIdx].lastAsrResult = asrResult;
        }
        if (asrResult.isNotEmpty) {
          if (asrResult != handlingAsrChinese) {
            handlingAsrChinese = asrResult;
            checkAsrResult(asrResult);
          }
        }
      });
    } else {
      // 结果未变化，通过逻辑检查是否需要处理（不触发UI更新）
      if (newAsrResult.isNotEmpty && newAsrResult != handlingAsrChinese) {
        handlingAsrChinese = newAsrResult;
        checkAsrResult(newAsrResult);
      }
    }
  }

  /// 当前并行的asr任务数量（由于协程，并发是可能的）
  int runningAsrTaskCount = 0;

  _incRunningAsrTaskCount() {
    runningAsrTaskCount++;
    Global.logger.d('runningAsrTaskCount增加至$runningAsrTaskCount');
  }

  _decRunningAsrTaskCount() {
    runningAsrTaskCount--;
    Global.logger.d('runningAsrTaskCount减少至$runningAsrTaskCount');
  }

  /// 检查语音识别结果是否匹配单词的意思
  checkAsrResult(String asrResult) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    Global.logger.d("~~~~~开始检查识别结果: $asrResult");

    final currWordIndex = getBookMarkUiPosition();
    if (currWordIndex == -1) return;

    // 记录开始检查时的单词ID
    final checkWordId = words[currWordIndex].word.id;

    if (asr.state != AsrState.started) {
      return;
    }

    _incRunningAsrTaskCount();
    try {
      if (studyMode == WordListStudyMode.speakEnglish) {
        // 背英文模式：检查英文拼写
        String inputText = asrResult.trim().toLowerCase();
        String correctSpell = words[currWordIndex].word.spell.toLowerCase();

        Global.logger
            .d('背英文模式检查: inputText=$inputText, correctSpell=$correctSpell');

        // 判定通过条件：
        // 1. 精确拼写匹配
        // 2. 音素相似度达到阈值
        bool isMatch = inputText == correctSpell;
        if (!isMatch && currWordIndex >= 0 && currWordIndex < words.length) {
          final score = words[currWordIndex].pronunciationScore;
          if (score != null && score >= Constants.phonemeMatchThreshold) {
            Global.logger.d(
                '背英文: 拼写不匹配("$inputText" != "$correctSpell")，但音素相似度($score)达到阈值(${Constants.phonemeMatchThreshold})，判定通过');
            isMatch = true;
          }
        }

        if (isMatch) {
          canLeaveCurrWord = true;
          words[currWordIndex].answeredAllMeanings = true;
          words[currWordIndex].speakEnglishPassed = true;
          
          try {
            await asr.stopAsr().timeout(
              const Duration(milliseconds: 500),
              onTimeout: () {
                Global.logger.w('停止ASR超时，继续播放单词发音');
              },
            );
            await asr.reset().catchError((e) {
              Global.logger.d("重置ASR失败: $e");
            });
          } catch (e) {
            Global.logger.d("停止ASR失败: $e");
          }
          
          try {
            if (!_audioPlayerDisposed) {
              await SoundUtil.playPronounceSound2(
                  words[currWordIndex].word, audioPlayer);
            }
          } catch (e) {
            Global.logger.d("播放发音失败: $e");
          }
        }
      } else {
        // 背中文模式：检查中文释义
        late MeaningMatchResult result;
        setState(() {
          result = matchInputChineseWithMeaningItems(
            words[currWordIndex],
            asrResult,
          );
        });

        if (result.newMatchCount > 0) {
          bool isPass = false;
          switch (asrPassRule) {
            case 'HALF':
              isPass = result.matchedCount >= (result.totalCount / 2).ceil();
              break;
            case 'ALL':
              isPass = result.matchedCount >= result.totalCount;
              break;
            case 'ONE':
            default:
              isPass = true; // 只要有新匹配且规则是 ONE，即可通过
              break;
          }
          if (isPass) {
            canLeaveCurrWord = true;
          }
        }
      }

      // 离开当前单词，跳转到下一个（如果回答正确）
      if (canLeaveCurrWord) {
        // 必须保证还是同一个单词（防止异步竞争）
        if (words[currWordIndex].word.id != checkWordId) {
          Global.logger.d("~~~~~单词已发生变化，丢弃旧识别结果的跳转请求");
          return;
        }

        Global.logger.d("~~~~~满足跳转条件，准备跳转 (当前任务检查耗时: ${DateTime.now().millisecondsSinceEpoch - startTime}ms)");
        // 立即重置标志位，防止重复跳转 (防抖)
        canLeaveCurrWord = false;

        try {
          await asr.stopAsr();
          await asr.reset(); // 清除缓冲区
        } catch (e) {
          Global.logger.d("停止ASR失败: $e");
        }

        var nextWordIndex = currWordIndex + 1;
        if (nextWordIndex == words.length) {
          nextWordIndex = 0;
        }
        var count = 0;
        while (nextWordIndex < words.length) {
          if (!words[nextWordIndex].answeredAllMeanings) {
            break;
          }
          nextWordIndex += 1;
          if (nextWordIndex == words.length) {
            nextWordIndex = 0;
          }
          count += 1;
          if (count > words.length) {
            ToastUtil.info("恭喜，你答对了所有单词");
            return;
          }
        }

        debugPrint('跳转到下一个单词：$nextWordIndex');
        jumpToNextWord(nextWordIndex - 1, true, () {
          debugPrint('已切换到下一个单词：$nextWordIndex');
          asrResult = "";
          handlingAsrChinese = "";
          // 增加 50ms 极短延迟
          Future.delayed(const Duration(milliseconds: 50), () {
            try {
              _startAsr(decideAsrLanguage());
            } catch (e) {
              Global.logger.e("启动ASR失败: $e");
            }
          });
        });
      }
    } catch (e) {
      Global.logger.e("检查语音识别结果时出错: $e");
    } finally {
      _decRunningAsrTaskCount();
    }
  }

  AsrLanguage decideAsrLanguage() {
    if (studyMode == WordListStudyMode.dictation ||
        studyMode == WordListStudyMode.dictationHandwriting ||
        studyMode == WordListStudyMode.speakEnglish) {
      return AsrLanguage.english;
    }
    return AsrLanguage.chinese;
  }

  /// 设置ASR上下文短语（热词机制）
  /// 必须在 startAsr 之前调用，否则只能等到下一次 startAsr 生效
  void _setAsrContextualPhrases([WordVo? word]) {
    try {
      WordVo? targetWord = word;
      if (targetWord == null) {
        int idx = getBookMarkUiPosition();
        if (idx >= 0 && idx < words.length) {
          targetWord = words[idx].word;
        }
      }

      if (targetWord == null) {
        asr.setContextualStrings([]);
        return;
      }

      List<String> phrases = [];
      if (studyMode == WordListStudyMode.speakEnglish) {
        // 说英文模式：热词设为英文拼写
        phrases.add(targetWord.spell);
      } else if (studyMode == WordListStudyMode.speakChinese) {
        // 说中文模式：热词设为该词的所有可能释义项
        phrases.addAll(
            AsrUtil.extractContextualPhrases(targetWord.meaningItems ?? []));
      }

      if (phrases.isNotEmpty) {
        Global.logger.d('~~~~~WordList: 设置 ASR 上下文热词: $phrases');
        asr.setContextualStrings(phrases);
      } else {
        asr.setContextualStrings([]);
      }
    } catch (e) {
      Global.logger.d('WordList: 设置 ASR 上下文短语失败: $e');
    }
  }

  doInit() {
    asr = Asr();
    // 延迟初始化 ASR，避免阻塞页面进入动画
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      asr.initAsr(onAsrResult);
      _subscribeMeterIfNeeded();
    });
    
    asr.addStateListener((state) {
      if (!mounted) return;
      setState(() {
        // 触发 UI 重绘以更新 ASR 状态指示器
      });
      if (state == AsrState.started) {
        // 恢复识别后，确保重新订阅电平流
        _subscribeMeterIfNeeded();
      } else if (state == AsrState.stopped) {
        _unsubscribeMeter();
      }
    });
  }

  Future<bool> checkArgs() async {
    if (Get.arguments == null) {
      Future.delayed(Duration.zero, () {
        // 延迟到下一个tick执行，避免导航冲突
        Get.toNamed('/index', arguments: IndexPageArgs(4));
      });
      return false;
    }
    args = Get.arguments;
    // 移除冗余的数据库查询，直接信任参数。如果参数缺失，才进行兜底检查。
    if (args.canEditWord == false && args.wordsProvider is WordModifier) {
      final String? targetDictId = (args.wordsProvider as WordModifier).targetDictId;
      if (targetDictId != null) {
        final dict = await WordBo().getDict(targetDictId);
        if (dict != null && dict.editable) {
          args.canEditWord = true;
          args.showDelBtn = true;
          args.canAddWord = true;
        }
      }
    }

    return true;
  }

  @override
  void dispose() {
    final sw = Stopwatch()..start();
    _handwritingPaddingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    // 停止 ASR：仅当当前页面处于语音学习模式时才停止，
    // 避免作为子页面销毁时误杀了父页面的 ASR 实例
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      try {
        asr.stopAsr();
      } catch (e) {
        Global.logger.d("dispose: 停止 ASR 失败：$e");
      }
    }

    // 清理 meter 订阅（通过 ASR 单例统一管理）
    _unsubscribeMeter();
    // 确保调用 ASR 的 disposeMeter 来彻底清理
    asr.disposeMeter();

    _audioPlayerDisposed = true; // 标记为已释放
    _meterLevelNotifier.dispose();
    _asrModelLoadingController.dispose();
    _glowController.dispose();

    // 释放所有 WordWrapper 中的资源，移至下一个 Event Loop 执行，避免阻塞 Pop 动画和主页面
    final wordsToDispose = List<WordWrapper>.from(words);
    Timer.run(() {
      final swTotal = Stopwatch()..start();
      for (var word in wordsToDispose) {
        try {
          word.dispose();
        } catch (e) {
          // 忽略已释放资源的错误
        }
      }
      Global.logger.d('WordListPage: Deferred resource disposal of ${wordsToDispose.length} words completed in ${swTotal.elapsedMilliseconds}ms');
    });

    // 清空单词列表，帮助 GC
    words.clear();

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        audioPlayer.dispose();
      } catch (e) {
        Global.logger.d("释放 AudioPlayer 时出错: $e");
      }
    });

    super.dispose();
    Global.logger.d('WordListPage: dispose synchronous part completed in ${sw.elapsedMilliseconds}ms');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // 应用恢复时，如果在语音模式下且ASR未启动，则启动ASR
      _restoreAsrIfNeeded('didChangeAppLifecycleState');
    } else if (state == AppLifecycleState.paused) {
      // 应用进入后台时，停止ASR以节省资源
      asr.stopAsr();
    }
  }

  /// 恢复ASR（如果当前在语音模式下且ASR未启动）
  void _restoreAsrIfNeeded(String caller) {
    // 如果正在加载ASR，则不需要恢复（避免与 _startAsrWithLoading 冲突导致死循环）
    if (_isAsrProcessing) return;

    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      if (asr.state != AsrState.started && asr.state != AsrState.stopping) {
        Global.logger
            .d('$caller: 检测到ASR未启动（当前状态: ${asr.state}），尝试恢复ASR，模式: $studyMode');
        try {
          // 如果ASR卡在initialized状态，先强制停止以清除内部状态
          if (asr.state == AsrState.initialized) {
            Global.logger.d('ASR卡在initialized状态，强制停止后重新启动');
            asr.stopAsr();
            asr.reset();
            // 短暂延迟确保清理完成
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _initializeAndStartAsr();
              }
            });
          } else {
            _initializeAndStartAsr();
          }
        } catch (e, stackTrace) {
          Global.logger.e('恢复ASR失败', error: e, stackTrace: stackTrace);
        }
      }
    }
  }

  /// 初始化并启动ASR的通用方法
  void _initializeAndStartAsr() {
    // 重新初始化事件监听，确保事件订阅有效（类似bdc.dart中的处理）
    asr.initAsr(onAsrResult);
    // 然后启动ASR（内部会加载模型、启动麦克风、设置热词、播放提示音）
    _startAsr(decideAsrLanguage());
    _subscribeMeterIfNeeded();
  }

  jumpToBookMark() {
    if (isBookMarkValid(bookMark)) {
      final bookMarkUiPos = getBookMarkUiPosition();
      if (bookMarkUiPos == -1 || bookMarkUiPos >= words.length) {
        return;
      }

      // 确保数据已加载完成
      if (!dataLoaded || words.isEmpty) {
        return;
      }

      // 检查当前单词是否已经在合适的位置
      var positions = itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        // 找到当前单词的位置信息
        var currentPosition =
            positions.where((pos) => pos.index == bookMarkUiPos).firstOrNull;
        if (currentPosition != null) {
          // 如果单词已经在屏幕中部附近（误差在5%以内），不需要滚动
          if (currentPosition.itemLeadingEdge >= _handwritingScrollAlignment &&
              currentPosition.itemLeadingEdge <= 0.55) {
            return;
          }
          // 如果单词在目标位置上方（更靠近屏幕顶部），不进行向下滚动调整
          if (currentPosition.itemLeadingEdge < 0.5) {
            return;
          }
        }
      }

      // 让书签单词的上沿显示在屏幕中部
      itemScrollController.scrollTo(
          index: bookMarkUiPos,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5); // 显示在屏幕中部
    }
  }

  scrollToWord(int wordUiIndex) {
    if (wordUiIndex < 0 || wordUiIndex >= words.length) return;

    // 确保数据已加载完成
    if (!dataLoaded || words.isEmpty) {
      return;
    }

    // 检查当前单词是否已经在合适的位置
    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // 找到当前单词的位置信息
      var currentPosition =
          positions.where((pos) => pos.index == wordUiIndex).firstOrNull;
      if (currentPosition != null) {
      }
    }

    // 让目标单词的上沿显示在屏幕偏上部（约 35% 处），为底部手写板留出更多视觉空间
    itemScrollController.scrollTo(
        index: wordUiIndex,
        duration: const Duration(milliseconds: 300),
        alignment: _handwritingScrollAlignment); // 稍微偏上
  }

  int getBookMarkUiPosition() {
    if (isBookMarkValid(bookMark)) {
      int position = bookMark!.position - baseIndex!;
      return position >= 0 ? position : -1; // 防止返回负值
    } else {
      return -1;
    }
  }

  Widget renderPage() {
    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (ScrollUpdateNotification notification) {
            // 如果设置了"请勿查询"标志，直接返回
            if (doNotQueryPlease) {
              return false;
            }

            // 如果正在查询或者查询时间间隔未到，跳过本次处理
            if (isQuerying ||
                (lastQueryTime != null &&
                    AppClock.now().difference(lastQueryTime!).inMilliseconds <
                        minQueryInterval)) {
              return false;
            }

            // 向下滚动 - 滑动到最下方单词时，加载下一页单词
            if (notification.scrollDelta != null &&
                notification.scrollDelta! > 0) {
              // 检查是否滚动到最下方单词
              if (notification.metrics.extentAfter < 100) {
                Global.logger.d(
                    '向下滚动触发: extentAfter=${notification.metrics.extentAfter}, baseIndex=$baseIndex, words.length=${words.length}');
                // 使用Future.microtask减少UI阻塞
                Future.microtask(() {
                  doQuery(false, baseIndex! + words.length, _pageSize, false);
                });
              }
            }
            // 向上滚动 - 滑动到最上方单词时，加载上一页单词
            else if (notification.scrollDelta != null &&
                notification.scrollDelta! < 0) {
              // 检查是否滚动到最上方单词，且还有更多内容可以加载
              if (notification.metrics.extentBefore < 100 && baseIndex! > 0) {
                Global.logger.d(
                    '向上滚动触发: extentBefore=${notification.metrics.extentBefore}, baseIndex=$baseIndex, words.length=${words.length}');
                // 使用Future.microtask减少UI阻塞
                Future.microtask(() {
                  Global.logger.d(
                      '开始向上查询: fromIndex=${baseIndex! - _pageSize}, pageSize=$_pageSize');
                  doQuery(false, baseIndex! - _pageSize, _pageSize, false);
                });
              } else if (notification.metrics.extentBefore < 100 &&
                  baseIndex! <= 0) {
                Global.logger.d(
                    '向上滚动检测: 已到最顶部，无法继续向上加载 extentBefore=${notification.metrics.extentBefore}, baseIndex=$baseIndex');
              }
            }


            return false;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // _buildLegend(isDarkMode), // 已移动到更多菜单中
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    // 为每个 item 添加 key，提高重用性
                    return RepaintBoundary(
                      key: ValueKey('word_${words[index].word.id}'),
                      child: renderWord(index),
                    );
                  },
                  itemScrollController: itemScrollController,
                  itemPositionsListener: itemPositionsListener,
                  padding: const EdgeInsets.only(top: 20, bottom: 120),
                ),
              ),
              // 底部的按钮，固定在页面底部
              if (args.injectedBtn != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 24.0),
                  child: args.injectedBtn,
                ),
            ],
          ),
        ),
        // ASR 加载中的大脑动画覆盖层
        if (_isAsrModelLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black12, // 轻微背景遮罩
              child: Center(
                child: AnimatedBuilder(
                  animation: _asrModelLoadingController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 +
                          0.2 *
                              Curves.easeInOut
                                  .transform(_asrModelLoadingController.value),
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.psychology, // 大脑图标
                          size: 48,
                          color: Color(0xFF0097A7),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '加载中...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0097A7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 带加载动画的 ASR 启动封装
  Future<void> _startAsr(AsrLanguage language) async {
    Global.logger.d("~~~~~正在启动 ASR (${language.name})...");
    if (!mounted) return;

    // 如果已经在处理中（无论是否显示动画），都不再重复启动
    if (_isAsrProcessing) {
      Global.logger.d('⚠️ ASR正在启动中，忽略本次调用');
      return;
    }

    // 如果ASR已经在运行，也不需要重复启动
    if (asr.state == AsrState.started) {
      Global.logger.d('✅ ASR已经在运行中，无需重复启动');
      return;
    }

    _isAsrProcessing = true;

    // 只有在语言发生变化（或者第一次启动）时才显示加载动画
    // 因为这通常意味着需要加载不同的声学模型，耗时较长
    // 而同一个语言下的单词切换（热词更新）通常很快，不需要显示动画干扰用户
    bool shouldShowAnimation = _lastAsrLanguage != language;
    _lastAsrLanguage = language;

    if (shouldShowAnimation) {
      setState(() {
        _isAsrModelLoading = true;
      });
      _asrModelLoadingController.repeat(reverse: true);
    }

    try {
      Global.logger.d('开始启动ASR，语言: ${language.locale}');
      _setAsrContextualPhrases();
      await asr.startAsr(language);
      Global.logger.d('ASR启动成功，开始播放提示音');

      // 播放提示音, 提醒用户可以开始说话
      Global.logger.d('播放ASR启动提示音 (已禁用)');
      // SoundUtil.playAsrReadyHintSound();
    } catch (e, stackTrace) {
      Global.logger.e('❌ ASR启动失败', error: e, stackTrace: stackTrace);
    } finally {
      _isAsrProcessing = false;
      if (shouldShowAnimation && mounted) {
        _asrModelLoadingController.stop();
        setState(() {
          _isAsrModelLoading = false;
        });
      }
    }
  }

  Future<void> _showAddWordDialog() async {
    isMenuOpen = true;
    try {
      FocusScope.of(context).unfocus();
      bool wasAnimating = _asrModelLoadingController.isAnimating;
      if (wasAnimating) {
        _asrModelLoadingController.stop();
      }
      final capturedContext = context;
      await Future.delayed(const Duration(milliseconds: 350));
      if (!capturedContext.mounted) return;

      final TextEditingController controller = TextEditingController();
      await showDialog(
        context: capturedContext,
        builder: (context) => AlertDialog(
          title: const Text('添加单词'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: '输入单词拼写',
              labelText: '单词',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                final spell = controller.text.trim();
                if (spell.isEmpty) return;

                final wordModifier = args.wordsProvider as WordModifier;
                // 检查单词是否存在于通用词典
                final searchResult = await WordBo().searchWordLocalOnly(spell);

                if (searchResult.word == null) {
                  ToastUtil.error('单词未在通用词典中找到，无法添加');
                  return;
                }

                // 添加到词典
                final success =
                    await wordModifier.addWord(searchResult.word!.id!);
                if (success) {
                  Get.back();
                  SoundUtil.playAddSuccessSound();
                  // 刷新列表
                  // 此处必须重置 totalWordCount，否则 doQuery 中的优化逻辑(words.length >= totalWordCount)
                  // 会认为数据已全部加载而跳过本次查询，导致新添加的单词无法显示
                  totalWordCount = -1;
                  await doQuery(true, baseIndex ?? 0, _pageSize, true);
                  setState(() {}); // 强制刷新UI
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      );
    } finally {
      isMenuOpen = false;
    }
  }

  Future<void> _showEditMeaningDialog(WordWrapper word) async {
    isMenuOpen = true;
    try {
      FocusScope.of(context).unfocus();
      bool wasAnimating = _asrModelLoadingController.isAnimating;
      if (wasAnimating) {
        _asrModelLoadingController.stop();
      }
      final capturedContext = context;
      await Future.delayed(const Duration(milliseconds: 350));
      if (!capturedContext.mounted) return;

      await showDialog(
        context: capturedContext,
        builder: (context) => EditMeaningDialog(
          word: word,
          wordModifier: args.wordsProvider as WordModifier,
          onSuccess: () async {
            // 立即刷新当前页面
            await doQuery(true, baseIndex ?? 0, _pageSize, false);
            setState(() {}); // 强制刷新UI
          },
        ),
      );
    } finally {
      isMenuOpen = false;
    }
  }

  onWordPressed(WordWrapper word, int index, bool playSound,
      Function? soundFinishListener) async {
    Global.logger.d("~~~~~onWordPressed 被调用: ${word.word.spell}");
    // 更新书签位置
    setState(() {
      if (bookMark == null || bookMark!.position != baseIndex! + index) {
        // 更新老位置的单词状态
        if (bookMark != null &&
            bookMark!.position >= baseIndex! &&
            bookMark!.position < baseIndex! + words.length) {
          int oldIndex = getBookMarkUiPosition();
          if (oldIndex >= 0 && oldIndex < words.length) {
            _revealWordAnswer(words[oldIndex]);
          }
        }

        // 更新书签到新位置
        bookMark = BookMarkVo(baseIndex! + index, word.word.spell);
        // 异步保存书签，并处理结果
        args.bookMarkProvider.saveBookMark(bookMark!).then((success) {
          Global.logger.d("~~~~~书签已保存: ${word.word.spell}");
          if (!success) {
            // 如果保存失败，可以记录日志或者通知用户
            Global.logger.e(
                '书签保存失败: ${word.word.spell}, position: ${baseIndex! + index}');
          }
        });

        word.hintLetterCount = 0;
        word.spellController.text = '';
        word.isAnswerProvidedBySystem = false;
        canLeaveCurrWord = false;
        _detectedSimilarWord = null;

        // 切换到新单词时，重置“背英文”模式的临时状态，避免显示上一个单词的识别/结果
        if (studyMode == WordListStudyMode.speakEnglish) {
          // 切换到新单词时，重置 ASR 识别结果和分数，但保留已通过状态（如果之前已通过）
          asrResult = "";
          word.pronunciationScore = null;
          handlingAsrChinese = "";
        }
      }

      if (studyMode == WordListStudyMode.dictationHandwriting) {
        // _isHandwritingOverlayVisible = true; // 移除这里的全局自动恢复
      }
    });



    // 在默写（dictation）或手写默写模式下，点击单词后让输入框获得焦点（用以触发大字号显示）
    if (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting) {
      try {
        word.focusNode.requestFocus();
      } catch (e, stackTrace) {
        // 焦点请求失败不影响主流程，但需要记录
        Global.logger.w('请求焦点失败', error: e, stackTrace: stackTrace);
      }
    }

    // 在背中文或背英文模式下，手动切换单词时也清空语音识别缓存
    // 强制停止ASR将导致状态变化，从而触发 listener 更新 context strings (热词)
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      await asr.stopAsr();
      await asr.reset(); // 清除缓冲区
    }

    // 播放单词发音（背英文模式/默写模式进入时不播放由调用者控制，避免泄露答案）
    final bool shouldPlaySound = playSound &&
        studyMode != WordListStudyMode.speakEnglish &&
        studyMode != WordListStudyMode.hideEnglish;
    if (shouldPlaySound) {
      debugPrint('播放单词发音: ${word.word.spell}');
      if (studyMode == WordListStudyMode.speakChinese) {
        // 在说中文模式下，为了防止 ASR 识别到手机自身发出的发音，改为等待播放完成后再启动 ASR
        await SoundUtil.playPronounceSound2(word.word, audioPlayer);
        soundFinishListener?.call();
      } else {
        final stopwatch = Stopwatch()..start();
        await SoundUtil.playPronounceSound2(word.word, audioPlayer);
        stopwatch.stop();
        Global.logger.d(
            '~~~~~单词发音播放完成: ${word.word.spell}, 耗时 ${stopwatch.elapsedMilliseconds}ms');
        soundFinishListener?.call();
      }
    } else {
      // 未播放发音时（如背英文模式），也要触发回调以继续流程（启动ASR等）
      soundFinishListener?.call();
    }

    // 在语音模式下，播放完成后启动语音识别
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      _startAsr(decideAsrLanguage());
      _subscribeMeterIfNeeded();
    }
  }

  /// 获取书签中记录的原始位置，如果书签为null，返回-1
  int getBookMarkRawPosition(BookMarkVo? bookMark) {
    return bookMark == null ? -1 : bookMark.position;
  }

  bool isBookMarkValid(BookMarkVo? bookMark) {
    return bookMark != null;
  }

  void _revealWordAnswer(WordWrapper word) {
    if (studyMode == WordListStudyMode.speakChinese) {
      if (!word.answeredAllMeanings) {
        var meaningItems = word.word.getMergedMeaningItems();
        for (var i = 0; i < meaningItems.length; i++) {
          var parts = splitMeaning2Parts(meaningItems[i].meaning!);
          for (var j = 0; j < parts.length; j++) {
            // 如果没被用户答对过，且不是被括号包裹的干扰项
            if (!word.asrMatchedMeaningItemParts.contains(Pair(i, j)) &&
                !_isWholeBracketed(parts[j])) {
              if (!word.asrRevealedMeaningItemParts.contains(Pair(i, j))) {
                word.asrRevealedMeaningItemParts.add(Pair(i, j));
              }
            }
          }
        }
        word.answeredAllMeanings = true;
      }
    } else if (studyMode == WordListStudyMode.speakEnglish) {
      if (!word.speakEnglishPassed) {
        word.speakEnglishPassed = true;
        word.isAnswerProvidedBySystem = true;
      }
    } else if (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting) {
      if (!Util.equalsIgnoreCase(word.spellController.text, word.word.spell)) {
        word.spellController.text = word.word.spell;
        word.isAnswerProvidedBySystem = true;
      }
    }
  }

  bool _isWholeBracketed(String text) {
    String trimmed = text.trim();
    return (trimmed.startsWith('[') && trimmed.endsWith(']')) ||
        (trimmed.startsWith('(') && trimmed.endsWith(')')) ||
        (trimmed.startsWith('（') && trimmed.endsWith('）'));
  }

  onDelBtnPressed(WordWrapper word, int index) {
    final start = DateTime.now().millisecondsSinceEpoch;
    Global.logger.d('[Perf] onDelBtnPressed START: word=${word.word.spell}, index=$index');
    
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final apiStart = DateTime.now().millisecondsSinceEpoch;
      Global.logger.d('[Perf] onDelBtnPressed API_START: delay=${apiStart - start}ms');

      args.wordsProvider.deleteWord(word).then((value) {
        final apiEnd = DateTime.now().millisecondsSinceEpoch;
        Global.logger.d('[Perf] onDelBtnPressed API_END: duration=${apiEnd - apiStart}ms, success=$value');
        
        if (value) {
        // 判断是否应该从UI上移除单词
        // 如果是今日学习相关的列表（包括分批次学习的阶段列表），并且今日学习已经正式开始，则不从UI移除记录，只更新状态
        // 这样可以保持今日学习单词表的记录总数不变，符合已经开始后的预期
        final String providerType = args.wordsProvider.runtimeType.toString();
        final bool isTodayTask = providerType == 'StageWordsProvider' ||
            ['学习中', '今日错词', '今日新词', '今日旧词', '今日单词', '单词列表']
                .contains(args.appBarTitle);
        final bool todayStudyStarted =
            Global.getLoggedInUser()?.todayStudyStarted ?? false;

        if (todayStudyStarted && isTodayTask) {
          // 仅更新状态，不从UI移除
          setState(() {
            word.currentLearningStatus = true;
            // 同时更新进度条显示逻辑所依赖的 tag 数据
            if (word.tag is LearningWordVo) {
              (word.tag as LearningWordVo).stability = 180.0;
            }
          });
          Global.logger.d('[Perf] onDelBtnPressed STATE_UPDATED (todayTask)');
          return;
        }

        // 默认行为：从UI移除单词并更新书签
        setState(() {
          words.remove(word);
          totalWordCount--;
        });
        Global.logger.d('[Perf] onDelBtnPressed STATE_UPDATED (removed)');

        // 更新书签
        if (isBookMarkValid(bookMark)) {
          final bookMarkPosition = getBookMarkRawPosition(bookMark);
          if (index + baseIndex! < bookMarkPosition &&
              bookMarkPosition <= words.length + baseIndex!) {
            var word = words[bookMarkPosition - baseIndex! - 1];
            setState(() {
              bookMark = BookMarkVo(bookMarkPosition - 1, word.word.spell);
            });

              args.bookMarkProvider.saveBookMark(bookMark!).then((success) {
                Global.logger.d('[Perf] onDelBtnPressed BOOKMARK_UPDATED: success=$success');
              });
            }
          }

          if (words.length < minWordCount) {
            doQuery(false, baseIndex! + words.length, _pageSize, false);
          }
        }
      });
    });
  }

  onMasterBtnPressed(WordWrapper word, int index) {
    Global.logger.d('[Perf] onMasterBtnPressed START: word=${word.word.spell}');

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final apiStart = DateTime.now().millisecondsSinceEpoch;

      args.wordsProvider.masterWord(word).then((value) {
        final apiEnd = DateTime.now().millisecondsSinceEpoch;
        Global.logger.d('[Perf] onMasterBtnPressed API_END: duration=${apiEnd - apiStart}ms, success=$value');

        if (value) {
          final String providerType = args.wordsProvider.runtimeType.toString();
          final bool isTodayTask = providerType == 'StageWordsProvider' ||
              ['学习中', '今日错词', '今日新词', '今日旧词', '今日单词', '单词列表']
                  .contains(args.appBarTitle);
          final bool todayStudyStarted =
              Global.getLoggedInUser()?.todayStudyStarted ?? false;

          if ((todayStudyStarted && isTodayTask) ||
              args.wordsProvider.keepWordsOnMaster) {
            setState(() {
              word.currentLearningStatus = true;
              if (word.tag is LearningWordVo) {
                (word.tag as LearningWordVo).stability = 180.0;
              }
            });
            Global.logger.d('[Perf] onMasterBtnPressed STATE_UPDATED (keep)');
            return;
          }

          setState(() {
            word.currentLearningStatus = true;
            if (word.tag is LearningWordVo) {
              (word.tag as LearningWordVo).stability = 180.0;
            }
            words.remove(word);
            totalWordCount--;
          });
          Global.logger.d('[Perf] onMasterBtnPressed STATE_UPDATED (removed)');

          if (isBookMarkValid(bookMark)) {
            final bookMarkPosition = getBookMarkRawPosition(bookMark);
            if (index + baseIndex! < bookMarkPosition &&
                bookMarkPosition <= words.length + baseIndex!) {
              var word = words[bookMarkPosition - baseIndex! - 1];
              setState(() {
                bookMark = BookMarkVo(bookMarkPosition - 1, word.word.spell);
              });
              args.bookMarkProvider.saveBookMark(bookMark!).then((success) {
                Global.logger.d('[Perf] onMasterBtnPressed BOOKMARK_UPDATED: success=$success');
              });
            }
          }

          if (words.length < minWordCount) {
            doQuery(false, baseIndex! + words.length, _pageSize, false);
          }
        }
      });
    });
  }

  onUnmasterBtnPressed(WordWrapper word, int index) {
    Global.logger.d('[Perf] onUnmasterBtnPressed START: word=${word.word.spell}');

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final initialStatus = word.initialLearningStatus;
      final apiStart = DateTime.now().millisecondsSinceEpoch;
      Global.logger.d('[Perf] onUnmasterBtnPressed PATH: initialStatus=$initialStatus');

      args.wordsProvider.unmasterWord(word).then((value) {
        final apiEnd = DateTime.now().millisecondsSinceEpoch;
        Global.logger.d('[Perf] onUnmasterBtnPressed API_END: duration=${apiEnd - apiStart}ms, success=$value');
        if (value) {
          if (initialStatus == true && !args.wordsProvider.keepWordsOnMaster) {
            setState(() {
              words.remove(word);
              totalWordCount--;
            });
            if (isBookMarkValid(bookMark)) {
              final bookMarkPosition = getBookMarkRawPosition(bookMark);
              if (index + baseIndex! < bookMarkPosition &&
                  bookMarkPosition <= words.length + baseIndex!) {
                var prevWord = words[bookMarkPosition - baseIndex! - 1];
                setState(() {
                  bookMark = BookMarkVo(bookMarkPosition - 1, prevWord.word.spell);
                });
                args.bookMarkProvider.saveBookMark(bookMark!).then((success) {});
              }
            }
            if (words.length < minWordCount) {
              doQuery(false, baseIndex! + words.length, _pageSize, false);
            }
          } else {
            setState(() {
              word.currentLearningStatus = initialStatus;
              if (word.tag is LearningWordVo) {
                (word.tag as LearningWordVo).stability = 0.0;
              }
            });
            Global.logger.d('[Perf] onUnmasterBtnPressed STATE_UPDATED');
          }
        }
      });
    });
  }

  Color progressColor(WordWrapper word) {
    double ratio = args.wordProgressProvider.getWordProgress(word.tag) /
        args.wordProgressProvider.getWordProgressMax(word.tag);
    if (ratio < 0.4) {
      return Colors.red;
    } else if (ratio < 0.6) {
      return Colors.orange;
    } else if (ratio < 0.8) {
      return Colors.blueGrey;
    } else if (ratio < 1.0) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }

  void clearWordStates() {
    for (var word in words) {
      word.hintLetterCount = 0;
      word.asrMatchedMeaningItemParts = [];
      word.asrRevealedMeaningItemParts = [];
      word.answeredAllMeanings = false;
      word.speakEnglishPassed = false;
      word.pronunciationScore = null;
      word.lastAsrResult = null;
    }
  }

  Widget _buildWordDecoration(
      {required Widget child,
      required bool isBookmarked,
      required bool isDarkMode,
      bool? learningStatus}) {
    final isAsrReady = isBookmarked && asr.state == AsrState.started;

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        // 计算动态阴影
        List<BoxShadow>? shadows;
        if (isAsrReady) {
          final glow = 1.0 - _glowController.value;
          shadows = [
            // 外层大云雾
            BoxShadow(
              color: AppTheme.gradientStartColor.withValues(alpha: 0.2 * glow),
              blurRadius: 15 + 10 * glow,
              spreadRadius: 2 + 4 * glow,
            ),
            // 内层亮色光晕
            BoxShadow(
              color: AppTheme.gradientEndColor.withValues(alpha: 0.3 * glow),
              blurRadius: 8 + 5 * glow,
              spreadRadius: 1 + 2 * glow,
            ),
          ];
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.black26 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: shadows,
            border: Border.all(
              width: 1.8,
              strokeAlign: BorderSide.strokeAlignInside,
              color: isBookmarked
                  ? (isAsrReady 
                      ? AppTheme.gradientStartColor.withValues(alpha: 0.5)
                      : const Color(0xFF0097A7))
                  : Colors.transparent,
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  void _handleWordTap(WordWrapper word, int index) {
    if (studyMode == WordListStudyMode.dictation ||
        studyMode == WordListStudyMode.dictationHandwriting) {
      // 揭晓答案：如果是切换单词，播放当前正在离开的那个词
      int curr = getBookMarkUiPosition();
      if (curr >= 0 && curr < words.length && curr != index) {
        SoundUtil.playPronounceSound2(words[curr].word, audioPlayer);
        onWordPressed(word, index, false, null);
      } else {
        // 如果点击的就是当前单词（左侧区域），则手动播放该词发音
        onWordPressed(word, index, true, null);
      }
    } else {
      onWordPressed(word, index, true, null);
    }
  }

  void _handleWordLongPress(WordWrapper word, int i) {
    Get.to(() => const WordDetailPage(),
        arguments: WordDetailPageArgs(word.word, true, null, false));
  }

  List<Widget> _getSlidableActions(WordWrapper word, int i, bool isBookmarked,
      {bool? learningStatus}) {
    final List<Widget> actions = [];
    final String title = args.appBarTitle;
    final bool isMastered = learningStatus == true;

    // 1. 编辑按钮
    if (args.canEditWord && args.wordsProvider is WordModifier && title != '已掌握') {
      actions.add(SlidableAction(
        onPressed: (_) => _showEditMeaningDialog(word),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        icon: Icons.edit,
        label: '编辑',
      ));
    }

    // 2. 提示相关按钮 (仅对书签单词有效)
    if (isBookmarked && (studyMode == WordListStudyMode.dictation ||
            studyMode == WordListStudyMode.dictationHandwriting ||
        studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) && word.hintLetterCount > 0) {
      // 提示按钮已移至右侧点击区域
      actions.add(SlidableAction(
        onPressed: (_) => clearHint(word),
        backgroundColor: const Color(0xFF9E9E9E),
        foregroundColor: Colors.white,
        icon: Icons.refresh,
        label: '重置',
      ));
    }

    // 3. 掌握/删除/重学 逻辑
    const specialLists = ['学习中', '单词列表', '今日错词', '今日新词', '今日旧词', '今日单词'];
    final bool isSpecialList = specialLists.contains(title);

    if (title != '已掌握' && !isSpecialList) {
      actions.add(SlidableAction(
        onPressed: (_) => isMastered
            ? onUnmasterBtnPressed(word, i)
            : onMasterBtnPressed(word, i),
        backgroundColor: isMastered ? Colors.grey[400]! : const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        icon: isMastered ? Icons.check_circle : Icons.check_circle_outline,
        label: isMastered ? '已掌握' : '掌握',
      ));
    }

    if (args.showDelBtn || isSpecialList) {
      if (isMastered && isSpecialList) {
        actions.add(SlidableAction(
          onPressed: (_) => onUnmasterBtnPressed(word, i),
          backgroundColor: Colors.grey[400]!,
          foregroundColor: Colors.white,
          icon: Icons.check_circle,
          label: '已熟知',
        ));
      } else {
        String buttonText;
        Color color;
        IconData icon;
        
        if (title == '已掌握') {
          buttonText = '重学';
          color = const Color(0xFF2196F3);
          icon = Icons.replay;
        } else if (isSpecialList) {
          buttonText = '熟知';
          color = const Color(0xFF26A69A);
          icon = Icons.check_circle;
        } else {
          buttonText = '删除';
          color = const Color(0xFFEF5350);
          icon = Icons.delete;
        }

        actions.add(SlidableAction(
          onPressed: (_) => (buttonText == '掌握' || buttonText == '熟知') 
              ? onMasterBtnPressed(word, i) 
              : onDelBtnPressed(word, i),
          backgroundColor: color,
          foregroundColor: Colors.white,
          icon: icon,
          label: buttonText,
        ));
      }
    }

    return actions;
  }

  Widget _buildSpeakEnglishArea(
      WordWrapper word, bool isBookmarked, bool isDarkMode) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!word.speakEnglishPassed)
          _buildSpeakEnglishNotPassed(word, isBookmarked, isDarkMode)
        else
          _buildSpeakEnglishPassed(word, isBookmarked, isDarkMode),
      ],
    );
  }

  Widget _buildSpeakEnglishNotPassed(
      WordWrapper word, bool isBookmarked, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 下划线：只有当前单词显示提示，其他只显示下划线
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode
                      ? Colors.white38
                      : (Colors.grey[500] ?? Colors.grey),
                  width: 1.0,
                ),
              ),
            ),
            child: Text(
              // 只有当前单词才显示提示文字
              isBookmarked
                  ? (word.hintLetterCount > 0
                      ? word.word.spell.substring(0, word.hintLetterCount)
                      : '请说出单词发音')
                  : (word.lastAsrResult != null && word.lastAsrResult!.isNotEmpty
                      ? word.lastAsrResult!
                      : (word.hintLetterCount > 0
                          ? word.word.spell.substring(0, word.hintLetterCount)
                          : '')), // 非当前单词显示提示或识别结果，否则保持原样
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563),
                height: 1.2,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        if (isBookmarked &&
            word.pronunciationScore != null &&
            word.pronunciationScore! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: word.pronunciationScore! >= 60
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.record_voice_over,
                    size: 14,
                    color: word.pronunciationScore! >= 60
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '发音: ${word.pronunciationScore}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: word.pronunciationScore! >= 60
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpeakEnglishPassed(
      WordWrapper word, bool isBookmarked, bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 估算单词和音标所需的宽度
        final spellWidth = word.word.spell.length * 14.0; // 估算单词宽度
        final pronounceWidth = word.word.mergedPronounce.isNotEmpty
            ? (word.word.mergedPronounce.length * 7.0 +
                24.0) // 估算音标宽度（包括容器padding）
            : 0.0;
        final totalWidth = spellWidth + pronounceWidth + 8.0; // 包括间距

        // 如果总宽度超过可用宽度，或者音标很长，则换行显示
        final shouldWrap = totalWidth > constraints.maxWidth ||
            (word.word.mergedPronounce.isNotEmpty &&
                word.word.mergedPronounce.length > 25);

        if (shouldWrap && word.word.mergedPronounce.isNotEmpty) {
          // 换行显示：单词一行，音标一行
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 单词行
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  word.word.spell,
                  softWrap: false,
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                    color: word.isAnswerProvidedBySystem
                        ? (isDarkMode ? Colors.white : const Color(0xFF1F2937))
                        : (isBookmarked
                            ? const Color(0xFF0097A7)
                            : (isDarkMode ? Colors.white : const Color(0xFF1F2937))),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              // 音标行
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '[${word.word.mergedPronounce}]',
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                    fontFamily: 'NotoSans',
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          );
        } else {
          // 同行显示：单词和音标在一行
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.word.spell,
                softWrap: false,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: word.isAnswerProvidedBySystem
                      ? (isDarkMode ? Colors.white : const Color(0xFF1F2937))
                      : (isBookmarked
                          ? const Color(0xFF0097A7)
                          : (isDarkMode ? Colors.white : const Color(0xFF1F2937))),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (word.word.mergedPronounce.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '[${word.word.mergedPronounce}]',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                      fontFamily: 'NotoSans',
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildSpeakChineseArea(WordWrapper word) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: renderAsrMeaningItems(word),
    );
  }

  Widget _buildDictationTextField(WordWrapper word, int i, bool isDarkMode) {
    return AnimatedBuilder(
      animation: word.focusNode,
      builder: (context, child) {
        const fontSize = 16.0;
        final isHandwriting = studyMode == WordListStudyMode.dictationHandwriting;
        return TextField(
          readOnly: isHandwriting,
          enableInteractiveSelection: !isHandwriting,
          controller: word.spellController,
          focusNode: word.focusNode,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            isCollapsed: true,
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: isHandwriting
                ? const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey))
                : const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0097A7))),
            contentPadding: EdgeInsets.zero,
            hintText: isHandwriting ? '请在屏幕任何位置手写拼写' : null,
            hintStyle: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white24 : Colors.black26),
          ),
          onTap: () {
            bool isAlreadyActive = getBookMarkUiPosition() == i;
            if (!isAlreadyActive) {
              // 揭晓答案：离开旧词时播放旧词发音
              int curr = getBookMarkUiPosition();
              if (curr >= 0 && curr < words.length) {
                SoundUtil.playPronounceSound2(words[curr].word, audioPlayer);
              }
            }
            onWordPressed(word, i, false, null);
            if (isAlreadyActive) {
              giveALittleHint(word);
            }
          },
          onChanged: (value) async {
            // 先刷新UI，使颜色立即变绿
            setState(() {});
            // 如果拼写正确：先让UI变绿，再执行后续动作（播放离开单词发音+跳转）
            if (Util.equalsIgnoreCase(word.word.spell, value)) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  await SoundUtil.playPronounceSound2(word.word, audioPlayer);
                } catch (e, stackTrace) {
                  // 音频播放失败不影响主流程，但需要记录
                  Global.logger.w('播放单词发音失败', error: e, stackTrace: stackTrace);
                }
                jumpToNextWord(i, false, () {});
              });
            }
          },
          style: TextStyle(
              fontSize: fontSize,
              color: Util.equalsIgnoreCase(
                      word.word.spell, word.spellController.text)
                  ? word.isAnswerProvidedBySystem
                      ? (isDarkMode ? Colors.white : const Color(0xFF1F2937))
                      : Colors.green
                  : Colors.red),
        );
      },
    );
  }

  Widget _buildDictationHint(WordWrapper word) {
    if (word.hintLetterCount <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(word.word.spell.substring(0, word.hintLetterCount)),
        ],
      ),
    );
  }


  Widget _buildHiddenAnswerArea(WordWrapper word, int index, bool isDarkMode, bool isEnglish) {
    // 准备实际的内容
    final Widget answerContent = isEnglish
        ? _buildWordHeader(word, getBookMarkUiPosition() == index, isDarkMode)
        : _buildWordMeaning(word, isDarkMode, topPadding: 0);

    if (word.isAnswerRevealed) {
      return answerContent;
    }

    // 未揭晓时，使用 Stack：
    // 底层放透明的实际内容来撑开空间（解决界面晃动问题），顶层放提示按钮
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        // 占位层：完全透明但占据空间，确保高度与揭晓后一致
        Opacity(
          opacity: 0.0,
          child: answerContent,
        ),
        // 按钮层：实际看到的“点击显示”按钮
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDarkMode ? Colors.white10 : Colors.black12,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 6),
              Text(
                isEnglish ? '点击显示英文' : '点击显示中文',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWordMeaning(WordWrapper word, bool isDarkMode, {double topPadding = 8}) {
    final meaning = word.word.getMeaningStr();
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        child: Text(
          meaning.isNotEmpty ? meaning : "（暂无释义）",
          textScaler: TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
            height: 1.5,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildWordHeader(WordWrapper word, bool isBookmarked, bool isDarkMode,
      {bool? learningStatus}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 单词行
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            word.word.spell,
            softWrap: false,
            textScaler: TextScaler.linear(1.0),
            style: TextStyle(
              color: isBookmarked
                  ? const Color(0xFF0097A7)
                  : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (word.word.mergedPronounce.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '[${word.word.mergedPronounce}]',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.black38,
              fontSize: 12,
              fontFamily: 'NotoSans',
              fontWeight: FontWeight.w400,
              height: 1.3,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ],
    );
  }

  Widget _buildAudioIndicator(
      WordWrapper word, bool isBookmarked, bool isDarkMode) {
    if (isBookmarked) {
      // 当前单词显示波形
      return Container(
        width: 32,
        height: 12,
        margin: const EdgeInsets.only(top: 3),
        child: _audioLevelBar(),
      );
    } else if (word.pronunciationScore != null &&
        word.pronunciationScore! > 0) {
      // 已过单词显示评分
      return Container(
        width: 32,
        height: 12,
        margin: const EdgeInsets.only(top: 3),
        alignment: Alignment.center,
        child: Text(
          '${word.pronunciationScore}',
          textScaler: TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w900,
            fontFamily: 'RobotoCondensed',
            color:
                word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
          ),
        ),
      );
    }
    return Container();
  }


  Widget _buildLegendForMenu(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildLegendItem(Colors.orange, '学习中', isDarkMode),
          const SizedBox(width: 16),
          _buildLegendItem(const Color(0xFF4CAF50), '已掌握', isDarkMode),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDarkMode ? Colors.white60 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildWordProgressContainer(WordWrapper word, bool isDarkMode,
      {double width = 32}) {
    return Container(
      width: width,
      height: 4,
      margin: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        child: FAProgressBar(
          borderRadius: const BorderRadius.all(Radius.circular(2)),
          currentValue: args.wordProgressProvider.getWordProgress(word.tag),
          maxValue: args.wordProgressProvider.getWordProgressMax(word.tag),
          displayText: '',
          direction: Axis.horizontal,
          displayTextStyle:
              const TextStyle(color: Color(0x00000000), fontSize: 0),
          backgroundColor:
              isDarkMode ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
          progressColor: progressColor(word),
          animatedDuration: const Duration(milliseconds: 200),
        ),
      ),
    );
  }

  Widget renderWord(final int i) {
    _renderWordCallCount++;
    var word = words[i];
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final learningStatus = word.currentLearningStatus;

    return ValueListenableBuilder<int>(
      valueListenable: activeWordIndexNotifier,
      builder: (context, activeIndex, child) {
        final isBookmarked = activeIndex == i;

        // 基础单词内容
        Widget content = _buildWordDecoration(
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          child: _renderWordContent(word, i, isBookmarked, isDarkMode, learningStatus),
        );

        // 检查是否需要显示单元标题（仅当Provider是DictWordsProvider时）
        if (args.wordsProvider is DictWordsProvider) {
          final dictWord = word.tag;
          if (dictWord is DictWordVo) {
            bool showHeader = false;
            if (i == 0) {
              showHeader = true;
            } else {
              final prevWord = words[i - 1];
              final prevDictWord = prevWord.tag;
              if (prevDictWord is DictWordVo) {
                if (prevDictWord.unit != dictWord.unit) {
                  showHeader = true;
                }
              } else {
                showHeader = true;
              }
            }

            if (showHeader && dictWord.unit != 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUnitHeader(dictWord.unit, isDarkMode),
                  content,
                ],
              );
            }
          }
        }

        return content;
      },
    );
  }

  Widget _buildUnitHeader(int unit, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(top: 24, bottom: 8, left: 12, right: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: AppTheme.primaryColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bookmark,
            size: 18,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            '第 $unit 单元',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
              fontFamily: 'NotoSansSC',
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderWordContent(WordWrapper word, int i, bool isBookmarked,
      bool isDarkMode, bool? learningStatus) {
    final actions = _getSlidableActions(word, i, isBookmarked,
        learningStatus: learningStatus);

    // 获取状态颜色
    Color? statusColor;
    if (learningStatus == true) {
      statusColor = const Color(0xFF4CAF50); // 已掌握 - 绿色
    } else if (learningStatus == false) {
      statusColor = Colors.orange; // 学习中 - 橙色
    }

    // 确定背景色
    final bgColor = isDarkMode
        ? (isBookmarked ? const Color(0xFF12353A) : const Color(0xFF1E1E1E))
        : (isBookmarked ? const Color(0xFFE0F2F1) : Colors.white);

    Widget itemContent = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: bgColor,
        child: Stack(
          children: [
            /// 1. 左侧高长条背景 (通过 Positioned.fill 自动伸缩至全高)
            Positioned.fill(
              child: Row(
                children: [
                  Container(
                    width: 32,
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.15)
                        : const Color(0xFFE2E8F0),
                  ),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),

            /// 2. 实际内容层
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                /// 左侧热区 (序号 + 状态)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handleWordTap(word, i),
                  onLongPress: () => _handleWordLongPress(word, i),
                  child: SizedBox(
                    width: 32,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(baseIndex! + i + 1) > 0 ? (baseIndex! + i + 1) : 1}',
                          textScaler: const TextScaler.linear(1.0),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white38 : Colors.black38,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (statusColor != null)
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),

                        /// 掌握度进度条（横条）
                        if (args.showWordProgress)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _buildWordProgressContainer(word, isDarkMode,
                                width: 22),
                          ),

                        // 紧凑波形或评分
                        if (studyMode == WordListStudyMode.speakChinese ||
                            studyMode == WordListStudyMode.speakEnglish)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _buildAudioIndicator(
                                word, isBookmarked, isDarkMode),
                          ),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      /// 左半部内容 (点击发音)
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _handleWordTap(word, i),
                          onLongPress: () => _handleWordLongPress(word, i),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
                            child: (studyMode == WordListStudyMode.speakEnglish || studyMode == WordListStudyMode.hideEnglish)
                                ? _buildWordMeaning(word, isDarkMode,
                                    topPadding: 0)
                                : (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting)
                                    ? _buildWordMeaning(word, isDarkMode, topPadding: 0)
                                    : _buildWordHeader(word, isBookmarked,
                                        isDarkMode,
                                        learningStatus: learningStatus),
                          ),
                        ),
                      ),

                      /// 右半部内容 (点击提示)
                      Expanded(
                        flex: 3,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // 1. 全屏透明点击层，确保整个区域可点击
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (studyMode == WordListStudyMode.hideChinese ||
                                      studyMode == WordListStudyMode.hideEnglish) {
                                    setState(() {
                                      word.isAnswerRevealed = !word.isAnswerRevealed;
                                    });
                                    if (getBookMarkUiPosition() != i) {
                                      onWordPressed(word, i, true, null);
                                    }
                                  } else if (isBookmarked && (studyMode == WordListStudyMode.dictation ||
                                          studyMode == WordListStudyMode.dictationHandwriting ||
                                          studyMode == WordListStudyMode.speakChinese ||
                                          studyMode == WordListStudyMode.speakEnglish)) {
                                    giveALittleHint(word);
                                  } else {
                                    _handleWordTap(word, i);
                                  }
                                },
                                onLongPress: () => _handleWordLongPress(word, i),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            // 2. 实际内容层
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  (isBookmarked && (studyMode == WordListStudyMode.dictation ||
                                          studyMode == WordListStudyMode.dictationHandwriting ||
                                          studyMode == WordListStudyMode.speakChinese ||
                                          studyMode == WordListStudyMode.speakEnglish))
                                      ? IgnorePointer(
                                          ignoring: (studyMode != WordListStudyMode.dictation && studyMode != WordListStudyMode.dictationHandwriting),
                                          child: (studyMode == WordListStudyMode.speakChinese)
                                              ? _buildSpeakChineseArea(word)
                                              : (studyMode == WordListStudyMode.speakEnglish)
                                                  ? _buildSpeakEnglishArea(word, isBookmarked, isDarkMode)
                                                  : _buildDictationTextField(word, i, isDarkMode),
                                        )
                                      : (studyMode == WordListStudyMode.speakChinese)
                                          ? _buildSpeakChineseArea(word)
                                          : (studyMode == WordListStudyMode.speakEnglish)
                                              ? _buildSpeakEnglishArea(word, isBookmarked, isDarkMode)
                                              : (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting)
                                                  ? _buildDictationTextField(word, i, isDarkMode)
                                                  : (studyMode == WordListStudyMode.hideChinese)
                                                      ? _buildHiddenAnswerArea(word, i, isDarkMode, false)
                                                      : (studyMode == WordListStudyMode.hideEnglish)
                                                          ? _buildHiddenAnswerArea(word, i, isDarkMode, true)
                                                          : _buildWordMeaning(word, isDarkMode, topPadding: 0),
                                  
                                  /// 给点提示 (如果是默写模式，位置在输入框下方)
                                    if (word.hintLetterCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: _buildDictationHint(word),
                                      ),
                                    if (studyMode == WordListStudyMode.dictationHandwriting &&
                                        getBookMarkUiPosition() == i)
                                      const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                if (studyMode == WordListStudyMode.dictationHandwriting)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // 揭晓答案
                      int curr = getBookMarkUiPosition();
                      if (curr >= 0 && curr < words.length && curr != i) {
                        SoundUtil.playPronounceSound2(words[curr].word, audioPlayer);
                      }
                      setState(() {
                        _isHandwritingOverlayOpen = true;
                      });
                      onWordPressed(word, i, false, null);
                      _handwritingBoardKey.currentState?.clearBoardSilently();
                    },
                    child: Container(
                      width: 60,
                      color: isDarkMode 
                          ? Colors.white.withValues(alpha: 0.01) 
                          : Colors.black.withValues(alpha: 0.01),
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 20,
                          color: isBookmarked
                              ? const Color(0xFF0097A7)
                              : (isDarkMode ? Colors.white38 : Colors.black38),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
    ),
  ),
);


    if (actions.isEmpty || (studyMode == WordListStudyMode.dictationHandwriting && _isHandwritingOverlayOpen)) return itemContent;

    return Slidable(
      key: ValueKey('slidable_${word.word.id}'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: (0.25 * actions.length).clamp(0.0, 0.75),
        children: actions,
      ),
      child: itemContent,
    );
  }

  void jumpToNextWord(final int currWordIndex, bool playPronounce,
      Function? soundFinishListener) {
    if (currWordIndex < words.length - 1) {
      var nextWord = words[currWordIndex + 1];
      onWordPressed(
          nextWord, currWordIndex + 1, playPronounce, soundFinishListener);
      if (studyMode == WordListStudyMode.dictation) {
        nextWord.focusNode.requestFocus();
      }
      if (studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish ||
          studyMode == WordListStudyMode.dictationHandwriting) {
        scrollToWord(currWordIndex + 1);

        /// 如果目标单词不可见（在视口下方），则视口向下滚动一个单词
        /*if (currWordIndex + 3 >= getLastVisibleListItem()) {
          scrollToWord(getFirstVisibleListItem() + 1);
        }*/
      }
    } else {
      // 到达最后一个单词
      // 跳回第一个单词
      if (studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish) {
        // 确保书签更新到第一个单词
        if (words.isNotEmpty) {
          onWordPressed(words[0], 0, playPronounce, soundFinishListener);
        }
        jumpToNextWord(-1, playPronounce, soundFinishListener);
        scrollToWord(0);
      }
    }
  }

  void jumpToPreviousWord(final int currWordIndex, bool playPronounce) {
    if (currWordIndex > 0) {
      var prevWord = words[currWordIndex - 1];
      onWordPressed(prevWord, currWordIndex - 1, playPronounce, null);
      if (studyMode == WordListStudyMode.dictation) {
        prevWord.focusNode.requestFocus();
      }
      if (studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish ||
          studyMode == WordListStudyMode.dictationHandwriting) {
        scrollToWord(currWordIndex - 1);
      }
    }
  }

  void clearHint(WordWrapper word) {
    setState(() {
      word.hintLetterCount = 0;
      // 在背英文模式下，清除提示时也清空识别结果，以便显示默认提示文字
      if (studyMode == WordListStudyMode.speakEnglish) {
        asrResult = "";
        word.pronunciationScore = null;
        word.speakEnglishPassed = false;
      }
    });
  }

  void giveALittleHint(WordWrapper word) {
    setState(() {
      if (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting) {
        if (word.hintLetterCount < word.word.spell.length) {
          word.hintLetterCount++;
        }
      } else if (studyMode == WordListStudyMode.speakChinese) {
        word.hintLetterCount++;
      } else if (studyMode == WordListStudyMode.speakEnglish) {
        if (word.hintLetterCount < word.word.spell.length) {
          word.hintLetterCount++;
        }
      }
    });
  }

  void giveFullHint(WordWrapper word) {
    setState(() {
      if (studyMode == WordListStudyMode.dictation ||
          studyMode == WordListStudyMode.dictationHandwriting ||
          studyMode == WordListStudyMode.speakEnglish) {
        word.hintLetterCount = word.word.spell.length;
      } else if (studyMode == WordListStudyMode.speakChinese) {
        word.hintLetterCount = 999;
      }
    });
  }

  void _clearHandwritingHints(WordWrapper? word) {
    if (_detectedSimilarWord != null || (word?.hintLetterCount ?? 0) > 0) {
      setState(() {
        _detectedSimilarWord = null;
        if (word != null) {
          word.hintLetterCount = 0;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final swBuild = Stopwatch()..start();
    _renderWordCallCount = 0;
    Global.logger.d('PERF_LOG_PENCIL [页面 build 开始]');
    activeWordIndexNotifier.value = _tempHandwritingSelectedIndex ?? getBookMarkUiPosition();

    super.build(context); // 必须调用，因为使用了 AutomaticKeepAliveClientMixin
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    // 在页面build时，检查页面是否可见，如果可见且在语音模式下，确保ASR已启动
    // 如果不可见且在语音模式下，停止ASR（用于从页面离开时停止）
    // 移除原有的 build 中直接调用 postFrameCallback 的 visibility 检查逻辑，
    // 改为在需要时（如 onSelected 或 dispose）处理 ASR 状态，或通过专门的监听器。
    // 这里保留 build 方法的简洁性。

    final popScopeWidget = PopScope(
      canPop: studyMode != WordListStudyMode.dictationHandwriting,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Stack(
      children: [
        Scaffold(
          resizeToAvoidBottomInset: false, // 禁止分屏或键盘变化导致的布局挤压，提升 iPad 稳定性
          backgroundColor:
              isDarkMode ? const Color(0xFF121212) : const Color(0xFFF9FAFB),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppTheme.gradientStartColor,
                    AppTheme.gradientEndColor,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                args.showBackBtn
                    ? IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon:
                            const Icon(Icons.arrow_back, color: Colors.white),
                      )
                    : const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          args.appBarTitle,
                          textScaler: TextScaler.linear(1.0),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            height: 1.3,
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (dataLoaded)
                        Text(
                          ' ($totalWordCount)',
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.3,
                            letterSpacing: 0.2,
                          ),
                        ),
                    ],
                  ),
                ),

                      /// 书签图标 - 跳到第一个单词
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.bookmark,
                                  color: Colors.white, size: 28),
                              Text(
                                'S',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        onTap: () async {
                          setState(() {
                            clearQueryResult();
                            baseIndex = 0;
                            doQuery(false, 0, 50, false).then((_) {
                              // 添加这一行，确保跳转到第一个单词
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                itemScrollController.scrollTo(
                                    index: 0,
                                    duration: const Duration(milliseconds: 300),
                                    alignment: _handwritingScrollAlignment); // 显示在屏幕偏上部
                              });
                            });
                          });
                        },
                      ),

                      /// 书签图标 - 跳到书签位置
                      if (isBookMarkValid(bookMark))
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.bookmark,
                                    color: Colors.white, size: 28),
                                Text(
                                  isBookMarkValid(bookMark)
                                      ? '${getBookMarkRawPosition(bookMark) + 1}'
                                      : '书签\n无效',
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      height: 1.1,
                                      letterSpacing: 0.1,
                                      color: isBookMarkValid(bookMark)
                                          ? AppTheme.primaryColor
                                          : Colors.red[300]),
                                ),
                              ],
                            ),
                          ),
                          onTap: () {
                            if (isBookMarkValid(bookMark)) {
                              final bookMarkUiPos = getBookMarkUiPosition();
                              if (bookMarkUiPos >= 0 &&
                                  bookMarkUiPos < words.length) {
                                // 书签在当前加载的单词范围内，直接跳转
                                jumpToBookMark();
                              } else {
                                // 书签不在当前范围内，重新加载数据到书签位置
                                clearQueryResult();
                                // 计算书签所在页的起始位置
                                baseIndex = (bookMark!.position ~/ _pageSize) *
                                    _pageSize;
                                doQuery(true, baseIndex!, _pageSize, false)
                                    .then((_) {
                                  // 滚动到书签位置，增加延迟确保UI完全更新
                                  Future.delayed(
                                      const Duration(milliseconds: 100), () {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      final newBookMarkUiPos =
                                          getBookMarkUiPosition();
                                      if (newBookMarkUiPos >= 0 &&
                                          newBookMarkUiPos < words.length) {
                                        // 直接滚动到书签位置，不使用jumpToBookMark避免位置检查
                                        itemScrollController.scrollTo(
                                            index: newBookMarkUiPos,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            alignment: 0.5);
                                      }
                                    });
                                  });
                                });
                              }
                            }
                          },
                        ),

                      /// 书签图标 - 跳到最后一个单词
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.bookmark,
                                  color: Colors.white, size: 28),
                              Text(
                                'E',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        onTap: () async {
                          setState(() {
                            clearQueryResult();
                            baseIndex = totalWordCount - 50;
                            baseIndex = baseIndex! < 0 ? 0 : baseIndex;
                            doQuery(false, baseIndex!, 50, true).then((_) {
                              // 添加这一行，确保跳转到最后一个单词
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                itemScrollController.scrollTo(
                                    index: words.length - 1,
                                    duration: const Duration(milliseconds: 300),
                                    alignment: _handwritingScrollAlignment); // 显示在屏幕偏上部
                              });
                            });
                          });
                        },
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    if (args.canAddWord && args.wordsProvider is WordModifier)
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white),
                        onPressed: _showAddWordDialog,
                      ),
                    // 使用GlobalKey包裹图标，便于计算其全局坐标
                    // 使用 GlobalKey 直挂按钮，确保 iPad Popover 锚定更准确稳定
                    // 使用 IconButton + showMenu 手动控制菜单，
                    // 以便在菜单显示期间暂停 ASR 和 UI 更新，防止 iPad Popover 闪退
                    IconButton(
                      key: _menuKey,
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        // 1. 设置标志位，屏蔽 ASR 和 Timer 对 UI 的刷新干扰
                        isMenuOpen = true; // 立即生效，屏蔽后续可能的 setState

                        // 2. 强制收起键盘并等待更长时间
                        // iPad 上键盘动画较慢，且布局变化可能导致 Overlay 重绘
                        // 给予足够的时间让这一过程完全结束
                        FocusScope.of(context).unfocus();

                        // 暂停加载动画，确保 UI 每一帧都静止
                        bool wasAnimating =
                            _asrModelLoadingController.isAnimating;
                        if (wasAnimating) {
                          _asrModelLoadingController.stop();
                        }

                        // 350ms 延时，足以覆盖大部分 iOS 键盘/过渡动画
                        final capturedContext = context;
                        await Future.delayed(const Duration(milliseconds: 350));

                        // 真正的解决 linter 警告：检查 context.mounted
                        if (!capturedContext.mounted) {
                          isMenuOpen = false;
                          return;
                        }

                        // 将 context 相关的操作移出 try 块，紧接在 mounted 检查之后
                        // 这样 linter 就能确认 context 的使用是安全的
                        final RenderBox? button = _menuKey.currentContext
                            ?.findRenderObject() as RenderBox?;

                        // 预先获取 overlayState，避免在 async gap 后使用 context
                        final BuildContext overlayContext =
                            Overlay.of(capturedContext, rootOverlay: true)
                                .context;
                        final RenderBox? overlayRenderBox =
                            overlayContext.findRenderObject() as RenderBox?;

                        if (button == null || overlayRenderBox == null) {
                          isMenuOpen = false;
                          return;
                        }

                        // 修正：确保 overlay 大小获取正确
                        final overlayRect = Offset.zero & overlayRenderBox.size;

                        final RelativeRect position = RelativeRect.fromRect(
                          Rect.fromPoints(
                            button.localToGlobal(const Offset(0, 50),
                                ancestor: overlayRenderBox), // 增加垂直偏移
                            button.localToGlobal(
                                button.size.bottomRight(Offset.zero) +
                                    const Offset(0, 50),
                                ancestor: overlayRenderBox),
                          ),
                          overlayRect,
                        );

                        try {
                          // 再次检查 mounted，确保 showMenu 调用安全 (虽然上面已经检查过，但为了满足 strict linter flow analysis)
                          if (!capturedContext.mounted) return;

                          // 4. 构建菜单项
                          List<String> menuItems = [
                            menuWordList,
                            menuWalkman,
                          ];
                          if (args.canAddWord &&
                              args.wordsProvider is WordModifier) {
                            menuItems.add(menuImportFromBook);
                            menuItems.add(menuImportFromScan);
                          }
                          if (PlatformUtils.isAsrSupported()) {
                            menuItems.add(menuSpeakChinese);
                          }
                          if (PlatformUtils.isEnglishAsrSupported()) {
                            menuItems.add(menuSpeakEnglish);
                          }
                          menuItems.add(menuWriteSpellTyping);
                          menuItems.add(menuWriteSpellHandwriting);
                          menuItems.add(menuHideChinese);
                          menuItems.add(menuHideEnglish);

                          if (args.showAiStory) {
                            menuItems.add(menuAiStory);
                          }
                          if (studyMode == WordListStudyMode.speakChinese ||
                              studyMode == WordListStudyMode.speakEnglish) {
                            menuItems.add(menuSettings);
                          }

                          // 5. 显示菜单 (使用 RootNavigator)
                          // ignore: use_build_context_synchronously
                          final String? selectedValue = await showMenu<String>(
                            context: capturedContext,
                            position: position,
                            useRootNavigator: true,
                            items: [
                              PopupMenuItem<String>(
                                enabled: false,
                                height: 32,
                                child: _buildLegendForMenu(isDarkMode),
                              ),
                              const PopupMenuDivider(height: 1),
                              ...menuItems.map((String choice) {
                              IconData icon;
                              switch (choice) {
                                case menuWordList:
                                  icon = Icons.list_alt;
                                  break;
                                case menuWalkman:
                                  icon = Icons.headphones;
                                  break;
                                case menuImportFromBook:
                                  icon = Icons.import_contacts;
                                  break;
                                case menuImportFromScan:
                                  icon = Icons.camera_alt;
                                  break;
                                case menuSpeakChinese:
                                  icon = Icons.record_voice_over;
                                  break;
                                case menuSpeakEnglish:
                                  icon = Icons.record_voice_over;
                                  break;
                                case menuWriteSpellTyping:
                                  icon = Icons.keyboard;
                                  break;
                                case menuWriteSpellHandwriting:
                                  icon = Icons.gesture;
                                  break;
                                case menuHideChinese:
                                  icon = Icons.visibility_off;
                                  break;
                                case menuHideEnglish:
                                  icon = Icons.visibility_off;
                                  break;

                                case menuAiStory:
                                  icon = Icons.auto_awesome;
                                  break;
                                case menuSettings:
                                  icon = Icons.settings;
                                  break;
                                default:
                                  icon = Icons.help_outline;
                              }

                              bool isSelected = false;
                              switch (choice) {
                                case menuWordList:
                                  isSelected =
                                      studyMode == WordListStudyMode.list;
                                  break;
                                case menuHideChinese:
                                  isSelected =
                                      studyMode == WordListStudyMode.hideChinese;
                                  break;
                                case menuHideEnglish:
                                  isSelected =
                                      studyMode == WordListStudyMode.hideEnglish;
                                  break;

                                case menuSpeakChinese:
                                  isSelected = studyMode ==
                                      WordListStudyMode.speakChinese;
                                  break;
                                case menuSpeakEnglish:
                                  isSelected = studyMode ==
                                      WordListStudyMode.speakEnglish;
                                  break;
                                case menuWriteSpellTyping:
                                  isSelected =
                                      studyMode == WordListStudyMode.dictation;
                                  break;
                                case menuWriteSpellHandwriting:
                                  isSelected =
                                      studyMode == WordListStudyMode.dictationHandwriting;
                                  break;
                                case menuImportFromBook:
                                  isSelected =
                                      false; // it does not represent a state
                                  break;
                                case menuImportFromScan:
                                  isSelected = false;
                                  break;
                                case menuAiStory:
                                  isSelected = false;
                                  break;
                                case menuSettings:
                                  isSelected = false;
                                  break;
                              }

                              return PopupMenuItem<String>(
                                value: choice,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF0097A7)
                                            .withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        icon,
                                        size: 20,
                                        color: isSelected
                                            ? const Color(0xFF0097A7)
                                            : (isDarkMode
                                                ? Colors.white
                                                : Colors.grey[700]),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        choice,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFF0097A7)
                                              : (isDarkMode
                                                  ? Colors.white
                                                  : Colors.grey[700]),
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );

                          // 6. 处理选择
                          if (selectedValue != null) {
                            switch (selectedValue) {
                              case menuWordList:
                                setState(() {
                                  studyMode = WordListStudyMode.list;
                                });
                                _unsubscribeMeter();
                                asr.stopAsr();
                                break;
                              case menuImportFromBook:
                                final needRefresh =
                                    await Get.to(() => ImportFromBookPage(
                                          wordModifier: args.wordsProvider
                                              as WordModifier,
                                        ));
                                if (needRefresh == true) {
                                  // 刷新当前页面
                                  totalWordCount = -1;
                                  baseIndex ??= 0;
                                  await doQuery(
                                      true, baseIndex!, _pageSize, false);
                                  setState(() {});
                                }
                                break;
                              case menuImportFromScan:
                                final needRefresh =
                                    await Get.to(() => ImportFromScanPage(
                                          wordModifier: args.wordsProvider
                                              as WordModifier,
                                        ));
                                if (needRefresh == true) {
                                  // 刷新当前页面
                                  totalWordCount = -1;
                                  baseIndex ??= 0;
                                  await doQuery(
                                      true, baseIndex!, _pageSize, false);
                                  setState(() {});
                                }
                                break;
                              case menuWriteSpellTyping:
                                if (studyMode != WordListStudyMode.dictation) {
                                  setState(() {
                                    studyMode = WordListStudyMode.dictation;
                                    for (final w in words) {
                                      w.spellController.text = '';
                                      w.isAnswerProvidedBySystem = false;
                                      w.hintLetterCount = 0;
                                    }
                                  });
                                  _unsubscribeMeter();
                                  asr.stopAsr();
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark();
                                });
                                break;
                              case menuWriteSpellHandwriting:
                                final swOpen = Stopwatch()..start();
                                // 如果已经是在手写模式下再次点击，则不执行重复初始化逻辑
                                if (studyMode == WordListStudyMode.dictationHandwriting && _isHandwritingOverlayOpen) {
                                  _handwritingBoardKey.currentState?.clearBoardSilently();
                                } else {
                                  Global.openPencilStopwatch.reset();
                                  Global.openPencilStopwatch.start();
                                  Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [进入听写手写模式] 开始处理...');
                                  WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
                                  setState(() {
                                    studyMode = WordListStudyMode.dictationHandwriting;
                                    _isHandwritingOverlayOpen = true;
                                    for (final w in words) {
                                      w.spellController.clear();
                                      w.hintLetterCount = 0;
                                      w.isAnswerProvidedBySystem = false;
                                    }
                                    _detectedSimilarWord = null;
                                    asrResult = "";
                                    handlingAsrChinese = "";
                                  });
                                }
                                // 滚动当前单词到可视区域（偏上位置）
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (itemScrollController.isAttached) {
                                    final activeIdx = getBookMarkUiPosition();
                                    if (activeIdx >= 0) {
                                      itemScrollController.scrollTo(
                                        index: activeIdx,
                                        duration: const Duration(milliseconds: 300),
                                        alignment: _handwritingScrollAlignment,
                                      );
                                    }
                                  }
                                });
                                Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [1. 状态变更与 setState] 耗时: ${swOpen.elapsedMilliseconds}ms');
                                _unsubscribeMeter();
                                asr.stopAsr();
                                swOpen.stop();
                                Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [2. 彻底退出事件体] 耗时: ${swOpen.elapsedMilliseconds}ms');
                                break;
                              case menuHideChinese:
                                setState(() {
                                  studyMode = WordListStudyMode.hideChinese;
                                  for (final w in words) {
                                    w.isAnswerRevealed = false;
                                  }
                                });
                                _unsubscribeMeter();
                                asr.stopAsr();
                                break;
                              case menuHideEnglish:
                                setState(() {
                                  studyMode = WordListStudyMode.hideEnglish;
                                  for (final w in words) {
                                    w.isAnswerRevealed = false;
                                  }
                                });
                                _unsubscribeMeter();
                                asr.stopAsr();
                                break;

                              case menuSpeakChinese:
                                if (studyMode != WordListStudyMode.speakChinese) {
                                  asr.stopAsr();
                                  asr.reset();
                                  setState(() {
                                    clearWordStates();
                                    asrResult = "";
                                    handlingAsrChinese = "";
                                    studyMode = WordListStudyMode.speakChinese;
                                  });
                                  _startAsr(decideAsrLanguage());
                                  _subscribeMeterIfNeeded();
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark();
                                });
                                break;
                              case menuSpeakEnglish:
                                if (studyMode != WordListStudyMode.speakEnglish) {
                                  asr.stopAsr();
                                  asr.reset();
                                  setState(() {
                                    clearWordStates();
                                    asrResult = "";
                                    handlingAsrChinese = "";
                                    studyMode = WordListStudyMode.speakEnglish;
                                  });
                                  _startAsr(decideAsrLanguage());
                                  _subscribeMeterIfNeeded();
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark();
                                });
                                break;
                                case menuWalkman:
                                  if (studyMode ==
                                          WordListStudyMode.speakChinese ||
                                      studyMode ==
                                          WordListStudyMode.speakEnglish) {
                                    asr.stopAsr();
                                    asr.reset();
                                  }
                                  Get.toNamed('/walkman',
                                      arguments:
                                          WalkmanParams(args.wordsProvider));
                                  break;
                                case menuAiStory:
                                  _generateAiStory();
                                  break;
                                case menuSettings:
                                  _showSettingsDialog();
                                  break;
                              }
                          }
                        } finally {
                          // 7. 恢复标志位
                          isMenuOpen = false;
                          if (wasAnimating && mounted) {
                            _asrModelLoadingController.repeat(reverse: true);
                          }
                        }
                      },
                    ),
                  ],
                ),
          body: SafeArea(
            bottom: false, // 不使用底部安全区域，充分利用屏幕
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDarkMode
                          ? [
                              const Color(0xFF121212),
                              const Color(0xFF1A1A1A),
                              const Color(0xFF121212),
                            ]
                          : [
                              const Color(0xFFF9FAFB),
                              const Color(0xFFF5F7FA),
                              const Color(0xFFF9FAFB),
                            ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: (!dataLoaded || !_showList)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF0097A7),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '正在整理词单...',
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF2C3E50),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(
                              leftPadding, 2, rightPadding, 0),
                          child: renderPage(),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: null,
        ),
        // 新手引导覆盖层 - 在Scaffold之上，覆盖整个屏幕包括AppBar
        if (showGuide) _buildGuideOverlay(),
        if (studyMode == WordListStudyMode.dictationHandwriting && _isHandwritingOverlayOpen)
          _buildHandwritingOverlay(isDarkMode),
      ],
      ),
    );

    swBuild.stop();
    Global.logger.d('PERF_LOG_PENCIL [页面 build 完毕] 耗时: ${swBuild.elapsedMilliseconds}ms, 累计调用 renderWord 次数: $_renderWordCallCount');
    return popScopeWidget;
  }

  /// 构建新手引导覆盖层
  Widget _buildGuideOverlay() {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final safePadding = MediaQuery.of(context).padding;

    final double defaultTop = safePadding.top + kToolbarHeight + 8;

    // 覆盖层现在在Stack顶层，和AppBar同一坐标系，直接使用全局坐标
    final double appBarTotalHeight = safePadding.top + kToolbarHeight;

    // 箭头组件的顶部位置：让箭头尖端对齐到图标底部
    // PopupMenuButton的Container高56px，实际图标约24px在中心，所以图标底部约在中心+12
    final double columnTop = _menuRect != null
        ? _menuRect!.center.dy + 12 // 直接使用全局坐标，不需要转换
        : defaultTop;

    // 箭头长度：固定值
    const double arrowHeight = 30.0;

    Global.logger.d('构建引导覆盖层详细信息:');
    Global.logger.d('  _menuRect: $_menuRect');
    Global.logger.d('  图标顶部: ${_menuRect?.top}');
    Global.logger.d('  图标底部: ${_menuRect?.bottom}');
    Global.logger.d('  图标中心: ${_menuRect?.center}');
    Global.logger.d('  safePadding.top: ${safePadding.top}');
    Global.logger.d('  kToolbarHeight: $kToolbarHeight');
    Global.logger.d('  appBarTotalHeight: $appBarTotalHeight');
    Global.logger.d('  columnTop (箭头Y in body): $columnTop');
    Global.logger.d('  屏幕宽度: $screenWidth');

    return GestureDetector(
      onTap: () {
        // 点击遮罩层只关闭，不标记为已显示
        _closeGuide();
      },
      child: Container(
        key: _overlayKey,
        color: Colors.black.withValues(alpha: 0.7),
        child: Stack(
          children: [
            // 箭头 - 单独定位
            Positioned(
              top: columnTop,
              left: _menuRect != null ? _menuRect!.center.dx - 1.5 : null,
              right: _menuRect == null ? 24.0 : null,
              child: CustomPaint(
                size: const Size(3, arrowHeight),
                painter: _ArrowPainter(isDarkMode),
              ),
            ),
            // 提示气泡 - 单独定位
            Positioned(
              top: columnTop + arrowHeight + 2,
              right: 16.0,
              child: GestureDetector(
                onTap: () {
                  // 阻止事件冒泡，避免点击气泡内容时关闭
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.gradientStartColor,
                        AppTheme.gradientEndColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lightbulb,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '新手提示',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              decoration: TextDecoration.none,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '这里有一些有趣的功能，你可以试试看:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildMenuItem(Icons.list_alt, '词表浏览'),
                      _buildMenuItem(Icons.headphones, '随身听'),
                      // 根据平台支持情况动态显示功能
                      if (PlatformUtils.isAsrSupported())
                        _buildMenuItem(Icons.record_voice_over, '背中文'),
                      if (PlatformUtils.isEnglishAsrSupported())
                        _buildMenuItem(Icons.record_voice_over, '背英文'),
                      _buildMenuItem(Icons.edit, '默写'),
                      const SizedBox(height: 16),
                      // 不再显示按钮
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            // 点击按钮标记为不再显示
                            _dismissGuideForever();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            '不再显示',
                            style: TextStyle(
                              fontSize: 14,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    isMenuOpen = true;
    try {
      FocusScope.of(context).unfocus();
      bool wasAnimating = _asrModelLoadingController.isAnimating;
      if (wasAnimating) {
        _asrModelLoadingController.stop();
      }
      final capturedContext = context;
      await Future.delayed(const Duration(milliseconds: 350));
      if (!capturedContext.mounted) return;

      final isDarkMode = capturedContext.read<DarkMode>().isDarkMode;

      await showDialog(
        context: capturedContext,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return AlertDialog(
                backgroundColor:
                    isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(
                  studyMode == WordListStudyMode.speakEnglish
                      ? '背英文模式设置'
                      : '背中文模式设置',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                content: DefaultTextStyle.merge(
                  style: const TextStyle(
                      fontSize: 13.0, fontWeight: FontWeight.w400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (studyMode == WordListStudyMode.speakChinese ||
                          studyMode == WordListStudyMode.speakEnglish)
                        _buildAsrPassRuleSelector(
                          isDarkMode,
                          asrPassRule,
                          (value) async {
                            await GetStorage()
                                .write('wordListAsrPassRule', value);
                            setState(() {});
                            setDialogState(() {});
                          },
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      '关闭',
                      style: TextStyle(
                        color: Color(0xFF4A90E2),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      isMenuOpen = false;
    }
  }

  Widget _buildAsrPassRuleSelector(
      bool isDarkMode, String currentValue, Function(String) onChanged) {
    const Map<String, String> options = {
      'ONE': '说出一个意思即可',
      'HALF': '说出半数意思',
      'ALL': '说出全部意思',
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Text(
          '语音识别通过规则',
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.grey[700],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          options[currentValue] ?? '说出一个意思即可',
          style: TextStyle(
            color: isDarkMode ? Colors.white54 : Colors.grey[500],
            fontSize: 12,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.arrow_drop_down_circle_outlined,
            color: isDarkMode ? Colors.white54 : Colors.grey[600],
          ),
          onSelected: onChanged,
          itemBuilder: (BuildContext context) {
            return options.entries.map((entry) {
              return PopupMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  void _generateAiStory() async {
    if (words.isEmpty) {
      ToastUtil.error('列表中没有单词');
      return;
    }

    if (_aiStory != null) {
      _showAiStoryDialog(_aiStory!);
      return;
    }

    try {
      // 准备单词列表 JSON
      final wordSpells = words.map((w) => w.word.spell).toList();
      final wordsJson = jsonEncode(wordSpells);

      // 显示加载中
      Api.setLoadingDisabled(false);
      final result = await Api.client.generateAiShortStory(wordsJson, Global.currentUserId!);

      if (result.success) {
        _aiStory = result.data;
        _showAiStoryDialog(_aiStory!);
      } else {
        ToastUtil.error(result.msg ?? '生成 AI 短文失败');
      }
    } catch (e) {
      Global.logger.e('生成 AI 短文异常', error: e);
      ToastUtil.error('生成异常: $e');
    }
  }

  void _showAiStoryDialog(String story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppTheme.createGradientAppBar(
            title: 'AI 单词小短文',
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '复制',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: story));
                  ToastUtil.info('已复制到剪贴板');
                },
              ),
            ],
          ),
          body: Container(
            color: Theme.of(context).scaffoldBackgroundColor, // 为背景提供清晰颜色，避免透视
            child: _buildClickableStory(story),
          ),
        ),
      ),
    );
  }

  Widget _buildClickableStory(String story) {
    // 预处理：将 **word** 替换为 <b>word</b>
    String processedStory =
        story.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (match) {
      return '<b>${match.group(1)}</b>';
    });

    List<String> paragraphs = processedStory.split('\n');
    List<Widget> widgets = [];

    for (var p in paragraphs) {
      if (p.trim().isEmpty) {
        // 空行作为段落间隔
        widgets.add(const SizedBox(height: 16));
        continue;
      }

      // 判断是否是中文（含有汉字），用于判断是故事还是翻译，或者标题
      bool hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(p);

      if (hasChinese) {
        // 中文部分（翻译或引导句）
        widgets.add(Util.makeChineseSpanText(p, context,
            style: const TextStyle(fontSize: 17, height: 1.6)));
      } else {
        // 英文部分（故事正文)
        widgets.add(Util.makeEnglishSpanText(
          p,
          '', // highlightWord
          true, // highlightWordHasBeenTaged
          context,
          false, // maskHighlightWord
          null, // maskTextField
          false, // isHighlightWordUnClickable
          FontWeight.w400,
          fontSize: 17, // 设置与全屏匹配的字体大小
        ));
      }
      widgets.add(const SizedBox(height: 12));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }


  Widget _buildHandwritingOverlay(bool isDarkMode) {
    final swOverlay = Stopwatch()..start();
    Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [_buildHandwritingOverlay 开始构造]');
    final double appBarHeight = MediaQuery.of(context).padding.top + kToolbarHeight;
    
    final bookmarkedIndex = getBookMarkUiPosition();
    WordWrapper? activeWord;
    if (bookmarkedIndex >= 0 && bookmarkedIndex < words.length) {
      activeWord = words[bookmarkedIndex];
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      swOverlay.stop();
      Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [_buildHandwritingOverlay 组件渲染挂载完毕] 耗时: ${swOverlay.elapsedMilliseconds}ms');
      if (Global.openPencilStopwatch.isRunning) {
        Global.openPencilStopwatch.stop();
        Global.logger.d('🔥 [超级大盘点] 从菜单点击到手写物理像素上屏，用户肉眼经历的真实总耗时：${Global.openPencilStopwatch.elapsedMilliseconds}ms');
      }
    });

    return Positioned(
      top: appBarHeight,
      left: 0,
      right: 0, // 占满全宽
      bottom: 0,
      child: Stack(
        children: [
          // 1. 左侧手写画板区域
          Positioned(
            left: 0,
            right: _handwritingRightPadding,
            top: 0,
            bottom: 0,
            child: Container(
              color: Colors.transparent,
              child: HandwritingBoard(
                key: _handwritingBoardKey,
                showHeader: false,
                showCloseButton: false, 
                useBoxDecoration: false,
                showCanvasButtons: true, 
                enableNavigationGestures: false,
                smartRightZoneWidth: 0, 
                rightZoneVisibleNotifier: _rightZoneVisible, 
                onHint: () {
                  if (activeWord != null) {
                    giveALittleHint(activeWord);
                  }
                },
                onUndo: () => _clearHandwritingHints(activeWord),
                onRewrite: () => _clearHandwritingHints(activeWord),
                onStartWriting: () {
                  _handwritingPaddingTimer?.cancel();
                  _clearHandwritingHints(activeWord);
                  if (_handwritingRightPadding != 0) {
                    setState(() {
                      _handwritingRightPadding = 0;
                    });
                  }
                },
                onPointerUp: () {
                  _handwritingPaddingTimer?.cancel();
                  _handwritingPaddingTimer = Timer(const Duration(milliseconds: 500), () {
                    if (mounted && _handwritingRightPadding != 60) {
                      setState(() {
                        _handwritingRightPadding = 60;
                      });
                    }
                  });
                },
                onRecognized: (text) async {
                  final targetWord = activeWord;
                  if (targetWord != null) { 
                    // 智能容错：处理 Google ML Kit 经常将手写 c/l 识别为 d 的物理误判
                    // 智能容错：终极 NLP 锚点距离感知算法 (USER 构想之神级实现)
                    String processedText = "";
                    final String lowerTarget = targetWord.word.spell.toLowerCase();
                    
                    // 1. 提取正确单词中所有 D、CL 的【物理锚点序列】
                    List<Map<String, dynamic>> anchors = [];
                    for (int i = 0; i < lowerTarget.length; i++) {
                      if (lowerTarget[i] == 'd') {
                        anchors.add({'idx': i, 'type': 'd'});
                      } else if (lowerTarget[i] == 'c' && (i + 1) < lowerTarget.length && lowerTarget[i + 1] == 'l') {
                        anchors.add({'idx': i, 'type': 'cl'});
                      }
                    }
                    
                    // 2. 遍历用户输入的 text，基于“物理距离最近”判定真伪
                    for (int idx = 0; idx < text.length; idx++) {
                      final iChar = text[idx].toLowerCase();
                      if ((iChar == 'd' || iChar == 'c') && anchors.isNotEmpty) {
                        Map<String, dynamic> nearestAnchor = anchors[0];
                        int minDistance = (idx - (anchors[0]['idx'] as int)).abs();
                        
                        for (final anchor in anchors) {
                          final int dist = (idx - (anchor['idx'] as int)).abs();
                          // 如果在同样的距离内发现类型匹配的锚点，优先选择匹配的类型，防止“误纠正”
                          if (dist < minDistance || (dist == minDistance && anchor['type'] == iChar)) {
                            minDistance = dist;
                            nearestAnchor = anchor;
                          }
                        }
                        
                        // D 与 CL 连写容错
                        if (iChar == 'd' && nearestAnchor['type'] == 'cl') {
                          processedText += (text[idx] == 'D') ? 'CL' : 'cl';
                          continue;
                        }
                      }
                      processedText += text[idx];
                    }
                    
                    setState(() {
                      targetWord.spellController.text = processedText;
                    });
                    
                    // 模糊匹配逻辑：忽略非英文字符（如空格、连字符、点等），提升手写容错率
                    final String normalizedTarget = targetWord.word.spell.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
                    final String normalizedInput = processedText.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
                    
                    // 超级模糊容错：如果单词本就既包含 D 又包含 CL (如 disclose)，后台自动为 'd' 视为 'cl' 的笔画放行
                    final String fuzzyTarget = normalizedTarget.replaceAll('cl', 'd');
                    
                    if (normalizedTarget == normalizedInput || fuzzyTarget == normalizedInput) {
                       setState(() {
                         _detectedSimilarWord = null;
                       });
                       WidgetsBinding.instance.addPostFrameCallback((_) async {
                         // 写对了，播放当前单词（揭晓答案/确认）
                         try {
                           await SoundUtil.playPronounceSound2(targetWord.word, audioPlayer);
                         } catch (_) {}
                         
                         _handwritingBoardKey.currentState?.clearBoardSilently();
                         jumpToNextWord(bookmarkedIndex, false, () {});
                       });
                    } else if (normalizedInput.length >= 2) {
                       // 如果输入不正确，但输入长度大于2，则尝试查词看是不是写成了别的合法单词
                       final result = await WordBo().searchWordLocalOnly(normalizedInput);
                       if (result.word != null && result.word!.spell.toLowerCase() == normalizedInput) {
                         if (mounted) {
                           setState(() {
                             _detectedSimilarWord = result.word;
                           });
                         }
                       } else {
                         if (mounted) {
                           setState(() {
                             _detectedSimilarWord = null;
                           });
                         }
                       }
                    } else {
                       if (mounted) {
                         setState(() {
                           _detectedSimilarWord = null;
                         });
                       }
                    }
                  }
                },
                onSwipeUp: () async {
                  _handwritingBoardKey.currentState?.clearBoardSilently();
                  // 揭晓答案：离开当前词时播放
                  if (bookmarkedIndex >= 0 && bookmarkedIndex < words.length) {
                    try {
                      await SoundUtil.playPronounceSound2(words[bookmarkedIndex].word, audioPlayer);
                    } catch (_) {}
                  }
                  jumpToNextWord(bookmarkedIndex, false, () {});
                },
                onSwipeDown: () async {
                  _handwritingBoardKey.currentState?.clearBoardSilently();
                  // 揭晓答案：离开当前词时播放
                  if (bookmarkedIndex >= 0 && bookmarkedIndex < words.length) {
                    try {
                      await SoundUtil.playPronounceSound2(words[bookmarkedIndex].word, audioPlayer);
                    } catch (_) {}
                  }
                  jumpToPreviousWord(bookmarkedIndex, false);
                },
                onCancel: () {
                  setState(() {
                    _isHandwritingOverlayOpen = false;
                  });
                },
              ),
            ),
          ),

          // 2. 相似词提示框
          if (_detectedSimilarWord != null)
            Positioned(
              left: 12,
              right: 12 + _handwritingRightPadding,
              top: 10,
              child: GestureDetector(
                onTap: () {
                  Get.to(() => const WordDetailPage(),
                      arguments: WordDetailPageArgs(_detectedSimilarWord!, true, null, false));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '注意，你写成了另一个单词: ${_detectedSimilarWord!.spell}',
                              style: const TextStyle(
                                color: Colors.orangeAccent, 
                                fontSize: 13, 
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 12),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Text(
                          _detectedSimilarWord!.getMeaningStr().replaceAll('\n', ' '),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9), 
                            fontSize: 12,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            right: _handwritingRightPadding > 0 ? _handwritingRightPadding - 1 : -1,
            top: 0,
            bottom: 0,
            width: 1,
            child: IgnorePointer(
              child: Container(
                color: isDarkMode 
                    ? Colors.white.withValues(alpha: 0.06) 
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),

        ],
      ),
    );
  }
}

/// 箭头绘制器 - 简单的向上箭头，从气泡指向菜单按钮
class _ArrowPainter extends CustomPainter {
  final bool isDarkMode;

  _ArrowPainter(this.isDarkMode);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 绘制垂直向上的线
    canvas.drawLine(
      Offset(size.width / 2, size.height),
      Offset(size.width / 2, 0),
      paint,
    );

    // 绘制箭头头部（指向上方）
    // 左侧线
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2 - 8, 10),
      paint,
    );

    // 右侧线
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2 + 8, 10),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
