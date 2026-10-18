import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/model/feature_challenge.dart';
import 'package:nnbdc/services/feature_challenge_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/frosted_glass_card.dart';

class DailyTipChallengeCard extends StatefulWidget {
  final VoidCallback? onFruitAwarded;

  const DailyTipChallengeCard({
    super.key,
    this.onFruitAwarded,
  });

  @override
  State<DailyTipChallengeCard> createState() => _DailyTipChallengeCardState();
}

class _DailyTipChallengeCardState extends State<DailyTipChallengeCard> {
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
    final service = FeatureChallengeService();
    _hasAnsweredToday = service.hasAnsweredToday();
    _challenge = service.getTodayChallenge();
    if (_hasAnsweredToday) {
      _selectedOptionIndex = _challenge.correctIndex;
      _result = ChallengeResult(
        isCorrect: true,
        isFirstUnlock: false,
        fruitEarned: 0,
        explanation: _challenge.explanation,
      );
    }
  }

  Future<void> _handleOptionTap(int index) async {
    if (_hasAnsweredToday || _submitting) return;

    // 如果选了错误的，给即时温和反馈
    if (index != _challenge.correctIndex) {
      setState(() {
        _wrongOptionIndex = index;
      });
      ToastUtil.info('不对哦，再试一次～答案就在其中');
      return;
    }

    // 选对了
    setState(() {
      _submitting = true;
      _wrongOptionIndex = null;
      _selectedOptionIndex = index;
    });

    final res = await FeatureChallengeService().submitAnswer(
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
    widget.onFruitAwarded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final themeConfig = AppThemeConfig.of(context.themeStyle);
    final isDark = context.isDarkMode;
    final totalCount = FeatureChallengeRepository.allChallenges.length;
    final unlockedCount = FeatureChallengeService().getUnlockedIds().length;

    final primaryColor = themeConfig.primaryColor;
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;

    return FrostedGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏：标题、徽章、查看全部秘籍入口
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(
                      '今日智慧锦囊',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'NotoSansSC',
                        fontFamilyFallback: AppTheme.sansSerifFallback,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_hasAnsweredToday)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '+3 智慧果',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/feature_handbook'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '秘籍 $unlockedCount/$totalCount',
                      style: TextStyle(
                        color: subTextColor.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontFamily: 'NotoSansSC',
                        fontFamilyFallback: AppTheme.sansSerifFallback,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: subTextColor.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 题目
          Text(
            _challenge.question,
            style: TextStyle(
              color: textColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              fontFamily: 'NotoSansSC',
              fontFamilyFallback: AppTheme.sansSerifFallback,
              letterSpacing: -0.1,
            ),
          ),

          const SizedBox(height: 14),

          // 选项列表
          Column(
            children: List.generate(_challenge.options.length, (index) {
              final optionText = _challenge.options[index];
              final isSelected = _selectedOptionIndex == index;
              final isWrong = _wrongOptionIndex == index;
              final isAnswered = _hasAnsweredToday;

              Color bgColor;
              Color borderCol;
              Color optionTextColor;

              if (isSelected && isAnswered) {
                // 选对状态：温润翡翠绿
                bgColor = const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12);
                borderCol = const Color(0xFF10B981).withValues(alpha: isDark ? 0.50 : 0.35);
                optionTextColor = const Color(0xFF10B981);
              } else if (isWrong) {
                // 选错状态：提示红
                bgColor = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.10);
                borderCol = const Color(0xFFEF4444).withValues(alpha: 0.4);
                optionTextColor = const Color(0xFFEF4444);
              } else {
                // 常规状态
                bgColor = isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
                borderCol = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);
                optionTextColor = textColor;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isAnswered ? null : () => _handleOptionTap(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderCol, width: 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected && isAnswered
                                  ? const Color(0xFF10B981)
                                  : (isWrong ? const Color(0xFFEF4444) : Colors.transparent),
                              border: Border.all(
                                color: isSelected && isAnswered
                                    ? const Color(0xFF10B981)
                                    : (isWrong ? const Color(0xFFEF4444) : subTextColor.withValues(alpha: 0.35)),
                                width: 1.2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: isSelected && isAnswered
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                                : (isWrong
                                    ? const Icon(Icons.close_rounded, color: Colors.white, size: 13)
                                    : Text(
                                        String.fromCharCode(65 + index),
                                        style: TextStyle(
                                          color: subTextColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              optionText,
                              style: TextStyle(
                                color: optionTextColor,
                                fontSize: 13.5,
                                fontWeight: (isSelected && isAnswered) ? FontWeight.w600 : FontWeight.w400,
                                fontFamily: 'NotoSansSC',
                                fontFamilyFallback: AppTheme.sansSerifFallback,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          // 答对后的技巧解析卡片
          if (_hasAnsweredToday && _result != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '【${_challenge.title}】',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'NotoSansSC',
                            fontFamilyFallback: AppTheme.sansSerifFallback,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _challenge.explanation,
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 12,
                            height: 1.45,
                            fontFamily: 'NotoSansSC',
                            fontFamilyFallback: AppTheme.sansSerifFallback,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
