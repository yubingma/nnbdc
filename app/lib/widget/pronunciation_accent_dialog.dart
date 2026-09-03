import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../util/prefs.dart';

/// 发音口音选择弹框：提供美音与英音切换，展示专属国旗图标与描述。
class PronunciationAccentDialog extends StatefulWidget {
  const PronunciationAccentDialog({super.key});

  /// 弹出对话框，返回选中的口音代号 ('us' 或 'uk')，若未切换或取消则返回 null
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const PronunciationAccentDialog(),
    );
  }

  @override
  State<PronunciationAccentDialog> createState() =>
      _PronunciationAccentDialogState();
}

class _PronunciationAccentDialogState extends State<PronunciationAccentDialog> {
  late String _currentAccent;

  @override
  void initState() {
    super.initState();
    _currentAccent = Prefs.pronunciationAccent;
  }

  Future<void> _selectAccent(String accent) async {
    if (_currentAccent != accent) {
      setState(() {
        _currentAccent = accent;
      });
      await Prefs.setPronunciationAccent(accent);
      if (mounted) {
        Navigator.pop(context, accent);
      }
    } else {
      Navigator.pop(context, accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<DarkMode>().isDarkMode;
    final primaryColor = Global.highlight;
    final textColor = context.textPrimary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, color: primaryColor, size: 22),
            const SizedBox(width: 10),
            Text(
              '发音口音',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.9, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildOptionCard(
              context: context,
              accentKey: 'us',
              title: '美音',
              subtitle: 'American English',
              isUk: false,
              isSelected: _currentAccent == 'us',
              onTap: () => _selectAccent('us'),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              context: context,
              accentKey: 'uk',
              title: '英音',
              subtitle: 'British English',
              isUk: true,
              isSelected: _currentAccent == 'uk',
              onTap: () => _selectAccent('uk'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String accentKey,
    required String title,
    required String subtitle,
    required bool isUk,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = context.watch<DarkMode>().isDarkMode;
    final primaryColor = Global.highlight;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.2 : 0.08)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8FAF9)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: isDark ? 0.25 : 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // 自绘国旗圆形徽章
            _AccentFlagBadge(isUk: isUk),
            const SizedBox(width: 14),
            // 文字说明
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      if (accentKey == 'us') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ],
              ),
            ),
            // 选中对勾状态
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white38 : const Color(0xFFCBD5E1)),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 自绘精美微型国旗徽标（直径 34）
class _AccentFlagBadge extends StatelessWidget {
  final bool isUk;

  const _AccentFlagBadge({required this.isUk});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipOval(
        child: CustomPaint(
          size: const Size(36, 36),
          painter: isUk ? _UkFlagPainter() : _UsFlagPainter(),
        ),
      ),
    );
  }
}

/// 美式国旗绘制器（Stars & Stripes 风格）
class _UsFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const int stripeCount = 7;
    final double stripeHeight = size.height / stripeCount;
    final Paint redPaint = Paint()..color = const Color(0xFFB22234);
    final Paint whitePaint = Paint()..color = Colors.white;

    // 绘制红白相间条纹
    for (int i = 0; i < stripeCount; i++) {
      final rect = Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight);
      canvas.drawRect(rect, i % 2 == 0 ? redPaint : whitePaint);
    }

    // 绘制左上角深蓝区域
    final double cantonWidth = size.width * 0.52;
    final double cantonHeight = stripeHeight * 4;
    final Paint bluePaint = Paint()..color = const Color(0xFF1E3A8A);
    final cantonRect = Rect.fromLTWH(0, 0, cantonWidth, cantonHeight);
    canvas.drawRect(cantonRect, bluePaint);

    // 绘制深蓝区域中的微型星芒点
    final Paint starPaint = Paint()..color = Colors.white;
    const double radius = 1.3;
    final List<Offset> starPoints = [
      Offset(cantonWidth * 0.25, cantonHeight * 0.3),
      Offset(cantonWidth * 0.72, cantonHeight * 0.3),
      Offset(cantonWidth * 0.48, cantonHeight * 0.52),
      Offset(cantonWidth * 0.25, cantonHeight * 0.75),
      Offset(cantonWidth * 0.72, cantonHeight * 0.75),
    ];
    for (final point in starPoints) {
      canvas.drawCircle(point, radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 英式国旗绘制器（Union Jack 风格）
class _UkFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. 深蓝底色
    final Paint bluePaint = Paint()..color = const Color(0xFF00247D);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bluePaint);

    // 2. 白色粗对角斜十字
    final Paint whiteDiagPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), whiteDiagPaint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), whiteDiagPaint);

    // 3. 红色细对角斜十字
    final Paint redDiagPaint = Paint()
      ..color = const Color(0xFFCF142B)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), redDiagPaint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), redDiagPaint);

    // 4. 白色粗正十字
    final Paint whiteCrossPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8;
    final double midX = size.width / 2;
    final double midY = size.height / 2;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), whiteCrossPaint);
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), whiteCrossPaint);

    // 5. 红色居中正十字 (圣乔治十字)
    final Paint redCrossPaint = Paint()
      ..color = const Color(0xFFCF142B)
      ..strokeWidth = 4.5;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), redCrossPaint);
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), redCrossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
