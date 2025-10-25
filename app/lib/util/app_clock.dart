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

  static void setClock(Clock clock) {
    _clock = clock;
  }

  static void reset() {
    _clock = SystemClock();
  }

  static DateTime now() => _clock.now();

  static DateTime today() {
    final n = _clock.now();
    return DateTime(n.year, n.month, n.day);
  }
}
