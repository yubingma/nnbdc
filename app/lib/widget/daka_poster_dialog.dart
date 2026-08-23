import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluwx/fluwx.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../global.dart';
import '../theme/app_theme.dart';
import '../util/toast_util.dart';
import '../util/wechat_util.dart';
import 'daka_poster.dart';

/// 打卡海报分享弹窗
class DakaPosterDialog extends StatefulWidget {
  final PosterData data;

  const DakaPosterDialog({
    super.key,
    required this.data,
  });

  static Future<void> show(BuildContext context, PosterData data) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DakaPosterDialog(data: data),
    );
  }

  @override
  State<DakaPosterDialog> createState() => _DakaPosterDialogState();
}

class _DakaPosterDialogState extends State<DakaPosterDialog> {
  final List<GlobalKey> _posterKeys = List.generate(
    PosterThemeType.values.length,
    (_) => GlobalKey(),
  );

  int _currentIndex = 0;
  late final PageController _pageController;
  bool _isExporting = false;
  FluwxCancelable? _weChatShareCancelable;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);

    // 订阅微信分享结果回调，发表成功后即时给予成功反馈
    _weChatShareCancelable = WechatUtil.addSubscriber((response) {
      if (!mounted) return;
      if (response is WeChatShareResponse) {
        if (response.errCode == 0) {
          ToastUtil.success('🎉 打卡海报分享成功！');
          Navigator.of(context).pop();
        } else if (response.errCode == -2) {
          // 用户取消分享，无需提示错误
        } else {
          ToastUtil.error('分享未完成: ${response.errStr ?? "未知错误"}');
        }
      }
    });
  }

  @override
  void dispose() {
    _weChatShareCancelable?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<String?> _capturePosterToTempFile() async {
    try {
      final key = _posterKeys[_currentIndex];
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/daka_poster_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// 一键分享到微信好友或朋友圈
  Future<void> _shareToWeChat(WeChatScene scene) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final filePath = await _capturePosterToTempFile();
    if (!mounted) return;
    setState(() => _isExporting = false);

    if (filePath == null) {
      ToastUtil.error('生成海报失败，请稍后重试');
      return;
    }

    final success = await WechatUtil.shareImage(
      imageFile: File(filePath),
      scene: scene,
    );

    if (success && mounted) {
      ToastUtil.success(scene == WeChatScene.timeline ? '已前往朋友圈发布' : '已前往微信发送');
    }
  }

  /// 直接保存海报图片到手机系统相册
  Future<void> _savePoster() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final filePath = await _capturePosterToTempFile();
    if (!mounted) return;

    if (filePath == null) {
      setState(() => _isExporting = false);
      Global.logger.e('[DakaPosterDialog] 截图导出临时图片失败: filePath is null');
      ToastUtil.error('生成海报失败');
      return;
    }

    try {
      // 1. 检查并请求相册权限
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            setState(() => _isExporting = false);
            ToastUtil.error('未获得相册权限，请在设置中开启');
          }
          return;
        }
      }

      // 2. 保存图片至系统相册
      await Gal.putImage(filePath);
      Global.logger.i('[DakaPosterDialog] 海报已成功保存至系统相册: $filePath');
      if (mounted) {
        setState(() => _isExporting = false);
        ToastUtil.success('已保存到手机相册');
      }
    } on GalException catch (e, stackTrace) {
      Global.logger.e('[DakaPosterDialog] 保存相册发生 GalException: ${e.type.message}', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isExporting = false);
        if (e.type == GalExceptionType.accessDenied) {
          ToastUtil.error('未获得相册权限，请在系统设置中允许访问相册');
        } else {
          ToastUtil.error('保存相册失败: ${e.type.message}');
        }
      }
    } catch (e, stackTrace) {
      Global.logger.e('[DakaPosterDialog] 保存相册发生未知异常', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isExporting = false);
        ToastUtil.error('保存相册失败，请重试');
      }
    }
  }

  /// 更多系统分享
  Future<void> _shareSystem() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final filePath = await _capturePosterToTempFile();
    if (!mounted) return;
    setState(() => _isExporting = false);

    if (filePath == null) {
      ToastUtil.error('生成海报失败，请稍后重试');
      return;
    }

    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: '我在泡泡单词已连续打卡 ${widget.data.continuousDays} 天！',
      );
    } catch (e) {
      ToastUtil.error('唤起分享失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themes = PosterThemeType.values;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.of(context).size.height - 32;
          
          // 准确预留头部 (40) + 指示器与文字 (28) + 底部按钮条 (76) + padding (24) = 168px
          // 留出充裕余量（210px），确保在任何超小屏幕上都绝不发生溢出
          final posterHeight = (maxH - 210).clamp(160.0, 460.0);

          return Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 弹窗顶部栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: AppTheme.primaryColor, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            '分享打卡成就',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // 海报左右滑动区域
                SizedBox(
                  height: posterHeight,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: themes.length,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final themeType = themes[index];
                      final isCurrent = index == _currentIndex;

                      return Center(
                        child: AnimatedScale(
                          scale: isCurrent ? 1.0 : 0.92,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: RepaintBoundary(
                                key: _posterKeys[index],
                                child: DakaPosterWidget(
                                  data: widget.data,
                                  themeType: themeType,
                                  width: 270,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 6),

                // 主题切换指示点与名称
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(themes.length, (index) {
                    final isSelected = index == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isSelected ? 16 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryColor : Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 3),
                Text(
                  PosterThemeConfig.getConfig(themes[_currentIndex]).name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),

                const SizedBox(height: 8),

                // 底部清爽专属分享渠道按钮条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _isExporting
                      ? Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '海报生成中...',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 微信好友
                            _buildChannelButton(
                              icon: Icons.chat_bubble_outline,
                              iconColor: const Color(0xFF07C160),
                              label: '微信好友',
                              onTap: () => _shareToWeChat(WeChatScene.session),
                            ),
                            // 微信朋友圈
                            _buildChannelButton(
                              icon: Icons.camera_outlined,
                              iconColor: const Color(0xFF07C160),
                              label: '朋友圈',
                              onTap: () => _shareToWeChat(WeChatScene.timeline),
                            ),
                            // 保存相册
                            _buildChannelButton(
                              icon: Icons.download_rounded,
                              iconColor: const Color(0xFF38BDF8),
                              label: '保存相册',
                              onTap: _savePoster,
                            ),
                            // 更多系统分享
                            _buildChannelButton(
                              icon: Icons.more_horiz,
                              iconColor: Colors.white70,
                              label: '更多',
                              onTap: _shareSystem,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChannelButton({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
