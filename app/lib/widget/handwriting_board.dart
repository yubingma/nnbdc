import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';

class HandwritingBoard extends StatefulWidget {
  final Function(String) onRecognized;
  final VoidCallback onCancel;
  final VoidCallback? onStartWriting;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showCloseButton;
  final bool showHeader;
  final bool useBoxDecoration;
  final bool showCanvasButtons;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;
  final ValueNotifier<bool>? rightZoneVisibleNotifier;

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
    this.onStartWriting,
    this.onSwipeUp,
    this.onSwipeDown,
    this.showCloseButton = true,
    this.showHeader = true,
    this.useBoxDecoration = true,
    this.showCanvasButtons = true,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
    this.rightZoneVisibleNotifier,
  });

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
    // 彻底摒弃任何 setState 的触发，直接打穿底层控制器的内存状态进行局部 Canvas 重绘！
    _canvasKey.currentState?._controller.clear();
    _lines.clear();
    _isRecognizing = false;
    _recognitionVersion++;
  }

  void _clear() {
    clearBoard();
  }

  void _incrementVersion() {
    _recognitionVersion++;
  }

  Future<void> _recognize() async {
    if (_lines.isEmpty) {
      widget.onRecognized("");
      return;
    }

    final int currentVersion = ++_recognitionVersion;

    setState(() {
      _isRecognizing = true;
    });

    try {
      // 1. 计算内容的精确边界，实现“动态紧凑裁剪”
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      bool hasValidStroke = false;

      for (var line in _lines) {
        if (line.isEmpty) continue; 
        hasValidStroke = true;
        for (var point in line) {
          if (point.dx < minX) minX = point.dx;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dy > maxY) maxY = point.dy;
        }
      }

      if (!hasValidStroke) {
        setState(() => _isRecognizing = false);
        return;
      }

      const double margin = 80.0; 
      double contentWidth = maxX - minX;
      double contentHeight = maxY - minY;
      
      // 核心修复：基于高度进行适度缩放。
      // iOS 的 Vision 框架对过大或过小的图片都不够友好。
      // 将理想字符高度提升到 240px，总图高度约 400px，这通常是 Vision 识别的最佳“甜蜜点”。
      const double idealLetterHeight = 240.0; 
      double scale = idealLetterHeight / (contentHeight > 0 ? contentHeight : 1);
      
      // 限制缩放范围
      if (scale > 5.0) scale = 5.0;
      if (scale < 0.2) scale = 0.2;
      
      // 如果缩放后宽度过大（长单词），则进一步缩小以适配
      if (contentWidth * scale > 1200) {
        scale = 1200 / contentWidth;
      }
      
      double targetWidth = contentWidth * scale + 2 * margin;
      double targetHeight = contentHeight * scale + 2 * margin;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke // 关键修复：必须设置为描边，否则带圈字母（a,e,o）会变成黑团
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..strokeWidth = 16.0 / scale; // 适中笔触 (16px)，防止字母粘连导致 mis-recognition

      // 背景白色 (按需分配尺寸)
      canvas.drawRect(
        Rect.fromLTWH(0, 0, targetWidth, targetHeight),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      
      // (诊断测试已移除，Hello 已卸载)

      // 将内容绘制在动态区域中心
      canvas.save();
      canvas.translate(margin - minX * scale, margin - minY * scale);
      canvas.scale(scale);

      // 绘制逻辑
      for (final line in _lines) {
        if (line.length < 2) continue;
        final path = Path();
        path.moveTo(line[0].dx, line[0].dy);
        for (int i = 1; i < line.length - 1; i++) {
          final p0 = line[i];
          final p1 = line[i + 1];
          path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
        }
        if (line.length > 1) {
          path.lineTo(line.last.dx, line.last.dy);
          canvas.drawPath(path, paint);
        } else if (line.length == 1) {
          // 关键修复：单点也需要绘制，否则 i, j 的点或标点符号无法识别
          canvas.drawCircle(line[0], 8.0 / scale, Paint()..color = Colors.black..style = PaintingStyle.fill);
        }
      }
      canvas.restore();

      final picture = recorder.endRecording();
      final img = await picture.toImage(targetWidth.toInt(), targetHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('无法生成图片数据');

      final bytes = byteData.buffer.asUint8List();

      // 2. 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/handwriting_${AppClock.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

        if (currentVersion != _recognitionVersion) return;

        // 3. 调用识别引擎 (统一使用 Google ML Kit Digital Ink Recognition 以获得最佳体验)
        final strokes = _lines.map((line) => line.map((p) => {'x': p.dx, 'y': p.dy}).toList()).toList();
        final recognitionFuture = OcrService.recognizeHandwriting(strokes);
        
        final response = await recognitionFuture.timeout(const Duration(seconds: 5));
        
        String text = "";
        String nativeInfo = "";
        
        text = response;
        nativeInfo = Platform.isAndroid ? "[Ink Android]" : "[Ink iOS]";

      // 关键：如果版本已改变（说明期间有新的书写或撤销），则丢弃当前陈旧的结果
      if (currentVersion != _recognitionVersion) {
        debugPrint('丢弃陈旧的识别结果: version $currentVersion < $_recognitionVersion');
        return;
      }

      // 清理临时文件
      if (await file.exists()) await file.delete();

      // 4. 后处理识别结果
      String rawOcrText = text;

      debugPrint('OCR Raw Text: "$rawOcrText", Info: "$nativeInfo"');

      // 针对手写识别的常见错误进行“视觉近形词”替换 (如 1 -> l, 0 -> o)
      String processedText = rawOcrText
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
          .replaceAll(RegExp(r'[^a-zA-Z\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (result.isEmpty) {
        // 如果是自动触发且结果为空，不弹提示以免干扰用户书写
        debugPrint('识别结果为空: "$rawOcrText"');
      } 
      
      // 重要：无论结果是否为空都通知外部更新 UI，防止空结果时界面“卡住”不刷新
      widget.onRecognized(result);
    } on TimeoutException {
      debugPrint('识别超时 (5s)');
    } catch (e) {
      debugPrint('识别异常: $e');
    } finally {
      if (mounted && currentVersion == _recognitionVersion) {
        setState(() {
          _isRecognizing = false;
        });
      }
    }
 
  }

  // _drawOnCanvas 的逻辑已整合进 _recognize 以支持动态高度

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
          // 顶部标题
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

          // 画布区域 (独占所有垂直空间，最大化书写面积)
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
                  onSwipeUp: widget.onSwipeUp,
                  onSwipeDown: widget.onSwipeDown,
                  showButtons: widget.showCanvasButtons,
                  onCancel: widget.onCancel,
                  enableNavigationGestures: widget.enableNavigationGestures,
                  smartRightZoneWidth: widget.smartRightZoneWidth,
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
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showButtons;
  final VoidCallback? onCancel;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;

  const _HandwritingCanvas({
    super.key,
    required this.lines,
    required this.isRecognizing,
    required this.onRewrite,
    required this.onUndo,
    required this.onRecognize,
    this.onStartWriting,
    this.onSwipeUp,
    this.onSwipeDown,
    required this.showButtons,
    this.onCancel,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
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
  

  
  // 视觉反馈：当前激活的感应区 (0:无, 1:重写, 2:撤销)
  int _activeZone = 0;
  
  // 用于取消延时任务，防止划过手势与感应区动作冲突
  Timer? _pendingRewardTask; 
  Timer? _pendingUndoTask;
  Timer? _autoRecognizeTimer; // 自动识别定时器

  @override
  void dispose() {
    _pendingRewardTask?.cancel();
    _pendingUndoTask?.cancel();
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
    // 同步引用：始终确保控制器的 rawLines 指向父组件最新的 _lines
    _controller.rawLines = widget.lines;
    
    // 如果父组件清空了 _lines，同步清除控制器的内部路径状态，并瞬间斩断后台离线识别
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
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        
        // 定义中心化的感应区，更加适合平板书写习惯，减少运笔负荷
        final bool isNarrow = width < 500;
        final double zoneWidth = (width * 0.28).clamp(70.0, 120.0);
        final double zoneHeight = isNarrow ? 56 : 65;
        final double bottomMargin = isNarrow ? 20 : 40; 

        final rewriteZone = Rect.fromLTWH(
          width / 2 - zoneWidth * 1.6, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final undoZone = Rect.fromLTWH(
          width / 2 - zoneWidth / 2, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final closeZone = Rect.fromLTWH(
          width / 2 + zoneWidth * 0.6, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );

        return Listener(
          behavior: _currentSmartZoneWidth > 0 ? HitTestBehavior.translucent : HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_activePointerId != null) return;

            final p = event.localPosition;
            
            // 智能交互区逻辑
            if (_currentSmartZoneWidth > 0) {
              final inRightZone = p.dx > width - _currentSmartZoneWidth;
              final isRecentWriting = DateTime.now().difference(_lastStrokeEndTime).inMilliseconds < 600;
              
              if (inRightZone && !isRecentWriting) {
                _ignoredPointers.add(event.pointer);
                return; // 忽略此指针，让其透传到底层UI
              }
            }

            // 如果点击的是底部的功能控制按钮区域，则不作为书写轨迹起笔，交由底部的 GestureDetector 处理
            if (rewriteZone.contains(p) || undoZone.contains(p) || closeZone.contains(p)) {
              _ignoredPointers.add(event.pointer);
              return;
            }

            _activePointerId = event.pointer;
            _ignoredPointers.remove(event.pointer); // 确保从忽略列表中移除（如果它是由于isRecentWriting被捕获的）
            


            // 触发开始书写回调并取消自动识别计时
            widget.onStartWriting?.call();
            _autoRecognizeTimer?.cancel();

            // 移除了底层按键点击拦截
            
            _controller.start(p);
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointerId) {
              // 如果是正在书写的过程中进入了右侧感应区，且当前指针未被锁定（即起笔不在右侧），
              // 那么它其实应该已经被捕获了。这里的逻辑主要是防止处理被忽略的指针。
              if (_ignoredPointers.contains(event.pointer)) return;
              return;
            }
            
            final p = event.localPosition;
            
            _controller.move(p, event.localDelta);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            
            _lastStrokeEndTime = DateTime.now();

            try {

              
              // 移除了全屏滑动手势判定，仅使用底部控制按钮和正常书写

              // 原点击检测逻辑已升级迁移为原生 GestureDetector
            } finally {
              // 关键修复：无论发生什么，必须释放指针锁，防止画板永久失效
              _activePointerId = null;
              _controller.end();
              
              // 启动自动识别定时器 (停笔 0.5 秒后自动触发)
              // 关键修复：即使正在识别中，也允许重新启动定时器，以确保撤销等操作能触发新一轮识别
              if (widget.lines.isNotEmpty) {
                _autoRecognizeTimer?.cancel();
                _autoRecognizeTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted && widget.lines.isNotEmpty) {
                    widget.onRecognize();
                  }
                });
              }
              
              // 重置激活区状态
              setState(() => _activeZone = 0);
            }
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            _activePointerId = null;
            _controller.end();
            setState(() => _activeZone = 0);
          },
          child: Stack(
            children: [
              // 背景遮罩层 - 使用 IgnorePointer 确保它不拦截任何点击
              Positioned.fill(
                child: IgnorePointer(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                      if (widget.smartRightZoneWidth > 0)
                        Container(
                          width: widget.smartRightZoneWidth,
                          color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.05),
                        ),
                    ],
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _HandwritingPainter(_controller),
                  size: Size.infinite,
                ),
              ),
              
              if (widget.showButtons) ...[
                // 底部背景栏 - 不透明显示
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
                // 智能交互区视觉提示
                if (_currentSmartZoneWidth > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: _currentSmartZoneWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        // 向左拉扩大感应区 (dx 是负值)
                        setState(() {
                          _currentSmartZoneWidth -= details.delta.dx;
                          _currentSmartZoneWidth = _currentSmartZoneWidth.clamp(40.0, width * 0.7);
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        // 如果快速向左滑，触发关闭
                        if (details.primaryVelocity != null && details.primaryVelocity! < -800) {
                          widget.onCancel?.call();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.08),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          border: Border(
                            left: BorderSide(
                              color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // 在边界处增加一个视觉指示器
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: height / 2 - 20,
                              child: Icon(
                                Icons.chevron_left, 
                                size: 16, 
                                color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.3)
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 居中显示的感应目标区
                Positioned(
                  left: rewriteZone.left,
                  top: rewriteZone.top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _autoRecognizeTimer?.cancel();
                      _pendingRewardTask?.cancel();
                      _controller.clear();
                      widget.onRewrite();
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: _activeZone == 1 
                          ? Colors.grey.withValues(alpha: 0.25) 
                          : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _activeZone == 1 ? Colors.grey : Colors.grey.withValues(alpha: 0.2), 
                          width: _activeZone == 1 ? 1.5 : 1
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_sweep_outlined, 
                            color: _activeZone == 1 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                            size: 22
                          ),
                          Text(
                            isNarrow ? '重写' : '划过重写', 
                            style: TextStyle(
                              color: _activeZone == 1 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                              fontSize: isNarrow ? 12 : 11,
                              fontWeight: _activeZone == 1 ? FontWeight.bold : FontWeight.normal,
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 关闭按钮区
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
                        color: _activeZone == 3 
                          ? Colors.grey.withValues(alpha: 0.25) 
                          : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _activeZone == 3 ? Colors.grey : Colors.grey.withValues(alpha: 0.2), 
                          width: _activeZone == 3 ? 1.5 : 1
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.close, 
                            color: _activeZone == 3 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                            size: 22
                          ),
                          Text(
                            '关闭', 
                            style: TextStyle(
                              color: _activeZone == 3 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                              fontSize: isNarrow ? 12 : 11,
                              fontWeight: _activeZone == 3 ? FontWeight.bold : FontWeight.normal,
                            )
                          ),
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
                      _pendingUndoTask?.cancel();
                      setState(() {
                        _controller.removeLast();
                      });
                      widget.onUndo();
                      if (widget.lines.isEmpty) {
                        widget.onRewrite();
                      }
                    },
                    child: Container(
                      width: zoneWidth,
                      height: zoneHeight,
                      decoration: BoxDecoration(
                        color: _activeZone == 2 
                          ? Colors.grey.withValues(alpha: 0.25) 
                          : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _activeZone == 2 ? Colors.grey : Colors.grey.withValues(alpha: 0.2), 
                          width: _activeZone == 2 ? 1.5 : 1
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.undo_outlined, 
                            color: _activeZone == 2 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                            size: 22
                          ),
                          Text(
                            isNarrow ? '撤销' : '划过撤销', 
                            style: TextStyle(
                              color: _activeZone == 2 ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.6), 
                              fontSize: isNarrow ? 12 : 11,
                              fontWeight: _activeZone == 2 ? FontWeight.bold : FontWeight.normal,
                            )
                          ),
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
  
  // 核心视觉连接点 (无预测，保证字迹形状不失真)
  Offset? lastRenderPoint; 
  Offset? midRenderPoint;

  // 核心状态：用于平滑和预测的位移矢量
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

    // 1. 动态采样：保留微小细节
    if ((p - lastSmoothPoint!).distanceSquared < 0.1) return;

    // 2. 高保真平滑滤波 (High-Fidelity Smoothing)：
    // 将当前点权重提升至 55%，历史权重降至 45%。
    // 这样笔冒既能保留“几何美感”，又能极度敏锐地跟随您的物理变向，真正做到“尊重原始轨迹”。
    final smoothedPoint = lastSmoothPoint! * 0.45 + p * 0.55;

    // 3. 数据隔离存储：
    // 关键修正：存储平滑后的点而非原始抖动点，确保导出的识别图像与用户看到的同样平滑，减少 OCR 干扰
    rawLines.last.add(smoothedPoint); 
    lastDelta = delta; // 仅存储位移量，由绘制器动态应用预测，不破坏路径几何结构

    // 4. 构建稳定二阶贝塞尔路径
    // 使用纯净的平滑点构建路径，彻底解决“字迹变小/变形”的问题
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
      
      // 智能手势识别已在全屏模式下由于误触发率高而被暂时禁用
      // 用户现在应使用底部明确的“重写”和“识别”按钮，或继续在屏幕书写
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
  
  // 缓存 Paint 对象，避免每一帧都重新分配内存引发 GC 卡顿
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
      // 1. 绘制稳定的历史轨迹
      canvas.drawPath(controller.activePath!, _linePaint);
      
      // 2. 动态预测补齐 (Dynamic Ghost Tip)：
      // 预测仅作用于“最后一公里”的笔尖连线，给用户 1.5 帧的极速响应错觉，但不改变已生成的字迹形状。
      final predictedTip = controller.lastRenderPoint! + controller.lastDelta * 1.5;
      canvas.drawLine(controller.midRenderPoint!, predictedTip, _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) => true;
}
