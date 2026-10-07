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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.nightlight_round, size: 20, color: primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '以凌晨 03:00 作为日期切换点',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '关照深夜深度学习的作息习惯',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '本应用专为深度学习者量身定制：每日以凌晨 03:00 判定跨天。若您在凌晨 3 点前背诵单词，所有学习进度、连胜与打卡记录仍将完整归属于前一天的计划中，无需赶在午夜前匆忙打卡。',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: isDarkMode ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 实时状态对照卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '当前时间与学习日期对照',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _buildInfoRow(
                    label: '当前系统时间',
                    valueWidget: DynamicClockText(
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    label: '归属学习日期',
                    value: businessDateStr,
                    isDarkMode: isDarkMode,
                    highlight: true,
                    highlightColor: primaryColor,
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    label: '设备所在时区',
                    value: '$timeZoneName (UTC$offsetSign$offsetHours)',
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 多时区漫游规则说明卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.public_rounded, size: 16, color: isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                      const SizedBox(width: 8),
                      Text(
                        '跨时区漫游同步规则',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当您出行旅居至其他时区时，应用将自动根据设备本地时间计算学习天，进度采用单向正向推进机制，杜绝因时区切换导致进度倒退或数据回滚，确保全球同步万无一失。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
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
          if (valueWidget != null)
            valueWidget
          else if (value != null)
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                color: highlight
                    ? (highlightColor ?? (isDarkMode ? Colors.white : Colors.black))
                    : (isDarkMode ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
        ],
      ),
    );
  }
}
