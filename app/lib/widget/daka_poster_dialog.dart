import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import '../util/toast_util.dart';
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
  }

  @override
  void dispose() {
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

  Future<void> _sharePoster() async {
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
        text: '我在泡泡背单词连续开口朗读打卡 ${widget.data.continuousDays} 天！',
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 弹窗顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        '分享打卡成就',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 海报滑动区域
            SizedBox(
              height: 480,
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
                      child: RepaintBoundary(
                        key: _posterKeys[index],
                        child: DakaPosterWidget(
                          data: widget.data,
                          themeType: themeType,
                          width: 270,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

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
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isSelected ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Text(
              PosterThemeConfig.getConfig(themes[_currentIndex]).name,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 16),

            // 底部操作按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : _sharePoster,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share, size: 18),
                  label: Text(
                    _isExporting ? '正在生成海报...' : '立即分享海报',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
