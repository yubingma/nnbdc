import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/config.dart';

/// 意见建议 / 客服会话里，消息正文与随消息一起发上来的截图。
///
/// 图片是**跟着某一条消息**走的：客户端先调 uploadImg.do 把图传上去，拿到形如
/// `advice/u_xxx_1699999999999.jpg` 的路径，再把这些路径以
/// `换行 + 【报错图片】 + JSON数组` 的形式追加在正文末尾。单词报错用的是同一种写法。
///
/// 解析只留这一份。以前管理端在两个地方各写了一遍同样的解析，改一处漏一处就出线上问题。
class AdviceContent {
  /// 正文里标记图片名列表的分隔标记，必须与服务端 MsgBo.IMAGE_FILES_MARKER 保持一致
  static const String imageMarker = '【报错图片】';

  /// 只发截图、一个字都没打时用的占位正文（服务端不允许空内容）
  static const String screenshotOnlyText = '【截图】';

  /// 取出消息里的图片路径列表；没有图片时返回空列表
  static List<String> imageFiles(String content) {
    final idx = content.indexOf(imageMarker);
    if (idx == -1) return const [];

    final jsonPart = content.substring(idx + imageMarker.length).trim();
    try {
      final parsed = jsonDecode(jsonPart);
      if (parsed is List) {
        return parsed.whereType<String>().where((e) => e.isNotEmpty).toList();
      }
    } on FormatException {
      // 标记后不是合法 JSON：当作没有图片，正文里会保留原始文字，不静默吞掉整条消息
    }
    return const [];
  }

  /// 剥掉图片标记，只留下用户真正说的话
  static String text(String content) {
    final idx = content.indexOf(imageMarker);
    if (idx == -1) return content;
    return content.substring(0, idx).trim();
  }

  /// 拼出可以直接访问的图片地址
  static String imageUrl(String imageFile) {
    // 新数据带目录（如 advice/xxx.jpg）；历史数据只有文件名，存在 word 目录下
    final path = imageFile.contains('/') ? imageFile : 'word/$imageFile';
    return '${Config.imgBaseUrl}$path';
  }

  /// 会话列表里的一行预览：有图就给个「[图片]」，正文压成一行并截断
  static String preview(String content, {int maxLength = 40}) {
    final text = AdviceContent.text(content).replaceAll(RegExp(r'\s+'), ' ').trim();
    final hasImage = imageFiles(content).isNotEmpty;

    if (text.isEmpty) {
      return hasImage ? '[图片]' : '';
    }
    final clipped = text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
    return hasImage ? '[图片] $clipped' : clipped;
  }
}

/// 一条准备发出去的截图：本地预览用字节，上传成功后拿到服务端路径
class AdviceImageAttachment {
  final Uint8List bytes;
  final String name;

  /// 上传成功后由 uploadImg.do 返回的路径（形如 advice/u_xxx_时间戳.jpg）；为空表示还没传上去
  String? uploadedPath;

  AdviceImageAttachment(this.bytes, this.name, {this.uploadedPath});
}

/// 客服会话里选图、压缩、上传截图。
///
/// 上传走现成的 uploadImg.do，只是把长边上限设为 1080（等比缩放，不再压成正方形）
/// 并且落进 advice 目录。用户端与管理端共用这一份，避免两处各写一套。
class AdviceImages {
  /// 一次最多能带几张截图
  static const int maxCount = 3;

  /// 上传前把长边压到这个值以内
  static const int maxEdge = 1080;

  /// 服务端 uploadImg.do 的硬限制是 1MB，超过会被直接拒绝
  static const int maxUploadBytes = 1024 * 1024;

  /// 弹一个「拍照 / 从相册选择」的选择框，用户取消时返回 null
  static Future<ImageSource?> pickSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 顺次选图并上传，返回所有成功的附件。用户没选图时返回空列表。
  ///
  /// [baseline] 是已经选好的截图（用于追加）。任何一张上传失败都会抛出异常，
  /// 由调用方把失败原因显示出来——不允许静默少一张。
  static Future<List<AdviceImageAttachment>> pickAndUpload({
    required BuildContext context,
    required String userId,
    required ImageSource source,
    List<AdviceImageAttachment> baseline = const [],
  }) async {
    final remaining = maxCount - baseline.length;
    if (remaining <= 0) {
      throw Exception('最多只能发 $maxCount 张截图');
    }

    final attachments = <AdviceImageAttachment>[];
    if (source == ImageSource.camera) {
      final file = await _pickFromCamera(remaining);
      if (file != null) {
        attachments.add(AdviceImageAttachment(await _compress(await file.readAsBytes()), file.name));
      }
    } else {
      attachments.addAll(await _pickFromGallery(remaining));
    }

    if (attachments.isEmpty) {
      return const [];
    }

    for (final attachment in attachments) {
      if (attachment.bytes.length > maxUploadBytes) {
        throw Exception('图片「${attachment.name}」压缩后仍然超过 1MB，请换一张');
      }
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(attachment.bytes, filename: attachment.name),
        'userId': userId,
      });
      final result = await Api.client.uploadImg(formData, maxEdge, 'advice');

      if (result.success && result.data != null) {
        attachment.uploadedPath = result.data!;
      } else {
        throw Exception(result.msg ?? '图片上传失败');
      }
    }
    return attachments;
  }

  static Future<XFile?> _pickFromCamera(int limit) async {
    if (limit <= 0) return null;
    return ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 90,
    );
  }

  static Future<List<AdviceImageAttachment>> _pickFromGallery(int limit) async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 90,
      limit: limit,
    );
    if (files.isEmpty) {
      return const [];
    }

    final attachments = <AdviceImageAttachment>[];
    for (final file in files.take(limit)) {
      attachments.add(AdviceImageAttachment(await _compress(await file.readAsBytes()), file.name));
    }
    return attachments;
  }

  /// 把截图等比压到长边 [maxEdge] 以内并转成 PNG。
  /// 截图里全是文字与纯色，PNG 压出来通常只有几百 KB，比 JPEG 清楚得多。
  static Future<Uint8List> _compress(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int longEdge = image.width > image.height ? image.width : image.height;
    final double factor = longEdge > maxEdge ? maxEdge / longEdge : 1.0;
    final int targetWidth = (image.width * factor).round();
    final int targetHeight = (image.height * factor).round();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final ui.Image resized = await recorder.endRecording().toImage(targetWidth, targetHeight);
    final ByteData? data = await resized.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw Exception('图片压缩失败，请换一张截图');
    }
    return data.buffer.asUint8List();
  }
}
