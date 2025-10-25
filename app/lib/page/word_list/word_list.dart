import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:async';
import 'dart:convert';

import '../../global.dart';
import '../../state.dart';
import '../../util/platform_util.dart';
import '../../util/sound.dart';
import '../../util/word_util.dart';
import '../../theme/app_theme.dart';
import '../../db/db.dart';
import '../index.dart';
import '../walkman.dart';
import '../../util/app_clock.dart';

const String menuWordList = '浏览';
const String menuWalkman = '随身听';
const String menuSpeakChinese = '背中文';
const String menuSpeakEnglish = '背英文';
const String menuWriteSpell = '默写';

abstract class WordsProvider {
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize);

  Future<bool> deleteWord(WordWrapper wordWrapper);

  /// 获取指定单词在所有单词中的位置, 如果指定单词不存在，返回-1
  Future<int> getWordIndex(String spell);
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

  void onWordDeletedFromList(WordWrapper wordWrapper, bool alreadyDeletedOnServer);
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

  /// 外部注入的button，显示在appbar上
  Widget? injectedBtn;

  WordListPageArgs(this.appBarTitle, this.wordsProvider, this.showBackBtn, this.showDelBtn, this.showWordProgress, this.wordProgressLabel,
      this.wordProgressProvider, this.bookMarkProvider, this.injectedBtn);

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

class WordListPageState extends State<WordListPage> {
  static const double leftPadding = 12;
  static const double rightPadding = 16;
  static const double delBtnSize = 24;
  static const int _pageSize = 30;
  static const double bookMarkBorderWidth = 2;

  /// 当列表中的单词数量小于此值时, 将触发加载数据动作。因为加载数据主要是由滚动事件触发的，
  /// 而删除动作可能会使滚动条消失，所以删除动作需要主动检测此值
  static const int minWordCount = 30;

  /// 两次查询的最小时间间隔，单位毫秒
  static const int minQueryInterval = 300;

  var studyMode = WordListStudyMode.list;

  /// 旧字段已移除，这里默认不强制全部答对（后续由 asrPassRule 控制）
  bool get mustAnswerAll => false;

  late WordListPageArgs args;
  bool dataLoaded = false;
  bool isQuerying = false;
  int totalWordCount = -1;
  BookMarkVo? bookMark;

  /// 是否可以离开当前单词（用户回答正确的释义数量达到要求）
  bool canLeaveCurrWord = false;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();

  /// 单词列表界面最上方那个单词在所有单词中（包括那些在服务端，还未加载的）的序号（需要这个值是为了支持从中间某个位置加载单词列表）
  int? baseIndex;

  /// 加载到界面的单词列表（其中第一个单词在所有单词中的序号为 baseIndex)
  List<WordWrapper> words = [];

  /// 是否显示返回到顶部按钮
  bool showToTopBtn = false;

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

  /// "请勿查询"标志，当此标志为true时，如果本来有查询动作（比如滚动到顶部或底部），该动作也不再执行
  bool doNotQueryPlease = false;

  /// 是否显示新手引导
  bool showGuide = false;

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
  }

  Future<void> loadData() async {
    if (!await checkArgs()) {
      return;
    }

    // 获取书签位置
    bookMark = await args.bookMarkProvider.getBookMark();

    if (isBookMarkValid(bookMark)) {
      // 有书签：加载书签所在的那一页单词
      var wordIndex = await args.wordsProvider.getWordIndex(bookMark!.spell);
      if (wordIndex != -1) {
        // 计算书签所在页的起始位置
        baseIndex = (wordIndex ~/ _pageSize) * _pageSize;
        await doQuery(true, baseIndex!, _pageSize, false);

        // 滚动到书签位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final bookMarkUiPos = getBookMarkUiPosition();
          if (bookMarkUiPos >= 0 && bookMarkUiPos < words.length) {
            itemScrollController.scrollTo(index: bookMarkUiPos, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
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
    }

    setState(() {
      dataLoaded = true;
    });
  }

  doQuery(bool clearCurrent, int fromIndex, final int pageSize, bool jumpToTailWhenReady) async {
    /// 如果正在查询，或者当前时间和最后一次查询时间之差小于规定毫秒数，则不查询（保护服务端和UI性能）
    fromIndex = fromIndex < 0 ? 0 : fromIndex;

    if (isQuerying ||
        doNotQueryPlease ||
        (totalWordCount >= 0 && fromIndex >= totalWordCount) ||
        (words.length >= totalWordCount && words.isNotEmpty) ||
        fromIndex < 0 ||
        (lastQueryTime != null && AppClock.now().difference(lastQueryTime!).inMilliseconds < minQueryInterval)) {
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

  loadAPageOfWords(final int fromIndex, final int pageSize, bool jumpToTailWhenReady) async {
    try {
      // 获取一页单词
      final result = await args.wordsProvider.getAPageOfWords(fromIndex, pageSize);

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
        Global.logger.d('向上加载数据: fromIndex=$fromIndex, baseIndex=$baseIndex, 当前words长度=${words.length}');
        var beforeLen = newWords.length;
        var newData = result.rows.where((element) => !words.contains(element)).toList();
        Global.logger.d('向上加载新数据: 新数据数量=${newData.length}');
        newWords.insertAll(0, newData);
        // 更新baseIndex
        var lenDelta = newWords.length - beforeLen;
        newBaseIndex = baseIndex! - lenDelta;
        Global.logger.d('向上加载完成: 新baseIndex=$newBaseIndex, 新words长度=${newWords.length}');

        // 向上加载后，需要调整滚动位置，避免连续触发向上加载
        if (jumpToTailWhenReady == false) {
          // 延迟调整滚动位置，确保UI更新完成
          SchedulerBinding.instance.addPostFrameCallback((_) {
            // 滚动到新插入数据的末尾位置，保持用户当前查看的内容在相同位置
            itemScrollController.scrollTo(index: lenDelta, duration: const Duration(milliseconds: 100), alignment: 0.5); // 显示在屏幕中部
          });
        }
      } else {
        // 向下滚动加载，从尾部添加新数据
        newWords.addAll(result.rows.where((element) => !words.contains(element)));
      }

      // 更新状态
      setState(() {
        totalWordCount = newTotalWordCount;
        words = newWords;
        baseIndex = newBaseIndex;

        if (jumpToTailWhenReady) {
          SchedulerBinding.instance.addPostFrameCallback((_) =>
              itemScrollController.scrollTo(index: (words.length - 1), duration: const Duration(milliseconds: 300), alignment: 0.5)); // 显示在屏幕中部
        }
      });
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '加载单词失败', showToast: false);
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
          .reduce((ItemPosition min, ItemPosition position) => position.itemTrailingEdge < min.itemTrailingEdge ? position : min)
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
              return Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    height: h,
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: Color.lerp(AppTheme.gradientStartColor, AppTheme.gradientEndColor, v),
                      borderRadius: BorderRadius.circular(2),
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
                child: Container(
                  height: 4,
                  margin: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFEAEAEA),
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
          .reduce((ItemPosition max, ItemPosition position) => position.itemLeadingEdge > max.itemLeadingEdge ? position : max)
          .index;
    }
    return max ?? -1;
  }

  void _subscribeMeterIfNeeded() {
    _meterSub ??= asr.meterStream().listen((level) {
      _lastMeterLevel = level.clamp(0.0, 1.0);
      _lastMeterAt = AppClock.now();
    });
    _meterTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = AppClock.now();
      final active = _lastMeterAt != null && now.difference(_lastMeterAt!).inMilliseconds < 150;
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
    super.initState();

    doInit();
    loadData();
    _checkAndShowGuide();
  }

  /// 检查并显示新手引导
  Future<void> _checkAndShowGuide() async {
    try {
      // 检查是否已显示过引导
      final hasShown = await MyDatabase.instance.localParamsDao.getWordListGuideShown();
      Global.logger.d('新手引导检查: hasShown=$hasShown');
      if (!hasShown) {
        // 延迟到下一帧，待布局完成后计算菜单按钮位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 再次延迟，确保菜单按钮完全渲染
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            
            try {
              final RenderBox? rb = _menuKey.currentContext?.findRenderObject() as RenderBox?;
              final Offset? topLeft = rb?.localToGlobal(Offset.zero);
              if (rb != null && topLeft != null) {
                _menuRect = Rect.fromLTWH(topLeft.dx, topLeft.dy, rb.size.width, rb.size.height);
                Global.logger.d('菜单按钮位置: $_menuRect');
              } else {
                Global.logger.w('未能获取菜单按钮位置: rb=$rb, topLeft=$topLeft');
              }
            } catch (e) {
              Global.logger.e('获取菜单按钮位置失败: $e');
            }
            
            Global.logger.d('准备显示引导: mounted=$mounted, dataLoaded=$dataLoaded, _menuRect=$_menuRect');
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
    } catch (e) {
      Global.logger.e('关闭新手引导失败: $e');
    }
  }

  /// 正在进行匹配的asr输入，防止重复处理，影响性能
  var handlingAsrChinese = "";

  onAsrResult(event) {
    if (mounted) {
      setState(() {
        // 统一处理JSON格式的候选结果
        String processedEvent;
        try {
          // 尝试解析JSON格式的候选结果
          Map<String, dynamic>? resultData;
          try {
            resultData = jsonDecode(event);
          } catch (e) {
            // 如果不是JSON格式，当作单个结果处理
            resultData = null;
          }

          if (resultData != null && resultData.containsKey('candidates')) {
            // 处理多个候选结果，使用最佳候选结果
            List<dynamic> candidates = resultData['candidates'];
            List<String> candidateStrings = candidates.map((e) => e.toString()).toList();
            String bestCandidate = resultData['best'] ?? candidateStrings.first;

            Global.logger.d("--- 语音识别候选结果: $candidateStrings");
            Global.logger.d("--- 最佳候选结果: $bestCandidate");
            if (studyMode == WordListStudyMode.speakEnglish) {
              // 背英文：选择最接近目标拼写的候选
              final curr = getBookMarkUiPosition();
              final target = (curr >= 0 && curr < words.length) ? words[curr].word.spell : '';
              processedEvent = AsrUtil.selectBestCandidate(candidateStrings, target);
              Global.logger.d('--- 背英文选择候选: "$processedEvent" (target: $target)');
            } else {
              processedEvent = bestCandidate;
            }
          } else {
            // 单个结果处理
            if (studyMode == WordListStudyMode.speakEnglish) {
              final curr = getBookMarkUiPosition();
              final target = (curr >= 0 && curr < words.length) ? words[curr].word.spell : '';
              processedEvent = AsrUtil.preprocessEnglish(event, target);
            } else {
              processedEvent = event;
            }
          }
        } catch (e) {
          Global.logger.e("--- 语音识别结果处理错误: $e");
          processedEvent = event;
        }

        // 模式化预处理：背英文用英文预处理；其他用中文预处理
        if (studyMode == WordListStudyMode.speakEnglish) {
          // 这里再次做一次英文预处理，确保一致
          final curr = getBookMarkUiPosition();
          final target = (curr >= 0 && curr < words.length) ? words[curr].word.spell : '';
          asrResult = AsrUtil.preprocessEnglish(processedEvent, target);
        } else {
          asrResult = AsrUtil.preprocess(processedEvent);
        }
        Global.logger.d("--- 语音识别结果: $asrResult");
        if (asrResult.isNotEmpty) {
          if (asrResult != handlingAsrChinese) {
            handlingAsrChinese = asrResult;
            Global.logger.d(asrResult);
            checkAsrResult(asrResult);
          }
        }
      });
    }
  }

  /// 当前并行的asr任务数量（由于协程，并发是可能的）
  int runningAsrTaskCount = 0;

  /// 检查语音识别结果是否匹配单词的意思
  checkAsrResult(String asrResult) async {
    if (asr.state != AsrState.started) {
      return;
    }

    final currWordIndex = getBookMarkUiPosition();
    if (currWordIndex == -1) {
      return;
    }

    runningAsrTaskCount++;
    try {
      if (studyMode == WordListStudyMode.speakEnglish) {
        // 背英文模式：检查英文拼写
        String inputText = asrResult.trim().toLowerCase();
        String correctSpell = words[currWordIndex].word.spell.toLowerCase();

        Global.logger.d('背英文模式检查: inputText=$inputText, correctSpell=$correctSpell');

        if (inputText == correctSpell) {
          canLeaveCurrWord = true;
          // 标记通过以揭示英文
          words[currWordIndex].speakEnglishPassed = true;
          // 播放提示音
          await SoundUtil.playAssetSound('ding5.mp3', 1.5, 0.2);
          // 识别正确后，先关闭语音识别，避免录到系统发音
          asr.stopAsr();
          asr.reset();
          // 然后播放一次标准发音（开始时不播放）
          try {
            if (!_audioPlayerDisposed) {
              await SoundUtil.playPronounceSound2(words[currWordIndex].word, audioPlayer);
            }
          } catch (e) {
            Global.logger.d("播放发音失败: $e");
          }
          Global.logger.d('背英文模式：拼写正确！');
        }
      } else {
        // 背中文模式：检查中文释义
        late Triple<int, int, int> result;
        setState(() {
          result = matchInputChineseWithMeaningItems(
            words[currWordIndex],
            asrResult,
          );
        });

        // 说出了正确意思，播放音效，同时置可离开当前单词的标志
        final answeredAllMeanings = result.second == result.first;
        if (result.third > 0) {
          if (answeredAllMeanings || !mustAnswerAll) {
            canLeaveCurrWord = true;
          }

          // 播放提示音（注：await等待播音完成，由于协程特性，可能会导致多个并发的asr任务，这正是需要的行为）
          await SoundUtil.playAssetSound('ding5.mp3', mustAnswerAll ? 2.0 : 1.5, 0.2);
        }
      }

      // 离开当前单词，跳转到下一个（如果回答正确，且当前没有其他进行中的asr任务）
      if (canLeaveCurrWord && runningAsrTaskCount == 1) {
        if (studyMode == WordListStudyMode.speakEnglish) {
          // 背英文模式：标记当前单词已答对
          words[currWordIndex].answeredAllMeanings = true;
        }

        asr.stopAsr();
        asr.reset(); // 清除缓冲区

        // 跳过全部释义已经答对的单词
        var nextWordIndex = currWordIndex + 1;
        if (nextWordIndex == words.length) {
          nextWordIndex = 0; // 已达末尾，回到开始
        }
        var count = 0; // 已尝试跳过的单词数量，不得大于单词数量，防止无穷循环
        while (nextWordIndex < words.length) {
          if (!words[nextWordIndex].answeredAllMeanings) {
            break;
          }
          nextWordIndex += 1;
          if (nextWordIndex == words.length) {
            nextWordIndex = 0; // 已达末尾，回到开始
          }
          count += 1;
          if (count > words.length) {
            ToastUtil.info("恭喜，你答对了所有单词");
            return;
          }
        }

        jumpToNextWord(nextWordIndex - 1, true, () {
          // 新单词：清空识别展示，避免显示上一个单词的结果
          asrResult = "";
          handlingAsrChinese = "";
          asr.startAsr(decideAsrLanguage());
        });

        canLeaveCurrWord = false;
      }
    } finally {
      runningAsrTaskCount--;
    }
  }

  AsrLanguage decideAsrLanguage() {
    if (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakEnglish) {
      return AsrLanguage.english;
    }
    return AsrLanguage.chinese;
  }

  doInit() {
    asr = Asr();
    asr.initAsr(onAsrResult);
    _subscribeMeterIfNeeded();
    asr.addStateListener((state) {
      if (!mounted) return;
      if (state == AsrState.started) {
        // 恢复识别后，确保重新订阅电平流
        _subscribeMeterIfNeeded();
        // 向 iOS 端下发上下文短语（当前单词允许的释义子项）
        try {
          final curr = getBookMarkUiPosition();
          if (curr >= 0 && curr < words.length) {
            // 使用util函数提取上下文短语
            List<String> allowPhrases = AsrUtil.extractContextualPhrases(
              words[curr].word.getMergedMeaningItems(),
            );
            if (allowPhrases.isNotEmpty) {
              AsrUtil.setContextualStrings(
                allowPhrases,
                asr.asrMethodChannel,
                asr.permissionGranted,
              );
            }
          }
        } catch (_) {}
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
    return true;
  }

  @override
  void dispose() {
    asr.stopAsr();
    _audioPlayerDisposed = true; // 标记为已释放
    _unsubscribeMeter();
    _meterLevelNotifier.dispose();

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        audioPlayer.dispose();
      } catch (e) {
        // 忽略释放时的错误
        Global.logger.d("释放 AudioPlayer 时出错: $e");
      }
    });

    for (var word in words) {
      word.focusNode.dispose();
    }
    super.dispose();
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
        var currentPosition = positions.where((pos) => pos.index == bookMarkUiPos).firstOrNull;
        if (currentPosition != null) {
          // 如果单词已经在屏幕中部附近（误差在5%以内），不需要滚动
          if (currentPosition.itemLeadingEdge >= 0.45 && currentPosition.itemLeadingEdge <= 0.55) {
            return;
          }
          // 如果单词在目标位置上方（更靠近屏幕顶部），不进行向下滚动调整
          if (currentPosition.itemLeadingEdge < 0.5) {
            return;
          }
        }
      }

      // 让书签单词的上沿显示在屏幕中部
      itemScrollController.scrollTo(index: bookMarkUiPos, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
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
      var currentPosition = positions.where((pos) => pos.index == wordUiIndex).firstOrNull;
      if (currentPosition != null) {
        // 如果单词已经在屏幕中部附近（误差在5%以内），不需要滚动
        if (currentPosition.itemLeadingEdge >= 0.45 && currentPosition.itemLeadingEdge <= 0.55) {
          return;
        }
        // 如果单词在目标位置上方（更靠近屏幕顶部），不进行向下滚动调整
        if (currentPosition.itemLeadingEdge < 0.5) {
          return;
        }
      }
    }

    // 让目标单词的上沿显示在屏幕中部
    itemScrollController.scrollTo(index: wordUiIndex, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
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
    return NotificationListener<ScrollUpdateNotification>(
        onNotification: (ScrollUpdateNotification notification) {
          // 如果设置了"请勿查询"标志，直接返回
          if (doNotQueryPlease) {
            return false;
          }

          // 如果正在查询或者查询时间间隔未到，跳过本次处理
          if (isQuerying || (lastQueryTime != null && AppClock.now().difference(lastQueryTime!).inMilliseconds < minQueryInterval)) {
            return false;
          }

          // 向下滚动 - 滑动到最下方单词时，加载下一页单词
          if (notification.scrollDelta != null && notification.scrollDelta! > 0) {
            // 检查是否滚动到最下方单词
            if (notification.metrics.extentAfter < 100) {
              Global.logger.d('向下滚动触发: extentAfter=${notification.metrics.extentAfter}, baseIndex=$baseIndex, words.length=${words.length}');
              // 使用Future.microtask减少UI阻塞
              Future.microtask(() {
                doQuery(false, baseIndex! + words.length, _pageSize, false);
              });
            }
          }
          // 向上滚动 - 滑动到最上方单词时，加载上一页单词
          else if (notification.scrollDelta != null && notification.scrollDelta! < 0) {
            // 检查是否滚动到最上方单词，且还有更多内容可以加载
            if (notification.metrics.extentBefore < 100 && baseIndex! > 0) {
              Global.logger.d('向上滚动触发: extentBefore=${notification.metrics.extentBefore}, baseIndex=$baseIndex, words.length=${words.length}');
              // 使用Future.microtask减少UI阻塞
              Future.microtask(() {
                Global.logger.d('开始向上查询: fromIndex=${baseIndex! - _pageSize}, pageSize=$_pageSize');
                doQuery(false, baseIndex! - _pageSize, _pageSize, false);
              });
            } else if (notification.metrics.extentBefore < 100 && baseIndex! <= 0) {
              Global.logger.d('向上滚动检测: 已到最顶部，无法继续向上加载 extentBefore=${notification.metrics.extentBefore}, baseIndex=$baseIndex');
            }
          }

          // 控制"回到顶部"按钮的显示与隐藏
          if (notification.metrics.extentBefore /*视口上方未展示的内容长度*/ < 500 && showToTopBtn) {
            setState(() {
              showToTopBtn = false;
            });
          } else if (notification.metrics.extentBefore /*视口上方未展示的内容长度*/ > 500 && !showToTopBtn) {
            setState(() {
              showToTopBtn = true;
            });
          }

          return false;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: ScrollablePositionedList.builder(
                itemCount: words.length,
                itemBuilder: (context, index) => renderWord(index),
                itemScrollController: itemScrollController,
                itemPositionsListener: itemPositionsListener,
                padding: EdgeInsets.zero,
              ),
            ),
            // 底部的按钮，固定在页面底部
            if (args.injectedBtn != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 0.0),
                child: args.injectedBtn,
              ),
          ],
        ));
  }

  onWordPressed(WordWrapper word, int index, bool playSound, Function? soundFinishListener) async {
    // 更新书签位置
    setState(() {
      if (bookMark == null || bookMark!.position != baseIndex! + index) {
        // 更新老位置的单词状态
        if (bookMark != null && bookMark!.position >= baseIndex! && bookMark!.position <= baseIndex! + words.length) {
          var oldWord = words[getBookMarkUiPosition()];
          if (studyMode == WordListStudyMode.dictation) {
            // 如果用户输入的单词拼写不正确，那么离开该单词时，自动提供正确的拼写
            // 仅填充正确答案，不在这里播放发音，避免与跳转前的“离开单词发音”重复
            if (!Util.equalsIgnoreCase(oldWord.spellController.text, oldWord.word.spell)) {
              oldWord.spellController.text = oldWord.word.spell;
              oldWord.isAnswerProvidedBySystem = true;
            }
          }
        }

        // 更新书签到新位置
        bookMark = BookMarkVo(baseIndex! + index, word.word.spell);
        // 异步保存书签，并处理结果
        args.bookMarkProvider.saveBookMark(bookMark!).then((success) {
          if (!success) {
            // 如果保存失败，可以记录日志或者通知用户
            Global.logger.e('书签保存失败: ${word.word.spell}, position: ${baseIndex! + index}');
          }
        });

        word.hintLetterCount = 0;
        word.spellController.text = '';
        word.isAnswerProvidedBySystem = false;
        canLeaveCurrWord = false;

        // 切换到新单词时，重置“背英文”模式的临时状态，避免显示上一个单词的识别/结果
        if (studyMode == WordListStudyMode.speakEnglish) {
          // 新单词默认未通过
          word.speakEnglishPassed = false;
          // 清空上一次的识别展示文本
          asrResult = "";
          handlingAsrChinese = "";
        }
      }
    });

    // 在默写（dictation）模式下，点击单词后让输入框自动获得焦点
    if (studyMode == WordListStudyMode.dictation) {
      try {
        word.focusNode.requestFocus();
      } catch (_) {}
    }

    // 在背中文模式下，手动切换单词时也清空语音识别缓存
    if (studyMode == WordListStudyMode.speakChinese) {
      asr.stopAsr();
      asr.reset(); // 清除缓冲区
    }

    // 播放单词发音（背英文模式开始时不播放，避免泄露答案）
    final bool shouldPlaySound = playSound && studyMode != WordListStudyMode.speakEnglish;
    if (shouldPlaySound) {
      await SoundUtil.playPronounceSound2(word.word, audioPlayer);
      soundFinishListener?.call();
    } else {
      // 未播放发音时（如背英文模式），也要触发回调以继续流程（启动ASR等）
      soundFinishListener?.call();
    }

    // 在背中文模式下，播放完成后启动语音识别
    if (studyMode == WordListStudyMode.speakChinese) {
      asr.startAsr(decideAsrLanguage());
    }
  }

  /// 获取书签中记录的原始位置，如果书签为null，返回-1
  int getBookMarkRawPosition(BookMarkVo? bookMark) {
    return bookMark == null ? -1 : bookMark.position;
  }

  bool isBookMarkValid(BookMarkVo? bookMark) {
    return bookMark != null;
  }

  onDelBtnPressed(WordWrapper word, int index) {
    // 删除单词并更新书签
    args.wordsProvider.deleteWord(word).then((value) {
      if (value) {
        // 删除单词
        setState(() {
          words.remove(word);
          totalWordCount--;
        });

        // 更新书签
        if (isBookMarkValid(bookMark)) {
          final bookMarkPosition = getBookMarkRawPosition(bookMark);
          if (index + baseIndex! < bookMarkPosition && bookMarkPosition <= words.length + baseIndex!) {
            var word = words[bookMarkPosition - baseIndex! - 1];
            setState(() {
              bookMark = BookMarkVo(bookMarkPosition - 1, word.word.spell);
            });

            args.bookMarkProvider.saveBookMark(bookMark!).then((success) {
              if (!success) {
                Global.logger.e('删除单词后更新书签失败: spell=${bookMark!.spell}, position=${bookMarkPosition - 1}');
              }
            });
          }
        }

        // 如果剩余单词小于一定数量，主动加载更多数据
        if (words.length < minWordCount) {
          doQuery(false, baseIndex! + words.length, _pageSize, false);
        }
      }
    });
  }

  Color progressColor(WordWrapper word) {
    double ratio = args.wordProgressProvider.getWordProgress(word.tag) / args.wordProgressProvider.getWordProgressMax(word.tag);
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
      word.answeredAllMeanings = false;
      word.speakEnglishPassed = false;
    }
  }

  Container renderWord(final int i) {
    var word = words[i];
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final isBookmarked = getBookMarkUiPosition() == i;

    /// 一个单词
    var row = Container(
      margin: EdgeInsets.only(
        left: 4,
        right: 4,
        top: 4,
        bottom: i == words.length - 1 ? 0 : 4, // 最后一个单词不设底部间距
      ),
      decoration: BoxDecoration(
        gradient: isBookmarked
            ? LinearGradient(
                colors: [
                  const Color(0xFF0097A7).withValues(alpha: 0.08),
                  const Color(0xFF00ACC1).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isBookmarked
            ? null
            : isDarkMode
                ? const Color(0xFF1E1E1E).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: isBookmarked
            ? Border.all(
                width: 2,
                color: const Color(0xFF0097A7).withValues(alpha: 0.3),
              )
            : Border.all(
                width: 1,
                color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
              ),
        boxShadow: [
          BoxShadow(
            color: isBookmarked ? const Color(0xFF0097A7).withValues(alpha: 0.2) : (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
            blurRadius: isBookmarked ? 8 : 4,
            offset: Offset(0, isBookmarked ? 4 : 2),
          ),
        ],
      ),
      child: Row(
        children: [
          /// 单词内容
          Expanded(
            child: InkWell(
              focusColor: Colors.transparent,
              onTap: () async {
                if (studyMode == WordListStudyMode.dictation) {
                  final curr = getBookMarkUiPosition();
                  // 点击引发跳转：播放离开的那个单词发音
                  if (curr >= 0 && curr != i && curr < words.length) {
                    try {
                      await SoundUtil.playPronounceSound2(words[curr].word, audioPlayer);
                    } catch (_) {}
                    onWordPressed(word, i, false, null);
                  } else {
                    // 未引发跳转：播放当前单词
                    onWordPressed(word, i, true, null);
                  }
                } else {
                  onWordPressed(word, i, true, null);
                }
              },
              onLongPress: () async {
                if (studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) {
                  var currentUser = Global.getLoggedInUser();
                  if (currentUser != null) {
                    // 旧字段已废弃：不再切换，直接刷新
                    setState(() {
                      onWordPressed(word, i, true, null);
                    });
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    /// 序号和进度条区域
                    Column(
                      children: [
                        /// 单词序号
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isBookmarked
                                  ? [const Color(0xFF0097A7), const Color(0xFF00ACC1)]
                                  : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: (isBookmarked ? const Color(0xFF0097A7) : Colors.grey).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${(baseIndex! + i + 1) > 0 ? (baseIndex! + i + 1) : 1}',
                              textScaler: TextScaler.linear(1.0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),

                        /// 掌握度进度条（横条）
                        if (args.showWordProgress)
                          Container(
                            width: 32,
                            height: 4,
                            margin: const EdgeInsets.only(top: 4),
                            child: FAProgressBar(
                              borderRadius: const BorderRadius.all(Radius.circular(2)),
                              currentValue: args.wordProgressProvider.getWordProgress(word.tag),
                              maxValue: args.wordProgressProvider.getWordProgressMax(word.tag),
                              displayText: '',
                              direction: Axis.horizontal,
                              displayTextStyle: const TextStyle(color: Color(0x00000000)),
                              backgroundColor: isDarkMode ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
                              progressColor: progressColor(word),
                              animatedDuration: const Duration(milliseconds: 200),
                            ),
                          ),
                        // 紧凑波形：放在掌握度条正下方
                        // 在背中文/背英文模式且当前单词（书签行）显示波形
                        if ((studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) && isBookmarked)
                          Container(
                            width: 32,
                            height: 12,
                            margin: const EdgeInsets.only(top: 3),
                            child: _audioLevelBar(),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    /// 单词内容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// 单词英文（背英文模式统一在释义下方展示，这里不显示）
                          (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakEnglish)
                              ? Container()
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // 估算单词和音标所需的宽度
                                    final spellWidth = word.word.spell.length * 11.0; // 估算单词宽度
                                    final pronounceWidth = word.word.mergedPronounce.isNotEmpty
                                        ? (word.word.mergedPronounce.length * 7.0 + 24.0) // 估算音标宽度（包括容器padding）
                                        : 0.0;
                                    final totalWidth = spellWidth + pronounceWidth + 16.0; // 包括间距

                                    // 如果总宽度超过可用宽度，或者音标很长，则换行显示
                                    final shouldWrap = totalWidth > constraints.maxWidth || word.word.mergedPronounce.length > 25;

                                    if (shouldWrap && word.word.mergedPronounce.isNotEmpty) {
                                      // 换行显示：单词一行，音标一行
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 单词行
                                          Text(
                                            word.word.spell,
                                            textScaler: TextScaler.linear(1.0),
                                            style: TextStyle(
                                              color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              height: 1.3,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          // 音标行
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '[${word.word.mergedPronounce}]',
                                                textScaler: TextScaler.linear(1.0),
                                                style: TextStyle(
                                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                                                  fontSize: 12,
                                                  fontFamily: 'NotoSans',
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.3,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    } else {
                                      // 同行显示：单词和音标在一行
                                      return Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              word.word.spell,
                                              textScaler: TextScaler.linear(1.0),
                                              style: TextStyle(
                                                color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                height: 1.3,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                          if (word.word.mergedPronounce.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '[${word.word.mergedPronounce}]',
                                                  textScaler: TextScaler.linear(1.0),
                                                  style: TextStyle(
                                                    color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                                                    fontSize: 12,
                                                    fontFamily: 'NotoSans',
                                                    fontWeight: FontWeight.w500,
                                                    height: 1.3,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    }
                                  },
                                ),

                          /// 单词释义
                          if (studyMode == WordListStudyMode.list ||
                              studyMode == WordListStudyMode.dictation ||
                              studyMode == WordListStudyMode.speakEnglish)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                word.word.getMeaningStr(),
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                  height: 1.5,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),

                          /// 给点提示
                          studyMode == WordListStudyMode.dictation && getBookMarkUiPosition() == i
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(word.word.spell.substring(0, word.hintLetterCount)),
                                    ],
                                  ),
                                )
                              : Container(),

                          // 移除在内容区域的大波形展示（改为紧凑放置在掌握度条下方）

                          /// 单词拼写输入框
                          studyMode == WordListStudyMode.dictation
                              ? AnimatedBuilder(
                                  animation: word.focusNode,
                                  builder: (context, child) {
                                    final hasFocus = word.focusNode.hasFocus;
                                    final fontSize = hasFocus ? 22.0 : 16.0;
                                    return TextField(
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
                                        focusedBorder: const UnderlineInputBorder(
                                          borderSide: BorderSide(color: Color(0xFF0097A7)),
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onTap: () {
                                        onWordPressed(word, i, false, null);
                                      },
                                      onChanged: (value) async {
                                        // 先刷新UI，使颜色立即变绿
                                        setState(() {});
                                        // 如果拼写正确：先让UI变绿，再执行后续动作（播放离开单词发音+跳转）
                                        if (Util.equalsIgnoreCase(word.word.spell, value)) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) async {
                                            try {
                                              await SoundUtil.playPronounceSound2(word.word, audioPlayer);
                                            } catch (_) {}
                                            jumpToNextWord(i, false, () {});
                                          });
                                        }
                                      },
                                      style: TextStyle(
                                          fontSize: fontSize,
                                          color: Util.equalsIgnoreCase(word.word.spell, word.spellController.text)
                                              ? word.isAnswerProvidedBySystem
                                                  ? Colors.blue
                                                  : Colors.green
                                              : Colors.red),
                                    );
                                  },
                                )
                              : Container(),

                          /// 默写中文输入区
                          studyMode == WordListStudyMode.speakChinese
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: renderAsrMeaningItems(word),
                                )
                              : Container(),

                          /// 背英文输入区（释义下方：未通过仅一条下划线；通过后显示英文与音标）
                          studyMode == WordListStudyMode.speakEnglish
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    if (!word.speakEnglishPassed) ...[
                                      // 下划线内显示占位文本，提示用户说出发音
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Container(
                                          constraints: const BoxConstraints(minWidth: 120),
                                          padding: const EdgeInsets.only(bottom: 2),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: isDarkMode ? Colors.white38 : (Colors.grey[500] ?? Colors.grey),
                                                width: 1.0,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            ((isBookmarked) && (asrResult is String && (asrResult as String).isNotEmpty))
                                                ? (asrResult as String)
                                                : (word.hintLetterCount > 0
                                                    ? word.word.spell.substring(0, word.hintLetterCount)
                                                    : '请说出单词发音'),
                                            textScaler: TextScaler.linear(1.0),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDarkMode ? Colors.white54 : Colors.grey[600],
                                              height: 1.2,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      // 显示英文拼写与音标
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            word.word.spell,
                                            textScaler: TextScaler.linear(1.0),
                                            style: TextStyle(
                                              color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                          if (word.word.mergedPronounce.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '[${word.word.mergedPronounce}]',
                                                textScaler: TextScaler.linear(1.0),
                                                style: TextStyle(
                                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
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
                                      ),
                                    ],
                                  ],
                                )
                              : Container(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// 按钮区
          if (args.showDelBtn ||
              ((studyMode == WordListStudyMode.dictation ||
                      studyMode == WordListStudyMode.speakChinese ||
                      studyMode == WordListStudyMode.speakEnglish) &&
                  isBookmarked))
            Container(
              constraints: const BoxConstraints(maxWidth: 60),
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 给点提示
                  if ((studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) && isBookmarked)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA726).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFFA726).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            giveALittleHint(word);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.lightbulb,
                              size: 22,
                              color: Color(0xFFFFA726),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 清除提示
                  if ((studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) && isBookmarked)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9E9E9E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF9E9E9E).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            clearHint(word);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.lightbulb_outline,
                              size: 22,
                              color: Color(0xFF9E9E9E),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 删除按钮
                  if (args.showDelBtn) _buildActionButton(word, i),
                ],
              ),
            ),
        ],
      ),
    );
    return row;
  }

  void jumpToNextWord(final int currWordIndex, bool playPronounce, Function? soundFinishListener) {
    if (currWordIndex < words.length - 1) {
      var nextWord = words[currWordIndex + 1];
      onWordPressed(nextWord, currWordIndex + 1, playPronounce, soundFinishListener);
      if (studyMode == WordListStudyMode.dictation) {
        nextWord.focusNode.requestFocus();
      }
      if (studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) {
        scrollToWord(currWordIndex + 1);

        /// 如果目标单词不可见（在视口下方），则视口向下滚动一个单词
        /*if (currWordIndex + 3 >= getLastVisibleListItem()) {
          scrollToWord(getFirstVisibleListItem() + 1);
        }*/
      }
    } else {
      // 到达最后一个单词
      // 跳回第一个单词
      if (studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) {
        // 确保书签更新到第一个单词
        if (words.isNotEmpty) {
          onWordPressed(words[0], 0, playPronounce, soundFinishListener);
        }
        jumpToNextWord(-1, playPronounce, soundFinishListener);
        scrollToWord(0);
      }
    }
  }

  void clearHint(WordWrapper word) {
    setState(() {
      word.hintLetterCount = 0;
    });
  }

  void giveALittleHint(WordWrapper word) {
    setState(() {
      if (studyMode == WordListStudyMode.dictation) {
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

  Widget _buildActionButton(WordWrapper word, int index) {
    // 根据不同的单词列表类型，显示不同的文字和颜色
    String buttonText;
    Color color;

    switch (args.appBarTitle) {
      case '已掌握':
        buttonText = '重学';
        color = const Color(0xFF2196F3); // 蓝色，表示重学
        break;
      case '学习中':
        buttonText = '掌握';
        color = const Color(0xFF4CAF50); // 绿色，表示完成/掌握
        break;
      case '生词本':
        buttonText = '删除';
        color = const Color(0xFFEF5350); // 红色，表示删除
        break;
      case '阶段复习':
        buttonText = '掌握';
        color = const Color(0xFF4CAF50); // 绿色，表示掌握
        break;
      case '今日错词':
      case '今日新词':
      case '今日旧词':
      case '今日单词':
        buttonText = '掌握';
        color = const Color(0xFF4CAF50); // 绿色，表示掌握
        break;
      default:
        buttonText = '删除';
        color = const Color(0xFFEF5350);
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            onDelBtnPressed(word, index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              buttonText,
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Stack(
      children: [
        Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
      appBar: !dataLoaded
          ? null
          : AppBar(
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
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                          const Icon(Icons.bookmark, color: Colors.white, size: 28),
                          Text(
                            'S',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.primaryColor),
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
                            itemScrollController.scrollTo(index: 0, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
                          });
                        });
                      });
                    },
                  ),

                  /// 书签图标 - 跳到书签位置
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.bookmark, color: Colors.white, size: 28),
                          Text(
                            isBookMarkValid(bookMark) ? '${getBookMarkRawPosition(bookMark) + 1}' : '书签\n无效',
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                                letterSpacing: 0.1,
                                color: isBookMarkValid(bookMark) ? AppTheme.primaryColor : Colors.red[300]),
                          ),
                        ],
                      ),
                    ),
                    onTap: () {
                      if (isBookMarkValid(bookMark)) {
                        final bookMarkUiPos = getBookMarkUiPosition();
                        if (bookMarkUiPos >= 0 && bookMarkUiPos < words.length) {
                          // 书签在当前加载的单词范围内，直接跳转
                          jumpToBookMark();
                        } else {
                          // 书签不在当前范围内，重新加载数据到书签位置
                          clearQueryResult();
                          // 计算书签所在页的起始位置
                          baseIndex = (bookMark!.position ~/ _pageSize) * _pageSize;
                          doQuery(true, baseIndex!, _pageSize, false).then((_) {
                            // 滚动到书签位置，增加延迟确保UI完全更新
                            Future.delayed(const Duration(milliseconds: 100), () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final newBookMarkUiPos = getBookMarkUiPosition();
                                if (newBookMarkUiPos >= 0 && newBookMarkUiPos < words.length) {
                                  // 直接滚动到书签位置，不使用jumpToBookMark避免位置检查
                                  itemScrollController.scrollTo(index: newBookMarkUiPos, duration: const Duration(milliseconds: 300), alignment: 0.5);
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
                          const Icon(Icons.bookmark, color: Colors.white, size: 28),
                          Text(
                            'E',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.primaryColor),
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
                                index: words.length - 1, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
                          });
                        });
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                // 使用GlobalKey包裹图标，便于计算其全局坐标
                Container(
                  key: _menuKey,
                  alignment: Alignment.center,
                  child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case menuWordList:
                        setState(() {
                          studyMode = WordListStudyMode.list;
                        });
                        _unsubscribeMeter();
                        asr.stopAsr();
                        break;
                      case menuWriteSpell:
                        setState(() {
                          // 进入默写模式：清空所有单词的输入与系统填充状态
                          studyMode = WordListStudyMode.dictation;
                          for (final w in words) {
                            w.spellController.text = '';
                            w.isAnswerProvidedBySystem = false;
                            w.hintLetterCount = 0;
                          }
                        });
                        _unsubscribeMeter();
                        asr.stopAsr();
                        break;
                      case menuSpeakChinese:
                      // 先停止并重置当前ASR，避免前一模式的缓存/语言残留
                        asr.stopAsr();
                        asr.reset();
                        setState(() {
                          clearWordStates();
                          // 切到中文识别前，清空英文下划线的识别展示
                          asrResult = "";
                          handlingAsrChinese = "";
                          studyMode = WordListStudyMode.speakChinese;
                        });
                        asr.startAsr(decideAsrLanguage());
                        _subscribeMeterIfNeeded();
                        break;
                      case menuSpeakEnglish:
                        // 先停止并重置当前ASR，避免前一模式的缓存/语言残留
                        asr.stopAsr();
                        asr.reset();
                        setState(() {
                          clearWordStates();
                          // 清空上一次的识别展示，避免把中文结果带到英文下划线
                          asrResult = "";
                          handlingAsrChinese = "";
                          studyMode = WordListStudyMode.speakEnglish;
                        });
                        // 用英文识别重启ASR，并订阅电平
                        asr.startAsr(decideAsrLanguage());
                        _subscribeMeterIfNeeded();
                        break;
                      case menuWalkman:
                        Get.toNamed('/walkman', arguments: WalkmanParams(args.wordsProvider));
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    List<String> menus = [
                      menuWordList,
                      menuWalkman,
                    ];
                    
                    // 根据ASR支持情况添加语音相关菜单
                    if (PlatformUtils.isAsrSupported()) {
                      menus.add(menuSpeakChinese); // 背中文（iOS和Android都支持）
                    }
                    if (PlatformUtils.isEnglishAsrSupported()) {
                      menus.add(menuSpeakEnglish); // 背英文（仅iOS支持）
                    }
                    
                    menus.add(menuWriteSpell);
                    return menus.map((String choice) {
                      IconData icon;
                      switch (choice) {
                        case menuWordList:
                          icon = Icons.list_alt;
                          break;
                        case menuWalkman:
                          icon = Icons.headphones;
                          break;
                        case menuSpeakChinese:
                          icon = Icons.record_voice_over;
                          break;
                        case menuSpeakEnglish:
                          icon = Icons.record_voice_over;
                          break;
                        case menuWriteSpell:
                          icon = Icons.edit;
                          break;
                        default:
                          icon = Icons.help_outline;
                      }
                      
                      // 判断当前菜单项是否被选中
                      bool isSelected = false;
                      switch (choice) {
                        case menuWordList:
                          isSelected = studyMode == WordListStudyMode.list;
                          break;
                        case menuSpeakChinese:
                          isSelected = studyMode == WordListStudyMode.speakChinese;
                          break;
                        case menuSpeakEnglish:
                          isSelected = studyMode == WordListStudyMode.speakEnglish;
                          break;
                        case menuWriteSpell:
                          isSelected = studyMode == WordListStudyMode.dictation;
                          break;
                      }
                      
                      return PopupMenuItem<String>(
                        value: choice,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFF0097A7).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: isSelected 
                                    ? const Color(0xFF0097A7)
                                    : (isDarkMode ? Colors.white : Colors.grey[700]),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                choice,
                                style: TextStyle(
                                  color: isSelected 
                                      ? const Color(0xFF0097A7)
                                      : (isDarkMode ? Colors.white : Colors.grey[700]),
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList();
                  },
                ),
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
                          const Color(0xFFF5F7FA),
                          const Color(0xFFE8ECF1),
                          const Color(0xFFF5F7FA),
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
                            '正在加载单词...',
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : const Color(0xFF2C3E50),
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
                      padding: const EdgeInsets.fromLTRB(leftPadding, 2, rightPadding, 0),
                      child: renderPage(),
                    ),
            ),
            // 设置按钮 - 固定在右下角，使用 Column 垂直排列
            if (studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish)
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 设置按钮
                    FloatingActionButton(
                      mini: true,
                      heroTag: "settings",
                      child: const Icon(Icons.settings),
                      onPressed: () {
                        _showSettingsDialog();
                      },
                    ),
                    // 回到顶部按钮（仅在需要时显示）
                    if (showToTopBtn) ...[
                      const SizedBox(height: 4), // 减少按钮间距
                      FloatingActionButton(
                        mini: true,
                        heroTag: "toTop",
                        child: const Icon(Icons.arrow_upward),
                        onPressed: () {
                          // 置"请勿查询"标志，避免返回顶部时触发查询
                          doNotQueryPlease = true;

                          // 返回到顶部
                          itemScrollController.scrollTo(index: 0, duration: const Duration(milliseconds: 300), alignment: 0.5); // 显示在屏幕中部
                          setState(() {
                            showToTopBtn = false;
                          });

                          // 一段时间后，清除 "请勿查询"标志
                          Future.delayed(const Duration(milliseconds: 500), () {
                            doNotQueryPlease = false;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            // 回到顶部按钮（非背中文模式时单独显示）
            if (studyMode != WordListStudyMode.speakChinese && showToTopBtn)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  mini: true,
                  heroTag: "toTop",
                  child: const Icon(Icons.arrow_upward),
                  onPressed: () {
                    // 置"请勿查询"标志，避免返回顶部时触发查询
                    doNotQueryPlease = true;

                    // 返回到顶部
                    itemScrollController.scrollTo(index: 0, duration: const Duration(milliseconds: 300), alignment: 0.5); // 0.5表示中央对齐
                    setState(() {
                      showToTopBtn = false;
                    });

                    // 一段时间后，清除 "请勿查询"标志
                    Future.delayed(const Duration(milliseconds: 500), () {
                      doNotQueryPlease = false;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: null,
    ),
        // 新手引导覆盖层 - 在Scaffold之上，覆盖整个屏幕包括AppBar
        if (showGuide)
          _buildGuideOverlay(),
      ],
    );
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

  void _showSettingsDialog() {
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                studyMode == WordListStudyMode.speakEnglish ? '背英文模式设置' : '背中文模式设置',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              content: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish)
                      Row(
                        children: [
                          Icon(
                            mustAnswerAll ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 20,
                            color: mustAnswerAll ? const Color(0xFF4A90E2) : Colors.grey[600],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              mustAnswerAll ? '必须全部答对才跳转' : '答对一个即可跳转',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF2D3748),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: mustAnswerAll,
                            onChanged: (value) async {
                              var currentUser = Global.getLoggedInUser();
                              if (currentUser != null) {
                                // 旧字段已删除：此开关UI保留但不再修改本地用户字段
                                setState(() {});
                                setDialogState(() {});
                              }
                            },
                            activeColor: const Color(0xFF4A90E2),
                            activeTrackColor: const Color(0xFF4A90E2).withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    '关闭',
                    style: const TextStyle(
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
