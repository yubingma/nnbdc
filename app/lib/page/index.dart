import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/model/nav_tab_config.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/widget/nav_stash_widgets.dart';
import 'package:provider/provider.dart';

import 'game.dart'; 
import 'me.dart';
import '../global.dart';
import '../state.dart';
import '../util/asr.dart';

class IndexPageArgs {
  final int buttonIndex;
  final NavTabKey? targetTab;

  IndexPageArgs(this.buttonIndex)
      : targetTab = NavTabKey.fromLegacyIndex(buttonIndex);

  IndexPageArgs.byTab(this.targetTab)
      : buttonIndex = targetTab?.index ?? 0;
}

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<StatefulWidget> createState() => IndexPageState();
}

class IndexPageState extends State<IndexPage> with TickerProviderStateMixin {
  NavTabKey _currentTab = NavTabKey.study;
  NavTabKey? _lastProcessedTabFromExtra;

  int get currentIndex {
    final visibleTabs = NavTabKey.getVisibleTabs(
      isGuest: Global.isGuest,
      hiddenKeys: Prefs.hiddenBottomNavKeys,
    );
    final idx = visibleTabs.indexOf(_currentTab);
    return idx >= 0 ? idx : 0;
  }

  @override
  void initState() {
    super.initState();
    // 进入主页时强制关闭 ASR，确保状态干净
    Asr().stopMicrophone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从 GoRouter extra 中提取参数
    final extra = GoRouterState.of(context).extra;
    NavTabKey targetTab = NavTabKey.study;

    if (extra is IndexPageArgs) {
      targetTab = extra.targetTab ?? NavTabKey.fromLegacyIndex(extra.buttonIndex);
    }

    // 只有当 extra 中的目标 Tab 发生变化时，才更新当前选中项
    if (_lastProcessedTabFromExtra == null || _lastProcessedTabFromExtra != targetTab) {
      _lastProcessedTabFromExtra = targetTab;
      _selectTab(targetTab);
    }
  }

  void _selectTab(NavTabKey tab) {
    final isGuest = Global.isGuest;
    final hiddenKeys = Prefs.hiddenBottomNavKeys;
    final visibleTabs = NavTabKey.getVisibleTabs(isGuest: isGuest, hiddenKeys: hiddenKeys);

    // 如果目标 Tab 在当前底栏中可见，直接选中
    if (visibleTabs.contains(tab)) {
      setState(() {
        _currentTab = tab;
      });
      _checkRefreshTab(tab);
    } else {
      // 如果目标 Tab 已被用户隐藏/收纳到「我」页面（例如比赛）：
      // 切换到与该功能最接近的宿主（优先“我”或默认主页），并通过独立路由打开对应页面
      if (tab.routePath.isNotEmpty && tab.routePath != '/index') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.push(tab.routePath);
          }
        });
      }
      setState(() {
        _currentTab = visibleTabs.contains(NavTabKey.me) ? NavTabKey.me : visibleTabs.first;
      });
    }
  }

  void _checkRefreshTab(NavTabKey tab) {
    if (tab == NavTabKey.wordLists) {
      final tabState = WordListsPageState.instance;
      if (tabState != null && tabState.isDirty) {
        tabState.refreshData();
      }
    } else if (tab == NavTabKey.me) {
      final tabState = MePageState.instance;
      if (tabState != null && tabState.isDirty) {
        tabState.refreshData();
      }
    }
  }

  Widget _buildPageForTab(NavTabKey tab) {
    switch (tab) {
      case NavTabKey.study:
        return const TodayPlanPage();
      case NavTabKey.wordLists:
        return const WordListsPage();
      case NavTabKey.search:
        return const SearchPage();
      case NavTabKey.game:
        return const GamePage();
      case NavTabKey.me:
        return const MePage();
    }
  }

  Widget _buildCustomNavItem(
    NavTabKey tab,
    bool isSelected,
    AppThemeConfig themeConfig,
  ) {
    final selectedColor = themeConfig.primaryColor;
    final unselectedColor = themeConfig.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_currentTab == tab) return;
          Asr().stopMicrophone();
          setState(() {
            _currentTab = tab;
          });
          _checkRefreshTab(tab);
        },
        onLongPress: () {
          // 长按任意底栏项，弹出功能收纳快捷菜单
          StashedNavMenuDialog.show(context);
        },
        child: Container(
          height: 54,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tab.icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: isSelected ? 24 : 22,
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: TextStyle(
                  color: isSelected ? selectedColor : unselectedColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                  height: 1.2,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    return ValueListenableBuilder<List<String>>(
      valueListenable: Prefs.hiddenBottomNavKeysNotifier,
      builder: (context, hiddenKeys, child) {
        final isGuest = Global.isGuest;
        final visibleTabs = NavTabKey.getVisibleTabs(
          isGuest: isGuest,
          hiddenKeys: hiddenKeys,
        );

        // 如果当前选中的 tab 被移出了底栏，自动回退到第一个或“我”
        NavTabKey activeTab = _currentTab;
        if (!visibleTabs.contains(activeTab)) {
          activeTab = visibleTabs.contains(NavTabKey.study) ? NavTabKey.study : visibleTabs.first;
        }

        final actualCurrentIndex = visibleTabs.indexOf(activeTab).clamp(
              0,
              visibleTabs.isEmpty ? 0 : visibleTabs.length - 1,
            );

        // 呼吸级超薄透光磨砂
        final navBg = isDarkMode
            ? const Color(0x66101E1A)
            : Colors.white.withValues(alpha: 0.18);
        final borderTopColor = isDarkMode
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05);

        final customBottomNav = ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: GestureDetector(
              onLongPress: () {
                StashedNavMenuDialog.show(context);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: navBg,
                  border: Border(top: BorderSide(color: borderTopColor, width: 0.5)),
                ),
                child: SafeArea(
                  top: false,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: visibleTabs.map((tab) {
                        return _buildCustomNavItem(
                          tab,
                          tab == activeTab,
                          themeConfig,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              IndexedStack(
                index: actualCurrentIndex,
                children: visibleTabs.map(_buildPageForTab).toList(),
              ),
              ValueListenableBuilder<int>(
                valueListenable: Global.activeRequestCount,
                builder: (context, count, child) {
                  if (count > 0) {
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor.withValues(alpha: 0.8),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          bottomNavigationBar: customBottomNav,
        );
      },
    );
  }
}
