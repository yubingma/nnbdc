import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
class EventBus {
  EventBus._(); 

  static final _wrongWordController = StreamController<NewWrongWordEvent>.broadcast();
  static final _studyFinishedController = StreamController<TodayStudyPlanFinishedEvent>.broadcast();
  static final _studyProgressController = StreamController<TodayStudyProgressChangedEvent>.broadcast();

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

  /// 产生的具体业务事件：发射与监听（今日学习进度变更）
  static void publishTodayStudyProgressChanged(TodayStudyProgressChangedEvent event) {
    _studyProgressController.add(event);
  }

  static Stream<TodayStudyProgressChangedEvent> onTodayStudyProgressChanged() {
    return _studyProgressController.stream;
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

/// 今日学习进度变更（例如单词被标记为掌握/删除等）
class TodayStudyProgressChangedEvent {
  final String? wordId;
  TodayStudyProgressChangedEvent({this.wordId});
}

/// 受管理的刷新契约接口
abstract class RefreshableTab {
  /// 是否有脏数据需要刷新
  bool get isDirty;
  
  /// 命令：重载数据
  void refreshData();
}






