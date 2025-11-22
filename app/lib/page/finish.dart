import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appcheck/appcheck.dart';

import '../api/result.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../util/platform_util.dart';
import 'package:provider/provider.dart';
import 'index.dart';

class FinishPage extends StatefulWidget {
  const FinishPage({super.key});

  @override
  FinishPageState createState() {
    return FinishPageState();
  }
}

class FinishPageState extends State<FinishPage> with TickerProviderStateMixin {
  bool dataLoaded = false;
  late int cowDung;
  late Result<int> dakaResult;
  late int todayDakaScore; // 今日打卡积分（固定1分）

  String? marketAppUrl; // 应用市场的对应Url
  
  late AnimationController _bubbleGlowController; // 泡泡光晕动画控制器
  late AnimationController _rayRotationController; // 光线旋转动画控制器

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();
    
    // 初始化泡泡光晕动画
    _bubbleGlowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    // 初始化光线旋转动画（降速为原来的十分之一）
    _rayRotationController = AnimationController(
      duration: const Duration(milliseconds: 10000),
      vsync: this,
    )..repeat();

    loadData();
  }
  
  @override
  void dispose() {
    _bubbleGlowController.dispose();
    _rayRotationController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    // 检测手机上安装的应用市场
    if (PlatformUtils.isAndroid) {
      if (await AppCheck().isAppInstalled('com.huawei.appmarket')) {
        marketAppUrl = "appmarket://details?id=com.nn.nnbdc.android";
      } /*else if (await DeviceApps.isAppInstalled('com.xiaomi.market')) {
        marketAppUrl = "mimarket://details?id=com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.sec.android.app.samsungapps')) {
        marketAppUrl = "samsungapps://ProductDetail/com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.oppo.market')) {
        marketAppUrl = "oppomarket://details?packagename=com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.bbk.appstore')) {
        marketAppUrl = "vivomarket://details?id=com.nn.nnbdc.android";
      }*/
    }

    dakaResult = await StudyBo().saveDakaRecord("好好学习，天天向上");
    if (dakaResult.success) {
      var user = await UserBo().getLoggedInUser();
      await Global.setLoggedInUser(user.data!);

      // 记录用户打卡操作
      await MyDatabase.instance.userOpersDao.recordDaka(user.data!.id!, remark: "用户完成打卡，获得1积分");

      todayDakaScore = 1; // 每天固定1分

      var result = await StudyBo().throwDiceAndSave();
      if (result.success) {
        cowDung = result.data!;
        // 不再播放特殊声音，因为不再有翻倍机制
      } else {
        ToastUtil.error(result.msg!);
      }
    }

    setState(() {
      dataLoaded = true;
    });
  }

  Widget renderPage() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);
    final subtitleColor = isDarkMode ? (Colors.grey[400] ?? Colors.grey) : (Colors.grey[600] ?? Colors.grey);

    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // 顶部装饰区域
          _buildHeaderSection(isDarkMode),
          
          // 主要内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // 打卡结果卡片
                  _buildDakaCard(
                    isDarkMode: isDarkMode,
                    cardColor: cardColor,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // 魔法泡泡卡片
                  if (dakaResult.success)
                    _buildBubbleCard(
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // 操作按钮卡片
                  _buildActionCards(
                    isDarkMode: isDarkMode,
                    cardColor: cardColor,
                    textColor: textColor,
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建顶部装饰区域
  Widget _buildHeaderSection(bool isDarkMode) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.gradientStartColor,
            AppTheme.gradientEndColor,
          ],
        ),
      ),
      child: Stack(
        children: [
          // 庆祝光晕效果
          _buildCelebrationGlow(),
          
          // 星星装饰
          _buildStars(),
          
          // 彩带装饰
          _buildConfetti(),
          
          // 标题文本
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.celebration,
                      color: Colors.amber[300],
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '学习完成',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.8,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '继续坚持，每天进步一点点',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建庆祝光晕效果
  Widget _buildCelebrationGlow() {
    return Stack(
      children: [
        // 主光晕 - 顶部中央
        Positioned(
          top: -60,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withValues(alpha: 0.3),
                    Colors.orange.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // 左侧光晕
        Positioned(
          top: 60,
          left: -40,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.pink.withValues(alpha: 0.25),
                  Colors.purple.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // 右侧光晕
        Positioned(
          top: 80,
          right: -30,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.cyan.withValues(alpha: 0.25),
                  Colors.blue.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建星星装饰
  Widget _buildStars() {
    return Stack(
      children: [
        // 左上角星星
        Positioned(
          top: 50,
          left: 30,
          child: Icon(
            Icons.star,
            color: Colors.amber[200],
            size: 24,
          ),
        ),
        // 右上角大星星
        Positioned(
          top: 40,
          right: 50,
          child: Icon(
            Icons.star,
            color: Colors.amber[300],
            size: 32,
          ),
        ),
        // 中间小星星
        Positioned(
          top: 80,
          right: 100,
          child: Icon(
            Icons.star,
            color: Colors.white.withValues(alpha: 0.8),
            size: 16,
          ),
        ),
        // 左侧小星星
        Positioned(
          top: 100,
          left: 80,
          child: Icon(
            Icons.star,
            color: Colors.white.withValues(alpha: 0.7),
            size: 14,
          ),
        ),
      ],
    );
  }

  // 构建彩带装饰
  Widget _buildConfetti() {
    return Stack(
      children: [
        // 左侧彩带
        Positioned(
          top: 20,
          left: 20,
          child: Transform.rotate(
            angle: -0.3,
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.withValues(alpha: 0.8),
                    Colors.orange.withValues(alpha: 0.8),
                    Colors.yellow.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // 右侧彩带
        Positioned(
          top: 30,
          right: 30,
          child: Transform.rotate(
            angle: 0.4,
            child: Container(
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.8),
                    Colors.pink.withValues(alpha: 0.8),
                    Colors.cyan.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // 中间彩带
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: 0.2,
              child: Container(
                width: 70,
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.withValues(alpha: 0.8),
                      Colors.blue.withValues(alpha: 0.8),
                      Colors.purple.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建打卡结果卡片
  Widget _buildDakaCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
    required Color subtitleColor,
  }) {
    if (!dakaResult.success) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.orange,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dakaResult.msg ?? '打卡失败',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '打卡成功！',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '今日学习完成',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.1),
                  AppTheme.primaryLightColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '获得积分',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      todayDakaScore.toString(),
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建魔法泡泡卡片
  Widget _buildBubbleCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: isDarkMode ? 0.2 : 0.1),
            Colors.pink.withValues(alpha: isDarkMode ? 0.15 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.purple[300] ?? Colors.purple,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '恭喜你得到$cowDung个魔法泡泡',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '可以建造自己的小天地啦',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 显示具体的泡泡
          _buildBubblesDisplay(cowDung, isDarkMode),
          const SizedBox(height: 12),
          // 进入我的小天地按钮 - 仅管理员可见
          if (Global.getLoggedInUser()?.isAdmin == true)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(
                  Icons.eco,
                  size: 18.0,
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.green[600],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                label: const Text(
                  '进入我的小天地',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                onPressed: () {
                  Get.toNamed('/farm');
                },
              ),
            ),
        ],
      ),
    );
  }

  // 泡泡类型配置
  static const List<BubbleTypeConfig> _bubbleTypes = [
    BubbleTypeConfig(
      name: '种子',
      color: Colors.green,
      icon: Icons.eco,
    ),
    BubbleTypeConfig(
      name: '卵',
      color: Colors.amber,
      icon: Icons.egg,
    ),
    BubbleTypeConfig(
      name: '资源',
      color: Colors.blue,
      icon: Icons.diamond,
    ),
  ];

  // 构建泡泡显示区域
  Widget _buildBubblesDisplay(int count, bool isDarkMode) {
    final displayCount = count > 10 ? 10 : count;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每行5个泡泡的大小
        // 可用宽度 = 屏幕宽度 - 左右padding (16 * 2)
        final availableWidth = constraints.maxWidth;
        // 每行5个，4个间距
        const int bubblesPerRow = 5;
        const double spacing = 8.0;
        const double totalSpacing = spacing * (bubblesPerRow - 1);
        
        // 计算每个泡泡容器的大小
        // containerSize = (availableWidth - totalSpacing) / bubblesPerRow
        final containerSize = (availableWidth - totalSpacing) / bubblesPerRow;
        
        // 计算实际的泡泡大小
        // containerSize = bubbleSize + maxGlowExtension * 2
        // maxGlowExtension = bubbleSize * 0.5
        // 所以 containerSize = bubbleSize * 2
        final bubbleSize = containerSize / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.start,
          children: List.generate(displayCount, (index) {
            // 循环分配到四类泡泡中
            final typeIndex = index % _bubbleTypes.length;
            final bubbleType = _bubbleTypes[typeIndex];
            
            return _buildSingleBubble(bubbleType, bubbleSize);
          }),
        );
      },
    );
  }

  // 构建单个泡泡
  Widget _buildSingleBubble(BubbleTypeConfig type, double size) {
    // 计算最大光晕范围，确保容器大小固定
    final maxGlowExtension = size * 0.5;
    final containerSize = size + maxGlowExtension * 2;
    
    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bubbleGlowController, _rayRotationController]),
        builder: (context, child) {
          // 计算光晕动画值，在 0.4 到 1.0 之间变化
          // 使用 controller.value，因为 repeat(reverse: true) 会在 0-1 之间来回
          final glowValue = 0.4 + (0.6 * _bubbleGlowController.value);
          // 旋转角度
          final rotationAngle = _rayRotationController.value * 2 * math.pi; // 0 到 2π
          
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 外层动态光晕（固定在容器中心，不会影响布局）
              Positioned(
                left: containerSize / 2 - (size + size * 0.5 * glowValue) / 2,
                top: containerSize / 2 - (size + size * 0.5 * glowValue) / 2,
                child: Container(
                  width: size + (size * 0.5 * glowValue),
                  height: size + (size * 0.5 * glowValue),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.5 * glowValue),
                        blurRadius: 15 * glowValue,
                        spreadRadius: 6 * glowValue,
                      ),
                    ],
                  ),
                ),
              ),
              // 主泡泡容器（固定在中心）
              Positioned(
                left: containerSize / 2 - size / 2,
                top: containerSize / 2 - size / 2,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                    gradient: RadialGradient(
                      colors: [
                        type.color.withValues(alpha: 0.95),
                        type.color.withValues(alpha: 0.75),
                        type.color.withValues(alpha: 0.5),
                        type.color.withValues(alpha: 0.3),
                      ],
                      stops: const [0.0, 0.4, 0.7, 1.0],
                    ),
                    boxShadow: [
                      // 动态内发光
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.5 * glowValue),
                        blurRadius: 6 * glowValue,
                        spreadRadius: 0,
                        offset: const Offset(0, 0),
                      ),
                      // 静态阴影
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      children: [
                        // 动态光晕层（内层，增强效果）
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  type.color.withValues(alpha: 0.4 * glowValue),
                                  type.color.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 内部放射光线效果（从中心向外发散）
                        ..._buildInternalRays(type, size, glowValue, rotationAngle),
                        // 中心高光点
                        Center(
                          child: Container(
                            width: size * 0.3,
                            height: size * 0.3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.9 * glowValue),
                                  Colors.white.withValues(alpha: 0.5 * glowValue),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 内部物品图标（中心）
                        Center(
                          child: Icon(
                            type.icon,
                            size: size * 0.4,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 构建操作按钮卡片
  Widget _buildActionCards({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return Column(
      children: [
        // 前往词表卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '若要复习，可前往',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '查看今日学习的单词',
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.wysiwyg,
                  size: 18.0,
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                key: const Key('finish_word_list_btn'),
                label: const Text(
                  '词表',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                onPressed: () {
                  Get.toNamed('/index', arguments: IndexPageArgs(1));
                },
              ),
            ],
          ),
        ),
        
        // 给个好评卡片（如果存在）
        if (marketAppUrl != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '喜欢泡泡，那就',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '给个好评支持一下',
                        style: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(
                    Icons.favorite,
                    size: 18.0,
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red[400],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  label: const Text(
                    '给个好评吧',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  onPressed: () {
                    launchUrl(Uri.parse(marketAppUrl!));
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }


  // 构建内部放射光线
  List<Widget> _buildInternalRays(
    BubbleTypeConfig type,
    double size,
    double glowValue,
    double rotationAngle,
  ) {
    final rayCount = 12; // 12条内部光线，更密集
    
    return List.generate(rayCount, (index) {
      final angle = (index * 2 * math.pi / rayCount) + rotationAngle;
      
      return Center(
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: size * 0.95,
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.centerRight,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.15 * glowValue),
                  Colors.white.withValues(alpha: 0.25 * glowValue),
                  Colors.white.withValues(alpha: 0.15 * glowValue),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: (!dataLoaded)
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : renderPage(),
    );
  }
}

// 泡泡类型配置类
class BubbleTypeConfig {
  final String name;
  final Color color;
  final IconData icon;

  const BubbleTypeConfig({
    required this.name,
    required this.color,
    required this.icon,
  });
}
