import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluwx/fluwx.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/vo.dart';
import '../config.dart';
import '../global.dart';
import '../util/toast_util.dart';
import '../util/wechat_util.dart';
import 'badge_svg_assets.dart';

/// 荣耀勋章分享海报弹窗
class BadgePosterDialog extends StatefulWidget {
  final UserBadgeVo userBadge;

  const BadgePosterDialog({
    super.key,
    required this.userBadge,
  });

  static Future<void> show(BuildContext context, {required UserBadgeVo userBadge}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (ctx) => BadgePosterDialog(userBadge: userBadge),
    );
  }

  @override
  State<BadgePosterDialog> createState() => _BadgePosterDialogState();
}

class _BadgePosterDialogState extends State<BadgePosterDialog> {
  final GlobalKey _posterKey = GlobalKey();
  bool _isExporting = false;
  FluwxCancelable? _weChatShareCancelable;

  @override
  void initState() {
    super.initState();
    _weChatShareCancelable = WechatUtil.addSubscriber((response) {
      if (!mounted) return;
      if (response is WeChatShareResponse) {
        if (response.errCode == 0) {
          ToastUtil.success('🎉 勋章海报分享成功！');
          Navigator.of(context).pop();
        } else if (response.errCode == -2) {
          // 取消分享
        } else {
          ToastUtil.error('分享未完成: ${response.errStr ?? "未知错误"}');
        }
      }
    });
  }

  @override
  void dispose() {
    _weChatShareCancelable?.cancel();
    super.dispose();
  }

  Future<String?> _capturePosterToTempFile() async {
    try {
      final boundary = _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/badge_poster_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      return file.path;
    } catch (e) {
      Global.logger.e('生成勋章海报图片失败: $e');
      return null;
    }
  }

  Future<void> _shareToWeChat(WeChatScene scene) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final imagePath = await _capturePosterToTempFile();
      if (imagePath == null) {
        ToastUtil.error('生成海报失败，请重试');
        return;
      }

      await WechatUtil.shareImage(
        imageFile: File(imagePath),
        scene: scene,
      );
    } catch (e) {
      ToastUtil.error('微信分享失败: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveToGallery() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final imagePath = await _capturePosterToTempFile();
      if (imagePath == null) {
        ToastUtil.error('生成海报失败，请重试');
        return;
      }

      // 桌面端 (macOS / Windows / Linux)：直接保存到 Downloads 文件夹
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final badgeName = widget.userBadge.badge?.name ?? 'medal';
        final fileName = 'bubble_badge_${badgeName}_${DateTime.now().millisecondsSinceEpoch}.png';
        final targetPath = '${downloadsDir.path}/$fileName';
        await File(imagePath).copy(targetPath);
        ToastUtil.success('✅ 已保存至「下载」文件夹: $fileName');
        return;
      }

      // 移动端 (iOS / Android)：保存至手机系统相册
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          ToastUtil.error('未获得相册权限，请在系统设置中允许');
          return;
        }
      }

      await Gal.putImage(imagePath);
      ToastUtil.success('✅ 荣誉海报已保存至相册！');
    } catch (e) {
      Global.logger.e('保存勋章海报失败: $e');
      ToastUtil.error('保存失败: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareToSystem() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final imagePath = await _capturePosterToTempFile();
      if (imagePath == null) return;

      await Share.shareXFiles(
        [XFile(imagePath)],
        text: '我在「泡泡单词」点亮了【${widget.userBadge.badge?.name}】勋章！',
      );
    } catch (e) {
      Global.logger.w('系统分享异常: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vo = widget.userBadge;
    final badge = vo.badge;
    final code = vo.badgeCode ?? badge?.code ?? 'STREAK_3';
    final name = badge?.name ?? '荣耀勋章';
    final tier = badge?.tier ?? 'BRONZE';
    final tierName = BadgeSvgAssets.getTierName(tier);
    final categoryName = BadgeSvgAssets.getCategoryName(badge?.category);
    final user = Global.getLoggedInUser();
    final userName = user?.nickName ?? user?.userName ?? '自律学伴';
    final now = DateTime.now();
    final dateStr = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部关闭
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 海报主卡片（RepaintBoundary 用于高清截屏）
          RepaintBoundary(
            key: _posterKey,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF0F172A), Color(0xFF020617)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF818CF8).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头部：用户信息与自律标识
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4F46E5),
                          border: Border.all(color: Colors.white30, width: 1.2),
                        ),
                        child: const Center(
                          child: Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              '在泡泡单词达成荣耀里程碑',
                              style: TextStyle(
                                color: Color(0xFFA5B4FC),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 核心视觉：高光立体大勋章
                  Center(
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: BadgeSvgAssets.getTierColor(tier).withValues(alpha: 0.35),
                            blurRadius: 35,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: BadgeSvgAssets.renderBadge(
                          code: code,
                          size: 120,
                          isUnlocked: true,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 勋章名称
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 品质与类别标签
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BadgeSvgAssets.getTierColor(tier).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: BadgeSvgAssets.getTierColor(tier).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '$tierName · $categoryName',
                      style: TextStyle(
                        color: BadgeSvgAssets.getTierColor(tier),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 寄语描述
                  Text(
                    badge?.description ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 14),

                  // 底部：品牌与二维码
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Text(
                                '泡泡单词',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text('✨', style: TextStyle(fontSize: 10)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '坚持背词，见证每日成长',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: QrImageView(
                          data: Config.appDownloadUrl.isNotEmpty ? Config.appDownloadUrl : 'https://www.nnbdc.com',
                          version: QrVersions.auto,
                          size: 38.0,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 底部分享操作按钮栏
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShareActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                label: '微信好友',
                color: const Color(0xFF07C160),
                onTap: () => _shareToWeChat(WeChatScene.session),
              ),
              const SizedBox(width: 16),
              _buildShareActionBtn(
                icon: Icons.camera_rounded,
                label: '朋友圈',
                color: const Color(0xFF10B981),
                onTap: () => _shareToWeChat(WeChatScene.timeline),
              ),
              const SizedBox(width: 16),
              _buildShareActionBtn(
                icon: Icons.download_rounded,
                label: (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ? '存电脑' : '存相册',
                color: const Color(0xFF6366F1),
                onTap: _saveToGallery,
              ),
              const SizedBox(width: 16),
              _buildShareActionBtn(
                icon: Icons.share_rounded,
                label: '更多',
                color: const Color(0xFF64748B),
                onTap: _shareToSystem,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isExporting ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.2),
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
