import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/widget/dynamic_clock_text.dart';
import 'package:provider/provider.dart';

/// 学习日期规则说明独立二级页面
class StudyDateRulesPage extends StatelessWidget {
  const StudyDateRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;

    final now = AppClock.now();
    final timeZoneName = now.timeZoneName;
    final offsetSign = now.timeZoneOffset.isNegative ? '-' : '+';
    final offsetHours = now.timeZoneOffset.inHours.abs();
    final businessDateStr = DateFormat('yyyy年M月d日').format(app_date.DateUtils.businessDate(now));

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '学习日期说明',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 核心高亮卡片：凌晨 03:00 切换
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          primaryColor.withValues(alpha: 0.16),
                          primaryColor.withValues(alpha: 0.06),
                        ]
                      : [
                          primaryColor.withValues(alpha: 0.10),
                          primaryColor.withValues(alpha: 0.03),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: primaryColor.withValues(alpha: isDarkMode ? 0.25 : 0.20),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.nightlight_round, size: 18, color: primaryColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '凌晨 03:00 跨天',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '每日以凌晨 03:00 判定跨天。凌晨 3 点前学习打卡，均计入前一天。',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: isDarkMode ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 实时状态对照卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '实时对照',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildInfoRow(
                    label: '系统时间',
                    valueWidget: DynamicClockText(
                      showBusinessDate: false,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    label: '归属日期',
                    value: businessDateStr,
                    isDarkMode: isDarkMode,
                    highlight: true,
                    highlightColor: primaryColor,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    label: '当前时区',
                    value: '$timeZoneName (UTC$offsetSign$offsetHours)',
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 时区规则说明卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '时区漫游',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '跨时区按设备本地时间计算，进度单向推进，不会倒退。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDarkMode ? Colors.white60 : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    String? value,
    Widget? valueWidget,
    required bool isDarkMode,
    bool highlight = false,
    Color? highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 8),
          if (valueWidget != null)
            Flexible(child: valueWidget)
          else if (value != null)
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                  color: highlight
                      ? (highlightColor ?? (isDarkMode ? Colors.white : Colors.black))
                      : (isDarkMode ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
