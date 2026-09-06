import 'dart:math' as math;

import 'package:appcheck/appcheck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/services/badge_service.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/result.dart';
import '../config.dart';
import '../global.dart';
import '../theme/app_theme.dart';
import '../util/analytics_util.dart';
import '../util/notification_util.dart';
import '../util/platform_util.dart';
import '../widget/daka_poster.dart';
import '../widget/daka_poster_dialog.dart';
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
  int cowDung = 0; // 初始化为0，防止 LateInitializationError
  late Result<int> dakaResult;
  int todayDakaScore = 0; // 今日打卡积分

  String? marketAppUrl; // 应用市场的对应Url

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!dataLoaded) {
      loadData();
    }
  }

  Future<void> loadData() async {
    // 检查是否从页面查看器进入，如果是则模拟打卡但不入库
    final arguments = GoRouterState.of(context).extra;
    final isFromPageViewer = arguments is Map && arguments['fromPageViewer'] == true;

    // iOS/macOS 平台：设置 App Store 评分跳转链接
    if ((PlatformUtils.isIOS || PlatformUtils.isMacOS) && Config.enableAppStoreReview) {
      marketAppUrl = "https://apps.apple.com/app/id${Config.appStoreId}?action=write-review";
    } else if (PlatformUtils.isAndroid) {
      // Android 平台：检测是否安装对应应用市场并设置跳转链接
      try {
        final appCheck = AppCheck();
        if (Config.enableHuaweiReview && await appCheck.isAppInstalled('com.huawei.appmarket')) {
          marketAppUrl = "appmarket://details?id=com.nn.nnbdc.android";
        } else if (Config.enableXiaomiReview && await appCheck.isAppInstalled('com.xiaomi.market')) {
          marketAppUrl = "mimarket://details?id=com.nn.nnbdc.android";
        } else if (Config.enableOppoReview && (await appCheck.isAppInstalled('com.heytap.market') || await appCheck.isAppInstalled('com.oppo.market'))) {
          marketAppUrl = "market://details?id=com.nn.nnbdc.android";
        } else if (Config.enableVivoReview && (await appCheck.isAppInstalled('com.bbk.appstore') || await appCheck.isAppInstalled('com.vivo.market'))) {
          marketAppUrl = "market://details?id=com.nn.nnbdc.android";
        } else if (Config.enableTencentReview && await appCheck.isAppInstalled('com.tencent.android.qqdownloader')) {
          marketAppUrl = "market://details?id=com.nn.nnbdc.android";
        } else if (Config.enableGooglePlayReview && await appCheck.isAppInstalled('com.android.vending')) {
          marketAppUrl = "market://details?id=com.nn.nnbdc.android";
        }
      } catch (e) {
        Global.logger.w('检测应用市场失败: $e');
      }
    }

    if (!isFromPageViewer) {
      // 正常流程：执行打卡逻辑
      dakaResult = await StudyBo().saveDakaRecord("好好学习，天天向上");
      if (dakaResult.success) {
        var user = await UserBo().getLoggedInUser();
        await Global.setLoggedInUser(user.data!);

        // 注：打卡操作记录（user_oper 的 DAKA）已由 saveDakaRecord 内部写入，这里不再重复记录，
        // 否则每天会产生两条 DAKA 操作记录（重复打卡日志）。
        // 精确打击：重置本地通知提醒时间到明天
        try {
          await NotificationUtil.scheduleDailyReminder();
        } catch (e) {
          Global.logger.e('打卡重置提醒失败: $e');
        }

        todayDakaScore = 10; // 每天固定10分

        var result = await StudyBo().throwDiceAndSave();
        if (result.success) {
          cowDung = result.data!;
          // 不再播放特殊声音，因为不再有翻倍机制

          // 漏斗：用户成功打卡完成
          AnalyticsUtil.trackFinishDaka(cowDung, user.data!.continuousDakaDayCount ?? 0);

          // 🌟 实时检测是否达成连续打卡勋章 (如萌芽初醒 3天, 习惯微光 21天, 百日筑基 100天, 早起/深夜打卡等)
          BadgeService().checkStreakDays(context: mounted ? context : null);
        } else {
          cowDung = 0; // 确保失败时为0
          ToastUtil.error(result.msg!);
        }

        // iOS/macOS 平台：打卡成功后请求应用内评分
        if ((PlatformUtils.isIOS || PlatformUtils.isMacOS) && Config.enableAppStoreReview) {
          _requestAppReview();
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

    if (!mounted) return;
    setState(() {
      dataLoaded = true;
    });
  }

  /// iOS/macOS 平台请求应用内评分
  Future<void> _requestAppReview() async {
    try {
      const platform = MethodChannel('com.nnbdc.review');
      await platform.invokeMethod('requestReview');
      Global.logger.d('已请求 iOS/macOS 应用内评分');
    } catch (e) {
      Global.logger.w('请求 iOS/macOS 应用内评分失败: $e');
    }
  }

  Widget renderPage() {
    final themeConfig = context.themeConfig;

    // 固定顶部的庆祝 Hero，始终在 AppBar 之下铺满渐变色块
    return Column(
      children: [
        _buildHero(themeConfig),
        Expanded(child: _buildBody(themeConfig)),
      ],
    );
  }

  Widget _buildBody(AppThemeConfig themeConfig) {
    if (!dataLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!dakaResult.success) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildFailureCard(themeConfig),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetricsCard(themeConfig),
          const SizedBox(height: 14),
          _buildActionGroup(themeConfig),
        ],
      ),
    );
  }

  // 构建顶部庆祝 Hero：主题渐变色块 + 完成印章 + 主标题
  Widget _buildHero(AppThemeConfig themeConfig) {
    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [themeConfig.primaryColor, themeConfig.primaryDarkColor],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: themeConfig.primaryColor.withValues(alpha: themeConfig.isDark ? 0.25 : 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 顶部柔和中心光晕
          Positioned(
            top: -50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 完成内容（避开 AppBar 区域，置于 Hero 下段）
          Positioned(
            left: 20,
            right: 20,
            top: 104,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 完成印章
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 14),
                const Text(
                  '打卡成功',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '今日学习完成 · 继续坚持每天进步一点点',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建打卡成果指标卡（排版驱动：随标签 + 修长数字，微发丝分隔）
  Widget _buildMetricsCard(AppThemeConfig themeConfig) {
    final continuousDays = Global.getLoggedInUser()?.continuousDakaDayCount ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeConfig.cardBorder, width: 1),
        boxShadow: themeConfig.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '打卡成果',
                style: TextStyle(
                  color: themeConfig.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: themeConfig.primaryColor.withValues(alpha: 0.45),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildMetric(themeConfig, label: '魔法泡泡', value: '$cowDung'),
              _buildMetricDivider(themeConfig),
              _buildMetric(themeConfig, label: '今日积分', value: '+$todayDakaScore'),
              _buildMetricDivider(themeConfig),
              _buildMetric(themeConfig, label: '连续打卡', value: '$continuousDays', unit: '天'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    AppThemeConfig themeConfig, {
    required String label,
    required String value,
    String? unit,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: themeConfig.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: themeConfig.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Roboto',
                  letterSpacing: -0.4,
                  height: 1.0,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    color: themeConfig.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDivider(AppThemeConfig themeConfig) {
    return Container(
      width: 0.5,
      height: 46,
      color: themeConfig.textSecondary.withValues(alpha: 0.16),
    );
  }

  // 构建操作入口分组内聚卡片（Grouped Inset Card：图标 + 标题/副说明 + 轻箭头）
  Widget _buildActionGroup(AppThemeConfig themeConfig) {
    final isAdmin = Global.getLoggedInUser()?.isAdmin == true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: themeConfig.cardShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: themeConfig.cardBg,
          child: Column(
            children: [
              _buildActionItem(
                themeConfig,
                key: const Key('finish_word_list_btn'),
                icon: Icons.wysiwyg_rounded,
                iconColor: themeConfig.primaryColor,
                title: '前往词表',
                subtitle: '复习今日学习的单词',
                onTap: () => context.go('/index', extra: IndexPageArgs(1)),
              ),
              _buildActionDivider(themeConfig),
              _buildActionItem(
                themeConfig,
                icon: Icons.share_outlined,
                iconColor: themeConfig.primaryColor,
                title: '生成打卡海报',
                subtitle: '坚持开口，值得记录',
                onTap: _openSharePosterDialog,
              ),
              if (marketAppUrl != null) ...[
                _buildActionDivider(themeConfig),
                _buildActionItem(
                  themeConfig,
                  icon: Icons.favorite_outline_rounded,
                  iconColor: themeConfig.warmAccentColor,
                  title: '给个好评',
                  subtitle: '喜欢，就支持一下',
                  onTap: () {
                    launchUrl(Uri.parse(marketAppUrl!), mode: LaunchMode.externalApplication);
                  },
                ),
              ],
              if (isAdmin) ...[
                _buildActionDivider(themeConfig),
                _buildActionItem(
                  themeConfig,
                  icon: Icons.eco_rounded,
                  iconColor: themeConfig.primaryColor,
                  title: '进入我的小天地',
                  subtitle: '打理你的专属学习田园',
                  onTap: () => context.push('/farm'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem(
    AppThemeConfig themeConfig, {
    Key? key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: themeConfig.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: themeConfig.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: themeConfig.textSecondary.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionDivider(AppThemeConfig themeConfig) {
    return Padding(
      padding: const EdgeInsets.only(left: 54, right: 18),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: themeConfig.isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.055),
      ),
    );
  }

  // 构建打卡失败提示卡
  Widget _buildFailureCard(AppThemeConfig themeConfig) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeConfig.cardBorder, width: 1),
        boxShadow: themeConfig.cardShadows,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: themeConfig.warmAccentColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dakaResult.msg ?? '打卡失败',
              style: TextStyle(
                color: themeConfig.textPrimary,
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

  /// 打开海报分享弹窗
  void _openSharePosterDialog() {
    final user = Global.getLoggedInUser();
    final nick = user?.nickName;
    final uName = user?.userName;
    final userName = (nick != null && nick.isNotEmpty)
        ? nick
        : ((uName != null && uName.isNotEmpty) ? uName : '学习者');
    final continuousDays = user?.continuousDakaDayCount ?? 1;
    final todayWords = user?.wordsPerDay ?? 30;
    final memoryRate = (user?.dakaRatio != null && (user!.dakaRatio! > 0)) ? user.dakaRatio!.round() : 98;
    final totalWords = user?.masteredWordsCount ?? 0;
    final now = DateTime.now();
    final dateStr = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    final posterData = PosterData(
      userName: userName,
      continuousDays: continuousDays,
      todayWords: todayWords,
      memoryRate: memoryRate,
      totalWords: totalWords,
      dateStr: dateStr,
    );

    DakaPosterDialog.show(context, posterData);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context.themeConfig),
      body: renderPage(),
    );
  }

  PreferredSizeWidget _buildAppBar(AppThemeConfig themeConfig) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () {
            context.go('/index');
          },
        ),
      ),
      title: Text(
        '学习完成',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
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
    );
  }
}
