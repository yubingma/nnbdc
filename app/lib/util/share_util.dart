import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// 分享工具类
/// 封装 share_plus 的调用，统一处理 iOS / iPadOS 上 UIPopoverPresentationController
/// 所必需的 sharePositionOrigin 参数，彻底避免系统抛出:
/// "sharePositionOrigin: argument must be set, {{0, 0}, {0, 0}} must be non-zero and within coordinate space of source view" 异常。
class ShareUtil {
  ShareUtil._();

  /// 获取适合 iOS/iPadOS 原生分享弹窗定位的 Rect
  static Rect resolvePositionOrigin(BuildContext? context) {
    if (context != null && context.mounted) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
        final origin = box.localToGlobal(Offset.zero);
        final mediaQuery = MediaQuery.maybeOf(context);
        final screenWidth = mediaQuery?.size.width ?? 0;
        final isNearFullScreen = screenWidth > 0 && box.size.width >= screenWidth * 0.9;
        if (!isNearFullScreen) {
          return origin & box.size;
        } else {
          return Rect.fromCenter(
            center: origin + Offset(box.size.width / 2, box.size.height / 2),
            width: 10,
            height: 10,
          );
        }
      }
    }

    // 兜底：从全局 FlutterView 中获取屏幕尺寸，构造屏幕中心小矩形
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null && view.devicePixelRatio > 0) {
      final width = view.physicalSize.width / view.devicePixelRatio;
      final height = view.physicalSize.height / view.devicePixelRatio;
      if (width > 0 && height > 0) {
        return Rect.fromCenter(
          center: Offset(width / 2, height / 2),
          width: 10,
          height: 10,
        );
      }
    }

    // 终极保护：在极端情况下返回合理非零 Rect
    return const Rect.fromLTWH(0, 0, 100, 100);
  }

  /// 安全分享文件，自动注入合法 sharePositionOrigin
  static Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? text,
    String? subject,
    BuildContext? context,
    Rect? sharePositionOrigin,
  }) async {
    final origin = sharePositionOrigin ?? resolvePositionOrigin(context);
    return Share.shareXFiles(
      files,
      text: text,
      subject: subject,
      sharePositionOrigin: origin,
    );
  }
}
