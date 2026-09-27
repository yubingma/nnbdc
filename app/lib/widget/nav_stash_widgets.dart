import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/model/nav_tab_config.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/frosted_glass_card.dart';

/// 1. 长按底栏弹出的快捷收纳菜单（基于 flutter-frosted-glass 规范）
class StashedNavMenuDialog {
  static Future<void> show(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isGuest = Global.isGuest;
    final hiddenKeys = Prefs.hiddenBottomNavKeys;
    final stashedTabs = NavTabKey.getStashedTabs(isGuest: isGuest, hiddenKeys: hiddenKeys);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_stashed_nav_menu',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.18),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xB81C2127) : const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDarkMode ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 头部标题与收起
                      Row(
                        children: [
                          Icon(
                            Icons.archive_outlined,
                            size: 18,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '快捷功能收纳',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(dialogCtx),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: isDarkMode ? Colors.white54 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 被收纳的功能列表
                      if (stashedTabs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 32,
                                color: Theme.of(context).primaryColor.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '所有功能已在底栏常驻',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...stashedTabs.map((tab) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.pop(dialogCtx);
                                  HapticFeedback.lightImpact();
                                  context.push(tab.routePath);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDarkMode
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : const Color(0xFFE2E8F0),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          tab.icon,
                                          size: 18,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tab.label,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                                                fontFamily: 'NotoSansSC',
                                              ),
                                            ),
                                            Text(
                                              tab.description,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                fontFamily: 'NotoSansSC',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                      // 分割线
                      Divider(
                        height: 16,
                        thickness: 0.6,
                        color: isDarkMode ? Colors.white12 : const Color(0xFFE2E8F0),
                      ),

                      // 底部偏好定制按钮
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.pop(dialogCtx);
                          NavBarCustomizationSheet.show(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 15,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '定制底栏按钮...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).primaryColor,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ],
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
      },
    );
  }
}

/// 2. 底栏导航管理弹窗（定制显示/隐藏）
class NavBarCustomizationSheet extends StatefulWidget {
  const NavBarCustomizationSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NavBarCustomizationSheet(),
    );
  }

  @override
  State<NavBarCustomizationSheet> createState() => _NavBarCustomizationSheetState();
}

class _NavBarCustomizationSheetState extends State<NavBarCustomizationSheet> {
  late List<String> _hiddenKeys;

  @override
  void initState() {
    super.initState();
    _hiddenKeys = List<String>.from(Prefs.hiddenBottomNavKeys);
  }

  void _toggleTab(NavTabKey tab, bool isVisible) async {
    final nextHidden = List<String>.from(_hiddenKeys);
    if (isVisible) {
      nextHidden.remove(tab.key);
    } else {
      // 检查隐藏后剩余数量，确保至少有 2 个留在底栏
      final currentVisible = NavTabKey.getVisibleTabs(
        isGuest: Global.isGuest,
        hiddenKeys: nextHidden..add(tab.key),
      );
      if (currentVisible.length < 2) {
        ToastUtil.info('底栏至少需要保留两个按钮');
        return;
      }
      if (!nextHidden.contains(tab.key)) {
        nextHidden.add(tab.key);
      }
    }

    setState(() {
      _hiddenKeys = nextHidden;
    });
    await Prefs.setHiddenBottomNavKeys(nextHidden);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isGuest = Global.isGuest;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E232A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖拽手柄
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 标题行
          Row(
            children: [
              Text(
                '底栏导航定制',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.2,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: isDarkMode ? Colors.white54 : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '关闭底栏显示的按钮将统一收纳在「我」页面，并可通过长按底栏快捷呼出。',
            style: TextStyle(
              fontSize: 12.5,
              color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              height: 1.45,
              fontFamily: 'NotoSansSC',
            ),
          ),
          const SizedBox(height: 18),

          // 选项列表
          ...NavTabKey.values.map((tab) {
            // 游客模式不展示游戏选项
            if (isGuest && tab == NavTabKey.game) return const SizedBox.shrink();

            final isVisible = !_hiddenKeys.contains(tab.key);
            final isLocked = !tab.canHide;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE2E8F0),
                  width: 0.6,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(tab.icon, size: 20, color: primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tab.label,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                            if (isLocked) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.white12 : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '核心常驻',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDarkMode ? Colors.white70 : const Color(0xFF64748B),
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.description,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: isVisible,
                    activeTrackColor: primaryColor,
                    inactiveThumbColor: isDarkMode ? const Color(0xFF94A3B8) : Colors.white,
                    inactiveTrackColor: isDarkMode ? Colors.white12 : const Color(0xFFE2E8F0),
                    onChanged: isLocked ? null : (val) => _toggleTab(tab, val),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 3. 「我」页面专属的功能收纳区卡片（当存在被收纳的按钮时展示）
class StashedFeaturesCard extends StatelessWidget {
  const StashedFeaturesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: Prefs.hiddenBottomNavKeysNotifier,
      builder: (context, hiddenKeys, child) {
        final isGuest = Global.isGuest;
        final stashedTabs = NavTabKey.getStashedTabs(isGuest: isGuest, hiddenKeys: hiddenKeys);

        // 如果没有被收纳的功能，不占用「我」页面的空间，保持纯净
        if (stashedTabs.isEmpty) {
          return const SizedBox.shrink();
        }

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = Theme.of(context).primaryColor;
        final textColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
        final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: FrostedGlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部标题与管理按钮
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.apps_rounded, size: 14, color: primaryColor),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '功能收纳',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${stashedTabs.length}项已移出底栏)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: subtitleColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => NavBarCustomizationSheet.show(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: Row(
                          children: [
                            Text(
                              '定制',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: primaryColor,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 收纳的功能列表（网格或并排卡片）
                Column(
                  children: stashedTabs.map((tab) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.push(tab.routePath);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.025),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(tab.icon, size: 20, color: primaryColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tab.label,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                          fontFamily: 'NotoSansSC',
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        tab.description,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: subtitleColor,
                                          fontFamily: 'NotoSansSC',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '进入',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'NotoSansSC',
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 12,
                                        color: primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
