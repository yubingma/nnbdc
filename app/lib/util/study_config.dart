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
  int asrPassRule;
  Map<String, dynamic>? walkman;

  StudyConfig({
    this.autoPlayWord = true,
    this.autoPlaySentence = false,
    this.showAnswersDirectly = true,
    this.enableAllWrong = false,
    this.autoJumpAfterCorrectCh2En = true,
    this.autoJumpAfterCorrectEn2Ch = false,
    this.asrPassRule = 60,
    this.walkman,
  });

  factory StudyConfig.fromJson(Map<String, dynamic> json) {
    return StudyConfig(
      autoPlayWord: json['autoPlayWord'] ?? true,
      autoPlaySentence: json['autoPlaySentence'] ?? false,
      showAnswersDirectly: json['showAnswersDirectly'] ?? true,
      enableAllWrong: json['enableAllWrong'] ?? false,
      autoJumpAfterCorrectCh2En: json['autoJumpAfterCorrectCh2En'] ?? true,
      autoJumpAfterCorrectEn2Ch: json['autoJumpAfterCorrectEn2Ch'] ?? false,
      asrPassRule: json['asrPassRule'] ?? 60,
      walkman: json['walkman'],
    );
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
      } catch (e) {
        Global.logger.e('Failed to parse studyConfig: $e');
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
