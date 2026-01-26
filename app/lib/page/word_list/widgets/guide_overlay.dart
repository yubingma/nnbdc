import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../state.dart';
import '../../../util/platform_util.dart';

class GuideOverlay extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onDismissForever;
  final Rect? menuRect;
  final GlobalKey overlayKey;

  const GuideOverlay({
    super.key,
    this.onClose,
    this.onDismissForever,
    this.menuRect,
    required this.overlayKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final safePadding = MediaQuery.of(context).padding;

    final double defaultTop = safePadding.top + kToolbarHeight + 8;
    final double columnTop = menuRect != null ? menuRect!.center.dy + 12 : defaultTop;
    const double arrowHeight = 30.0;

    return GestureDetector(
      onTap: onClose,
      child: Container(
        key: overlayKey,
        color: Colors.black.withValues(alpha: 0.7),
        child: Stack(
          children: [
            Positioned(
              top: columnTop,
              left: menuRect != null ? menuRect!.center.dx - 1.5 : null,
              right: menuRect == null ? 24.0 : null,
              child: CustomPaint(
                size: const Size(3, arrowHeight),
                painter: _ArrowPainter(isDarkMode),
              ),
            ),
            Positioned(
              top: columnTop + arrowHeight + 2,
              right: 16.0,
              child: GestureDetector(
                onTap: () {}, // Prevent event bubbling
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.gradientStartColor,
                        AppTheme.gradientEndColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 12),
                      const Text(
                        '这里有一些有趣的功能，你可以试试看:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildMenuItem(Icons.list_alt, '词表浏览'),
                      _buildMenuItem(Icons.headphones, '随身听'),
                      if (PlatformUtils.isAsrSupported()) _buildMenuItem(Icons.record_voice_over, '背中文'),
                      if (PlatformUtils.isEnglishAsrSupported()) _buildMenuItem(Icons.record_voice_over, '背英文'),
                      _buildMenuItem(Icons.edit, '默写'),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onDismissForever,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            '不再显示',
                            style: TextStyle(
                              fontSize: 14,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.lightbulb,
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(width: 8),
        const Text(
          '新手提示',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final bool isDarkMode;

  _ArrowPainter(this.isDarkMode);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width / 2, size.height),
      Offset(size.width / 2, 0),
      paint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2 - 8, 10),
      paint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2 + 8, 10),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
