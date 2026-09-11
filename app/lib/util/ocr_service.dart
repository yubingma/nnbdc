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
  /// [language] ML Kit 数字墨迹语言标签（默认英文 en-US；中文手写传 'zh-Hani'）
  /// [writingAreaWidth]/[writingAreaHeight] 手写区尺寸（与 stroke 坐标同单位）。
  /// 传入可帮助 ML Kit 正确切分多字连写（如连续写多个汉字时避免被合成一个字）。
  /// [preContext] 书写位置之前的已有文本（已定稿的前缀），帮助 ML Kit 判断词边界与前导空格。
  /// 无前缀时传空串：ML Kit 内部把它当 C 字符串读取，传 nil 会在 strlen 处崩溃。
  static Future<String> recognizeHandwriting(List<List<Map<String, dynamic>>> strokes,
      {String language = 'en-US',
      double? writingAreaWidth,
      double? writingAreaHeight,
      String preContext = ''}) async {
    try {
      final result = await _channel.invokeMethod<String>('recognizeHandwriting', {
        'strokes': strokes,
        'language': language,
        'writingAreaWidth': writingAreaWidth,
        'writingAreaHeight': writingAreaHeight,
        'preContext': preContext,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('手写识别失败: ${e.message}');
    }
  }

  /// 提前下载/准备手写识别模型 (Digital Ink Recognition Model)
  /// [language] ML Kit 数字墨迹语言标签（默认英文 en-US；中文手写传 'zh-Hani'）
  static Future<void> prepareModel({String language = 'en-US'}) async {
    try {
      await _channel.invokeMethod<void>('prepareModel', {
        'language': language,
      });
    } on PlatformException catch (e) {
      // 仅仅是静默下载，出错无需影响主业务流程，只打印日志即可
      debugPrint('准备手写识别模型失败: ${e.message}');
    }
  }
}

