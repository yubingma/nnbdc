import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/badge_svg_assets.dart';
import '../../theme/app_theme.dart';

class BadgeWallPage extends StatefulWidget {
  const BadgeWallPage({super.key});

  @override
  State<BadgeWallPage> createState() => _BadgeWallPageState();
}

class _BadgeWallPageState extends State<BadgeWallPage> {
  bool _loading = true;
  List<UserBadgeVo> _allBadges = [];
  String _selectedCategory = 'ALL';

  final List<Map<String, String>> _categories = [
    {'key': 'ALL', 'label': '全部'},
    {'key': 'HABIT', 'label': '恒心打卡'},
    {'key': 'VOCAB', 'label': '博学词汇'},
    {'key': 'MASTERY', 'label': '精进学霸'},
    {'key': 'SOCIAL', 'label': '共鸣探索'},
  ];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // 1. 查询本地 user_badges 记录
      final localRecords = await MyDatabase.instance.userBadgesDao.getBadgesByUserId(user.id);
      final Map<String, UserBadge> localMap = {for (var item in localRecords) item.badgeCode: item};

      // 2. 获取客观指标数据
      final streakDays = user.continuousDakaDayCount;
      final masteredWords = user.masteredWordsCount;

      // 3. 本地全量装配 16 枚勋章，并自动对齐历史已达标勋章
      final List<UserBadgeVo> list = [];
      for (final def in BadgeSvgAssets.allBadgeDefinitions) {
        final code = def['code'] as String;
        final targetValue = def['targetValue'] as int;
        final conditionType = def['conditionType'] as String;
        final isStackable = def['isStackable'] as bool;
        final rewardBubbles = def['rewardBubbles'] as int;

        var ub = localMap[code];

        // 计算当前客观进度
        int current = 0;
        if (conditionType == 'STREAK_DAYS') {
          current = streakDays;
        } else if (conditionType == 'MASTERED_WORDS') {
          current = masteredWords;
        }

        // 纯粹根据本地数据库状态如实展示
        final isUnlocked = ub != null;
        final vo = UserBadgeVo(
          id: ub?.id,
          userId: user.id,
          badgeCode: code,
          obtainCount: ub?.obtainCount ?? 0,
          starLevel: ub?.starLevel ?? 1,
          unlockedAt: ub?.unlockedAt,
          isEquipped: ub?.isEquipped ?? false,
          isViewed: ub?.isViewed ?? false,
          isUnlocked: isUnlocked,
          progressCurrent: isUnlocked ? targetValue : current,
          progressTarget: targetValue,
          progressPercent: isUnlocked ? 1.0 : (targetValue > 0 ? (current / targetValue).clamp(0.0, 1.0) : 0.0),
          badge: BadgeVo(
            code: code,
            name: def['name'] as String,
            category: def['category'] as String,
            tier: def['tier'] as String,
            isStackable: isStackable,
            rewardBubbles: rewardBubbles,
            description: def['description'] as String,
            targetValue: targetValue,
            conditionType: conditionType,
          ),
        );
        list.add(vo);
      }

      if (mounted) {
        setState(() {
          _allBadges = list;
          _loading = false;
        });
      }
    } catch (e, s) {
      Global.logger.e('加载本地勋章失败: $e', stackTrace: s);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<UserBadgeVo> get _filteredBadges {
    final list = _selectedCategory == 'ALL'
        ? List<UserBadgeVo>.from(_allBadges)
        : _allBadges.where((b) {
            final cat = b.badge?.category?.toUpperCase();
            return cat == _selectedCategory;
          }).toList();

    // 🎯 按照完成度与达成状态智能排序
    list.sort((a, b) {
      // 1. 已佩戴置顶的优先排在最前
      final aEquipped = a.isEquipped == true ? 1 : 0;
      final bEquipped = b.isEquipped == true ? 1 : 0;
      if (aEquipped != bEquipped) {
        return bEquipped.compareTo(aEquipped);
      }

      // 2. 已解锁 vs 未解锁 (已解锁在前)
      final aUnlocked = a.isUnlocked == true ? 1 : 0;
      final bUnlocked = b.isUnlocked == true ? 1 : 0;
      if (aUnlocked != bUnlocked) {
        return bUnlocked.compareTo(aUnlocked);
      }

      // 3. 如果都已解锁：优先比较叠层次数，其次解锁时间
      if (a.isUnlocked == true) {
        final aCount = a.obtainCount ?? 1;
        final bCount = b.obtainCount ?? 1;
        if (aCount != bCount) {
          return bCount.compareTo(aCount);
        }
        if (a.unlockedAt != null && b.unlockedAt != null) {
          return b.unlockedAt!.compareTo(a.unlockedAt!);
        }
      }

      // 4. 如果都未解锁：按完成度百分比从高到低排序
      final aPercent = a.progressPercent ?? 0.0;
      final bPercent = b.progressPercent ?? 0.0;
      if ((aPercent - bPercent).abs() > 0.001) {
        return bPercent.compareTo(aPercent);
      }

      // 5. 完成度相同时，目标阈值小的在前（更容易达成）
      final aTarget = a.progressTarget ?? 0;
      final bTarget = b.progressTarget ?? 0;
      return aTarget.compareTo(bTarget);
    });

    return list;
  }

  int get _unlockedCount => _allBadges.where((b) => b.isUnlocked == true).length;

  Future<void> _toggleEquip(UserBadgeVo badgeVo) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;
    final badgeCode = badgeVo.badgeCode ?? badgeVo.badge?.code;
    if (badgeCode == null) return;

    final currentlyEquipped = badgeVo.isEquipped ?? false;
    final newStatus = !currentlyEquipped;

    try {
      final success = await MyDatabase.instance.userBadgesDao.toggleEquipBadge(user.id, badgeCode, newStatus);
      if (success) {
        ToastUtil.success(newStatus ? '已置顶佩戴该勋章' : '已取消佩戴');
        _loadBadges();
      }
    } catch (e) {
      ToastUtil.error('操作失败');
    }
  }

  void _showBadgeDetail(UserBadgeVo vo) {
    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final badge = vo.badge;
    final isUnlocked = vo.isUnlocked == true;
    final tier = badge?.tier ?? 'BRONZE';
    final tierColor = BadgeSvgAssets.getTierColor(tier);
    final tierName = BadgeSvgAssets.getTierName(tier);
    final categoryName = BadgeSvgAssets.getCategoryName(badge?.category);
    final isStackable = badge?.isStackable ?? false;
    final obtainCount = vo.obtainCount ?? 0;
    final starLevel = vo.starLevel ?? 1;
    final themeStyle = Provider.of<DarkMode>(context, listen: false).themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final cardBg = themeConfig.cardBg;
    final subtleBg = themeConfig.subtleBg;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: themeConfig.cardBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.5 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部指示条
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white24 : const Color(0xFFD0E0DC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // 勋章大图
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isUnlocked ? BadgeSvgAssets.getTierGlowColor(tier).withValues(alpha: 0.35) : Colors.transparent,
                          blurRadius: 32,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  BadgeSvgAssets.renderBadge(
                    code: badge?.code,
                    size: 92,
                    isUnlocked: isUnlocked,
                  ),
                  if (isStackable && isUnlocked && obtainCount > 1)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEC4899).withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Text(
                          '×$obtainCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // 勋章名称
              Text(
                badge?.name ?? '',
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 6),

              // 品阶 & 分类
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tierColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '$tierName · $categoryName',
                  style: TextStyle(
                    color: tierColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ),

              if (isStackable && isUnlocked) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < starLevel ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFFBBF24),
                      size: 16,
                    );
                  }),
                ),
              ],

              const SizedBox(height: 16),

              // 解锁条件与描述
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: subtleBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📜 达成条件',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge?.description ?? '',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '🎁 激励回馈',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '魔法泡泡 +${badge?.rewardBubbles ?? 0}',
                      style: const TextStyle(
                        color: Color(0xFF0284C7),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    if (isUnlocked && vo.unlockedAt != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '⏰ 解锁时间',
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vo.unlockedAt!.toLocal().toString().split('.')[0],
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 12,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 底部佩戴与关闭按钮
              if (isUnlocked) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (vo.isEquipped == true)
                          ? (isDarkMode ? const Color(0xFF334155) : const Color(0xFF64748B))
                          : accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _toggleEquip(vo);
                    },
                    child: Text(
                      (vo.isEquipped == true) ? '取消主页佩戴' : '置顶佩戴到主页',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'NotoSansSC'),
                    ),
                  ),
                ),

                // 管理员调试删除
                if (Global.getLoggedInUser()?.isAdmin == true) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text(
                        '删除此勋章（管理员调试）',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final user = Global.getLoggedInUser();
                        final badgeCode = vo.badgeCode ?? vo.badge?.code;
                        if (user != null && badgeCode != null) {
                          Navigator.of(ctx).pop();
                          await MyDatabase.instance.userBadgesDao.deleteBadge(user.id, badgeCode, true);
                          ToastUtil.success('已删除勋章: $badgeCode');
                          _loadBadges();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;
    final filtered = _filteredBadges;

    final cardBg = themeConfig.cardBg;
    final subtleBg = themeConfig.subtleBg;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final borderColor = themeConfig.cardBorder;

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '荣耀勋章墙',
          style: TextStyle(
            color: textColor,
            fontSize: 17.5,
            fontWeight: FontWeight.w800,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : RefreshIndicator(
              onRefresh: _loadBadges,
              color: accentColor,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 1. 顶部 Hero 成就殿堂展台
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: themeConfig.appBarGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('✨ ', style: TextStyle(fontSize: 11)),
                                    Text(
                                      '个人成就殿堂',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text('🎖️', style: TextStyle(fontSize: 32)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$_unlockedCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Roboto',
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '/ ${_allBadges.length} 枚已点亮',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '坚持背词与自律打卡，点亮属于你的星光图鉴',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const SizedBox(height: 14),
                          // 进度条
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _allBadges.isNotEmpty ? (_unlockedCount / _allBadges.length) : 0.0,
                              backgroundColor: Colors.black.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. 分类筛选胶囊栏
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat['key'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () => setState(() => _selectedCategory = cat['key']!),
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? accentColor : cardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? accentColor : borderColor,
                                    width: 1.2,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: accentColor.withValues(alpha: 0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Text(
                                  cat['label']!,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : subtitleColor,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    fontSize: 12.5,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // 3. 勋章网格展示
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.76,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final vo = filtered[index];
                          final badge = vo.badge;
                          final isUnlocked = vo.isUnlocked == true;
                          final tier = badge?.tier ?? 'BRONZE';
                          final tierColor = BadgeSvgAssets.getTierColor(tier);
                          final tierName = BadgeSvgAssets.getTierName(tier);
                          final isStackable = badge?.isStackable ?? false;
                          final obtainCount = vo.obtainCount ?? 0;
                          final starLevel = vo.starLevel ?? 1;

                          return InkWell(
                            onTap: () => _showBadgeDetail(vo),
                            borderRadius: BorderRadius.circular(22),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? (isDarkMode ? const Color(0xFF162522) : cardBg)
                                    : (isDarkMode ? const Color(0xFF101B19) : cardBg.withValues(alpha: 0.8)),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isUnlocked
                                      ? (vo.isEquipped == true ? accentColor : tierColor.withValues(alpha: isDarkMode ? 0.4 : 0.3))
                                      : borderColor,
                                  width: isUnlocked ? 1.5 : 1,
                                ),
                                boxShadow: isUnlocked
                                    ? [
                                        BoxShadow(
                                          color: tierColor.withValues(alpha: isDarkMode ? 0.18 : 0.08),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 顶部角标区 (左：已佩戴；右：品阶)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (vo.isEquipped == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentColor,
                                            borderRadius: BorderRadius.circular(6),
                                            boxShadow: [
                                              BoxShadow(
                                                color: accentColor.withValues(alpha: 0.35),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.star_rounded, size: 9, color: Colors.white),
                                              SizedBox(width: 2),
                                              Text(
                                                '佩戴中',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  fontFamily: 'NotoSansSC',
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        const SizedBox.shrink(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: tierColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          tierName,
                                          style: TextStyle(
                                            color: tierColor,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'NotoSansSC',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 6),

                                  // 勋章 SVG 图标 + 叠层角标
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      BadgeSvgAssets.renderBadge(
                                        code: badge?.code,
                                        size: 68,
                                        isUnlocked: isUnlocked,
                                      ),
                                      if (isStackable && isUnlocked && obtainCount > 1)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              '×$obtainCount',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w900,
                                                fontFamily: 'Roboto',
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // 名称
                                  Text(
                                    badge?.name ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isUnlocked ? textColor : subtitleColor.withValues(alpha: 0.6),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'NotoSansSC',
                                    ),
                                  ),
                                  const SizedBox(height: 2),

                                  // 状态 / 进度 / 星级
                                  if (isStackable && isUnlocked)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(5, (index) {
                                        return Icon(
                                          index < starLevel ? Icons.star_rounded : Icons.star_border_rounded,
                                          color: const Color(0xFFFBBF24),
                                          size: 13,
                                        );
                                      }),
                                    )
                                  else
                                    Text(
                                      isUnlocked
                                          ? '已点亮'
                                          : '${vo.progressCurrent ?? 0} / ${vo.progressTarget ?? badge?.targetValue ?? 1}',
                                      style: TextStyle(
                                        color: isUnlocked ? accentColor : subtitleColor.withValues(alpha: 0.7),
                                        fontSize: 10.5,
                                        fontWeight: isUnlocked ? FontWeight.w700 : FontWeight.w600,
                                        fontFamily: isUnlocked ? 'NotoSansSC' : 'Roboto',
                                      ),
                                    ),

                                  const SizedBox(height: 6),

                                  // 进度条（未解锁时）
                                  if (!isUnlocked)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: vo.progressPercent ?? 0.0,
                                        backgroundColor: subtleBg,
                                        valueColor: AlwaysStoppedAnimation<Color>(accentColor.withValues(alpha: 0.7)),
                                        minHeight: 4,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

