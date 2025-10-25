import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/page/before_bdc.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'game.dart'; // 如果是在同一个包的路径下，可以直接使用对应的文件名
import 'me.dart';
import 'nav_icon_view.dart';
import '../state.dart';

class IndexPageArgs {
  late int buttonIndex;

  IndexPageArgs(this.buttonIndex);
}

/// 创建一个 带有状态的 Widget Index
class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  /// 固定的写法
  @override
  State<StatefulWidget> createState() => _IndexPageState();
}

/// 要让主页面 Index 支持动效，要在它的定义中附加mixin类型的对象TickerProviderStateMixin
class _IndexPageState extends State<IndexPage> with TickerProviderStateMixin {
  late IndexPageArgs args;
  int _currentIndex = -1; // 当前界面的索引值
  List<NavigationIconView>? _navigationViews; // 底部图标按钮区域
  List<StatefulWidget?>? _pageList; // 用来存放我们的图标对应的页面
  StatefulWidget? _currentPage; // 当前的显示页面

  /// 定义一个触发界面重建的方法，用于响应外部状态变化
  /// 这里的空setState是有意的，目的是触发Widget树重建
  void _rebuild() {
    setState(() {
      // 空的setState用于触发重建，这是有意的设计
    });
  }

  @override
  void initState() {
    super.initState();
    args = Get.arguments ?? IndexPageArgs(4);
    _currentIndex = args.buttonIndex;

    /// 初始化导航图标
    _navigationViews = <NavigationIconView>[
      NavigationIconView(icon: const Icon(Icons.school), title: "学习", vsync: this),
      // vsync 默认属性和参数
      NavigationIconView(icon: const Icon(Icons.library_books), title: "词表", vsync: this),
      NavigationIconView(icon: const Icon(Icons.search_rounded), title: "查词", vsync: this),
      NavigationIconView(icon: const Icon(Icons.sports_esports), title: "比赛", vsync: this),
      NavigationIconView(icon: const Icon(Icons.person_rounded), title: "我", vsync: this),
    ];

    /// 给每一个按钮区域加上监听
    for (NavigationIconView view in _navigationViews!) {
      view.controller.addListener(_rebuild);
    }

    /// 将我们 bottomBar 上面的按钮图标对应的页面存放起来，方便我们在点击的时候
    _pageList = <StatefulWidget?>[null, const WordListsPage(), const SearchPage(), const GamePage(), const MePage()];
    // 初始页面处理
    if (_currentIndex == 0) {
      _currentPage = BeforeBdcPage();
    } else {
      _currentPage = _pageList![_currentIndex];
    }
  }

  // 创建自定义的导航栏项
  Widget _buildCustomNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final selectedColor = AppTheme.primaryColor;
    final unselectedColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _navigationViews![_currentIndex].controller.reverse();
            _currentIndex = index;
            _navigationViews![_currentIndex].controller.forward();
            // 特殊处理学习页面，每次都创建新实例
            if (index == 0) {
              _currentPage = BeforeBdcPage();
            } else {
              _currentPage = _pageList![_currentIndex];
            }
          });
        },
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? selectedColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? selectedColor : unselectedColor,
                  size: isSelected ? 26 : 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? selectedColor : unselectedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w400, // 保持一致的字体粗细，避免变糊
                  fontFamily: 'NotoSansSC',
                  height: 1.4,
                  letterSpacing: 0.4, // 统一字间距
                ),
                textScaler: const TextScaler.linear(1.0),
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
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : Colors.white;

    /// 创建自定义的底部导航栏
    final customBottomNav = Container(
      height: 65,
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
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCustomNavItem(Icons.school, "学习", 0),
            _buildCustomNavItem(Icons.library_books, "词表", 1),
            _buildCustomNavItem(Icons.search_rounded, "查词", 2),
            _buildCustomNavItem(Icons.sports_esports, "比赛", 3),
            _buildCustomNavItem(Icons.person_rounded, "我", 4),
          ],
        ),
      ),
    );
    return Scaffold(
      body: Center(child: _currentPage // 动态的展示我们当前的页面
          ),
      bottomNavigationBar: customBottomNav, // 底部工具栏
    );
  }
}
