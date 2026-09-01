import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'game.dart'; 
import 'me.dart';
import 'nav_icon_view.dart';
import '../global.dart';
import '../state.dart';
import 'package:nnbdc/event/events.dart';
import '../util/asr.dart';

class IndexPageArgs {
  late int buttonIndex;

  IndexPageArgs(this.buttonIndex);
}

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<StatefulWidget> createState() => IndexPageState();
}

class IndexPageState extends State<IndexPage> with TickerProviderStateMixin {
  int _currentIndex = 0; 
  int? _lastProcessedIndexFromExtra;
  int get currentIndex => _currentIndex;
  List<NavigationIconView>? _navigationViews; 

  @override
  void initState() {
    super.initState();
    // 进入主页时强制关闭 ASR，确保状态干净
    Asr().stopMicrophone();

    /// 初始化导航图标
    _navigationViews = <NavigationIconView>[
      NavigationIconView(icon: const Icon(Icons.school), title: "学习", vsync: this),
      NavigationIconView(icon: const Icon(Icons.library_books), title: "词表", vsync: this),
      NavigationIconView(icon: const Icon(Icons.search_rounded), title: "查词", vsync: this),
      if (!Global.isGuest) NavigationIconView(icon: const Icon(Icons.sports_esports), title: "比赛", vsync: this),
      NavigationIconView(icon: const Icon(Icons.person_rounded), title: "我", vsync: this),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从 GoRouter extra 中提取参数
    final extra = GoRouterState.of(context).extra;
    final indexFromExtra = (extra is IndexPageArgs) ? extra.buttonIndex : 0;

    // 只有当 extra 中的索引发生变化时，才更新当前索引和动画
    // 这样可以避免从子页面返回时，因为 extra 没变（或者是默认值）而导致索引被重置
    if (_lastProcessedIndexFromExtra == null || _lastProcessedIndexFromExtra != indexFromExtra) {
      _lastProcessedIndexFromExtra = indexFromExtra;
      _currentIndex = indexFromExtra;

      // 如果是游客且请求的是原本的游戏页面索引，则重定向到词表或“我”
      if (Global.isGuest && _currentIndex == 3) {
        _currentIndex = 4; // 默认为“我”
      }
      
      // 处理动态增加/减少 Tab 后的索引映射
      int actualIndex = _currentIndex;
      if (Global.isGuest && _currentIndex > 3) {
        actualIndex = _currentIndex - 1;
      }

      // 初始化时启动选中项的动画
      if (_navigationViews != null) {
        for (int i = 0; i < _navigationViews!.length; i++) {
          _navigationViews![i].controller.value = (i == actualIndex) ? 1.0 : 0.0;
        }
      }
    }
  }

  Widget _buildCustomNavItem(IconData icon, String label, int index, int actualCurrentIndex) {
    final isSelected = _currentIndex == index;
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final selectedColor = AppTheme.primaryColor;
    final unselectedColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    int actualNewIndex = index;
    if (Global.isGuest && index > 3) {
      actualNewIndex = index - 1;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_currentIndex == index) return;
          Asr().stopMicrophone();

          setState(() {
            _navigationViews![actualCurrentIndex].controller.reverse();
            _currentIndex = index;
            _navigationViews![actualNewIndex].controller.forward();
          });

          final tabState = _getTabState(index);
          if (tabState != null && tabState.isDirty) {
            tabState.refreshData();
          }
        },
        child: Container(
          height: 54, 
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12), 
                decoration: BoxDecoration(
                  color: isSelected ? selectedColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isSelected ? selectedColor : unselectedColor, size: isSelected ? 24 : 22),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? selectedColor : unselectedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                  height: 1.2,
                  letterSpacing: 0.4,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  RefreshableTab? _getTabState(int index) {
    if (index == 1) return WordListsPageState.instance;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayPlanPage(),
      const WordListsPage(),
      const SearchPage(),
      if (!Global.isGuest) const GamePage(),
      const MePage(),
    ];

    int actualCurrentIndex = _currentIndex;
    if (Global.isGuest && _currentIndex > 3) {
      actualCurrentIndex = _currentIndex - 1;
    }
    actualCurrentIndex = actualCurrentIndex.clamp(0, pages.isEmpty ? 0 : pages.length - 1);

    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final navBg = isDarkMode ? const Color(0xFF101E1A).withValues(alpha: 0.90) : Colors.white.withValues(alpha: 0.90);
    final borderTopColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0x1418BA7C);

    final customBottomNav = Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: borderTopColor, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.only(
          top: 2,
          bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom * 0.5 : 4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCustomNavItem(Icons.school, "学习", 0, actualCurrentIndex),
            _buildCustomNavItem(Icons.library_books, "词表", 1, actualCurrentIndex),
            _buildCustomNavItem(Icons.search_rounded, "查词", 2, actualCurrentIndex),
            if (!Global.isGuest) _buildCustomNavItem(Icons.sports_esports, "比赛", 3, actualCurrentIndex),
            _buildCustomNavItem(Icons.person_rounded, "我", 4, actualCurrentIndex),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(index: actualCurrentIndex, children: pages),
          ValueListenableBuilder<int>(
            valueListenable: Global.activeRequestCount,
            builder: (context, count, child) {
              if (count > 0) {
                return Positioned(
                  top: 0, left: 0, right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor.withValues(alpha: 0.8)),
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
  }
}
