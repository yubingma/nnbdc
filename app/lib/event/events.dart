import 'dart:async';

/// 基于 Dart Stream 实现的轻量化事件总线 (EventBus)
/// 支持多订阅、通过泛型自动拦截分发对应的具象业务事件
class EventBus {
  EventBus._(); // 阻止实例化

  static final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();

  /// 发布一个事件（由发射端调用，可以是任何具象类实例）
  static void publish(dynamic event) {
    _streamController.add(event);
  }

  /// 监听特定类型的事件（由接收端注册，通过泛型精准拦截匹配）
  static Stream<T> on<T>() {
    return _streamController.stream.where((event) => event is T).cast<T>();
  }
}

/// 产生的具体业务事件管理，随着业务深入可在此向下无限扩展

/// 产生了新错词的具体业务事件
class NewWrongWordEvent {
  final String? wordId;
  NewWrongWordEvent({this.wordId});
}
