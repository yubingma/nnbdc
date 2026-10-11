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
import 'package:nnbdc/widget/nav_tab_icon.dart';
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

  /// 底栏要同时跟着「哪些 Tab 被收进抽屉」和「今日计划那张壁纸的明暗」两处变，
  /// 合成一个 Listenable 一次订阅。
  late final Listenable _navBarSources = Listenable.merge([
    Prefs.hiddenBottomNavKeysNotifier,
    planWallpaperIsDark,
  ]);

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

  /// 底栏内容高度（不含底部安全区，安全区由底栏自己的 SafeArea 补上）
  static const double navBarContentHeight = 50;

  /// 底栏图标一律 24 网格定尺：选中态只换墨色、不换尺寸。
  /// 原先选中 24、未选中 22，来回切 Tab 时整排图标会跟着一跳一跳。
  static const double navBarIconSize = 24;

  /// 底栏图标的墨色。
  ///
  /// 今日计划页的底栏是整条透明的，图标直接压在壁纸照片上，颜色必须跟照片明暗
  /// 同进同退：暗底照片配白图标、亮底照片配深墨图标，并各带一层反向柔光描边，
  /// 否则石板灰或主题色原色会直接糊进照片里。选中态取主题色的亮档/深档，而不是
  /// 主题色原色——原色是给浅色页面底调的中间调，压在照片上要么太暗、要么太浅。
  ///
  /// [wallpaperIsDark] 为 null 表示此刻底栏底下没有照片（不在今日计划页，或今日
  /// 计划用的是「经典」无壁纸），沿用 App 主题原本的一套。
  ({Color selected, Color unselected, Shadow? shadow}) _navBarInk(
    AppThemeConfig themeConfig,
    bool? wallpaperIsDark,
  ) {
    if (wallpaperIsDark == null) {
      return (
        selected: themeConfig.primaryColor,
        unselected: themeConfig.textNeutral,
        shadow: null,
      );
    }
    if (wallpaperIsDark) {
      return (
        selected: themeConfig.primaryLightColor,
        unselected: Colors.white.withValues(alpha: 0.62),
        shadow: Shadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 5,
          offset: const Offset(0, 1),
        ),
      );
    }
    return (
      selected: themeConfig.primaryDarkColor,
      unselected: const Color(0xFF1E293B).withValues(alpha: 0.58),
      shadow: Shadow(
        color: Colors.white.withValues(alpha: 0.85),
        blurRadius: 5,
        offset: const Offset(0, 1),
      ),
    );
  }

  Widget _buildPageForTab(NavTabKey tab) {
    switch (tab) {
      case NavTabKey.study:
        // 壁纸模式下内容铺到屏幕最底部，必须把底栏占位交给页面：
        // 底栏虽然透明，却占着屏幕最底部那一整块并吞掉点击，
        // 页面不让开，"开始学习/继续学习"就会被压在底栏下面点不到。
        return TodayPlanPage(
          bottomNavReserve: navBarContentHeight + MediaQuery.viewPaddingOf(context).bottom,
        );
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
    bool? wallpaperIsDark,
  ) {
    final ink = _navBarInk(themeConfig, wallpaperIsDark);

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
          height: navBarContentHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: NavTabIcon(
            tab.icon,
            color: isSelected ? ink.selected : ink.unselected,
            size: navBarIconSize,
            shadow: ink.shadow,
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

    return ListenableBuilder(
      listenable: _navBarSources,
      builder: (context, child) {
        final hiddenKeys = Prefs.hiddenBottomNavKeysNotifier.value;
        final wallpaperIsDark = planWallpaperIsDark.value;
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

        // 今日计划页底栏完全透明（与壁纸/内容区浑然一体），其他页面保留透光磨砂
        final isStudyTab = activeTab == NavTabKey.study;

        final navBg = isStudyTab
            ? Colors.transparent
            : (isDarkMode
                ? const Color(0x66101E1A)
                : Colors.white.withValues(alpha: 0.18));
        final borderTopColor = isStudyTab
            ? Colors.transparent
            : (isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05));

        final navContent = Container(
          decoration: BoxDecoration(
            color: navBg,
            border: isStudyTab
                ? null
                : Border(top: BorderSide(color: borderTopColor, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: navBarContentHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: visibleTabs.map((tab) {
                  return _buildCustomNavItem(
                    tab,
                    tab == activeTab,
                    themeConfig,
                    // 只有今日计划页的底栏底下是照片，其余页面底栏带磨砂底，跟主题走
                    isStudyTab ? wallpaperIsDark : null,
                  );
                }).toList(),
              ),
            ),
          ),
        );

        final customBottomNav = ClipRect(
          child: GestureDetector(
            onLongPress: () {
              StashedNavMenuDialog.show(context);
            },
            child: isStudyTab
                ? navContent
                : BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                    child: navContent,
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
