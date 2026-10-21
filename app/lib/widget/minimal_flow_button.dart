import 'package:flutter/material.dart';

import 'app_scaffold.dart';

/// 极简流转按钮：一行文字 + 下方一条主题色指示光条，无实心底色/描边。
/// 背单词页「下一词」、阶段复习「下一组」等主流转动作共用同一套视觉，
/// 避免各处各自写实心按钮导致风格分裂。
class MinimalFlowButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? textColor;
  final Color? indicatorColor;
  final bool isEnabled;
  final double indicatorWidth;
  final double fontSize;
  final Key? tapKey;

  /// 写进无障碍树 resource-id 的稳定标识，供真机端到端测试定位；普通界面不传。
  final String? identifier;

  const MinimalFlowButton({
    super.key,
    required this.label,
    required this.onTap,
    this.textColor,
    this.indicatorColor,
    this.isEnabled = true,
    this.indicatorWidth = 20.0,
    this.fontSize = 16.0,
    this.tapKey,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final effectiveTextColor = textColor ?? context.textPrimary;
    final effectiveIndicator = indicatorColor ?? context.primaryColor;

    // 只有需要给真机自动化定位的按钮才挂语义标识；未传 identifier 时各项保持 null，
    // 语义配置为空，不会额外生成语义节点，其余按钮的无障碍表现与改动前一致。
    return Semantics(
      identifier: identifier,
      button: identifier == null ? null : true,
      enabled: identifier == null ? null : isEnabled,
      child: AbsorbPointer(
        absorbing: !isEnabled,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.4,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: tapKey,
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: effectiveTextColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: indicatorWidth,
                      height: 3.2,
                      decoration: BoxDecoration(
                        color: effectiveIndicator,
                        borderRadius: BorderRadius.circular(1.6),
                        boxShadow: [
                          BoxShadow(
                            color: effectiveIndicator.withValues(
                                alpha: isDark ? 0.45 : 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
