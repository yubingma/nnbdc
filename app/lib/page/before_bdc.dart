import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';

import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

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

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  void reorderData(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = studySteps!.removeAt(oldIndex);
      studySteps!.insert(newIndex, items);

      // 重新计算每个study step的顺序号
      for (var i = 0; i < studySteps!.length; i++) {
        studySteps![i].index = i;
      }

      saveStudyStep();
    });
  }

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
    if (mounted) {
      Timer.run(() {
        if (mounted) {
          loadData();
        }
      });
    }
  }

  Future<void> loadData() async {
    // 禁用loading提示
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
          studySteps!.add(step);
        }
      } else {
        ToastUtil.error(result.msg!);
        return;
      }

      // 生成（或获取）用户的今日单词
      try {
        prepareResult = await StudyBo().prepareForStudy(false);
        if (prepareResult!.success || prepareResult!.code == "NNBDC-0012" /*未取到足够单词*/) {
          List<int> counts = prepareResult!.data!;
          newWordCount = counts[0];
          oldWordCount = counts[1];
          todayWordCount = newWordCount! + oldWordCount!;
        } else {
          ToastUtil.error(prepareResult!.msg!);
          return;
        }
      } catch (e) {
        ToastUtil.error('准备学习失败: $e');
        return;
      }

      // 获取用户的今日打卡状态
      hasDakaToday = (await UserBo().hasDakaToday(user!.id!)).data!;

      setState(() {
        dataLoaded = true;
      });
    } finally {
      // 重新启用loading提示
      Api.setLoadingDisabled(false);
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
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return SingleChildScrollView(
      child: Column(
        children: [
          renderStudySteps(),
          // 统计信息卡片
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                // 今日学习概览卡片
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF0097A7).withValues(alpha: 0.1),
                        const Color(0xFF00ACC1).withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF0097A7).withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0097A7).withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 标题
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.today_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '今日学习概览',
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : const Color(0xFF2C3E50),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // 统计数据网格
                      Row(
                        children: [
                          // 总单词数
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                toTodayWordsListPage(!user!.isTodayLearningStarted!)?.then((value) => loadData());
                              },
                              child: Container(
                                height: 152, // 70 + 12 + 70 = 152 (新词高度 + 间距 + 旧词高度)
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.library_books_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 30,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '${todayWordCount!}',
                                      textScaler: TextScaler.linear(1.0),
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '今日单词',
                                      textScaler: TextScaler.linear(1.0),
                                      style: TextStyle(
                                        fontFamily: 'NotoSansSC',
                                        color: isDarkMode ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF495057),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.5,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // 新词和旧词
                          Expanded(
                            child: Column(
                              children: [
                                // 新词
                                GestureDetector(
                                  onTap: () {
                                    toTodayNewWordsListPage(!user!.isTodayLearningStarted!)?.then((value) => loadData());
                                  },
                                  child: Container(
                                    height: 70, // 设置固定高度
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.fiber_new_rounded,
                                              color: AppTheme.primaryColor,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${newWordCount!}',
                                              textScaler: TextScaler.linear(1.0),
                                              style: TextStyle(
                                                color: AppTheme.primaryColor,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '新词',
                                          textScaler: TextScaler.linear(1.0),
                                          style: TextStyle(
                                            fontFamily: 'NotoSansSC',
                                            color: isDarkMode ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF495057),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.5,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // 旧词
                                GestureDetector(
                                  onTap: () {
                                    toTodayOldWordsListPage(!user!.isTodayLearningStarted!)?.then((value) => loadData());
                                  },
                                  child: Container(
                                    height: 70, // 设置固定高度
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.refresh_rounded,
                                              color: AppTheme.primaryColor,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${oldWordCount!}',
                                              textScaler: TextScaler.linear(1.0),
                                              style: TextStyle(
                                                color: AppTheme.primaryColor,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '旧词',
                                          textScaler: TextScaler.linear(1.0),
                                          style: TextStyle(
                                            fontFamily: 'NotoSansSC',
                                            color: isDarkMode ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF495057),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.5,
                                            height: 1.2,
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
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                // 主要操作按钮
                if (prepareResult!.success)
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    child: hasDakaToday
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '今日已打卡',
                                  textScaler: TextScaler.linear(1.0),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: MediaQuery.of(context).size.width > 600 ? 20 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 4,
                                shadowColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                              ),
                              icon: Icon(
                                Icons.play_arrow_rounded,
                                size: MediaQuery.of(context).size.width > 600 ? 28 : 24,
                              ),
                              key: const Key('before_bdc_start_learn_btn'),
                              label: Text(
                                '开始学习',
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                  fontSize: MediaQuery.of(context).size.width > 600 ? 20 : 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              onPressed: () async {
                                if (selectedSteps().isEmpty) {
                                  ToastUtil.error('请至少选择一个学习方式');
                                  return;
                                }

                                // 记录用户开始学习操作
                                if (user != null) {
                                  await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "用户开始学习");
                                }

                                await GetStorage().write("BdcPageArgs", BdcPageArgs('before_bdc').toJson());
                                Get.toNamed('/bdc');
                              },
                            ),
                          ),
                  ),
                // 错误提示和备选操作
                if (prepareResult!.code == "NNBDC-0012")
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.warning_rounded,
                                color: Color(0xFFFF5252),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '没有取到足够单词',
                                textScaler: TextScaler.linear(1.0),
                                style: const TextStyle(
                                  color: Color(0xFFFF5252),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // 操作按钮
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.library_books, size: 18),
                                label: Text(
                                  '选择词书',
                                  textScaler: TextScaler.linear(1.0),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onPressed: () {
                                  Get.toNamed('/select_book')?.then((value) => loadData());
                                },
                              ),
                            ),
                            if (todayWordCount! < user!.wordsPerDay! && todayWordCount! > 0) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF9800),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: Text(
                                    '继续学习',
                                    textScaler: TextScaler.linear(1.0),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                // 底部间距
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget renderStudySteps() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : Colors.white;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDarkMode ? Colors.black : const Color(0xFF0097A7)).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // 简洁的标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.list_alt_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '学习方式',
                  textScaler: TextScaler.linear(1.0),
                  style: const TextStyle(
                    fontFamily: 'NotoSansSC',
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // 现代化的学习方式列表
          Container(
            height: 128,
            padding: const EdgeInsets.all(12),
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorder: reorderData,
              shrinkWrap: true,
              itemExtent: 48, // 固定每个item的高度（两项更紧凑）
              children: <Widget>[
                for (final step in studySteps!)
                  ReorderableDragStartListener(
                    key: ValueKey(step),
                    index: step.index,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() {
                            step.state = step.state == StudyStepState.active.json ? StudyStepState.inactive.json : StudyStepState.active.json;
                            saveStudyStep();
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: step.state == StudyStepState.active.json
                                  ? (isDarkMode ? const Color(0xFF2D3748) : const Color(0xFFF0F4F8))
                                  : (isDarkMode ? const Color(0xFF1A202C) : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: step.state == StudyStepState.active.json
                                    ? AppTheme.primaryColor
                                    : (isDarkMode ? const Color(0xFF404040) : const Color(0xFFE2E8F0)),
                                width: step.state == StudyStepState.active.json ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // 状态指示器
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: step.state == StudyStepState.active.json ? AppTheme.primaryColor : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: step.state == StudyStepState.active.json
                                          ? AppTheme.primaryColor
                                          : (isDarkMode ? const Color(0xFF666666) : const Color(0xFFADB5BD)),
                                      width: 2,
                                    ),
                                  ),
                                  child: step.state == StudyStepState.active.json
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 10,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),

                                // 步骤文本
                                Expanded(
                                  child: Text(
                                    StudyStepExt.fromString(step.studyStep).description,
                                    textScaler: TextScaler.linear(1.0),
                                    style: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      color: step.state == StudyStepState.active.json
                                          ? AppTheme.primaryColor
                                          : (isDarkMode ? const Color(0xFFE9ECEF) : const Color(0xFF495057)),
                                      fontSize: 15,
                                      fontWeight: step.state == StudyStepState.active.json ? FontWeight.w500 : FontWeight.w400,
                                      letterSpacing: 0.5,
                                      height: 1.3,
                                    ),
                                  ),
                                ),

                                // 拖拽指示器
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    color: isDarkMode ? const Color(0xFF666666) : const Color(0xFFADB5BD),
                                    size: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
              expandedHeight: 88,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: Get.currentRoute != '/index',
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.gradientStartColor,
                        AppTheme.gradientEndColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 主要内容层
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.school,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '今日学习计划',
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
                                  '开始你的学习之旅',
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
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
