import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
class EventBus {
  EventBus._(); 

  static final _wrongWordController = StreamController<NewWrongWordEvent>.broadcast();
  static final _studyFinishedController = StreamController<TodayStudyPlanFinishedEvent>.broadcast();
  static final _wordDeletedController = StreamController<WordDeletedFromWordListEvent>.broadcast();
  static final _wordMasteredController = StreamController<WordMasteredEvent>.broadcast();
  static final _wordUnMasteredController = StreamController<WordUnMasteredEvent>.broadcast();
  static final _dictDownloadCompletedController = StreamController<DictDownloadCompletedEvent>.broadcast();

  /// 产生的具体业务事件：发射与监听（新错词产生）
  static void publishNewWrongWord(NewWrongWordEvent event) {
    _wrongWordController.add(event);
  }

  static Stream<NewWrongWordEvent> onNewWrongWord() {
    return _wrongWordController.stream;
  }

  /// 产生的具体业务事件：发射与监听（今日学习计划已完成）
  static void publishTodayStudyPlanFinished(TodayStudyPlanFinishedEvent event) {
    _studyFinishedController.add(event);
  }

  static Stream<TodayStudyPlanFinishedEvent> onTodayStudyPlanFinished() {
    return _studyFinishedController.stream;
  }

  /// 产生的具体业务事件：发射与监听（从词表中删除了单词）
  static void publishWordDeletedFromWordList(WordDeletedFromWordListEvent event) {
    _wordDeletedController.add(event);
  }

  static Stream<WordDeletedFromWordListEvent> onWordDeletedFromWordList() {
    return _wordDeletedController.stream;
  }

  /// 产生的具体业务事件：发射与监听（标记了单词为掌握）
  static void publishWordMastered(WordMasteredEvent event) {
    _wordMasteredController.add(event);
  }

  static Stream<WordMasteredEvent> onWordMastered() {
    return _wordMasteredController.stream;
  }

  /// 产生的具体业务事件：发射与监听（取消了单词的掌握状态）
  static void publishWordUnMastered(WordUnMasteredEvent event) {
    _wordUnMasteredController.add(event);
  }

  static Stream<WordUnMasteredEvent> onWordUnMastered() {
    return _wordUnMasteredController.stream;
  }

  /// 词书下载完成事件：发射与监听（用于跨页面刷新，如今日计划下载后通知"我"页面刷新）
  static void publishDictDownloadCompleted(DictDownloadCompletedEvent event) {
    _dictDownloadCompletedController.add(event);
  }

  static Stream<DictDownloadCompletedEvent> onDictDownloadCompleted() {
    return _dictDownloadCompletedController.stream;
  }

  /// 书桌词书发生变化事件：发射与监听（停学/选书后通知其他页面刷新书桌）
  static final _learningDictChangedController = StreamController<LearningDictChangedEvent>.broadcast();

  static void publishLearningDictChanged(LearningDictChangedEvent event) {
    _learningDictChangedController.add(event);
  }

  static Stream<LearningDictChangedEvent> onLearningDictChanged() {
    return _learningDictChangedController.stream;
  }

  /// 词表单词集合变化事件：批量导入、删除单词后，通知词表总览等页面重新统计词数
  static final _dictWordsChangedController = StreamController<DictWordsChangedEvent>.broadcast();

  static void publishDictWordsChanged(DictWordsChangedEvent event) {
    _dictWordsChangedController.add(event);
  }

  static Stream<DictWordsChangedEvent> onDictWordsChanged() {
    return _dictWordsChangedController.stream;
  }

  /// 今日学习列表进度变化事件：学习页学完（含加量批次）后发射。
  /// 学习页跳完成页用的是 pushReplacement，被替换路由的 push future 永远不会完成，
  /// 计划页挂在 push('/bdc').then(...) 上的刷新会失效，必须靠这个业务事实补齐，
  /// 否则计划页会停留在进入学习页之前的旧快照（加量进度、主按钮全都不对）。
  static final _todayStudyListChangedController = StreamController<TodayStudyListChangedEvent>.broadcast();

  static void publishTodayStudyListChanged(TodayStudyListChangedEvent event) {
    _todayStudyListChangedController.add(event);
  }

  static Stream<TodayStudyListChangedEvent> onTodayStudyListChanged() {
    return _todayStudyListChangedController.stream;
  }
}

/// 产生了新错词的具体业务事件
class NewWrongWordEvent {
  final String? wordId;
  NewWrongWordEvent({this.wordId});
}

/// 今日学习计划已完成
class TodayStudyPlanFinishedEvent {
  final String? wordId;
  TodayStudyPlanFinishedEvent({this.wordId});
}

/// 从词表中删除了单词
class WordDeletedFromWordListEvent {
  final String? wordId;
  WordDeletedFromWordListEvent({this.wordId});
}

/// 标记了单词为掌握
class WordMasteredEvent {
  final String? wordId;
  WordMasteredEvent({this.wordId});
}

/// 取消了单词的掌握状态
class WordUnMasteredEvent {
  final String? wordId;
  WordUnMasteredEvent({this.wordId});
}

/// 受管理的刷新契约接口
abstract class RefreshableTab {
  /// 是否有脏数据需要刷新
  bool get isDirty;
  
  /// 命令：重载数据
  void refreshData();
}

/// 词书下载完成事件（无论成功/失败都会被触发，用于跨页面同步刷新）
class DictDownloadCompletedEvent {
  final List<String> dictIds;
  DictDownloadCompletedEvent({required this.dictIds});
}

/// 书桌词书发生变化事件（停学/选书保存后发射，通知所有页面刷新书桌）
class LearningDictChangedEvent {
  const LearningDictChangedEvent();
}

/// 词表的单词集合发生变化（批量导入、删除单词等），用于跨页面同步刷新词数
class DictWordsChangedEvent {
  final String? dictId;
  const DictWordsChangedEvent({this.dictId});
}

/// 今日学习列表（含打卡后追加的加量批次）的进度已变化。
/// 与 [TodayStudyPlanFinishedEvent] 的区别：后者是打卡这一事实，计划页收到后会重新准备
/// 今日计划（取词/削减）；本事件只表示"列表进度变了"，计划页只需重算进度与主按钮。
class TodayStudyListChangedEvent {
  final String? wordId;
  const TodayStudyListChangedEvent({this.wordId});
}