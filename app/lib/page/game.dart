import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/api.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

import '../api/vo.dart';
import '../global.dart';
import '../theme/app_theme.dart';
import '../util/error_handler.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<StatefulWidget> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  GetGameHallDataResult? gameHallDataResult;
  final Map<String, bool> _expandedGroups = {};
  String? errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      errorMessage = null;
    });

    try {
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

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'getGameHallData', showToast: false);
      if (mounted) {
        setState(() {
          _isLoading = false;
          errorMessage = '网络连接失败，请检查设置后重试';
        });
      }
    }
  }

  Future<int?> _promptRoomId(BuildContext context) async {
    final controller = TextEditingController();
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white12 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5B7A75);
    final subtleBg = isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF0F6F3);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;

    return showDialog<int>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.5 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0x2660A5FA) : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        size: 20,
                        color: isDarkMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '输入房间号',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: textMain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: subtleBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder, width: 1),
                  ),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textMain, fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: '请输入 3~6 位房间号',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.7), fontSize: 13.5),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: subtleBg,
                            foregroundColor: textSub,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(21),
                              side: BorderSide(color: cardBorder, width: 1),
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGreen,
                            foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                            elevation: 2,
                            shadowColor: accentGreen.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                          ),
                          onPressed: () {
                            final text = controller.text.trim();
                            final id = int.tryParse(text);
                            Navigator.of(ctx).pop(id);
                          },
                          child: const Text('进入房间', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGameRuleDialog(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white12 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5B7A75);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.5 : 0.12),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(Icons.help_outline_rounded, size: 20, color: accentGreen),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '对战玩法规则',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: textMain,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: textSub),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildRuleItem('1', '实时单词消消乐对战，匹配实力相当的在线学友。', textMain, textSub),
                const SizedBox(height: 10),
                _buildRuleItem('2', '根据上方掉落的英文单词，快速点击匹配正确的中文释义方块消除得分。', textMain, textSub),
                const SizedBox(height: 10),
                _buildRuleItem('3', '连击可触发攻击方块，加速对手方块堆积，先堆满顶部者判负。', textMain, textSub),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentGreen,
                      foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('我知道了', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRuleItem(String index, String text, Color textMain, Color textSub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: textSub.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            index,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMain),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: textSub, height: 1.45, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSubColor = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);

    if (Global.isGuest) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.sports_esports_rounded, size: 36, color: accentGreen),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '单词PK竞技场',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '实时对战功能需登录后方可体验，快来与全网学友一较高下吧！',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: textSubColor, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 160,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => context.go('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                        elevation: 2,
                        shadowColor: accentGreen.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text('前往登录', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. 顶部大标题栏
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '单词PK大厅',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '实时对战 · 词汇巅峰竞速',
                          style: TextStyle(
                            color: textSubColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showGameRuleDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
                          border: Border.all(color: cardBorder, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.help_outline_rounded, size: 14, color: textSubColor),
                            const SizedBox(width: 4),
                            Text(
                              '玩法规则',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: textSubColor,
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

            // 2. 主内容区域
            SliverToBoxAdapter(
              child: errorMessage != null
                  ? Container(
                      height: 360,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 56, color: textSubColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 14),
                          Text(
                            errorMessage!,
                            style: TextStyle(color: textSubColor, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: loadData,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('重新加载', style: TextStyle(fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentGreen,
                              foregroundColor: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : (_isLoading || gameHallDataResult == null
                      ? SizedBox(
                          height: 320,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(accentGreen),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '正在加载对战大厅...',
                                  style: TextStyle(color: textSubColor, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...gameHallDataResult!.hallGroups.map((group) => _buildGroupCard(group, isDarkMode)),
                            ],
                          ),
                        )),
            ),
          ],
        ),
      ),
    );
  }

  /// 大厅分组折叠卡片
  Widget _buildGroupCard(HallGroupVo group, bool isDarkMode) {
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);
    final pillBg = isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF0F6F3);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;

    // 默认展开
    _expandedGroups[group.groupName] ??= true;
    final isExpanded = _expandedGroups[group.groupName]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组标题行（点击可展开/折叠）
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(20),
              bottom: Radius.circular(isExpanded ? 0 : 20),
            ),
            onTap: () {
              setState(() {
                _expandedGroups[group.groupName] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(
                          color: accentGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        group.groupName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textMain,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: Text(
                          '${group.gameHalls.length} 个场次',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: textSub),
                        ),
                      ),
                    ],
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.arrow_forward_ios_rounded, size: 13, color: textSub.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),

          // 组内各场次
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: group.gameHalls.map((hall) => _buildHallItem(hall, isDarkMode)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// 单个大厅竞技场项目
  Widget _buildHallItem(GameHallVo hall, bool isDarkMode) {
    final itemBg = isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF0F6F3);
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Row(
        children: [
          // 左侧图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: cardBorder, width: 0.8),
            ),
            child: Icon(Icons.sports_esports_rounded, size: 18, color: accentGreen),
          ),
          const SizedBox(width: 10),

          // 中间大厅信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hall.hallName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${hall.userCount} 人在线对战',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSub,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 右侧操作：进房 + 开房 + 匹配
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final int? roomId = await _promptRoomId(context);
                  if (roomId != null && mounted) {
                    context.push('/russia', extra: [
                      hall,
                      null,
                      {'joinRoomId': roomId.toString()}
                    ]);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder, width: 1),
                  ),
                  child: Text(
                    '进房',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: textSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push('/russia', extra: [
                  hall,
                  null,
                  {'mode': 'createPrivate'}
                ]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder, width: 1),
                  ),
                  child: Text(
                    '开房',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: textSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push('/russia', extra: [hall, null]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentGreen,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: accentGreen.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '匹配',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
