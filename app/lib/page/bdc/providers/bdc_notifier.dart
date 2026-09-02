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
import 'package:nnbdc/util/ai_referee_util.dart';
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
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:nnbdc/util/study_track.dart';
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
  Timer? _wordAiRefereeDebounceTimer;
  final Set<String> _failedWordAiEvaluationsForCurrentWord = {};
  int _wordAiEvaluationCountForCurrentWord = 0;
  bool _isWordAiRefereeJudging = false;
  String _wordAccumulatedAsrText = "";
  String _wordLastFinalAsrText = "";

  Timer? _sentenceAiRefereeDebounceTimer;
  final Set<String> _failedSentenceAiEvaluationsForCurrentWord = {};
  int _sentenceAiEvaluationCountForCurrentWord = 0;
  bool _isSentenceAiRefereeJudging = false;
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
      _checkAsrDebounceTimer?.cancel();
      _checkAsrDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        checkAsrResult();
      });
    });

    sentenceAnswerController.addListener(() {
      _checkAsrDebounceTimer?.cancel();
      _checkAsrDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        checkAsrResult();
      });
    });

    ref.onDispose(() {
      _isDisposed = true;
      _learningTimer?.cancel();
      _persistTimer?.cancel();
      _checkAsrDebounceTimer?.cancel();
      _wordAiRefereeDebounceTimer?.cancel();
      _sentenceAiRefereeDebounceTimer?.cancel();
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

  /// 例句练习模式:看答案后隐藏答案,恢复语音识别练习。
  /// 练习时识别判定照常但答对不改今日测评结果(不写 LearningLog、不更新 FSRS)。
  bool _isPracticeMode = false;

  /// PTT 按住期间识别已达通过阈值但等待松开的标记:
  /// 例句环节按住时即使语音识别达标也不通过,必须松开按钮才判定。
  bool _pendingPttPass = false;

  /// 例句环节 PTT 会话轮次 token：每次 startPttAsr 递增。
  /// onAsrResult 的异步间隙(await 纠错)恢复后校验轮次是否仍为当前轮，
  /// 拦截"上一轮 stop 前已进入的事件在重按后继续写入"的跨轮污染
  int _pttRoundToken = 0;

  /// 例句补充模式锚点：按住 PTT 时答案区光标前后的文本。
  /// 本轮识别增量插入锚点之间，松开后拼成完整答案。
  String _pttAnchorPrefix = "";
  String _pttAnchorSuffix = "";

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
        autoJumpAfterCorrectChSentence2En: studyConfig.autoJumpAfterCorrectChSentence2En,
        autoJumpAfterCorrectEnSentence2Ch: studyConfig.autoJumpAfterCorrectEnSentence2Ch,
        showWordDetailAfterCorrect: studyConfig.showWordDetailAfterCorrect,
      );

      state = state.copyWith(loadError: null);

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
          // 若恢复的单词正是当前正在学习的单词(重新进入学习页),
          // 将其测评得分(上个环节的 lastFsrsRating)提取为 assessmentRating,
          // 供巩固环节显示"测评参考"与评分修正对话框默认值使用。
          if (state.word?.id == wordId && state.currentGetWordResult != null &&
              state.currentGetWordResult!.stepIndex > 0 && wordUIState.lastFsrsRating != null) {
            state = state.copyWith(
              assessmentRating: wordUIState.lastFsrsRating,
              assessmentScheduledDays: wordUIState.fsrsItem?.scheduledDays,
            );
          }
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
    _wordAiRefereeDebounceTimer?.cancel();
    _failedWordAiEvaluationsForCurrentWord.clear();
    _wordAiEvaluationCountForCurrentWord = 0;
    _isWordAiRefereeJudging = false;
    _wordAccumulatedAsrText = "";
    _wordLastFinalAsrText = "";

    _sentenceAiRefereeDebounceTimer?.cancel();
    _failedSentenceAiEvaluationsForCurrentWord.clear();
    _sentenceAiEvaluationCountForCurrentWord = 0;
    _isSentenceAiRefereeJudging = false;
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

    final trackResult = await _trackOfCurrentWord(getWordResult);
    final int stepIdx = (getWordResult.stepIndex >= 0 && getWordResult.stepIndex < trackResult.track.length)
        ? getWordResult.stepIndex
        : (trackResult.track.isNotEmpty ? trackResult.track.length - 1 : 0);
    final currentStep = trackResult.track.isNotEmpty ? trackResult.track[stepIdx] : '';
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
            '本组小结',
            StageWordsProvider(),
            true, // showBackBtn
            false, // showDelBtn: 本组小结为学习回顾环节，禁用删除操作
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
    String newStudyStep = trackResult.track[getWordResult.stepIndex];
    
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
    _isPracticeMode = false; // 新单词/新环节重置练习模式

    state = state.copyWith(
      currentGetWordResult: getWordResult,
      word: word,
      wordWrapper: wordWrapper,
      studyStep: newStudyStep,
      isRestoreStep: trackResult.isReview && getWordResult.stepIndex == 1,
      canLeaveCurrWord: false,
      hasFinishedAnswering: false,
      selectedAnswerIndex: null,
      correctAnswerIndex: null,
      words: null,
      showAnswerButtons: false,
      showSentenceTranslation: false,
      currentScore: null,
      englishDigestOfFirstSentence: null,
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

    // 加载该单词的历史测评日志,供巩固环节显示"今日测评"得分。
    // (learningHistoryFuture 此前从未赋值,导致巩固环节的 FutureBuilder
    //  永远拿不到数据,只能显示"测评中"。)
    final currentUserId = Global.getLoggedInUser()?.id;
    if (currentUserId != null && wordId != null) {
      learningHistoryFuture = MyDatabase.instance.learningLogsDao.getHistory(currentUserId, wordId);
    } else {
      learningHistoryFuture = null;
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

  /// 当前取词结果所属单词的环节轨道（学习轨道/复习轨道）与是否复习轨道，用于把 stepIndex 映射为具体环节名。
  /// 轨道由今天首条评分日志的间隔固化（与 StudyBo 一致），防止当天轨道漂移。
  Future<({List<String> track, bool isReview})> _trackOfCurrentWord(GetWordResult getWordResult) async {
    final lw = getWordResult.learningWord;
    if (lw == null) return (track: const <String>[], isReview: false);
    final userId = Global.getLoggedInUser()?.id;
    final wordId = lw.word.id;
    int? firstLogElapsedDays;
    int? firstLogRating;
    if (userId != null && wordId != null) {
      final row = await (MyDatabase.instance.select(MyDatabase.instance.learningLogs)
            ..where((l) =>
                l.userId.equals(userId) &
                l.wordId.equals(wordId) &
                l.createTime.isBiggerOrEqualValue(AppClock.today()))
            ..orderBy([(l) => drift.OrderingTerm(expression: l.createTime)])
            ..limit(1))
          .getSingleOrNull();
      firstLogElapsedDays = row?.elapsedDays;
      firstLogRating = row?.rating;
    }
    final newCfg = await StudyStepsService().getThreeGroupConfig('new');
    final reviewCfg = await StudyStepsService().getThreeGroupConfig('review');
    final isReview = StudyTrack.isReviewTrack(
      stability: lw.stability,
      state: lw.state,
      lastLearningDate: lw.lastLearningDate,
      todayFirstLogElapsedDays: firstLogElapsedDays,
      today: AppClock.today(),
    );
    return (
      track: StudyTrack.trackOf(
        stability: lw.stability,
        state: lw.state,
        lastLearningDate: lw.lastLearningDate,
        todayFirstLogElapsedDays: firstLogElapsedDays,
        todayFirstLogRating: firstLogRating,
        newCheck: newCfg.check,
        newCorrect: newCfg.correct,
        newWrong: newCfg.wrong,
        reviewCheck: reviewCfg.check,
        reviewCorrect: reviewCfg.correct,
        reviewWrong: reviewCfg.wrong,
        today: AppClock.today(),
      ),
      isReview: isReview,
    );
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
    // 用户显式点击"看答案"是强意图,即使 _isAnswerCorrectHandling 残留也执行
    _isAnswerCorrectHandling = false;
    if (state.hasFinishedAnswering) return;



    // 强制关闭 ASR 识别
    StudyAudioSessionController.instance.syncHardwareIntent(
      isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
      isAnsweringActive: false,
      language: AsrLanguage.english,
      phrases: [],
      caller: this,
    );

    // 设置已完成回答状态，评分为 FsrsRating.again，显示正确答案
    // 练习模式(看答案后隐藏答案再练习)中再次看答案:不改今日评分
    final bool keepRating = _isPracticeMode;
    state = state.copyWith(
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      lastFsrsRating: keepRating ? state.lastFsrsRating : FsrsRating.again,
      lastFsrsRatingReason: keepRating ? state.lastFsrsRatingReason : "手动查看答案",
      currentScore: 0, // 分数设为 0 代表未读对
    );
    _handleTabChangeForAsr();
  }

  /// 例句环节:看答案后隐藏答案,回到可练习状态(PTT 可用、可语音识别),
  /// 但进入练习模式——识别答对不改今日测评结果(不写 LearningLog/不更新 FSRS)。
  void hideAnswer() {
    if (!state.hasFinishedAnswering) return;
    _isPracticeMode = true;
    _isAnswerCorrectHandling = false; // 重置答对锁,否则练习模式 checkAsrResult 被 L1555 拦截,评分不更新
    state = state.copyWith(
      hasFinishedAnswering: false,
      // 练习模式允许点"下一词"离开(canLeaveCurrWord=true 使底部按钮可见)
      canLeaveCurrWord: true,
      showSentenceTranslation: false,
      currentScore: null,
      currentAsrCandidates: [],
    );
    sentenceAnswerController.text = "";
    _accumulatedAsrText = "";
    _lastFinalAsrText = "";
    _handleTabChangeForAsr();
  }

  void onAnswerClicked(int index, BuildContext context) async {
    if (state.selectedAnswerIndex != null || state.hasFinishedAnswering) {
      int wordIdx = index - 1;
      if (state.words != null && wordIdx >= 0 && wordIdx < state.words!.length) {
        final word = state.words![wordIdx];
        if (word.spell != "[ 都不对 ]") {
          StudyAudioSessionController.instance.playWordSound(word);
        }
      }
      return;
    }

    state = state.copyWith(selectedAnswerIndex: index);
    bool correct = index == state.correctAnswerIndex;
    if (correct) {
      final ratingResult = _calculateRating("选择题");
      _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
    } else {
      StudyAudioSessionController.instance.playSoundEffect('failed.mp3', speed: 1.5, volume: 0.1);
      showWordDetail(state.word!, true, context,
          fsrsRating: FsrsRating.again,
          reason: "选错了答案");
    }
  }

  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, BuildContext? context, {FsrsRating? fsrsRating, String? reason}) async {
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
        // 新词：init 预览
        nextItem = fsrs.init(rating);
      } else {
        final prevItem = FSRSItem(
          stability: lw.stability!,
          difficulty: lw.difficulty!,
          elapsedDays: days,
          scheduledDays: lw.scheduledDays ?? 0,
          reps: lw.reps ?? 0,
          lapses: lw.lapses ?? 0,
          state: FsrsStateExt.fromInt(lw.state),
        );
        nextItem = fsrs.next(prevItem, rating, days);
      }

      state = state.copyWith(fsrsItem: nextItem);
    }
  }

  void updateFsrsRating(FsrsRating rating) {
    state = state.copyWith(lastFsrsRating: rating);
    // 立即同步巩固阶段的测评参考评分标签
    if (state.assessmentRating != null) {
      state = state.copyWith(assessmentRating: rating);
    }
    // 异步:按"该词今天之前是否学习过"决定重新 init(新词)或 next(复习词),
    // 重新计算下次复习时间并持久化,同时刷新学习历史 future。
    unawaited(_applyRatingModification(rating));
  }

  Future<void> _applyRatingModification(FsrsRating rating) async {
    final lw = state.currentGetWordResult?.learningWord;
    if (lw == null) return;
    try {
      final nextItem = await _recalcFsrsForRating(lw, rating);
      state = state.copyWith(fsrsItem: nextItem);
      // 同步巩固阶段的测评参考显示,使"今日测评"标签立即反映新评分
      if (state.assessmentRating != null) {
        state = state.copyWith(
          assessmentScheduledDays: state.fsrsItem?.scheduledDays,
        );
      }
      await _persistRatingModification(rating);
    } catch (e, s) {
      Global.logger.e('修改今日评分失败', error: e, stackTrace: s);
    }
  }

  /// 按新评分重新计算 FSRS 结果。
  ///
  /// 修改"今日测评"评分的语义是修正测评环节的评分。判断测评环节
  /// 是 init(新词)还是 next(复习词)的依据是 LearningLog 最新一条
  /// (即本次测评提交结果)的 elapsedDays:
  /// - elapsedDays == 0 → 测评是 init(今日新词)→ 重新 init(rating)
  /// - elapsedDays > 0 → 测评是 next(复习词)→ next(测评前状态, rating, elapsedDays)
  ///
  /// 不能用 addTime 判断:计划内单词可能 addTime 很早但 stability 从未
  /// 初始化(今天才真正学习),测评仍走 init;反之也不能用巩固环节的
  /// lw.stability——它已被测评提交推进(init 后非 0),用它做 next 会
  /// 产生"测评后状态再推进一次"的重复放大。复习词的测评前状态应取
  /// LearningLog 中"今天之前最后一条"记录(该记录即测评前最后一次学习结果)。
  /// 按新评分重新计算 FSRS 结果（修改"今日评分"时调用）。
  ///
  /// 幂等规则：以"今天首条评分日志的前一条"（测评前状态）为基准重算：
  /// - 今天首条日志 elapsedDays == 0 → 当天是 init（新词学习日）→ 重新 init(rating)；
  /// - 今天首条日志 elapsedDays > 0 → 当天是 next（复习日）→ next(测评前状态, rating, 该间隔)；
  /// - 今天之前无日志 → 新词 → init(rating)。
  /// reps/lapses 回推：测评前 reps = lw.reps − 当天日志条数；lapses 同理减去当天 again 条数。
  Future<FSRSItem> _recalcFsrsForRating(
      LearningWordVo lw, FsrsRating rating) async {
    final fsrs = FSRS();
    final userId = Global.getLoggedInUser()?.id;
    final wordId = lw.word.id;
    if (userId == null || wordId == null) return fsrs.init(rating);

    final logs =
        await MyDatabase.instance.learningLogsDao.getHistory(userId, wordId);
    if (logs.isEmpty) return fsrs.init(rating);

    final today = AppClock.today();
    // 今天之前的最后一条日志 = 测评前状态
    LearningLog? prevLog;
    int todayLogCount = 0;
    int todayAgainCount = 0;
    for (final log in logs) {
      if (log.createTime.isBefore(today)) {
        prevLog = log;
        break;
      }
      todayLogCount++;
      if (log.rating == FsrsRating.again.value) todayAgainCount++;
    }
    // 新词（今天之前无日志）：修改评分 = 重新 init
    if (prevLog == null) return fsrs.init(rating);

    // 当天首条日志（createTime 最早）的 elapsedDays 决定当天事件类型：
    // 不能用最新一条（巩固/重测的 relearn 日志 elapsedDays 恒为 0，会误判为新词 init）
    final todayLogs =
        logs.where((l) => !l.createTime.isBefore(today)).toList(); // 倒序
    final firstTodayLog = todayLogs.last; // 当天最早一条
    if (firstTodayLog.elapsedDays == 0) {
      // 当天是学习日（init 起手），巩固环节评分已按 relearn 重设过
      return fsrs.init(rating);
    }

    final prevItem = FSRSItem(
      stability: prevLog.stability,
      difficulty: prevLog.difficulty,
      elapsedDays: firstTodayLog.elapsedDays,
      scheduledDays: prevLog.scheduledDays,
      reps: (lw.reps ?? 0) - todayLogCount,
      lapses: (lw.lapses ?? 0) - todayAgainCount,
      // 日志表无 state 字段：测评前 state 由其评分推断（again → relearning，否则 review）
      state: prevLog.rating == FsrsRating.again.value
          ? FsrsState.relearning
          : FsrsState.review,
    );
    return fsrs.next(prevItem, rating, firstTodayLog.elapsedDays);
  }

  Future<void> _persistRatingModification(FsrsRating rating) async {
    final lw = state.currentGetWordResult?.learningWord;
    if (lw == null || state.fsrsItem == null) return;
    try {
      await StudyBo().saveHistoryFSRSUpdate(
        currWord: lw,
        nextFsrs: state.fsrsItem!,
        newRating: rating,
      );
      if (_isDisposed) return;
      // 刷新学习历史,让巩固环节"今日测评"显示修改后的评分
      final userId = Global.getLoggedInUser()?.id;
      final wordId = lw.word.id;
      if (userId != null && wordId != null) {
        learningHistoryFuture =
            MyDatabase.instance.learningLogsDao.getHistory(userId, wordId);
        state = state.copyWith();
      }
    } catch (e, s) {
      Global.logger.e('修改今日评分持久化失败', error: e, stackTrace: s);
    }
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
      // 例句环节已答对时,点"清空"自动进入练习模式(可继续语音练习,评分不改变测评结果)
      final bool isSentenceStep = state.studyStep == StudyStep.enSentence2Ch.json ||
          state.studyStep == StudyStep.chSentence2En.json;
      if (isSentenceStep && state.hasFinishedAnswering) {
        _isPracticeMode = true;
        _isAnswerCorrectHandling = false;
        state = state.copyWith(
          hasFinishedAnswering: false,
          canLeaveCurrWord: true,
          currentScore: null,
        );
      }
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
    await StudyAudioSessionController.instance.cancelPlayback();
    
    state = state.copyWith(historyIndex: -1);
    await handleWord(target, isFromBatchWordList: true);
  }
  Future<void> reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }



  /// 持久化"离开的单词"的完整 UI 状态(含测评得分 lastFsrsRating)。
  /// 立即执行(不延迟):取下一个单词时同步落盘,确保用户随时返回
  /// 学习计划页/退出页面后,重新进入仍能恢复该单词的测评得分。
  void _persistLastWordHistoryItem() {
    _executePersistLastWordHistoryItem();
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
    if (_isDisposed) return;
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
            Global.logger.d('~~~~~[ASR] RAW isFinal=$isFinal rawBest=[$rawBest]');
          }

          // 例句中英模式：在 stitch 之前对 ASR 片段做发音相似度自动纠错，
          // 确保 stitch 的 prev 与 next 都是纠正后文本，重叠检测才能正确工作，
          // 同时让所有帧（不限于 final）都能实时显示纠正结果。
          // 注:仅英文例句(说英文)做纠错,中文识别不做自动纠正(用户发音自由)。
          String cleanBest = rawBest;
          if (isEnglish) {
            final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
                ? state.word!.sentences!.first
                : null;
            if (sentence?.english != null && sentence!.english!.isNotEmpty) {
              Global.logger.d('~~~~~[CORRECT] CALL onAsrResult isFinal=$isFinal rawBest=[$rawBest]');
              cleanBest = await _phoneticAutoCorrectSentence(rawBest, sentence.english!);
              Global.logger.d('~~~~~[CORRECT] RESULT onAsrResult cleanBest=[$cleanBest]');
              // await 期间可能已松开并重按(轮次切换)：校验仍属于当前 PTT 轮次才继续写入
              if (_isDisposed || !_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
            }
          }

          // 每个帧（无论 final/non-final）先与旧文本做增量拼接。Android 端点 reset
          // 后新帧可能只是尾部片段，stitchTexts 在无重叠时会错误地直接拼接。
          // 拼接后用匹配度守卫：若拼接结果不如旧文本，保留旧文本。
          final prevAccumulated = _accumulatedAsrText;
          _accumulatedAsrText = mergeAsrText(_lastFinalAsrText, cleanBest, isEnglish: isEnglish);
          if (prevAccumulated.isNotEmpty && _accumulatedAsrText != prevAccumulated) {
            final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
                ? state.word!.sentences!.first
                : null;
            if (sentence != null) {
              final oldScore = isEnglish
                  ? await getEnglishSentenceMatchScore(prevAccumulated, sentence.english ?? '')
                  : getChineseSentenceMatchScore(prevAccumulated, sentence.chinese ?? '');
              final newScore = isEnglish
                  ? await getEnglishSentenceMatchScore(_accumulatedAsrText, sentence.english ?? '')
                  : getChineseSentenceMatchScore(_accumulatedAsrText, sentence.chinese ?? '');
              if (newScore < oldScore) {
                Global.logger.d('~~~~~[MERGE] REJECT oldScore=$oldScore newScore=$newScore keep=[$prevAccumulated] reject=[$_accumulatedAsrText]');
                _accumulatedAsrText = prevAccumulated;
              } else {
                Global.logger.d('~~~~~[MERGE] ACCEPT oldScore=$oldScore newScore=$newScore accum=[$_accumulatedAsrText]');
              }
            }
          }
          if (isFinal) {
            _lastFinalAsrText = _accumulatedAsrText;
            Global.logger.d('~~~~~[MERGE] FINAL _lastFinalAsrText=[$_lastFinalAsrText]');
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
        // 单词环节：若当前题目已答完（或正在执行答对过渡）且非主动练习模式，
        // 忽略关麦过渡期间到达的残余尾部 ASR 帧，避免尾音低分篡改通关评分。
        if ((state.hasFinishedAnswering || _isAnswerCorrectHandling) && !_isPracticeMode) {
          return;
        }

        if (resultData != null && resultData.containsKey('candidates')) {
          if (state.studyStep == StudyStep.ch2En.json) {
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(candidates, state.word!.spell);
            if (_isDisposed) return;
            // await 音素计算期间可能并发完成了答对处理，二次守卫防止低分覆盖
            if ((state.hasFinishedAnswering || _isAnswerCorrectHandling) && !_isPracticeMode) {
              return;
            }
            processedResult = AsrUtil.preprocessEnglish(result.text, state.word!.spell);
            _updateState(state.copyWith(currentScore: result.score, currentAsrCandidates: candidates), tag: 'asr-result');
          } else {
            // 单词英中模式：支持跨端点（Endpoint reset）分段增量拼接
            final rawBest = best.trim();
            if (rawBest.isNotEmpty) {
              _wordAccumulatedAsrText = mergeAsrText(_wordLastFinalAsrText, rawBest, isEnglish: false);
              if (isFinal) {
                _wordLastFinalAsrText = _wordAccumulatedAsrText;
              }
            }
            final uniqueCandidates = <String>[];
            if (_wordAccumulatedAsrText.isNotEmpty) {
              uniqueCandidates.add(_wordAccumulatedAsrText);
            }
            for (final c in candidates) {
              if (!uniqueCandidates.contains(c)) {
                uniqueCandidates.add(c);
              }
            }
            if (uniqueCandidates.isEmpty) {
              uniqueCandidates.add(best);
            }
            processedResult = AsrUtil.preprocess(_wordAccumulatedAsrText.isNotEmpty ? _wordAccumulatedAsrText : best);
            _updateState(state.copyWith(currentAsrCandidates: uniqueCandidates), tag: 'asr-candidate');
          }
        } else {
          final rawBest = best.trim();
          if (rawBest.isNotEmpty) {
            _wordAccumulatedAsrText = mergeAsrText(_wordLastFinalAsrText, rawBest, isEnglish: false);
            if (isFinal) {
              _wordLastFinalAsrText = _wordAccumulatedAsrText;
            }
          }
          final uniqueCandidates = <String>[];
          if (_wordAccumulatedAsrText.isNotEmpty) {
            uniqueCandidates.add(_wordAccumulatedAsrText);
          }
          for (final c in candidates) {
            if (!uniqueCandidates.contains(c)) {
              uniqueCandidates.add(c);
            }
          }
          if (uniqueCandidates.isEmpty) {
            uniqueCandidates.add(best);
          }
          processedResult = AsrUtil.preprocess(_wordAccumulatedAsrText.isNotEmpty ? _wordAccumulatedAsrText : best);
          _updateState(state.copyWith(currentAsrCandidates: uniqueCandidates), tag: 'asr-candidate');
        }
      }
    } catch (e, stackTrace) {
      Global.logger.d('~~~~~[CORRECT] onAsrResult EXCEPTION: $e\n$stackTrace');
      if (_isDisposed) return;
      final bool isSentence = state.studyStep == StudyStep.enSentence2Ch.json ||
                              state.studyStep == StudyStep.chSentence2En.json;
      if (!isSentence && (state.hasFinishedAnswering || _isAnswerCorrectHandling) && !_isPracticeMode) {
        return;
      }
      processedResult = AsrUtil.preprocess(event.toString());
      candidates = [event.toString()];
      if (isSentence) {
        if (!_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;

        final rawBest = event.toString().trim();
        if (rawBest.isNotEmpty) {
          final bool isEnglish = state.studyStep == StudyStep.chSentence2En.json;

          // 同样在 stitch 前做自动纠错(仅英文例句)
          String cleanBest = rawBest;
          if (isEnglish) {
            final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
                ? state.word!.sentences!.first
                : null;
            if (sentence?.english != null && sentence!.english!.isNotEmpty) {
              Global.logger.d('~~~~~[CORRECT] CALL onAsrResult(catch) rawBest=[$rawBest]');
              cleanBest = await _phoneticAutoCorrectSentence(rawBest, sentence.english!);
              Global.logger.d('~~~~~[CORRECT] RESULT onAsrResult(catch) cleanBest=[$cleanBest]');
              // await 间隙可能已切换 PTT 轮次：校验后才继续写入
              if (_isDisposed || !_isPttPressed || pttRoundAtEntry != _pttRoundToken) return;
            }
          }

          _lastFinalAsrText = mergeAsrText(_lastFinalAsrText, cleanBest, isEnglish: isEnglish);
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
    if (!state.showHandwritingBoard && (state.hasFinishedAnswering || _isAnswerCorrectHandling)) return;
    final stopwatch = Stopwatch()..start();
    String inputText = asrInput ?? meaningController.text;

    // ==========================================
    // 优先处理：全屏手写/拼写板练习的拼写匹配
    // 只要当前开启了手写拼写板，用户的一切输入（手写/键盘）均以当前单词拼写为目标。
    // 无论当前处于何种题型模式（英中、中英、列表、例句），拼写正确后必须立即退出手写板并返回背单词主页面！
    // ==========================================
    if (state.showHandwritingBoard && state.word != null) {
      final correctSpell = state.word!.spell.toLowerCase();
      final inputLower = inputText.trim().toLowerCase();
      final isSpellingMatch = inputLower.replaceAll(RegExp(r'[^a-z]'), '') == correctSpell.replaceAll(RegExp(r'[^a-z]'), '');

      if (isSpellingMatch) {
        // 1. 中译英模式 (Ch2En) 且未完成答题：拼写英文即代表回答该题正确！
        if (!state.hasFinishedAnswering && state.studyStep == StudyStep.ch2En.json) {
          meaningController.text = state.word!.spell;
          state = state.copyWith(showHandwritingBoard: false, isKeyboardVisible: false);
          final hintRevealedAll =
              (state.wordWrapper?.hintLetterCount ?? 0) >= (state.word?.spell.length ?? 0);
          if (!hintRevealedAll || isVoice) {
            String method = isVoice ? "语音识别" : (asrInput != null ? "手写输入" : "键盘输入");
            final ratingResult = _calculateRating(method);
            _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
          }
          return;
        }

        // 2. 已完成答题状态（无论何种题型）：用户在已掌握或已做完当前词后进行的手写/拼写巩固
        if (state.hasFinishedAnswering) {
          meaningController.text = state.word!.spell;
          state = state.copyWith(showHandwritingBoard: false, isKeyboardVisible: false);
          _handleTabChangeForAsr();
          StudyAudioSessionController.instance.playWordSound(state.word!);
          return;
        }

        // 3. 英译汉模式 (En2Ch) 或其他模式且【未完成答题】：
        // 用户只是在未做完英译汉时顺手进行拼写练习。
        // 拼写正确后退出手写板返回背单词页面，用户必须能够继续正常答题（说中文/选中文）！
        // 不能把英文留在 meaningController，必须恢复英译汉做题状态并重新唤醒麦克风！
        meaningController.clear();
        _handlingChinese = "";
        state = state.copyWith(showHandwritingBoard: false, isKeyboardVisible: false);
        
        // 播放发音，播放完毕后重新唤醒硬件麦克风状态，保证用户回到英译汉页面后能继续正常语音做题
        await StudyAudioSessionController.instance.playWordSound(state.word!);
        _handleTabChangeForAsr();
        Global.logger.d('[PERF] checkAsrResult handwriting board spelling match cost: ${stopwatch.elapsedMilliseconds}ms');
        return;
      }
    }
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

        bool passedThreshold = false;
        if (step == StudyStep.enSentence2Ch.json) {
          // 例句英中：说中文，匹对 sentence.chinese
          final targetCh = sentence.chinese ?? "";
          bool coreMatched = false;
          for (final input in inputs) {
            final score = getChineseSentenceMatchScore(input, targetCh);
            if (score > maxScore) maxScore = score;
            if (!coreMatched && state.word != null) {
              coreMatched = isChineseSentenceCoreKeywordsMatched(
                input,
                targetCh,
                state.word!,
                targetPinyinsCache: state.wordWrapper?.targetPinyinsCache,
              );
            }
          }
          // 例句英中模式：通过需要得分达到及格线且核心考察词已答对
          passedThreshold = maxScore >= 60 && coreMatched;
        } else {
          // 例句中英：说英文，匹对 sentence.english
          final targetEn = sentence.english ?? "";
          bool coreMatched = false;
          for (final input in inputs) {
            final score = await getEnglishSentenceMatchScore(input, targetEn);
            if (score > maxScore) maxScore = score;
            if (!coreMatched && state.word != null) {
              coreMatched = await isEnglishSentenceCoreKeywordsMatched(
                input,
                targetEn,
                state.word!,
              );
            }
          }
          // 例句中英模式：通过需要得分达到及格线且英文核心考察词已答对
          passedThreshold = maxScore >= 60 && coreMatched;
        }

        // 实时更新 currentScore，让 UI 实时显示得分！
        state = state.copyWith(currentScore: maxScore, isScorePassed: passedThreshold);
        Global.logger.d('[PTT] score更新: isPracticeMode=$_isPracticeMode maxScore=$maxScore, passedThreshold=$passedThreshold');

        final bool isMatch;
        // 将英文例句通过的得分阈值放宽到 60 分，增加口音与吞音容错率
        // ⚡ 体验优化：为了防止最后一个单词没有显示完整就提前通关并掐断识别，
        // 对于语音识别（isVoice），必须等待最后一帧 isFinal 为 true 时才执行 Match 通过，以保证单词在 UI 上完整展现。
        isMatch = passedThreshold && (!isVoice || isFinal);
        Global.logger.d('[PTT] checkAsrResult isPttPressed=$_isPttPressed isFinal=$isFinal score=$maxScore passedThreshold=$passedThreshold isMatch=$isMatch inputs=$inputs');

        // PTT 按住期间:识别得分达标即记录等待松开标记(不要求 isFinal,
        // 因为按住期间实时事件 isFinal=false,但得分已达到通过阈值)。
        // 松开按钮(释放手指)是例句环节语音通过的必要条件之一。
        if (_isPttPressed && passedThreshold) {
          _pendingPttPass = true;
          _isAnswerCorrectHandling = false; // 不锁死,按住期间持续更新得分
        }

        if (isMatch) {
          // 已松开时正常通过;按住期间(isMatch 不可能成立,因 isFinal=false)
          // 若意外成立则等待松开
          if (_isPttPressed) {
            state = state.copyWith(currentScore: maxScore, isScorePassed: passedThreshold);
            Global.logger.d('[PTT] 识别已达标但按住中,等待松开判定. score=$maxScore');
            return;
          }
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
          if (_isPracticeMode) {
            // 练习模式:识别答对仅反馈,不改今日测评结果(不写 LearningLog/不更新 FSRS)
            _isAnswerCorrectHandling = false; // 练习答对不锁死,允许继续练习/看答案
            _playCorrectSound();
            state = state.copyWith(
              hasFinishedAnswering: true, // 自动显示正确答案,便于用户比对纠错
              canLeaveCurrWord: true,
              currentScore: maxScore,
              isScorePassed: true,
            );
          } else {
            final ratingResult = _calculateRating(method);
            _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
          }
        } else if (!state.hasFinishedAnswering && !_isAnswerCorrectHandling && !_isPttPressed) {
          // 本地未匹配通过且非按住中：触发例句 AI 裁判防抖判定
          _scheduleSentenceAiRefereeCheck(inputs);
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
        
        // 退出手写板全屏界面，平滑返回背单词主页面
        state = state.copyWith(showHandwritingBoard: false);
        _handleTabChangeForAsr();
        StudyAudioSessionController.instance.playWordSound(state.word!);
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
        _wordAiRefereeDebounceTimer?.cancel(); // 本地匹配命中，取消待触发的AI裁判
        _wordAccumulatedAsrText = "";
        _wordLastFinalAsrText = "";
        _isWordAiRefereeJudging = false;
        clonedWrapper.isAiEvaluating = false;
        state = state.copyWith(
          isAiEvaluating: false,
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
      } else if (!state.hasFinishedAnswering && !_isAnswerCorrectHandling) {
        // 本地未匹配成功：触发单词 AI 裁判防抖判定
        _scheduleWordAiRefereeCheck(inputs);
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
          // 若处于已答完状态（复习或查看详情时的手写/拼写练习），退出手写板并返回背单词页面
          if (state.showHandwritingBoard) {
            state = state.copyWith(showHandwritingBoard: false);
            _handleTabChangeForAsr();
          }
          // 需先等待麦克风关停（含切换至 playback），再播放发音防止回声
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
      } else if (!state.hasFinishedAnswering && !_isAnswerCorrectHandling && isVoice) {
        final isFromAsr = asrInput != null || meaningController.text == _handlingChinese;
        final inputs = isFromAsr ? state.currentAsrCandidates : [_handlingChinese];
        _scheduleCh2EnAiRefereeCheck(inputs);
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
    
    // 判断是否为例句环节，如果是，适当延长打分响应时间阈值（Easy 24s，Hard 40s）
    final bool isSentenceStep = state.studyStep == StudyStep.enSentence2Ch.json || 
                                state.studyStep == StudyStep.chSentence2En.json;
    final int easyThreshold = isSentenceStep ? 24 : 8;
    final int hardThreshold = isSentenceStep ? 40 : 18;

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

    _wordAiRefereeDebounceTimer?.cancel();
    _isWordAiRefereeJudging = false;
    if (state.wordWrapper != null) {
      state.wordWrapper!.isAiEvaluating = false;
    }

    // 同步立即锁定状态，彻底阻断由于 ASR 连续识别或 re-entry 重复触发导致的回声和并发冲突
    state = state.copyWith(
      isAiEvaluating: false,
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      lastFsrsRating: rating,
      lastFsrsRatingReason: reason,
      showHandwritingBoard: false,
    );
    _handleTabChangeForAsr();
    
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
          state: FsrsStateExt.fromInt(lw.state),
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

    if (state.showWordDetailAfterCorrect && state.word != null && state.historyIndex == -1) {
      final showDelayMs = state.studyStep == StudyStep.ch2En.json ? 200 : 500;
      Future.delayed(Duration(milliseconds: showDelayMs), () {
        if (!_isDisposed && state.word != null) {
          showWordDetail(state.word!, false, null, fsrsRating: rating, reason: reason);
        }
      });
      Global.logger.d('[PERF] _onAnswerCorrect total cost: ${stopwatch.elapsedMilliseconds}ms');
      return;
    }

    bool autoJump = state.autoJumpAfterCorrect;
    if (autoJump && state.historyIndex == -1) {
      // 中英模式发音已完整播完，仅需 400ms 短暂缓冲即可舒适跳转；
      // 其他模式保留原有 800ms 延迟。
      final jumpDelayMs = state.studyStep == StudyStep.ch2En.json ? 0 : 1000;
      Future.delayed(Duration(milliseconds: jumpDelayMs), () {
        getNextWord(true, fsrsRating: rating);
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
  /// 对例句中英模式 (ChSentence2En) 的 ASR 结果做发音相似度自动纠错。
  ///
  /// 核心原则：利用 ASR 已正确识别的词作为位置锚点，只在未对齐的局部做纠错。
  /// 避免 "for"(句尾) 被全局搜索错误替换为 "towed"(句中)。
  Future<String> _phoneticAutoCorrectSentence(String input, String targetSentence) async {
    final sw = Stopwatch()..start();
    final inputWords = _extractEnglishWords(input);
    if (inputWords.isEmpty) return input;

    final targetWords = _extractEnglishWords(targetSentence);
    if (targetWords.isEmpty) return input;

    // 如果输入已经与目标句完全一致（词数相同且字面全部匹配），直接返回无需纠错
    if (inputWords.length == targetWords.length) {
      bool allExact = true;
      for (int i = 0; i < inputWords.length; i++) {
        if (inputWords[i].toLowerCase() != targetWords[i].toLowerCase()) {
          allExact = false;
          break;
        }
      }
      if (allExact) return input;
    }
    Global.logger.d('~~~~~[CORRECT] START input=[$input] target=[$targetSentence]');

    const int matchThreshold = 55;
    const int maxLenDiff = 3;
    // 常见功能词:不做单词级近音纠正(避免 "this"→"is"、"to"→"for" 等误改),
    // 但可发起与后续词的合并匹配(如 "this plan"→"discipline")。
    const Set<String> functionWords = {
      'a', 'an', 'the', 'is', 'are', 'was', 'were', 'to', 'for', 'of', 'at',
      'in', 'on', 'this', 'that', 'these', 'those', 'his', 'her', 'it', 'its',
      'and', 'or', 'but', 'with', 'as', 'by', 'from', 'up', 'out', 'do', 'does',
    };

    // 步骤 1：基于 DP 的单调递增位置感知对齐（杜绝逆序或交叉匹配）
    // 实词（非功能词）匹配权重更高（10分），功能词权重较低（2分），并叠加位置距离惩罚
    final int n = inputWords.length;
    final int m = targetWords.length;
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0.0));
    final choice = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0)); // 1: skip input, 2: skip target, 3: match

    for (int i = 1; i <= n; i++) {
      final iw = inputWords[i - 1].toLowerCase();
      final isFuncI = functionWords.contains(iw);
      for (int j = 1; j <= m; j++) {
        final tw = targetWords[j - 1].toLowerCase();
        double bestScore = dp[i - 1][j];
        int bestChoice = 1;

        if (dp[i][j - 1] > bestScore) {
          bestScore = dp[i][j - 1];
          bestChoice = 2;
        }

        if (iw == tw) {
          final double baseWeight = isFuncI ? 2.0 : 10.0;
          final double distPenalty = ((i - 1) * m / n - (j - 1)).abs() * 0.1;
          final double matchScore = dp[i - 1][j - 1] + (baseWeight - distPenalty).clamp(0.5, 10.0);
          if (matchScore > bestScore) {
            bestScore = matchScore;
            bestChoice = 3;
          }
        }

        dp[i][j] = bestScore;
        choice[i][j] = bestChoice;
      }
    }

    final inputAlign = List<int?>.filled(n, null);
    final targetUsed = List<bool>.filled(m, false);
    int currI = n, currJ = m;
    while (currI > 0 && currJ > 0) {
      if (choice[currI][currJ] == 3) {
        inputAlign[currI - 1] = currJ - 1;
        targetUsed[currJ - 1] = true;
        currI--;
        currJ--;
      } else if (choice[currI][currJ] == 1) {
        currI--;
      } else {
        currJ--;
      }
    }

    // 日志：对齐结果
    final alignDesc = <String>[];
    for (int i = 0; i < inputWords.length; i++) {
      if (inputAlign[i] != null) {
        alignDesc.add('${inputWords[i]}→target[${inputAlign[i]}]="${targetWords[inputAlign[i]!]}"');
      }
    }
    Global.logger.d('~~~~~[CORRECT] 对齐锚点: ${alignDesc.isEmpty ? "无" : alignDesc.join(", ")}');

    // 步骤 2：对未对齐的词，在期望位置附近做局部音素纠错
    final hasAnchors = inputAlign.any((a) => a != null);
    final corrected = <String>[];
    var i = 0;
    while (i < inputWords.length) {
      if (inputAlign[i] != null) {
        corrected.add(targetWords[inputAlign[i]!]);
        i++;
        continue;
      }

      final iw = inputWords[i];

      // ≤2 字符的词通常是 ASR 碎片（如 "ve" 是 "vessel" 的前缀），
      // 音素匹配过于模糊，不纠错，避免 "ve"→"dry" 误改。
      if (iw.length <= 2) {
        Global.logger.d('~~~~~[CORRECT] KEPT "$iw" (too short for phoneme correction)');
        corrected.add(iw);
        i++;
        continue;
      }

      // 计算该词在 target 中的期望位置窗口（基于前后锚点）
      int leftJ = -1, rightJ = targetWords.length;
      for (int k = i - 1; k >= 0 && leftJ < 0; k--) {
        if (inputAlign[k] != null) leftJ = inputAlign[k]!;
      }
      for (int k = i + 1; k < inputWords.length && rightJ >= targetWords.length; k++) {
        if (inputAlign[k] != null) rightJ = inputAlign[k]!;
      }
      // 无锚点按比例估算;全句无任何锚点时退化为全局窗口(输入可能对应目标句任意局部,
      // 比例估算对短输入会错位,如 "seaplane" 的估算窗口不含 "discipline")
      if (leftJ < 0) leftJ = hasAnchors ? (i * targetWords.length / inputWords.length).round() - 2 : -1;
      if (rightJ >= targetWords.length) rightJ = hasAnchors ? ((i + 1) * targetWords.length / inputWords.length).round() + 2 : targetWords.length;
      final wStart = (leftJ + 1).clamp(0, targetWords.length - 1);
      final wEnd = rightJ.clamp(wStart, targetWords.length - 1);

      // 在位置窗口中做音素匹配（单词 + 多词合并）
      String bestMatch = iw;
      int bestSim = 0, consumeNext = 0;

      final isFunctionWord = functionWords.contains(iw.toLowerCase());
      if (!isFunctionWord) {
        for (int j = wStart; j <= wEnd; j++) {
          final tw = targetWords[j];
          if (targetUsed[j]) continue;
          if (functionWords.contains(tw.toLowerCase())) continue;
          if ((iw.length - tw.length).abs() > maxLenDiff) continue;
          final sim = await PhonemeUtil.similarity(iw, tw);
          if (sim > bestSim) { bestSim = sim; bestMatch = tw; }
        }
      }
      final singleBestSim = bestSim;

      for (var win = 2; win <= 3 && i + win <= inputWords.length; win++) {
        // 窗口不跨功能词(除首词外):避免 "this plan is" 把 "is" 也吞进合并
        final winWords = inputWords.sublist(i, i + win);
        if (winWords.skip(1).any((w) => functionWords.contains(w.toLowerCase()))) break;
        final windowText = winWords.join(" ");
        for (int j = wStart; j <= wEnd; j++) {
          final tw = targetWords[j];
          if (targetUsed[j]) continue;
          if (functionWords.contains(tw.toLowerCase())) continue;
          if ((windowText.length - tw.length).abs() > maxLenDiff * win) continue;
          if (windowText.length > tw.length + 2) continue;
          final sim = await PhonemeUtil.similarity(windowText, tw);
          // 功能词发起的合并(如 "this plan"→"discipline")阈值 70;
          // 普通词合并要求显著优于单词匹配(+15),防吞掉可独立匹配的词
          final bool mergeOk = isFunctionWord
              ? (sim > bestSim && sim >= 70)
              : (sim > bestSim && sim >= singleBestSim + 15);
          if (mergeOk) {
            bestSim = sim; bestMatch = tw; consumeNext = win - 1;
          }
        }
      }

      final result = bestSim >= matchThreshold ? bestMatch : iw;
      final action = bestSim >= matchThreshold
          ? 'CORRECTED "$iw"→"$result" window=[$wStart..$wEnd] sim=$bestSim'
          : 'KEPT "$iw" (bestSim=$bestSim<$matchThreshold)';
      Global.logger.d('~~~~~[CORRECT] $action');
      corrected.add(result);
      i += 1 + consumeNext;
    }

    final result = corrected.join(" ");
    Global.logger.d('~~~~~[CORRECT] DONE (${sw.elapsedMilliseconds}ms) result=[$result]');
    return result;
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
        // 例句英中模式(说中文)：把例句的中文翻译加入热词，确保例句关键词
        // (如"乡愁")获得 ASR 热词加成，避免被识别为近音字(如"乡种")。
        if (state.studyStep == StudyStep.enSentence2Ch.json) {
          final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
              ? state.word!.sentences!.first
              : null;
          if (sentence != null) {
            final rawChinese = sentence.chinese ?? '';
            // 整句 + 逐字短语都加入热词
            final cleanChinese = rawChinese.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
            if (cleanChinese.isNotEmpty) {
              phrases.add(cleanChinese);
              for (final ch in cleanChinese.split('')) {
                phrases.add(ch);
              }
            }
          }
        }
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
    Global.logger.d('[PTT] startPttAsr: isSentenceStep=$isSentenceStep hasFinished=${state.hasFinishedAnswering} isPttPressed=$_isPttPressed isPracticeMode=$_isPracticeMode');
    if (!isSentenceStep || state.hasFinishedAnswering) return;
    if (_isPttPressed) return; // 防重复按下

    _isPttPressed = true;
    _pttRoundToken++; // 开启新一轮 PTT 会话
    _pendingPttPass = false; // 新一轮按住:重置等待松开标记
    // 捕获答案区锚点：若已有内容(补充模式)，本轮识别增量插入光标处；
    // 否则锚点为空(首次模式)，等同从头识别。
    final curText = sentenceAnswerController.text;
    final sel = sentenceAnswerController.selection;
    final int caret = (sel.isValid && sel.isCollapsed && sel.start <= curText.length)
        ? sel.start
        : curText.length; // 无光标/选区时默认追加到末尾
    _pttAnchorPrefix = curText.substring(0, caret);
    _pttAnchorSuffix = curText.substring(caret);
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

    // 松开:先复位 PTT 状态,使后续判定以"已松开"语义执行
    // (checkAsrResult 按住期间拦截通过,松开后才允许判定通过)
    _isPttPressed = false;
    _updateState(state.copyWith(isPttPressed: false), tag: 'ptt-stop');
    final bool wasPendingPass = _pendingPttPass;
    _pendingPttPass = false;

    // 松开后统一用答案区完整文本直接判定:
    // 不能依赖 onAsrResult(flush),因其句子分支在 _isPttPressed=false 时会拦截丢弃。
    //
    // 原生 flush 解出的是干净完整的最终文本(含尾部词),而按住期间实时累积的
    // current(controller)可能因 stitch 失败而错乱重复。因此松开时以 flush 为准,
    // 补全/重置答案区文本后再判定,避免错乱文本与缺失尾部。
    if (flushText != null && flushText.isNotEmpty) {
      final currentText = sentenceAnswerController.text;
      var flushTrim = flushText.trim();
      // 英文例句(chSentence2En):对 flush 最终文本做发音相似度纠错,
      // 与实时事件一致(如 "displain" → "discipline"),否则松开以 flush 为准
      // 会绕过纠错,识别错误无法修正。
      if (state.studyStep == StudyStep.chSentence2En.json) {
        final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
            ? state.word!.sentences!.first
            : null;
        if (sentence?.english != null && sentence!.english!.isNotEmpty) {
          Global.logger.d('~~~~~[CORRECT] CALL stopPttAsr flushTrim=[$flushTrim]');
          final correctedFlush = await _phoneticAutoCorrectSentence(flushTrim, sentence.english!);
          Global.logger.d('~~~~~[CORRECT] RESULT stopPttAsr correctedFlush=[$correctedFlush]');
          Global.logger.d('[PTT] flush纠错: "$flushTrim" → "$correctedFlush"');
          flushTrim = correctedFlush;
        }
      }
      // 松开时合并 current(按住期间实时累积)与 flush(原生收尾):
      // - flush 可能只是端点 reset 后的末段(如 "for success in any organization"),
      //   而 current 是完整文本 —— 此时应保留 current,避免截断;
      // - flush 更完整(补尾部词)时用 flush;
      // - current 异常错乱(远超 flush 且不重叠)时用 flush 兜底。
      // 但长度比较不可靠:端点 reset 后 current 可能已被新帧 stitch 污染,
      // flush 也可能只是尾部片段。最终依据:对目标句的匹配度。
      final String fullFlush;
      if (_pttAnchorPrefix.isEmpty && _pttAnchorSuffix.isEmpty) {
        final currentNorm = currentText.trim();
        Global.logger.d('~~~~~[MERGE] stopPttAsr current=[$currentNorm] flush=[$flushTrim]');
        // 用匹配度而非长度选择最优文本
        fullFlush = await _selectBestText(currentNorm, flushTrim);
        Global.logger.d('~~~~~[MERGE] stopPttAsr RESULT fullFlush=[$fullFlush]');
      } else {
        final prefix = _pttAnchorPrefix.isEmpty
            ? ''
            : (_pttAnchorPrefix.endsWith(' ') ? _pttAnchorPrefix : '$_pttAnchorPrefix ');
        final suffix = _pttAnchorSuffix.isEmpty
            ? ''
            : (_pttAnchorSuffix.startsWith(' ') ? _pttAnchorSuffix : ' $_pttAnchorSuffix');
        fullFlush = prefix + flushTrim + suffix;
      }
      sentenceAnswerController.value = sentenceAnswerController.value.copyWith(
        text: fullFlush,
        selection: TextSelection.collapsed(offset: fullFlush.length),
        composing: TextRange.empty,
      );
      _accumulatedAsrText = fullFlush;
      _lastFinalAsrText = fullFlush;
      _updateState(
        state.copyWith(currentAsrCandidates: [fullFlush]),
        tag: 'asr-flush',
      );
      Global.logger.d('[PTT] 松开合并: current="$currentText" flush="$flushTrim" result="$fullFlush"');
    }
    final String text = sentenceAnswerController.text.trim();
    Global.logger.d('[PTT] 松开判定: wasPendingPass=$wasPendingPass text="$text"');
    if (text.isNotEmpty) {
      await checkAsrResult(asrInput: text, isVoice: true, isFinal: true);
    }
  }

  /// 松开时比较 currentText(按住期间累积) 与 flushText(原生收尾) 对目标句的匹配度，
  /// 返回匹配度更高的文本。避免端点 reset 后 flush/current 被污染时选错。
  Future<String> _selectBestText(String current, String flush) async {
    if (current.isEmpty) return flush;
    if (flush.isEmpty) return current;
    if (current == flush) return current;

    final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
        ? state.word!.sentences!.first
        : null;
    if (sentence == null) return current.length >= flush.length ? current : flush;

    final isEnglish = state.studyStep == StudyStep.chSentence2En.json;
    final oldScore = isEnglish
        ? await getEnglishSentenceMatchScore(current, sentence.english ?? '')
        : getChineseSentenceMatchScore(current, sentence.chinese ?? '');
    final newScore = isEnglish
        ? await getEnglishSentenceMatchScore(flush, sentence.english ?? '')
        : getChineseSentenceMatchScore(flush, sentence.chinese ?? '');

    final best = newScore > oldScore ? flush : current;
    Global.logger.d('~~~~~[MERGE] _selectBestText: old=$oldScore new=$newScore → "$best"');
    return best;
  }

  int getChineseSentenceMatchScore(String input, String target) {
    String clean(String s) => s.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
    // 同音字归一化：她/他/它 (tā)、的/地/得 (de) 发音完全相同，语音识别无法区分
    String normalizeHomophones(String s) => s.split('').map((ch) {
      if (ch == '她' || ch == '它') return '他';
      if (ch == '地' || ch == '得') return '的';
      return ch;
    }).join('');
    final cleanInput = normalizeHomophones(clean(input));
    final cleanTarget = normalizeHomophones(clean(target));
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
    if (show) {
      _isAnswerCorrectHandling = false;
    }
    state = state.copyWith(showHandwritingBoard: show);
    handleTabChangeForAsr();
  }

  void updateShowSentenceTranslation(bool show) {
    state = state.copyWith(showSentenceTranslation: show);
  }

  void updateAutoJump(bool value) {
    if (state.studyStep == StudyStep.ch2En.json) {
      state = state.copyWith(autoJumpAfterCorrectCh2En: value);
    } else if (state.studyStep == StudyStep.chSentence2En.json) {
      state = state.copyWith(autoJumpAfterCorrectChSentence2En: value);
    } else if (state.studyStep == StudyStep.enSentence2Ch.json) {
      state = state.copyWith(autoJumpAfterCorrectEnSentence2Ch: value);
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

  void updateAutoJumpChSentence2En(bool value) {
    state = state.copyWith(autoJumpAfterCorrectChSentence2En: value);
  }

  void updateAutoJumpEnSentence2Ch(bool value) {
    state = state.copyWith(autoJumpAfterCorrectEnSentence2Ch: value);
  }

  void updateShowWordDetailAfterCorrect(bool value) {
    state = state.copyWith(showWordDetailAfterCorrect: value);
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
      final isEn2Ch = state.studyStep == StudyStep.en2Ch.json || state.studyStep == StudyStep.enSentence2Ch.json;
      final speakLabel = isEn2Ch ? '说释义' : '说发音';
      tabs.add(Tab(
        height: 30,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_none_rounded, size: 15),
            const SizedBox(width: 4),
            Text(speakLabel),
          ],
        ),
      ));
    }
    tabs.add(const Tab(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 15),
          SizedBox(width: 4),
          Text('选择题'),
        ],
      ),
    ));
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
      // 1. 重新加载当前用户的 StudyConfig
      final studyConfig = StudyConfig.fromCurrentUser();
      
      // 2. 重新配置 ASR 缓存参数与答对详情展示
      state = state.copyWith(
        asrPassRuleCache: studyConfig.asrPassRule,
        showWordDetailAfterCorrect: studyConfig.showWordDetailAfterCorrect,
      );
      
      // 3. 确保 ASR 事件监听已绑定
      await asr.initAsr(onAsrResult);
      
      // 4. 根据当前状态，以 bypassStartDebounce 立即同步底层硬件
      _syncAudioHardware(bypassStartDebounce: true);
      
      // 5. 主动触发状态更新以重绘界面
      state = state.copyWith();
    } catch (e, stackTrace) {
      Global.logger.e('🔊 [BDC-ASR] 刷新设置与重构语音识别失败: $e', error: e, stackTrace: stackTrace);
    }
  }

  /// 合并本轮 PTT 的 ASR 结果到累积文本。
  /// 两端原生识别器(Android sherpa-onnx / iOS SFSpeechRecognizer)发送的都是
  /// "累积全文"(从会话/段落开始到当前的完整文本),并非增量片段。
  /// - iOS:每次回调都是完整全文且识别中途会整体改写。但端点 reset 后新帧可能只有
  ///   尾部片段(如 "was chipped"),此时应保留更长的 prev 而非截断覆盖。
  /// - Android:按住期间以 _lastFinalAsrText(空)为基准同样退化为覆盖;
  ///   仅跨段(endpoint reset 后新段落)时才需要 stitchTexts 与旧段拼接。
  static String mergeAsrText(String prev, String next, {bool isEnglish = false}) {
    if (PlatformUtils.isIOS) {
      // 若 prev 更长且包含 next,说明 next 只是 prev 的末尾截断（端点 reset 导致），保留 prev
      if (prev.length > next.length && prev.contains(next)) return prev;
      return next;
    }
    return stitchTexts(prev, next, isEnglish: isEnglish);
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
        // 无重叠的阶段性结果用空格分隔,避免多个阶段识别文本黏连
        // (如误识别 "Good" 与后续 "the day before..." 直接拼成 "Goodthe day...")
        return "$p $n";
      }
    }
  }

  /// 当用户说出中文释义但本地未命中时，触发大模型裁判防抖调度（1500ms）
  void _scheduleWordAiRefereeCheck(List<String> inputs) {
    _wordAiRefereeDebounceTimer?.cancel();
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling || _isWordAiRefereeJudging) return;
    if (state.studyStep != StudyStep.en2Ch.json) return;

    final String asrText = inputs.isNotEmpty ? inputs.first : meaningController.text;
    final cleanInput = asrText.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').trim();
    if (cleanInput.length < 2) return; // 避免单字/助词杂音（如“啊/嗯”）浪费大模型Token

    // 过滤同词已判错的文本
    if (_failedWordAiEvaluationsForCurrentWord.contains(cleanInput)) return;

    // 单词请求频次上限
    if (_wordAiEvaluationCountForCurrentWord >= 5) return;

    _wordAiRefereeDebounceTimer = Timer(const Duration(milliseconds: 1500), () async {
      await _evaluateWordWithAiReferee(cleanInput, rawInput: asrText, candidates: inputs);
    });
  }

  /// 执行单词中文释义大模型智能裁决
  Future<void> _evaluateWordWithAiReferee(
    String cleanInput, {
    String? rawInput,
    List<String>? candidates,
    BuildContext? context,
  }) async {
    if (_isDisposed || _isWordAiRefereeJudging) return;
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;
    final word = state.word;
    final wordWrapper = state.wordWrapper;
    if (word == null || wordWrapper == null) return;

    final user = Global.getLoggedInUser();
    if (user == null) return;

    final checkWordId = word.id;
    _isWordAiRefereeJudging = true;
    _wordAiEvaluationCountForCurrentWord++;
    wordWrapper.isAiEvaluating = true;
    state = state.copyWith(isAiEvaluating: true);

    final targetWord = word.spell;
    final referenceMeanings = word.getMeaningStr();
    final userInput = rawInput ?? cleanInput;

    Global.logger.d('~~~~~[AI裁判-单词] 启动大模型裁判(第$_wordAiEvaluationCountForCurrentWord次): word="$targetWord", meanings="$referenceMeanings", input="$userInput"');

    try {
      final refereeResult = await AiRefereeUtil.judgeWordMeaning(
        targetWord: targetWord,
        referenceMeanings: referenceMeanings,
        userInput: userInput,
        candidates: candidates,
        userId: user.id,
      );

      if (_isDisposed || state.word?.id != checkWordId || state.hasFinishedAnswering || _isAnswerCorrectHandling) {
        Global.logger.d('~~~~~[AI裁判-单词] 单词已切换、已答对或已销毁，丢弃裁判结果');
        wordWrapper.isAiEvaluating = false;
        if (!_isDisposed && state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
        return;
      }

      final isCorrect = refereeResult.isCorrect;
      final explanation = refereeResult.explanation;
      Global.logger.d('~~~~~[AI裁判-单词] 裁判结果: isCorrect=$isCorrect, response=${refereeResult.rawResponse}');

      if (isCorrect) {
        wordWrapper.isAiEvaluating = false;
        final approvedText = refereeResult.intendedMeaning?.trim().isNotEmpty == true
            ? refereeResult.intendedMeaning!.trim()
            : (cleanInput.isNotEmpty ? cleanInput : userInput);
        wordWrapper.markAllMeaningsAsAiMatched(approvedAnswer: approvedText);

        state = state.copyWith(
          isAiEvaluating: false,
          canLeaveCurrWord: true,
          isScorePassed: true,
          wordWrapper: wordWrapper,
        );

        if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: true, explanation: '');
        }

        if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
          await StudyAudioSessionController.instance.syncHardwareIntent(
            isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
            isAnsweringActive: false,
            language: AsrLanguage.english,
            phrases: [],
            caller: this,
          );
        }
        final ratingResult = _calculateRating("AI裁判");
        _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
      } else {
        _failedWordAiEvaluationsForCurrentWord.add(cleanInput);
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
        if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: false, explanation: explanation);
          if (!_isDisposed) _handleTabChangeForAsr();
        }
      }
    } catch (e, st) {
      Global.logger.e("AI单词裁判判分出错", error: e, stackTrace: st);
      if (!_isDisposed) {
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
      }
      if (context != null && context.mounted) {
        ToastUtil.error("AI 裁判开小差了，请重试");
      }
    } finally {
      _isWordAiRefereeJudging = false;
      if (!_isDisposed && (state.hasFinishedAnswering || state.word?.id != checkWordId)) {
        wordWrapper.isAiEvaluating = false;
        if (state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
      }
    }
  }

  /// 当用户说英文停顿一小段时间后，触发单词中英（ch2En）大模型发音与同义词智能裁判
  void _scheduleCh2EnAiRefereeCheck(List<String> inputs) {
    _wordAiRefereeDebounceTimer?.cancel();
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;

    final word = state.word;
    final wordWrapper = state.wordWrapper;
    if (word == null || wordWrapper == null) return;

    final rawInput = inputs.isNotEmpty ? inputs.first : meaningController.text;
    final cleanInput = rawInput.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleanInput.length < 2) return;

    if (_failedWordAiEvaluationsForCurrentWord.contains(cleanInput)) return;
    if (_wordAiEvaluationCountForCurrentWord >= 5) return;

    _wordAiRefereeDebounceTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (_isDisposed) return;
      if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;
      if (_isWordAiRefereeJudging) return;
      if (state.word?.id != word.id) return;

      await _evaluateCh2EnWithAiReferee(
        cleanInput,
        rawInput: rawInput,
        candidates: inputs,
      );
    });
  }

  /// 执行单词中英（ch2En）大模型智能裁决
  Future<void> _evaluateCh2EnWithAiReferee(
    String cleanInput, {
    String? rawInput,
    List<String>? candidates,
    BuildContext? context,
  }) async {
    if (_isDisposed || _isWordAiRefereeJudging) return;
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;
    final word = state.word;
    final wordWrapper = state.wordWrapper;
    if (word == null || wordWrapper == null) return;

    final user = Global.getLoggedInUser();
    if (user == null) return;

    final checkWordId = word.id;
    _isWordAiRefereeJudging = true;
    _wordAiEvaluationCountForCurrentWord++;
    wordWrapper.isAiEvaluating = true;
    state = state.copyWith(isAiEvaluating: true);

    final targetWord = word.spell;
    final referenceMeanings = word.getMeaningStr();
    final userInput = rawInput ?? cleanInput;

    Global.logger.d('~~~~~[AI裁判-中英单词] 启动大模型裁判(第$_wordAiEvaluationCountForCurrentWord次): word="$targetWord", meanings="$referenceMeanings", input="$userInput"');

    try {
      final refereeResult = await AiRefereeUtil.judgeWordEnglish(
        targetWord: targetWord,
        referenceMeanings: referenceMeanings,
        userInput: userInput,
        candidates: candidates,
        userId: user.id,
      );

      if (_isDisposed || state.word?.id != checkWordId || state.hasFinishedAnswering || _isAnswerCorrectHandling) {
        Global.logger.d('~~~~~[AI裁判-中英单词] 单词已切换、已答对或已销毁，丢弃裁判结果');
        wordWrapper.isAiEvaluating = false;
        if (!_isDisposed && state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
        return;
      }

      final isCorrect = refereeResult.isCorrect;
      final isSynonym = refereeResult.isSynonym;
      final explanation = refereeResult.explanation;
      Global.logger.d('~~~~~[AI裁判-中英单词] 裁判结果: isCorrect=$isCorrect, isSynonym=$isSynonym, response=${refereeResult.rawResponse}');

      if (isCorrect) {
        wordWrapper.isAiEvaluating = false;
        meaningController.text = targetWord;

        state = state.copyWith(
          isAiEvaluating: false,
          canLeaveCurrWord: true,
          isScorePassed: true,
          wordWrapper: wordWrapper,
        );

        if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: true, explanation: '');
        }

        if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
          await StudyAudioSessionController.instance.syncHardwareIntent(
            isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
            isAnsweringActive: false,
            language: AsrLanguage.english,
            phrases: [],
            caller: this,
          );
        }
        final ratingResult = _calculateRating("AI裁判");
        _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
      } else {
        _failedWordAiEvaluationsForCurrentWord.add(cleanInput);
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
        if (isSynonym && explanation.isNotEmpty) {
          ToastUtil.info(explanation, autoCloseDuration: const Duration(seconds: 4));
        } else if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: false, explanation: explanation);
        }
        if (!_isDisposed) _handleTabChangeForAsr();
      }
    } catch (e, st) {
      Global.logger.e("AI中英单词裁判判分出错", error: e, stackTrace: st);
      if (!_isDisposed) {
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
      }
      if (context != null && context.mounted) {
        ToastUtil.error("AI 裁判开小差了，请重试");
      }
    } finally {
      _isWordAiRefereeJudging = false;
      if (!_isDisposed && (state.hasFinishedAnswering || state.word?.id != checkWordId)) {
        wordWrapper.isAiEvaluating = false;
        if (state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
      }
    }
  }

  /// 当用户停顿一小段时间后，触发例句大模型裁判对翻译进行智能容错判决
  void _scheduleSentenceAiRefereeCheck(List<String> inputs) {
    _sentenceAiRefereeDebounceTimer?.cancel();
    if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;

    final word = state.word;
    final wordWrapper = state.wordWrapper;
    if (word == null || wordWrapper == null) return;

    final sentence = (word.sentences != null && word.sentences!.isNotEmpty)
        ? word.sentences!.first
        : null;
    if (sentence == null) return;

    final rawInput = inputs.isNotEmpty ? inputs.first : sentenceAnswerController.text;
    final cleanInput = rawInput.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').trim();
    if (cleanInput.length < 2) return;

    if (_failedSentenceAiEvaluationsForCurrentWord.contains(cleanInput)) return;
    if (_sentenceAiEvaluationCountForCurrentWord >= 5) return;

    _sentenceAiRefereeDebounceTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (_isDisposed) return;
      if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;
      if (_isSentenceAiRefereeJudging) return;
      if (state.word?.id != word.id) return;

      await _evaluateSentenceWithAiReferee(
        cleanInput,
        rawInput: rawInput,
        candidates: inputs,
      );
    });
  }

  /// 执行例句翻译大模型智能裁决
  Future<void> _evaluateSentenceWithAiReferee(
    String cleanInput, {
    String? rawInput,
    List<String>? candidates,
    BuildContext? context,
  }) async {
    if (_isSentenceAiRefereeJudging) return;
    final word = state.word;
    final wordWrapper = state.wordWrapper;
    if (word == null || wordWrapper == null) return;

    final sentence = (word.sentences != null && word.sentences!.isNotEmpty)
        ? word.sentences!.first
        : null;
    if (sentence == null) return;

    final user = Global.getLoggedInUser();
    if (user == null) return;

    final checkWordId = word.id;
    _isSentenceAiRefereeJudging = true;
    _sentenceAiEvaluationCountForCurrentWord++;
    wordWrapper.isAiEvaluating = true;
    state = state.copyWith(isAiEvaluating: true);

    final isEn2Ch = state.studyStep == StudyStep.enSentence2Ch.json;
    final sourceText = isEn2Ch ? (sentence.english ?? "") : (sentence.chinese ?? "");
    final referenceText = isEn2Ch ? (sentence.chinese ?? "") : (sentence.english ?? "");
    final userInput = rawInput ?? cleanInput;

    Global.logger.d('~~~~~[AI裁判-例句] 启动大模型裁判(第$_sentenceAiEvaluationCountForCurrentWord次): source="$sourceText", ref="$referenceText", input="$userInput"');

    try {
      final refereeResult = await AiRefereeUtil.judgeSentenceTranslation(
        sourceSentence: sourceText,
        referenceTranslation: referenceText,
        userInput: userInput,
        exerciseType: state.studyStep,
        userId: user.id,
      );

      if (_isDisposed || state.word?.id != checkWordId || state.hasFinishedAnswering || _isAnswerCorrectHandling) {
        Global.logger.d('~~~~~[AI裁判-例句] 单词已切换、已答对或已销毁，丢弃裁判结果');
        wordWrapper.isAiEvaluating = false;
        if (!_isDisposed && state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
        return;
      }

      final isCorrect = refereeResult.isCorrect;
      final explanation = refereeResult.explanation;
      Global.logger.d('~~~~~[AI裁判-例句] 裁判结果: isCorrect=$isCorrect, response=${refereeResult.rawResponse}');

      if (isCorrect) {
        wordWrapper.isAiEvaluating = false;
        wordWrapper.sentenceTranslatedPassed = true;
        wordWrapper.isAiEvaluatedPassed = true;

        state = state.copyWith(
          isAiEvaluating: false,
          canLeaveCurrWord: true,
          isScorePassed: true,
          wordWrapper: wordWrapper,
        );

        if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: true, explanation: '');
        }

        if (StudyAudioSessionController.instance.activeMode == AudioMode.record) {
          await StudyAudioSessionController.instance.syncHardwareIntent(
            isInSpeakTab: _shouldShowSpeakTab && state.tabIndex == 0,
            isAnsweringActive: false,
            language: AsrLanguage.english,
            phrases: [],
            caller: this,
          );
        }
        final ratingResult = _calculateRating("AI裁判");
        _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
      } else {
        _failedSentenceAiEvaluationsForCurrentWord.add(cleanInput);
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
        if (context != null && context.mounted) {
          await showAiRefereeDialog(context, isCorrect: false, explanation: explanation);
          if (!_isDisposed) _handleTabChangeForAsr();
        }
      }
    } catch (e, st) {
      Global.logger.e("AI例句裁判判分出错", error: e, stackTrace: st);
      if (!_isDisposed) {
        wordWrapper.isAiEvaluating = false;
        state = state.copyWith(isAiEvaluating: false);
      }
      if (context != null && context.mounted) {
        ToastUtil.error("AI 裁判开小差了，请重试");
      }
    } finally {
      _isSentenceAiRefereeJudging = false;
      if (!_isDisposed && (state.hasFinishedAnswering || state.word?.id != checkWordId)) {
        wordWrapper.isAiEvaluating = false;
        if (state.isAiEvaluating) {
          state = state.copyWith(isAiEvaluating: false);
        }
      }
    }
  }

  Future<void> evaluateWithAiReferee(BuildContext context) async {
    final word = state.word;
    if (word == null) return;

    // 单词英中模式：调用单词 AI 裁判
    if (state.studyStep == StudyStep.en2Ch.json) {
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

      try {
        await asr.stopAsr();
      } catch (_) {}

      await Api.loadingService.show(status: 'AI裁判裁决中...');
      try {
        if (!context.mounted) return;
        final cleanInput = userInput.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').trim();
        await _evaluateWordWithAiReferee(
          cleanInput,
          rawInput: userInput,
          candidates: state.currentAsrCandidates,
          context: context,
        );
      } finally {
        await Api.loadingService.dismiss();
      }
      return;
    }

    // 例句模式：调用例句 AI 裁判
    final recognizedText = state.currentAsrCandidates.isNotEmpty
        ? state.currentAsrCandidates.first
        : '';
    final userInput = recognizedText.isNotEmpty
        ? recognizedText
        : sentenceAnswerController.text;

    if (userInput.trim().isEmpty) {
      ToastUtil.error("请先回答问题");
      return;
    }

    try {
      await asr.stopAsr();
    } catch (_) {}

    await Api.loadingService.show(status: 'AI裁判裁决中...');
    try {
      if (!context.mounted) return;
      final cleanInput = userInput.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').trim();
      await _evaluateSentenceWithAiReferee(
        cleanInput,
        rawInput: userInput,
        candidates: state.currentAsrCandidates,
        context: context,
      );
    } finally {
      await Api.loadingService.dismiss();
    }
  }

  /// 以对话框形式展示 AI 裁判结果(通过/失败),避免反馈气泡被滚动区顶出可视范围。
  Future<void> showAiRefereeDialog(
    BuildContext context, {
    required bool isCorrect,
    required String explanation,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.gavel_rounded,
              color: isCorrect ? Colors.green : Colors.orange,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('AI 裁判'),
          ],
        ),
        content: Text(
          isCorrect ? '判定通过！回答正确。' : explanation,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

}




