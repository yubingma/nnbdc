import 'package:flutter/material.dart';
import '../../api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/badge_svg_assets.dart';

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

      // 4. 如果都未解锁：按完成度百分比从高到低排序 (例如 80% > 50% > 0%)
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
    final badge = vo.badge;
    final isUnlocked = vo.isUnlocked == true;
    final tier = badge?.tier ?? 'BRONZE';
    final tierColor = BadgeSvgAssets.getTierColor(tier);
    final tierName = BadgeSvgAssets.getTierName(tier);
    final categoryName = BadgeSvgAssets.getCategoryName(badge?.category);
    final isStackable = badge?.isStackable ?? false;
    final obtainCount = vo.obtainCount ?? 0;
    final starLevel = vo.starLevel ?? 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1B2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部指示条
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // 勋章大图
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isUnlocked ? BadgeSvgAssets.getTierGlowColor(tier).withValues(alpha: 0.4) : Colors.transparent,
                          blurRadius: 36,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  BadgeSvgAssets.renderBadge(
                    code: badge?.code,
                    size: 96,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 勋章名称
              Text(
                badge?.name ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),

              // 品阶 & 分类
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tierColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$tierName · $categoryName',
                  style: TextStyle(
                    color: tierColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              if (isStackable && isUnlocked) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < starLevel ? Icons.star : Icons.star_border,
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📜 达成条件',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge?.description ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '🎁 激励回馈',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '魔法泡泡 +${badge?.rewardBubbles ?? 0}',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                          ? const Color(0xFF334155)
                          : const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _toggleEquip(vo);
                    },
                    child: Text(
                      (vo.isEquipped == true) ? '取消主页佩戴' : '置顶佩戴到主页',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // 🛠️ 管理员专属：重置/删除此勋章（便于调试与测试弹窗）
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
    final filtered = _filteredBadges;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '荣耀勋章墙',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : RefreshIndicator(
              onRefresh: _loadBadges,
              color: const Color(0xFF4F46E5),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 顶部汇总展台
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF818CF8).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '🏆 收集成就进度',
                                  style: TextStyle(
                                    color: Color(0xFFA5B4FC),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '$_unlockedCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      TextSpan(
                                        text: ' / ${_allBadges.length}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '坚持背词与自律打卡，点亮属于你的星光图鉴',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text('🎖', style: TextStyle(fontSize: 48)),
                        ],
                      ),
                    ),
                  ),

                  // 分类筛选 Chip
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = _selectedCategory == cat['key'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat['label']!),
                              selected: isSelected,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                              backgroundColor: const Color(0xFF1E293B),
                              selectedColor: const Color(0xFF4F46E5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color: isSelected
                                      ? const Color(0xFF818CF8)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              showCheckmark: false,
                              onSelected: (_) {
                                setState(() => _selectedCategory = cat['key']!);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // 勋章网格 Grid
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final vo = filtered[index];
                          final badge = vo.badge;
                          final isUnlocked = vo.isUnlocked == true;
                          final tier = badge?.tier ?? 'BRONZE';
                          final tierColor = BadgeSvgAssets.getTierColor(tier);
                          final isStackable = badge?.isStackable ?? false;
                          final obtainCount = vo.obtainCount ?? 0;
                          final starLevel = vo.starLevel ?? 1;

                          return InkWell(
                            onTap: () => _showBadgeDetail(vo),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: isUnlocked
                                    ? RadialGradient(
                                        center: const Alignment(0, -0.3),
                                        radius: 0.85,
                                        colors: [
                                          BadgeSvgAssets.getTierGlowColor(tier).withValues(alpha: 0.22),
                                          const Color(0xFF1E293B).withValues(alpha: 0.85),
                                        ],
                                      )
                                    : const LinearGradient(
                                        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isUnlocked
                                      ? tierColor.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.08),
                                  width: isUnlocked ? 1.5 : 1,
                                ),
                                boxShadow: isUnlocked
                                    ? [
                                        BoxShadow(
                                          color: tierColor.withValues(alpha: 0.2),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 勋章 SVG 图标 + 叠层角标
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      BadgeSvgAssets.renderBadge(
                                        code: badge?.code,
                                        size: 72,
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
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (vo.isEquipped == true)
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981),
                                              borderRadius: BorderRadius.circular(6),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                            child: const Text(
                                              '佩戴中',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
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
                                      color: isUnlocked ? Colors.white : Colors.white38,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),

                                  // 状态 / 星级
                                  if (isStackable && isUnlocked)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(5, (index) {
                                        return Icon(
                                          index < starLevel ? Icons.star : Icons.star_border,
                                          color: const Color(0xFFFBBF24),
                                          size: 12,
                                        );
                                      }),
                                    )
                                  else
                                    Text(
                                      isUnlocked
                                          ? '已点亮'
                                          : '${vo.progressCurrent ?? 0} / ${vo.progressTarget ?? badge?.targetValue ?? 1}',
                                      style: TextStyle(
                                        color: isUnlocked ? tierColor : Colors.white30,
                                        fontSize: 11,
                                        fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),

                                  const SizedBox(height: 6),

                                  // 进度条（未解锁时）
                                  if (!isUnlocked)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: vo.progressPercent ?? 0.0,
                                        backgroundColor: Colors.white10,
                                        valueColor: AlwaysStoppedAnimation<Color>(tierColor.withValues(alpha: 0.6)),
                                        minHeight: 4,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 32),
                  ),
                ],
              ),
            ),
    );
  }
}
