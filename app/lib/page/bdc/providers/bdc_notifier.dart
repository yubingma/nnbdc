import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;
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
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
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
ja.AudioPlayer bdcAudioPlayer(BdcAudioPlayerRef ref) {
  final player = SoundUtil.createAudioPlayer();
  ref.onDispose(() {
    SoundUtil.unwatchPlayer(player);
    player.dispose();
  });
  return player;
}

@riverpod
class BdcNotifier extends _$BdcNotifier {
  int _stateChangeCount = 0;
  bool _isDisposed = false;

  void _updateState(BdcState newState, {String tag = ''}) {
    _stateChangeCount++;
    state = newState;
    if (tag.isNotEmpty) {
      debugPrint('⚡ [PERF] BdcNotifier.state #$_stateChangeCount tag=$tag');
    }
  }

  late Asr asr;
  late BdcPageArgs _args;
  late final ja.AudioPlayer _audioPlayer;
  late final StudyAudioSessionController _sessionController;
  Timer? _learningTimer;
  Timer? _persistTimer;
  /// 播放取消令牌：每次换词或用户手动操作时递增，使旧延迟 callback 失效。
  int _playToken = 0;
  
  late final SpellingTextEditingController meaningController = SpellingTextEditingController(
    getTargetSpell: () => state.word?.spell,
    baseColor: AppTheme.primaryColor,
  );
  
  String _handlingChinese = "";

  @override
  BdcState build() {
    asr = ref.watch(asrProvider);
    _audioPlayer = ref.watch(bdcAudioPlayerProvider);
    _sessionController = StudyAudioSessionController(_audioPlayer);
    
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
      checkAsrResult();
    });

    ref.onDispose(() {
      _isDisposed = true;
      _learningTimer?.cancel();
      _persistTimer?.cancel();
      progressBarTapTimer?.cancel();
      _syncLearningTimeToDb();
      asr.removeStateListener(_onAsrStateChanged);
      _sessionController.dispose();
      // 仅停止 ASR 识别任务，不销毁原生音频引擎。
      // 引擎保持存活可在后续 BDC 页面访问时消除 2.3s 的冷启动延迟。
      asr.stopAsr();
      // 物理释放麦克风，平滑物理淡出所有活跃音频流并物理释放硬件资源，防止退出页面后麦克风占用指示灯持续亮起
      unawaited(SoundUtil.transitTo(AudioMode.idle, asrInstance: asr));
      meaningController.dispose();
      Prefs.remove("BdcPageArgs");
    });

    _startLearningTimer();

    return const BdcState();
  }

  DateTime? _lastSyncTime;

  void _onAsrStateChanged(AsrState asrState) {
    Future.microtask(() {
      if (_isDisposed) return;
      _updateState(state.copyWith(asrState: asrState), tag: 'asr-state');
    });
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
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isDisposed) {
        unawaited(SoundUtil.prewarmCoreSounds());
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
      unawaited(SoundUtil.configureAudioSession());
      
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
      await asr.stopMicrophone();
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
    int newTabIndex = 0;
    if (state.isSelectModePreferred) {
      newTabIndex = speakTabAvailable ? 1 : 0;
    }

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
      wordStartTime: AppClock.now(),
      fsrsItem: null,
      lastFsrsRating: null,
      currentAsrCandidates: [],
      loadError: null, // Successfully loaded a word, clear error
      tabIndex: newTabIndex,
      showHandwritingBoard: false,
      isKeyboardVisible: false,
      hintTapCount: 0,
    );

    final wordId = word.id;
    if (state.wordUIStates.containsKey(wordId)) {
      _restoreWordState(getWordResult);
    } else {
      meaningController.text = "";
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

    // iOS 说模式引擎预热：在 dataLoaded 之后、200ms delay 之前启动。
    // 此时 ASR 状态已稳定（initialized），不会被 loadData 中的 stopAsr 干扰。
    // 预热与音频预加载、200ms 延迟并行运行。
    final bool shouldSpeak = _shouldShowSpeakTab && state.tabIndex == 0;
    if (PlatformUtils.isIOS && shouldSpeak) {
      unawaited(asr.warmupMicrophone());
    }

    // 将发音播放和 ASR 启动延迟 200ms 执行，在卡片过渡动画结束前不抢占渲染资源。
    // 延迟结束后等待引擎预热完成（若正在进行），确保 startAsr 能瞬间复用已初始化的引擎。
    // 使用 _playToken 防止快速切词时旧 callback 使用过期 state。
    final token = ++_playToken;
    Future.delayed(const Duration(milliseconds: 200), () async {
      if (_playToken != token || _isDisposed) return;
      final playStopwatch = Stopwatch()..start();
      try {
        debugPrint('⏱️ [Latency-BDC] handleWord -> playWordAndFirstSentence 触发 (background)...');
        if (PlatformUtils.isIOS && shouldSpeak) {
          final warmupWaitSw = Stopwatch()..start();
          await asr.awaitMicWarmup();
          debugPrint('⚡ [PERF] Engine warmup done before playWordAndFirstSentence: ${warmupWaitSw.elapsedMilliseconds}ms');
        }
        // 关键重构：仅在说模式（shouldSpeak为true）时才在播放后衔接启动 ASR，非说模式（如英中模式）下彻底解耦 ASR 释放重启开销，确保发音播放链路纯净、无任何麦克风占用和爆音
        //
        // 统一停用共享播放器：fastPath（详情页下一词）跳过了 getNextWord 中的
        // _safeStopAudioPlayer，导致播放器处于 completed 而非 idle 状态。
        // 在此处提前停用，使播放器状态与正常 BDC 切词一致，消除 iOS AVPlayer
        // 在 completed 态直接加载新音源时可能产生的瞬态爆音。同时 ~200ms 的
        // 空闲时间给原生音频管线更充分的稳定窗口。
        try { await _safeStopAudioPlayer(); } catch (_) {}
        await playWordAndFirstSentence(false, shouldSpeak);
      } catch (e, st) {
        Global.logger.e('后台播放单词发音及开启 ASR 失败', error: e, stackTrace: st);
      } finally {
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

  void updateTabIndex(int index) {
    // Determine if the user is choosing the "Select" tab (always the last tab)
    final isSelectTab = index == (_shouldShowSpeakTab ? 1 : 0);
    state = state.copyWith(tabIndex: index, isSelectModePreferred: isSelectTab);
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
      SoundUtil.playAssetSoundConcurrent('failed.mp3', 1.5, 1.0);
      showWordDetail(state.word!, true, context, fsrsRating: FsrsRating.again, reason: "选错了答案");
    }
  }

  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, BuildContext context, {FsrsRating? fsrsRating, String? reason}) async {
    // 强制并平滑地关闭正在播放的主发音/例句音频，彻底根除打开详情页瞬间因两路音频流冲突产生的爆音
    try {
      await _safeStopAudioPlayer();
    } catch (_) {}

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
    
    final result = await goRouter.push<bool>('/word_detail', extra: WordDetailPageArgs(word, false, null, isAnswerWrong,
        showNextWordButton: true,
        sessionController: _sessionController,
        onNextWord: () => getNextWord(true, fsrsRating: state.lastFsrsRating, fastPath: false)));
    
    if (_isDisposed) return;

    if (result == true) {
      // onNextWord 回调已在详情页 Pop 前静默执行了 getNextWord，
      // 主页切词已完成，无需在此重复执行，消除双重过渡延迟。
    } else {
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
      state = state.copyWith(
        wordWrapper: wrapper,
        isUpdatingByHint: !state.isUpdatingByHint,
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
    if (visible) {
      unawaited(_sessionController.stopSession(forceStopMicrophone: true));
    } else {
      _handleTabChangeForAsr();
    }
  }

  void goToPreviousWord() async {
    if (state.history.isEmpty) return;

    _saveCurrentWordState();
    await _sessionController.stopSession(forceStopMicrophone: true);
    await _safeStopAudioPlayer();

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
    await _sessionController.stopSession(forceStopMicrophone: true);
    await _safeStopAudioPlayer();
    
    state = state.copyWith(historyIndex: -1);
    await handleWord(target, isFromBatchWordList: true);
  }
  Future<void> reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }

  /// Safely stop the BDC audio player with a Soft-Mute to prevent popping.
  /// Uses pause+seek(0) instead of stop() to avoid tearing down the native
  /// AVQueuePlayer (just_audio's stop() calls _setPlatformActive(false) which
  /// disposes the native player on iOS, causing an audible pop when it's
  /// recreated on the next play).
  Future<void> _safeStopAudioPlayer() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.setVolume(0.0);
    }
    await _audioPlayer.pause();
    await _audioPlayer.seek(Duration.zero);
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
        );
        meaningController.text = "";
      }
      debugPrint('⚡ [PERF] _restoreWordState cost: ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<bool> getNextWord(bool gotoNext, {FsrsRating? fsrsRating, bool fastPath = false}) async {
    if (state.isGettingNextWord) return false;
    final totalStopwatch = Stopwatch()..start();

    _saveCurrentWordState();
    _playToken++; // 取消任何待执行的自动播放延迟 callback

    // 快速通道（详情页预拉取）：跳过音频/ASR 清理和视觉驻留，仅做数据加载。
    if (!fastPath) {
      // 切换单词的一瞬间，强行、立即关停上一个单词的音频播放，
      // 使得 SoundUtil.waitForAllPlayers 判定无活跃播放器，从而闪电完成 AudioSession 切换！
      try {
        await _safeStopAudioPlayer();
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
        await asr.stopAsr();
        await asr.reset();
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
    String processedResult = "";
    List<String> candidates = [];
    
    try {
      Map<String, dynamic>? resultData;
      try {
        resultData = jsonDecode(event.toString());
      } catch (_) {
        resultData = null;
      }

      if (resultData != null && resultData.containsKey('candidates')) {
        candidates = List<String>.from(resultData['candidates']);
        String best = resultData['best'] ?? candidates.first;
        
        if (state.studyStep == StudyStep.ch2En.json) {
          final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(candidates, state.word!.spell);
          processedResult = AsrUtil.preprocessEnglish(result.text, state.word!.spell);
          _updateState(state.copyWith(currentScore: result.score, currentAsrCandidates: candidates), tag: 'asr-result');
        } else {
          processedResult = AsrUtil.preprocess(best);
          _updateState(state.copyWith(currentAsrCandidates: candidates), tag: 'asr-candidate');
        }
      } else {
        candidates = [event.toString()];
        processedResult = AsrUtil.preprocess(event.toString());
      }
    } catch (e) {
      processedResult = AsrUtil.preprocess(event.toString());
      candidates = [event.toString()];
    }

    checkAsrResult(asrInput: processedResult, isVoice: true);
  }

  Future<void> checkAsrResult({String? asrInput, bool isVoice = false}) async {
    if (_isDisposed) return;
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
        await _sessionController.stopSession(forceStopMicrophone: true);
        
        if (state.hasFinishedAnswering) {
          // 已经答对了（处于查看详情时的额外练习），直接关闭
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
          SoundUtil.playPronounceSound2(state.word!, _audioPlayer);
        } else {
          // 还没答对（英中模式下的拼写练习），仅关闭界面，不视为答对题目
          state = state.copyWith(showHandwritingBoard: false);
          SoundUtil.playPronounceSound2(state.word!, _audioPlayer);
          _handleTabChangeForAsr();
        }
        Global.logger.d('[PERF] checkAsrResult spelling match cost: ${stopwatch.elapsedMilliseconds}ms');
        return;
      }

      final isFromAsr = asrInput != null || meaningController.text == _handlingChinese;
      final inputs = isFromAsr ? state.currentAsrCandidates : [_handlingChinese];
      
      final matchStopwatch = Stopwatch()..start();
      final result = matchInputChineseWithMeaningItems(state.wordWrapper!, inputs);
      bool isMatch = _isAsrPassSync(result.totalCount, result.matchedCount);
      Global.logger.d('[PERF] checkAsrResult -> matchInputChineseWithMeaningItems cost: ${matchStopwatch.elapsedMilliseconds}ms');
      
      if (result.newMatchCount > 0) {
        state = state.copyWith(canLeaveCurrWord: true);
        if (isMatch) {
          // 先等待麦克风完全关停（含原生侧 AVAudioSession 切换至 playback），
          // 再播放提示音，避免音频会话切换导致 just_audio AVPlayer 中断并重放缓冲区尾部，产生回声。
          await _sessionController.stopSession(forceStopMicrophone: true);
          final ratingResult = _calculateRating(method);
          _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
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

        // 先等待麦克风完全关停（含原生侧 AVAudioSession 切换至 playback），
        // 再播放发音，避免音频会话切换导致 AVPlayer 中断并产生回声。
        await _sessionController.stopSession(forceStopMicrophone: true);

        // 如果已经答过题（hasFinishedAnswering=true），_onAnswerCorrect 会直接返回，
        // 不会播放发音。因此在这里手动播放单词正确发音作为反馈。
        // 使用 _audioPlayer 而非 _pronouncePlayer，确保与 playWordAndFirstSentence
        // 共享同一播放器，避免两个播放器同时播放导致回声。
        if (state.hasFinishedAnswering) {
          SoundUtil.playPronounceSound2(state.word!, _audioPlayer);
        }
        final ratingResult = _calculateRating(method);
        _onAnswerCorrect(ratingResult.rating, reason: ratingResult.reason);
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

  ({FsrsRating rating, String reason}) _calculateRating(String method) {
    if (state.wordStartTime == null) return (rating: FsrsRating.good, reason: "$method，初始评分: ${FsrsRating.good.label}");
    final responseTime = AppClock.now().difference(state.wordStartTime!).inSeconds;
    
    FsrsRating rating;
    if (responseTime < 8) {
      rating = FsrsRating.easy;
    } else if (responseTime >= 18) {
      rating = FsrsRating.hard;
    } else {
      rating = FsrsRating.good;
    }
    String reason = "$method，响应时间: ${responseTime}s，判定为${rating.label}";
    
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
    state = state.copyWith(
      hasFinishedAnswering: true,
      canLeaveCurrWord: true,
      lastFsrsRating: rating,
      lastFsrsRatingReason: reason,
      showHandwritingBoard: false,
    );
    _handleTabChangeForAsr();
    
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
      if (PlatformUtils.isIOS) {
        SoundUtil.playAssetSoundConcurrent('correct_ios.wav', 1.0, 0.3);
      } else {
        SoundUtil.playAssetSoundConcurrent('correct.wav', 1.0, 1.0);
      }
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

  Future<void> playWordAndFirstSentence(bool forcePlayWord, bool startAsrWhenFinish, {bool forcePlaySentence = false}) async {
    if (_isDisposed) return;
    final stopwatch = Stopwatch()..start();
    final studyConfig = StudyConfig.fromCurrentUser();
    
    debugPrint('⏱️ [Latency-BDC] playWordAndFirstSentence() 启动');

    // 强制播放标志优先级最高，不受模式限制。自动播放则依然仅限英中模式。
    bool willPlayWord = forcePlayWord || (state.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlayWord);
    bool willPlaySentence = forcePlaySentence || (state.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlaySentence);

    debugPrint('🔊 [BDC-Sound] 播放决策结果: willPlayWord=$willPlayWord, willPlaySentence=$willPlaySentence');

    if (willPlayWord || willPlaySentence) {
      if (state.word != null) {
        await _sessionController.playWordAndSentence(
          state.word!,
          sentenceDigest: state.englishDigestOfFirstSentence,
          playWord: willPlayWord,
          playSentence: willPlaySentence,
          isSpeakMode: startAsrWhenFinish,
        );
      }
    }

    if (startAsrWhenFinish && !_isDisposed) {
      debugPrint('⏱️ [Latency-BDC] 播放完自动衔接 ASR...');
      _handleTabChangeForAsr();
    }
    
    Global.logger.d('[PERF] playWordAndFirstSentence total cost: ${stopwatch.elapsedMilliseconds}ms');
  }

  void _handleTabChangeForAsr() {
    // 只有在显示了“说”Tab（即 _shouldShowSpeakTab 为 true）且当前索引为 0 时，才认为是“说”模式
    bool isInSpeakTab = _shouldShowSpeakTab && state.tabIndex == 0; 
    
    debugPrint('💡 [BDC-ASR] _handleTabChangeForAsr() 触发。isInSpeakTab: $isInSpeakTab (shouldShowSpeakTab: $_shouldShowSpeakTab, tabIndex: ${state.tabIndex})');

    if (isInSpeakTab) {
      if (state.word == null || state.loadError != null || state.hasFinishedAnswering || state.showHandwritingBoard || state.isGettingNextWord || state.isKeyboardVisible) {
        debugPrint('💡 [BDC-ASR] 当前虽然在 SpeakTab，但由于条件不满足决定停止 ASR：word=${state.word?.spell}, loadError=${state.loadError}, hasFinishedAnswering=${state.hasFinishedAnswering}, showHandwritingBoard=${state.showHandwritingBoard}, isGettingNextWord=${state.isGettingNextWord}, isKeyboardVisible=${state.isKeyboardVisible}');
        
        // 如果处于 SpeakTab，但只是因为换词中、已答对、手写板展开等暂时的非答题状态，只执行热停止 (stopAsr) 以暂停识别，保持麦克风与 playAndRecord 会话 Category 稳定，避免高频冷切换
        final shouldOnlyStopAsr = state.isGettingNextWord || state.hasFinishedAnswering || state.showHandwritingBoard;
        unawaited(_sessionController.stopSession(forceStopMicrophone: !shouldOnlyStopAsr));
        return;
      }

      final language = state.studyStep == StudyStep.ch2En.json ? AsrLanguage.english : AsrLanguage.chinese;
      debugPrint('💡 [BDC-ASR] 条件满足，准备调用 _startAsrWithHint，语言: ${language.locale}');
      unawaited(_startAsrWithHint(language));
    } else {
      debugPrint('💡 [BDC-ASR] 不在 SpeakTab，当前 asr 状态: ${asr.state}');
      // 如果不在说模式下，且当前 ASR 仍在运行或音频 Category 依然是录放通道，强制触发 cold 关停以释放麦克风和硬件资源
      if (asr.state != AsrState.stopped || SoundUtil.activeSessionCategory == 'playAndRecord') {
        debugPrint('💡 [BDC-ASR] 不在 SpeakTab 且 ASR 运行或麦克风未释放，触发状态机物理释放麦克风');
        unawaited(_sessionController.stopSession(forceStopMicrophone: true));
      }
    }
  }

  Future<void> _startAsrWithHint(AsrLanguage language) async {
    final sw = Stopwatch()..start();
    if (state.word == null || state.loadError != null || state.showHandwritingBoard || state.isGettingNextWord) {
      debugPrint('⚡ [PERF] _startAsrWithHint SKIPPED: word=${state.word != null} loadErr=${state.loadError != null} hw=${state.showHandwritingBoard} getting=${state.isGettingNextWord}');
      return;
    }

    debugPrint('⚡ [PERF] _startAsrWithHint START lang=${language.locale}');

    // 添加调试日志，方便查看正确答案
    final correctAnswer = state.studyStep == StudyStep.ch2En.json ? state.word?.spell : state.word?.getMeaningStr();
    Global.logger.d('~~~~~ 当前说模式正确答案: ${correctAnswer?.replaceAll('\n', '; ')}');

    // 2. 提取热词（Phrases）并启动 ASR，等就绪
    List<String> phrases = [];
    if (language == AsrLanguage.english) {
      phrases.add(state.word!.spell);
    } else {
      phrases.addAll(AsrUtil.extractContextualPhrases(state.word!.meaningItems ?? []));
    }

    try {
      await _sessionController.startSession(
        language: language,
        phrases: phrases,
        isSpeakMode: true,
      );
      
      state = state.copyWith(wordStartTime: AppClock.now());
      debugPrint('⚡ [PERF] _startAsrWithHint DONE total: ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      Global.logger.e('ASR启动指令下发失败: $e');
      debugPrint('⚡ [PERF] _startAsrWithHint FAILED: $e');
    }
  }

  void handleTabChangeForAsr() {
    _handleTabChangeForAsr();
  }

  void updateKeyboardVisibility(bool visible) {
    state = state.copyWith(isKeyboardVisible: visible);
    if (visible) {
      unawaited(_sessionController.stopSession(forceStopMicrophone: true));
    } else {
      handleTabChangeForAsr();
    }
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
    if (studyStep == StudyStep.ch2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    if (studyStep == StudyStep.en2Ch.json) {
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
      await SoundUtil.transitTo(AudioMode.idle, asrInstance: asr);
      
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
}

