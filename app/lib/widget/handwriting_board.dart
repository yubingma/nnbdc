import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

          // 画布区域
          Expanded(
            child: _HandwritingCanvas(
              lines: _lines,
              isRecognizing: _isRecognizing,
            ),
          ),

          // 底部操作栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _isRecognizing ? null : _clear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('重写'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isRecognizing ? null : _recognize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: const Text('识别'),
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

  const _HandwritingCanvas({required this.lines, required this.isRecognizing});

  @override
  State<_HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<_HandwritingCanvas> {
  late final _HandwritingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _HandwritingController(widget.lines);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (widget.isRecognizing) return;
        _controller.start(event.localPosition);
      },
      onPointerMove: (event) {
        if (widget.isRecognizing) return;
        // 采用增量式平滑与预测绘制合并方案，实现全平台统一的高流畅书写
        _controller.move(event.localPosition, event.localDelta);
      },
      onPointerUp: (event) {
        _controller.end();
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HandwritingPainter(_controller),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _HandwritingController extends ChangeNotifier {
  final List<List<Offset>> rawLines;
  Path finishedPath = Path();
  Path? activePath;
  Offset? lastPoint;
  Offset? midPoint;

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
    lastPoint = p;
    midPoint = p;
    notifyListeners();
  }

  void move(Offset p, Offset delta) {
    if (activePath == null || lastPoint == null) return;

    // 极致原生化：移除所有平滑滤波器
    // 虽然平滑会让线条更圆润，但也不可避免地会引入 1-2 帧的物理相位延迟。
    // 为了对抗原生手写的敏锐感，我们牺牲微小的圆润度，追求绝对的响应速度。
    if ((p - lastPoint!).distanceSquared < 0.25) return;

    // 极致预测：使用 1.0 帧的完整位移预测
    // 将视觉落点完全推移到触控点的物理预测位置。
    final predictedPoint = p + delta * 1.0;
    rawLines.last.add(p); 

    // 增量构建
    final newMidPoint =
        Offset((lastPoint!.dx + predictedPoint.dx) / 2.0, (lastPoint!.dy + predictedPoint.dy) / 2.0);
    activePath!.quadraticBezierTo(
        lastPoint!.dx, lastPoint!.dy, newMidPoint.dx, newMidPoint.dy);

    midPoint = newMidPoint;
    lastPoint = predictedPoint;
    notifyListeners();
  }

  void end() {
    if (activePath != null && lastPoint != null) {
      activePath!.lineTo(lastPoint!.dx, lastPoint!.dy);
      finishedPath.addPath(activePath!, Offset.zero);
      activePath = null;
      lastPoint = null;
      midPoint = null;
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
    // 极致平滑绘制：移除复杂的 MaskFilter 模糊，改用纯净的高性能路径渲染，大幅降低 GPU 耗时
    canvas.drawPath(controller.finishedPath, _linePaint);

    if (controller.activePath != null &&
        controller.lastPoint != null &&
        controller.midPoint != null) {
      canvas.drawPath(controller.activePath!, _linePaint);
      // 笔尖补齐
      canvas.drawLine(controller.midPoint!, controller.lastPoint!, _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) => true;
}
