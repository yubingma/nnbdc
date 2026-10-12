/// 对战本地出题用的单词包队列。
///
/// 服务端一次下发一段连续单词（`[起始索引, 词条列表]`），手机本地依次出题，
/// 不再每答一题就往返一次。这个类只管"当前包 / 预取的下包 / 什么时候该补包"
/// 的下标记账，不碰界面，便于单测（见 test/word_pack_queue_test.dart）。
class WordPackQueue {
  /// 当前包剩余不足这么多个时提前预取下一包，避免下一次断链正好卡在包尾
  static const int prefetchThreshold = 8;

  final List<dynamic> _current = [];
  int _currentStart = 0;
  final List<dynamic> _next = [];
  int _nextStart = 0;

  /// 已经发出去的补包请求起始索引（-1 表示没有在途请求）
  int _requestedFrom = -1;

  /// 新一局开打：清空上一局的单词包
  void reset() {
    _current.clear();
    _currentStart = 0;
    _next.clear();
    _nextStart = 0;
    _requestedFrom = -1;
  }

  /// 收到一个单词包：落在当前包范围内的（开局首包、重连后重新对齐）直接接管，
  /// 落在当前包之后的存为下一包
  void accept(int fromIndex, List<dynamic> entries) {
    _requestedFrom = -1;
    if (_current.isEmpty || fromIndex < _currentStart + _current.length) {
      _currentStart = fromIndex;
      _current
        ..clear()
        ..addAll(entries);
    } else {
      _nextStart = fromIndex;
      _next
        ..clear()
        ..addAll(entries);
    }
  }

  /// 取第 index 题；本地暂时没有这一题时返回 null
  dynamic wordAt(int index) {
    // 当前包用完且下一包已预取到，无缝接管
    if (_next.isNotEmpty && index >= _nextStart) {
      _currentStart = _nextStart;
      _nextStart = 0;
      _current
        ..clear()
        ..addAll(_next);
      _next.clear();
    }

    final offset = index - _currentStart;
    if (offset >= 0 && offset < _current.length) {
      return _current[offset];
    }
    return null;
  }

  /// 现在需要向服务端补包时返回请求的起始索引，不需要补时返回 null。
  /// 同一段只会要一次，避免包尾每题都重复要一整包词。
  int? packRequestFor(int index) {
    final offset = index - _currentStart;
    final bool hasWord = offset >= 0 && offset < _current.length;
    if (hasWord) {
      if (_current.length - offset > prefetchThreshold || _next.isNotEmpty) {
        return null;
      }
      return _markRequested(_currentStart + _current.length);
    }

    if (_next.isNotEmpty && index >= _nextStart) {
      return null; // 下一包马上就能接管
    }
    return _markRequested(index);
  }

  /// 主动要了一包词（开局、重连后）
  void markRequested(int fromIndex) {
    _requestedFrom = fromIndex;
  }

  /// 断线前在途的补包请求可能已经丢了，重连后允许对同一段再要一次
  void forgetRequested() {
    _requestedFrom = -1;
  }

  int? _markRequested(int fromIndex) {
    if (_requestedFrom == fromIndex) return null;
    _requestedFrom = fromIndex;
    return fromIndex;
  }
}
