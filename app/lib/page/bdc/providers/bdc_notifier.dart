import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_list/batch_words.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/router.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/phoneme_util.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/bdc_page_args.dart';
import '../models/word_ui_state.dart';
import 'bdc_state.dart';

part 'bdc_notifier.g.dart';

@riverpod
Asr asr(AsrRef ref) {
  return Asr();
}

@riverpod
class BdcNotifier extends _$BdcNotifier {
  int _stateChangeCount = 0;
  bool _isDisposed = false;
  bool _isSoundPlayingOrPending = false;
  bool _isAnswerCorrectHandling = false;
  DateTime? _lastCorrectSoundTime;

  void _updateState(BdcState newState, {String tag = ''}) {
    _stateChangeCount++;
    state = newState;
    if (tag.isNotEmpty) {
      debugPrint('⚡ [PERF] BdcNotifier.state #$_stateChangeCount tag=$tag');
    }
  }

  late Asr asr;
  late BdcPageArgs _args;
  Timer? _learningTimer;
  Timer? _persistTimer;
  Timer? _checkAsrDebounceTimer;
  /// 播放取消令牌：每次换词或用户手动操作时递增，使旧延迟 callback 失效。
  int _playToken = 0;
  /// 页面过渡屏障：详情页弹出时，让音频播放等待页面动画完成再启动，
  /// 避让 iOS 导航转场动画与 AVAudioSession 初始化在主线线程上冲突导致的爆音。
  Completer<void>? _pageTransitionBarrier;
  
  late final SpellingTextEditingController meaningController = SpellingTextEditingController(
    getTargetSpell: () => state.word?.spell,
    baseColor: AppTheme.primaryColor,
  );
  // 例句环节答案区(可编辑)独立控制器:识别结果写入此处,支持光标插入/手动编辑,
  // 避免与单词拼写 meaningController 的逐字符标色逻辑冲突。
  late final TextEditingController sentenceAnswerController = TextEditingController();
  
  String _handlingChinese = "";

  @override
  BdcState build() {
    asr = ref.watch(asrProvider);
    StudyAudioSessionController.instance.registerNotifier(this);
    
    // Initialize args
    final argsJson = Prefs.read<String>("BdcPageArgs");
    if (argsJson != null) {
      _args = BdcPageArgs.fromJson(argsJson);
    } else {
      _args = BdcPageArgs('unknown');
    }

    // Add ASR state listener
    asr.addStateListener(_onAsrStateChanged);
    
    meaningController.addListener(() {
      if (_pttSuppressAutoCheck) return; // PTT 按住期间抑制自动判定
      _checkAsrDebounceTimer?.cancel();
      _checkAsrDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        checkAsrResult();
      });
    });
    // 例句答案区手动编辑(PTT 未按住时)的自动判定监听
    sentenceAnswerController.addListener(() {
      if (_pttSuppressAutoCheck) return;
      if (!_isPttPressed && _isSentenceStepActive()) {
        _checkAsrDebounceTimer?.cancel();
        _checkAsrDebounceTimer = Timer(const Duration(milliseconds: 150), () {
          checkAsrResult(asrInput: sentenceAnswerController.text, isVoice: false, isFinal: true);
        });
      }
    });

    ref.onDispose(() {
      _isDisposed = true;
      _learningTimer?.cancel();
      _persistTimer?.cancel();
      _checkAsrDebounceTimer?.cancel();
      progressBarTapTimer?.cancel();
      _syncLearningTimeToDb();
      asr.removeStateListener(_onAsrStateChanged);
      // 物理释放麦克风，平滑物理淡出所有活跃音频流并物理释放硬件资源，防止退出页面后麦克风占用指示灯持续亮起
      unawaited(StudyAudioSessionController.instance.syncHardwareIntent(
        isInSpeakTab: false,
        isAnsweringActive: false,
        language: AsrLanguage.english,
        phrases: [],
        caller: this,
      ));
      meaningController.dispose();
      sentenceAnswerController.dispose();
      Prefs.remove("BdcPageArgs");
    });

    _startLearningTimer();

    return const BdcState();
  }

  DateTime? _lastSyncTime;
  String _accumulatedAsrText = "";
  String _lastFinalAsrText = "";

  /// 例句环节 PTT(按下说话):是否按住中
  bool _isPttPressed = false;

  /// 例句环节 PTT 会话轮次 token：每次 startPttAsr 递增。
  /// onAsrResult 的异步间隙(await 纠错)恢复后校验轮次是否仍为当前轮，
  /// 拦截"上一轮 stop 前已进入的事件在重按后继续写入"的跨轮污染
  int _pttRoundToken = 0;

  /// 例句补充模式锚点：按住 PTT 时答案区光标前后的文本。
  /// 本轮识别增量插入锚点之间，松开后拼成完整答案。
  String _pttAnchorPrefix = "";
  String _pttAnchorSuffix = "";

  /// PTT 按住期间抑制 meaningController/sentenceAnswerController 的
  /// 自动防抖判定(150ms)，避免识别文本写入时误触发判定；松开后由 stopPttAsr 统一判定
  bool _pttSuppressAutoCheck = false;

  void _onAsrStateChanged(AsrState asrState) {
    Future.microtask(() {
      if (_isDisposed) return;
      _updateState(state.copyWith(asrState: asrState), tag: 'asr-state');
    });
  }

  /// 是否处于例句环节且未答完(答案区可编辑/可补充)
  bool _isSentenceStepActive() {
    final step = state.studyStep;
    return (step == StudyStep.enSentence2Ch.json ||
            step == StudyStep.chSentence2En.json) &&
        !state.hasFinishedAnswering;
  }

  void _startLearningTimer() {
    _lastSyncTime = AppClock.now();
    _learningTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _syncLearningTimeToDb();
    });
  }

  Future<void> _syncLearningTimeToDb() async {
    if (_lastSyncTime == null) return;
    final now = AppClock.now();
    int secsToSync = now.difference(_lastSyncTime!).inSeconds;
    if (secsToSync <= 0) return;
    _lastSyncTime = now;

    try {
      final user = Global.getLoggedInUser();
      if (user == null) return;
      final dao = MyDatabase.instance.usersDao;
      final dbUser = await dao.getUserById(user.id);
      if (dbUser != null) {
        int todaySecs = dbUser.todayLearningSeconds ?? 0;
        if (dbUser.lastLearningDate != null) {
          final now = AppClock.now();
          if (dbUser.lastLearningDate!.year != now.year ||
              dbUser.lastLearningDate!.month != now.month ||
              dbUser.lastLearningDate!.day != now.day) {
            todaySecs = 0;
          }
        }

        final newTotal = (dbUser.totalLearningSeconds ?? 0) + secsToSync;
        final newToday = todaySecs + secsToSync;

        final updatedDbUser = dbUser.copyWith(
          totalLearningSeconds: drift.Value(newTotal),
          todayLearningSeconds: drift.Value(newToday),
        );

        await dao.saveUser(updatedDbUser, true);
        Global.updateUserCache(updatedDbUser);
        await MyDatabase.instance.userStudyDailyStatsDao.incrementSeconds(user.id, AppClock.now(), secsToSync);
      }
    } catch (e) {
      Global.logger.e("同步学习时长失败", error: e);
    }
  }

  Future<void> loadData(BuildContext context) async {
    if (state.dataLoaded || state.isGettingNextWord) return;
    final totalStopwatch = Stopwatch()..start();
    Api.setLoadingDisabled(true);
    
    // 极致优化：为了绝对保障批次第一个单词的发音稳定与流畅，我们将音效池的预热延后 2 秒（用户看词阶段）执行，
    // 彻底避开首词加载与发音播放的硬件黄金窗口，根治并发硬件抢占导致的破音。
    final ctrl = StudyAudioSessionController.instance;
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isDisposed && !ctrl.isSfxPoolFullyPrewarmed) {
        unawaited(ctrl.prewarm());
      }
    });

    bool dialogShown = false;
    Timer? dialogTimer;
    try {
      if (state.word == null) {
        state = state.copyWith(dataLoaded: false);
      }
      
      // 仅在非预加载且非 iOS (iPhone) 平台时展示加载弹窗。
      // iOS 端使用的是系统内置引擎，无预加载耗时，直接跳过弹窗以提供最流畅的进入体验。
      bool needPreload = !asr.isPreloaded && !PlatformUtils.isIOS;
      Future<void>? preloadFuture;
      if (!PlatformUtils.isIOS) {
        preloadFuture = asr.preloadModels();
      }
      // 预加载音素字典，延迟 1.5 秒等转场与首帧渲染完毕后再低优加载，避免阻塞进入页面首帧与过渡动画
      Timer(const Duration(milliseconds: 1500), () {
        PhonemeUtil.load();
      });

      if (context.mounted && needPreload && preloadFuture != null) {
        // 延迟 150ms 显示加载弹窗，如果在这期间模型预载完成了，就完全不弹窗，给用户最极致的流畅体验！
        dialogTimer = Timer(const Duration(milliseconds: 150), () async {
          if (context.mounted && !asr.isPreloaded) {
            final getWordsStopwatch = Stopwatch()..start();
            List<String> displayWords = await _getDisplayWords();
            debugPrint('⚡ [PERF] loadData -> _getDisplayWords cost: ${getWordsStopwatch.elapsedMilliseconds}ms');
            if (context.mounted && !asr.isPreloaded && !dialogShown) {
              _showLoadingDialog(context, displayWords);
              dialogShown = true;
            }
          }
        });
      }
      
      if (preloadFuture != null) {
        final preloadStopwatch = Stopwatch()..start();
        await preloadFuture;
        debugPrint('⚡ [PERF] loadData -> asr.preloadModels cost: ${preloadStopwatch.elapsedMilliseconds}ms');
        dialogTimer?.cancel(); // 模型加载完成后，立即取消弹窗定时器
        if (needPreload) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
      
      // 彻底将音频会话配置异步化抛入后台，避免页面转场滑出期间音频硬件重新配置导致丢帧
      unawaited(StudyAudioSessionController.instance.configureSession());
      
      final studyConfig = StudyConfig.fromCurrentUser();
      
      state = state.copyWith(
        asrPassRuleCache: studyConfig.asrPassRule,
        autoJumpAfterCorrectCh2En: studyConfig.autoJumpAfterCorrectCh2En,
        autoJumpAfterCorrectEn2Ch: studyConfig.autoJumpAfterCorrectEn2Ch,
      );

      final stepsStopwatch = Stopwatch()..start();
      var stepsResult = await StudyBo().getActiveUserStudySteps();
      debugPrint('⚡ [PERF] loadData -> getActiveUserStudySteps cost: ${stepsStopwatch.elapsedMilliseconds}ms');
      if (!stepsResult.success || stepsResult.data == null) {
        if (context.mounted && dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        ToastUtil.error(stepsResult.msg ?? '获取学习步骤失败');
        return;
      }
      state = state.copyWith(activeUserStudySteps: stepsResult.data!, loadError: null);

      final nextWordStopwatch = Stopwatch()..start();
      bool success = await getNextWord(false);
      debugPrint('⚡ [PERF] loadData -> getNextWord cost: ${nextWordStopwatch.elapsedMilliseconds}ms');
      
      if (context.mounted && dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (success) {
        await _restoreLastWordHistory();
      }
      
      // Use state directly after getNextWord
      if (state.word != null) {
        state = state.copyWith(dataLoaded: true);
      } else if (state.loadError != null) {
        // If it's a redirecting message, keep dataLoaded false to show spinner
        // Otherwise, it's a real error we want to show
        if (!state.loadError!.contains('跳转')) {
          state = state.copyWith(dataLoaded: true);
        }
      } else if (!success) {
        Global.logger.e('loadData: getNextWord failed without loadError. State: word=${state.word}');
        state = state.copyWith(
          loadError: '获取单词失败，请检查网络后重试',
          dataLoaded: true,
        );
      }
    } catch (e, st) {
      if (context.mounted && dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      state = state.copyWith(loadError: e.toString(), dataLoaded: true);
      ErrorHandler.handleError(e, st, logPrefix: 'loadData');
    } finally {
      dialogTimer?.cancel(); // 兜底取消定时器，防止泄露或延迟弹窗
      Api.setLoadingDisabled(false);
      Global.logger.i('⚡ [PERF] Total loadData cost: ${totalStopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<List<String>> _getDisplayWords() async {
    final stopwatch = Stopwatch()..start();
    List<String> displayWords = [];
    try {
      final db = MyDatabase.instance;
      final user = await db.usersDao.getLastLoggedInUser();
      if (user != null) {
        final todayWords = await (db.select(db.learningWords)
              ..where((tbl) => tbl.userId.equals(user.id) & tbl.batchId.isBiggerThanValue(0)))
            .get();
        
        var newWords = todayWords.where((w) => w.state == 0).toList()..shuffle();
        var reviewWords = todayWords.where((w) => w.state != 0).toList()..shuffle();
        
        var selectedWords = [...newWords.take(5)];
        if (selectedWords.length < 5) {
          selectedWords.addAll(reviewWords.take(5 - selectedWords.length));
        }
        
        for (var w in selectedWords) {
          final wordItem = await db.wordsDao.getWordById(w.wordId);
          if (wordItem != null && wordItem.spell.isNotEmpty) {
            displayWords.add(wordItem.spell);
          }
        }
      }
    } catch (e) {
      Global.logger.e('获取展示单词失败: $e');
    }
    debugPrint('⚡ [PERF] _getDisplayWords cost: ${stopwatch.elapsedMilliseconds}ms');
    return displayWords;
  }

  void _showLoadingDialog(BuildContext context, List<String> displayWords) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text("语音识别引擎", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 8),
                  Text("正在准备离线识别模型...", style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.5))),
                  if (displayWords.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    ...displayWords.map((word) => Text(word, style: const TextStyle(fontSize: 20, color: AppTheme.primaryColor))),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _restoreLastWordHistory() async {
    try {
      final lastWordDataStr = Prefs.read<String>('last_word_history_item');
      if (lastWordDataStr != null) {
        final lastWordData = json.decode(lastWordDataStr);
        final wordResult = GetWordResult.fromJson(lastWordData['wordResult']);
        final stateJson = lastWordData['state'];

        final wordUIState = WordUIState(
          hasFinishedAnswering: stateJson['hasFinishedAnswering'] ?? false,
          canLeaveCurrWord: stateJson['canLeaveCurrWord'] ?? false,
          showSentenceTranslation: stateJson['showSentenceTranslation'] ?? false,
          selectedAnswerIndex: stateJson['selectedAnswerIndex'],
          flippedAnswerIndices: Set<int>.from(stateJson['flippedAnswerIndices'] ?? []),
          tabIndex: stateJson['tabIndex'] ?? 0,
          currentScore: stateJson['currentScore'],
          meaningText: stateJson['meaningText'] ?? '',
          correctAnswerIndex: stateJson['correctAnswerIndex'] ?? 0,
          fsrsItem: stateJson['fsrsItem'] != null ? FSRSItem.fromMap(stateJson['fsrsItem']) : null,
          daysSinceLastReview: stateJson['daysSinceLastReview'],
          lastFsrsRating: stateJson['lastFsrsRating'] != null ? FsrsRating.values[stateJson['lastFsrsRating'] as int] : null,
          hintTapCount: stateJson['hintTapCount'] ?? 0,
        );

        final wordId = wordResult.learningWord?.word.id;
        if (wordId != null) {
          // 检查该词是否已被掌握，若是则跳过恢复，避免已掌握单词重新出现在回看历史中
          final user = Global.getLoggedInUser();
          if (user != null) {
            final isMastered = await MyDatabase.instance.masteredWordsDao.isWordMastered(user.id, wordId);
            if (isMastered) {
              Global.logger.d('💡 _restoreLastWordHistory: 跳过已掌握单词 $wordId');
              return;
            }
          }
          state = state.copyWith(
            history: [...state.history, wordResult],
            wordUIStates: {...state.wordUIStates, wordId: wordUIState},
          );
        }
      }
    } catch (e) {
      Global.logger.e('恢复上一个单词的历史状态失败: $e');
    }
  }

  Future<bool> handleWord(GetWordResult? getWordResult, {bool isFromBatchWordList = false}) async {
    if (getWordResult == null) return false;
    _isAnswerCorrectHandling = false; // 新词开始，安全重置答对锁
    _lastCorrectSoundTime = null; // 重置正确反馈音播放时间
    final totalStopwatch = Stopwatch()..start();
    
    // 防止处理同一个结果引发的循环
    if (getWordResult == state.currentGetWordResult && !isFromBatchWordList) {
      return true;
    }
    
    if (getWordResult.finished) {
      state = state.copyWith(
        loadError: '学习已完成',
        word: null,
        wordWrapper: null,
      );
      goRouter.pushReplacement("/finish");
      return false;
    } else if (getWordResult.noWord) {
      state = state.copyWith(
        loadError: '当前书本没有正在学习的单词',
        word: null,
        wordWrapper: null,
      );
      goRouter.push("/select_book");
      return false;
    }

    state = state.copyWith(buttonsEnabled: false);
    Future.delayed(const Duration(milliseconds: 500), () {
      state = state.copyWith(buttonsEnabled: true);
    });

    final currentStep = state.activeUserStudySteps[getWordResult.stepIndex].studyStep;
    if (currentStep == 'List') {
      state = state.copyWith(
        loadError: '正在跳转到单词列表...',
        word: null,
        wordWrapper: null,
      );
      
      // 开启麦克风保温以跨越列表页
      StudyAudioSessionController.instance.keepMicrophoneWarm = true;
      
      // Redirect to batch word list
      Future.delayed(Duration.zero, () {
        final nextBtn = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () async {
            StudyAudioSessionController.instance.keepMicrophoneWarm = true;
            await StudyBo().completeListStepForCurrentBatch();
            // 跳转回 BDC 页面，它会自动加载下一个非 List 环节的单词
            goRouter.pushReplacement('/bdc');
          },
          child: const Text('下一组', style: TextStyle(fontWeight: FontWeight.bold)),
        );
        
        final batchId = getWordResult.learningWord?.batchId;
        final learningOrder = getWordResult.learningWord?.learningOrder;
        final startIndex = learningOrder != null ? learningOrder - 1 : 0;
        goRouter.pushReplacement('/word_list',
          extra: WordListPageArgs(
            '本组单词',
            StageWordsProvider(),
            true, // showBackBtn
            true, // showDelBtn
            true, // showWordProgress
            '掌握度',
            StageWordsProgressProvider(),
            StageWordsBookMarkProvider(batchId: batchId, batchStartIndex: startIndex),
            nextBtn,
            showAiStory: true
          )
        );
      });
      return false;
    }

    String? oldStudyStep = state.studyStep;
    String newStudyStep = state.activeUserStudySteps[getWordResult.stepIndex].studyStep;
    
    if (asr.state == AsrState.started) {
      await StudyAudioSessionController.instance.syncHardwareIntent(
        isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
        isAnsweringActive: false,
        language: AsrLanguage.english,
        phrases: [],
        caller: this,
      );
    }

    if (oldStudyStep != newStudyStep || isFromBatchWordList) {
      final asrInitStopwatch = Stopwatch()..start();
      await asr.initAsr(onAsrResult);
      Global.logger.d('[PERF] handleWord -> asr.initAsr cost: ${asrInitStopwatch.elapsedMilliseconds}ms');
    }

    WordVo word = getWordResult.learningWord!.word;
    
    if (word.spell.isEmpty) {
      final dbStopwatch = Stopwatch()..start();
      final local = await MyDatabase.instance.wordsDao.getWordById(word.id!);
      if (local != null) {
        word.spell = local.spell;
        word.shortDesc = local.shortDesc;
        word.pronounce = local.pronounce;
        word.britishPronounce = local.britishPronounce;
        word.americaPronounce = local.americaPronounce;
      }
      final user = Global.getLoggedInUser();
      if (user != null) {
        word.meaningItems = await WordBo().getMeaningItemsForWord(word.id!, user.id);
      }
      Global.logger.d('[PERF] handleWord -> fetch local word/meaning items cost: ${dbStopwatch.elapsedMilliseconds}ms');
    }

    WordWrapper wordWrapper = WordWrapper(word, null);
    
    bool speakTabAvailable = _getShouldShowSpeakTabFor(newStudyStep);
    final bool isSentenceStep = newStudyStep == StudyStep.enSentence2Ch.json || newStudyStep == StudyStep.chSentence2En.json;
    int newTabIndex = 0;
    if (state.isSelectModePreferred && !isSentenceStep) {
      newTabIndex = speakTabAvailable ? 1 : 0;
    }

    _accumulatedAsrText = "";
    _lastFinalAsrText = "";
    sentenceAnswerController.text = ""; // 新单词重置例句答案区

    state = state.copyWith(
      currentGetWordResult: getWordResult,
      word: word,
      wordWrapper: wordWrapper,
      studyStep: newStudyStep,
      canLeaveCurrWord: false,
      hasFinishedAnswering: false,
      selectedAnswerIndex: null,
      correctAnswerIndex: null,
      words: null,
      flippedAnswerIndices: {},
      showAnswerButtons: false,
      showSentenceTranslation: false,
      currentScore: null,
      englishDigestOfFirstSentence: null,
      aiRefereeFeedback: null,
      wordStartTime: AppClock.now(),
      fsrsItem: null,
      lastFsrsRating: null,
      currentAsrCandidates: [],
      loadError: null, // Successfully loaded a word, clear error
      tabIndex: newTabIndex,
      showHandwritingBoard: false,
      isKeyboardVisible: false,
      hintTapCount: 0,
      isWordMastered: false,
      isPttPressed: false,
    );

    final wordId = word.id;
    if (state.wordUIStates.containsKey(wordId)) {
      _restoreWordState(getWordResult);
    } else {
      meaningController.text = "";
      sentenceAnswerController.text = ""; // 新单词重置例句答案区
    }

    if (state.wordWrapper != null) {
      final previousUIState = state.wordUIStates[word.id];
      if (previousUIState != null) {
        if (previousUIState.asrMatchedMeaningItemParts != null) {
          state.wordWrapper!.asrMatchedMeaningItemParts.addAll(previousUIState.asrMatchedMeaningItemParts!);
        }
        if (previousUIState.asrRevealedMeaningItemParts != null) {
          state.wordWrapper!.asrRevealedMeaningItemParts.addAll(previousUIState.asrRevealedMeaningItemParts!);
        }
      }
    }

    String? englishDigest;
    final sentenceStopwatch = Stopwatch()..start();
    final sentences = await word.getSentences();
    if (sentences.isNotEmpty) englishDigest = sentences[0].englishDigest;
    state = state.copyWith(englishDigestOfFirstSentence: englishDigest);
    Global.logger.d('[PERF] handleWord -> getSentences cost: ${sentenceStopwatch.elapsedMilliseconds}ms');

    if (state.words == null) {
      _initChoiceData(getWordResult);
    }

    state = state.copyWith(dataLoaded: true);

    // 优化：彻底取消在切词时针对每个单词的后台 setAudioSource 预热，
    // 根治预热任务与后续播放任务高频并发撞车导致的 Loading interrupted 调试断点异常

    // iOS 说模式引擎预热在发音播放完成后进行，避免提前抢占 AudioSession
    //（将 session 切为 playAndRecord）导致后续发音播放时 session 状态不匹配产生爆音。
    // 例句环节采用 PTT（按下说话）完全手动控制，不自动开麦。
    final bool shouldSpeak = !isSentenceStep && _shouldShowSpeakTab && state.tabIndex == 0;

    // 将发音播放和 ASR 启动延迟 200ms 执行，在卡片过渡动画结束前不抢占渲染资源。
    // 使用 _playToken 防止快速切词时旧 callback 使用过期 state。
    final token = ++_playToken;
    _isSoundPlayingOrPending = true; // 开启播放及自动开麦保护
    Future.delayed(const Duration(milliseconds: 200), () async {
      if (_playToken != token || _isDisposed) {
        _isSoundPlayingOrPending = false;
        return;
      }
      final playStopwatch = Stopwatch()..start();
      try {
        // 页面过渡屏障：如果详情页弹出动画仍在进行，等待其完成再播放，
        // 避免 iOS 导航转场与音频初始化在主线程竞争导致爆音。
        if (_pageTransitionBarrier != null) {
          debugPrint('🕵️ [AudioDiag] handleWord.delayedCallback.waitingTransition');
          await _pageTransitionBarrier!.future;
          if (_playToken != token || _isDisposed) {
            _isSoundPlayingOrPending = false;
            return;
          }
          debugPrint('🕵️ [AudioDiag] handleWord.delayedCallback.transitionDone');
        }

        debugPrint('🕵️ [AudioDiag] handleWord.delayedCallback.enter | word=${state.word?.spell} shouldSpeak=$shouldSpeak');
        try { await StudyAudioSessionController.instance.cancelPlayback(); } catch (_) {}
        debugPrint('🕵️ [AudioDiag] handleWord.delayedCallback.afterCancelPlayback');
        await playWordAndFirstSentence(false, shouldSpeak);
        // 麦克风预热由 playWordAndFirstSentence 内部的 _handleTabChangeForAsr
        // 通过状态机统一管理，无需此处再额外调用 warmupMicrophone，
        // 避免与状态机冲突产生音频瞬态杂音。
      } catch (e, st) {
        Global.logger.e('后台播放单词发音及开启 ASR 失败', error: e, stackTrace: st);
      } finally {
        if (_playToken == token) {
          _isSoundPlayingOrPending = false;
        }
        Global.logger.d('[PERF] handleWord -> playWordAndFirstSentence (background) cost: ${playStopwatch.elapsedMilliseconds}ms');
      }
    });
    
    Global.logger.i('[PERF] Total handleWord cost: ${totalStopwatch.elapsedMilliseconds}ms');
    return true;
  }

  void _initChoiceData(GetWordResult getWordResult) {
    if (getWordResult.otherWords == null || getWordResult.otherWords!.length < 2) return;

    List<WordVo> words = [state.word!, ...getWordResult.otherWords!];
    words.shuffle();

    int correctIndex = words.indexOf(state.word!) + 1;

    if (StudyConfig.fromCurrentUser().enableAllWrong) {
      var rnd = Random();
      var indexToDelete = rnd.nextInt(words.length);
      bool correctWasDeleted = indexToDelete == (correctIndex - 1);
      words.removeAt(indexToDelete);
      
      var mockWord = WordVo.c2("[ 都不对 ]");
      mockWord.setMeaningStr("[ 都不对 ]");
      words.add(mockWord);
      
      if (correctWasDeleted) {
        correctIndex = words.length;
      } else {
        correctIndex = words.indexOf(state.word!) + 1;
      }
    }

    state = state.copyWith(words: words, correctAnswerIndex: correctIndex);
  }

  /// 当前是否为例句巩固环节（非测评，仅为练习）。
  /// 条件：例句步骤 (EnSentence2Ch / ChSentence2En) 且不是第一个环节 (stepIndex > 0)。
  bool _isSentencePracticeStep() {
    final step = state.studyStep;
    if (step != StudyStep.enSentence2Ch.json && step != StudyStep.chSentence2En.json) {
      return false;
    }
    return (state.currentGetWordResult?.stepIndex ?? 0) > 0;
  }

  void updateTabIndex(int index) {
    // Determine if the user is choosing the "Select" tab (always the last tab)
    final isSelectTab = index == (_shouldShowSpeakTab ? 1 : 0);
    // 切换 Tab 即视为松开 PTT（防止切到"选"Tab 后例句环节识别仍在继续）
    if (_isPttPressed) {
      _isPttPressed = false;
      unawaited(asr.stopAsr());
    }
    state = state.copyWith(tabIndex: index, isSelectModePreferred: isSelectTab, isPttPressed: _isPttPressed);
    _handleTabChangeForAsr();
  }

  void revealAnswerAndMarkWrong(BuildContext context) {
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;



    // 强制关闭 ASR 识别
    StudyAudioSessionController.instance.syncHardwareIntent(
      isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
      isAnsweringActive: false,
      language: AsrLanguage.english,
      phrases: [],
      caller: this,
    );

    // 设置已完成回答状态，评分为 FsrsRating.again，显示正确答案
    // 例句巩固环节仅为练习，不降低评分
    final bool isSentencePractice = _isSentencePracticeStep();
    state = state.copyWith(
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      lastFsrsRating: isSentencePractice ? null : FsrsRating.again,
      lastFsrsRatingReason: isSentencePractice ? "手动查看答案（练习模式）" : "手动查看答案",
      currentScore: 0, // 分数设为 0 代表未读对
    );
    _handleTabChangeForAsr();
  }

  void onAnswerClicked(int index, BuildContext context) async {
    if (state.selectedAnswerIndex != null) {
      int wordIdx = index - 1;
      if (state.words != null && wordIdx >= 0 && wordIdx < state.words!.length) {
        if (state.words![wordIdx].spell == "[ 都不对 ]") return;
        final flipped = Set<int>.from(state.flippedAnswerIndices);
        if (flipped.contains(wordIdx)) {
          flipped.remove(wordIdx);
        } else {
          flipped.add(wordIdx);
        }
        state = state.copyWith(flippedAnswerIndices: flipped);
      }
      return;
    }
    
    if (state.hasFinishedAnswering) {
      int wordIdx = index - 1;
      final flipped = Set<int>.from(state.flippedAnswerIndices);
      if (state.words != null && wordIdx >= 0 && wordIdx < state.words!.length) {
        if (state.words![wordIdx].spell != "[ 都不对 ]") {
          flipped.add(wordIdx);
        }
      }
      state = state.copyWith(selectedAnswerIndex: index, flippedAnswerIndices: flipped);
      return;
    }

    state = state.copyWith(selectedAnswerIndex: index);
    bool correct = index == state.correctAnswerIndex;
    if (correct) {
      final ratingResult = _calculateRating("选择题");
      _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
    } else {
      StudyAudioSessionController.instance.playSoundEffect('failed.mp3', speed: 1.5, volume: 1.0);
      // 例句巩固环节仅为练习，错选不降低评分
      final bool isSentencePractice = _isSentencePracticeStep();
      showWordDetail(state.word!, true, context,
          fsrsRating: isSentencePractice ? null : FsrsRating.again,
          reason: isSentencePractice ? "选错了答案（练习模式）" : "选错了答案");
    }
  }

  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, BuildContext context, {FsrsRating? fsrsRating, String? reason}) async {
    debugPrint('🕵️ [AudioDiag] showWordDetail.enter | word=${word.spell} isAnswerWrong=$isAnswerWrong');
    // 强制并平滑地关闭正在播放的音频与清理 ASR。通过 Future.wait 并行执行，并设置 1.5s 的硬超时，
    // 防止底层系统音频驱动卡死阻塞跳转页面。
    try {
      await Future.wait([
        StudyAudioSessionController.instance.cancelPlayback(),
        asr.stopAsr(),
        asr.reset(),
      ]).timeout(const Duration(milliseconds: 1500));
    } catch (e) {
      Global.logger.w('showWordDetail: clean up ASR/playback failed or timed out: $e');
    }

    _playToken++; // 取消任何待执行的自动播放延迟 callback，防止详情页与主页延迟自动播放并发撞车

    if (fsrsRating != null) {
      if (state.studyStep == StudyStep.en2Ch.json && state.wordWrapper != null) {
        state.wordWrapper!.revealAllRemainingMeanings();
      }
      state = state.copyWith(
        lastFsrsRating: fsrsRating,
        lastFsrsRatingReason: reason,
        hasFinishedAnswering: true,
        canLeaveCurrWord: true,
      );
      _updateFsrsPreview(fsrsRating);
    }
    
    final barrier = Completer<void>();
    _pageTransitionBarrier = barrier;
    final result = await goRouter.push<bool>('/word_detail', extra: WordDetailPageArgs(word, false, null, isAnswerWrong,
        showNextWordButton: true,
        sessionController: StudyAudioSessionController.instance,
        onNextWord: () => getNextWord(true, fsrsRating: state.lastFsrsRating, fastPath: false)));
    
    if (_isDisposed) return;

    if (result == true) {
      // onNextWord 已在弹窗前执行了 getNextWord，此时 handleWord 的延时 callback
      // 正等待 _pageTransitionBarrier。延迟 300ms 让 pop 动画完全结束再放行。
      Future.delayed(const Duration(milliseconds: 300), () {
        barrier.complete();
        if (!_isDisposed) _pageTransitionBarrier = null;
      });
    } else {
      barrier.complete();
      _pageTransitionBarrier = null;
      _handleTabChangeForAsr();
    }
  }

  void _updateFsrsPreview(FsrsRating rating) {
    final lw = state.currentGetWordResult?.learningWord;
    if (lw != null) {
      final fsrs = FSRS();
      int days = state.daysSinceLastReview ?? 0;
      FSRSItem nextItem;
      if (lw.stability == null || lw.stability == 0.0) {
        nextItem = fsrs.init(rating);
      } else {
        final prevItem = FSRSItem(
          stability: lw.stability!,
          difficulty: lw.difficulty!,
          elapsedDays: days,
          scheduledDays: lw.scheduledDays ?? 0,
          reps: lw.reps ?? 0,
          lapses: lw.lapses ?? 0,
          state: FsrsState.values[lw.state ?? 0],
        );
        nextItem = fsrs.next(prevItem, rating, days);
      }

      state = state.copyWith(fsrsItem: nextItem);
    }
  }

  void updateFsrsRating(FsrsRating rating) {
    state = state.copyWith(lastFsrsRating: rating);
    _updateFsrsPreview(rating);
  }

  void giveALittleHint() {
    if (state.wordWrapper != null) {
      final wrapper = state.wordWrapper!;
      wrapper.hintLetterCount++;
      state = state.copyWith(
        wordWrapper: wrapper,
        hintTapCount: state.hintTapCount + 1,
        isUpdatingByHint: !state.isUpdatingByHint,
      );
      if (state.studyStep == StudyStep.ch2En.json || state.showHandwritingBoard) {
        meaningController.text = state.word!.spell.substring(0, min(wrapper.hintLetterCount, state.word!.spell.length));
      }
    }
  }

  void giveFullHint() {
    if (state.wordWrapper != null) {
      final wrapper = state.wordWrapper!;
      wrapper.hintLetterCount = state.word!.spell.length;
      state = state.copyWith(
        wordWrapper: wrapper,
        hintTapCount: 2,
        isUpdatingByHint: !state.isUpdatingByHint,
      );
      if (state.studyStep == StudyStep.ch2En.json || state.showHandwritingBoard) {
        meaningController.text = state.word!.spell;
      }
    }
  }

  void clearHint() {
    if (state.wordWrapper != null) {
      final wrapper = state.wordWrapper!;
      wrapper.hintLetterCount = 0;
    _accumulatedAsrText = "";
    _lastFinalAsrText = "";
    sentenceAnswerController.text = ""; // 清空例句答案区
    // 换词即视为松开 PTT：防止按住时自动进下一词导致 _isPttPressed 残留、新词例句环节误自动开麦
    _isPttPressed = false;
      state = state.copyWith(
        wordWrapper: wrapper,
        isUpdatingByHint: !state.isUpdatingByHint,
        currentAsrCandidates: [],
      );
      if (state.studyStep == StudyStep.ch2En.json || state.showHandwritingBoard) {
        meaningController.text = '';
      }
    }
  }

  void toggleSentenceTranslation() {
    state = state.copyWith(showSentenceTranslation: !state.showSentenceTranslation);
  }

  void toggleHandwritingBoard() {
    state = state.copyWith(showHandwritingBoard: !state.showHandwritingBoard);
    _handleTabChangeForAsr();
  }

  void updateIsKeyboardVisible(bool visible) {
    state = state.copyWith(isKeyboardVisible: visible);
    _syncAudioHardware();
  }

  void goToPreviousWord() async {
    if (state.history.isEmpty) return;

    _saveCurrentWordState();
    await StudyAudioSessionController.instance.syncHardwareIntent(
      isInSpeakTab: false,
      isAnsweringActive: false,
      language: AsrLanguage.english,
      phrases: [],
      caller: this,
    );
    await StudyAudioSessionController.instance.cancelPlayback();

    int nextIndex;
    if (state.historyIndex == -1) {
      nextIndex = state.history.length - 1;
      state = state.copyWith(reviewReturnTarget: state.currentGetWordResult);
    } else if (state.historyIndex > 0) {
      nextIndex = state.historyIndex - 1;
    } else {
      return;
    }

    state = state.copyWith(historyIndex: nextIndex);
    handleWord(state.history[nextIndex]);
  }

  void exitReviewMode() async {
    if (state.historyIndex == -1) return;
    
    final target = state.reviewReturnTarget;
    if (target == null) {
      await getNextWord(false);
      return;
    }

    _saveCurrentWordState();
    await StudyAudioSessionController.instance.syncHardwareIntent(
      isInSpeakTab: false,
      isAnsweringActive: false,
      language: AsrLanguage.english,
      phrases: [],
      caller: this,
    );
    await StudyAudioSessionController.instance.cancelPlayback();
    
    state = state.copyWith(historyIndex: -1);
    await handleWord(target, isFromBatchWordList: true);
  }
  Future<void> reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }



  void _persistLastWordHistoryItem() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 1), () {
      _executePersistLastWordHistoryItem();
    });
  }

  /// 直接持久化指定的历史条目（不经过定时器），用于掌握操作后同步更新
  void _persistLastWordHistoryItemWith(GetWordResult wordResult, WordUIState uiState) {
    try {
      final targetWord = wordResult.learningWord?.word;
      final others = wordResult.otherWords;

      final lastWordData = {
        'wordResult': wordResult.toJson(),
        'state': {
          'hasFinishedAnswering': uiState.hasFinishedAnswering,
          'canLeaveCurrWord': uiState.canLeaveCurrWord,
          'showSentenceTranslation': uiState.showSentenceTranslation,
          'selectedAnswerIndex': uiState.selectedAnswerIndex,
          'flippedAnswerIndices': uiState.flippedAnswerIndices.toList(),
          'tabIndex': uiState.tabIndex,
          'currentScore': uiState.currentScore,
          'meaningText': uiState.meaningText,
          'correctAnswerIndex': uiState.correctAnswerIndex,
          'fsrsItem': uiState.fsrsItem?.toMap(),
          'daysSinceLastReview': uiState.daysSinceLastReview,
          'lastFsrsRating': uiState.lastFsrsRating?.index,
          'currentAsrCandidates': uiState.currentAsrCandidates,
          'hintTapCount': uiState.hintTapCount,
          'wordsIndices': uiState.words?.map((w) {
            if (w.spell == "[ 都不对 ]") return 3;
            if (targetWord != null && w.id == targetWord.id) return 0;
            if (others != null && others.isNotEmpty && w.id == others[0].id) return 1;
            if (others != null && others.length > 1 && w.id == others[1].id) return 2;
            return -1;
          }).toList(),
        }
      };
      final jsonStr = json.encode(lastWordData);
      Prefs.write('last_word_history_item', jsonStr);
    } catch (e) {
      Global.logger.e('_persistLastWordHistoryItemWith 失败: $e');
    }
  }

  void _executePersistLastWordHistoryItem() {
    final sw = Stopwatch()..start();
    try {
      final wordId = state.word?.id;
      final uiState = wordId != null ? state.wordUIStates[wordId] : null;
      if (uiState != null && state.currentGetWordResult != null) {
        final targetWord = state.currentGetWordResult!.learningWord?.word;
        final others = state.currentGetWordResult!.otherWords;
        
        final lastWordData = {
          'wordResult': state.currentGetWordResult!.toJson(),
          'state': {
            'hasFinishedAnswering': uiState.hasFinishedAnswering,
            'canLeaveCurrWord': uiState.canLeaveCurrWord,
            'showSentenceTranslation': uiState.showSentenceTranslation,
            'selectedAnswerIndex': uiState.selectedAnswerIndex,
            'flippedAnswerIndices': uiState.flippedAnswerIndices.toList(),
            'tabIndex': uiState.tabIndex,
            'currentScore': uiState.currentScore,
            'meaningText': uiState.meaningText,
            'correctAnswerIndex': uiState.correctAnswerIndex,
            'fsrsItem': uiState.fsrsItem?.toMap(),
            'daysSinceLastReview': uiState.daysSinceLastReview,
            'lastFsrsRating': uiState.lastFsrsRating?.index,
            'currentAsrCandidates': uiState.currentAsrCandidates,
            'hintTapCount': uiState.hintTapCount,
            'wordsIndices': uiState.words?.map((w) {
              if (w.spell == "[ 都不对 ]") return 3;
              if (targetWord != null && w.id == targetWord.id) return 0;
              if (others != null && others.isNotEmpty && w.id == others[0].id) return 1;
              if (others != null && others.length > 1 && w.id == others[1].id) return 2;
              return -1;
            }).toList(),
          }
        };
        final encodeSw = Stopwatch()..start();
        final jsonStr = json.encode(lastWordData);
        final encodeCost = encodeSw.elapsedMilliseconds;
        
        final writeSw = Stopwatch()..start();
        Prefs.write('last_word_history_item', jsonStr).then((_) {
          debugPrint('⚡ [PERF] _persistLastWordHistoryItem -> Prefs.write cost: ${writeSw.elapsedMilliseconds}ms');
        });
        debugPrint('⚡ [PERF] _persistLastWordHistoryItem -> JSON encode cost: ${encodeCost}ms, total dispatch sync cost: ${sw.elapsedMilliseconds}ms');
      }
    } catch (e) {
      Global.logger.e('持久化上一个单词失败: $e');
    }
  }


  void _restoreWordState(GetWordResult result) {
    final sw = Stopwatch()..start();
    final wordId = result.learningWord?.word.id;
    final uiState = wordId != null ? state.wordUIStates[wordId] : null;
    if (uiState != null) {
      // 按环节索引比较：相同 stepIndex 视为同环节，恢复完整答题状态
      // 不同 stepIndex（如测评→巩固）只恢复选项，重置答题状态，并将旧评分提取为测评参考
      if (uiState.stepIndex == result.stepIndex) {
        state = state.copyWith(
          hasFinishedAnswering: uiState.hasFinishedAnswering,
          canLeaveCurrWord: uiState.canLeaveCurrWord,
          showSentenceTranslation: uiState.showSentenceTranslation,
          selectedAnswerIndex: uiState.selectedAnswerIndex,
          flippedAnswerIndices: uiState.flippedAnswerIndices,
          tabIndex: uiState.tabIndex,
          currentScore: uiState.currentScore,
          words: uiState.words,
          correctAnswerIndex: uiState.correctAnswerIndex,
          fsrsItem: uiState.fsrsItem,
          daysSinceLastReview: uiState.daysSinceLastReview,
          lastFsrsRating: uiState.lastFsrsRating,
          currentAsrCandidates: uiState.currentAsrCandidates ?? [],
          hintTapCount: uiState.hintTapCount,
          isWordMastered: false,
        );
        meaningController.text = uiState.meaningText;
      } else {
        // 环节不同（如测评→巩固），重置答题状态，将旧评分提取为测评参考
        // 同时将测评的评分和 fsrsItem 作为巩固环节的默认值带出，
        // 让评分修正对话框默认选中测评评分，并用测评的下次复习天数做预览
        state = state.copyWith(
          words: uiState.words,
          correctAnswerIndex: uiState.correctAnswerIndex,
          hasFinishedAnswering: false,
          canLeaveCurrWord: false,
          selectedAnswerIndex: null,
          flippedAnswerIndices: {},
          currentScore: null,
          lastFsrsRating: uiState.lastFsrsRating,
          fsrsItem: uiState.fsrsItem,
          hintTapCount: 0,
          assessmentRating: uiState.lastFsrsRating,
          assessmentScheduledDays: uiState.fsrsItem?.scheduledDays,
          isWordMastered: false,
        );
        meaningController.text = "";
        sentenceAnswerController.text = "";
      }
      debugPrint('⚡ [PERF] _restoreWordState cost: ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<bool> getNextWord(bool gotoNext, {FsrsRating? fsrsRating, bool fastPath = false}) async {
    if (state.isGettingNextWord) return false;
    final totalStopwatch = Stopwatch()..start();
    debugPrint('🕵️ [AudioDiag] getNextWord.enter | gotoNext=$gotoNext fastPath=$fastPath word=${state.word?.spell}');

    _saveCurrentWordState();
    _playToken++; // 取消任何待执行的自动播放延迟 callback

    // 快速通道（详情页预拉取）：跳过音频/ASR 清理和视觉驻留，仅做数据加载。
    if (!fastPath) {
      // 切换单词的一瞬间，强行、立即关停上一个单词的音频播放，
      // 使得 SoundUtil.waitForAllPlayers 判定无活跃播放器，从而闪电完成 AudioSession 切换！
      try {
        unawaited(StudyAudioSessionController.instance.cancelPlayback());
      } catch (_) {}

      // 答对单词后切换下一词前的视觉驻留延迟。
      // Ch2En 模式（说英文）发音已播完提供充足的驻留时长，无需额外等待；
      // 其他模式（如 En2Ch）仅播短促提示音，保留 50ms 缓冲让用户看一眼评分。
      if (gotoNext && state.word != null) {
        final dwellMs = state.studyStep == StudyStep.ch2En.json ? 0 : 50;
        if (dwellMs > 0) await Future.delayed(Duration(milliseconds: dwellMs));
      }
    }

    if (state.historyIndex != -1) {
      if (gotoNext) {
        final lw = state.currentGetWordResult?.learningWord;

        // 回看模式下点击掌握：保存已掌握状态，并从历史中移除以避免回看时再次出现
        bool didMaster = false;
        if (state.isWordMastered && lw != null) {
          await StudyBo().markWordAsMastered(lw);
          final filteredHistory = state.history
              .where((item) => item.learningWord?.word.id != lw.word.id)
              .toList();
          state = state.copyWith(history: filteredHistory);

          // 同步更新持久化的历史记录：取消待执行定时器，用过滤后的最后一项替换或清除
          _persistTimer?.cancel();
          if (filteredHistory.isNotEmpty) {
            final lastItem = filteredHistory.last;
            final lastWordId = lastItem.learningWord?.word.id;
            final lastUiState = lastWordId != null ? state.wordUIStates[lastWordId] : null;
            if (lastUiState != null) {
              _persistLastWordHistoryItemWith(lastItem, lastUiState);
            } else {
              Prefs.remove('last_word_history_item');
            }
          } else {
            Prefs.remove('last_word_history_item');
          }

          didMaster = true;
        }

        if (lw != null && state.fsrsItem != null && state.lastFsrsRating != null) {
          StudyBo().saveHistoryFSRSUpdate(
            currWord: lw,
            nextFsrs: state.fsrsItem!,
            newRating: state.lastFsrsRating!,
          );
        }

        // 若本次掌握了当前词，该词已从 history 中移除，后续词前移一位，nextIndex 不 +1
        int nextIndex = didMaster ? state.historyIndex : state.historyIndex + 1;
        if (nextIndex >= state.history.length) {
          state = state.copyWith(historyIndex: -1);
          final target = state.reviewReturnTarget;
          if (target != null) {
            final res = await handleWord(target, isFromBatchWordList: true);
            Global.logger.i('[PERF] Total getNextWord (history exit) cost: ${totalStopwatch.elapsedMilliseconds}ms');
            return res;
          } else {
            final res = await getNextWord(false);
            Global.logger.i('[PERF] Total getNextWord (history fallback) cost: ${totalStopwatch.elapsedMilliseconds}ms');
            return res;
          }
        } else {
          state = state.copyWith(historyIndex: nextIndex);
          final res = await handleWord(state.history[nextIndex]);
          Global.logger.i('[PERF] Total getNextWord (history next) cost: ${totalStopwatch.elapsedMilliseconds}ms');
          return res;
        }
      }
    }

    state = state.copyWith(
      isGettingNextWord: true,
      selectedAnswerIndex: null,
      hasFinishedAnswering: false,
      flippedAnswerIndices: {},
      showAnswerButtons: false,
    );
    try {
      if (!fastPath) {
        try {
          await Future.wait([
            asr.stopAsr(),
            asr.reset(),
          ]).timeout(const Duration(milliseconds: 1500));
        } catch (e) {
          Global.logger.w('getNextWord: clean up ASR failed or timed out: $e');
        }
      }

      meaningController.text = '';
      _handlingChinese = '';

      if (gotoNext && state.currentGetWordResult != null) {
        if (!state.currentGetWordResult!.finished && !state.currentGetWordResult!.noWord) {
          state = state.copyWith(history: [...state.history, state.currentGetWordResult!]);
          _persistLastWordHistoryItem();
        }
      }

      bool isFromBatchWordList = false;
      if (_args.fromPage == 'batch_word_list') {
        isFromBatchWordList = true;
        _args.fromPage = null;
        await Prefs.write("BdcPageArgs", _args.toJson());
      }

      final apiStopwatch = Stopwatch()..start();
      final result = await StudyBo().getWord(state.isWordMastered, gotoNext, fsrsRating: fsrsRating);
      Global.logger.d('[PERF] getNextWord -> StudyBo().getWord API cost: ${apiStopwatch.elapsedMilliseconds}ms');
      
      if (result.success && result.data != null) {
        state = state.copyWith(loadError: null, learningGetWordResult: result.data);
        final handleStopwatch = Stopwatch()..start();
        final success = await handleWord(result.data, isFromBatchWordList: isFromBatchWordList);
        Global.logger.d('[PERF] getNextWord -> handleWord cost: ${handleStopwatch.elapsedMilliseconds}ms');
        return success;
      } else {
        Global.logger.w('getNextWord: 获取单词失败: code=${result.code}, msg=${result.msg}');
        if (result.code == "NEW_DAY") {
          ToastUtil.info('已进入新的一天，请重新开始学习');
          goRouter.go('/index'); // Redirect back to plan page
        } else {
          state = state.copyWith(loadError: result.msg ?? '获取单词失败');
          ToastUtil.error(result.msg ?? '获取单词失败');
        }
        return false;
      }
    } catch (e, st) {
      state = state.copyWith(loadError: e.toString());
      ErrorHandler.handleError(e, st, logPrefix: 'getNextWord');
      return false;
    } finally {
      state = state.copyWith(isGettingNextWord: false);
      Global.logger.i('[PERF] Total getNextWord cost: ${totalStopwatch.elapsedMilliseconds}ms');
    }
  }

  void _saveCurrentWordState() {
    final sw = Stopwatch()..start();
    if (state.word?.id != null) {
      final uiState = WordUIState(
        stepIndex: state.currentGetWordResult?.stepIndex,
        studyStep: state.studyStep,
        hasFinishedAnswering: state.hasFinishedAnswering,
        canLeaveCurrWord: state.canLeaveCurrWord,
        showSentenceTranslation: state.showSentenceTranslation,
        selectedAnswerIndex: state.selectedAnswerIndex,
        flippedAnswerIndices: Set<int>.from(state.flippedAnswerIndices),
        tabIndex: state.tabIndex,
        currentScore: state.currentScore,
        meaningText: meaningController.text,
        words: state.words != null ? List<WordVo>.from(state.words!) : null,
        correctAnswerIndex: state.correctAnswerIndex ?? 0,
        fsrsItem: state.fsrsItem,
        daysSinceLastReview: state.daysSinceLastReview,
        lastFsrsRating: state.lastFsrsRating,
        asrMatchedMeaningItemParts: state.wordWrapper != null ? List<Pair<int, int>>.from(state.wordWrapper!.asrMatchedMeaningItemParts) : null,
        asrRevealedMeaningItemParts: state.wordWrapper != null ? List<Pair<int, int>>.from(state.wordWrapper!.asrRevealedMeaningItemParts) : null,
        currentAsrCandidates: List<String>.from(state.currentAsrCandidates),
        hintTapCount: state.hintTapCount,
      );
      state = state.copyWith(wordUIStates: {...state.wordUIStates, state.word!.id!: uiState});
      debugPrint('⚡ [PERF] _saveCurrentWordState cost: ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<void> onAsrResult(event) async {
    final int pttRoundAtEntry = _pttRoundToken;
    String processedResult = "";
    List<String> candidates = [];
    bool isFinal = false;
    
    try {
      Map<String, dynamic>? resultData;
      try {
        resultData = jsonDecode(event.toString());
        if (resultData != null) {
          isFinal = resultData['isFinal'] ?? false;
        }
      } catch (_) {
        resultData = null;
      }

      String best = "";
      if (resultData != null && resultData.containsKey('candidates')) {
        candidates = List<String>.from(resultData['candidates']);
        best = resultData['best'] ?? candidates.first;
      } else {
        best = event.toString();
        candidates = [best];
      }

      // ⚡ 净化防护：用正则剔除掉由 ASR 解码注意力退化产生的连续重复单字符（如 r r r r r）
      final repeatPattern = RegExp(r'\b([a-zA-Z])(\s+\1){2,}\b', caseSensitive: false);
      best = best.replaceAll(repeatPattern, '').trim();
      candidates = candidates.map((c) => c.replaceAll(repeatPattern, '').trim()).toList();

      final bool isSentence = state.studyStep == StudyStep.enSentence2Ch.json ||
                              state.studyStep == StudyStep.chSentence2En.json;

      if (isSentence) {
        // 例句环节为 PTT 模式：松开后到达的遗留事件一律忽略，
        // 避免原生端 stop 前已排队的最终结果污染下一次按住的新会话
        if (!_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
        final rawBest = best.trim();
        if (rawBest.isNotEmpty) {
          final bool isEnglish = state.studyStep == StudyStep.chSentence2En.json;
          if (isEnglish) {
            Global.logger.i('🎤 [ASR] [Sentence-English] ASR识别事件触发，例句模式激活中，使用 en-US-sentence (en-80M BPE) 模型识别。当前识别片段: "$rawBest"');
          }

          // 例句中英模式：在 stitch 之前对 ASR 片段做发音相似度自动纠错，
          // 确保 stitch 的 prev 与 next 都是纠正后文本，重叠检测才能正确工作，
          // 同时让所有帧（不限于 final）都能实时显示纠正结果。
          String cleanBest = rawBest;
          if (isEnglish) {
            final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
                ? state.word!.sentences!.first
                : null;
            if (sentence?.english != null && sentence!.english!.isNotEmpty) {
              cleanBest = await _phoneticAutoCorrectSentence(rawBest, sentence.english!);
              // await 期间可能已松开并重按(轮次切换)：校验仍属于当前 PTT 轮次才继续写入
              if (!_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
            }
          }

          if (isFinal) {
            _lastFinalAsrText = stitchTexts(_lastFinalAsrText, cleanBest, isEnglish: isEnglish);
            _accumulatedAsrText = _lastFinalAsrText;
          } else {
            _accumulatedAsrText = stitchTexts(_lastFinalAsrText, cleanBest, isEnglish: isEnglish);
          }
        }
        processedResult = AsrUtil.preprocess(_accumulatedAsrText);
        final uniqueCandidates = [_accumulatedAsrText];
        for (final c in candidates) {
          if (c != _accumulatedAsrText) uniqueCandidates.add(c);
        }
        // 识别增量写入可编辑答案区(锚点前 + 本轮增量 + 锚点后),光标置于增量末尾,
        // 便于连续补充。currentAsrCandidates 保持增量语义供判定时拼接。
        if (_isPttPressed) {
          final fullText = _pttAnchorPrefix + _accumulatedAsrText + _pttAnchorSuffix;
          if (sentenceAnswerController.text != fullText) {
            sentenceAnswerController.value = sentenceAnswerController.value.copyWith(
              text: fullText,
              selection: TextSelection.collapsed(offset: _pttAnchorPrefix.length + _accumulatedAsrText.length),
              composing: TextRange.empty,
            );
          }
        }
        _updateState(state.copyWith(currentAsrCandidates: uniqueCandidates), tag: 'asr-candidate');
      } else {
        if (resultData != null && resultData.containsKey('candidates')) {
          if (state.studyStep == StudyStep.ch2En.json) {
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(candidates, state.word!.spell);
            processedResult = AsrUtil.preprocessEnglish(result.text, state.word!.spell);
            _updateState(state.copyWith(currentScore: result.score, currentAsrCandidates: candidates), tag: 'asr-result');
          } else {
            processedResult = AsrUtil.preprocess(best);
            _updateState(state.copyWith(currentAsrCandidates: candidates), tag: 'asr-candidate');
          }
        } else {
          processedResult = AsrUtil.preprocess(best);
          _updateState(state.copyWith(currentAsrCandidates: candidates), tag: 'asr-candidate');
        }
      }
    } catch (e) {
      processedResult = AsrUtil.preprocess(event.toString());
      candidates = [event.toString()];
      final bool isSentence = state.studyStep == StudyStep.enSentence2Ch.json ||
                              state.studyStep == StudyStep.chSentence2En.json;
      if (isSentence) {
        if (!_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
        final rawBest = event.toString().trim();
        if (rawBest.isNotEmpty) {
          final bool isEnglish = state.studyStep == StudyStep.chSentence2En.json;

          // 同样在 stitch 前做自动纠错
          String cleanBest = rawBest;
          if (isEnglish) {
            final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
                ? state.word!.sentences!.first
                : null;
            if (sentence?.english != null && sentence!.english!.isNotEmpty) {
              cleanBest = await _phoneticAutoCorrectSentence(rawBest, sentence.english!);
              // await 间隙可能已切换 PTT 轮次：校验后才继续写入
              if (!_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
            }
          }

          _lastFinalAsrText = stitchTexts(_lastFinalAsrText, cleanBest, isEnglish: isEnglish);
          _accumulatedAsrText = _lastFinalAsrText;
        }
        processedResult = AsrUtil.preprocess(_accumulatedAsrText);
        _updateState(state.copyWith(currentAsrCandidates: [_accumulatedAsrText]), tag: 'asr-candidate');
      }
      isFinal = true;
    }

    // 句子环节判定用完整答案(锚点+增量+锚点后);非句子环节用处理后的识别结果
    final String judgeInput = (_isSentenceStepActive() && _isPttPressed)
        ? sentenceAnswerController.text
        : processedResult;
    checkAsrResult(asrInput: judgeInput, isVoice: true, isFinal: isFinal);
  }

  Future<void> checkAsrResult({String? asrInput, bool isVoice = false, bool isFinal = false}) async {
    if (_isDisposed) return;
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;
    final stopwatch = Stopwatch()..start();
    String inputText = asrInput ?? meaningController.text;
    if (asrInput == null) {
      if (state.studyStep == StudyStep.ch2En.json) {
        // Ch2En 模式：ASR 识别结果可能包含标点（如 "hello."），而
        // meaningController.text 是纯拼写（如 "hello"）。对两者归一化处理
        //（去除所有非字母字符）后再比较，防止 text listener 触发 re-entry
        // 导致 _pronouncePlayer 与 _audioPlayer 同时播放同一发音（回声 bug）。
        if (inputText.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') ==
            _handlingChinese.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
          return;
        }
      } else {
        if (inputText.toLowerCase() == _handlingChinese.toLowerCase()) return;
      }
    }
    _handlingChinese = inputText;

    final String? step = state.studyStep;
    final bool isSentenceStep = step == StudyStep.enSentence2Ch.json || step == StudyStep.chSentence2En.json;
    if (isSentenceStep) {
      final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
          ? state.word!.sentences!.first
          : null;
      if (sentence != null) {
        String method = "键盘输入";
        if (isVoice) {
          method = "语音识别";
        } else if (asrInput != null) {
          method = "手写输入";
        }

        // 语音/手写识别传入 asrInput(完整答案)时直接用它判定；
        // 键盘输入或防抖自动判定时用当前答案区文本。
        final List<String> inputs = (asrInput != null)
            ? [asrInput]
            : [sentenceAnswerController.text.isNotEmpty
                ? sentenceAnswerController.text
                : meaningController.text];
        int maxScore = 0;

        if (step == StudyStep.enSentence2Ch.json) {
          // 例句英中：说中文，匹对 sentence.chinese
          final targetCh = sentence.chinese ?? "";
          for (final input in inputs) {
            final score = getChineseSentenceMatchScore(input, targetCh);
            if (score > maxScore) maxScore = score;
          }
        } else {
          // 例句中英：说英文，匹对 sentence.english
          final targetEn = sentence.english ?? "";
          for (final input in inputs) {
            final score = await getEnglishSentenceMatchScore(input, targetEn);
            if (score > maxScore) maxScore = score;
          }
        }

        // 实时更新 currentScore，让 UI 实时显示得分！
        state = state.copyWith(currentScore: maxScore);

        final bool isMatch;
        // 将英文例句通过的得分阈值放宽到 60 分，增加口音与吞音容错率
        // ⚡ 体验优化：为了防止最后一个单词没有显示完整就提前通关并掐断识别，
        // 对于语音识别（isVoice），必须等待最后一帧 isFinal 为 true 时才执行 Match 通过，以保证单词在 UI 上完整展现。
        final bool passedThreshold = maxScore >= 60;
        isMatch = passedThreshold && (!isVoice || isFinal);

        if (isMatch) {
          _isAnswerCorrectHandling = true;
          if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
            // 例句环节 PTT 语义：统一走 _syncAudioHardware 按 _isPttPressed 判定说模式，
            // 避免旧表达式 (_shouldShowSpeakTab && tabIndex==0) 绕过 PTT 控制导致开麦状态错乱。
            final bool isSentenceStep = step == StudyStep.enSentence2Ch.json ||
                step == StudyStep.chSentence2En.json;
            if (isSentenceStep) {
              _syncAudioHardware();
            } else {
              await StudyAudioSessionController.instance.syncHardwareIntent(
                isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
                isAnsweringActive: false,
                language: AsrLanguage.english,
                phrases: [],
                caller: this,
              );
            }
          }
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
        }
      }
      Global.logger.d('[PERF] checkAsrResult total cost: ${stopwatch.elapsedMilliseconds}ms');
      return;
    }

    if (state.hasFinishedAnswering && !state.showHandwritingBoard) return;

    String method = "键盘输入";
    if (isVoice) {
      method = "语音识别";
    } else if (asrInput != null) {
      // 只有手写板会显式传入 asrInput 且 isVoice 为 false
      method = "手写输入";
    }

    // 预先检查拼写（针对手写/键盘拼写练习模式，不论当前是英中还是中英）
    bool isSpellingMatch = false;
    if (state.word != null) {
      String correctSpell = state.word!.spell.toLowerCase();
      String inputLower = inputText.trim().toLowerCase();
      
      isSpellingMatch = inputLower.replaceAll(RegExp(r'[^a-z]'), '') == correctSpell.replaceAll(RegExp(r'[^a-z]'), '');
      // 音素相似度阈值仅适用于语音输入 (isVoice=true)，不用于手写或键盘输入
      if (!isSpellingMatch && isVoice && asrInput != null && (state.currentScore ?? 0) >= Constants.phonemeMatchThreshold) {
        isSpellingMatch = true;
      }
    }

    if (state.studyStep == StudyStep.en2Ch.json) {
      // 如果开启了手写拼写练习，且拼写正确
      if (isSpellingMatch && state.showHandwritingBoard) {
        if (asrInput != null) {
          meaningController.text = state.word!.spell;
        }
        // 仅在麦克风处于开启状态时才进行物理关麦
        if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
          await StudyAudioSessionController.instance.syncHardwareIntent(
            isInSpeakTab: false,
            isAnsweringActive: false,
            language: AsrLanguage.english,
            phrases: [],
            caller: this,
          );
        }
        
        if (state.hasFinishedAnswering) {
          // 已经答对了（处于查看详情时的额外练习），直接关闭
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
          StudyAudioSessionController.instance.playWordSound(state.word!);
        } else {
          // 还没答对（英中模式下的拼写练习），仅关闭界面，不视为答对题目
          state = state.copyWith(showHandwritingBoard: false);
          StudyAudioSessionController.instance.playWordSound(state.word!);
          _handleTabChangeForAsr();
        }
        Global.logger.d('[PERF] checkAsrResult spelling match cost: ${stopwatch.elapsedMilliseconds}ms');
        return;
      }

      final isFromAsr = asrInput != null || meaningController.text == _handlingChinese;
      final inputs = isFromAsr ? state.currentAsrCandidates : [_handlingChinese];
      
      final matchStopwatch = Stopwatch()..start();
      final clonedWrapper = state.wordWrapper!.clone();
      final result = matchInputChineseWithMeaningItems(clonedWrapper, inputs);
      bool isMatch = _isAsrPassSync(result.totalCount, result.matchedCount);
      Global.logger.d('[PERF] checkAsrResult -> matchInputChineseWithMeaningItems cost: ${matchStopwatch.elapsedMilliseconds}ms');
      
      if (result.newMatchCount > 0) {
        state = state.copyWith(
          canLeaveCurrWord: true,
          wordWrapper: clonedWrapper,
        );
        if (isMatch) {
          _isAnswerCorrectHandling = true; // 立即同步上锁，防止异步 stopSession 期间重入
          
          // 仅在麦克风处于开启状态时才进行物理关麦，避免冗余硬件操作导致 Session 被重置为 'none' 并产生爆音
          if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
            await StudyAudioSessionController.instance.syncHardwareIntent(
              isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
              isAnsweringActive: false,
              language: AsrLanguage.english,
              phrases: [],
              caller: this,
            );
          }
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
        } else {
          _playCorrectSound();
        }
      }
    } else if (state.studyStep == StudyStep.ch2En.json) {
      if (isSpellingMatch) {
        if (asrInput != null) {
          meaningController.text = state.word!.spell;
        }

        // 如果提示已经显示了所有字母，则不应自动提交为用户完成做题，
        // 也不应关闭语音识别。用户应继续手动拼写输入，自主确认答案。
        // （语音输入 isVoice=true 不受此限制——用户是在主动说出答案，而非被动看到字母填充）
        final hintRevealedAll =
            (state.wordWrapper?.hintLetterCount ?? 0) >= (state.word?.spell.length ?? 0);
        if (!state.hasFinishedAnswering && hintRevealedAll && !isVoice) {
          // 提示已展示全部字母，不自动提交、不播放发音，用户应继续手动答题
          if (state.showHandwritingBoard) {
            state = state.copyWith(showHandwritingBoard: false);
            _handleTabChangeForAsr();
          }
          return;
        }

        if (state.hasFinishedAnswering) {
          // 若已答完，需先等待麦克风关停（含切换至 playback），再播放发音防止回声
          await StudyAudioSessionController.instance.syncHardwareIntent(
            isInSpeakTab: false,
            isAnsweringActive: false,
            language: AsrLanguage.english,
            phrases: [],
            caller: this,
          );
          StudyAudioSessionController.instance.playWordSound(state.word!);
        } else {
          // 若未答完，后续 _onAnswerCorrect -> playWordAndFirstSentence 内部会进行原子关麦与播音，
          // 此处无需重复 stopSession 以防底层硬件频繁配置冲突产生轻微爆音
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
        }
      }
    }
    Global.logger.d('[PERF] checkAsrResult total cost: ${stopwatch.elapsedMilliseconds}ms');
  }

  bool _isAsrPassSync(int total, int matched) {
    if (state.asrPassRuleCache == 'ALL') {
      return matched >= total && total > 0;
    } else if (state.asrPassRuleCache == 'HALF') {
      return matched >= ((total + 1) >> 1);
    } else {
      return matched >= 1;
    }
  }

  ({FsrsRating rating, String reason}) _calculateRating(String method, {int? customResponseTime}) {
    if (state.wordStartTime == null) return (rating: FsrsRating.good, reason: "$method，初始评分: ${FsrsRating.good.label}");
    final responseTime = customResponseTime ?? AppClock.now().difference(state.wordStartTime!).inSeconds;
    
    // 判断是否为例句环节，如果是，适当延长打分响应时间阈值（Easy 16s，Hard 30s）
    final bool isSentenceStep = state.studyStep == StudyStep.enSentence2Ch.json || 
                                state.studyStep == StudyStep.chSentence2En.json;
    final int easyThreshold = isSentenceStep ? 16 : 8;
    final int hardThreshold = isSentenceStep ? 30 : 18;

    FsrsRating rating;
    if (responseTime < easyThreshold) {
      rating = FsrsRating.easy;
    } else if (responseTime >= hardThreshold) {
      rating = FsrsRating.hard;
    } else {
      rating = FsrsRating.good;
    }
    String reason;
    if (method == "AI裁判") {
      reason = "AI裁判判定回答正确 (答题耗时: ${responseTime}s)，判定为${rating.label}";
    } else {
      reason = "$method，响应时间: ${responseTime}s，判定为${rating.label}";
    }
    
    if (state.hintTapCount >= 2 || state.showSentenceTranslation) {
      rating = FsrsRating.again;
      reason = "$method，由于使用了大量提示或查看了翻译，评分: ${rating.label}";
    } else if (state.hintTapCount == 1) {
      reason += "，由于使用了一次提示，评分下调一级";
      if (rating == FsrsRating.easy) {
        rating = FsrsRating.good;
      } else if (rating == FsrsRating.good) {
        rating = FsrsRating.hard;
      } else if (rating == FsrsRating.hard) {
        rating = FsrsRating.again;
      }
    }
    return (rating: rating, reason: reason);
  }

  void _onAnswerCorrect(FsrsRating rating, {String? reason}) async {
    final stopwatch = Stopwatch()..start();
    if (state.hasFinishedAnswering) {
      state = state.copyWith(showHandwritingBoard: false);
      _handleTabChangeForAsr();
      return;
    }
    
    // 同步立即锁定状态，彻底阻断由于 ASR 连续识别或 re-entry 重复触发导致的回声和并发冲突
    state = state.copyWith(
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      lastFsrsRating: rating,
      lastFsrsRatingReason: reason,
      showHandwritingBoard: false,
    );
    _handleTabChangeForAsr();
    
    // 巩固阶段：巩固评分不得优于之前的测评评分。
    // 如果用户答得比测评时好（评分档次更高），则以测评评分为准，
    // 防止因测评阶段已掌握评分较高而导致巩固阶段重复降难度。
    if ((state.currentGetWordResult?.stepIndex ?? 0) > 0 && state.assessmentRating != null) {
      if (rating.index > state.assessmentRating!.index) {
        rating = state.assessmentRating!;
      }
    }
    
    // 答对了，轻量级停止识别任务本身，保持麦克风与 Category 通道保温，绝不阻塞 UI 主帧
    unawaited(asr.stopAsr());
    
    if (state.studyStep == StudyStep.en2Ch.json && state.wordWrapper != null) {
      state.wordWrapper!.revealAllRemainingMeanings();
    }
    
    final fsrsStopwatch = Stopwatch()..start();
    final lw = state.currentGetWordResult?.learningWord;
    if (lw != null) {
      final fsrs = FSRS();
      int daysSinceLastReview = 0;
      if (lw.lastLearningDate != null) {
        daysSinceLastReview = AppClock.today().difference(app_date.DateUtils.businessDate(lw.lastLearningDate!)).inDays;
      }
      int days = state.daysSinceLastReview ?? 0;
      FSRSItem nextItem;
      if (lw.stability == null || lw.stability == 0.0) {
        nextItem = fsrs.init(rating);
      } else {
        final prevItem = FSRSItem(
          stability: lw.stability!,
          difficulty: lw.difficulty!,
          elapsedDays: days,
          scheduledDays: lw.scheduledDays ?? 0,
          reps: lw.reps ?? 0,
          lapses: lw.lapses ?? 0,
          state: FsrsState.values[lw.state ?? 0],
        );
        nextItem = fsrs.next(prevItem, rating, days);
      }

      state = state.copyWith(fsrsItem: nextItem, daysSinceLastReview: daysSinceLastReview);
    }
    Global.logger.d('[PERF] _onAnswerCorrect -> FSRS calculation cost: ${fsrsStopwatch.elapsedMilliseconds}ms');

    // 答对后的反馈逻辑：
    // 1. 中英模式 (Ch2En)：用户通过识别/拼写回答正确。此时播放单词发音，帮助用户纠正发音并加深印象。
    //    await 等待发音播完，使用户完整听到后再跳转，避免突兀感。
    // 2. 其他模式 (如 En2Ch)：用户已经听过发音。此时仅播放轻快的正确提示音，避免冗余感。
    if (state.studyStep == StudyStep.ch2En.json) {
      final playSw = Stopwatch()..start();
      await playWordAndFirstSentence(true, false);
      debugPrint('⚡ [PERF] _onAnswerCorrect -> playWordAndFirstSentence cost: ${playSw.elapsedMilliseconds}ms');
    } else {
      _playCorrectSound();
    }

    // 例句巩固环节（非测评）仅为练习，不更新 FSRS 参数
    final bool isSentencePractice = _isSentencePracticeStep();

    bool autoJump = state.autoJumpAfterCorrect;
    if (autoJump && state.historyIndex == -1) {
      // 中英模式发音已完整播完，仅需 400ms 短暂缓冲即可舒适跳转；
      // 其他模式保留原有 800ms 延迟。
      final jumpDelayMs = state.studyStep == StudyStep.ch2En.json ? 0 : 1000;
      Future.delayed(Duration(milliseconds: jumpDelayMs), () {
        getNextWord(true, fsrsRating: isSentencePractice ? null : rating);
      });
    }
    Global.logger.d('[PERF] _onAnswerCorrect total cost: ${stopwatch.elapsedMilliseconds}ms');
  }

  void _playCorrectSound() {
    final now = DateTime.now();
    if (_lastCorrectSoundTime != null &&
        now.difference(_lastCorrectSoundTime!) < const Duration(milliseconds: 800)) {
      debugPrint('⚡ [Audio-Filter] 800ms 内已播放过正确反馈音，忽略本次播放以防止回声');
      return;
    }
    _lastCorrectSoundTime = now;
    if (PlatformUtils.isIOS) {
      StudyAudioSessionController.instance.playSoundEffect('correct_ios.wav', speed: 1.0, volume: 0.3);
    } else {
      StudyAudioSessionController.instance.playSoundEffect('correct.wav', speed: 1.0, volume: 1.0);
    }
  }

  Future<void> playWordAndFirstSentence(bool forcePlayWord, bool startAsrWhenFinish, {bool forcePlaySentence = false}) async {
    if (_isDisposed) return;
    final stopwatch = Stopwatch()..start();
    final studyConfig = StudyConfig.fromCurrentUser();
    
    debugPrint('🕵️ [AudioDiag] playWordAndFirstSentence.enter | forcePlayWord=$forcePlayWord startAsrWhenFinish=$startAsrWhenFinish word=${state.word?.spell}');

    // 强制播放标志优先级最高，不受模式限制。自动播放则依然仅限英中模式。
    bool willPlayWord = forcePlayWord || (state.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlayWord);
    bool willPlaySentence = forcePlaySentence || (state.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlaySentence);

    debugPrint('🕵️ [AudioDiag] playWordAndFirstSentence.decision | willPlayWord=$willPlayWord willPlaySentence=$willPlaySentence step=${state.studyStep}');

    if (willPlayWord || willPlaySentence) {
      if (state.word != null) {
        await StudyAudioSessionController.instance.playWordAndSentence(
          state.word!,
          sentenceDigest: state.englishDigestOfFirstSentence,
          playWord: willPlayWord,
          playSentence: willPlaySentence,
          isSpeakMode: startAsrWhenFinish && _shouldShowSpeakTab && state.tabIndex == 0,
        );
      }
    }

    _isSoundPlayingOrPending = false; // 播音已结束，释放状态保护

    if (startAsrWhenFinish && !_isDisposed) {
      debugPrint('⏱️ [Latency-BDC] 播放完自动衔接 ASR...');
      _handleTabChangeForAsr();
    }
    
    Global.logger.d('[PERF] playWordAndFirstSentence total cost: ${stopwatch.elapsedMilliseconds}ms');
  }

  List<String> _extractEnglishWords(String sentence) {
    // 1. 去掉 HTML 标签
    final plainText = sentence.replaceAll(RegExp(r"<.*?>"), " ");
    // 2. 清洗非字母数字和空白的标点符号
    final cleanText = plainText.replaceAll(RegExp(r"[^a-zA-Z0-9\s]"), " ");
    // 3. 按空格切分，并过滤掉空串
    return cleanText
        .split(RegExp(r"\s+"))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// 对例句中英模式 (ChSentence2En) 的 ASR 识别结果进行发音相似度自动纠错。
  /// 将识别出的每个单词与例句正确单词做音素比对，相似度达到阈值时替换为例句用词，
  /// 修正 ASR 对发音相近单词的误识别（如 "dessert" → "desert"、"gotta" → "got to" 等）。
  Future<String> _phoneticAutoCorrectSentence(String input, String targetSentence) async {
    final inputWords = _extractEnglishWords(input);
    if (inputWords.isEmpty) return input;

    final targetWords = _extractEnglishWords(targetSentence);
    if (targetWords.isEmpty) return input;

    final corrected = <String>[];
    for (final iw in inputWords) {
      final iwLower = iw.toLowerCase();

      // 1. 精确匹配优先（大小写不敏感）
      String? exactMatch;
      for (final tw in targetWords) {
        if (iwLower == tw.toLowerCase()) {
          exactMatch = tw;
          break;
        }
      }
      if (exactMatch != null) {
        corrected.add(exactMatch);
        continue;
      }

      // 2. 音素相似度模糊匹配
      String bestMatch = iw;
      int bestSim = 0;
      for (final tw in targetWords) {
        final sim = await PhonemeUtil.similarity(iw, tw);
        if (sim > bestSim) {
          bestSim = sim;
          bestMatch = tw;
        }
      }

      // 相似度 >= 75 时纠正为例句中的正确单词
      corrected.add(bestSim >= 75 ? bestMatch : iw);
    }

    return corrected.join(" ");
  }

  void _syncAudioHardware({bool bypassStartDebounce = false}) {
    if (_isDisposed) return;

    // 例句环节的"说"模式完全由 PTT 按住状态控制：按住才视为说模式并开麦，
    // 松开/切选 Tab/答对/离开时 isInSpeakTab=false → 物理释放麦克风。
    final bool isSentenceStep = state.studyStep == StudyStep.enSentence2Ch.json ||
        state.studyStep == StudyStep.chSentence2En.json;
    final isInSpeakTab = isSentenceStep
        ? _isPttPressed && state.tabIndex == 0
        : _shouldShowSpeakTab && state.tabIndex == 0;
    final isAnsweringActive = state.word != null &&
        state.loadError == null &&
        !state.hasFinishedAnswering &&
        !state.showHandwritingBoard &&
        !state.isGettingNextWord &&
        !state.isKeyboardVisible;

    final AsrLanguage language;
    if (state.studyStep == StudyStep.chSentence2En.json) {
      language = AsrLanguage.englishSentence;
    } else if (state.studyStep == StudyStep.ch2En.json) {
      language = AsrLanguage.english;
    } else {
      language = AsrLanguage.chinese;
    }
    List<String> phrases = [];
    if (state.word != null) {
      if (language == AsrLanguage.english || language == AsrLanguage.englishSentence) {
        phrases.add(state.word!.spell);
        // 如果是例句中英模式，把例句的每个单词也加入热词，并对核心词做权重加倍
        if (state.studyStep == StudyStep.chSentence2En.json) {
          final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
              ? state.word!.sentences!.first
              : null;
          if (sentence != null) {
            final rawSentence = sentence.english ?? '';
            
            // 提取加粗的词（<b>包裹的短语）以用于后续加权
            final RegExp boldPattern = RegExp(r"<b>(.*?)</b>");
            final Iterable<Match> matches = boldPattern.allMatches(rawSentence);
            final List<String> boldPhrases = matches.map((m) => m.group(1) ?? "").where((w) => w.isNotEmpty).toList();

            // 提取所有分词
            final words = _extractEnglishWords(rawSentence);
            if (words.isNotEmpty) {
              // A. 整句例句作为串联热词
              phrases.add(words.join(" "));
              
              // B. 例句中每一个单独单词
              phrases.addAll(words);
              
              // C. 核心词/主单词权重加倍
              phrases.add(state.word!.spell);
              for (final boldPhrase in boldPhrases) {
                final boldWords = _extractEnglishWords(boldPhrase);
                phrases.addAll(boldWords);
              }
            }
          }
        }
      } else {
        phrases.addAll(AsrUtil.extractContextualPhrases(state.word!.meaningItems ?? []));
      }
    }

    unawaited(StudyAudioSessionController.instance.syncHardwareIntent(
      isInSpeakTab: isInSpeakTab,
      isAnsweringActive: isAnsweringActive,
      language: language,
      phrases: phrases,
      caller: this,
      bypassStartDebounce: bypassStartDebounce,
    ));
  }

  void _handleTabChangeForAsr() {
    if (_isSoundPlayingOrPending) {
      debugPrint('💡 [BDC-ASR] 拦截 _handleTabChangeForAsr()：当前正处于单词发音播放或等待播放期间，拒绝开启 ASR。');
      return;
    }
    _syncAudioHardware();
  }

  /// 例句环节 PTT(按下说话)：按下并保持时开始语音识别。
  /// 仅例句步骤 (EnSentence2Ch / ChSentence2En) 且未答完时生效。
  void startPttAsr() {
    if (_isDisposed) return;
    final step = state.studyStep;
    final bool isSentenceStep = step == StudyStep.enSentence2Ch.json ||
        step == StudyStep.chSentence2En.json;
    if (!isSentenceStep || state.hasFinishedAnswering) return;
    if (_isPttPressed) return; // 防重复按下

    _isPttPressed = true;
    _pttRoundToken++; // 开启新一轮 PTT 会话
    // 捕获答案区锚点：若已有内容(补充模式)，本轮识别增量插入光标处；
    // 否则锚点为空(首次模式)，等同从头识别。
    final curText = sentenceAnswerController.text;
    final sel = sentenceAnswerController.selection;
    final int caret = (sel.isValid && sel.isCollapsed && sel.start <= curText.length)
        ? sel.start
        : curText.length; // 无光标/选区时默认追加到末尾
    _pttAnchorPrefix = curText.substring(0, caret);
    _pttAnchorSuffix = curText.substring(caret);
    _pttSuppressAutoCheck = true; // 按住期间抑制自动判定
    // 按住即开始全新一轮识别：重置本轮增量累积文本，松开时以"锚点+增量+锚点后"判定
    _accumulatedAsrText = "";
    _lastFinalAsrText = "";
    _updateState(
      state.copyWith(isPttPressed: true, currentAsrCandidates: []),
      tag: 'ptt-start',
    );
    _syncAudioHardware(bypassStartDebounce: true);
  }

  /// 例句环节 PTT(按下说话)：松开时优雅收尾并立即判定。
  /// 有识别文本则以最终结果判定；空文本（没说话）静默放弃。
  Future<void> stopPttAsr() async {
    if (_isDisposed) return;
    final int roundAtStop = _pttRoundToken;
    // 无条件停止识别任务（保留麦克风保温，支持快速重按）；
    // 即使 _isPttPressed 已被切 Tab 等复位，抬起事件也必须停止识别。
    // 原生端 flush 收尾：结束音频输入、解码残留音频后返回完整最终文本，
    // 松开不会硬切丢词，尾部单词自然识别完成。
    final String? flushText = await asr.stopAsr();
    // await 期间可能已重新按住(新 PTT 轮次),本轮停止不得覆盖新轮状态
    if (_pttRoundToken != roundAtStop) return;

    // 松开瞬间原生 flush 解出的完整文本:作为 isFinal 事件交给 onAsrResult
    // 走统一路径(纠错+拼接+UI 更新+判定),与实时事件流完全一致,避免
    // 此处用 stitchTexts 自行拼接导致 flushText(未纠错)与累积文本(已纠错)
    // 不一致时重叠检测失败、整句重复。
    if (flushText != null && flushText.isNotEmpty) {
      await onAsrResult(jsonEncode({
        'best': flushText,
        'candidates': [flushText],
        'isFinal': true,
      }));
    }

    // 解除抑制:松开后可正常自动判定(手动编辑 150ms 防抖)
    _pttSuppressAutoCheck = false;
    _isPttPressed = false;
    _updateState(state.copyWith(isPttPressed: false), tag: 'ptt-stop');

    // 完整答案 = 锚点 + 本轮增量 + 锚点后(controller 已在 onAsrResult 实时更新,
    // 此处仅兜底:flush 为空但有累积文本时,确保 controller 反映最终状态)
    final String fullText = sentenceAnswerController.text;
    if (flushText == null || flushText.isEmpty) {
      final text = fullText.trim();
      if (text.isEmpty) return; // 没说话：静默放弃，不判定
      await checkAsrResult(asrInput: text, isVoice: true, isFinal: true);
    }
  }

  int getChineseSentenceMatchScore(String input, String target) {
    String clean(String s) => s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
    final cleanInput = clean(input);
    final cleanTarget = clean(target);
    if (cleanTarget.isEmpty) return 0;

    List<List<int>> dp = List.generate(cleanInput.length + 1, (_) => List.filled(cleanTarget.length + 1, 0));
    for (int i = 1; i <= cleanInput.length; i++) {
      for (int j = 1; j <= cleanTarget.length; j++) {
        if (cleanInput[i - 1] == cleanTarget[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    final lcs = dp[cleanInput.length][cleanTarget.length];
    final ratio = lcs / cleanTarget.length;
    return (ratio * 100).round();
  }

  Future<int> getEnglishSentenceMatchScore(String input, String target) async {
    List<String> getWords(String s) {
      final list = s.toLowerCase().split(RegExp(r"[^a-zA-Z\d\u0027]")).where((w) => w.isNotEmpty).toList();
      // 过滤由于呼吸声/吸气声或拟声产生的非单词辅音块(如单字母t, s, 独立's 等)，只保留 a, i 和长度大于 1 且不是 's 的有效单词
      return list.where((w) {
        if (w == 'a' || w == 'i') return true;
        if (w == "'s" || w == "s") return false;
        if (w.length == 1) return false;
        return true;
      }).toList();
    }
    final inputWords = getWords(input);
    final targetWords = getWords(target);
    if (targetWords.isEmpty) return 0;

    // 1. 使用最长公共子序列 (LCS) 算法并结合音素相似度计算两个单词列表的匹配度
    List<List<double>> dp = List.generate(
        inputWords.length + 1, (_) => List.filled(targetWords.length + 1, 0.0));

    for (int i = 1; i <= inputWords.length; i++) {
      for (int j = 1; j <= targetWords.length; j++) {
        final wA = inputWords[i - 1];
        final wB = targetWords[j - 1];
        
        double matchWeight = 0.0;
        if (wA == wB) {
          matchWeight = 1.0; // 字面完全一致，满分匹配
        } else {
          // 如果字面不相等，进行音素模糊相似度比对
          final sim = await PhonemeUtil.similarity(wA, wB);
          if (sim >= 75) {
            matchWeight = 0.75; // 音素相似算通过，但权重打 7.5 折扣除完美度分值
          }
        }

        if (matchWeight > 0.0) {
          dp[i][j] = dp[i - 1][j - 1] + matchWeight;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    final double lcs = dp[inputWords.length][targetWords.length];
    final wordScore = (lcs * 100 / targetWords.length).round().clamp(0, 100);

    // 2. 同时计算整句的音素相似度，取两者最大值作为容错
    final phonemeScore = await PhonemeUtil.similarity(input, target);

    return wordScore > phonemeScore ? wordScore : phonemeScore;
  }

  void handleTabChangeForAsr() {
    _handleTabChangeForAsr();
  }

  void updateKeyboardVisibility(bool visible) {
    state = state.copyWith(isKeyboardVisible: visible);
    _syncAudioHardware();
  }

  void updateShowHandwritingBoard(bool show) {
    state = state.copyWith(showHandwritingBoard: show);
    handleTabChangeForAsr();
  }

  void updateShowSentenceTranslation(bool show) {
    state = state.copyWith(showSentenceTranslation: show);
  }

  void updateAutoJump(bool value) {
    if (state.studyStep == StudyStep.ch2En.json) {
      state = state.copyWith(autoJumpAfterCorrectCh2En: value);
    } else {
      state = state.copyWith(autoJumpAfterCorrectEn2Ch: value);
    }
  }

  void updateAutoJumpCh2En(bool value) {
    state = state.copyWith(autoJumpAfterCorrectCh2En: value);
  }

  void updateAutoJumpEn2Ch(bool value) {
    state = state.copyWith(autoJumpAfterCorrectEn2Ch: value);
  }

  void updateFlippedAnswerIndices(Set<int> indices) {
    state = state.copyWith(flippedAnswerIndices: indices);
  }

  Future<List<LearningLog>>? learningHistoryFuture;
  Timer? progressBarTapTimer;

  void handleProgressBarTap() {
    state = state.copyWith(progressBarTapCount: state.progressBarTapCount + 1);
    progressBarTapTimer?.cancel();
    progressBarTapTimer = Timer(const Duration(milliseconds: 3000), () {
      state = state.copyWith(progressBarTapCount: 0);
    });
    if (state.progressBarTapCount >= 5) {
      state = state.copyWith(progressBarTapCount: 0);
      // Logic to show debug overlay could be here or triggered via state
    }
  }

  String hideParenthesesContent(String text) {
    return text.replaceAll(RegExp(r'\([^)]*\)'), '(...)');
  }

  String hideAnswerLeakContent(String text) {
    if (state.studyStep == StudyStep.ch2En.json) {
      return text.replaceAll(state.word?.spell ?? '', '___');
    }
    return text;
  }

  Future<void> playWithAnimation(Future<void> Function() playSound, String audioType) async {
    // 用户手动触发播放，废除所有待执行的自动播放回调
    _playToken++;
    _updateState(state.copyWith(playingStates: {...state.playingStates, audioType: true}), tag: 'play-start');
    // 仅当 ASR 正在运行时才关停麦克风（释放硬件焦点），避免在"选"模式做无意义的 AudioSession 切换
    final wasAsrRunning = asr.state == AsrState.started;
    if (wasAsrRunning) {
      await asr.stopAsr();
    }
    try {
      await playSound();
    } finally {
      _updateState(state.copyWith(playingStates: {...state.playingStates, audioType: false}), tag: 'play-end');
      // 仅在之前开着 ASR 时才恢复，避免非说模式下的无效 AudioSession 切换
      if (wasAsrRunning) {
        _handleTabChangeForAsr();
      }
    }
  }

  void updateHasFinishedAnswering(bool value) {
    state = state.copyWith(hasFinishedAnswering: value);
  }

  void updateIsWordMastered(bool value) {
    state = state.copyWith(isWordMastered: value);
  }

  List<Tab> get dynamicTabs {
    List<Tab> tabs = [];
    if (_shouldShowSpeakTab) {
      tabs.add(const Tab(child: Row(children: [Icon(Icons.mic, size: 18), SizedBox(width: 4), Text('说')])));
    }
    tabs.add(const Tab(child: Row(children: [Icon(Icons.touch_app, size: 18), SizedBox(width: 4), Text('选')])));
    return tabs;
  }

  bool get _shouldShowSpeakTab => _getShouldShowSpeakTabFor(state.studyStep ?? '');

  bool _getShouldShowSpeakTabFor(String studyStep) {
    if (!PlatformUtils.isAsrSupported()) return false;
    if (studyStep == StudyStep.ch2En.json || studyStep == StudyStep.chSentence2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    if (studyStep == StudyStep.en2Ch.json || studyStep == StudyStep.enSentence2Ch.json) {
      return true;
    }
    return false;
  }

  void updateIsUpdatingByHint(bool value) {
    state = state.copyWith(isUpdatingByHint: value);
  }

  void updateShowAnswerButtons(bool value) {
    state = state.copyWith(showAnswerButtons: value);
  }

  void updateProgressBarTapCount(int value) {
    state = state.copyWith(progressBarTapCount: value);
  }


  void resetHighlightedWordImg() {
    state = state.copyWith(highlightedWordImg: null);
  }

  bool wordImageHasBeenVoted(String imageId) {
    // 简化的实现，实际逻辑可能需要查库
    return false;
  }

  void updateIsWordImageEdited(bool value) {
    state = state.copyWith(isWordImageEdited: value);
  }

  void updateAsrPassRuleCache(String value) {
    state = state.copyWith(asrPassRuleCache: value);
  }

  /// 当配置改变（例如设置弹窗关闭）时，安全地刷新当前配置并重建 ASR 语音识别
  Future<void> refreshConfigAndAsr() async {
    try {
      // 1. 通过状态机强行停止当前的麦克风，确保不会占用和通道冲突，同时更新 _activeMode
      await StudyAudioSessionController.instance.stopSession(forceStopMicrophone: true);
      
      // 2. 重新加载当前用户的 StudyConfig
      final studyConfig = StudyConfig.fromCurrentUser();
      
      // 3. 重新配置 ASR 缓存参数
      state = state.copyWith(
        asrPassRuleCache: studyConfig.asrPassRule,
      );
      
      // 4. 重置并初始化 ASR 状态
      await asr.initAsr(onAsrResult);
      
      // 5. 根据当前的 Tab 状态，安全触发录音的开启或关闭
      _handleTabChangeForAsr();
      
      // 6. 主动触发状态更新以重绘界面
      state = state.copyWith();
    } catch (e, stackTrace) {
      Global.logger.e('🔊 [BDC-ASR] 刷新设置与重构语音识别失败: $e', error: e, stackTrace: stackTrace);
    }
  }

  /// 智能重叠拼接算法：寻找并融合 prev 末尾与 next 开头的重合重叠部分
  static String stitchTexts(String prev, String next, {bool isEnglish = false}) {
    final p = prev.trim();
    final n = next.trim();
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;

    if (isEnglish) {
      final pWords = p.split(RegExp(r'\s+'));
      final nWords = n.split(RegExp(r'\s+'));

      // 归一化单词列表（仅保留字母和数字，并转为小写）
      final cleanPWords = pWords
          .map((w) => w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase())
          .toList();
      final cleanNWords = nWords
          .map((w) => w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase())
          .toList();

      cleanPWords.removeWhere((w) => w.isEmpty);
      cleanNWords.removeWhere((w) => w.isEmpty);

      if (cleanPWords.isEmpty) return n;
      if (cleanNWords.isEmpty) return p;

      int maxCleanOverlap = 0;
      final minLen = cleanPWords.length < cleanNWords.length
          ? cleanPWords.length
          : cleanNWords.length;

      for (int i = 1; i <= minLen; i++) {
        final pTail = cleanPWords.sublist(cleanPWords.length - i).join(' ');
        final nHead = cleanNWords.sublist(0, i).join(' ');

        if (pTail == nHead) {
          maxCleanOverlap = i;
        }
      }

      if (maxCleanOverlap > 0) {
        // 在原始的 nWords 中，找到第 maxCleanOverlap 个含有有效字母/数字单词的索引
        int count = 0;
        int sliceIdx = 0;
        final validReg = RegExp(r'[a-zA-Z0-9]');

        for (int i = 0; i < nWords.length; i++) {
          if (validReg.hasMatch(nWords[i])) {
            count++;
            if (count == maxCleanOverlap) {
              sliceIdx = i + 1;
              break;
            }
          }
        }

        final remainingN = nWords.sublist(sliceIdx).join(' ');
        return remainingN.isEmpty ? p : "$p $remainingN";
      } else {
        return "$p $n";
      }
    } else {
      // 中文按字符字级进行重叠比对，归一化（剔除非中文/字母/数字）
      final cleanP = p.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '');
      final cleanN = n.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '');

      if (cleanP.isEmpty) return n;
      if (cleanN.isEmpty) return p;

      int maxCleanOverlap = 0;
      final minLen = cleanP.length < cleanN.length ? cleanP.length : cleanN.length;

      for (int i = 1; i <= minLen; i++) {
        final pTail = cleanP.substring(cleanP.length - i);
        final nHead = cleanN.substring(0, i);

        if (pTail == nHead) {
          maxCleanOverlap = i;
        }
      }

      if (maxCleanOverlap > 0) {
        // 映射回原始的 n，找到第 maxCleanOverlap 个有效字符的索引
        int count = 0;
        int sliceIdx = 0;
        final validReg = RegExp(r'[\u4e00-\u9fa5a-zA-Z0-9]');

        for (int i = 0; i < n.length; i++) {
          if (validReg.hasMatch(n[i])) {
            count++;
            if (count == maxCleanOverlap) {
              sliceIdx = i + 1;
              break;
            }
          }
        }

        // 去除截断后开头紧跟的多余标点
        while (sliceIdx < n.length && !validReg.hasMatch(n[sliceIdx])) {
          sliceIdx++;
        }

        final remainingN = n.substring(sliceIdx);
        return remainingN.isEmpty ? p : "$p$remainingN";
      } else {
        return "$p$n";
      }
    }
  }

  Future<void> evaluateWithAiReferee(BuildContext context) async {
    final userResponseTime = state.wordStartTime != null
        ? AppClock.now().difference(state.wordStartTime!).inSeconds
        : 0;

    final word = state.word;
    if (word == null) return;
    final sentence = (word.sentences != null && word.sentences!.isNotEmpty)
        ? word.sentences!.first
        : null;
    if (sentence == null) {
      ToastUtil.error("当前单词没有例句，无法进行AI裁判");
      return;
    }

    final recognizedText = state.currentAsrCandidates.isNotEmpty
        ? state.currentAsrCandidates.first
        : '';
    final userInput = recognizedText.isNotEmpty
        ? recognizedText
        : meaningController.text;

    if (userInput.trim().isEmpty) {
      ToastUtil.error("请先回答问题");
      return;
    }

    // 停止 ASR 录音，冻结当前识别文本用于评判
    try {
      await asr.stopAsr();
    } catch (_) {}

    // 显示 Loading
    await Api.loadingService.show(status: 'AI裁判裁决中...');

    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        ToastUtil.error("请先登录");
        return;
      }

      final isEn2Ch = state.studyStep == StudyStep.enSentence2Ch.json;
      final sourceText = isEn2Ch ? (sentence.english ?? "") : (sentence.chinese ?? "");
      final referenceText = isEn2Ch ? (sentence.chinese ?? "") : (sentence.english ?? "");

      final systemPrompt = 'You are an AI referee. Judge if the user\'s translation is semantically correct. Respond in raw JSON format with: {"isCorrect": true} if correct, or {"isCorrect": false, "explanation": "Chinese explanation (max 12 words)"} if incorrect. Do NOT explain if correct. Do NOT include markdown format like ```json.';
      final userPrompt = 'Exercise Type: ${state.studyStep}\nSource Sentence: $sourceText\nReference Translation: $referenceText\nUser Answer: $userInput';

      final messages = [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": userPrompt}
      ];
      final messagesJson = jsonEncode(messages);

      final result = await Api.client.aiChat(messagesJson, user.id);

      await Api.loadingService.dismiss();

      if (result.success && result.data != null) {
        final responseText = result.data!.trim();
        String cleanJson = responseText;
        if (cleanJson.contains('```')) {
          final regExp = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
          final match = regExp.firstMatch(cleanJson);
          if (match != null) {
            cleanJson = match.group(1) ?? cleanJson;
          }
        }

        final startIdx = cleanJson.indexOf('{');
        final endIdx = cleanJson.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          cleanJson = cleanJson.substring(startIdx, endIdx + 1);
        }

        final parsed = jsonDecode(cleanJson.trim());
        final isCorrect = parsed['isCorrect'] as bool? ?? false;
        final explanation = parsed['explanation'] as String? ?? '';

        if (isCorrect) {
          ToastUtil.success("AI 裁判判定：通过！");
          _isAnswerCorrectHandling = true;
          if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
            await StudyAudioSessionController.instance.syncHardwareIntent(
              isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
              isAnsweringActive: false,
              language: AsrLanguage.english,
              phrases: [],
              caller: this,
            );
          }
          final ratingResult = _calculateRating("AI裁判", customResponseTime: userResponseTime);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
        } else {
          // 直接在页面上 inline 显示反馈 + 自动重启 ASR
          state = state.copyWith(aiRefereeFeedback: explanation);
          // 延迟重启 ASR，让用户先看到反馈
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!_isDisposed) _handleTabChangeForAsr();
          });
          // 5 秒后自动清除反馈
          Future.delayed(const Duration(seconds: 5), () {
            if (!_isDisposed && state.aiRefereeFeedback == explanation) {
              state = state.copyWith(aiRefereeFeedback: null);
            }
          });
        }
      } else {
        ToastUtil.error(result.msg ?? "调用 AI 裁判失败");
      }
    } catch (e, st) {
      await Api.loadingService.dismiss();
      Global.logger.e("AI裁判判分出错", error: e, stackTrace: st);
      ToastUtil.error("AI 裁判开小差了，请重试");
    }
  }


}




