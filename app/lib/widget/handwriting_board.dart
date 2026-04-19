import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';

class HandwritingBoard extends StatefulWidget {
  final Function(String) onRecognized;
  final VoidCallback onCancel;
  final VoidCallback? onStartWriting;
  final bool showCloseButton;
  final bool showHeader;
  final bool useBoxDecoration;

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
    this.onStartWriting,
    this.showCloseButton = true,
    this.showHeader = true,
    this.useBoxDecoration = true,
  });

  @override
  State<HandwritingBoard> createState() => _HandwritingBoardState();
}

class _HandwritingBoardState extends State<HandwritingBoard> {
  List<List<Offset>> _lines = [];
  bool _isRecognizing = false;

  void _clear() {
    setState(() {
      _lines = [];
    });
  }

  Future<void> _recognize() async {
    if (_lines.isEmpty) {
      ToastUtil.info('请先写点什么');
      return;
    }

    setState(() {
      _isRecognizing = true;
    });

    try {
      // 1. 计算内容的精确边界，实现“动态紧凑裁剪”
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      bool hasValidStroke = false;

      for (var line in _lines) {
        if (line.length < 3) continue; // 更加激进地忽略孤立点（如无意的点或笔尖抖动）
        hasValidStroke = true;
        for (var point in line) {
          if (point.dx < minX) minX = point.dx;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dy > maxY) maxY = point.dy;
        }
      }

      if (!hasValidStroke) {
        ToastUtil.info('请先写点什么');
        setState(() => _isRecognizing = false);
        return;
      }

      const double margin = 100.0; // 增加垂直空间，适配手写体的长柄字母
      double contentWidth = maxX - minX;
      double contentHeight = maxY - minY;
      
      // 设定目标宽度为 800px (极致采样，适合单词识别)
      const double targetWidth = 800.0;
      double scale = (targetWidth - 2 * margin) / contentWidth;
      
      // 动态计算高度，保持比例
      double targetHeight = contentHeight * scale + 2 * margin;
      // 极端情况限制：防止高度过小
      if (targetHeight < 200) targetHeight = 200;

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
          ..color = const Color(0xFFFAFAFA)
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
        path.lineTo(line.last.dx, line.last.dy);
        canvas.drawPath(path, paint);
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

        // 3. 调用识别引擎 (增加 5 秒超时保护，防止原生层卡死导致 UI 永久冻结)
        final strokes = _lines.map((line) => line.map((p) => {'x': p.dx, 'y': p.dy}).toList()).toList();
        final recognitionFuture = Platform.isAndroid 
          ? OcrService.recognizeHandwriting(strokes)
          : OcrService.recognizeText(file.path);
        
        final response = await recognitionFuture.timeout(const Duration(seconds: 5));
        
        String text = "";
        String nativeInfo = "";
        
        if (Platform.isAndroid) {
          text = response;
          nativeInfo = "[Ink Android]";
        } else {
          List<String> parts = response.split(" ||| ");
          text = parts[0];
          nativeInfo = parts.length > 1 ? parts[1] : "";
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
          .replaceAll('9', 'g');
          
      // 提取有效的英文单词或短语（保留字母和空格）
      String result = processedText.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

      if (result.isEmpty) {
        // 如果是自动触发且结果为空，不弹提示以免干扰用户书写
        debugPrint('识别结果为空: "$rawOcrText"');
      } else {
        // 重要：显示识别结果
        ToastUtil.info('[Ink] 结果: $result');
        widget.onRecognized(result);
      }
    } on TimeoutException {
      debugPrint('识别超时 (5s)');
    } catch (e) {
      debugPrint('识别异常: $e');
    } finally {
      if (mounted) {
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
                  lines: _lines,
                  isRecognizing: _isRecognizing,
                  onRewrite: _clear,
                  onRecognize: _recognize,
                  onStartWriting: widget.onStartWriting,
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
  final VoidCallback onRecognize;
  final VoidCallback? onStartWriting;

  const _HandwritingCanvas({
    required this.lines,
    required this.isRecognizing,
    required this.onRewrite,
    required this.onRecognize,
    this.onStartWriting,
  });

  @override
  State<_HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<_HandwritingCanvas> {
  late final _HandwritingController _controller;
  int? _activePointerId;
  
  // 用于防止在一次划动中重复触发区域动作
  bool _rewriteTriggered = false;
  bool _undoTriggered = false;
  
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
  }

  @override
  void didUpdateWidget(_HandwritingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同步引用：始终确保控制器的 rawLines 指向父组件最新的 _lines
    _controller.rawLines = widget.lines;
    
    // 如果父组件清空了 _lines，同步清除控制器的内部路径状态
    if (widget.lines.isEmpty && oldWidget.lines.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        
        // 定义中心化的感应区，更加适合平板书写习惯，减少运笔负荷
        final bool isNarrow = width < 500;
        final double zoneWidth = (width * 0.35).clamp(80.0, 140.0);
        final double zoneHeight = isNarrow ? 56 : 65;
        final double bottomMargin = isNarrow ? 20 : 40; // 窄屏下稍微靠下一点，留出更多书写空间

        final rewriteZone = Rect.fromLTWH(
          (width / 2 - zoneWidth) / 2, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final undoZone = Rect.fromLTWH(
          width / 2 + (width / 2 - zoneWidth) / 2, 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            // 注意：重写按钮现在不被 isRecognizing 锁定，确保随时可重置
            if (_activePointerId != null) return;
            _activePointerId = event.pointer;
            _rewriteTriggered = false;
            _undoTriggered = false;

            final p = event.localPosition;
            
            // 触发开始书写回调并取消自动识别计时
            widget.onStartWriting?.call();
            _autoRecognizeTimer?.cancel();

            // 窄屏下，如果在感应区内按下，先给予视觉反馈且不立即开始绘画
            if (isNarrow) {
              if (rewriteZone.contains(p)) {
                setState(() => _activeZone = 1);
                return;
              }
              if (undoZone.contains(p)) {
                setState(() => _activeZone = 2);
                return;
              }
            }
            
            _controller.start(p);
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointerId) return;
            
            final p = event.localPosition;
            
            // 碰撞检测：扫过即触发
            if (!isNarrow && rewriteZone.contains(p) && !_rewriteTriggered) {
              _rewriteTriggered = true;
              setState(() => _activeZone = 1);
              HapticFeedback.lightImpact();
              
              _autoRecognizeTimer?.cancel(); // 取消自动识别
              _pendingRewardTask?.cancel();
              
              // 立即执行清空，不再等待 250ms
              _controller.clear(); 
              widget.onRewrite();
              
              // 延时恢复视觉状态即可
              Timer(const Duration(milliseconds: 200), () {
                if (mounted) setState(() => _activeZone = 0);
              });
            }
            if (!isNarrow && undoZone.contains(p) && !_undoTriggered) {
              _undoTriggered = true;
              setState(() => _activeZone = 2);
              HapticFeedback.lightImpact();
              
              _autoRecognizeTimer?.cancel(); // 撤销时重置识别计时
              _pendingUndoTask?.cancel();
              _pendingUndoTask = Timer(const Duration(milliseconds: 200), () {
                if (mounted) {
                  _controller.removeLast();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) setState(() => _activeZone = 0);
                  });
                }
              });
            }

            _controller.move(p, event.localDelta);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) return;

            try {
              final p = event.localPosition;
              
              // 先检查是否有全屏/回退手势 (增加空判断，修复 Bad state: No element)
              if (_controller.rawLines.isNotEmpty) {
                final swipeStatus = _controller._detectSwipe(_controller.rawLines.last);
                if (swipeStatus != 0) {
                  // 如果是手势，取消所有感应区的任务
                  _pendingRewardTask?.cancel();
                  _pendingUndoTask?.cancel();
                  setState(() => _activeZone = 0);
                  
                  // 标记为已触发，防止下方点击检测再次触发
                  _rewriteTriggered = true; 
                  _undoTriggered = true;

                  // 执行手势动作
                  if (swipeStatus == 2) {
                    // 向左滑：删除最后一笔 (撤销)
                    _controller.removeLast(); // 1. 先删掉这道“划痕”手势本身
                    _controller.removeLast(); // 2. 再删掉上一笔真正的内容笔迹
                    HapticFeedback.mediumImpact();
                  }
                }
              }

              // 点击检测：重写
              if (!_rewriteTriggered && rewriteZone.contains(p)) {
                _rewriteTriggered = true;
                setState(() => _activeZone = 1);
                HapticFeedback.lightImpact();
                
                _autoRecognizeTimer?.cancel();
                _pendingRewardTask?.cancel();
                
                _controller.clear();
                widget.onRewrite();
                
                Timer(const Duration(milliseconds: 200), () {
                  if (mounted) setState(() => _activeZone = 0);
                });
              } else if (!_undoTriggered && undoZone.contains(p)) {
                _undoTriggered = true;
                setState(() => _activeZone = 2);
                HapticFeedback.lightImpact();
                
                _autoRecognizeTimer?.cancel();
                _pendingUndoTask?.cancel();
                
                _controller.removeLast();
                
                Timer(const Duration(milliseconds: 200), () {
                  if (mounted) setState(() => _activeZone = 0);
                });
              }
            } finally {
              // 关键修复：无论发生什么，必须释放指针锁，防止画板永久失效
              _activePointerId = null;
              _controller.end();
              
              // 启动自动识别定时器 (停笔 0.5 秒后自动触发)
              if (widget.lines.isNotEmpty && !widget.isRecognizing) {
                _autoRecognizeTimer?.cancel();
                _autoRecognizeTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted && widget.lines.isNotEmpty && !widget.isRecognizing) {
                    widget.onRecognize();
                  }
                });
              }
              
              // 如果最终没有触发任何动作，确保重置激活区状态
              if (!_rewriteTriggered && !_undoTriggered) {
                setState(() => _activeZone = 0);
              }
            }
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) return;
            _activePointerId = null;
            _controller.end();
            setState(() => _activeZone = 0);
          },
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _HandwritingPainter(_controller),
                  size: Size.infinite,
                ),
              ),
              
              // 居中显示的感应目标区
              Positioned(
                left: rewriteZone.left,
                top: rewriteZone.top,
                child: Container(
                  width: zoneWidth,
                  height: zoneHeight,
                  decoration: BoxDecoration(
                    color: _activeZone == 1 
                      ? Colors.grey.withValues(alpha: 0.2) 
                      : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _activeZone == 1 ? Colors.grey : Colors.grey.withValues(alpha: 0.1), 
                      width: _activeZone == 1 ? 1.5 : 1
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined, 
                        color: _activeZone == 1 ? Colors.grey : Colors.grey.withValues(alpha: 0.4), 
                        size: 22
                      ),
                      Text(
                        isNarrow ? '重写' : '划过重写', 
                        style: TextStyle(
                          color: _activeZone == 1 ? Colors.grey : Colors.grey.withValues(alpha: 0.4), 
                          fontSize: isNarrow ? 12 : 11,
                          fontWeight: _activeZone == 1 ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: undoZone.left,
                top: undoZone.top,
                child: Container(
                  width: zoneWidth,
                  height: zoneHeight,
                  decoration: BoxDecoration(
                    color: _activeZone == 2 
                      ? AppTheme.primaryColor.withValues(alpha: 0.2) 
                      : AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _activeZone == 2 ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.1), 
                      width: _activeZone == 2 ? 1.5 : 1
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.undo_outlined, 
                        color: _activeZone == 2 ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.4), 
                        size: 22
                      ),
                      Text(
                        isNarrow ? '撤销' : '划过撤销', 
                        style: TextStyle(
                          color: _activeZone == 2 ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.4), 
                          fontSize: isNarrow ? 12 : 11,
                          fontWeight: _activeZone == 2 ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ],
                  ),
                ),
              ),
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

  /// 简单高效的“划掉”识别：检测到一个贯穿性的长横笔
  /// 手势识别：0:无, 1:从左往右(清除全部), 2:从右往左(删除最后一笔)
  int _detectSwipe(List<Offset> stroke) {
    if (stroke.length < 5) return 0;
    
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var p in stroke) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    double width = maxX - minX;
    double height = maxY - minY;

    // 判定条件：长横扫动作
    // 阈值调低 (从 280 降到 160)，增加灵敏度。
    // 只要划过大约 1/5 屏幕宽度即可触发。
    if (width > 160 && width > height * 2.0) {
      // 检查方向：位移超过 50 像素即认定方向有效
      if (stroke.first.dx - stroke.last.dx > 50) {
        return 2; // Right to Left (向左滑)
      } else if (stroke.last.dx - stroke.first.dx > 50) {
        return 1; // Left to Right (向右滑)
      }
    }
    return 0;
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
