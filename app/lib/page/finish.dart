import 'dart:async';
import 'dart:math' as math;

import 'package:appcheck/appcheck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/services/badge_service.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/bo/pet_game_bo.dart';
import '../api/result.dart';
import '../config.dart';
import '../global.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';
import '../widget/frosted_glass_card.dart';
import '../util/analytics_util.dart';
import '../util/learning_service.dart';
import '../util/notification_util.dart';
import '../util/platform_util.dart';
import '../util/prefs.dart';
import '../services/user_privilege_manager.dart';
import '../widget/daka_poster.dart';
import '../widget/daka_poster_dialog.dart';
import '../widget/daka_stamp_badge.dart';
import '../widget/guardian_pet.dart';
import 'index.dart';
import 'bdc/models/bdc_page_args.dart';
import 'subscription.dart';

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

  /// 今日是否已经打卡。打卡记录、掷骰子、打卡类勋章每日只结算一次，
  /// 因此本标志只决定"本次是否还要执行打卡结算"，不决定完成页怎么讲。
  bool hasDakaToday = false;

  /// 本次完成的是否为「加量」批次（打卡后用户主动追加的"再来一组"）。
  /// 判据必须是"今日确实存在加量词"，不能用"今日已打卡"代替：打卡后重学今日计划
  /// （调整单词量后的补词、他端打卡后本端首次学完）同样会回到完成页，那些是正常学习，不是加量。
  bool isExtraRound = false;

  String? marketAppUrl; // 应用市场的对应Url

  /// 记忆守护兽当前情绪。打卡完成本身就是"今天喂饱了"，所以默认是精神饱满；
  /// 用户戳一下或投喂时临时切到开心，两秒后回到常态。
  PetMood petMood = PetMood.excited;
  Timer? _petMoodTimer;

  /// 守护兽养成状态（累计投喂次数与进化阶段），加载失败时保持 null 并按初始态展示。
  UserPetState? petState;
  bool petFeeding = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _petMoodTimer?.cancel();
    super.dispose();
  }

  /// 触发一次守护兽的开心反馈（呼吸、眨眼、光核脉冲都由组件自己驱动）。
  void _cheerPet() {
    _petMoodTimer?.cancel();
    if (petMood != PetMood.happy) {
      setState(() => petMood = PetMood.happy);
    }
    _petMoodTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => petMood = PetMood.excited);
    });
  }

  /// 投喂一次守护兽：消耗 1 个魔法泡泡，累计投喂次数 +1，达到阈值时升阶。
  Future<void> _feedPet() async {
    if (petFeeding) return;
    final user = Global.getLoggedInUser();
    if (user == null) return;
    if (user.cowDung < PetGameBo.feedCost) {
      ToastUtil.info('魔法泡泡不够了，明天打卡再来喂它');
      return;
    }

    setState(() => petFeeding = true);
    try {
      final result = await PetGameBo().feed();
      if (!mounted) return;
      if (result == null) {
        ToastUtil.info('魔法泡泡不够了，明天打卡再来喂它');
        return;
      }
      setState(() {
        petState = result.state;
        cowDung = Global.getLoggedInUser()?.cowDung ?? cowDung;
      });
      final stage = PetGameBo.stages[result.state.stageIndex];
      if (result.leveledUp) {
        ToastUtil.success('守护兽进化成了「${stage.name}」');
      } else {
        ToastUtil.success('已投喂 1 个魔法泡泡');
      }
      _cheerPet();
    } catch (e, stackTrace) {
      Global.logger.e('投喂守护兽失败: $e', error: e, stackTrace: stackTrace);
      ToastUtil.error('投喂失败，请稍后再试');
    } finally {
      if (mounted) setState(() => petFeeding = false);
    }
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
          // appmarket://details?id= 在新版华为应用市场只会拉起市场首页、丢弃 details 参数，
          // 改用官方 applink 形式：market://com.huawei.appmarket.applink?appId=xxx 直达应用详情页
          marketAppUrl = "market://com.huawei.appmarket.applink?appId=${Config.huaweiAppId}";
        } else if (Config.enableHuaweiReview && await appCheck.isAppInstalled('com.hihonor.appmarket')) {
          // 荣耀应用市场由华为应用市场分拆独立：包名独立，详情页使用通用 market:// scheme
          marketAppUrl = "market://details?id=com.nn.nnbdc.android";
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

    // 今日是否已经打卡：已打卡则本次不重复打卡、不掷骰子
    // （掷骰子机会仅在每日首次打卡时发放，重复掷必然失败），
    // 也不再判定打卡类勋章（破晓/夜行等必须在完成打卡的当下判定一次）。
    final currentUser = Global.getLoggedInUser();
    hasDakaToday = !isFromPageViewer &&
        currentUser != null &&
        ((await UserBo().hasDakaToday(currentUser.id)).data ?? false);

    // 加量完成 = 打卡后确实追加过"再来一组"，即今日学习列表里存在标记为 isExtra 的词。
    // 学习页只有在今日所有词（含加量批次）都学完时才会跳到这里，"存在加量词"即"本次学完的是加量批次"。
    if (hasDakaToday) {
      final todayWords = await LearningService.getTodayLearningWordsFromDb(currentUser!.id);
      isExtraRound = todayWords.any((w) => w.isExtra);
    }

    if (!isFromPageViewer) {
      if (hasDakaToday) {
        // 打卡已在今日首次完成，此处只展示成果
        dakaResult = Result("SUCCESS", isExtraRound ? "加量完成" : "学习完成", true);
      } else {
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
          } else {
            cowDung = 0; // 确保失败时为0
            ToastUtil.error(result.msg!);
          }

          // iOS/macOS 平台：打卡成功后请求应用内评分
          if ((PlatformUtils.isIOS || PlatformUtils.isMacOS) && Config.enableAppStoreReview) {
            _requestAppReview();
          }
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

    if (!isFromPageViewer && !hasDakaToday) {
      // 🌟 本次学习结束: 判定连续打卡、打卡时段(破晓/夜行)与单次学习表现(全对/心流)类勋章
      await BadgeService().checkStreakDays();
      await BadgeService().checkStudyTimeBadge();
      await BadgeService().checkStudyPerformance();
    }

    if (!mounted) return;
    // 守护兽养成状态：只读，加载失败不阻塞完成页其余内容。
    // 该功能尚未对外发布（入口只对管理员开放），因此非管理员不必白查一次库。
    try {
      final user = Global.getLoggedInUser();
      if (user != null && user.isAdmin == true) {
        petState = await PetGameBo().loadState(user.id);
      }
    } catch (e, stackTrace) {
      Global.logger.w('读取守护兽养成状态失败: $e', error: e, stackTrace: stackTrace);
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

    // 记忆守护兽尚未对外发布：只对管理员开放，用于真机验收，普通用户看不到入口。
    final isAdmin = Global.getLoggedInUser()?.isAdmin == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 打卡成果（积分/魔法泡泡）只在本次真正结算了打卡时才有值，已在今日打过卡时不再展示
          if (!hasDakaToday) ...[
            _buildMetricsCard(themeConfig),
            const SizedBox(height: 14),
          ],
          if (isAdmin) ...[
            _buildPetCard(themeConfig),
            const SizedBox(height: 14),
          ],
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
            top: 98,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 完成打卡专属物理动效印章（印泥朱砂红，不随主题变色）
                DakaStampBadge(
                  size: 76,
                  isExtraRound: isExtraRound,
                  color: DakaSealColors.forDark(themeConfig.isDark),
                  backgroundColor: themeConfig.isDark
                      ? const Color(0xFF1E293B)
                      : Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  isExtraRound ? '加量完成' : '打卡成功',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
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

    return FrostedGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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

  // 构建记忆守护兽卡片：宠物在左，进化进度与投喂动作在右
  Widget _buildPetCard(AppThemeConfig themeConfig) {
    final (moodTitle, line) = switch (petMood) {
      PetMood.happy => ('吃得开心', 'Yummy! You mastered ${StudyBo.batchSize} words today.'),
      PetMood.hungry => ('肚子饿了', "I'm hungry, let's learn!"),
      PetMood.sad => ('有点消沉', 'Feed me a word?'),
      PetMood.sleepy => ('睡着了', 'Zzz… wake me with a review.'),
      PetMood.excited => ('精神饱满', 'Crisp! Worth remembering.'),
    };

    final totalFeedings = petState?.totalFeedings ?? 0;
    final stage = PetGameBo.stages[PetGameBo.stageIndexOf(totalFeedings)];
    final toNext = PetGameBo.feedingsToNextStage(totalFeedings);
    final canFeed = (Global.getLoggedInUser()?.cowDung ?? 0) >= PetGameBo.feedCost;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: themeConfig.cardShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: context.cardBg,
          child: InkWell(
            onTap: _cheerPet,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
              child: Row(
                children: [
                  GuardianPet(mood: petMood, height: 116),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '记忆守护兽 · ${stage.name}',
                          style: TextStyle(
                            color: themeConfig.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          moodTitle,
                          style: TextStyle(
                            color: themeConfig.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          toNext == null ? '已经长到最终形态了' : '再投喂 $toNext 次就能进化',
                          style: TextStyle(
                            color: themeConfig.textSecondary,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line,
                          style: TextStyle(
                            color: themeConfig.textSecondary.withValues(alpha: 0.75),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildFeedButton(themeConfig, canFeed),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 投喂按钮：泡泡不足时置灰但保留可点，点了给一句明确提示，避免用户不知道为什么没反应。
  Widget _buildFeedButton(AppThemeConfig themeConfig, bool canFeed) {
    final enabled = canFeed && !petFeeding;
    return TextButton(
      key: const Key('finish_feed_pet_btn'),
      onPressed: enabled ? _feedPet : null,
      style: TextButton.styleFrom(
        backgroundColor: enabled
            ? themeConfig.primaryColor.withValues(alpha: 0.12)
            : themeConfig.textSecondary.withValues(alpha: 0.08),
        foregroundColor: enabled ? themeConfig.primaryColor : themeConfig.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: petFeeding
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: themeConfig.primaryColor,
              ),
            )
          : Text(
              '投喂 ${PetGameBo.feedCost}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
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
          color: context.cardBg,
          child: Column(
            children: [
              // 打卡后完成的学习都可以继续加量（不限次数，会员权益）
              if (hasDakaToday) ...[
                _buildActionItem(
                  themeConfig,
                  key: const Key('finish_extra_again_btn'),
                  icon: Icons.add_circle_outline_rounded,
                  iconColor: themeConfig.primaryColor,
                  title: '再来一组',
                  subtitle: '趁状态正好，再背 ${StudyBo.batchSize} 个单词',
                  onTap: _startExtraStudy,
                ),
                _buildActionDivider(themeConfig),
              ],
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
        color: context.cardBg,
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

  /// 打卡后继续加量：追加一组单词后直接进入学习页。
  /// 加量是会员权益，非会员引导至订阅页。
  Future<void> _startExtraStudy() async {
    if (!UserPrivilegeManager.canExtraStudy) {
      ToastUtil.info('加量是会员专属权益');
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscriptionPage()),
      );
      return;
    }

    final result = await StudyBo().prepareExtraStudy();
    if (!mounted) return;
    if (!result.success) {
      ToastUtil.error(result.msg ?? '加量失败');
      return;
    }

    await Prefs.write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
    if (!mounted) return;
    // 使用 pushReplacement 替换当前完成页，避免加量学习中途回退时再次进入完成页造成“已学完”的误解，
    // 使回退自然回到栈底的今日学习计划页面（/index）
    context.pushReplacement('/bdc');
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
      vibrancy: PageVibrancy.finish,
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
