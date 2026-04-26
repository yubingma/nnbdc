import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
class EventBus {
  EventBus._(); 

  static final _wrongWordController = StreamController<NewWrongWordEvent>.broadcast();

  /// 产生的具体业务事件：发射与监听（新错词产生）
  static void publishNewWrongWord(NewWrongWordEvent event) {
    _wrongWordController.add(event);
  }

  static Stream<NewWrongWordEvent> onNewWrongWord() {
    return _wrongWordController.stream;
  }
}

/// 产生了新错词的具体业务事件
class NewWrongWordEvent {
  final String? wordId;
  NewWrongWordEvent({this.wordId});
}

/// 受管理的刷新契约接口
abstract class RefreshableTab {
  /// 是否有脏数据需要刷新
  bool get isDirty;
  
  /// 命令：重载数据
  void refreshData();
}






