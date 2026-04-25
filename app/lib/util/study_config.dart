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
  String asrPassRule;
  bool enableWordImage;
  bool preferKeyboardInSpelling;
  String distractorStrategy;
  Map<String, dynamic>? walkman;

  StudyConfig({
    this.autoPlayWord = true,
    this.autoPlaySentence = false,
    this.showAnswersDirectly = true,
    this.enableAllWrong = false,
    this.autoJumpAfterCorrectCh2En = false,
    this.autoJumpAfterCorrectEn2Ch = false,
    this.asrPassRule = 'ONE',
    this.enableWordImage = true,
    this.preferKeyboardInSpelling = false,
    this.distractorStrategy = 'RecentlyLearned',
    this.walkman,
  });

  factory StudyConfig.fromJson(Map<String, dynamic> json) {
    return StudyConfig(
      autoPlayWord: _toBool(json['autoPlayWord'], true),
      autoPlaySentence: _toBool(json['autoPlaySentence'], false),
      showAnswersDirectly: _toBool(json['showAnswersDirectly'], true),
      enableAllWrong: _toBool(json['enableAllWrong'], false),
      autoJumpAfterCorrectCh2En: _toBool(json['autoJumpAfterCorrectCh2En'], false),
      autoJumpAfterCorrectEn2Ch: _toBool(json['autoJumpAfterCorrectEn2Ch'], false),
      asrPassRule: _toAsrPassRule(json['asrPassRule']),
      enableWordImage: _toBool(json['enableWordImage'], true),
      preferKeyboardInSpelling: _toBool(json['preferKeyboardInSpelling'], false),
      distractorStrategy: json['distractorStrategy'] is String ? json['distractorStrategy'] : 'RecentlyLearned',
      walkman: json['walkman'] is Map<String, dynamic> ? json['walkman'] : null,
    );
  }

  static bool _toBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value != 0; 
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
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
      'asrPassRule': asrPassRule,
      'enableWordImage': enableWordImage,
      'preferKeyboardInSpelling': preferKeyboardInSpelling,
      'distractorStrategy': distractorStrategy,
      if (walkman != null) 'walkman': walkman,
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
