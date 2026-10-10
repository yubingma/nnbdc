import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/user_extensions.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

/// 学习计划与词量设置独立二级页面
/// 包含：今日单词数、今日最少新词、每组单词数的高级调节与规则说明
class StudyPlanSettingsPage extends StatefulWidget {
  const StudyPlanSettingsPage({super.key});

  @override
  State<StudyPlanSettingsPage> createState() => _StudyPlanSettingsPageState();
}

class _StudyPlanSettingsPageState extends State<StudyPlanSettingsPage> {
  late int _initialWordsPerDay;
  late int _selectedWordsPerDay;

  late int _initialMinNewWords;
  late int _selectedMinNewWords;

  late int _initialBatchSize;
  late int _selectedBatchSize;

  late StudyConfig _config;
  bool _isStarted = false;
  bool _initialized = false;

  double _wordsPerDayDragAccumulator = 0;
  double _minNewWordsDragAccumulator = 0;
  double _batchSizeDragAccumulator = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final user = Global.getLoggedInUser();
    _config = StudyConfig.fromCurrentUser();
    _isStarted = user?.todayStudyStarted == true;

    _initialWordsPerDay = user?.effectiveWordsPerDay ?? 20;
    _selectedWordsPerDay = _initialWordsPerDay;

    _initialMinNewWords = _config.minNewWordsPerDay;
    _selectedMinNewWords = _initialMinNewWords.clamp(0, _selectedWordsPerDay);

    _initialBatchSize = _config.batchSize;
    _selectedBatchSize = _initialBatchSize.clamp(1, StudyConfig.maxBatchSize);

    _initialized = true;
  }

  Future<void> _saveSettingsIfChanged() async {
    if (_isStarted) return;
    final user = Global.getLoggedInUser();
    if (user == null) return;

    final hasWordsChanged = _selectedWordsPerDay != _initialWordsPerDay;
    final hasConfigChanged =
        _selectedMinNewWords != _initialMinNewWords || _selectedBatchSize != _initialBatchSize;

    if (hasWordsChanged || hasConfigChanged) {
      if (hasWordsChanged) {
        await MyDatabase.instance.usersDao.updateWordsPerDay(user.id, _selectedWordsPerDay);
        await Global.loadUserFromDb();
        ThrottledDbSyncService().requestSync();
      }
      if (hasConfigChanged) {
        _config.minNewWordsPerDay = _selectedMinNewWords;
        _config.batchSize = _selectedBatchSize;
        await _config.saveToCurrentUser();
      }
    }
  }

  void _handleSelectWordsPerDay(int v) {
    if (!UserPrivilegeManager.isDailyWordsAllowed(v)) {
      ToastUtil.info('开通会员可选择更多单词数量');
      return;
    }
    setState(() {
      _selectedWordsPerDay = v;
      if (_selectedMinNewWords > _selectedWordsPerDay) {
        _selectedMinNewWords = _selectedWordsPerDay;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final darkMode = context.watch<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _saveSettingsIfChanged();
        }
      },
      child: Scaffold(
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
            onPressed: () async {
              await _saveSettingsIfChanged();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            '学习计划设置',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isStarted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: isDarkMode ? Colors.white70 : Colors.black54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '今日学习已开始，学习计划与词量设置暂时锁定',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 1. 今日单词数卡片
              _buildSectionCard(
                isDarkMode: isDarkMode,
                title: '今日单词数',
                badgeText: _isStarted ? '$_selectedWordsPerDay 词' : null,
                child: Column(
                  children: [
                    if (!_isStarted) ...[
                      _buildStepper(
                        isDarkMode: isDarkMode,
                        valueText: '$_selectedWordsPerDay',
                        unitText: '词',
                        canMinus: _selectedWordsPerDay > 2,
                        canPlus: _selectedWordsPerDay < 500,
                        onMinus: () {
                          setState(() {
                            _selectedWordsPerDay = (_selectedWordsPerDay - 1).clamp(2, 500);
                            if (_selectedMinNewWords > _selectedWordsPerDay) {
                              _selectedMinNewWords = _selectedWordsPerDay;
                            }
                          });
                        },
                        onPlus: () {
                          final next = (_selectedWordsPerDay + 1).clamp(2, 500);
                          if (!UserPrivilegeManager.isDailyWordsAllowed(next)) {
                            ToastUtil.info('开通会员可选择更多单词数量');
                            return;
                          }
                          setState(() {
                            _selectedWordsPerDay = next;
                          });
                        },
                        onTapValue: () async {
                          final inputVal = await _showCustomNumberInputDialog(
                            parentContext: context,
                            title: '自定义今日单词数',
                            unit: '词',
                            min: 2,
                            max: 500,
                            subtitle: '范围 2 ~ 500 词',
                            currentValue: _selectedWordsPerDay,
                            primaryColor: primaryColor,
                            isDarkMode: isDarkMode,
                          );
                          if (inputVal != null) {
                            if (!UserPrivilegeManager.isDailyWordsAllowed(inputVal)) {
                              ToastUtil.info('开通会员可选择更多单词数量');
                              return;
                            }
                            setState(() {
                              _selectedWordsPerDay = inputVal;
                              if (_selectedMinNewWords > _selectedWordsPerDay) {
                                _selectedMinNewWords = _selectedWordsPerDay;
                              }
                            });
                          }
                        },
                        onHorizontalDragStart: (_) => _wordsPerDayDragAccumulator = 0,
                        onHorizontalDragUpdate: (details) {
                          _wordsPerDayDragAccumulator += details.primaryDelta ?? 0;
                          if (_wordsPerDayDragAccumulator.abs() >= 8.0) {
                            final dir = _wordsPerDayDragAccumulator > 0 ? 1 : -1;
                            _wordsPerDayDragAccumulator = 0;
                            final next = (_selectedWordsPerDay + dir).clamp(2, 500);
                            if (next != _selectedWordsPerDay) {
                              if (next > _selectedWordsPerDay && !UserPrivilegeManager.isDailyWordsAllowed(next)) {
                                return;
                              }
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedWordsPerDay = next;
                                if (_selectedMinNewWords > _selectedWordsPerDay) {
                                  _selectedMinNewWords = _selectedWordsPerDay;
                                }
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildQuickChip('5词', 5, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('10词', 10, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('20词', 20, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildQuickChip('30词', 30, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('50词', 50, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('100词', 100, _selectedWordsPerDay, _handleSelectWordsPerDay, primaryColor, isDarkMode)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. 今日最少新词卡片
              _buildSectionCard(
                isDarkMode: isDarkMode,
                title: '今日最少新词',
                badgeText: _isStarted ? '$_selectedMinNewWords 词' : null,
                actionIcon: Icons.help_outline_rounded,
                onActionTap: () => _showMinNewWordsExplanationDialog(context),
                child: Column(
                  children: [
                    if (!_isStarted) ...[
                      _buildStepper(
                        isDarkMode: isDarkMode,
                        valueText: _selectedMinNewWords == 0 ? '不限制' : '$_selectedMinNewWords',
                        unitText: _selectedMinNewWords == 0 ? '' : '词',
                        canMinus: _selectedMinNewWords > 0,
                        canPlus: _selectedMinNewWords < _selectedWordsPerDay,
                        onMinus: () {
                          setState(() {
                            _selectedMinNewWords = (_selectedMinNewWords - 1).clamp(0, _selectedWordsPerDay);
                          });
                        },
                        onPlus: () {
                          setState(() {
                            _selectedMinNewWords = (_selectedMinNewWords + 1).clamp(0, _selectedWordsPerDay);
                          });
                        },
                        onTapValue: () async {
                          final inputVal = await _showCustomNumberInputDialog(
                            parentContext: context,
                            title: '自定义最少新词数',
                            unit: '词',
                            min: 0,
                            max: _selectedWordsPerDay,
                            subtitle: '范围 0 ~ $_selectedWordsPerDay 词 (0 为不限制)',
                            currentValue: _selectedMinNewWords,
                            primaryColor: primaryColor,
                            isDarkMode: isDarkMode,
                          );
                          if (inputVal != null) {
                            setState(() {
                              _selectedMinNewWords = inputVal.clamp(0, _selectedWordsPerDay);
                            });
                          }
                        },
                        onHorizontalDragStart: (_) => _minNewWordsDragAccumulator = 0,
                        onHorizontalDragUpdate: (details) {
                          _minNewWordsDragAccumulator += details.primaryDelta ?? 0;
                          if (_minNewWordsDragAccumulator.abs() >= 8.0) {
                            final dir = _minNewWordsDragAccumulator > 0 ? 1 : -1;
                            _minNewWordsDragAccumulator = 0;
                            final next = (_selectedMinNewWords + dir).clamp(0, _selectedWordsPerDay);
                            if (next != _selectedMinNewWords) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedMinNewWords = next;
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildQuickChip('不限制', 0, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('5词', 5, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode, enabled: _selectedWordsPerDay >= 5)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('10词', 10, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode, enabled: _selectedWordsPerDay >= 10)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildQuickChip('20词', 20, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode, enabled: _selectedWordsPerDay >= 20)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('30词', 30, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode, enabled: _selectedWordsPerDay >= 30)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildQuickChip('全学新词', _selectedWordsPerDay, _selectedMinNewWords, (v) => setState(() => _selectedMinNewWords = v), primaryColor, isDarkMode, enabled: _selectedWordsPerDay > 0)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 3. 每组单词数卡片
              _buildSectionCard(
                isDarkMode: isDarkMode,
                title: '每组单词数',
                badgeText: _isStarted ? '$_selectedBatchSize 词/组' : null,
                child: Column(
                  children: [
                    if (!_isStarted) ...[
                      _buildStepper(
                        isDarkMode: isDarkMode,
                        valueText: '$_selectedBatchSize',
                        unitText: '词/组',
                        canMinus: _selectedBatchSize > 1,
                        canPlus: _selectedBatchSize < StudyConfig.maxBatchSize,
                        onMinus: () {
                          setState(() {
                            _selectedBatchSize = (_selectedBatchSize - 1).clamp(1, StudyConfig.maxBatchSize);
                          });
                        },
                        onPlus: () {
                          setState(() {
                            _selectedBatchSize = (_selectedBatchSize + 1).clamp(1, StudyConfig.maxBatchSize);
                          });
                        },
                        onTapValue: () async {
                          final inputVal = await _showCustomNumberInputDialog(
                            parentContext: context,
                            title: '自定义每组单词数',
                            unit: '词',
                            min: 1,
                            max: StudyConfig.maxBatchSize,
                            subtitle: '范围 1 ~ ${StudyConfig.maxBatchSize} 词/组',
                            currentValue: _selectedBatchSize,
                            primaryColor: primaryColor,
                            isDarkMode: isDarkMode,
                          );
                          if (inputVal != null) {
                            setState(() {
                              _selectedBatchSize = inputVal.clamp(1, StudyConfig.maxBatchSize);
                            });
                          }
                        },
                        onHorizontalDragStart: (_) => _batchSizeDragAccumulator = 0,
                        onHorizontalDragUpdate: (details) {
                          _batchSizeDragAccumulator += details.primaryDelta ?? 0;
                          final threshold = _selectedBatchSize > 50 ? 6.0 : 8.0;
                          if (_batchSizeDragAccumulator.abs() >= threshold) {
                            final dir = _batchSizeDragAccumulator > 0 ? 1 : -1;
                            final step = _selectedBatchSize > 100
                                ? dir * 5
                                : (_selectedBatchSize > 30 ? dir * 2 : dir);
                            _batchSizeDragAccumulator = 0;
                            final next = (_selectedBatchSize + step).clamp(1, StudyConfig.maxBatchSize);
                            if (next != _selectedBatchSize) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedBatchSize = next;
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final chip in [5, 10, 20, 30, 50]) ...[
                            if (chip != 5) const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickChip(
                                '$chip词',
                                chip,
                                _selectedBatchSize,
                                (v) => setState(() => _selectedBatchSize = v),
                                primaryColor,
                                isDarkMode,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDarkMode,
    required String title,
    String? badgeText,
    IconData? actionIcon,
    VoidCallback? onActionTap,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF161C26) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  if (actionIcon != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onActionTap,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          actionIcon,
                          size: 16,
                          color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 13, color: isDarkMode ? Colors.white54 : Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (child is! SizedBox) ...[
            const SizedBox(height: 14),
            child,
          ],
        ],
      ),
    );
  }

  Widget _buildStepper({
    required bool isDarkMode,
    required String valueText,
    required String unitText,
    required bool canMinus,
    required bool canPlus,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required VoidCallback onTapValue,
    required GestureDragStartCallback onHorizontalDragStart,
    required GestureDragUpdateCallback onHorizontalDragUpdate,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _StepBtn(
            icon: Icons.remove_rounded,
            enabled: canMinus,
            onTap: onMinus,
            isDarkMode: isDarkMode,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapValue,
              onHorizontalDragStart: onHorizontalDragStart,
              onHorizontalDragUpdate: onHorizontalDragUpdate,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: valueText,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              fontFamily: RegExp(r'^\d+$').hasMatch(valueText) ? 'Roboto' : null,
                              color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          if (unitText.isNotEmpty)
                            TextSpan(
                              text: ' $unitText',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _StepBtn(
            icon: Icons.add_rounded,
            enabled: canPlus,
            onTap: onPlus,
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(
    String label,
    int value,
    int selectedValue,
    ValueChanged<int> onSelect,
    Color primaryColor,
    bool isDarkMode, {
    bool enabled = true,
  }) {
    final isSelected = enabled && value == selectedValue;

    return GestureDetector(
      onTap: enabled ? () => onSelect(value) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? (isDarkMode ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02))
              : isSelected
                  ? primaryColor
                  : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: !enabled
                ? Colors.transparent
                : isSelected
                    ? Colors.transparent
                    : (isDarkMode ? const Color(0x20FFFFFF) : Colors.black.withValues(alpha: 0.04)),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: !enabled
                ? (isDarkMode ? Colors.white24 : const Color(0xFFCBD5E1))
                : isSelected
                    ? Colors.white
                    : (isDarkMode ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Future<int?> _showCustomNumberInputDialog({
    required BuildContext parentContext,
    required String title,
    required String unit,
    required int min,
    required int max,
    required String subtitle,
    required int currentValue,
    required Color primaryColor,
    required bool isDarkMode,
  }) {
    final textController = TextEditingController(text: '$currentValue');
    textController.selection = TextSelection(baseOffset: 0, extentOffset: textController.text.length);
    String? errorText;

    return showGeneralDialog<int>(
      context: parentContext,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setInputState) {
          void submit() {
            final text = textController.text.trim();
            final val = int.tryParse(text);
            if (val == null) {
              setInputState(() => errorText = '请输入有效整数');
              return;
            }
            if (val < min || val > max) {
              setInputState(() => errorText = '范围必须在 $min ~ $max 之间');
              return;
            }
            Navigator.pop(ctx, val);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 36),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                color: isDarkMode ? const Color(0xFF1E2532) : Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white38 : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: textController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Roboto',
                        color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: '输入数量',
                        suffixText: unit,
                        errorText: errorText,
                        filled: true,
                        fillColor: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white54 : const Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMinNewWordsExplanationDialog(BuildContext parentCtx) {
    final darkMode = parentCtx.read<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;

    showGeneralDialog<void>(
      context: parentCtx,
      barrierDismissible: true,
      barrierLabel: '今日最少新词规则说明',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E2532) : Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日最少新词规则说明',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '• 系统默认根据记忆遗忘曲线优先安排复习。当待复习词较多时，今日配额可能全部被复习词占满。\n\n• 设置此项后，系统每天会强制保留至少指定数量的新词，保障背词进度稳步向前。\n\n• 注意：若长期强行调高新词比例，会导致前置复习词延期，请根据实际复习负荷理性平衡。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDarkMode ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('我知道了', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  State<_StepBtn> createState() => _StepBtnState();
}

class _StepBtnState extends State<_StepBtn> {
  Timer? _initialTimer;
  Timer? _periodicTimer;

  void _start() {
    if (!widget.enabled) return;
    widget.onTap();
    _initialTimer = Timer(const Duration(milliseconds: 350), () {
      _periodicTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
        if (!widget.enabled) {
          _cancel();
          return;
        }
        widget.onTap();
      });
    });
  }

  void _cancel() {
    _initialTimer?.cancel();
    _periodicTimer?.cancel();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: widget.enabled
              ? (widget.isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.enabled
                ? (widget.isDarkMode ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06))
                : Colors.transparent,
          ),
        ),
        child: Icon(
          widget.icon,
          size: 18,
          color: widget.enabled
              ? (widget.isDarkMode ? Colors.white : const Color(0xFF0F172A))
              : (widget.isDarkMode ? Colors.white24 : Colors.black26),
        ),
      ),
    );
  }
}
