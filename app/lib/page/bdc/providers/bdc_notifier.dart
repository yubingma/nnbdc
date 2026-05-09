import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/constants.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:drift/drift.dart' as drift;
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/db/user_extensions.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'bdc_state.dart';
import '../models/bdc_page_args.dart';
import '../models/word_ui_state.dart';

part 'bdc_notifier.g.dart';

@riverpod
class BdcNotifier extends _$BdcNotifier {
  late Asr asr;
  late BdcPageArgs _args;
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  Timer? _learningTimer;
  
  late final SpellingTextEditingController meaningController = SpellingTextEditingController(
    getTargetSpell: () => state.word?.spell,
    baseColor: AppTheme.primaryColor,
  );
  
  String _handlingChinese = "";

  @override
  BdcState build() {
    asr = Asr();
    
    // Initialize args
    final argsJson = GetStorage().read<String>("BdcPageArgs");
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
      _learningTimer?.cancel();
      _syncLearningTimeToDb();
      asr.removeStateListener(_onAsrStateChanged);
      asr.stopMicrophone();
      meaningController.dispose();
      GetStorage().remove("BdcPageArgs");
      
      _audioPlayer.dispose();
    });

    _startLearningTimer();

    return const BdcState();
  }

  void _onAsrStateChanged(AsrState asrState) {
    state = state.copyWith(asrState: asrState);
  }

  void _startLearningTimer() {
    _learningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = state.copyWith(accumulatedSeconds: state.accumulatedSeconds + 1);
      if (state.accumulatedSeconds % 10 == 0) {
        _syncLearningTimeToDb();
      }
    });
  }

  Future<void> _syncLearningTimeToDb() async {
    if (state.accumulatedSeconds <= 0) return;
    int secsToSync = state.accumulatedSeconds;
    state = state.copyWith(accumulatedSeconds: 0);

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
      state = state.copyWith(accumulatedSeconds: state.accumulatedSeconds + secsToSync);
    }
  }

  Future<void> loadData(BuildContext context) async {
    Api.setLoadingDisabled(true);
    try {
      state = state.copyWith(dataLoaded: false);
      
      // Get display words for loading dialog
      List<String> displayWords = await _getDisplayWords();

      // Show loading dialog
      if (context.mounted) {
        _showLoadingDialog(context, displayWords);
      }
      
      await asr.preloadModels();
      await Future.delayed(const Duration(milliseconds: 50));
      
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      await SoundUtil.configureAudioSession();
      
      final studyConfig = StudyConfig.fromCurrentUser();
      
      state = state.copyWith(
        asrPassRuleCache: studyConfig.asrPassRule,
        autoJumpAfterCorrectCh2En: studyConfig.autoJumpAfterCorrectCh2En,
        autoJumpAfterCorrectEn2Ch: studyConfig.autoJumpAfterCorrectEn2Ch,
      );

      var stepsResult = await StudyBo().getActiveUserStudySteps();
      if (!stepsResult.success || stepsResult.data == null) {
        ToastUtil.error(stepsResult.msg ?? '获取学习步骤失败');
        return;
      }
      state = state.copyWith(activeUserStudySteps: stepsResult.data!);

      await getNextWord(false);
      
      _restoreLastWordHistory();
      
      state = state.copyWith(dataLoaded: true);
    } catch (e, st) {
      ErrorHandler.handleError(e, st, logPrefix: 'loadData');
    } finally {
      Api.setLoadingDisabled(false);
    }
  }

  Future<List<String>> _getDisplayWords() async {
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

  void _restoreLastWordHistory() {
    try {
      final lastWordDataStr = GetStorage().read<String>('last_word_history_item');
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
        );
        
        final wordId = wordResult.learningWord?.word.id;
        if (wordId != null) {
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

  Future<void> handleWord(GetWordResult? getWordResult, {bool isFromBatchWordList = false}) async {
    if (getWordResult == null) return;
    
    if (getWordResult.finished) {
      Get.offNamed("/finish");
      return;
    } else if (getWordResult.noWord) {
      Get.toNamed("/select_book");
      return;
    }

    state = state.copyWith(buttonsEnabled: false);
    Future.delayed(const Duration(milliseconds: 500), () {
      state = state.copyWith(buttonsEnabled: true);
    });

    final currentStep = state.activeUserStudySteps[getWordResult.stepIndex].studyStep;
    if (currentStep == 'List') return;

    String? oldStudyStep = state.studyStep;
    String newStudyStep = state.activeUserStudySteps[getWordResult.stepIndex].studyStep;
    
    if (asr.state == AsrState.started) {
      await asr.stopAsr();
    }

    if (oldStudyStep != newStudyStep || isFromBatchWordList) {
      await asr.initAsr(onAsrResult);
    }

    WordVo word = getWordResult.learningWord!.word;
    
    if (word.spell.isEmpty) {
      final local = await MyDatabase.instance.wordsDao.getWordById(word.id!);
      if (local != null) {
        word.spell = local.spell;
        word.shortDesc = local.shortDesc;
      }
      final user = Global.getLoggedInUser();
      if (user != null) {
        word.meaningItems = await WordBo().getMeaningItemsForWord(word.id!, user.id);
      }
    }

    WordWrapper wordWrapper = WordWrapper(word, null);
    
    state = state.copyWith(
      currentGetWordResult: getWordResult,
      word: word,
      wordWrapper: wordWrapper,
      studyStep: newStudyStep,
      canLeaveCurrWord: false,
      hasFinishedAnswering: false,
      selectedAnswerIndex: null,
      flippedAnswerIndices: {},
      showSentenceTranslation: false,
      currentScore: null,
      englishDigestOfFirstSentence: null,
      wordStartTime: (newStudyStep != StudyStep.en2Ch.json) ? AppClock.now() : null,
      fsrsItem: null,
      lastFsrsRating: null,
      currentAsrCandidates: [],
    );

    if (state.historyIndex != -1) {
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
    final sentences = await word.getSentences();
    if (sentences.isNotEmpty) englishDigest = sentences[0].englishDigest;
    state = state.copyWith(englishDigestOfFirstSentence: englishDigest);

    _initChoiceData(getWordResult);

    final user = Global.getLoggedInUserNotNull();
    if (state.studyStep == StudyStep.en2Ch.json) {
      await playWordAndFirstSentence(await user.toUserVo(), false, false);
    } else {
      await playWordAndFirstSentence(await user.toUserVo(), true, false);
    }
    
    state = state.copyWith(dataLoaded: true);
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
    state = state.copyWith(tabIndex: index);
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
      _onAnswerCorrect(_calculateRating());
    } else {
      SoundUtil.playAssetSoundConcurrent('failed.mp3', 1.5, 1.0);
      showWordDetail(state.word!, true, context, fsrsRating: FsrsRating.again, reason: "选错了答案");
    }
  }

  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, BuildContext context, {FsrsRating? fsrsRating, String? reason}) async {
    if (fsrsRating != null) {
      state = state.copyWith(
        lastFsrsRating: fsrsRating,
        lastFsrsRatingReason: reason,
        hasFinishedAnswering: true,
        canLeaveCurrWord: true,
      );
      _updateFsrsPreview(fsrsRating);
    }
    
    await Get.toNamed('/word_detail', arguments: WordDetailPageArgs(word, false, null, isAnswerWrong));
    _handleTabChangeForAsr();
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
      state = state.copyWith(wordWrapper: wrapper);
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
      asr.stopMicrophone();
    } else {
      _handleTabChangeForAsr();
    }
  }

  void goToPreviousWord() async {
    if (state.history.isEmpty) return;

    _saveCurrentWordState();
    await asr.stopAsr();
    await _audioPlayer.stop();

    int nextIndex;
    if (state.historyIndex == -1) {
      nextIndex = state.history.length - 1;
    } else if (state.historyIndex > 0) {
      nextIndex = state.historyIndex - 1;
    } else {
      return;
    }

    state = state.copyWith(historyIndex: nextIndex);
    handleWord(state.history[nextIndex]);
  }

  Future<void> reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }

  void _persistLastWordHistoryItem() {
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
            'wordsIndices': uiState.words?.map((w) {
              if (w.spell == "[ 都不对 ]") return 3;
              if (targetWord != null && w.id == targetWord.id) return 0;
              if (others != null && others.isNotEmpty && w.id == others[0].id) return 1;
              if (others != null && others.length > 1 && w.id == others[1].id) return 2;
              return -1;
            }).toList(),
          }
        };
        GetStorage().write('last_word_history_item', json.encode(lastWordData));
      }
    } catch (e) {
      Global.logger.e('持久化上一个单词失败: $e');
    }
  }

  void _restoreWordState(GetWordResult result) {
    final wordId = result.learningWord?.word.id;
    final uiState = wordId != null ? state.wordUIStates[wordId] : null;
    if (uiState != null) {
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
      );
      meaningController.text = uiState.meaningText;
    }
  }

  Future<void> getNextWord(bool gotoNext, {FsrsRating? fsrsRating}) async {
    if (state.isGettingNextWord) return;

    _saveCurrentWordState();

    if (state.historyIndex != -1) {
      if (gotoNext) {
        final lw = state.currentGetWordResult?.learningWord;
        if (lw != null && state.fsrsItem != null && state.lastFsrsRating != null) {
          StudyBo().saveHistoryFSRSUpdate(
            currWord: lw,
            nextFsrs: state.fsrsItem!,
            newRating: state.lastFsrsRating!,
          );
        }

        int nextIndex = state.historyIndex + 1;
        if (nextIndex >= state.history.length) {
          state = state.copyWith(historyIndex: -1);
          await handleWord(state.currentGetWordResult);
          return;
        } else {
          state = state.copyWith(historyIndex: nextIndex);
          await handleWord(state.history[nextIndex]);
          return;
        }
      }
    }

    state = state.copyWith(isGettingNextWord: true);
    try {
      await asr.stopAsr();
      await asr.reset();

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
        await GetStorage().write("BdcPageArgs", _args.toJson());
      }

      final result = await StudyBo().getWord(state.isWordMastered, gotoNext, fsrsRating: fsrsRating);
      if (result.success && result.data != null) {
        await handleWord(result.data, isFromBatchWordList: isFromBatchWordList);
      } else {
        Global.logger.w('getNextWord: 获取单词失败: code=${result.code}, msg=${result.msg}');
        if (result.code == "NEW_DAY") {
          ToastUtil.info('已进入新的一天，请重新开始学习');
          Get.offAllNamed('/today_plan'); // Redirect back to plan page
        } else {
          ToastUtil.error(result.msg ?? '获取单词失败');
        }
      }
    } catch (e, st) {
      ErrorHandler.handleError(e, st, logPrefix: 'getNextWord');
    } finally {
      state = state.copyWith(isGettingNextWord: false);
    }
  }

  void _saveCurrentWordState() {
    if (state.word?.id != null) {
      final uiState = WordUIState(
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
      );
      state = state.copyWith(wordUIStates: {...state.wordUIStates, state.word!.id!: uiState});
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
          state = state.copyWith(currentScore: result.score);
          processedResult = AsrUtil.preprocessEnglish(result.text, state.word!.spell);
        } else {
          processedResult = AsrUtil.preprocess(best);
        }
      } else {
        candidates = [event.toString()];
        processedResult = AsrUtil.preprocess(event.toString());
      }
    } catch (e) {
      processedResult = AsrUtil.preprocess(event.toString());
      candidates = [event.toString()];
    }

    state = state.copyWith(currentAsrCandidates: candidates);
    checkAsrResult(asrInput: processedResult, isVoice: true);
  }

  Future<void> checkAsrResult({String? asrInput, bool isVoice = false}) async {
    String inputText = asrInput ?? meaningController.text;
    if (inputText == _handlingChinese && asrInput == null) return;
    _handlingChinese = inputText;

    if (state.hasFinishedAnswering && !state.showHandwritingBoard) return;

    if (state.studyStep == StudyStep.en2Ch.json) {
      final isFromAsr = asrInput != null || meaningController.text == _handlingChinese;
      final inputs = isFromAsr ? state.currentAsrCandidates : [_handlingChinese];
      
      final result = matchInputChineseWithMeaningItems(state.wordWrapper!, inputs);
      bool isMatch = _isAsrPassSync(result.totalCount, result.matchedCount);
      
      if (result.newMatchCount > 0) {
        state = state.copyWith(canLeaveCurrWord: true);
        if (isMatch) {
          await asr.stopAsr();
          _onAnswerCorrect(_calculateRating());
          SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
        }
      }
    } else if (state.studyStep == StudyStep.ch2En.json) {
      String correctSpell = state.word!.spell.toLowerCase();
      String inputLower = inputText.trim().toLowerCase();
      
      bool isMatch = inputLower.replaceAll(RegExp(r'[^a-z]'), '') == correctSpell.replaceAll(RegExp(r'[^a-z]'), '');
      if (!isMatch && asrInput != null && (state.currentScore ?? 0) >= Constants.phonemeMatchThreshold) {
        isMatch = true;
      }
      
      if (isMatch) {
        if (asrInput != null) {
          meaningController.text = state.word!.spell;
        }
        await asr.stopAsr();
        _onAnswerCorrect(_calculateRating());
      }
    }
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

  FsrsRating _calculateRating() {
    if (state.wordStartTime == null) return FsrsRating.good;
    final responseTime = AppClock.now().difference(state.wordStartTime!).inSeconds;
    
    FsrsRating rating = FsrsRating.good;
    if (responseTime < 8) {
      rating = FsrsRating.easy;
    } else if (responseTime >= 18) {
      rating = FsrsRating.hard;
    }
    
    if (state.hintTapCount >= 2 || state.showSentenceTranslation) {
      rating = FsrsRating.again;
    } else if (state.hintTapCount == 1) {
      if (rating == FsrsRating.easy) {
        rating = FsrsRating.good;
      } else if (rating == FsrsRating.good) {
        rating = FsrsRating.hard;
      } else if (rating == FsrsRating.hard) {
        rating = FsrsRating.again;
      }
    }
    return rating;
  }

  void _onAnswerCorrect(FsrsRating rating) async {
    state = state.copyWith(hasFinishedAnswering: true, canLeaveCurrWord: true, lastFsrsRating: rating);
    
    final lw = state.currentGetWordResult?.learningWord;
    if (lw != null) {
      final fsrs = FSRS();
      int daysSinceLastReview = 0;
      if (lw.lastLearningDate != null) {
        daysSinceLastReview = AppClock.today().difference(app_date.DateUtils.pureDate(lw.lastLearningDate!)).inDays;
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

    if (state.studyStep == StudyStep.ch2En.json && !PlatformUtils.isWeb) {
      SoundUtil.prefetchSounds([Util.getWordSoundUrl(state.word!.spell, word: state.word)]);
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (state.studyStep != StudyStep.ch2En.json) {
      SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
    } else {
      SoundUtil.playPronounceSound2(state.word!, _audioPlayer);
    }

    bool autoJump = state.studyStep == StudyStep.ch2En.json ? state.autoJumpAfterCorrectCh2En : state.autoJumpAfterCorrectEn2Ch;
    if (autoJump && state.historyIndex == -1) {
      Future.delayed(const Duration(milliseconds: 800), () {
        getNextWord(true, fsrsRating: rating);
      });
    }
  }

  Future<void> playWordAndFirstSentence(UserVo user, bool forcePlayWord, bool startAsrWhenFinish) async {
    final studyConfig = StudyConfig.fromCurrentUser();
    bool willPlayWord = state.studyStep == StudyStep.en2Ch.json && (studyConfig.autoPlayWord || forcePlayWord);
    bool willPlaySentence = state.studyStep == StudyStep.en2Ch.json && studyConfig.autoPlaySentence;

    if (willPlayWord || willPlaySentence) {
      await asr.stopAsr();
    }

    try {
      if (willPlayWord) {
        await SoundUtil.playPronounceSound2(state.word!, _audioPlayer);
      }
      if (willPlaySentence && state.englishDigestOfFirstSentence != null) {
        await SoundUtil.playSentenceSound2(state.englishDigestOfFirstSentence!, _audioPlayer);
      }
    } finally {
      if (startAsrWhenFinish) {
        _handleTabChangeForAsr();
      }
    }
  }

  void _handleTabChangeForAsr() {
    bool isInSpeakTab = state.tabIndex == 0; 
    
    if (isInSpeakTab) {
      if (state.hasFinishedAnswering || state.showHandwritingBoard || state.isGettingNextWord || state.isKeyboardVisible) {
        if (asr.state != AsrState.stopped && asr.state != AsrState.initialized) {
          asr.stopAsr();
        }
        return;
      }

      if (asr.state == AsrState.started) return;

      final language = state.studyStep == StudyStep.ch2En.json ? AsrLanguage.english : AsrLanguage.chinese;
      _startAsrWithHint(language);
    } else {
      if (asr.state != AsrState.stopped && asr.state != AsrState.initialized) {
        asr.stopAsr();
      }
    }
  }

  Future<void> _startAsrWithHint(AsrLanguage language) async {
    if (state.showHandwritingBoard || state.isGettingNextWord) return;
    if (asr.state == AsrState.started) return;

    try {
      await asr.startAsr(language);
      if (PlatformUtils.isIOS) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await SoundUtil.playAsrReadyHintSound();
      state = state.copyWith(wordStartTime: AppClock.now());
    } catch (e) {
      Global.logger.e('ASR启动失败: $e');
    }
  }

  void handleTabChangeForAsr() {
    bool isInSpeakTab = state.tabIndex == 0; 
    
    if (isInSpeakTab) {
      if (state.hasFinishedAnswering || state.showHandwritingBoard || state.isGettingNextWord || state.isKeyboardVisible) {
        if (asr.state != AsrState.stopped && asr.state != AsrState.initialized) {
          asr.stopAsr();
        }
        return;
      }

      if (asr.state == AsrState.started) return;

      final language = state.studyStep == StudyStep.ch2En.json ? AsrLanguage.english : AsrLanguage.chinese;
      _startAsrWithHint(language);
    } else {
      if (asr.state != AsrState.stopped && asr.state != AsrState.initialized) {
        asr.stopAsr();
      }
    }
  }

  void updateKeyboardVisibility(bool visible) {
    state = state.copyWith(isKeyboardVisible: visible);
    if (visible) {
      asr.stopMicrophone();
    } else {
      handleTabChangeForAsr();
    }
  }

  void updateShowHandwritingBoard(bool show) {
    state = state.copyWith(showHandwritingBoard: show);
    if (!show) {
      handleTabChangeForAsr();
    }
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
    state = state.copyWith(playingStates: {...state.playingStates, audioType: true});
    await asr.stopAsr();
    try {
      await playSound();
    } finally {
      state = state.copyWith(playingStates: {...state.playingStates, audioType: false});
      _handleTabChangeForAsr();
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

  bool get _shouldShowSpeakTab {
    if (!PlatformUtils.isAsrSupported()) return false;
    if (state.studyStep == StudyStep.ch2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    return true;
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
}
