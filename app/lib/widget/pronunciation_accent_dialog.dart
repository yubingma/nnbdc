import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme/app_theme.dart';
import '../util/prefs.dart';

/// 发音口音选择弹框：提供美音与英音切换，展示专属国旗图标与描述。
/// 遵循全局现代极简美学与高斯模糊毛玻璃规范（flutter-frosted-glass）。
class PronunciationAccentDialog extends StatefulWidget {
  const PronunciationAccentDialog({super.key});

  /// 弹出对话框，返回选中的口音代号 ('us' 或 'uk')，若未切换或取消则返回 null
  static Future<String?> show(BuildContext context) {
    final isDark = context.read<DarkMode>().isDarkMode;
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_pronunciation_accent',
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return const PronunciationAccentDialog();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
    );
  }

  @override
  State<PronunciationAccentDialog> createState() => _PronunciationAccentDialogState();
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
    final darkMode = context.watch<DarkMode>();
    final selectedStyle = darkMode.themeStyle;
    final themeConfig = AppThemeConfig.of(selectedStyle);
    final isDark = selectedStyle.isDark || darkMode.isDarkMode;

    final primaryColor = themeConfig.primaryColor;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xB8161B26),
                          const Color(0x9910141D),
                        ]
                      : [
                          const Color(0x66FFFFFF),
                          const Color(0x4DFFFFFF),
                        ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 顶部标题与轻量关闭按钮
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.20),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: primaryColor,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '发音口音',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: textColor,
                                fontFamily: 'NotoSansSC',
                                fontFamilyFallback: AppTheme.sansSerifFallback,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '选择单词播放时的标准发音风格',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: subtitleColor.withValues(alpha: 0.75),
                                fontFamily: 'NotoSansSC',
                                fontFamilyFallback: AppTheme.sansSerifFallback,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.45),
                            border: Border.all(
                              color: isDark ? Colors.white12 : const Color(0x66FFFFFF),
                              width: 0.8,
                            ),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: subtitleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 2. 美音与英音选项卡片
                  _buildOptionCard(
                    context: context,
                    accentKey: 'us',
                    title: '美音',
                    subtitle: 'American English (标准美式发音)',
                    isUk: false,
                    isSelected: _currentAccent == 'us',
                    primaryColor: primaryColor,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                    isDark: isDark,
                    onTap: () => _selectAccent('us'),
                  ),
                  const SizedBox(height: 10),
                  _buildOptionCard(
                    context: context,
                    accentKey: 'uk',
                    title: '英音',
                    subtitle: 'British English (标准英式发音)',
                    isUk: true,
                    isSelected: _currentAccent == 'uk',
                    primaryColor: primaryColor,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                    isDark: isDark,
                    onTap: () => _selectAccent('uk'),
                  ),
                  const SizedBox(height: 18),

                  // 3. 底部操作按钮
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor.withValues(alpha: isDark ? 0.25 : 0.15),
                        foregroundColor: primaryColor,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.center,
                        side: BorderSide(
                          color: primaryColor.withValues(alpha: isDark ? 0.40 : 0.25),
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(21),
                        ),
                      ),
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                          letterSpacing: 0.3,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                          fontFamily: 'NotoSansSC',
                          fontFamilyFallback: AppTheme.sansSerifFallback,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    required Color primaryColor,
    required Color textColor,
    required Color subtitleColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.24 : 0.14)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0x80FFFFFF)),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? primaryColor : textColor,
                          fontFamily: 'NotoSansSC',
                          fontFamilyFallback: AppTheme.sansSerifFallback,
                        ),
                      ),
                      if (accentKey == 'us') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
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
                      fontSize: 11.5,
                      color: subtitleColor.withValues(alpha: 0.75),
                      fontFamily: 'NotoSansSC',
                      fontFamilyFallback: AppTheme.sansSerifFallback,
                    ),
                  ),
                ],
              ),
            ),
            // 选中对勾状态
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
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

/// 自绘精美微型国旗徽标（直径 36）
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
          color: Colors.white.withValues(alpha: 0.4),
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
