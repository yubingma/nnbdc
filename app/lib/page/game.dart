import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/api.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';
import '../theme/app_theme_background.dart';
import '../widget/frosted_glass_card.dart';
import '../widget/page_back_button.dart';
import '../util/error_handler.dart';
import '../util/toast_util.dart';

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

  /// 当前选中的游戏类型：'bubble'（戳泡泡）、'brick'（削砖块）、'monster'（打哭小馋怪）
  String _selectedGame = 'bubble';

  String get _targetGameRoute =>
      _selectedGame == 'brick' ? '/brick' : '/russia';

  /// 用户当前选中的对战特训词书
  Dict? _selectedTrainingDict;

  /// 用户正在学习的全部词书列表
  List<Dict> _userLearningDicts = [];

  /// 用户自定义/自建词书列表
  List<Dict> _userCustomDicts = [];

  @override
  void initState() {
    super.initState();
    loadData();
    _loadUserTrainingDicts();
  }

  Future<void> _loadUserTrainingDicts() async {
    final user = Global.getLoggedInUser();
    if (user == null) return;
    try {
      final db = MyDatabase.instance;
      // 1. 获取当前用户正在学习的书桌词书
      final learningRecords =
          await db.learningDictsDao.getLearningDictsOfUser(user.id);
      final dictIds = learningRecords.map((e) => e.dictId).toSet();

      final allDicts = await db.select(db.dicts).get();
      final dictMap = {for (final d in allDicts) d.id: d};
      final loadedLearningDicts = <Dict>[];
      for (final id in dictIds) {
        final d = dictMap[id];
        if (d != null) {
          loadedLearningDicts.add(d);
        }
      }

      // 2. 获取当前用户自身的所有词单（包括生词本、已掌握、用户自建词单，严格限定 ownerId == user.id，防止访客空词书污染）
      final userOwnedDicts = await (db.select(db.dicts)
            ..where((d) => d.ownerId.equals(user.id)))
          .get();
      userOwnedDicts.sort((a, b) {
        if (a.name == '生词本') return -1;
        if (b.name == '生词本') return 1;
        if (a.name == '已掌握') return -1;
        if (b.name == '已掌握') return 1;
        return b.createTime.compareTo(a.createTime);
      });

      // 3. 自定义分组排除已经在「在学列表」里的词书（确保上下两组绝不重复展示同一本词书）
      final customRecords =
          userOwnedDicts.where((d) => !dictIds.contains(d.id)).toList();

      if (mounted) {
        setState(() {
          _userLearningDicts = loadedLearningDicts;
          _userCustomDicts = customRecords;
          if (_selectedTrainingDict == null ||
              (!_userLearningDicts
                      .any((d) => d.id == _selectedTrainingDict!.id) &&
                  !_userCustomDicts
                      .any((d) => d.id == _selectedTrainingDict!.id))) {
            if (_userLearningDicts.isNotEmpty) {
              _selectedTrainingDict = _userLearningDicts.first;
            } else if (_userCustomDicts.isNotEmpty) {
              _selectedTrainingDict = _userCustomDicts.first;
            }
          }
        });
      }
    } catch (e) {
      Global.logger.w('加载特训词书失败: $e');
    }
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
      ErrorHandler.handleNetworkError(e, stackTrace,
          api: 'getGameHallData', showToast: false);
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
    final themeStyle = context.read<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final cardBorder = themeConfig.cardBorder;
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final subtleBg = themeConfig.subtleBg;
    final accentColor = themeConfig.primaryColor;

    return showDialog<int>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: FrostedGlassCard(
            borderRadius: 22,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
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
                        color: subtleBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        size: 20,
                        color: accentColor,
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
                const SizedBox(height: 14),
                Text(
                  '请输入好友创建的数字房间号以进入专属对战房间：',
                  style: TextStyle(fontSize: 12.5, color: textSub, height: 1.4),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: subtleBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder, width: 1),
                  ),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textMain,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: '如：1024',
                      hintStyle: TextStyle(
                        color: textSub.withValues(alpha: 0.6),
                        fontSize: 14,
                        letterSpacing: 0,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cardBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('取消',
                              style: TextStyle(
                                  color: textSub, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: themeStyle.isDark
                                ? const Color(0xFF0B1714)
                                : Colors.white,
                            elevation: 2,
                            shadowColor: accentColor.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21)),
                          ),
                          onPressed: () {
                            final text = controller.text.trim();
                            final id = int.tryParse(text);
                            Navigator.of(ctx).pop(id);
                          },
                          child: const Text('进入房间',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
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

  @override
  Widget build(BuildContext context) {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    final textColor = themeConfig.textPrimary;
    final textSubColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    // 本页既内嵌在首页底栏，也会被「我」页面的功能收纳入口 push 成独立路由；
    // 只有独立打开时才有可返回的上一页，此时补出返回箭头。
    final canPop = Navigator.of(context).canPop();

    if (Global.isGuest) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AppThemeBackground(
                themeStyle: themeStyle,
                config: PageVibrancy.game,
              ),
            ),
            SafeArea(
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
                          color: themeConfig.subtleBg,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(Icons.sports_esports_rounded,
                            size: 36, color: accentColor),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '单词PK竞技场',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: textColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '实时对战功能需登录后方可体验，快来与全网学友一较高下吧！',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: textSubColor, height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 160,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => context.go('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: isDarkMode
                                ? const Color(0xFF0B1714)
                                : Colors.white,
                            elevation: 2,
                            shadowColor: accentColor.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22)),
                          ),
                          child: const Text('前往登录',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AppThemeBackground(
              themeStyle: themeStyle,
              config: PageVibrancy.game,
            ),
          ),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
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
                            Row(
                              children: [
                                if (canPop) ...[
                                  PageBackButton(color: textColor),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  '单词乐园',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '趣味对战 · 闯关竞速',
                              style: TextStyle(
                                color: textSubColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 1.5 游戏模式选择卡片（精选三款游戏）
                SliverToBoxAdapter(
                  child: _buildGameShowcase(themeConfig),
                ),

                // 1.6 选中游戏的专属玩法说明大卡片（三款游戏保持完全对称统一）
                SliverToBoxAdapter(
                  child: _buildSelectedGameShowcase(themeConfig),
                ),

                // 1.7 针对性强化的「自选词书专属特训场」（三款游戏均支持自定义与在学词书精准特训/对战）
                SliverToBoxAdapter(
                  child: _buildCurrentDictSection(themeConfig),
                ),

                // 2. 主内容区域（多人房间列表仅在戳泡泡和削砖块模式展示）
                if (_selectedGame != 'monster')
                  SliverToBoxAdapter(
                    child: errorMessage != null
                        ? Container(
                            height: 360,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off_rounded,
                                    size: 56,
                                    color: textSubColor.withValues(alpha: 0.5)),
                                const SizedBox(height: 14),
                                Text(
                                  errorMessage!,
                                  style: TextStyle(
                                      color: textSubColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: loadData,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('重新加载',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: isDarkMode
                                        ? const Color(0xFF0B1714)
                                        : Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(18)),
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                accentColor),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        '正在加载对战大厅...',
                                        style: TextStyle(
                                            color: textSubColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...gameHallDataResult!.hallGroups.map(
                                        (group) => _buildGroupCard(
                                            group, themeConfig)),
                                  ],
                                ),
                              )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 游戏模式选择卡片栏（对标极简高级感规范，三款游戏平铺选择）
  Widget _buildGameShowcase(AppThemeConfig themeConfig) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          // 1. 戳泡泡（PVP 对战）
          Expanded(
            child: _buildGameTabCard(
              id: 'bubble',
              title: '戳泡泡',
              tag: '1v1 对战',
              icon: Icons.bubble_chart_rounded,
              themeConfig: themeConfig,
            ),
          ),
          const SizedBox(width: 8),

          // 2. 削砖块（PVP 对战，经典下落消除）
          Expanded(
            child: _buildGameTabCard(
              id: 'brick',
              title: '削砖块',
              tag: '1v1 消除',
              icon: Icons.grid_view_rounded,
              themeConfig: themeConfig,
            ),
          ),
          const SizedBox(width: 8),

          // 3. 打哭小馋怪（单人守桥）
          Expanded(
            child: _buildGameTabCard(
              id: 'monster',
              title: '小馋怪',
              tag: '单人守桥',
              icon: Icons.pets_rounded,
              themeConfig: themeConfig,
            ),
          ),
        ],
      ),
    );
  }

  /// 单个游戏卡片（支持选中高亮与极简微边框）
  Widget _buildGameTabCard({
    required String id,
    required String title,
    required String tag,
    required IconData icon,
    required AppThemeConfig themeConfig,
  }) {
    final isSelected = _selectedGame == id;
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    return FrostedGlassCard(
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (_selectedGame != id) {
            setState(() {
              _selectedGame = id;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: isDarkMode ? 0.8 : 0.6)
                  : (isDarkMode
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05)),
              width: isSelected ? 1.5 : 0.5,
            ),
            color: isSelected
                ? accentColor.withValues(alpha: isDarkMode ? 0.12 : 0.08)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.18)
                      : themeConfig.subtleBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isSelected ? accentColor : textSub,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isSelected
                      ? (isDarkMode ? Colors.white : accentColor)
                      : textMain,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.18)
                      : themeConfig.subtleBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? accentColor : textSub,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选中游戏的专属玩法说明大卡片（三款游戏保持完全对称统一的卡片规格与结构）
  Widget _buildSelectedGameShowcase(AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    final IconData icon;
    final String title;
    final String subtitle;
    final String description;
    final bool isMonster = _selectedGame == 'monster';

    if (isMonster) {
      icon = Icons.pets_rounded;
      title = '打哭小馋怪 · 守桥保卫战';
      subtitle = '左摇杆走位 · 自动投掷 · 走位答词';
      description =
          '成群结队的小馋怪正迈着小短腿压过长桥，企图抢走桥头守护的水果！左下摇杆带着小宠物在桥头前后左右走位，小宠物自动朝正前方投掷坚果：桥两侧悬着一对单词牌，把队伍挪到正确那个单词的正下方，坚果就会打中它——答对火力升级，打错或超时火力下降；小馋怪被打哭会抹着眼泪跑掉，水果被抢光就输啦！';
    } else if (_selectedGame == 'brick') {
      icon = Icons.dashboard_rounded;
      title = '削砖块 · 1v1 经典下落消除';
      subtitle = '单词下落触底 · 辨析中文释义';
      description =
          '单局从顶部缓缓下落 1 个英文单词方块；看准词义在底部 3 个中文释义中快速点选正确答案。答对爆破方块消除，连对可获得道具：左侧「治疗」用在自己这边，右侧「攻击」打向对手；若未在方块触底前答出或答错，该方块会落到防线前堆成死词层——两侧竖排防线会同步长高，堆得越高下一题的下落行程越短，压力越来越大；名字上方会实时显示双方当前单词，两人共用同一份共享词序、同一索引永远是同一个词；堆满 10 层防线失守，先耗尽者判负。';
    } else {
      icon = Icons.bubble_chart_rounded;
      title = '戳泡泡 · 1v1 海底对决';
      subtitle = '单词泡泡升腾 · 抢点正确拼写';
      description =
          '底部显示中文释义，英文单词泡泡从海底升腾；在泡泡冒过顶部警戒线之前，点中拼写正确的那一个。每连续答对 3 题可获道具：水雷轰击对手，海星回复生命，双方各有 10 格生命，先被扣光判负。';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: FrostedGlassCard(
        borderRadius: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 24, color: accentColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: textMain,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeConfig.subtleBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: textSub,
                  ),
                ),
              ),
              if (isMonster) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/monster', extra: {
                      'dictId': _selectedTrainingDict?.id,
                      'dictName': _selectedTrainingDict?.name,
                    }),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text(
                      '进入守桥挑战',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isDarkMode ? const Color(0xFF0B1714) : Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 我的当前词书专属定制场（针对性练习，解决词量太大太泛的痛点）
  GameHallVo? _findBestHallForDict(Dict? dict) {
    if (gameHallDataResult == null || gameHallDataResult!.hallGroups.isEmpty) {
      return null;
    }
    if (dict == null) {
      for (final group in gameHallDataResult!.hallGroups) {
        if (group.gameHalls.isNotEmpty) return group.gameHalls.first;
      }
      return null;
    }

    final dictName = dict.name.toLowerCase();
    for (final group in gameHallDataResult!.hallGroups) {
      final groupName = group.groupName.toLowerCase();
      if (dictName.contains(groupName) || groupName.contains(dictName)) {
        if (group.gameHalls.isNotEmpty) return group.gameHalls.first;
      }
      for (final hall in group.gameHalls) {
        final hallName = hall.hallName.toLowerCase();
        if (dictName.contains(hallName) || hallName.contains(dictName)) {
          return hall;
        }
      }
    }

    final keywords = [
      '考研',
      '四级',
      '六级',
      '专四',
      '专八',
      '雅思',
      '托福',
      '高考',
      '高中',
      '初中',
      '小学'
    ];
    for (final kw in keywords) {
      if (dictName.contains(kw)) {
        for (final group in gameHallDataResult!.hallGroups) {
          if (group.groupName.contains(kw) && group.gameHalls.isNotEmpty) {
            return group.gameHalls.first;
          }
          for (final hall in group.gameHalls) {
            if (hall.hallName.contains(kw)) return hall;
          }
        }
      }
    }

    for (final group in gameHallDataResult!.hallGroups) {
      if (group.gameHalls.isNotEmpty) return group.gameHalls.first;
    }
    return null;
  }

  void _startTrainingBattle() {
    if (_selectedTrainingDict == null) {
      final themeState = context.read<DarkMode>();
      final themeConfig = AppThemeConfig.of(themeState.themeStyle);
      _showDictSelectorSheet(context, themeConfig);
      return;
    }

    if (_selectedGame == 'monster') {
      context.push('/monster', extra: {
        'dictId': _selectedTrainingDict!.id,
        'dictName': _selectedTrainingDict!.name,
      });
      return;
    }

    final hall = _findBestHallForDict(_selectedTrainingDict);
    if (hall == null) {
      ToastUtil.error('暂无可用的游戏对战场次');
      return;
    }

    context.push(_targetGameRoute, extra: [
      hall,
      null,
      {
        'gameMode': _selectedGame,
        'dictId': _selectedTrainingDict!.id,
        'dictName': _selectedTrainingDict!.name,
      }
    ]);
  }

  Widget _buildCurrentDictSection(AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    final hasDict = _selectedTrainingDict != null;
    final dictName = _selectedTrainingDict?.name ?? '点击选择特训词书';
    final dictInfo = hasDict
        ? '已选定 · 共 ${_selectedTrainingDict!.wordCount} 词 · 点击可切换'
        : (_selectedGame == 'monster'
            ? '挑选正在学习或自定义的词书进行守桥特训'
            : '挑选正在学习或自定义的词书进行对战');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: FrostedGlassCard(
        borderRadius: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶层信息行：功能标识 + 切换入口
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9800), Color(0xFFF59E0B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_stories_rounded,
                        size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '自选词书针对特训',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: textMain,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _selectedGame == 'monster' ? '守桥特训' : '精准PK',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF9800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showDictSelectorSheet(context, themeConfig),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDarkMode ? Colors.white12 : Colors.black12,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 13, color: textSub),
                          const SizedBox(width: 3),
                          Text(
                            hasDict ? '换词书' : '选词书',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. 底层信息行：词书大字展示 + 开始对战主按钮
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showDictSelectorSheet(context, themeConfig),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '《$dictName》',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: hasDict
                                  ? (isDarkMode
                                      ? const Color(0xFF38BDF8)
                                      : accentColor)
                                  : textSub,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dictInfo,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textSub,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _startTrainingBattle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7.5),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedGame == 'monster'
                                ? Icons.play_arrow_rounded
                                : Icons.bolt_rounded,
                            size: 15,
                            color: isDarkMode
                                ? const Color(0xFF0B1714)
                                : Colors.white,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _selectedGame == 'monster' ? '开始守桥' : '开始对战',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? const Color(0xFF0B1714)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDictSelectorSheet(
      BuildContext context, AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖拽指示条与标题
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.menu_book_rounded,
                          color: accentColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择对战特训词书',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textMain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '挑选自定义词书或正在学习的词书进行针对性对战',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: textSub, size: 20),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.8),

              // 列表滚动内容
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    // 分组 1：正在学习的词书
                    if (_userLearningDicts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.school_rounded,
                                size: 14, color: accentColor),
                            const SizedBox(width: 6),
                            Text(
                              '我正在学习的词书 (${_userLearningDicts.length})',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._userLearningDicts.map(
                          (d) => _buildDictItem(d, sheetContext, themeConfig)),
                      const SizedBox(height: 14),
                    ],

                    // 分组 2：自定义词单 / 导入词单
                    if (_userCustomDicts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_special_rounded,
                                size: 14, color: Color(0xFFFF9800)),
                            const SizedBox(width: 6),
                            Text(
                              '我的自定义词单 / 导入词书 (${_userCustomDicts.length})',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._userCustomDicts.map((d) => _buildDictItem(
                          d, sheetContext, themeConfig,
                          isCustom: true)),
                      const SizedBox(height: 14),
                    ],

                    // 若既无在学词书也无自定义词单
                    if (_userLearningDicts.isEmpty &&
                        _userCustomDicts.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Column(
                          children: [
                            Icon(Icons.library_books_outlined,
                                size: 44,
                                color: textSub.withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            Text(
                              '书桌上暂无在学词书，快去词库挑选一本吧',
                              style: TextStyle(fontSize: 13, color: textSub),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 扩展通道：去词库挑选更多词书
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await context.push('/select_book');
                        if (mounted) {
                          _loadUserTrainingDicts();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDarkMode ? Colors.white12 : Colors.black12,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 18, color: accentColor),
                            const SizedBox(width: 6),
                            Text(
                              '从完整词库挑选更多词书...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDictItem(
      Dict dict, BuildContext sheetContext, AppThemeConfig themeConfig,
      {bool isCustom = false}) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    final isSelected = _selectedTrainingDict?.id == dict.id;

    final isMastered = dict.name == '已掌握';
    final isRawDict = dict.name == '生词本';

    final IconData iconData;
    final Color iconColor;
    if (isMastered) {
      iconData = Icons.check_circle_outline_rounded;
      iconColor = const Color(0xFF10B981);
    } else if (isRawDict) {
      iconData = Icons.bookmark_rounded;
      iconColor = const Color(0xFFFF9800);
    } else if (isCustom) {
      iconData = Icons.bookmark_added_rounded;
      iconColor = const Color(0xFFFF9800);
    } else {
      iconData = Icons.menu_book_rounded;
      iconColor = accentColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? accentColor.withValues(alpha: isDarkMode ? 0.16 : 0.08)
            : (isDarkMode
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.6)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _selectedTrainingDict = dict;
            });
            Navigator.of(sheetContext).pop();
            ToastUtil.success('已选定特训词书:《${dict.name}》');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    iconData,
                    color: iconColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              dict.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? (isDarkMode
                                        ? const Color(0xFF38BDF8)
                                        : accentColor)
                                    : textMain,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMastered) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '掌握',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981)),
                              ),
                            ),
                          ] else if (isRawDict) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '生词',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFF9800)),
                              ),
                            ),
                          ] else if (isCustom) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '自建',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFF9800)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '共 ${dict.wordCount} 个单词',
                        style: TextStyle(fontSize: 11, color: textSub),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 大厅分组折叠卡片
  Widget _buildGroupCard(HallGroupVo group, AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final isDarkMode = themeConfig.isDark;

    // 默认展开
    _expandedGroups[group.groupName] ??= true;
    final isExpanded = _expandedGroups[group.groupName]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FrostedGlassCard(
        borderRadius: 20,
        child: _buildGroupCardContent(
            group, textMain, textSub, themeConfig, isExpanded, isDarkMode),
      ),
    );
  }

  Widget _buildGroupCardContent(
      HallGroupVo group,
      Color textMain,
      Color textSub,
      AppThemeConfig themeConfig,
      bool isExpanded,
      bool isDarkMode) {
    return Column(
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
                    Text(
                      group.groupName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: textMain,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${group.gameHalls.length} 个场次',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: textSub,
                      ),
                    ),
                  ],
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.arrow_forward_ios_rounded,
                      size: 13, color: textSub.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),

        // 组内各场次（聚合为一行一行的发丝分割列表，不再每项独立浮卡）
        if (isExpanded) ...[
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.055),
          ),
          for (int i = 0; i < group.gameHalls.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.055),
              ),
            _buildHallItem(group.gameHalls[i], themeConfig),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 单个大厅竞技场项目（聚合卡片内的一行，不再独立浮卡）
  Widget _buildHallItem(GameHallVo hall, AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final isDarkMode = themeConfig.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 裸图标
          Icon(Icons.sports_esports_rounded, size: 20, color: accentColor),
          const SizedBox(width: 12),

          // 中间大厅信息
          Expanded(
            child: Text(
              hall.hallName,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: textMain,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // 右侧操作：进房 + 开房（轻文字）+ 匹配（主题色胶囊主按钮）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final int? roomId = await _promptRoomId(context);
                  if (roomId != null && mounted) {
                    context.push(_targetGameRoute, extra: [
                      hall,
                      null,
                      {
                        'joinRoomId': roomId.toString(),
                        'gameMode': _selectedGame,
                      }
                    ]);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  child: Text(
                    '进房',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: textSub,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.push(_targetGameRoute, extra: [
                  hall,
                  null,
                  {
                    'mode': 'createPrivate',
                    'gameMode': _selectedGame,
                  }
                ]),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  child: Text(
                    '开房',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: textSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(_targetGameRoute, extra: [
                  hall,
                  null,
                  {'gameMode': _selectedGame}
                ]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '匹配',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode
                              ? const Color(0xFF0B1714)
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color:
                            isDarkMode ? const Color(0xFF0B1714) : Colors.white,
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

/// 「对战玩法规则」弹窗。
///
/// 抽成独立组件，是为了让放大字号下的布局能被 widget 测试直接验证——
/// 这里曾经把按钮高度和序号圆圈都写死成像素，iPad 上系统字号调大后
/// 按钮文字的下半截就被裁掉了。
class GameRulesDialog extends StatelessWidget {
  const GameRulesDialog({
    super.key,
    required this.themeStyle,
    required this.themeConfig,
  });

  final AppThemeStyle themeStyle;
  final AppThemeConfig themeConfig;

  @override
  Widget build(BuildContext context) {
    final cardBorder = themeConfig.cardBorder;
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    // 规则弹框作为 modal，取更实的底色，避免底下大厅内容透出来
    final dialogBg = themeConfig.isDark
        ? const Color(0xFF1C2127)
        : themeConfig.cardBg.withValues(alpha: 0.96);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cardBorder, width: 1),
          boxShadow: themeConfig.cardShadows,
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
                        color: themeConfig.subtleBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.help_outline_rounded,
                          size: 20, color: accentColor),
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildRuleItem(
                '1',
                '升腾答题',
                '底部显示中文释义，英文单词泡泡从海底升腾；在泡泡冒过顶部警戒线之前，点中拼写正确的那一个。',
                textMain,
                textSub),
            const SizedBox(height: 9),
            _buildRuleItem('2', '失误惩罚', '答错或漏答都会消耗 1 格生命，答错的单词会自动记入生词本。',
                textMain, textSub),
            const SizedBox(height: 9),
            _buildRuleItem(
                '3',
                '连对道具',
                '每连续答对 3 题必得 1 个道具，水雷 2/3、海星 1/3：水雷轰掉对手 1 格生命，海星给自己补回 1 格。',
                textMain,
                textSub),
            const SizedBox(height: 9),
            _buildRuleItem(
                '4', '胜负判定', '双方各有 10 格生命，谁先被扣光谁就判负。', textMain, textSub),
            const SizedBox(height: 9),
            _buildRuleItem(
                '5',
                '匹配与开房',
                '【匹配】自动寻找在线学友快速对战；【开房/进房】房主开房生成房间号，好友输入房间号即可私密切磋。',
                textMain,
                textSub),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: themeStyle.isDark
                      ? const Color(0xFF0B1714)
                      : Colors.white,
                  elevation: 0,
                  // 只定下限、不写死高度：写死 44 时，系统字号调大后文字行高超过 44，
                  // 下半截会被容器裁掉（iPad 上就是这个表现）
                  minimumSize: const Size.fromHeight(44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('我知道了',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleItem(
      String index, String title, String desc, Color textMain, Color textSub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          // 同理不写死 18x18：序号也是文字，字号放大后圆圈得跟着长
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: textSub.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            index,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: textMain),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$title：',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                    height: 1.45,
                  ),
                ),
                TextSpan(
                  text: desc,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: textSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
