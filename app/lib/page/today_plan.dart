import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/state.dart';

import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/subscription_util.dart';

import '../theme/app_theme.dart';
import 'bdc.dart';

class BeforeBdcPage extends StatefulWidget {
  const BeforeBdcPage({super.key});

  @override
  BeforeBdcPageState createState() {
    return BeforeBdcPageState();
  }
}

class BeforeBdcPageState extends State<BeforeBdcPage> with TickerProviderStateMixin {
  List<UserStudyStepVo>? studySteps;
  int? newWordCount;
  int? oldWordCount;
  int? todayWordCount;
  bool dataLoaded = false;
  UserVo? user;
  bool hasDakaToday = false;
  Result<List<int>>? prepareResult;
  bool _hasTriedSupplement = false;

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  void reorderData(int oldIndex, int newIndex) {
    if (!mounted) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = studySteps!.removeAt(oldIndex);
      studySteps!.insert(newIndex, items);

      // 重新计算每个study step的顺序号
      for (var i = 0; i < studySteps!.length; i++) {
        studySteps![i].seq = i;
      }

      saveStudyStep();
    });
  }

  bool _isLoadingData = false;

  @override
  void initState() {
    super.initState();
    // 使用Timer.run确保完全异步执行，避免阻塞UI
    Timer.run(() {
      if (mounted) {
        loadData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 使用Timer.run确保完全异步执行，避免阻塞UI
    if (mounted && !dataLoaded && !_isLoadingData) {
      Timer.run(() {
        if (mounted && !dataLoaded && !_isLoadingData) {
          loadData();
        }
      });
    }
  }

  Future<void> loadData({bool forceSupplement = false}) async {
    // 如果不是强制补充模式，重置“已尝试补充”标记
    if (!forceSupplement) {
      _hasTriedSupplement = false;
    }

    // 防止重复加载
    if (_isLoadingData) return;
    _isLoadingData = true;

    // 禁用 loading 提示
    Api.setLoadingDisabled(true);

    // 添加一个短暂延迟，确保加载动画能够显示
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // 获取用户基本信息
      var result0 = await UserBo().getLoggedInUser();
      if (result0.success) {
        user = result0.data;
      } else {
        ToastUtil.error(result0.msg!);
        return;
      }

      // 获取用户的学习步骤
      var result = await StudyBo().getUserStudySteps();
      if (result.success) {
        studySteps = [];
        List<UserStudyStepVo> userStudySteps = result.data!;
        for (UserStudyStepVo step in userStudySteps) {
          // 在UI设置中隐藏“单词列表”阶段，让它成为一个隐形的固定环节
          if (step.studyStep != 'List') {
            studySteps!.add(step);
          }
        }
      } else {
        ToastUtil.error(result.msg!);
        return;
      }

      // 生成（或获取）用户的今日单词
      try {
        prepareResult = await StudyBo().prepareForStudy(forceSupplement);
        if (prepareResult!.success || prepareResult!.code == "NNBDC-0012" /*未取到足够单词*/) {
          if (forceSupplement) {
            _hasTriedSupplement = true;
          }
          List<int> counts = prepareResult!.data!;
          newWordCount = counts[0];
          oldWordCount = counts[1];
          todayWordCount = newWordCount! + oldWordCount!;
        } else {
          ToastUtil.error(prepareResult!.msg!);
          return;
        }
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace, logPrefix: '准备学习失败', userMessage: '准备学习失败，请稍后重试', showToast: true);
        return;
      }

      // 获取用户的今日打卡状态
      hasDakaToday = (await UserBo().hasDakaToday(user!.id!)).data!;

      // 检查页面是否仍然挂载，避免在 dispose 后调用 setState
      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
      }
    } finally {
      // 重新启用 loading 提示
      Api.setLoadingDisabled(false);
      _isLoadingData = false;
    }
  }

  List<UserStudyStepVo> selectedSteps() {
    List<UserStudyStepVo> steps = [];
    for (var step in studySteps!) {
      if (step.state == StudyStepState.active.json) {
        steps.add(step);
      }
    }
    return steps;
  }

  Widget renderPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // 1. 学习步骤/模式设置
          renderStudySteps(),

          // 2. 今日核心任务卡片 (目标设置 + 单词统计)
          renderMissionCard(),

          // 底部间距
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget renderMissionCard() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : AppTheme.primaryColor).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部：目标设置
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '今日目标',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    if (user?.todayStudyStarted == true) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => ToastUtil.info('今日学习已开始，无法修改计划数量'),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          color: isDarkMode ? Colors.white30 : Colors.black26,
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
                renderGoalDropdown(),
              ],
            ),
          ),

          // 中间：核心数据
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildStatItem('今日单词', todayWordCount!, Icons.library_books_rounded, AppTheme.primaryColor,
                    () => toTodayWordsListPage(true)?.then((v) => loadData())),
                _buildStatItem('新词', newWordCount!, Icons.fiber_new_rounded, const Color(0xFF4CAF50),
                    () => toTodayNewWordsListPage(true)?.then((v) => loadData())),
                _buildStatItem('复习', oldWordCount!, Icons.refresh_rounded, const Color(0xFFFF9800),
                    () => toTodayOldWordsListPage(true)?.then((v) => loadData())),
              ],
            ),
          ),

          // 单词不足补充提醒
          if (prepareResult!.success && todayWordCount! < user!.wordsPerDay! && !(user!.todayStudyStarted ?? false) && !_hasTriedSupplement)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '任务量不足，建议点击旁边按钮补充',
                        style: TextStyle(color: const Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        loadData(forceSupplement: true);
                      },
                      child: const Text('补充', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          // 底部：开始按钮 或 错误处理区域
          Padding(
            padding: const EdgeInsets.all(20),
            child: (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && todayWordCount! < (user?.wordsPerDay ?? 0)))
                ? renderErrorActions()
                : renderStartButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color color, VoidCallback onTap) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold, height: 1.1),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  fontSize: 12,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget renderGoalDropdown() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: (() {
            final isPremium = SubscriptionUtil.isPremium();
            final raw = user?.wordsPerDay ?? 20;
            if (!isPremium && raw > 20) return 20;
            return raw;
          })(),
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          dropdownColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          onChanged: (user?.todayStudyStarted == true)
              ? null
              : (value) async {
                  if (value == null) return;
                  if (!SubscriptionUtil.isPremium() && value > 20) {
                    ToastUtil.info('开通会员可选择更多单词数量');
                    return;
                  }
                  setState(() {
                    user!.wordsPerDay = value;
                    dataLoaded = false;
                  });
                  await MyDatabase.instance.usersDao.updateWordsPerDay(user!.id!, value);
                  await Global.loadUserFromDb();
                  ThrottledDbSyncService().requestSync();
                  loadData(forceSupplement: false);
                },
          items: (() {
            final isPremium = SubscriptionUtil.isPremium();
            return [10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500].map((v) {
              final isRestricted = !isPremium && v > 20;
              return DropdownMenuItem<int>(
                value: v,
                enabled: !isRestricted,
                child: Row(
                  children: [
                    Text('$v'),
                    if (isRestricted) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.workspace_premium, color: Colors.amber, size: 14),
                    ]
                  ],
                ),
              );
            }).toList();
          })(),
        ),
      ),
    );
  }

  Widget renderStartButton() {
    if (hasDakaToday) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            const Text('今日已打卡', style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 2,
        ),
        onPressed: () async {
          if (selectedSteps().isEmpty) {
            ToastUtil.error('请至少选择一个学习方式');
            return;
          }
          if (user != null) {
            await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "用户开始学习");
            await (MyDatabase.instance.update(MyDatabase.instance.users)..where((u) => u.id.equals(user!.id!))).write(UsersCompanion(
              todayStudyStarted: const drift.Value(true),
            ));
            await Global.loadUserFromDb();
          }
          await GetStorage().write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
          Get.toNamed('/bdc')?.then((value) {
            if (mounted && !_isLoadingData) loadData();
          });
        },
        child: const Text('准备好了，开始学习', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  Widget renderErrorActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFFF5252), size: 24),
              SizedBox(width: 12),
              Text('没有取到足够单词', style: TextStyle(color: Color(0xFFFF5252), fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch, // 确保子组件填满高度
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      minimumSize: const Size(0, 48), // 设置最小高度
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.library_books, color: Colors.white, size: 18),
                    label: const Text('选择词书', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Get.toNamed('/select_book')?.then((v) {
                        if (mounted) {
                          setState(() => _hasTriedSupplement = false);
                          loadData(forceSupplement: true);
                        }
                      });
                    },
                  ),
                ),
                if (todayWordCount! > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        minimumSize: const Size(0, 48), // 设置最小高度
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                      label: const Text(
                        '就这样吧\n去学习',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.2),
                      ),
                      onPressed: () => Get.toNamed('/bdc'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTile(step) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final isActive = step.state == StudyStepState.active.json;
    return Container(
      key: ValueKey(step),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryColor.withValues(alpha: 0.05)
            : (isDarkMode ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppTheme.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              step.state = isActive ? StudyStepState.inactive.json : StudyStepState.active.json;
              saveStudyStep();
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isActive ? AppTheme.primaryColor : (isDarkMode ? Colors.white24 : Colors.black26),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    StudyStepExt.fromString(step.studyStep).description,
                    style: TextStyle(
                      color: isActive ? AppTheme.primaryColor : (isDarkMode ? Colors.white70 : Colors.black87),
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.drag_indicator_rounded,
                  color: isDarkMode ? Colors.white10 : Colors.black12,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget renderStudySteps() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '学习模式',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const Spacer(),
              Text(
                '长按可调整顺序',
                style: TextStyle(
                  color: isDarkMode ? Colors.white24 : Colors.black26,
                  fontSize: 12,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: reorderData,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (int i = 0; i < studySteps!.length; i++)
                ReorderableDragStartListener(
                  key: ValueKey(studySteps![i].studyStep),
                  index: i,
                  child: _buildStepTile(studySteps![i]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> saveStudyStep() async {
    var result = await StudyBo().saveUserStudySteps(studySteps!);
    if (!result.success) {
      ToastUtil.error(result.msg!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

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
                    const Color(0xFFF8F9FA),
                    const Color(0xFFE9ECEF),
                    const Color(0xFFF8F9FA),
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            // 美化的AppBar
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: Get.currentRoute != '/index',
              leading: Get.currentRoute != '/index'
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      onPressed: () => Get.back(),
                    )
                  : null,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.gradientStartColor, AppTheme.gradientEndColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              title: const Text(
                '今日学习计划',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // 内容区域
            SliverToBoxAdapter(
              child: Container(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 80 - MediaQuery.of(context).padding.bottom,
                ),
                child: (!dataLoaded)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF0097A7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '正在加载学习计划...',
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                color: (isDarkMode ? Colors.white : const Color(0xFF2C3E50)).withValues(alpha: 0.7),
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                height: 1.3,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      )
                    : renderPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
