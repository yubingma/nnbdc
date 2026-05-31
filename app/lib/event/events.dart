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