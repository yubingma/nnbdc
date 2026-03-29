/// 可注入的时间提供器，便于在测试中模拟时间
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

class FakeClock implements Clock {
  DateTime _now;

  FakeClock(DateTime start) : _now = start;

  @override
  DateTime now() => _now;

  void setNow(DateTime dateTime) {
    _now = dateTime;
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void advanceDays(int days) {
    _now = _now.add(Duration(days: days));
  }
}

class AppClock {
  static Clock _clock = SystemClock();
  static Duration _offset = Duration.zero;

  static void setClock(Clock clock) {
    _clock = clock;
  }

  static void reset() {
    _clock = SystemClock();
    _offset = Duration.zero;
  }

  static DateTime now() => _clock.now().add(_offset);

  static void advanceDays(int days) {
    _offset += Duration(days: days);
  }

  static int getOffsetDays() {
    return _offset.inDays;
  }

  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }
}
