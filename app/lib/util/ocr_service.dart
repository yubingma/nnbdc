import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 调用 iOS 原生 Vision 框架进行 OCR 文字识别
class OcrService {
  static const MethodChannel _channel = MethodChannel('nnbdc/ocr');

  /// 识别图片中的文字
  /// [imagePath] 图片文件的绝对路径
  /// 返回识别到的全部文字
  static Future<String> recognizeText(String imagePath) async {
    try {
      final result = await _channel.invokeMethod<String>('recognizeText', {
        'imagePath': imagePath,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('OCR识别失败: ${e.message}');
    }
  }

  /// 识别手写轨迹中的文字 (Digital Ink Recognition)
  /// [strokes] 笔画列表，每个笔画是点的列表 [{'x': ..., 'y': ..., 't': ...}]
  static Future<String> recognizeHandwriting(List<List<Map<String, dynamic>>> strokes) async {
    try {
      final result = await _channel.invokeMethod<String>('recognizeHandwriting', {
        'strokes': strokes,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('手写识别失败: ${e.message}');
    }
  }

  /// 提前下载/准备手写识别模型 (Digital Ink Recognition Model)
  static Future<void> prepareModel() async {
    try {
      await _channel.invokeMethod<void>('prepareModel');
    } on PlatformException catch (e) {
      // 仅仅是静默下载，出错无需影响主业务流程，只打印日志即可
      debugPrint('准备手写识别模型失败: ${e.message}');
    }
  }
}

