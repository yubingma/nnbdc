import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';

class HandwritingBoard extends StatefulWidget {
  final Function(String) onRecognized;
  final VoidCallback onCancel;
  final bool showCloseButton;

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
    this.showCloseButton = true,
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
      // 1. 将画布转换为图片
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..color = Colors.black
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8.0;

      // 背景白色
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1000, 1000),
        Paint()..color = Colors.white,
      );

      // 计算边界以进行缩放/平移优化（可选）
      // 绘制逻辑已整合到 _drawOnCanvas 中，此处不再重复循环
      _drawOnCanvas(canvas, paint, 1000, 1000);

      final picture = recorder.endRecording();
      final img = await picture.toImage(1000, 1000);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('无法生成图片数据');

      // 2. 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/handwriting_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      // 3. 调用 OCR 识别
      final text = await OcrService.recognizeText(file.path);

      // 清理临时文件
      if (await file.exists()) await file.delete();

      // 提取有效的英文单词或短语（保留字母和空格）
      String result = text.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

      if (result.isEmpty) {
        ToastUtil.info('未能识别到单词');
      } else {
        widget.onRecognized(result);
      }
    } catch (e) {
      ToastUtil.error('识别失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
    } 
  }

  void _drawOnCanvas(Canvas canvas, Paint paint, double width, double height) {
    if (_lines.isEmpty) return;

    // 寻找内容的边界，以便进行居中和缩放
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var line in _lines) {
      for (var point in line) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    // 留出边距
    const margin = 50.0;
    double contentWidth = maxX - minX;
    double contentHeight = maxY - minY;
    if (contentWidth < 10) contentWidth = 10;
    if (contentHeight < 10) contentHeight = 10;

    double scaleX = (width - 2 * margin) / contentWidth;
    double scaleY = (height - 2 * margin) / contentHeight;
    double scale = scaleX < scaleY ? scaleX : scaleY;
    if (scale > 2.0) scale = 2.0;

    canvas.save();
    canvas.translate(
      (width - contentWidth * scale) / 2 - minX * scale,
      (height - contentHeight * scale) / 2 - minY * scale,
    );
    canvas.scale(scale);

    paint.style = PaintingStyle.stroke;
    paint.strokeJoin = StrokeJoin.round;

    for (final line in _lines) {
      if (line.isEmpty) continue;
      final path = Path();
      path.moveTo(line[0].dx, line[0].dy);
      for (int i = 1; i < line.length - 1; i++) {
        final p0 = line[i];
        final p1 = line[i + 1];
        path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
      }
      if (line.length > 1) {
        path.lineTo(line.last.dx, line.last.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部标题
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
            child: _HandwritingCanvas(
              lines: _lines,
              isRecognizing: _isRecognizing,
              onRewrite: _clear,
              onRecognize: _recognize,
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

  const _HandwritingCanvas({
    required this.lines,
    required this.isRecognizing,
    required this.onRewrite,
    required this.onRecognize,
  });

  @override
  State<_HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<_HandwritingCanvas> {
  late final _HandwritingController _controller;
  int? _activePointerId;
  
  // 用于防止在一次划动中重复触发区域动作
  bool _rewriteTriggered = false;
  bool _recognizeTriggered = false;
  
  // 视觉反馈：当前激活的感应区 (0:无, 1:重写, 2:识别)
  int _activeZone = 0;
  
  // 用于取消延时任务，防止划过手势与感应区动作冲突
  Timer? _pendingRewardTask; 
  Timer? _pendingRecognizeTask;

  @override
  void dispose() {
    _pendingRewardTask?.cancel();
    _pendingRecognizeTask?.cancel();
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
       final double zoneWidth = 130;
    final double zoneHeight = 65;
    final double bottomMargin = 40; // 调高位置，方便从底部向上方划入触发

        final rewriteZone = Rect.fromLTWH(
          (width / 3) - (zoneWidth / 2), 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );
        final recognizeZone = Rect.fromLTWH(
          ((width / 3) * 2) - (zoneWidth / 2), 
          height - zoneHeight - bottomMargin, 
          zoneWidth, 
          zoneHeight
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (widget.isRecognizing || _activePointerId != null) return;
            _activePointerId = event.pointer;
            _rewriteTriggered = false;
            _recognizeTriggered = false;
            _controller.start(event.localPosition);
          },
          onPointerMove: (event) {
            if (widget.isRecognizing || event.pointer != _activePointerId) return;
            
            final p = event.localPosition;
            
            // 碰撞检测：扫过即触发，但允许笔迹流继续维持
            if (rewriteZone.contains(p) && !_rewriteTriggered) {
              _rewriteTriggered = true;
              setState(() => _activeZone = 1);
              HapticFeedback.lightImpact();
              
              _pendingRewardTask?.cancel();
              _pendingRewardTask = Timer(const Duration(milliseconds: 250), () {
                if (mounted) {
                  _controller.clear(); 
                  widget.onRewrite();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) setState(() => _activeZone = 0);
                  });
                }
              });
            }
            if (recognizeZone.contains(p) && !_recognizeTriggered) {
              _recognizeTriggered = true;
              setState(() => _activeZone = 2);
              HapticFeedback.lightImpact();
              
              _pendingRecognizeTask?.cancel();
              _pendingRecognizeTask = Timer(const Duration(milliseconds: 250), () {
                if (mounted) {
                  widget.onRecognize();
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (mounted) setState(() => _activeZone = 0);
                  });
                }
              });
            }

            _controller.move(p, event.localDelta);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) return;

            final p = event.localPosition;
            
            // 先检查是否有全屏/回退手势
            final swipeStatus = _controller._detectSwipe(_controller.rawLines.last);
            if (swipeStatus != 0) {
              // 如果是手势，取消所有感应区的任务
              _pendingRewardTask?.cancel();
              _pendingRecognizeTask?.cancel();
              setState(() => _activeZone = 0);
              // 标记为已触发，防止下方点击检测再次触发
              _rewriteTriggered = true; 
              _recognizeTriggered = true;
            }

            // 点击检测：如果还没因为划过而触发，且抬起位置在感应区内，则视为点击触发
            if (!_rewriteTriggered && rewriteZone.contains(p)) {
              _rewriteTriggered = true;
              setState(() => _activeZone = 1);
              HapticFeedback.lightImpact();
              _pendingRewardTask?.cancel();
              _pendingRewardTask = Timer(const Duration(milliseconds: 250), () {
                if (mounted) {
                  _controller.clear();
                  widget.onRewrite();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) setState(() => _activeZone = 0);
                  });
                }
              });
            } else if (!_recognizeTriggered && recognizeZone.contains(p)) {
              _recognizeTriggered = true;
              setState(() => _activeZone = 2);
              HapticFeedback.lightImpact();
              _pendingRecognizeTask?.cancel();
              _pendingRecognizeTask = Timer(const Duration(milliseconds: 250), () {
                if (mounted) {
                  widget.onRecognize();
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (mounted) setState(() => _activeZone = 0);
                  });
                }
              });
            }

            _activePointerId = null;
            _controller.end();
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) return;
            _activePointerId = null;
            _controller.end();
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
                        '划过重写', 
                        style: TextStyle(
                          color: _activeZone == 1 ? Colors.grey : Colors.grey.withValues(alpha: 0.4), 
                          fontSize: 11,
                          fontWeight: _activeZone == 1 ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: recognizeZone.left,
                top: recognizeZone.top,
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
                        Icons.check_circle_outline, 
                        color: _activeZone == 2 ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.4), 
                        size: 22
                      ),
                      Text(
                        '划过识别', 
                        style: TextStyle(
                          color: _activeZone == 2 ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.4), 
                          fontSize: 11,
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
    rawLines.last.add(p); 
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
      
      // 智能手势识别：反向移动(从右到左)则删除一笔，正向(从左到右)大行程则全清
      final swipeStatus = _detectSwipe(rawLines.last);
      if (swipeStatus == 1) { // Left to Right
        clear();
      } else if (swipeStatus == 2) { // Right to Left
        rawLines.removeLast(); // 先把当前这根触发手势的线去掉
        removeLast(); // 再去掉前一笔也就是目标字母
      } else {
        finishedPath.addPath(activePath!, Offset.zero);
      }

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
    if (width > 120 && width > height * 2.5) {
      // 检查方向：起点在终点右侧一定距离即为反向划动
      if (stroke.first.dx - stroke.last.dx > 60) {
        return 2; // Right to Left
      } else if (stroke.last.dx - stroke.first.dx > 60) {
        return 1; // Left to Right
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
