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

enum ClientType { browser, android, ios, windows, macos, linux, jmeter }

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
      case ClientType.linux:
        return "Linux";
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

  static UserDayStatus fromJson(String json) {
    switch (json) {
      case "LOGGEDIN":
        return UserDayStatus.loggedIn;
      case "STUDIED":
        return UserDayStatus.studied;
      case "DAKAED":
        return UserDayStatus.dakaed;
      default:
        return UserDayStatus.notLogin;
    }
  }
}

enum StudyStep {
  /// 英→中 - 眼
  en2Ch,

  /// 中→英 - 眼
  ch2En,

  /// 例句英→中
  enSentence2Ch,

  /// 例句中→英
  chSentence2En,

  /// 列表模式 - 预览/复习当前批次单词
  list,

  /// 未知兜底（用于未来向后兼容）
  unknown
}

extension StudyStepExt on StudyStep {
  String get json {
    switch (this) {
      case StudyStep.en2Ch:
        return "En2Ch";
      case StudyStep.ch2En:
        return "Ch2En";
      case StudyStep.enSentence2Ch:
        return "EnSentence2Ch";
      case StudyStep.chSentence2En:
        return "ChSentence2En";
      case StudyStep.list:
        return "List";
      case StudyStep.unknown:
        return "Unknown";
    }
  }

  String get description {
    switch (this) {
      case StudyStep.en2Ch:
        return "单词 ・ 英→中";
      case StudyStep.ch2En:
        return "单词 ・ 中→英";
      case StudyStep.enSentence2Ch:
        return "例句 ・ 英→中";
      case StudyStep.chSentence2En:
        return "例句 ・ 中→英";
      case StudyStep.list: 
        return "单词列表";
      case StudyStep.unknown:
        return "未知环节";
    }
  }

  static StudyStep fromString(String value) {
    switch (value) {
      case "En2Ch":
        return StudyStep.en2Ch;
      case "Ch2En":
        return StudyStep.ch2En;
      case "EnSentence2Ch":
        return StudyStep.enSentence2Ch;
      case "ChSentence2En":
        return StudyStep.chSentence2En;
      case "List":
        return StudyStep.list;
      default:
        // 遇到未来未知步骤，返回 unknown，避免老客户端崩溃
        return StudyStep.unknown;
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

enum WordListStudyMode { list, dictation, dictationHandwriting, speakChinese, speakEnglish, walkman, hideChinese, hideEnglish }


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

enum FeatureRequestStatus { voting, inProgress, rejected, completed }

extension FeatureRequestStatusExt on FeatureRequestStatus {
  String get json {
    switch (this) {
      case FeatureRequestStatus.voting:
        return "VOTING";
      case FeatureRequestStatus.inProgress:
        return "IN_PROGRESS";
      case FeatureRequestStatus.rejected:
        return "REJECTED";
      case FeatureRequestStatus.completed:
        return "COMPLETED";
    }
  }

  String get description {
    switch (this) {
      case FeatureRequestStatus.voting:
        return "投票中";
      case FeatureRequestStatus.inProgress:
        return "开发中";
      case FeatureRequestStatus.rejected:
        return "已拒绝";
      case FeatureRequestStatus.completed:
        return "已完成";
    }
  }

  static FeatureRequestStatus fromString(String value) {
    switch (value) {
      case "VOTING":
        return FeatureRequestStatus.voting;
      case "IN_PROGRESS":
        return FeatureRequestStatus.inProgress;
      case "REJECTED":
        return FeatureRequestStatus.rejected;
      case "COMPLETED":
        return FeatureRequestStatus.completed;
      default:
        throw Error();
    }
  }
}

enum FsrsRating {
  /// 重来
  again,

  /// 困难
  hard,

  /// 一般
  good,

  /// 简单
  easy
}

extension FsrsRatingExt on FsrsRating {
  int get value {
    switch (this) {
      case FsrsRating.again:
        return 1;
      case FsrsRating.hard:
        return 2;
      case FsrsRating.good:
        return 3;
      case FsrsRating.easy:
        return 4;
    }
  }

  String get label {
    switch (this) {
      case FsrsRating.again:
        return "忘记";
      case FsrsRating.hard:
        return "模糊";
      case FsrsRating.good:
        return "良好";
      case FsrsRating.easy:
        return "轻松";
    }
  }

  static FsrsRating fromInt(int value) {
    switch (value) {
      case 1:
        return FsrsRating.again;
      case 2:
        return FsrsRating.hard;
      case 3:
        return FsrsRating.good;
      case 4:
        return FsrsRating.easy;
      default:
        throw ArgumentError('Invalid FsrsRating value: $value');
    }
  }
}

enum FsrsState {
  /// 新词
  newItem,

  /// 学习中
  learning,

  /// 复习中
  review,

  /// 重学中
  relearning
}

extension FsrsStateExt on FsrsState {
  int get value {
    switch (this) {
      case FsrsState.newItem:
        return 0;
      case FsrsState.learning:
        return 1;
      case FsrsState.review:
        return 2;
      case FsrsState.relearning:
        return 3;
    }
  }

  static FsrsState fromInt(int? value) {
    if (value == null) return FsrsState.newItem;
    switch (value) {
      case 0:
        return FsrsState.newItem;
      case 1:
        return FsrsState.learning;
      case 2:
        return FsrsState.review;
      case 3:
        return FsrsState.relearning;
      default:
        return FsrsState.newItem;
    }
  }
}
