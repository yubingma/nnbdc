import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

import '../api/vo.dart';
import '../theme/app_theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<StatefulWidget> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  static const double leftPadding = 0;
  static const double rightPadding = 0;
  GetGameHallDataResult? gameHallDataResult;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  // 辅助：小按钮与输入房号
  Widget _buildSmallActionButton({required String label, required IconData icon, required VoidCallback onTap, required bool enabled}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = enabled ? (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF2F4F7)) : Colors.grey[300];
    final iconColor = enabled ? AppTheme.primaryColor : Colors.grey;
    final textColor = enabled ? (isDark ? Colors.white : const Color(0xFF2C3E50)) : Colors.grey;

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _promptRoomId(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('输入房间号', textScaler: TextScaler.linear(1.0)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '例如：123'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消', textScaler: TextScaler.linear(1.0))),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                final id = int.tryParse(text);
                Navigator.of(ctx).pop(id);
              },
              child: const Text('确定', textScaler: TextScaler.linear(1.0)),
            ),
          ],
        );
      },
    );
    return result;
  }

  // 添加折叠状态管理
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    gameHallDataResult = await Api.client.getGameHallData();

    // 把Hall以名字为key组织为Hash map
    var hallsByName = HashMap<String, HallVo>();
    for (var hall in gameHallDataResult!.halls) {
      hallsByName[hall.name] = hall;
    }

    // 计算大厅分组及每个大厅中的在线人数
    for (var hallGroup in gameHallDataResult!.hallGroups) {
      var userCount = 0;
      for (var gameHall in hallGroup.gameHalls) {
        var hall = hallsByName[gameHall.hallName];
        gameHall.userCount = hall == null ? 0 : hall.userCount;
        userCount += gameHall.userCount;
      }
      hallGroup.userCount = userCount;
    }

    setState(() {
      // 游戏大厅数据已加载完成，触发UI更新
    });
  }

  // 获取在线状态信息
  ({Color color, String text, IconData icon}) _getStatusInfo(int userCount) {
    if (userCount == 0) {
      return (color: Colors.grey, text: '空闲', icon: Icons.schedule);
    } else if (userCount < 50) {
      return (color: Colors.green, text: '畅通', icon: Icons.signal_cellular_4_bar);
    } else if (userCount < 100) {
      return (color: Colors.orange, text: '繁忙', icon: Icons.signal_cellular_alt);
    } else {
      return (color: Colors.red, text: '拥挤', icon: Icons.signal_cellular_off);
    }
  }

  Widget _buildOnlineIndicator(int userCount) {
    final status = _getStatusInfo(userCount);
    final hasUsers = userCount > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: hasUsers ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: status.color,
                  shape: BoxShape.circle,
                  boxShadow: hasUsers ? [
                    BoxShadow(
                      color: status.color.withValues(alpha: 0.6),
                      blurRadius: 2,
                      spreadRadius: 0.5,
                    ),
                  ] : null,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        Icon(status.icon, size: 12, color: status.color),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            status.text,
            textScaler: TextScaler.linear(1.0),
            style: TextStyle(
              color: status.color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // 构建游戏图标
  Widget _buildGameIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.gradientStartColor, AppTheme.gradientEndColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.sports_esports,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  // 构建大厅信息
  Widget _buildHallInfo(GameHallVo hall, Color textColor, Color? subtitleColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hall.hallName,
            textScaler: TextScaler.linear(1.0),
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.4,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.people, size: 16, color: subtitleColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${hall.userCount} 人在线',
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _buildOnlineIndicator(hall.userCount)),
            ],
          ),
        ],
      ),
    );
  }

  // 构建匹配按钮
  Widget _buildMatchButton(GameHallVo hall) {
    final hasUsers = hall.userCount > 0;
    return InkWell(
      onTap: () => Get.toNamed('/russia', arguments: [hall, null]),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasUsers 
              ? [const Color(0xFF4A90E2), const Color(0xFF357ABD)] 
              : [Colors.grey[400]!, Colors.grey[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: hasUsers ? [
            BoxShadow(
              color: const Color(0xFF4A90E2).withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              '匹配',
              textScaler: TextScaler.linear(1.0),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.3,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建操作按钮行
  Widget _buildActionButtons(GameHallVo hall) {
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildSmallActionButton(
              label: '开房间',
              icon: Icons.meeting_room_outlined,
              onTap: () => Get.toNamed('/russia', arguments: [hall, null, {'mode': 'createPrivate'}]),
              enabled: true,
            ),
            const SizedBox(width: 8),
            _buildSmallActionButton(
              label: '进房间',
              icon: Icons.vpn_key,
              onTap: () async {
                final roomId = await _promptRoomId(context);
                if (roomId != null) {
                  Get.toNamed('/russia', arguments: [hall, null, {'joinRoomId': roomId}]);
                }
              },
              enabled: true,
            ),
            const SizedBox(width: 8),
            _buildMatchButton(hall),
          ],
        ),
      ),
    );
  }

  Widget _buildHallCard(GameHallVo hall, bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);
    final subtitleColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cardColor, isDarkMode ? const Color(0xFF363636) : const Color(0xFFF8F9FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hall.userCount > 0 
            ? AppTheme.primaryColor.withValues(alpha: 0.3) 
            : (isDarkMode ? Colors.grey[700]! : Colors.grey[200]!),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildGameIcon(),
                const SizedBox(width: 16),
                _buildHallInfo(hall, textColor, subtitleColor),
              ],
            ),
            const SizedBox(height: 14),
            _buildActionButtons(hall),
          ],
        ),
      ),
    );
  }

  // 构建组标题左侧装饰条
  Widget _buildGroupTitleDecorator(Color accentColor) {
    return Container(
      width: 4,
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor, accentColor.withValues(alpha: 0.6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // 构建在线人数指示器（动画版本）
  Widget _buildGroupUserCountBadge(HallGroupVo group, Color accentColor) {
    final hasUsers = group.userCount > 0;
    final badgeColor = hasUsers ? accentColor : Colors.grey;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasUsers
            ? [accentColor.withValues(alpha: 0.15), accentColor.withValues(alpha: 0.08)]
            : [Colors.grey.withValues(alpha: 0.1), Colors.grey.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasUsers ? accentColor.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: hasUsers ? [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: hasUsers ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    boxShadow: hasUsers ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.6),
                        blurRadius: 3,
                        spreadRadius: 1,
                      ),
                    ] : null,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Icon(Icons.people, size: 18, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            '${group.userCount}',
            textScaler: TextScaler.linear(1.0),
            style: TextStyle(
              color: badgeColor,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontFamily: 'NotoSansSC',
              height: 1.3,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '在线',
            textScaler: TextScaler.linear(1.0),
            style: TextStyle(
              color: hasUsers ? accentColor.withValues(alpha: 0.8) : Colors.grey.withValues(alpha: 0.7),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.3,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // 构建组标题
  Widget _buildGroupTitle(HallGroupVo group, Color textColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        children: [
          _buildGroupTitleDecorator(accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.groupName,
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.4,
                letterSpacing: 0.6,
              ),
            ),
          ),
          _buildGroupUserCountBadge(group, accentColor),
        ],
      ),
    );
  }

  Widget _buildGroupCard(HallGroupVo group, bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F7FA);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);
    final accentColor = isDarkMode ? const Color(0xFF4A90E2) : const Color(0xFF357ABD);

    // 初始化折叠状态为false（默认折叠）
    _expandedGroups[group.groupName] ??= false;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: _expandedGroups[group.groupName]!,
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedGroups[group.groupName] = expanded;
          });
        },
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: accentColor,
        collapsedIconColor: accentColor,
        title: _buildGroupTitle(group, textColor, accentColor),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 8),
            child: Column(
              children: group.gameHalls.map((hall) => _buildHallCard(hall, isDarkMode)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget renderHallGroups() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Column(
      children: gameHallDataResult!.hallGroups.map((group) => _buildGroupCard(group, isDarkMode)).toList(),
    );
  }

  // 构建AppBar图标
  Widget _buildAppBarIcon() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.sports_esports,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  // 构建AppBar标题
  Widget _buildAppBarTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '单词PK大厅',
          textScaler: TextScaler.linear(1.0),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            height: 1.5,
            letterSpacing: 1.5,
          ),
        ),
        Text(
          '挑战你的词汇极限',
          textScaler: TextScaler.linear(1.0),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w300,
            height: 1.5,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // 构建AppBar背景
  Widget _buildAppBarBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4A90E2),
            Color(0xFF357ABD),
            Color(0xFF2E5F8A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAppBarIcon(),
                const SizedBox(width: 12),
                _buildAppBarTitle(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建加载指示器
  Widget _buildLoadingIndicator(Color textColor) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF4A90E2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载游戏大厅...',
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.3,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF0F2F5);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [
                    const Color(0xFF121212),
                    const Color(0xFF1A1A1A),
                    const Color(0xFF121212),
                  ]
                : [
                    const Color(0xFFF0F2F5),
                    const Color(0xFFE8ECF1),
                    const Color(0xFFF0F2F5),
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 88,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildAppBarBackground(),
              ),
            ),
            SliverToBoxAdapter(
              child: gameHallDataResult == null
                  ? _buildLoadingIndicator(textColor)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 24),
                      child: renderHallGroups(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
