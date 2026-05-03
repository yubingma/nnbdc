import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/ocr_service.dart';
import '../theme/app_theme.dart';

class HandwritingBoard extends StatefulWidget {
  final Function(String) onRecognized;
  final VoidCallback onCancel;
  final ValueNotifier<bool>? rightZoneVisibleNotifier;
  final VoidCallback? onHint;

  final VoidCallback? onStartWriting;
  final VoidCallback? onPointerUp;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showCloseButton;
  final bool showHeader;
  final bool useBoxDecoration;
  final bool showCanvasButtons;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
    this.onStartWriting,
    this.onPointerUp,
    this.onSwipeUp,
    this.onSwipeDown,
    this.showCloseButton = true,
    this.showHeader = true,
    this.useBoxDecoration = true,
    this.showCanvasButtons = true,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
    this.rightZoneVisibleNotifier,
    this.onHint,
    this.onUndo,
    this.onRewrite,
  });

  final VoidCallback? onUndo;
  final VoidCallback? onRewrite;

  @override
  State<HandwritingBoard> createState() => HandwritingBoardState();
}

class HandwritingBoardState extends State<HandwritingBoard> {
  List<List<Offset>> _lines = [];
  bool _isRecognizing = false;
  int _recognitionVersion = 0;
  final GlobalKey<_HandwritingCanvasState> _canvasKey = GlobalKey<_HandwritingCanvasState>();
  
  void hideRightZone() {
    widget.rightZoneVisibleNotifier?.value = false;
  }

  void showRightZone() {
    widget.rightZoneVisibleNotifier?.value = true;
  }

  void clearBoard() {
    setState(() {
      _lines = [];
      _isRecognizing = false;
      _recognitionVersion++;
    });
    // 内容清空时，同步清空外部输入框
    widget.onRecognized("");
  }

  void clearBoardSilently() {
    _canvasKey.currentState?._controller.clear();
    _lines.clear();
    _isRecognizing = false;
    _recognitionVersion++;
  }

  void _clear() {
    clearBoard();
    widget.onRewrite?.call();
  }

  void _incrementVersion() {
    _recognitionVersion++;
    widget.onUndo?.call();
  }

  Future<void> _recognize() async {
    if (_lines.isEmpty) {
      widget.onRecognized("");
      return;
    }

    final int currentVersion = ++_recognitionVersion;
    debugPrint('HB: Triggering _recognize (version $currentVersion, strokes: ${_lines.length})');

    setState(() {
      _isRecognizing = true;
    });

    try {
      // 1. 调用识别引擎 (统一使用 Google ML Kit Digital Ink Recognition)
      final strokes = _lines.map((line) => line.map((p) => {'x': p.dx, 'y': p.dy}).toList()).toList();
      final recognitionFuture = OcrService.recognizeHandwriting(strokes);
        
      final startTime = DateTime.now();
      final response = await recognitionFuture.timeout(const Duration(seconds: 5));
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('HB: OCR Recognition finished in ${duration}ms, result: "$response"');

      // 关键：如果版本已改变，则丢弃当前陈旧的结果
      if (currentVersion != _recognitionVersion) {
        debugPrint('HB: Discarding stale result: version $currentVersion < $_recognitionVersion');
        return;
      }

      // 4. 后处理识别结果
      String text = response;

      // 视觉近形词替换
      String processedText = text
          .replaceAll('1', 'l')
          .replaceAll('0', 'o')
          .replaceAll('5', 's')
          .replaceAll('2', 'z')
          .replaceAll('8', 'b')
          .replaceAll('9', 'g')
          .replaceAll('6', 'g')
          .replaceAll('4', 'a')
          .replaceAll('7', 't');
          
      String result = processedText
          .replaceAll('|', 'l')
          .replaceAll('/', 'l')
          .replaceAll('\\', 'l')
          .replaceAll(RegExp(r"[^a-zA-Z\s\-']"), '') // 允许连字符和单引号
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      widget.onRecognized(result);
    } on TimeoutException {
      debugPrint('HB: Recognition timeout (5s)');
    } catch (e) {
      debugPrint('HB: Recognition error: $e');
    } finally {
      if (mounted && currentVersion == _recognitionVersion) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.useBoxDecoration ? BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ) : null,
      child: Column(
        children: [
          if (widget.showHeader)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.gesture, size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    '手写板',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Spacer(),
                  if (_isRecognizing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    ),
                  const SizedBox(width: 12),
                  if (widget.showCloseButton)
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: const Icon(Icons.close, size: 20, color: Colors.grey),
                    ),
                ],
              ),
            ),

          Expanded(
            child: Stack(
              children: [
                _HandwritingCanvas(
                  key: _canvasKey,
                  lines: _lines,
                  isRecognizing: _isRecognizing,
                  onRewrite: _clear,
                  onUndo: _incrementVersion,
                  onRecognize: _recognize,
                  onStartWriting: widget.onStartWriting,
                  onPointerUp: widget.onPointerUp,
                  onSwipeUp: widget.onSwipeUp,
                  onSwipeDown: widget.onSwipeDown,
                  showButtons: widget.showCanvasButtons,
                  onCancel: widget.onCancel,
                  enableNavigationGestures: widget.enableNavigationGestures,
                  smartRightZoneWidth: widget.smartRightZoneWidth,
                  rightZoneVisibleNotifier: widget.rightZoneVisibleNotifier,
                  onHint: widget.onHint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandwritingCanvas extends StatefulWidget {
  final List<List<Offset>> lines;
  final bool isRecognizing;
  final VoidCallback onRewrite;
  final VoidCallback onUndo;
  final VoidCallback onRecognize;
  final VoidCallback? onStartWriting;
  final VoidCallback? onPointerUp;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showButtons;
  final VoidCallback? onCancel;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;
  final ValueNotifier<bool>? rightZoneVisibleNotifier;
  final VoidCallback? onHint;

  const _HandwritingCanvas({
    super.key,
    required this.lines,
    required this.isRecognizing,
    required this.onRewrite,
    required this.onUndo,
    required this.onRecognize,
    this.onStartWriting,
    this.onPointerUp,
    this.onSwipeUp,
    this.onSwipeDown,
    required this.showButtons,
    this.onCancel,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
    this.rightZoneVisibleNotifier,
    this.onHint,
  });

  @override
  State<_HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<_HandwritingCanvas> {
  late final _HandwritingController _controller;
  int? _activePointerId;
  final Set<int> _ignoredPointers = {}; 
  DateTime _lastStrokeEndTime = DateTime.fromMillisecondsSinceEpoch(0);
  late double _currentSmartZoneWidth;
  Timer? _autoRecognizeTimer;

  @override
  void dispose() {
    _autoRecognizeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = _HandwritingController(widget.lines);
    _currentSmartZoneWidth = widget.smartRightZoneWidth;
  }

  @override
  void didUpdateWidget(_HandwritingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.rawLines = widget.lines;
    if (widget.lines.isEmpty && oldWidget.lines.isNotEmpty) {
      _controller.clear();
      _autoRecognizeTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        
        final bool isNarrow = width < 500;
        final bool hasHint = widget.onHint != null;
        final double zoneWidth = hasHint 
            ? (width * 0.21).clamp(60.0, 95.0) 
            : (width * 0.28).clamp(70.0, 120.0);
        final double zoneHeight = isNarrow ? 56 : 65;
        final double bottomMargin = isNarrow ? 20 : 40; 
        
        final rewriteZone = Rect.fromLTWH(
          width / 2 - (hasHint ? zoneWidth * 2.15 : zoneWidth * 1.6), 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final undoZone = Rect.fromLTWH(
          width / 2 - (hasHint ? zoneWidth * 1.05 : zoneWidth / 2), 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final hintZone = hasHint ? Rect.fromLTWH(
          width / 2 + zoneWidth * 0.05, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        ) : Rect.zero;
        final closeZone = Rect.fromLTWH(
          width / 2 + (hasHint ? zoneWidth * 1.15 : zoneWidth * 0.6), 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );

        return Listener(
          behavior: _currentSmartZoneWidth > 0 ? HitTestBehavior.translucent : HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_activePointerId != null) return;
            final p = event.localPosition;
            
            if (_currentSmartZoneWidth > 0) {
              final inRightZone = p.dx > width - _currentSmartZoneWidth;
              final isRecentWriting = DateTime.now().difference(_lastStrokeEndTime).inMilliseconds < 600;
              if (inRightZone && !isRecentWriting) {
                _ignoredPointers.add(event.pointer);
                return;
              }
            }

            if (rewriteZone.contains(p) || undoZone.contains(p) || closeZone.contains(p) || hintZone.contains(p)) {
              _ignoredPointers.add(event.pointer);
              return;
            }

            _activePointerId = event.pointer;
            _ignoredPointers.remove(event.pointer);
            widget.onStartWriting?.call();
            _autoRecognizeTimer?.cancel();
            _controller.start(p);
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointerId) return;
            _controller.move(event.localPosition, event.localDelta);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            
            _lastStrokeEndTime = DateTime.now();
            widget.onPointerUp?.call();

            _activePointerId = null;
            _controller.end();
            
            if (widget.lines.isNotEmpty) {
              _autoRecognizeTimer?.cancel();
              _autoRecognizeTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted && widget.lines.isNotEmpty) {
                  debugPrint('HB: Auto-triggering recognition via timer');
                  widget.onRecognize();
                }
              });
            } else {
              debugPrint('HB: Skip auto-trigger because lines is empty');
            }
            setState(() {});
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            _activePointerId = null;
            _controller.end();
            setState(() {});
          },
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _HandwritingPainter(_controller),
                  size: Size.infinite,
                ),
              ),
              
              if (widget.showButtons) ...[
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: zoneHeight + bottomMargin + 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: rewriteZone.left,
                  top: rewriteZone.top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _autoRecognizeTimer?.cancel();
                      _controller.clear();
                      widget.onRewrite();
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_sweep_outlined, color: Colors.grey, size: 22),
                          Text('重写', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasHint)
                Positioned(
                  left: hintZone.left,
                  top: hintZone.top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onHint?.call();
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.grey, size: 22),
                          Text('提示', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: closeZone.left,
                  top: closeZone.top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onCancel?.call();
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, color: Colors.grey, size: 22),
                          Text('关闭', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: undoZone.left,
                  top: undoZone.top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _autoRecognizeTimer?.cancel();
                      setState(() {
                        _controller.removeLast();
                      });
                      widget.onUndo();
                      widget.onRecognize();
                      if (widget.lines.isEmpty) {
                        widget.onRewrite();
                      }
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.undo_outlined, color: Colors.grey, size: 22),
                          Text('回退', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HandwritingController extends ChangeNotifier {
  List<List<Offset>> rawLines;
  Path finishedPath = Path();
  Path? activePath;
  Offset? lastRenderPoint; 
  Offset? midRenderPoint;
  Offset lastDelta = Offset.zero;
  Offset? lastSmoothPoint;

  _HandwritingController(this.rawLines) {
    _rebuildFinishedPath();
  }

  void _rebuildFinishedPath() {
    finishedPath = Path();
    for (var line in rawLines) {
      if (line.isEmpty) continue;
      finishedPath.moveTo(line[0].dx, line[0].dy);
      for (int i = 1; i < line.length - 1; i++) {
        final p0 = line[i];
        final p1 = line[i + 1];
        finishedPath.quadraticBezierTo(
            p0.dx, p0.dy, (p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
      }
      if (line.length > 1) {
        finishedPath.lineTo(line.last.dx, line.last.dy);
      }
    }
  }

  void start(Offset p) {
    rawLines.add([p]);
    activePath = Path();
    activePath!.moveTo(p.dx, p.dy);
    lastRenderPoint = p;
    midRenderPoint = p;
    lastSmoothPoint = p;
    lastDelta = Offset.zero;
    notifyListeners();
  }

  void clear() {
    rawLines.clear();
    finishedPath = Path();
    activePath = null;
    notifyListeners();
  }

  void removeLast() {
    if (rawLines.isNotEmpty) {
      rawLines.removeLast();
      _rebuildFinishedPath();
      activePath = null;
      notifyListeners();
    }
  }

  void move(Offset p, Offset delta) {
    if (activePath == null || lastRenderPoint == null || lastSmoothPoint == null) return;
    if ((p - lastSmoothPoint!).distanceSquared < 0.1) return;
    final smoothedPoint = lastSmoothPoint! * 0.45 + p * 0.55;
    rawLines.last.add(smoothedPoint); 
    lastDelta = delta;
    final newMidPoint =
        Offset((lastRenderPoint!.dx + smoothedPoint.dx) / 2.0, (lastRenderPoint!.dy + smoothedPoint.dy) / 2.0);
    activePath!.quadraticBezierTo(
        lastRenderPoint!.dx, lastRenderPoint!.dy, newMidPoint.dx, newMidPoint.dy);
    midRenderPoint = newMidPoint;
    lastRenderPoint = smoothedPoint;
    lastSmoothPoint = smoothedPoint;
    notifyListeners();
  }

  void end() {
    if (activePath != null && lastRenderPoint != null) {
      activePath!.lineTo(lastRenderPoint!.dx, lastRenderPoint!.dy);
      finishedPath.addPath(activePath!, Offset.zero);
      activePath = null;
      lastRenderPoint = null;
      midRenderPoint = null;
      lastSmoothPoint = null;
      notifyListeners();
    }
  }
}

class _HandwritingPainter extends CustomPainter {
  final _HandwritingController controller;
  late final Paint _linePaint;

  _HandwritingPainter(this.controller) : super(repaint: controller) {
    _linePaint = Paint()
      ..color = AppTheme.primaryColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.8
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(controller.finishedPath, _linePaint);
    if (controller.activePath != null &&
        controller.lastRenderPoint != null &&
        controller.midRenderPoint != null) {
      canvas.drawPath(controller.activePath!, _linePaint);
      final predictedTip = controller.lastRenderPoint! + controller.lastDelta * 1.5;
      canvas.drawLine(controller.midRenderPoint!, predictedTip, _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) => true;
}
