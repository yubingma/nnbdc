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
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/subscription_util.dart';

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
  bool _isLoadingData = false;

  @override
  void initState() {
    super.initState();
    Timer.run(() {
      if (mounted) {
        loadData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && !dataLoaded && !_isLoadingData) {
      Timer.run(() {
        if (mounted && !dataLoaded && !_isLoadingData) {
          loadData();
        }
      });
    }
  }

  Future<void> loadData({bool forceSupplement = false}) async {
    if (!forceSupplement) {
      _hasTriedSupplement = false;
    }
    if (_isLoadingData) return;
    _isLoadingData = true;

    Api.setLoadingDisabled(true);
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      var result0 = await UserBo().getLoggedInUser();
      if (result0.success) {
        user = result0.data;
      } else {
        ToastUtil.error(result0.msg!);
        return;
      }

      var result = await StudyBo().getUserStudySteps();
      if (result.success) {
        studySteps = [];
        List<UserStudyStepVo> userStudySteps = result.data!;
        for (UserStudyStepVo step in userStudySteps) {
          if (step.studyStep != 'List') {
            studySteps!.add(step);
          }
        }
      } else {
        ToastUtil.error(result.msg!);
        return;
      }

      try {
        prepareResult = await StudyBo().prepareForStudy(forceSupplement);
        if (prepareResult!.success || prepareResult!.code == "NNBDC-0012") {
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

      hasDakaToday = (await UserBo().hasDakaToday(user!.id!)).data!;

      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
      }
    } finally {
      Api.setLoadingDisabled(false);
      _isLoadingData = false;
    }
  }

  void reorderData(int oldIndex, int newIndex) {
    if (!mounted) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = studySteps!.removeAt(oldIndex);
      studySteps!.insert(newIndex, items);
      for (var i = 0; i < studySteps!.length; i++) {
        studySteps![i].seq = i;
      }
      saveStudyStep();
    });
  }

  List<UserStudyStepVo> selectedSteps() {
    return studySteps?.where((s) => s.state == StudyStepState.active.json).toList() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: (!dataLoaded)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.grey)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'LOADING PLAN...',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white54 : Colors.black26,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: backgroundColor,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  centerTitle: true,
                  title: Text(
                    '今日学习计划',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        renderMissionCard(),
                        const SizedBox(height: 24),
                        renderStudySteps(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget renderMissionCard() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardBg = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header: Goal Setting
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '今日目标',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (user?.todayStudyStarted == true) ...[
                      const SizedBox(width: 8),
                    Icon(
                      Icons.lock_outline_rounded,
                      color: isDarkMode ? Colors.white38 : Colors.black12,
                      size: 14,
                    ),
                    ],
                  ],
                ),
                renderGoalDropdown(),
              ],
            ),
          ),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatItem('今日总词', todayWordCount!, Icons.all_inclusive_rounded),
                const SizedBox(width: 12),
                _buildStatItem('新词', newWordCount!, Icons.fiber_new_rounded),
                const SizedBox(width: 12),
                _buildStatItem('复习', oldWordCount!, Icons.history_rounded),
              ],
            ),
          ),

          // Supplement Hint
          if (prepareResult!.success && todayWordCount! < user!.wordsPerDay! && !(user!.todayStudyStarted ?? false) && !_hasTriedSupplement)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: isDarkMode ? Colors.white54 : Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '任务量不足，建议补充',
                        style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.grey, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: isDarkMode ? Colors.white : Colors.black,
                      ),
                      onPressed: () => loadData(forceSupplement: true),
                      child: const Text('补充', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          // Action Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: (prepareResult?.code == "NNBDC-0012" || (_hasTriedSupplement && todayWordCount! < (user?.wordsPerDay ?? 0)))
                ? renderErrorActions()
                : renderStartButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.02),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget renderGoalDropdown() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final bool isStarted = user?.todayStudyStarted == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
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
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          dropdownColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          onChanged: isStarted
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
          items: [10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500].map((v) {
            final isPremium = SubscriptionUtil.isPremium();
            final isRestricted = !isPremium && v > 20;
            return DropdownMenuItem<int>(
              value: v,
              enabled: !isRestricted,
              child: Row(
                children: [
                  Text('$v'),
                  if (isRestricted) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.workspace_premium, color: Colors.amber, size: 12),
                  ]
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget renderStartButton() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    if (hasDakaToday) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.greenAccent.withValues(alpha: 0.1) : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: isDarkMode ? Colors.greenAccent : Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              '今日学习已达成',
              style: TextStyle(color: isDarkMode ? Colors.greenAccent : Colors.green.shade700, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
          foregroundColor: isDarkMode ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () async {
          if (selectedSteps().isEmpty) {
            ToastUtil.error('请选择至少一种学习模式');
            return;
          }
          if (user != null) {
            await MyDatabase.instance.userOpersDao.recordStartLearn(user!.id!, remark: "开始学习");
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
        child: Text(
          user?.todayStudyStarted == true ? '继续学习' : '开始学习',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
      ),
    );
  }

  Widget renderErrorActions() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('词书单词量不足', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDarkMode ? Colors.white : Colors.black,
                  side: BorderSide(color: isDarkMode ? Colors.white24 : Colors.black12),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Get.toNamed('/select_book')?.then((v) {
                  if (mounted) loadData(forceSupplement: true);
                }),
                child: const Text('更换词书', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (todayWordCount! > 0) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                    foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Get.toNamed('/bdc'),
                  child: const Text('就这样吧', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget renderStudySteps() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '学习模式',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '长按拖动排序',
                style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black26, fontSize: 11),
              ),
            ],
          ),
        ),
        ReorderableListView(
          buildDefaultDragHandles: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: reorderData,
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
    );
  }

  Widget _buildStepTile(UserStudyStepVo step) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final isActive = step.state == StudyStepState.active.json;

    return Container(
      key: ValueKey(step),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? (isDarkMode ? Colors.white30 : Colors.black87)
              : (isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              step.state = isActive ? StudyStepState.inactive.json : StudyStepState.active.json;
              saveStudyStep();
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isActive ? (isDarkMode ? Colors.white : Colors.black) : Colors.grey.shade400,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    StudyStepExt.fromString(step.studyStep).description,
                    style: TextStyle(
                      color: isActive ? (isDarkMode ? Colors.white : Colors.black) : (isDarkMode ? Colors.white54 : Colors.grey),
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                Icon(Icons.drag_indicator_rounded, color: Colors.grey.withValues(alpha: 0.3), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> saveStudyStep() async {
    await StudyBo().saveUserStudySteps(studySteps!);
  }
}
