import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/constants.dart';
import '../models/word_detail_page_args.dart' as bdc_args;

class BdcController extends GetxController with GetTickerProviderStateMixin {
  late TabController tabController;
  final word = Rxn<WordVo>();
  final wordWrapper = Rxn<WordWrapper>();
  final fsrsItem = Rxn<FSRSItem>();
  final lastFsrsRating = Rxn<FsrsRating>();
  final nextReviewTimes = <FsrsRating, String>{}.obs;
  
  final isDarkMode = false.obs;
  final studyStep = "".obs;
  final currentGetWordResult = Rxn<GetWordResult>();
  
  final hasFinishedAnswering = false.obs;
  final canLeaveCurrWord = false.obs;
  final playedSomething = false.obs;
  final isKeyboardVisible = false.obs;
  
  final highlightedWordImg = Rxn<WordImageVo>();
  final playingStates = <String, bool>{}.obs;
  
  final AudioPlayer wordSoundPlayer = AudioPlayer();
  final AudioPlayer sentenceSoundPlayer = AudioPlayer();
  late AnimationController wordSoundController;
  late AnimationController sentenceSoundController;
  
  final FocusNode meaningFocusNode = FocusNode();
  final TextEditingController meaningController = TextEditingController();
  
  final words = Rx<List<WordVo>>([]);
  final flippedAnswerIndices = <int>{}.obs;
  int? selectedAnswerIndex;
  int? correctAnswerIndex;
  
  DateTime? wordStartTime;
  FsrsRating? lowestRatingForCurrentWord;
  
  String? englishDigestOfFirstSentence;
  String? asrPassRuleCache;
  final List<Future> playingCorrectSounds = [];
  
  final buttonsEnabled = true.obs;
  final showBorders = false.obs;
  final bottomButtonsKey = GlobalKey();
  final errorReportController = TextEditingController();
  bool wordImageEdited = false;
  bool autoJumpAfterCorrect = true;
  bool autoJumpAfterCorrectCh2En = true;
  bool autoJumpAfterCorrectEn2Ch = true;
  
  final List<GetWordResult> history = [];
  final historyIndex = (-1).obs;

  final isUpdatingByHint = false.obs;
  int progressBarTapCount = 0;
  Timer? progressBarTapTimer;
  final activeUserStudySteps = <String>[].obs;
  final slideDirection = AxisDirection.right.obs;
  final showAnswerButtons = false.obs;
  final isGettingNextWord = false.obs;
  final isWordMastered = false.obs;
  final currentScore = 0.obs;
  final speakPanelScrollController = ScrollController();
  final showHandwritingBoard = false.obs;
  final showSentenceTranslation = false.obs;
  final isEditMode = false.obs;
  Future<List<LearningLog>>? learningHistoryFuture;
  final dataLoaded = false.obs;
  final assessmentRating = Rxn<FsrsRating>();
  final lastFsrsRatingReason = Rxn<String>();
  
  final asrState = AsrState.unknown.obs;
  final asrResult = "".obs;

  double get slideDirectionValue => slideDirection.value == AxisDirection.right ? 1.0 : -1.0;

  @override
  void onInit() {
    super.onInit();
    Global.logger.d('BdcController: onInit starting');
    tabController = TabController(length: 2, vsync: this);
    wordSoundController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    sentenceSoundController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    
    isDarkMode.value = Get.isDarkMode;
    
    KeyboardVisibilityController().onChange.listen((bool visible) {
      isKeyboardVisible.value = visible;
    });
    
    Asr().addStateListener((state) => asrState.value = state);
    
    // Initialize jump settings
    try {
      final config = StudyConfig.fromCurrentUser();
      autoJumpAfterCorrectCh2En = config.autoJumpAfterCorrectCh2En;
      autoJumpAfterCorrectEn2Ch = config.autoJumpAfterCorrectEn2Ch;
    } catch (e) {
      Global.logger.w('BdcController: Failed to load config in onInit: $e');
    }

    Global.logger.d('BdcController: Initializing with config - autoJump: $autoJumpAfterCorrect');
    
    getNextWord(false);
  }

  @override
  void onClose() {
    Global.logger.d('BdcController: onClose');
    tabController.dispose();
    wordSoundPlayer.dispose();
    sentenceSoundPlayer.dispose();
    wordSoundController.dispose();
    sentenceSoundController.dispose();
    meaningFocusNode.dispose();
    meaningController.dispose();
    errorReportController.dispose();
    speakPanelScrollController.dispose();
    progressBarTapTimer?.cancel();
    super.onClose();
  }

  Future<void> handleWord(GetWordResult result) async {
    Global.logger.d('BdcController: handleWord started for ${result.learningWord?.word.spell}');
    currentGetWordResult.value = result;
    
    // Set immediate values to allow UI to render something
    studyStep.value = result.stepIndex == 0 ? StudyStep.en2Ch.json : StudyStep.ch2En.json;
    word.value = result.learningWord?.word;
    
    if (word.value != null) {
      wordWrapper.value = WordWrapper(word.value!, result.learningWord);
    }

    // Load full word details if only ID is provided (asynchronous)
    if (result.learningWord?.word.id != null && (result.learningWord?.word.spell.isEmpty ?? true)) {
      Global.logger.d('BdcController: Loading full word details for ID: ${result.learningWord!.word.id}');
      try {
        final searchResult = await WordBo().searchWordById(result.learningWord!.word.id!, Global.currentUserId);
        if (searchResult.word != null) {
          result.learningWord!.word = searchResult.word!;
          word.value = searchResult.word!;
          wordWrapper.value = WordWrapper(word.value!, result.learningWord);
        }
      } catch (e) {
        Global.logger.e('BdcController: Failed to load word details: $e');
      }
    }
    
    if (result.learningWord != null) {
      fsrsItem.value = FSRSItem(
        stability: result.learningWord!.stability ?? 0.0,
        difficulty: result.learningWord!.difficulty ?? 0.0,
        elapsedDays: result.learningWord!.elapsedDays ?? 0,
        scheduledDays: result.learningWord!.scheduledDays ?? 0,
        reps: result.learningWord!.reps ?? 0,
        lapses: result.learningWord!.lapses ?? 0,
        state: FsrsState.values[result.learningWord!.state ?? 0],
      );
    }
    
    wordStartTime = AppClock.now();
    lowestRatingForCurrentWord = null;
    hasFinishedAnswering.value = false;
    canLeaveCurrWord.value = false;
    playedSomething.value = false;
    
    selectedAnswerIndex = null;
    flippedAnswerIndices.clear();
    asrResult.value = "";
    
    await prepareWordData();
    
    if (word.value?.id != null && Global.currentUserId != null) {
      learningHistoryFuture = MyDatabase.instance.learningLogsDao.getHistory(Global.currentUserId!, word.value!.id!);
    }
    
    dataLoaded.value = true;
    Global.logger.d('BdcController: dataLoaded marked true');
    
    _initAsrListener();
    
    if (StudyConfig.fromCurrentUser().autoPlayWord) {
      playWordAndFirstSentence(Global.getLoggedInUser()!, false, false);
    }
    
    update();
  }

  void _initAsrListener() {
    Asr().initAsr((event) {
      try {
        String processedEvent = "";
        if (event is String) {
          processedEvent = event;
        } else if (event is Map) {
          final candidates = event['candidates'] as List?;
          processedEvent = event['best'] ?? (candidates != null && candidates.isNotEmpty ? candidates.first : "");
        }
        
        if (studyStep.value == StudyStep.ch2En.json) {
          asrResult.value = AsrUtil.preprocessEnglish(processedEvent, word.value?.spell ?? "");
        } else {
          asrResult.value = AsrUtil.preprocess(processedEvent);
        }
        
        if (asrResult.value.isNotEmpty) {
          checkAsrResult(asrInput: asrResult.value);
        }
      } catch (e) {
        Global.logger.e("ASR result processing error: $e");
      }
    });
    
    _setAsrContextualPhrases();
  }

  void _setAsrContextualPhrases() {
    if (word.value == null) return;
    List<String> phrases = [];
    if (studyStep.value == StudyStep.ch2En.json) {
      phrases.add(word.value!.spell);
    } else {
      phrases.addAll(AsrUtil.extractContextualPhrases(word.value!.meaningItems ?? []));
    }
    Asr().setContextualStrings(phrases);
  }

  Future<void> prepareWordData() async {
    if (word.value == null) return;
    Global.logger.d('BdcController: prepareWordData starting');
    if (word.value!.sentences.isNotEmpty) {
      englishDigestOfFirstSentence = word.value!.sentences.first.english;
    } else {
      englishDigestOfFirstSentence = null;
    }
    
    List<WordVo> selectionWords = [];
    if (currentGetWordResult.value?.otherWords != null) {
      selectionWords = List.from(currentGetWordResult.value!.otherWords!);
    }
    
    // Add target word if not already present
    if (!selectionWords.any((w) => w.id == word.value!.id)) {
      selectionWords.add(word.value!);
    }
    
    selectionWords.shuffle();
    
    // Add "None of the above" at the end
    selectionWords.add(WordVo.c2("[ 都不对 ]"));
    
    words.value = selectionWords;
    correctAnswerIndex = (words.value.indexWhere((w) => w.id == word.value!.id)) + 1;
    Global.logger.d('BdcController: prepareWordData finished, correct index: $correctAnswerIndex');
  }

  void updateFsrsPreview(FsrsRating rating) {
    if (fsrsItem.value == null) return;
    final fsrs = FSRS();
    nextReviewTimes.clear();
    for (var r in FsrsRating.values) {
      final nextItem = fsrs.next(fsrsItem.value!, r, fsrsItem.value!.elapsedDays);
      nextReviewTimes[r] = "${nextItem.scheduledDays}天后";
    }
  }

  void onAnswerCorrect(FsrsRating rating) {
    hasFinishedAnswering.value = true;
    canLeaveCurrWord.value = true;
    lastFsrsRating.value = rating;
    
    final config = StudyConfig.fromCurrentUser();
    bool autoJump = studyStep.value == StudyStep.ch2En.json ? config.autoJumpAfterCorrectCh2En : config.autoJumpAfterCorrectEn2Ch;

    if (autoJump) {
      Future.delayed(const Duration(milliseconds: 800), () {
        getNextWord(true, fsrsRating: rating);
      });
    }
    update();
  }

  Future<void> getNextWord(bool success, {FsrsRating? fsrsRating}) async {
    Global.logger.d('BdcController: getNextWord started');
    isGettingNextWord.value = true;
    try {
      final result = await StudyBo().getWord(false, true, fsrsRating: fsrsRating);
      isGettingNextWord.value = false;
      if (result.success && result.data != null) {
        history.add(result.data!);
        historyIndex.value = history.length - 1;
        Global.logger.d('BdcController: getNextWord success, index: ${historyIndex.value}');
        await handleWord(result.data!);
      } else if (result.success && result.data?.finished == true) {
        Global.logger.d('BdcController: Study finished, going back');
        Get.back();
      } else {
        Global.logger.w('BdcController: getWord failed or returned no data: ${result.msg}');
      }
    } catch (e, st) {
      isGettingNextWord.value = false;
      Global.logger.e('BdcController: getNextWord FATAL error: $e', stackTrace: st);
    }
  }

  void handleTabChangeForAsr() {
    if (tabController.index == 0) {
      startAsr();
    } else {
      Asr().stopAsr();
    }
  }

  Future<void> startAsr() async {
    _initAsrListener();
    final lang = studyStep.value == StudyStep.ch2En.json ? AsrLanguage.english : AsrLanguage.chinese;
    await Asr().startAsr(lang);
    SoundUtil.playAsrReadyHintSound();
  }

  String hideParenthesesContent(String text) {
    if (text.isEmpty) return text;
    final parenthesesRegex = RegExp(r'[（(][^）)]*[）)]');
    String result = text.replaceAll(parenthesesRegex, '');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'[;；]\s*[;；]'), '；');
    result = result.replaceAll(RegExp(r'[,，]\s*[,，]'), '，');
    return result;
  }

  String hideAnswerLeakContent(String text) {
    if (text.isEmpty) return text;
    String result = text;
    final parenthesesRegex = RegExp(r'[（(][^）)]*[）)]');
    result = result.replaceAll(parenthesesRegex, '');
    final englishWordRegex = RegExp(r'\b[a-zA-Z]+\b(?=的|是|为|，|；|\.|$)');
    result = result.replaceAll(englishWordRegex, '***');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'[;；]\s*[;；]'), '；');
    result = result.replaceAll(RegExp(r'[,，]\s*[,，]'), '，');
    return result;
  }

  bool isAsrPassSync(int total, int matched) {
    switch (asrPassRuleCache) {
      case 'ALL': return matched >= total && total > 0;
      case 'HALF': return matched >= ((total + 1) >> 1);
      case 'ONE': default: return matched >= 1;
    }
  }

  Future<void> playWordAndFirstSentence(User user, bool forcePlayWord, bool startAsrWhenFinish) async {
    if (playingCorrectSounds.isNotEmpty) await Future.wait(playingCorrectSounds);
    final savedStep = studyStep.value;
    final savedId = word.value?.id;
    try {
      if (word.value != null) {
        if (studyStep.value == StudyStep.en2Ch.json || forcePlayWord) {
          playedSomething.value = true;
          await playWithAnimation(word.value!.pronounce ?? word.value!.spell, wordSoundPlayer, wordSoundController, stateKey: 'word');
        }
        if (studyStep.value == StudyStep.en2Ch.json && englishDigestOfFirstSentence != null) {
          playedSomething.value = true;
          await Future.delayed(const Duration(milliseconds: 300));
          if (word.value?.id == savedId) {
            await playWithAnimation(englishDigestOfFirstSentence!, sentenceSoundPlayer, sentenceSoundController, stateKey: 'sentence');
          }
        }
      }
    } catch (e) {
      Global.logger.e('播放失败', error: e);
    } finally {
      if (startAsrWhenFinish && studyStep.value == savedStep && word.value?.id == savedId) {
        handleTabChangeForAsr();
      }
    }
  }

  Future<void> playWithAnimation(String sound, AudioPlayer player, AnimationController animationController, {String? stateKey}) async {
    if (sound.isEmpty) return;
    final key = stateKey ?? sound;
    playingStates[key] = true;
    try {
      animationController.repeat(reverse: true);
      if (sound.contains('/') || sound.contains('\\')) {
        await player.play(DeviceFileSource(sound));
      } else {
        await SoundUtil.playPronounceSound2(word.value!, player);
      }
      await player.onPlayerComplete.first;
    } finally {
      animationController.stop(canceled: false);
      animationController.value = 0.0;
      playingStates[key] = false;
    }
  }

  void giveALittleHint() {
    if (wordWrapper.value != null) {
      wordWrapper.value!.hintLetterCount++;
      update();
    }
  }

  void giveFullHint() {
    if (wordWrapper.value != null) {
      wordWrapper.value!.hintLetterCount = word.value?.spell.length ?? 0;
      update();
    }
  }

  void clearHint() {
    if (wordWrapper.value != null) {
      wordWrapper.value!.hintLetterCount = 0;
      update();
    }
  }

  void goToPreviousWord() {
    if (historyIndex.value > 0) {
      historyIndex.value--;
      currentGetWordResult.value = history[historyIndex.value];
      handleWord(currentGetWordResult.value!);
    }
  }

  Future<void> reloadWord() async {
    final result = await StudyBo().getWord(false, false);
    if (result.success && result.data != null) {
      await handleWord(result.data!);
    }
  }

  void onAnswerClicked(int index) async {
    if (selectedAnswerIndex != null) {
      int wordIdx = index - 1;
      if (wordIdx >= 0 && wordIdx < words.value.length) {
        if (words.value[wordIdx].spell == "[ 都不对 ]") return;
        if (flippedAnswerIndices.contains(wordIdx)) {
          flippedAnswerIndices.remove(wordIdx);
        } else {
          flippedAnswerIndices.add(wordIdx);
        }
        update();
      }
      return;
    }
    if (hasFinishedAnswering.value) {
      selectedAnswerIndex = index;
      int wordIdx = index - 1;
      if (wordIdx >= 0 && wordIdx < words.value.length) {
        if (words.value[wordIdx].spell != "[ 都不对 ]") {
          flippedAnswerIndices.add(wordIdx);
        }
      }
      update();
      return;
    }
    selectedAnswerIndex = index;
    hasFinishedAnswering.value = (index == correctAnswerIndex);
    if (hasFinishedAnswering.value) {
      FsrsRating rating = calculateFsrsRating(AppClock.now().difference(wordStartTime!).inSeconds, false);
      if (lowestRatingForCurrentWord == null || rating.index < lowestRatingForCurrentWord!.index) {
        lowestRatingForCurrentWord = rating;
      }
      rating = lowestRatingForCurrentWord!;
      lastFsrsRating.value = rating;
      onAnswerCorrect(rating);
    } else {
      if (lowestRatingForCurrentWord == null || FsrsRating.again.index < lowestRatingForCurrentWord!.index) {
        lowestRatingForCurrentWord = FsrsRating.again;
      }
      SoundUtil.playAssetSoundConcurrent('failed.mp3', 1.5, 1.0);
      showWordDetail(word.value!, true, fsrsRating: lowestRatingForCurrentWord, reason: "选错了答案");
    }
    update();
  }

  Future<void> showWordDetail(WordVo word, bool isAnswerWrong, {FsrsRating? fsrsRating, String? reason}) async {
    if (fsrsRating != null) {
      if (lowestRatingForCurrentWord == null || fsrsRating.index < lowestRatingForCurrentWord!.index) {
        lowestRatingForCurrentWord = fsrsRating;
      }
      lastFsrsRating.value = lowestRatingForCurrentWord;
      hasFinishedAnswering.value = true;
      canLeaveCurrWord.value = true;
      meaningFocusNode.unfocus();
      updateFsrsPreview(fsrsRating);
      update();
    }
    
    await Get.toNamed('/word_detail', arguments: bdc_args.WordDetailPageArgs(word: word, showAddButton: false));
    handleTabChangeForAsr();
  }

  List<Tab> get dynamicTabs {
    List<Tab> tabs = [];
    tabs.add(Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.mic, size: 18), const SizedBox(width: 4), const Text('说')])));
    tabs.add(Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.touch_app, size: 18), const SizedBox(width: 4), const Text('选')])));
    return tabs;
  }

  void resetHighlightedWordImg() {
    highlightedWordImg.value = null;
    update();
  }

  bool wordImageHasBeenVoted(WordImageVo image) {
    return false;
  }

  void updateFsrsRating(FsrsRating rating) {
    lastFsrsRating.value = rating;
    updateFsrsPreview(rating);
    update();
  }

  Future<void> checkAsrResult({String? asrInput, bool isVoice = true}) async {
    if (wordWrapper.value == null) return;
    
    final input = asrInput ?? meaningController.text.trim();
    if (input.isEmpty) return;
    
    if (studyStep.value == StudyStep.ch2En.json) {
      // English check
      final correctSpell = word.value?.spell.toLowerCase() ?? "";
      final inputText = input.toLowerCase();
      
      bool isMatch = inputText == correctSpell;
      if (!isMatch) {
        final score = await AsrUtil.calculateOverallSimilarity(inputText, correctSpell);
        if (score >= Constants.phonemeMatchThreshold) {
          isMatch = true;
        }
      }
      
      if (isMatch) {
        onAnswerCorrect(calculateFsrsRating(AppClock.now().difference(wordStartTime!).inSeconds, false));
      }
    } else {
      // Chinese check
      final result = matchInputChineseWithMeaningItems(wordWrapper.value!, input);
      if (result.newMatchCount > 0) {
        bool isPass = false;
        final rule = StudyConfig.fromCurrentUser().asrPassRule;
        switch (rule) {
          case 'HALF': isPass = result.matchedCount >= (result.totalCount / 2).ceil(); break;
          case 'ALL': isPass = result.matchedCount >= result.totalCount; break;
          case 'ONE': default: isPass = true; break;
        }
        if (isPass) {
          onAnswerCorrect(calculateFsrsRating(AppClock.now().difference(wordStartTime!).inSeconds, false));
        }
      }
    }
  }

  void reinitializeTabController() {
    tabController.dispose();
    tabController = TabController(length: 2, vsync: this);
    update();
  }

  FsrsRating calculateFsrsRating(int elapsedSeconds, bool isSpellWrong) {
    if (isSpellWrong) return FsrsRating.again;
    if (elapsedSeconds < 5) return FsrsRating.easy;
    if (elapsedSeconds < 10) return FsrsRating.good;
    if (elapsedSeconds < 20) return FsrsRating.hard;
    return FsrsRating.again;
  }
}
