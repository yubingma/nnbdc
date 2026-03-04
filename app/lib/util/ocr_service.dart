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
}
