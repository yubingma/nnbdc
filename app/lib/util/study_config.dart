import 'dart:convert';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/db/db.dart';
import 'package:drift/drift.dart' as drift;

class StudyConfig {
  bool autoPlayWord;
  bool autoPlaySentence;
  bool showAnswersDirectly;
  bool enableAllWrong;
  bool autoJumpAfterCorrectCh2En;
  bool autoJumpAfterCorrectEn2Ch;
  bool autoJumpAfterCorrectChSentence2En;
  bool autoJumpAfterCorrectEnSentence2Ch;
  String asrPassRule;
  bool enableWordImage;
  bool preferKeyboardInSpelling;
  String distractorStrategy;
  bool mixWithOthersForIos;
  bool showWordDetailAfterCorrect;
  Map<String, dynamic>? walkman;
  int minNewWordsPerDay;

  /// 每组单词数（学习批次大小）：整组横向推进时一组容纳多少词，见 [effectiveBatchSize]
  int batchSize;

  /// 用户已关闭学习页「本组环节顺序提示」，不再展示
  bool hideGroupStepHint;

  /// 每组单词数的上限（防异常安全兜底，实际由当日计划词数 wordsPerDay 动态约束）
  static const int maxBatchSize = 500;

  StudyConfig({
    this.autoPlayWord = true,
    this.autoPlaySentence = false,
    this.showAnswersDirectly = true,
    this.enableAllWrong = false,
    this.autoJumpAfterCorrectCh2En = false,
    this.autoJumpAfterCorrectEn2Ch = false,
    this.autoJumpAfterCorrectChSentence2En = false,
    this.autoJumpAfterCorrectEnSentence2Ch = false,
    this.asrPassRule = 'ONE',
    this.enableWordImage = true,
    this.preferKeyboardInSpelling = false,
    this.distractorStrategy = 'RecentlyLearned',
    this.mixWithOthersForIos = false,
    this.showWordDetailAfterCorrect = false,
    this.walkman,
    this.minNewWordsPerDay = 0,
    this.batchSize = 10,
    this.hideGroupStepHint = false,
  });

  factory StudyConfig.fromJson(Map<String, dynamic> json) {
    return StudyConfig(
      autoPlayWord: _toBool(json['autoPlayWord'], true),
      autoPlaySentence: _toBool(json['autoPlaySentence'], false),
      showAnswersDirectly: _toBool(json['showAnswersDirectly'], true),
      enableAllWrong: _toBool(json['enableAllWrong'], false),
      autoJumpAfterCorrectCh2En: _toBool(json['autoJumpAfterCorrectCh2En'], false),
      autoJumpAfterCorrectEn2Ch: _toBool(json['autoJumpAfterCorrectEn2Ch'], false),
      autoJumpAfterCorrectChSentence2En: _toBool(json['autoJumpAfterCorrectChSentence2En'], false),
      autoJumpAfterCorrectEnSentence2Ch: _toBool(json['autoJumpAfterCorrectEnSentence2Ch'], false),
      asrPassRule: _toAsrPassRule(json['asrPassRule']),
      enableWordImage: _toBool(json['enableWordImage'], true),
      preferKeyboardInSpelling: _toBool(json['preferKeyboardInSpelling'], false),
      distractorStrategy: json['distractorStrategy'] is String ? json['distractorStrategy'] : 'RecentlyLearned',
      mixWithOthersForIos: _toBool(json['mixWithOthersForIos'], false),
      showWordDetailAfterCorrect: _toBool(json['showWordDetailAfterCorrect'], false),
      walkman: json['walkman'] is Map<String, dynamic> ? json['walkman'] : null,
      minNewWordsPerDay: _toInt(json['minNewWordsPerDay']),
      batchSize: _toInt(json['batchSize'], 10).clamp(1, maxBatchSize),
      hideGroupStepHint: _toBool(json['hideGroupStepHint'], false),
    );
  }

  /// 实际生效的每组单词数：一组不得超过当日计划词数，否则加量批次会被并进计划组，
  /// 破坏"加量不计入今日计划"的口径（组内进度指示也会把计划词算进加量的分母）。
  /// [wordsPerDay] <= 0 表示未设置计划量，不做压缩。
  int effectiveBatchSize(int wordsPerDay) =>
      wordsPerDay > 0 ? batchSize.clamp(1, wordsPerDay) : batchSize;

  static bool _toBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value != 0; 
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return defaultValue;
  }

  static int _toInt(dynamic value, [int defaultValue = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return defaultValue;
  }

  static String _toAsrPassRule(dynamic value) {
    if (value is String) return value;
    if (value is int) {
      if (value >= 100) return 'ALL';
      if (value >= 50) return 'HALF';
      return 'ONE';
    }
    return 'ONE';
  }

  Map<String, dynamic> toJson() {
    return {
      'autoPlayWord': autoPlayWord,
      'autoPlaySentence': autoPlaySentence,
      'showAnswersDirectly': showAnswersDirectly,
      'enableAllWrong': enableAllWrong,
      'autoJumpAfterCorrectCh2En': autoJumpAfterCorrectCh2En,
      'autoJumpAfterCorrectEn2Ch': autoJumpAfterCorrectEn2Ch,
      'autoJumpAfterCorrectChSentence2En': autoJumpAfterCorrectChSentence2En,
      'autoJumpAfterCorrectEnSentence2Ch': autoJumpAfterCorrectEnSentence2Ch,
      'asrPassRule': asrPassRule,
      'enableWordImage': enableWordImage,
      'preferKeyboardInSpelling': preferKeyboardInSpelling,
      'distractorStrategy': distractorStrategy,
      'mixWithOthersForIos': mixWithOthersForIos,
      'showWordDetailAfterCorrect': showWordDetailAfterCorrect,
      if (walkman != null) 'walkman': walkman,
      'minNewWordsPerDay': minNewWordsPerDay,
      'batchSize': batchSize,
      'hideGroupStepHint': hideGroupStepHint,
    };
  }

  // Helper method to fetch config from the current logged-in user
  static StudyConfig fromCurrentUser() {
    final user = Global.getLoggedInUser();
    if (user != null && user.studyConfig != null) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(user.studyConfig!);
        return StudyConfig.fromJson(jsonMap);
      } catch (e, stack) {
        Global.logger.e('Failed to parse studyConfig: $e', error: e, stackTrace: stack);
      }
    }
    return StudyConfig();
  }

  // Helper method to save config to the current logged-in user
  Future<void> saveToCurrentUser() async {
    final user = Global.getLoggedInUser();
    if (user != null) {
      final jsonStr = jsonEncode(toJson());
      final updatedUser = user.copyWith(studyConfig: drift.Value<String?>(jsonStr));
      await MyDatabase.instance.usersDao.saveUser(updatedUser, true);
      Global.updateUserCache(updatedUser);
    }
  }
}
