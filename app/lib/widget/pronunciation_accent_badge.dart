import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../util/prefs.dart';

/// 发音口音小按钮（'英' / '美'）
/// 点击可快速在英音与美音之间切换，并弹出提示。
/// 效果等同于通过英音美音切换对话框进行切换。
class PronunciationAccentBadge extends StatefulWidget {
  /// 显示的口音文字，例如 '英' 或 '美'
  final String label;

  /// 是否发生了口音降级（例如用户偏好英音，但当前词无英音而降级为美音）
  final bool isFallback;

  /// 自定义强调色（未指定则取主题 primaryColor）
  final Color? color;

  /// 点击切换成功后的回调，入参为切换后的新口音代号 ('us' / 'uk')
  final Future<void> Function(String newAccent)? onSwitched;

  /// 字体大小，默认 10.5
  final double fontSize;

  /// 外边距，默认 EdgeInsets.only(right: 5)
  final EdgeInsetsGeometry margin;

  const PronunciationAccentBadge({
    super.key,
    required this.label,
    this.isFallback = false,
    this.color,
    this.onSwitched,
    this.fontSize = 10.5,
    this.margin = const EdgeInsets.only(right: 5),
  });

  @override
  State<PronunciationAccentBadge> createState() => _PronunciationAccentBadgeState();
}

class _PronunciationAccentBadgeState extends State<PronunciationAccentBadge> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return const SizedBox.shrink();

    Color themeColor;
    bool isDark;
    try {
      themeColor = widget.color ?? context.primaryColor;
      isDark = context.isDarkMode;
    } catch (_) {
      themeColor = widget.color ?? Theme.of(context).primaryColor;
      isDark = Theme.of(context).brightness == Brightness.dark;
    }

    final bgColor = widget.isFallback
        ? Colors.orange.withValues(alpha: isDark ? 0.25 : 0.15)
        : themeColor.withValues(alpha: isDark ? 0.22 : 0.12);

    final textColor = widget.isFallback
        ? (isDark ? Colors.orange[300]! : Colors.orange[800]!)
        : themeColor;

    return Padding(
      padding: widget.margin,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () async {
          final newAccent = await Prefs.togglePronunciationAccent();
          if (widget.onSwitched != null) {
            await widget.onSwitched!(newAccent);
          }
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: widget.isFallback
                    ? Colors.orange.withValues(alpha: isDark ? 0.4 : 0.25)
                    : themeColor.withValues(alpha: isDark ? 0.35 : 0.2),
                width: 0.6,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: textColor,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
