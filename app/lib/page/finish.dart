import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late int todayDakaScore; // 今日打卡积分（固定1分）

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

    // 检查是否从页面查看器进入，如果是则模拟打卡但不入库
    final arguments = Get.arguments;
    final isFromPageViewer = arguments is Map && arguments['fromPageViewer'] == true;
    
    if (!isFromPageViewer) {
      // 正常流程：执行打卡逻辑
      dakaResult = await StudyBo().saveDakaRecord("好好学习，天天向上");
      if (dakaResult.success) {
        var user = await UserBo().getLoggedInUser();
        await Global.setLoggedInUser(user.data!);

        // 记录用户打卡操作
        await MyDatabase.instance.userOpersDao.recordDaka(user.data!.id!, remark: "用户完成打卡，获得10积分");

        todayDakaScore = 10; // 每天固定10分

        var result = await StudyBo().throwDiceAndSave();
        if (result.success) {
          cowDung = result.data!;
          // 不再播放特殊声音，因为不再有翻倍机制
        } else {
          ToastUtil.error(result.msg!);
        }
      }
    } else {
      // 从页面查看器进入：模拟打卡数据，但不入库
      // 生成1-5的随机魔法泡泡数（模拟掷骰子结果）
      cowDung = math.Random().nextInt(5) + 1;
      todayDakaScore = 10; // 模拟获得10积分
      // 模拟打卡成功的结果
      dakaResult = Result("SUCCESS", "页面查看器模式（模拟打卡，数据未入库）", true);
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
                  
                  // 打卡结果卡片（包含积分和魔法泡泡信息）
                  _buildDakaCard(
                    isDarkMode: isDarkMode,
                    cardColor: cardColor,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
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
      height: 140,
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
          // 简洁的庆祝装饰
          _buildSimpleCelebration(),
          
          // 副标题文本
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Center(
              child: Text(
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
            ),
          ),
        ],
      ),
    );
  }

  // 构建简洁的庆祝装饰
  Widget _buildSimpleCelebration() {
    return Stack(
      children: [
        // 顶部柔和的中心光晕
        Positioned(
          top: -30,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 获得积分
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            color: AppTheme.primaryColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '获得积分',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
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
                ),
                // 获得魔法泡泡
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: Colors.purple[300] ?? Colors.purple,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '魔法泡泡',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            cowDung.toString(),
                            style: TextStyle(
                              color: Colors.purple[300] ?? Colors.purple,
                              fontSize: 24,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '个',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 14,
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
          ),
          // 管理员按钮 - 进入我的小天地
          if (dakaResult.success && Global.getLoggedInUser()?.isAdmin == true) ...[
            const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.celebration,
              color: Colors.amber[300],
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              '学习完成',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        // 添加一个与leading相同宽度的透明占位符，使标题完全居中
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            width: 48, // 与leading的IconButton宽度相同（56 - 8*2 margin）
            height: 48,
          ),
        ],
      ),
      body: (!dataLoaded)
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : renderPage(),
    );
  }
}
