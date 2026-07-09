import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nnbdc/util/pdf_exporter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/ocr_service.dart';
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
import '../../util/word_util.dart';
import '../index.dart';
import '../walkman.dart';
import '../word_detail.dart';
import 'dict_words.dart';
import 'edit_meaning_dialog.dart';
import 'word_list_actions.dart';
import 'modes/list_mode_item.dart';
import 'modes/speak_mode_item.dart';
import 'modes/typing_mode_item.dart';
import 'modes/handwriting_mode_item.dart';
import 'modes/hide_mode_item.dart';
import 'word_list_controller.dart';
import 'word_list_asr_controller.dart';
import 'widgets/handwriting_overlay.dart';
import 'widgets/guide_overlay.dart';

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
const String menuSortSettings = '排序设置';
const String menuExportPdf = '导出为 PDF';



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
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return {};
    return await WordBo.getWordsLearningStatusBatch(userId, wordIds);
  }

  /// 当单词被标记为“掌握”时，是否保留在当前UI列表中（不自动移除）
  bool get keepWordsOnMaster => false;

  /// 获取当前词表数据源的排序规则
  Future<WordSortAlg> getSortAlg() async {
    return WordSortAlg.original;
  }

  /// 保存当前词表数据源的排序规则
  Future<void> saveSortAlg(WordSortAlg alg) async {}

  /// 该数据源是否包含分单元的数据（用于判断是否展示单元序）
  Future<bool> get hasUnits async => false;
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
        AutomaticKeepAliveClientMixin,
        WordListActionHandler {
  @override
  void onWordTap(WordWrapper word, int index) => _handleWordTap(word, index);

  @override
  void onWordLongPress(WordWrapper word, int index) =>
      _handleWordLongPress(word, index);

  @override
  void onEditBtnPressed(WordWrapper word, int index) =>
      _showEditMeaningDialog(word);

  @override
  void onResetHint(WordWrapper word) => clearHint(word);

  @override
  void onGiveHint(WordWrapper word) => giveALittleHint(word);

  @override
  void onToggleAnswer(WordWrapper word, int index) {
    setState(() {
      word.isAnswerRevealed = !word.isAnswerRevealed;
    });

    if (word.isAnswerRevealed && studyMode == WordListStudyMode.hideEnglish) {
      unawaited(_sessionController.playWordSound(word.word));
    }

    if (getBookMarkUiPosition() != index) {
      onWordPressed(word, index, true, null);
    }
  }

  @override
  void onHandwritingPressed(WordWrapper word, int index) {
    setState(() {
      _isHandwritingOverlayOpen = true;
    });
    onWordPressed(word, index, false, null);
    _handwritingBoardKey.currentState?.clearBoardSilently();
  }

  @override
  void onSpellChanged(WordWrapper word, int index, String value) {
    // 先刷新UI，使颜色立即变绿/红
    setState(() {});
    // 如果拼写正确：执行后续动作（onWordPressed 会负责播放离开单词发音+跳转）
    if (Util.equalsIgnoreCase(word.word.spell, value)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        jumpToNextWord(index, false, () {});
      });
    }
  }
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

  var studyMode = WordListStudyMode.hideChinese;
  bool _isHandwritingOverlayOpen = true;
  bool _isSwitchingMode = false;
  String _switchingMessage = '模式切换中...';
  int? _tempHandwritingSelectedIndex;
  final GlobalKey<HandwritingBoardState> _handwritingBoardKey = GlobalKey<HandwritingBoardState>();
  int _renderWordCallCount = 0;
  final ValueNotifier<int> activeWordIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<bool> _rightZoneVisible = ValueNotifier<bool>(true);

  /// 语音识别通过规则：'ONE' (说出一个), 'HALF' (说出半数), 'ALL' (说出全部)
  String get asrPassRule => Prefs.read<String>('wordListAsrPassRule') ?? 'ONE';

  late WordListPageArgs args;

  /// 是否可以离开当前单词（用户回答正确的释义数量达到要求）
  bool canLeaveCurrWord = false;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  Offset floatBtnPosition = const Offset(20.0, 20.0);
  bool _controllerInitialized = false;

  late final WordListController controller;
  late final WordListAsrController asrController;
  late final StudyAudioSessionController _sessionController;

  // ASR模型加载状态与动画控制器
  late AnimationController _asrModelLoadingController;
  late AnimationController _glowController;

  /// 是否显示新手引导
  bool showGuide = false;

  /// 菜单是否打开（用于控制iPad上的弹出菜单稳定性）
  bool isMenuOpen = false;

  // 映射属性到控制器以保持原逻辑引用正常
  bool get dataLoaded => _controllerInitialized ? controller.dataLoaded : false;
  set dataLoaded(bool val) { if (_controllerInitialized) controller.dataLoaded = val; }

  int get totalWordCount => _controllerInitialized ? controller.totalWordCount : -1;
  set totalWordCount(int val) { if (_controllerInitialized) controller.totalWordCount = val; }

  int? get baseIndex => _controllerInitialized ? controller.baseIndex : null;
  set baseIndex(int? val) { if (_controllerInitialized) controller.baseIndex = val; }

  List<WordWrapper> get words => _controllerInitialized ? controller.words : const [];
  set words(List<WordWrapper> val) { if (_controllerInitialized) controller.words = val; }

  AiStoryVo? get _aiStory => _controllerInitialized ? controller.aiStory : null;
  set _aiStory(AiStoryVo? val) { if (_controllerInitialized) controller.aiStory = val; }

  BookMarkVo? get bookMark => _controllerInitialized ? controller.bookMark : null;
  set bookMark(BookMarkVo? val) { if (_controllerInitialized) controller.bookMark = val; }

  set _lastExtentAfter(double val) { if (_controllerInitialized) controller.lastExtentAfter = val; }

  bool get isQuerying => _controllerInitialized ? controller.isQuerying : false;
  set isQuerying(bool val) { if (_controllerInitialized) controller.isQuerying = val; }

  DateTime? get lastQueryTime => _controllerInitialized ? controller.lastQueryTime : null;
  set lastQueryTime(DateTime? val) { if (_controllerInitialized) controller.lastQueryTime = val; }

  bool get doNotQueryPlease => _controllerInitialized ? controller.doNotQueryPlease : false;
  set doNotQueryPlease(bool val) { if (_controllerInitialized) controller.doNotQueryPlease = val; }

  int? get _initialScrollIndex => _controllerInitialized ? controller.initialScrollIndex : null;

  Asr get asr => asrController.asr;

  String get asrResult => asrController.asrResult;
  set asrResult(String val) { asrController.asrResult = val; }

  String get handlingAsrChinese => asrController.handlingAsrChinese;
  set handlingAsrChinese(String val) { asrController.handlingAsrChinese = val; }

  bool get _isAsrModelLoading => asrController.isAsrModelLoading;
  set _isAsrModelLoading(bool val) { asrController.isAsrModelLoading = val; }

  bool get _isAsrProcessing => asrController.isAsrProcessing;
  set _isAsrProcessing(bool val) { asrController.isAsrProcessing = val; }

  AsrLanguage? get _lastAsrLanguage => asrController.lastAsrLanguage;
  set _lastAsrLanguage(AsrLanguage? val) { asrController.lastAsrLanguage = val; }

  List<double> get _waveLevels => asrController.waveLevels;
  ValueNotifier<double> get _meterLevelNotifier => asrController.meterLevelNotifier;

  set _detectedSimilarWord(WordVo? val) { asrController.detectedSimilarWord = val; }

  @override
  bool get wantKeepAlive => true; // 保持状态，避免页面重建

  /// 用于获取右上角菜单按钮的坐标
  final GlobalKey _menuKey = GlobalKey();
  OverlayEntry? _guideOverlay;
  Rect? _menuRect;
  final GlobalKey _overlayKey = GlobalKey();

  void clearQueryResult() {
    if (_controllerInitialized) {
      controller.clearQueryResult();
    }
  }

  Future<void> doQuery(bool clearCurrent, int fromIndex, final int pageSize,
      bool jumpToTailWhenReady, {bool force = false}) async {
    if (_controllerInitialized) {
      await controller.doQuery(clearCurrent, fromIndex, pageSize, jumpToTailWhenReady, force: force);
    }
  }

  void jumpToBookMark({bool force = false}) {
    if (_controllerInitialized) {
      controller.jumpToBookMark(force: force);
    }
  }

  scrollToWord(int wordUiIndex) {
    if (_controllerInitialized) {
      controller.scrollToWord(wordUiIndex);
    }
  }

  int getBookMarkUiPosition() {
    if (!_controllerInitialized) return -1;
    return controller.getBookMarkUiPosition();
  }

  int getFirstVisibleListItem() {
    if (!_controllerInitialized) return -1;
    return controller.getFirstVisibleListItem();
  }

  int getLastVisibleListItem() {
    if (!_controllerInitialized) return -1;
    return controller.getLastVisibleListItem();
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





  @override
  void initState() {
    final sw = Stopwatch()..start();
    super.initState();
    // 异步预加载音素字典，避免用户说话时才开始解析导致的延迟
    unawaited(PhonemeUtil.load());
    // 异步加载并预热手写识别模型，避免进入手写板写完第一笔后产生延迟
    OcrService.prepareModel();
    _asrModelLoadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);

    _sessionController = StudyAudioSessionController();
    asrController = WordListAsrController();
    asrController.asr.addStateListener((state) {
      if (!mounted) return;
      setState(() {});
    });

    Global.logger.d('WordListPage: initState completed in ${sw.elapsedMilliseconds}ms');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!dataLoaded) {
      _initAndLoadData();
    }
  }

  Future<void> _initAndLoadData() async {
    if (!await checkArgs()) return;
    if (_controllerInitialized) return;
    
    controller = WordListController(
      args: args,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      sessionController: _sessionController,
    );
    _controllerInitialized = true;
    
    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    asrController.asr.initAsr(_unifiedOnAsrResult);

    await controller.loadData(
      checkAndShowGuide: _checkAndShowGuide,
      restoreAsrIfNeeded: (caller) {
        _restoreAsrIfNeeded(caller);
      },
    );
  }

  /// 检查并显示新手引导
  Future<void> _checkAndShowGuide() async {
    try {
      final cacheKey = 'wordListGuideShown_${Global.currentUserId}';

      // 优先从缓存读取，极快
      bool hasShown = Prefs.read<bool>(cacheKey) ?? false;

      if (!hasShown) {
        // 只有缓存没有时才查数据库
        hasShown = await MyDatabase.instance.localParamsDao.getWordListGuideShown();
        if (hasShown) {
          Prefs.write(cacheKey, true);
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
                Global.logger.w('未能获取菜单按钮位置');
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
      Prefs.write('wordListGuideShown_${Global.currentUserId}', true);
    } catch (e) {
      Global.logger.e('关闭新手引导失败: $e');
    }
  }

  void _unifiedOnAsrResult(dynamic event) {
    if (!mounted) return;
    if (isMenuOpen || showGuide) return;
    
    final bookmarkedIndex = getBookMarkUiPosition();
    final targetWord = (bookmarkedIndex >= 0 && bookmarkedIndex < words.length)
        ? words[bookmarkedIndex]
        : null;
    final targetSpell = targetWord?.word.spell ?? "";

    asrController.onAsrResult(
      event,
      studyMode: studyMode,
      targetSpell: targetSpell,
      activeWord: targetWord,
      onMatchChecked: (matchedResult) {
        checkAsrResult(matchedResult);
      },
    );
  }

  /// 检查语音识别结果是否匹配单词的意思
  checkAsrResult(String asrResult) async {
    Global.logger.d("~~~~~开始检查识别结果: $asrResult");

    final currWordIndex = getBookMarkUiPosition();
    if (currWordIndex == -1 || currWordIndex >= words.length) return;

    // 记录开始检查时的单词ID
    final checkWordId = words[currWordIndex].word.id;

    if (asr.state != AsrState.started) {
      return;
    }

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
            // 答对时，使用 stopAsr 进行热停止以维持麦克风保温状态，完全消除高频物理切流延迟与设备假死
            await _sessionController.stopSession(forceStopMicrophone: false).timeout(
              const Duration(milliseconds: 500),
              onTimeout: () {
                Global.logger.w('停止ASR超时，继续播放单词发音');
              },
            );
          } catch (e) {
            Global.logger.d("停止ASR失败: $e");
          }
          
          try {
            await _sessionController.playWordSound(words[currWordIndex].word);
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

        final swJump = Stopwatch()..start();
        debugPrint('⏱️ [Latency] 答对！开始跳转流程...');
        // 立即重置标志位，防止重复跳转 (防抖)
        canLeaveCurrWord = false;

        try {
          // 跳转前，使用 stopAsr 进行热停止以维持麦克风保温状态，消除高频冷启动重构与设备假死
          await _sessionController.stopSession(forceStopMicrophone: false);
          debugPrint('⏱️ [Latency] stopAsr 完成: +${swJump.elapsedMilliseconds}ms');
        } catch (e) {
          Global.logger.d("停止ASR失败: $e");
        }

        var nextWordIndex = currWordIndex + 1;
        while (nextWordIndex < words.length) {
          if (!words[nextWordIndex].answeredAllMeanings) {
            break;
          }
          nextWordIndex += 1;
        }

        // 检查是否全部答对
        bool allFinished = words.every((w) => w.answeredAllMeanings);
        if (allFinished) {
          ToastUtil.info("恭喜，你答对了所有单词");
          return;
        }

        // 如果在当前词之后没有未答词了，由于不要向上找，我们就不继续向下跳
        if (nextWordIndex == words.length) {
          debugPrint('⏱️ [ASR] 当前词之后已无未答词，由于不环回机制，停止跳转');
          return;
        }

        debugPrint('跳转到下一个单词：$nextWordIndex');
        jumpToNextWord(nextWordIndex - 1, true, () {
          asrResult = "";
          handlingAsrChinese = "";
          // _startAsr 由 onWordPressed 统一调用，此处不再重复触发
        });
      }
    } catch (e) {
      Global.logger.e("检查语音识别结果时出错: $e");
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

  Future<bool> checkArgs() async {
    final sw = Stopwatch()..start();
    final extra = GoRouterState.of(context).extra;
    final routerMs = sw.elapsedMilliseconds;
    sw.reset();
    if (extra == null) {
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        // 延迟到下一个tick执行，避免导航冲突
        context.go('/index', extra: IndexPageArgs(4));
      });
      return false;
    }
    args = extra as WordListPageArgs;
    
    int dbMs = 0;
    // 移除冗余的数据库查询，直接信任参数。如果参数缺失，才进行兜底检查。
    if (args.canEditWord == false && args.wordsProvider is WordModifier) {
      final swDb = Stopwatch()..start();
      final String? targetDictId = (args.wordsProvider as WordModifier).targetDictId;
      if (targetDictId != null) {
        final dict = await WordBo().getDict(targetDictId);
        if (dict != null && dict.editable) {
          args.canEditWord = true;
          args.showDelBtn = true;
          args.canAddWord = true;
        }
      }
      dbMs = swDb.elapsedMilliseconds;
    }
    Global.logger.d('WordListPage: checkArgs inner breakdown (routerMs=${routerMs}ms, dbMs=${dbMs}ms)');
    return true;
  }

  @override
  void dispose() {
    final sw = Stopwatch()..start();
    WidgetsBinding.instance.removeObserver(this);

    // 停止 ASR：不再检查 studyMode，只要页面销毁就无条件尝试停止识别引擎并转换状态机到 idle
    // 平滑物理淡出所有活跃音频流并物理释放硬件资源，防止麦克风占用指示灯常亮
    try {
      unawaited(_sessionController.stopSession(forceStopMicrophone: true));
    } catch (e) {
      Global.logger.d("dispose: 停止 ASR 失败：$e");
    }

    _asrModelLoadingController.dispose();
    _glowController.dispose();
    controller.dispose();
    asrController.dispose();

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
      _sessionController.stopSession(forceStopMicrophone: true);
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
            _sessionController.stopSession(forceStopMicrophone: true);
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
    asr.initAsr(_unifiedOnAsrResult);
    // 然后启动ASR（内部会加载模型、启动麦克风、设置热词、播放提示音）
    _startAsr(decideAsrLanguage());
  }



  Widget renderPage() {
    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (ScrollUpdateNotification notification) {
            _lastExtentAfter = notification.metrics.extentAfter;
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
                  key: const ValueKey('word_list_scrollable_positioned_list'),
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    if (index < 0 || index >= words.length) {
                      return const SizedBox.shrink();
                    }
                    return RepaintBoundary(
                      key: ValueKey('word_${words[index].word.id}'),
                      child: renderWord(index),
                    );
                  },
                  initialScrollIndex: _initialScrollIndex ?? 0,
                  itemScrollController: itemScrollController,
                  itemPositionsListener: itemPositionsListener,
                  padding: EdgeInsets.only(
                      top: 20,
                      bottom: 120 + MediaQuery.of(context).viewInsets.bottom,
                  ),
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
  Future<void> _startAsr(AsrLanguage language, [WordVo? word]) async {
    final sw = Stopwatch()..start();
    debugPrint('⏱️ [Latency-ASR] _startAsr 入口 (语言: ${language.locale})');
    if (!mounted) return;

    // 确保监听器已初始化
    asr.initAsr(_unifiedOnAsrResult);

    // 如果已经在处理中（无论是否显示动画），都不再重复启动
    if (_isAsrProcessing) {
      Global.logger.d('⚠️ ASR正在启动中，忽略本次调用');
      return;
    }

    // 如果ASR已经在运行且语言一致，也不需要重复启动
    if (asr.state == AsrState.started && asr.currentLanguage == language) {
      Global.logger.d('✅ ASR已经在运行中且语言一致，无需重复启动');
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
      // 提取 phrases 热词列表
      WordVo? targetWord = word;
      if (targetWord == null) {
        int idx = getBookMarkUiPosition();
        if (idx >= 0 && idx < words.length) {
          targetWord = words[idx].word;
        }
      }

      List<String> phrases = [];
      if (studyMode == WordListStudyMode.speakEnglish) {
        if (targetWord != null) phrases.add(targetWord.spell);
      } else if (studyMode == WordListStudyMode.speakChinese) {
        if (targetWord != null) phrases.addAll(AsrUtil.extractContextualPhrases(targetWord.meaningItems ?? []));
      }

      if (phrases.isNotEmpty) {
        Global.logger.d('~~~~~WordList: 设置 ASR 上下文热词: $phrases');
      }

      await _sessionController.startSession(
        language: language,
        phrases: phrases,
        isSpeakMode: true,
      );
      debugPrint('⏱️ [Latency-ASR] ASR 启动成功: +${sw.elapsedMilliseconds}ms');
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
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
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
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  _sessionController.playAddSuccessSound();

                  // 刷新列表

                  // 此处必须重置 totalWordCount，否则 doQuery 中的优化逻辑(words.length >= totalWordCount)
                  // 会认为数据已全部加载而跳过本次查询，导致新添加的单词无法显示
                  totalWordCount = -1;
                  int queryPageSize = _pageSize;
                  int targetBaseIndex = baseIndex ?? 0;
                  try {
                    final checkResult = await args.wordsProvider.getAPageOfWords(0, 1);
                    final newTotalCount = checkResult.total;
                    if (newTotalCount - targetBaseIndex <= 100) {
                      queryPageSize = max(_pageSize, newTotalCount - targetBaseIndex);
                    } else {
                      targetBaseIndex = ((newTotalCount - 1) ~/ _pageSize) * _pageSize;
                      baseIndex = targetBaseIndex;
                    }
                  } catch (e) {
                    Global.logger.e('计算添加单词后的分页参数失败: $e');
                  }
                  await doQuery(true, targetBaseIndex, queryPageSize, true);
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
    final sw = Stopwatch()..start();
    debugPrint('⏱️ [Latency] onWordPressed 入口: ${word.word.spell}');

    // 如果是切换单词，且处于听说/拼写模式，则先播放当前正在离开的那个词的发音
    if (bookMark != null && bookMark!.position != baseIndex! + index) {
      int oldIndex = getBookMarkUiPosition();
      if (oldIndex >= 0 && oldIndex < words.length) {
        if (studyMode == WordListStudyMode.speakEnglish ||
            studyMode == WordListStudyMode.dictation ||
            studyMode == WordListStudyMode.dictationHandwriting) {
          // 如果该单词已经答对或已揭晓答案（刚才已经播放过一次反馈音），则不再重复播放
          if (words[oldIndex].speakEnglishPassed) {
            Global.logger.d("onWordPressed: 单词已答对/已揭晓且已播放过，跳过离开时的重复播放");
          } else {
            await _sessionController.playWordSound(words[oldIndex].word);
          }
        }
      }
    }

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

      if (studyMode == WordListStudyMode.dictation ||
          studyMode == WordListStudyMode.dictationHandwriting ||
          studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish) {
        scrollToWord(index);
      }
    });



    // 在默写（dictation）或手写默写模式下，点击单词后让输入框获得焦点（用以触发大字号显示）
    if (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.dictationHandwriting) {
      // 延迟到下一帧：scrollToWord 触发的 jumpTo 布局完成后焦点才有效
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          word.focusNode.requestFocus();
        } catch (e, stackTrace) {
          Global.logger.w('请求焦点失败', error: e, stackTrace: stackTrace);
        }
      });
    }

    // 在背中文或背英文模式下，手动切换单词时也清空语音识别缓存
    // 使用 stopAsr 进行热停止以维持麦克风保温状态，完全消除高频物理切流延迟
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      await asr.stopAsr();
      await asr.reset(); // 清除缓冲区
      debugPrint('⏱️ [Latency] stopAsr+reset 完成: +${sw.elapsedMilliseconds}ms');
    }

    // 播放单词发音（背英文模式/默写模式进入时不播放由调用者控制，避免泄露答案）
    final bool shouldPlaySound = playSound &&
        studyMode != WordListStudyMode.speakEnglish &&
        studyMode != WordListStudyMode.hideEnglish; 


    if (shouldPlaySound) {
      debugPrint('⏱️ [Latency] 开始播放发音: +${sw.elapsedMilliseconds}ms');
      await _sessionController.playWordSound(word.word);
      debugPrint('⏱️ [Latency] 发音播放完成: +${sw.elapsedMilliseconds}ms');
      soundFinishListener?.call();
    } else {
      // 未播放发音时（如背英文模式），也要触发回调以继续流程（启动ASR等）
      soundFinishListener?.call();
    }

    // 在语音模式下，播放完成后启动语音识别
    if (studyMode == WordListStudyMode.speakChinese ||
        studyMode == WordListStudyMode.speakEnglish) {
      debugPrint('⏱️ [Latency] 开始 _startAsr: +${sw.elapsedMilliseconds}ms');
      _startAsr(decideAsrLanguage());
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

  @override
  onDelBtnPressed(WordWrapper word, int index) {
    controller.deleteWord(word, index);
  }

  @override
  onMasterBtnPressed(WordWrapper word, int index) {
    controller.masterWord(word, index);
  }

  @override
  onUnmasterBtnPressed(WordWrapper word, int index) {
    controller.unmasterWord(word, index);
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
      // 拼写模式点击不发音，避免泄题
      onWordPressed(word, index, false, null);
    } else {
      onWordPressed(word, index, true, null);
    }
  }

  void _handleWordLongPress(WordWrapper word, int i) {
    context.push('/word_detail',
        extra: WordDetailPageArgs(word.word, true, null, false));
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
      actions.add(CustomSlidableAction(
        onPressed: (_) => isMastered
            ? onUnmasterBtnPressed(word, i)
            : onMasterBtnPressed(word, i),
        backgroundColor: isMastered ? Colors.grey[400]! : const Color(0xFF4CAF50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isMastered ? Icons.check_circle : Icons.check_circle_outline, color: Colors.white, size: 20),
            Text(isMastered ? '已掌握' : '掌握', style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ));
    }

    if (args.showDelBtn || isSpecialList) {
      if (isMastered && isSpecialList) {
        actions.add(CustomSlidableAction(
          onPressed: (_) => onUnmasterBtnPressed(word, i),
          backgroundColor: Colors.grey[400]!,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              Text('已掌握', style: TextStyle(color: Colors.white, fontSize: 10)),
            ],
          ),
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
          buttonText = '掌握';
          color = const Color(0xFF26A69A);
          icon = Icons.check_circle;
        } else {
          buttonText = '删除';
          color = const Color(0xFFEF5350);
          icon = Icons.delete;
        }

        actions.add(CustomSlidableAction(
          onPressed: (_) => (buttonText == '掌握') 
              ? onMasterBtnPressed(word, i) 
              : onDelBtnPressed(word, i),
          backgroundColor: color,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ],
          ),
        ));
      }
    }

    // 4. 详情按钮
    actions.add(CustomSlidableAction(
      onPressed: (_) => _handleWordLongPress(word, i),
      backgroundColor: const Color(0xFF2196F3),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: Colors.white, size: 20),
          Text('详情', style: TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    ));

    return actions;
  }

  // --- Obsolete UI builders removed ---




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
    final slidableActions = _getSlidableActions(word, i, isBookmarked,
        learningStatus: learningStatus);

    switch (studyMode) {
      case WordListStudyMode.list:
        return ListModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          actions: this,
          slidableActions: slidableActions,
        );
      case WordListStudyMode.speakChinese:
      case WordListStudyMode.speakEnglish:
        return SpeakModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          studyMode: studyMode,
          actions: this,
          slidableActions: slidableActions,
          audioLevelBar: _audioLevelBar(),
        );
      case WordListStudyMode.dictation:
        return TypingModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          actions: this,
          slidableActions: slidableActions,
        );
      case WordListStudyMode.dictationHandwriting:
        return HandwritingModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          actions: this,
          slidableActions: slidableActions,
        );
      case WordListStudyMode.hideChinese:
      case WordListStudyMode.hideEnglish:
        return HideModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          studyMode: studyMode,
          actions: this,
          slidableActions: slidableActions,
        );
      default:
        return ListModeItem(
          word: word,
          index: i,
          baseIndex: baseIndex ?? 0,
          isBookmarked: isBookmarked,
          isDarkMode: isDarkMode,
          learningStatus: learningStatus,
          showWordProgress: args.showWordProgress,
          actions: this,
          slidableActions: slidableActions,
        );
    }
  }

  void jumpToNextWord(final int currWordIndex, bool playPronounce,
      Function? soundFinishListener) {
    if (currWordIndex < words.length - 1) {
      var nextWord = words[currWordIndex + 1];
      onWordPressed(
          nextWord, currWordIndex + 1, playPronounce, soundFinishListener);
      if (studyMode == WordListStudyMode.dictation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          nextWord.focusNode.requestFocus();
        });
      }
      if (studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish ||
          studyMode == WordListStudyMode.dictation ||
          studyMode == WordListStudyMode.dictationHandwriting) {
        scrollToWord(currWordIndex + 1);
      }
    } else {
      // 最后一个单词：播放发音，关闭输入法键盘
      unawaited(_sessionController.playWordSound(words[currWordIndex].word));
      FocusScope.of(context).unfocus();
    }
  }

  void jumpToPreviousWord(final int currWordIndex, bool playPronounce) {
    if (currWordIndex > 0) {
      var prevWord = words[currWordIndex - 1];
      onWordPressed(prevWord, currWordIndex - 1, playPronounce, null);
      if (studyMode == WordListStudyMode.dictation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          prevWord.focusNode.requestFocus();
        });
      }
      if (studyMode == WordListStudyMode.speakChinese ||
          studyMode == WordListStudyMode.speakEnglish ||
          studyMode == WordListStudyMode.dictation ||
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
                          if (baseIndex == 0 && words.isNotEmpty && itemScrollController.isAttached) {
                            itemScrollController.jumpTo(index: 0, alignment: 0.0);
                            return;
                          }
                          if (isQuerying) return;
                          // force:true 绕过 lastQueryTime 频率限制，用户主动操作应立即可用
                          baseIndex = 0;
                          await doQuery(true, 0, _pageSize, false, force: true);
                          // 使用 addPostFrameCallback 确保在 UI 重建完成后再跳转
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            if (words.isNotEmpty && itemScrollController.isAttached) {
                              itemScrollController.jumpTo(index: 0, alignment: 0.0);
                            }
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
                          if (totalWordCount <= 0) return;
                          final int lastPageBase = ((totalWordCount - 1) ~/ _pageSize) * _pageSize;
                          if (baseIndex != null && baseIndex! <= lastPageBase && baseIndex! + words.length >= totalWordCount && words.isNotEmpty && itemScrollController.isAttached) {
                            itemScrollController.jumpTo(index: words.length - 1, alignment: _handwritingScrollAlignment);
                            return;
                          }
                          if (isQuerying) return;
                          baseIndex = lastPageBase < 0 ? 0 : lastPageBase;
                          await doQuery(true, baseIndex!, _pageSize, false, force: true);
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            if (words.isNotEmpty && itemScrollController.isAttached) {
                              itemScrollController.jumpTo(index: words.length - 1, alignment: _handwritingScrollAlignment);
                            }
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
                          if (!capturedContext.mounted) {
                            isMenuOpen = false;
                            return;
                          }

                          final sortAlg = await controller.getCurrentSortAlg();
                          if (!capturedContext.mounted) {
                            isMenuOpen = false;
                            return;
                          }

                          // 4. 构建菜单项
                          List<String> menuItems = [
                            menuSortSettings,
                            menuWordList,
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
                          if (studyMode == WordListStudyMode.speakChinese) {
                            menuItems.add(menuSettings);
                          }

                          // 随身听菜单放在最下面
                          menuItems.add(menuWalkman);
                          menuItems.add(menuExportPdf);

                          // 5. 显示菜单 (使用 RootNavigator)
                          // ignore: use_build_context_synchronously
                          final String? selectedValue = await showMenu<String>(
                            context: capturedContext,
                            position: position,
                            useRootNavigator: true,
                            constraints: const BoxConstraints(
                              minWidth: 140,
                              maxWidth: 160,
                            ),
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
                                case menuExportPdf:
                                  icon = Icons.picture_as_pdf;
                                  break;

                                case menuAiStory:
                                  icon = Icons.auto_awesome;
                                  break;
                                case menuSettings:
                                  icon = Icons.settings;
                                  break;
                                case menuSortSettings:
                                  icon = Icons.sort;
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
                                case menuSortSettings:
                                  isSelected = false;
                                  break;
                                case menuExportPdf:
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
                                        choice == menuSortSettings
                                            ? '排序: ${sortAlg.label}'
                                            : choice,
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
                            if (selectedValue == menuExportPdf) {
                              _showExportPdfBottomSheet();
                            } else {
                              setState(() {
                                _isSwitchingMode = true;
                                _switchingMessage = '模式切换中...';
                              });

                              // 利用微任务将沉重的逻辑切分到下一帧开始
                              Future.microtask(() async {
                              if (!mounted) return;
                              
                              try {
                                switch (selectedValue) {
                              case menuWordList:
                                setState(() {
                                  studyMode = WordListStudyMode.list;
                                });
                                await _sessionController.stopSession(forceStopMicrophone: true);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                break;
                              case menuImportFromBook:
                                if (!context.mounted) return;
                                final needRefresh =
                                    await context.push('/import_from_book',
                                        extra: args.wordsProvider
                                            as WordModifier);

                                if (needRefresh == true) {

                                  // 刷新当前页面
                                  totalWordCount = -1;
                                  baseIndex ??= 0;
                                  await doQuery(
                                      true, baseIndex!, _pageSize, false);
                                  if (!context.mounted) return;
                                  setState(() {});
                                }
                                break;
                              case menuImportFromScan:
                                if (!context.mounted) return;
                                final needRefresh =
                                    await context.push('/import_from_scan',
                                        extra: args.wordsProvider
                                            as WordModifier);

                                if (needRefresh == true) {

                                  // 刷新当前页面
                                  totalWordCount = -1;
                                  baseIndex ??= 0;
                                  await doQuery(
                                      true, baseIndex!, _pageSize, false);
                                  if (!context.mounted) return;
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
                                  await _sessionController.stopSession(forceStopMicrophone: true);
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
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
                                // 滚动当前单词到可视区域
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [1. 状态变更与 setState] 耗时: ${swOpen.elapsedMilliseconds}ms');
                                await _sessionController.stopSession(forceStopMicrophone: true);
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
                                await _sessionController.stopSession(forceStopMicrophone: true);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                break;
                              case menuHideEnglish:
                                setState(() {
                                  studyMode = WordListStudyMode.hideEnglish;
                                  for (final w in words) {
                                    w.isAnswerRevealed = false;
                                  }
                                });
                                await _sessionController.stopSession(forceStopMicrophone: true);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                break;

                              case menuSpeakChinese:
                                if (studyMode != WordListStudyMode.speakChinese) {
                                  await _sessionController.stopSession(forceStopMicrophone: true);
                                  setState(() {
                                    clearWordStates();
                                    asrResult = "";
                                    handlingAsrChinese = "";
                                    studyMode = WordListStudyMode.speakChinese;
                                  });
                                  await _startAsr(decideAsrLanguage());
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                break;
                              case menuSpeakEnglish:
                                if (studyMode != WordListStudyMode.speakEnglish) {
                                  await _sessionController.stopSession(forceStopMicrophone: true);
                                  setState(() {
                                    clearWordStates();
                                    asrResult = "";
                                    handlingAsrChinese = "";
                                    studyMode = WordListStudyMode.speakEnglish;
                                  });
                                  await _startAsr(decideAsrLanguage());
                                }
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  jumpToBookMark(force: true);
                                });
                                break;
                                case menuWalkman:
                                  if (studyMode ==
                                          WordListStudyMode.speakChinese ||
                                      studyMode ==
                                          WordListStudyMode.speakEnglish) {
                                    asr.stopMicrophone();
                                    asr.reset();
                                  }
                                  if (!context.mounted) return;
                                  context.push('/walkman',
                                      extra:
                                          WalkmanParams(args.wordsProvider));


                                  break;
                                case menuAiStory:
                                  _generateAiStory();
                                  break;
                                case menuSettings:
                                  _showSettingsDialog();
                                  break;
                                case menuSortSettings:
                                  await _showSortSettingsDialog();
                                  break;
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isSwitchingMode = false;
                                  });
                                }
                              }
                            });
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
                  child: (!dataLoaded)
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
        if (_isSwitchingMode) _buildSwitchingModeOverlay(isDarkMode, message: _switchingMessage),
        if (studyMode == WordListStudyMode.dictationHandwriting && _isHandwritingOverlayOpen)
          HandwritingOverlay(
            isDarkMode: isDarkMode,
            appBarHeight: MediaQuery.of(context).padding.top + kToolbarHeight,
            activeWord: (getBookMarkUiPosition() >= 0 && getBookMarkUiPosition() < words.length)
                ? words[getBookMarkUiPosition()]
                : null,
            bookmarkedIndex: getBookMarkUiPosition(),
            words: words,
            studyMode: studyMode,
            rightZoneVisible: _rightZoneVisible,
            handwritingBoardKey: _handwritingBoardKey,
            giveALittleHint: giveALittleHint,
            clearHint: clearHint,
            onCancel: () {
              setState(() {
                _isHandwritingOverlayOpen = false;
              });
            },
            onWordAnswered: (idx) {
              jumpToNextWord(idx, false, () {});
            },
            onWordPrevious: (idx) {
              jumpToPreviousWord(idx, false);
            },
          ),
      ],
      ),
    );

    swBuild.stop();
    Global.logger.d('PERF_LOG_PENCIL [页面 build 完毕] 耗时: ${swBuild.elapsedMilliseconds}ms, 累计调用 renderWord 次数: $_renderWordCallCount');
    return popScopeWidget;
  }

  /// 构建新手引导覆盖层
  Widget _buildGuideOverlay() {
    return GuideOverlay(
      onClose: _closeGuide,
      onDismissForever: _dismissGuideForever,
      menuRect: _menuRect,
      overlayKey: _overlayKey,
    );
  }

  Widget _buildSwitchingModeOverlay(bool isDarkMode, {required String message}) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontSize: 14,
                      decoration: TextDecoration.none,
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
                      ? '说英文模式设置'
                      : '说中文模式设置',
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
                            await Prefs.write('wordListAsrPassRule', value);
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
      child: Material(
        type: MaterialType.transparency,
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

      final result = await LoadingUtils.withApiLoading(
        loadingText: 'AI 正在为你创作小短文...',
        operation: () => Api.client.generateAiShortStory(wordsJson, Global.currentUserId!),
      );

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

  void _showAiStoryDialog(AiStoryVo storyVo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppTheme.createGradientAppBar(
            title: 'AI 单词小短文',
            actions: [
              if (storyVo.enTtsEnabled)
                IconButton(
                  icon: const Row(
                    children: [
                      Icon(Icons.volume_up, size: 20, color: Colors.white),
                      Text(' En',
                          style: TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  tooltip: '播放英文配音',
                  onPressed: () {
                    _sessionController.playAiStoryEnSound(storyVo.wordsHash);
                  },
                ),
              if (storyVo.cnTtsEnabled)
                IconButton(
                  icon: const Row(
                    children: [
                      Icon(Icons.volume_up, size: 20, color: Colors.white),
                      Text(' 中',
                          style: TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  tooltip: '播放中文配音',
                  onPressed: () {
                    _sessionController.playAiStoryCnSound(storyVo.wordsHash);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white),
                tooltip: '复制',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: storyVo.storyContent));
                  ToastUtil.info('已复制到剪贴板');
                },
              ),
            ],
          ),
          body: Container(
            color: Theme.of(context).scaffoldBackgroundColor, // 为背景提供清晰颜色，避免透视
            child: _buildClickableStory(storyVo.storyContent),
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

  Future<void> _showSortSettingsDialog() async {
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
      
      // Get the current sort alg
      WordSortAlg currentAlg;
      if (args.wordsProvider is! DictWordsProvider) {
        final currentBookmark = await args.bookMarkProvider.getBookMark();
        currentAlg = WordSortAlg.fromCode(currentBookmark?.sortAlg ?? WordSortAlg.original.code);
      } else {
        currentAlg = await args.wordsProvider.getSortAlg();
      }
      final hasUnits = await args.wordsProvider.hasUnits;

      final availableAlgs = WordSortAlg.values.where((alg) {
        if (alg == WordSortAlg.unit && !hasUnits) {
          return false;
        }
        return true;
      }).toList();

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor:
                isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '词表排序设置',
              style: TextStyle(
                color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: availableAlgs.map((alg) {
                final isSelected = currentAlg == alg;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0097A7).withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0097A7)
                          : (isDarkMode ? Colors.white12 : Colors.black12),
                      width: 1,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    title: Text(
                      alg.label,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF0097A7)
                            : (isDarkMode ? Colors.white : Colors.black87),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      _getSortAlgDesc(alg),
                      style: TextStyle(
                        color: isDarkMode ? Colors.white54 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF0097A7))
                        : const Icon(Icons.circle_outlined, color: Colors.grey),
                    onTap: () async {
                      Navigator.of(context).pop();
                      if (currentAlg != alg || alg == WordSortAlg.semantic) {
                        setState(() {
                          _isSwitchingMode = true;
                          _switchingMessage = alg == WordSortAlg.semantic
                              ? '正在计算语境排序，请稍候...'
                              : '正在重新排序，请稍候...';
                        });
                        try {
                          await controller.changeSortAlg(alg);
                        } catch (e) {
                          ToastUtil.error('切换排序失败: $e');
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isSwitchingMode = false;
                            });
                          }
                        }
                      }
                    },
                    ),
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  '取消',
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
    } finally {
      isMenuOpen = false;
    }
  }

  String _getSortAlgDesc(WordSortAlg alg) {
    switch (alg) {
      case WordSortAlg.original:
        return '词书的原始单词顺序';
      case WordSortAlg.random:
        return '单词随机排列';
      case WordSortAlg.alphabetical:
        return '单词按拼写顺序排列';
      case WordSortAlg.unit:
        return '单词按单元顺序排列';
      case WordSortAlg.semantic:
        return '按单词语境和意思关联度排列';
    }
  }

  void _showExportPdfBottomSheet() {
    PdfExportMode selectedMode = PdfExportMode.classic;
    bool includePronounce = true;
    bool isDoubleColumn = true;
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    const primaryColor = Color(0xFF0097A7);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Widget buildRadioOption(PdfExportMode mode, String label) {
              final isSelected = selectedMode == mode;
              return InkWell(
                onTap: () {
                  setModalState(() {
                    selectedMode = mode;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? primaryColor : (isDarkMode ? Colors.white54 : Colors.grey[400]),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode ? Colors.white : Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '导出词表为 PDF',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.grey[900],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: isDarkMode ? Colors.white60 : Colors.grey[600]),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '支持中英对照、拼写和释义的自测默写排版，适合纸质打印与 iPad 复习。',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: isDarkMode ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 8),
                    Text(
                      '导出模式',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white70 : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    buildRadioOption(PdfExportMode.classic, '中英对照表 (常规复习清单)'),
                    buildRadioOption(PdfExportMode.spellDictation, '拼写默写本 (隐藏英文，保留中文和横线)'),
                    buildRadioOption(PdfExportMode.meaningDictation, '释义记忆本 (隐藏中文，保留英文和横线)'),
                    const SizedBox(height: 4),
                    Divider(color: isDarkMode ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 4),
                    Text(
                      '页面版式',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white70 : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setModalState(() {
                                isDoubleColumn = true;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    isDoubleColumn ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: isDoubleColumn ? primaryColor : (isDarkMode ? Colors.white54 : Colors.grey[400]),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '双列排版 (省纸)',
                                    style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white : Colors.grey[800]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setModalState(() {
                                isDoubleColumn = false;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    !isDoubleColumn ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: !isDoubleColumn ? primaryColor : (isDarkMode ? Colors.white54 : Colors.grey[400]),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '单列排版 (字大)',
                                    style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white : Colors.grey[800]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Divider(color: isDarkMode ? Colors.white12 : Colors.grey[200]),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: primaryColor,
                      title: Text(
                        '包含单词音标',
                        style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white70 : Colors.grey[800]),
                      ),
                      value: includePronounce,
                      onChanged: (val) {
                        setModalState(() {
                          includePronounce = val ?? true;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: isDarkMode ? Colors.white30 : Colors.grey[300]!),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              '取消',
                              style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.grey[700]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _handleExportPdf(selectedMode, includePronounce, isDoubleColumn);
                            },
                            child: const Text(
                              '开始导出',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      },
    );
  }

  Future<void> _handleExportPdf(PdfExportMode exportMode, bool includePronounce, bool isDoubleColumn) async {
    final title = args.appBarTitle;
    try {
      await Api.loadingService.show(status: '正在获取词表单词...');
      if (!mounted) return;
      
      final allWords = await controller.getAllSortedWords();
      if (!mounted) return;
      
      if (allWords.isEmpty) {
        throw Exception('当前词表中没有任何单词');
      }

      await PdfExporter.exportToPdf(
        context: context,
        title: title,
        words: allWords,
        exportMode: exportMode,
        includePronounce: includePronounce,
        isDoubleColumn: isDoubleColumn,
        onStatusChanged: (status) {
          Api.loadingService.show(status: status);
        },
      );
    } catch (e) {
      Global.logger.e('导出 PDF 失败', error: e);
      ToastUtil.error('导出失败: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      await Api.loadingService.dismiss();
    }
  }
}


