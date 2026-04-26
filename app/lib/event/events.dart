import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
/// 支持多订阅、通过泛型自动拦截分发对应的具象业务事件
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

/// 产生的具体业务事件管理，随着业务深入可在此向下无限扩展

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


