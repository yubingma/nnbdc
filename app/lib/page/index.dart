import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'game.dart'; // 如果是在同一个包的路径下，可以直接使用对应的文件名
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

/// 创建一个 带有状态的 Widget Index
class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  /// 固定的写法
  @override
  State<StatefulWidget> createState() => IndexPageState();
}

/// 要让主页面 Index 支持动效，要在它的定义中附加mixin类型的对象TickerProviderStateMixin
class IndexPageState extends State<IndexPage> with TickerProviderStateMixin {
  late IndexPageArgs args;
  int _currentIndex = 0; // 当前界面的索引值
  int get currentIndex => _currentIndex;
  List<NavigationIconView>? _navigationViews; // 底部图标按钮区域
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // 进入主页时强制关闭 ASR，确保状态干净
    Asr().stopAsr();

    args = Get.arguments ?? IndexPageArgs(0);
    _currentIndex = args.buttonIndex;

    /// 初始化导航图标
    _navigationViews = <NavigationIconView>[
      NavigationIconView(icon: const Icon(Icons.school), title: "学习", vsync: this),
      NavigationIconView(icon: const Icon(Icons.library_books), title: "词表", vsync: this),
      NavigationIconView(icon: const Icon(Icons.search_rounded), title: "查词", vsync: this),
      if (!Global.isGuest) NavigationIconView(icon: const Icon(Icons.sports_esports), title: "比赛", vsync: this),
      NavigationIconView(icon: const Icon(Icons.person_rounded), title: "我", vsync: this),
    ];

    // 初始化页面列表
    _pages = [
      const TodayPlanPage(),
      const WordListsPage(),
      const SearchPage(),
      if (!Global.isGuest) const GamePage(),
      const MePage(),
    ];

    // 如果是游客且请求的是原本的游戏页面索引，则重定向到词表或“我”
    if (Global.isGuest && _currentIndex == 3) {
      _currentIndex = 4; // 默认为“我”
    }
    
    // 初始化时启动选中项的动画
    int initialActualIndex = _currentIndex;
    if (Global.isGuest && _currentIndex > 3) {
      initialActualIndex = _currentIndex - 1;
    }
    _navigationViews![initialActualIndex].controller.value = 1.0;
  }

  // 创建自定义的导航栏项
  Widget _buildCustomNavItem(IconData icon, String label, int index, int actualCurrentIndex) {
    final isSelected = _currentIndex == index;
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final selectedColor = AppTheme.primaryColor;
    final unselectedColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    // 计算点击这个项对应的实际内部索引（用于动画和PageList访问）
    int actualNewIndex = index;
    if (Global.isGuest && index > 3) {
      actualNewIndex = index - 1;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_currentIndex == index) return;
          
          // 切换 Tab 时强制关闭 ASR，防止后台残留
          Asr().stopAsr();

          setState(() {
            _navigationViews![actualCurrentIndex].controller.reverse();
            _currentIndex = index;
            _navigationViews![actualNewIndex].controller.forward();
          });

          final tabState = _getTabState(index);
          if (tabState != null && tabState.isDirty) {
            Global.logger.d('[Index Manager] 检测到目标页面(index=$index)为脏数据，触发 refreshData()');
            tabState.refreshData();
          }
        },
        child: Container(
          height: 54, 
          decoration: const BoxDecoration(
            color: Colors.transparent,  
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12), 
                decoration: BoxDecoration(
                  color: isSelected ? selectedColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? selectedColor : unselectedColor,
                  size: isSelected ? 24 : 22,
                ),
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
    // 处理游客模式下的索引映射
    int actualCurrentIndex = _currentIndex;
    if (Global.isGuest && _currentIndex > 3) {
      actualCurrentIndex = _currentIndex - 1;
    }
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : Colors.white;

    final customBottomNav = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.only(
          top: 2,
          bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom * 0.5 : 4,
        ),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0),
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
      ),
    );
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: actualCurrentIndex,
            children: _pages,
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
      bottomNavigationBar: customBottomNav, // 底部工具栏
    );
  }
}
