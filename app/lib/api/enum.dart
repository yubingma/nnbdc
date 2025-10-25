enum CheckBy { email, userName, phone }

extension CheckByExt on CheckBy {
  String get json {
    switch (this) {
      case CheckBy.email:
        return "Email";
      case CheckBy.userName:
        return "UserName";
      case CheckBy.phone:
        return "Phone";
    }
  }
}

enum ClientType { browser, android, ios, windows, macos, jmeter }

extension ClientTypeExt on ClientType {
  String get json {
    switch (this) {
      case ClientType.browser:
        return "Browser";
      case ClientType.android:
        return "Android";
      case ClientType.ios:
        return "IOS";
      case ClientType.windows:
        return "Windows";
      case ClientType.macos:
        return "MacOS";
      case ClientType.jmeter:
        return "JMeter";
    }
  }
}

/// 用户每日状态(未登录/未学习/未打卡)
enum UserDayStatus {
  /// 未登录
  notLogin,

  /// 已登录
  loggedIn,

  /// 已学习
  studied,

  /// 已打卡
  dakaed
}

extension UserDayStatusExt on UserDayStatus {
  String get json {
    switch (this) {
      case UserDayStatus.notLogin:
        return "NOT_LOGIN";
      case UserDayStatus.loggedIn:
        return "LOGGEDIN";
      case UserDayStatus.studied:
        return "STUDIED";
      case UserDayStatus.dakaed:
        return "DAKAED";
    }
  }
}

enum StudyStep {
  /// 英→中 - 眼
  word,

  /// 中→英 - 眼
  meaning
}

extension StudyStepExt on StudyStep {
  String get json {
    switch (this) {
      case StudyStep.word:
        return "Word";
      case StudyStep.meaning:
        return "Meaning";
    }
  }

  String get description {
    switch (this) {
      case StudyStep.word:
        return "英→中";
      case StudyStep.meaning:
        return "中→英";
    }
  }

  static StudyStep fromString(String value) {
    switch (value) {
      case "Word":
        return StudyStep.word;
      case "Meaning":
        return StudyStep.meaning;
      default:
        throw ArgumentError('无效的StudyStep值：$value');
    }
  }
}

enum StudyStepState {
  /// 激活
  active,

  /// 非激活
  inactive
}

extension StudyStepStateExt on StudyStepState {
  String get json {
    switch (this) {
      case StudyStepState.active:
        return "Active";
      case StudyStepState.inactive:
        return "Inactive";
    }
  }
}

enum WordListStudyMode { list, dictation, speakChinese, speakEnglish, walkman }

enum TenseType { pastTense, pastParticiple, presentParticiple }

extension TenseTypeExt on TenseType {
  String get json {
    switch (this) {
      case TenseType.pastTense:
        return "过去式";
      case TenseType.pastParticiple:
        return "过去分词";
      case TenseType.presentParticiple:
        return "现在分词";
    }
  }

  static TenseType fromString(String value) {
    switch (value) {
      case "过去式":
        return TenseType.pastTense;
      case "过去分词":
        return TenseType.pastParticiple;
      case "现在分词":
        return TenseType.presentParticiple;
      default:
        throw Error();
    }
  }
}

enum MsgType { advice, adviceReply, normalMsg }

extension MsgTypeExt on MsgType {
  String get json {
    switch (this) {
      case MsgType.advice:
        return "建议";
      case MsgType.adviceReply:
        return "建议回复";
      case MsgType.normalMsg:
        return "普通消息";
    }
  }

  static MsgType fromString(String value) {
    switch (value) {
      case "建议":
        return MsgType.advice;
      case "建议回复":
        return MsgType.adviceReply;
      case "普通消息":
        return MsgType.normalMsg;
      default:
        throw Error();
    }
  }
}
