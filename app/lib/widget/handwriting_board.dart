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

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
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

      // 提取有效的英文单词（去除空格等）
      String result = text.replaceAll(RegExp(r'[^a-zA-Z]'), '').trim();
      
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
    // 寻找内容的边界，以便进行居中和缩放
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    if (_lines.isEmpty) return;

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
    
    // 如果内容太小，不进行大幅度缩放以免失真
    if (contentWidth < 10) contentWidth = 10;
    if (contentHeight < 10) contentHeight = 10;

    double scaleX = (width - 2 * margin) / contentWidth;
    double scaleY = (height - 2 * margin) / contentHeight;
    double scale = scaleX < scaleY ? scaleX : scaleY;
    if (scale > 2.0) scale = 2.0; // 避免过度放大噪音

    canvas.save();
    // 移动到中央并缩放
    canvas.translate(
      (width - contentWidth * scale) / 2 - minX * scale,
      (height - contentHeight * scale) / 2 - minY * scale,
    );
    canvas.scale(scale);

    for (var line in _lines) {
      for (int i = 0; i < line.length - 1; i++) {
        canvas.drawLine(line[i], line[i + 1], paint);
      }
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
                GestureDetector(
                  onTap: widget.onCancel,
                  child: const Icon(Icons.close, size: 20, color: Colors.grey),
                ),
              ],
            ),
          ),
          
          // 画布区域
          Expanded(
            child: GestureDetector(
              onPanStart: (details) {
                if (_isRecognizing) return;
                setState(() {
                  _lines.add([details.localPosition]);
                });
              },
              onPanUpdate: (details) {
                if (_isRecognizing) return;
                setState(() {
                  _lines.last.add(details.localPosition);
                });
              },
              child: CustomPaint(
                painter: _HandwritingPainter(_lines),
                size: Size.infinite,
                child: Container(),
              ),
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

class _HandwritingPainter extends CustomPainter {
  final List<List<Offset>> lines;

  _HandwritingPainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (var line in lines) {
      for (int i = 0; i < line.length - 1; i++) {
        canvas.drawLine(line[i], line[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
