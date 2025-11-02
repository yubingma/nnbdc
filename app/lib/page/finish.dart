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

class FinishPageState extends State<FinishPage> {
  bool dataLoaded = false;
  late int cowDung;
  late Result<int> dakaResult;
  late int todayDakaScore; // 今日打卡积分（含加成）
  late int extraScore; // 打卡积分加成

  String? marketAppUrl; // 应用市场的对应Url

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();

    loadData();
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
      await MyDatabase.instance.userOpersDao.recordDaka(user.data!.id!, remark: "用户完成打卡，获得${dakaResult.data}积分");

      todayDakaScore = dakaResult.data!;
      extraScore = Global.getLoggedInUser()!.continuousDakaDayCount;

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
                  const SizedBox(height: 24),
                  
                  // 打卡结果卡片
                  _buildDakaCard(
                    isDarkMode: isDarkMode,
                    cardColor: cardColor,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 魔法泡泡卡片
                  if (dakaResult.success)
                    _buildBubbleCard(
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // 操作按钮卡片
                  _buildActionCards(
                    isDarkMode: isDarkMode,
                    cardColor: cardColor,
                    textColor: textColor,
                  ),
                  
                  const SizedBox(height: 32),
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
      height: 220,
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
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.celebration,
                      color: Colors.amber[300],
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '学习完成',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '继续坚持，每天进步一点点',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 16,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                dakaResult.msg ?? '打卡失败',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '打卡成功！',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '今日学习完成',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.1),
                  AppTheme.primaryLightColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
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
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${todayDakaScore - extraScore}',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (extraScore > 0) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 4),
                            child: Text(
                              '+ $extraScore',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (extraScore > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          color: Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '连续打卡',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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

  // 构建魔法泡泡卡片
  Widget _buildBubbleCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: isDarkMode ? 0.2 : 0.1),
            Colors.pink.withValues(alpha: isDarkMode ? 0.15 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: Colors.purple[300] ?? Colors.purple,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '恭喜！你得到',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$cowDung',
                      style: TextStyle(
                        color: Colors.purple[400] ?? Colors.purple,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 4),
                      child: Text(
                        '颗魔法泡泡',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
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
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '查看今日学习的单词',
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(
                  Icons.wysiwyg,
                  size: 20.0,
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                key: const Key('finish_word_list_btn'),
                label: const Text(
                  '词表',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
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
                        '如果喜欢牛牛，那就',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '给个好评支持一下',
                        style: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(
                    Icons.favorite,
                    size: 20.0,
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red[400],
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  label: const Text(
                    '给个好评吧',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
