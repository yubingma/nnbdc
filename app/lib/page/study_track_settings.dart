import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/study_steps_service.dart';
import 'package:provider/provider.dart';

/// 学习轨道独立二级设置页面
/// 支持自定义新词与旧词的测评题型起点及答对/答错流转路线
class StudyTrackSettingsPage extends StatefulWidget {
  const StudyTrackSettingsPage({super.key});

  @override
  State<StudyTrackSettingsPage> createState() => _StudyTrackSettingsPageState();
}

class _StudyTrackSettingsPageState extends State<StudyTrackSettingsPage> {
  static const List<String> _allStepNames = [
    'En2Ch',
    'Ch2En',
    'EnSentence2Ch',
    'ChSentence2En',
  ];

  bool _isLoading = true;

  String _newCheckStep = 'En2Ch';
  List<String> _newCorrectSteps = ['Ch2En'];
  List<String> _newWrongSteps = ['Ch2En'];

  String _reviewCheckStep = 'En2Ch';
  List<String> _reviewCorrectSteps = [];
  List<String> _reviewWrongSteps = ['Ch2En'];

  @override
  void initState() {
    super.initState();
    _loadTrackConfigs();
  }

  Future<void> _loadTrackConfigs() async {
    try {
      final service = StudyStepsService();
      final newCfg = await service.getThreeGroupConfig('new');
      final reviewCfg = await service.getThreeGroupConfig('review');
      if (mounted) {
        setState(() {
          _newCheckStep = newCfg.check;
          _newCorrectSteps = List<String>.from(newCfg.correct);
          _newWrongSteps = List<String>.from(newCfg.wrong);

          _reviewCheckStep = reviewCfg.check;
          _reviewCorrectSteps = List<String>.from(reviewCfg.correct);
          _reviewWrongSteps = List<String>.from(reviewCfg.wrong);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig(String scope) async {
    final isNew = scope == 'new';
    try {
      await StudyStepsService().saveThreeGroupConfig(
        scope: scope,
        check: isNew ? _newCheckStep : _reviewCheckStep,
        correct: isNew ? _newCorrectSteps : _reviewCorrectSteps,
        wrong: isNew ? _newWrongSteps : _reviewWrongSteps,
      );
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '学习轨道设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部引导文案
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 18),
                    child: Text(
                      '新词/旧词设置不同的学习轨道，可节约学习时间。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDarkMode ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                  ),

                  // 1. 新词轨道卡片
                  _buildTrackSection(
                    title: '新词轨道',
                    scope: 'new',
                    accentColor: themeConfig.primaryColor,
                    checkStep: _newCheckStep,
                    correctSteps: _newCorrectSteps,
                    wrongSteps: _newWrongSteps,
                    isDarkMode: isDarkMode,
                    themeConfig: themeConfig,
                  ),

                  const SizedBox(height: 20),

                  // 2. 旧词轨道卡片
                  _buildTrackSection(
                    title: '旧词轨道',
                    scope: 'review',
                    accentColor: isDarkMode ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                    checkStep: _reviewCheckStep,
                    correctSteps: _reviewCorrectSteps,
                    wrongSteps: _reviewWrongSteps,
                    isDarkMode: isDarkMode,
                    themeConfig: themeConfig,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTrackSection({
    required String title,
    required String scope,
    required Color accentColor,
    required String checkStep,
    required List<String> correctSteps,
    required List<String> wrongSteps,
    required bool isDarkMode,
    required AppThemeConfig themeConfig,
  }) {
    final isNew = scope == 'new';

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 轨道标题栏
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 测评环节选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 17, color: accentColor),
                    const SizedBox(width: 8),
                    Text(
                      '测评环节',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: checkStep,
                    isDense: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: isDarkMode ? Colors.white60 : const Color(0xFF64748B),
                    ),
                    dropdownColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final s in _allStepNames)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            StudyStepExt.fromString(s).description,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          if (isNew) {
                            _newCheckStep = v;
                          } else {
                            _reviewCheckStep = v;
                          }
                        });
                        unawaited(_saveConfig(scope));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 答对分支
          _buildBranchGroup(
            scope: scope,
            title: '答对后环节',
            icon: Icons.check_circle_rounded,
            titleColor: isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669),
            emptyHint: '直接结束（无需巩固）',
            steps: correctSteps,
            isCorrect: true,
            isDarkMode: isDarkMode,
          ),

          const SizedBox(height: 14),

          // 答错分支
          _buildBranchGroup(
            scope: scope,
            title: '答错后环节',
            icon: Icons.cancel_rounded,
            titleColor: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
            emptyHint: '直接结束（标记错误）',
            steps: wrongSteps,
            isCorrect: false,
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildBranchGroup({
    required String scope,
    required String title,
    required IconData icon,
    required Color titleColor,
    required String emptyHint,
    required List<String> steps,
    required bool isCorrect,
    required bool isDarkMode,
  }) {
    final bool canAdd = _allStepNames.any((s) => !steps.contains(s));
    final isNew = scope == 'new';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: titleColor),
                const SizedBox(width: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            if (canAdd)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickStepDialog(scope, isCorrect: isCorrect),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: titleColor),
                      const SizedBox(width: 2),
                      Text(
                        '添加环节',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (steps.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFEEF2F6),
              ),
            ),
            child: Text(
              emptyHint,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: steps.length,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final targetList = isNew
                    ? (isCorrect ? _newCorrectSteps : _newWrongSteps)
                    : (isCorrect ? _reviewCorrectSteps : _reviewWrongSteps);
                final item = targetList.removeAt(oldIndex);
                targetList.insert(newIndex, item);
              });
              unawaited(_saveConfig(scope));
            },
            itemBuilder: (context, index) {
              final stepName = steps[index];
              return Container(
                key: ValueKey('$scope-$isCorrect-$stepName'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.drag_indicator_rounded, size: 16, color: isDarkMode ? Colors.white24 : Colors.black26),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: titleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '步骤 ${index + 1}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: titleColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        StudyStepExt.fromString(stepName).description,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final targetList = isNew
                              ? (isCorrect ? _newCorrectSteps : _newWrongSteps)
                              : (isCorrect ? _reviewCorrectSteps : _reviewWrongSteps);
                          targetList.remove(stepName);
                        });
                        unawaited(_saveConfig(scope));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 15, color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _pickStepDialog(String scope, {required bool isCorrect}) async {
    final isNew = scope == 'new';
    final current = isNew
        ? (isCorrect ? _newCorrectSteps : _newWrongSteps)
        : (isCorrect ? _reviewCorrectSteps : _reviewWrongSteps);
    final available = _allStepNames.where((s) => !current.contains(s)).toList();
    if (available.isEmpty) return;

    final darkMode = context.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final color = isCorrect
        ? (isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669))
        : (isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706));

    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.25),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1C2230) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? '添加答对后环节' : '添加答错后环节',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final item in available) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(ctx, item),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              StudyStepExt.fromString(item).description,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            Icon(Icons.add_rounded, size: 16, color: color),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        final targetList = isNew
            ? (isCorrect ? _newCorrectSteps : _newWrongSteps)
            : (isCorrect ? _reviewCorrectSteps : _reviewWrongSteps);
        targetList.add(picked);
      });
      unawaited(_saveConfig(scope));
    }
  }
}
