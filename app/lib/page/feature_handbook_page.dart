import 'package:flutter/material.dart';

import 'package:nnbdc/model/feature_challenge.dart';
import 'package:nnbdc/services/feature_challenge_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/widget/frosted_glass_card.dart';
import 'package:nnbdc/widget/page_back_button.dart';

class FeatureHandbookPage extends StatefulWidget {
  const FeatureHandbookPage({super.key});

  @override
  State<FeatureHandbookPage> createState() => _FeatureHandbookPageState();
}

class _FeatureHandbookPageState extends State<FeatureHandbookPage> {
  final FeatureChallengeService _service = FeatureChallengeService();
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = '全部';
  String _searchKeyword = '';
  Set<String> _unlockedIds = {};
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _unlockedIds = _service.getUnlockedIds().toSet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final cats = {'全部'};
    for (final c in FeatureChallengeRepository.allChallenges) {
      cats.add(c.category);
    }
    return cats.toList();
  }

  List<FeatureChallenge> get _filteredChallenges {
    return FeatureChallengeRepository.allChallenges.where((item) {
      if (_selectedCategory != '全部' && item.category != _selectedCategory) {
        return false;
      }
      if (_searchKeyword.isNotEmpty) {
        final kw = _searchKeyword.toLowerCase();
        final matchTitle = item.title.toLowerCase().contains(kw);
        final matchQuestion = item.question.toLowerCase().contains(kw);
        final matchExplanation = item.explanation.toLowerCase().contains(kw);
        return matchTitle || matchQuestion || matchExplanation;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeConfig = AppThemeConfig.of(context.themeStyle);
    final isDark = context.isDarkMode;
    final primaryColor = themeConfig.primaryColor;
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;
    final totalCount = FeatureChallengeRepository.allChallenges.length;
    final unlockedCount = _unlockedIds.length;
    final progress = totalCount > 0 ? unlockedCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  PageBackButton(color: textColor),
                  const SizedBox(width: 8),
                  Text(
                    '玩转技巧与常见问题',
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
                ],
              ),
            ),

            // 搜索输入框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: textColor, fontSize: 13.5),
                  onChanged: (val) => setState(() => _searchKeyword = val.trim()),
                  decoration: InputDecoration(
                    hintText: '搜索手势、释义、发音、同步等秘籍与问题...',
                    hintStyle: TextStyle(
                      color: subTextColor.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      fontFamily: 'NotoSansSC',
                      fontFamilyFallback: AppTheme.sansSerifFallback,
                    ),
                    prefixIcon: Icon(Icons.search_rounded, color: subTextColor, size: 18),
                    suffixIcon: _searchKeyword.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchKeyword = '');
                            },
                            child: Icon(Icons.clear_rounded, color: subTextColor, size: 16),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 列表内容
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  // 进度展台卡片
                  FrostedGlassCard(
                    borderRadius: 18,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🍒', style: TextStyle(fontSize: 16)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '秘籍掌握度：$unlockedCount / $totalCount',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'NotoSansSC',
                                      fontFamilyFallback: AppTheme.sansSerifFallback,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '每天打卡完成后参与 1 题智慧小挑战，即可解锁新秘籍并赢取智慧果',
                                    style: TextStyle(
                                      color: subTextColor,
                                      fontSize: 11.5,
                                      fontFamily: 'NotoSansSC',
                                      fontFamilyFallback: AppTheme.sansSerifFallback,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 分类 Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = cat == _selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) setState(() => _selectedCategory = cat);
                            },
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : subTextColor,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
                            ),
                            selectedColor: primaryColor,
                            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 秘籍列表
                  ..._filteredChallenges.map((item) {
                    final isUnlocked = _unlockedIds.contains(item.id);
                    final isExpanded = _expandedIds.contains(item.id);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FrostedGlassCard(
                        borderRadius: 16,
                        padding: const EdgeInsets.all(14),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedIds.remove(item.id);
                              } else {
                                _expandedIds.add(item.id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isUnlocked
                                          ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12)
                                          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: TextStyle(
                                        color: isUnlocked ? const Color(0xFF10B981) : subTextColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'NotoSansSC',
                                        fontFamilyFallback: AppTheme.sansSerifFallback,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: subTextColor.withValues(alpha: 0.5),
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                Divider(
                                  height: 1,
                                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '❓ 常见疑问与场景',
                                  style: TextStyle(
                                    color: subTextColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.question,
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    height: 1.45,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '💡 解决方案与秘籍',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.explanation,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    height: 1.45,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
