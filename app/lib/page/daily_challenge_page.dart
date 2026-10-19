import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/model/feature_challenge.dart';
import 'package:nnbdc/services/feature_challenge_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/page_back_button.dart';

/// 每日一问 / 每日问题挑战独立页面（对标炭炭背单词百宝箱「每日一问」）
class DailyChallengePage extends StatefulWidget {
  const DailyChallengePage({super.key});

  @override
  State<DailyChallengePage> createState() => _DailyChallengePageState();
}

class _DailyChallengePageState extends State<DailyChallengePage> {
  final FeatureChallengeService _service = FeatureChallengeService();
  late FeatureChallenge _challenge;
  bool _hasAnsweredToday = false;
  int? _selectedOptionIndex;
  int? _wrongOptionIndex;
  ChallengeResult? _result;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  void _loadState() {
    _hasAnsweredToday = _service.hasAnsweredToday();
    _challenge = _service.getTodayChallenge();
    if (_hasAnsweredToday) {
      _selectedOptionIndex = _challenge.correctIndex;
      _result = ChallengeResult(
        isCorrect: true,
        isFirstUnlock: false,
        fruitEarned: 1,
        explanation: _challenge.explanation,
      );
    }
  }

  Future<void> _handleOptionTap(int index) async {
    if (_hasAnsweredToday || _submitting) return;

    if (index != _challenge.correctIndex) {
      HapticFeedback.lightImpact();
      setState(() {
        _wrongOptionIndex = index;
      });
      ToastUtil.info('不对哦，再试一次～答案就在其中');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = true;
      _wrongOptionIndex = null;
      _selectedOptionIndex = index;
    });

    final res = await _service.submitAnswer(
      challengeId: _challenge.id,
      selectedOptionIndex: index,
    );

    if (!mounted) return;

    setState(() {
      _submitting = false;
      _hasAnsweredToday = true;
      _result = res;
    });

    ToastUtil.success('回答正确！获得 ${res.fruitEarned} 颗智慧果 🍒');
  }

  @override
  Widget build(BuildContext context) {
    final themeConfig = AppThemeConfig.of(context.themeStyle);
    final isDark = context.isDarkMode;
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;
    final accentGreen = const Color(0xFF10B981);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏：返回键、中间「每日一问」、右上角「答题历史」
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  PageBackButton(color: textColor),
                  const Spacer(),
                  Text(
                    '每日一问',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      fontFamily: 'NotoSansSC',
                      fontFamilyFallback: AppTheme.sansSerifFallback,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '答题历史',
                    icon: Icon(
                      Icons.history_rounded,
                      color: textColor.withValues(alpha: 0.8),
                      size: 24,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DailyChallengeHistoryPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 题干与已答题印章
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _challenge.question,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.38,
                              letterSpacing: -0.3,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
                            ),
                          ),
                        ),
                        if (_hasAnsweredToday) ...[
                          const SizedBox(width: 14),
                          _buildAnsweredSeal(accentGreen),
                        ],
                      ],
                    ),

                    const SizedBox(height: 32),

                    // 选项列表（对标炭炭背单词：左代号竖线分栏卡片）
                    Column(
                      children: List.generate(_challenge.options.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildTantanStyleOption(
                            index: index,
                            text: _challenge.options[index],
                            isDark: isDark,
                            textColor: textColor,
                            subTextColor: subTextColor,
                            accentGreen: accentGreen,
                          ),
                        );
                      }),
                    ),

                    // 底部解析与「泡泡 tips」（答对或已答后呈现）
                    if (_hasAnsweredToday && _result != null) ...[
                      const SizedBox(height: 12),
                      Divider(
                        height: 32,
                        thickness: 0.8,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: accentGreen,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '泡泡 tips',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _challenge.title,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _challenge.explanation,
                                  style: TextStyle(
                                    color: subTextColor,
                                    fontSize: 13.5,
                                    height: 1.55,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 题干右上角的「已答题」圆形印章徽章
  Widget _buildAnsweredSeal(Color sealColor) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: sealColor.withValues(alpha: 0.55),
          width: 1.8,
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: sealColor.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '已答题',
          style: TextStyle(
            color: sealColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFamily: 'NotoSansSC',
            fontFamilyFallback: AppTheme.sansSerifFallback,
          ),
        ),
      ),
    );
  }

  /// 对标炭炭背单词的选项条形卡片
  Widget _buildTantanStyleOption({
    required int index,
    required String text,
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
    required Color accentGreen,
  }) {
    final isSelected = _selectedOptionIndex == index;
    final isWrong = _wrongOptionIndex == index;
    final isAnswered = _hasAnsweredToday;

    Color cardBg;
    Color borderCol;
    Color labelCol;
    Color contentCol;

    if (isSelected && isAnswered) {
      cardBg = accentGreen.withValues(alpha: isDark ? 0.20 : 0.10);
      borderCol = accentGreen.withValues(alpha: 0.85);
      labelCol = accentGreen;
      contentCol = textColor;
    } else if (isWrong) {
      cardBg = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.10);
      borderCol = const Color(0xFFEF4444).withValues(alpha: 0.7);
      labelCol = const Color(0xFFEF4444);
      contentCol = textColor;
    } else {
      cardBg = isDark
          ? const Color(0xFF1E293B)
          : const Color(0xFFF1F5F9).withValues(alpha: 0.7);
      borderCol = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04);
      labelCol = textColor.withValues(alpha: 0.85);
      contentCol = textColor;
    }

    final letter = String.fromCharCode(65 + index);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAnswered ? null : () => _handleOptionTap(index),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderCol,
              width: (isSelected && isAnswered) ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // 左侧代号区域（固定宽度）
              SizedBox(
                width: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      letter,
                      style: TextStyle(
                        color: labelCol,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (isAnswered && isSelected) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accentGreen.withValues(alpha: isDark ? 0.35 : 0.20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '+1',
                          style: TextStyle(
                            color: accentGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 垂直细分割线
              Container(
                width: 1,
                height: 42,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),

              // 右侧选项正文
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: contentCol,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
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
    );
  }
}

/// 答题历史页面（对标炭炭背单词「答题历史」）
class DailyChallengeHistoryPage extends StatelessWidget {
  const DailyChallengeHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeConfig = AppThemeConfig.of(context.themeStyle);
    final isDark = context.isDarkMode;
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;
    final accentGreen = const Color(0xFF10B981);

    final history = FeatureChallengeService().getAnswerHistory();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  PageBackButton(color: textColor),
                  const Spacer(),
                  Text(
                    '答题历史',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      fontFamily: 'NotoSansSC',
                      fontFamilyFallback: AppTheme.sansSerifFallback,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // 占位保持居中
                ],
              ),
            ),

            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 48,
                            color: subTextColor.withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无答题记录',
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 14,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '每天打卡后来答一题，轻松解锁智慧果',
                            style: TextStyle(
                              color: subTextColor.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 20,
                        thickness: 0.6,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final timeStr = _formatTime(item.answerTime);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.question,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                        fontFamily: 'NotoSansSC',
                                        fontFamilyFallback: AppTheme.sansSerifFallback,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        color: subTextColor.withValues(alpha: 0.7),
                                        fontSize: 12,
                                        fontFamily: 'NotoSansSC',
                                        fontFamilyFallback: AppTheme.sansSerifFallback,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '+${item.fruitEarned}',
                                    style: TextStyle(
                                      color: accentGreen,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '智慧果',
                                    style: TextStyle(
                                      color: subTextColor.withValues(alpha: 0.8),
                                      fontSize: 11,
                                      fontFamily: 'NotoSansSC',
                                      fontFamilyFallback: AppTheme.sansSerifFallback,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}
