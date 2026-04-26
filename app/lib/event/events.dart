import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
class EventBus {
  EventBus._(); 

  static final _wrongWordController = StreamController<NewWrongWordEvent>.broadcast();
  static final _tabSwitchedController = StreamController<TabSwitchedEvent>.broadcast();

  /// 产生的具体业务事件：发射与监听（新错词产生）
  static void publishNewWrongWord(NewWrongWordEvent event) {
    _wrongWordController.add(event);
  }

  static Stream<NewWrongWordEvent> onNewWrongWord() {
    return _wrongWordController.stream;
  }

  /// 产生的具体业务事件：发射与监听（Tab 栏切换）
  static void publishTabSwitched(TabSwitchedEvent event) {
    _tabSwitchedController.add(event);
  }

  static Stream<TabSwitchedEvent> onTabSwitched() {
    return _tabSwitchedController.stream;
  }
}

/// 产生了新错词的具体业务事件
class NewWrongWordEvent {
  final String? wordId;
  NewWrongWordEvent({this.wordId});
}

/// Tab 栏切换的具体业务事件
class TabSwitchedEvent {
  final int index;
  TabSwitchedEvent(this.index);
}




