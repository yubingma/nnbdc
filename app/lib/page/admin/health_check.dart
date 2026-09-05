import 'package:flutter/material.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';
import 'package:nnbdc/util/error_handler.dart';

/// 健康检查页面
class HealthCheckPage extends StatefulWidget {
  final bool autoStart;
  const HealthCheckPage({super.key, this.autoStart = false});

  @override
  State<HealthCheckPage> createState() => _HealthCheckPageState();
}

class _HealthCheckPageState extends State<HealthCheckPage> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runDiagnostic();
      });
    }
  }

  bool _isRunning = false;
  IntegrityCheckResult? _checkResult;

  // 每项检查的状态：null=未开始, false=进行中, true=通过, 'failed'=失败
  final Map<int, dynamic> _checkStates = {}; // 1=序号, 2=数量, 3=学习进度, 4=版本, 5=通用词典
  final Map<int, String?> _checkMessages = {};

  static const List<Map<String, dynamic>> _checkItems = [
    {
      'id': 1,
      'title': '您的词典单词序号连续性',
      'step': 1,
      'category': 'dict_word_sequence'
    },
    {'id': 2, 'title': '您的词典单词数量一致性', 'step': 2, 'category': 'dict_word_count'},
    {'id': 3, 'title': '您的学习步骤完整性', 'step': 3, 'category': 'user_study_steps'},
    {'id': 4, 'title': '您的数据库版本一致性', 'step': 4, 'category': 'user_db_version'},
    {
      'id': 5,
      'title': '通用词典完整性',
      'step': 5,
      'category': 'common_dict_integrity'
    },
    {'id': 6, 'title': '您的词书完整性', 'step': 6, 'category': 'missing_user_dict'},
    {
      'id': 7,
      'title': '书桌系统词库底层托底',
      'step': 7,
      'category': 'sys_dict_missing_fallback'
    },
    {
      'id': 8,
      'title': '正在学习单词的释义完整性',
      'step': 8,
      'category': 'learning_word_missing_meaning'
    },
    {'id': 9, 'title': '网络连接', 'step': 9, 'category': 'network_connectivity'},
    {'id': 10, 'title': '后端服务器连通性', 'step': 10, 'category': 'backend_server'},
    {'id': 11, 'title': '游戏服务器连通性', 'step': 11, 'category': 'game_server'},
    {
      'id': 12,
      'title': '本地TTS功能',
      'step': 12,
      'category': 'local_tts'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '健康检查',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: '返回',
          splashRadius: 22,
        ),
        actions: [
          if (_checkResult != null && _checkResult!.hasIssues)
            IconButton(
              onPressed: _isRunning ? null : _runAutoFix,
              icon: Icon(Icons.auto_fix_high_rounded, color: theme.primaryColor, size: 22),
              tooltip: '一键自动修复',
              splashRadius: 22,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildContent(theme, isDark),
    );
  }

  Widget _buildContent(AppThemeConfig theme, bool isDark) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 核心检查项聚合卡片
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.cardBorder, width: 0.8),
              boxShadow: theme.cardShadows,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 卡片头部
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.health_and_safety_rounded,
                        size: 22,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '系统与数据健康诊断',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '实时诊断 12 项本地数据库、学习进度与网络状态',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                // 检查项列表
                ..._checkItems.map((item) => _buildCheckItemWithStatus(
                      item['title'] as String,
                      _checkStates[item['id'] as int],
                      theme,
                      isDark,
                      item['category'] as String,
                    )),
              ],
            ),
          ),
          // 检查结果提示卡片
          if (_checkResult != null) ...[
            const SizedBox(height: 14),
            _buildResultSummary(theme, isDark),
          ],
          const SizedBox(height: 18),
          // 底部开始/重新检查主按钮（最新美学：薄雾微光底 + 精细描边 + 主题色文字与图标）
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isRunning ? null : _runDiagnostic,
              borderRadius: BorderRadius.circular(100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: theme.primaryColor.withValues(alpha: isDark ? 0.35 : 0.22),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withValues(alpha: isDark ? 0.15 : 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isRunning) ...[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      Icon(
                        _checkResult == null ? Icons.search_rounded : Icons.refresh_rounded,
                        size: 18,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _isRunning
                          ? '正在全面自检中...'
                          : (_checkResult == null ? '开始检查' : '重新检查'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                        letterSpacing: 0.2,
                      ),
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

  Widget _buildResultSummary(AppThemeConfig theme, bool isDark) {
    final checkItemCategories =
        _checkItems.map((item) => item['category'] as String).toSet();

    final categorizedIssues = _checkResult!.issues.where((issue) {
      return checkItemCategories.contains(issue.category);
    }).toList();

    final hasFailedCheckItem =
        _checkStates.values.any((state) => state == 'failed');

    final categorizedIssueCount = categorizedIssues.length;
    final errorCount = _checkResult!.errors.length;
    final totalIssues = categorizedIssueCount + errorCount;
    final isHealthy = !hasFailedCheckItem && totalIssues == 0;

    final accentStatusColor =
        isHealthy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accentStatusColor.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentStatusColor.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isHealthy ? Icons.verified_rounded : Icons.warning_amber_rounded,
            color: accentStatusColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy ? '检查完成，所有项目状态良好' : '发现 $totalIssues 处状态异常',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isHealthy ? '本地数据库结构完好，数据与网络状态健康' : '可点击各项右侧详情或上方一键修复',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!isHealthy)
            TextButton(
              onPressed: _isRunning ? null : _runAutoFix,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: accentStatusColor.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              ),
              child: Text(
                '一键修复',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentStatusColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckItemWithStatus(
      String text, dynamic status, AppThemeConfig theme, bool isDark, String category) {
    Widget iconWidget;
    Color textColor = theme.textSecondary;
    bool isFailed = false;

    if (status == null) {
      // 尚未检查：轻淡细圆圈
      iconWidget = Icon(
        Icons.radio_button_unchecked_rounded,
        size: 15,
        color: theme.textMuted.withValues(alpha: 0.35),
      );
    } else if (status == false) {
      // 正在进行中：微型转圈动画
      iconWidget = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
        ),
      );
      textColor = theme.primaryColor;
    } else if (status == true) {
      // 通过：翡翠绿微对勾
      iconWidget = const Icon(
        Icons.check_circle_rounded,
        size: 16,
        color: Color(0xFF10B981),
      );
    } else {
      // 失败：珊瑚红错误图标
      iconWidget = const Icon(
        Icons.error_rounded,
        size: 16,
        color: Color(0xFFEF4444),
      );
      textColor = const Color(0xFFEF4444);
      isFailed = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.5),
      child: Row(
        children: [
          Container(
            width: 20,
            alignment: Alignment.centerLeft,
            child: iconWidget,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isFailed ? FontWeight.w600 : FontWeight.w400,
                color: textColor,
              ),
            ),
          ),
          if (isFailed && _checkResult != null)
            GestureDetector(
              onTap: () => _showIssueDetails(category, text),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '详情',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: Color(0xFFEF4444),
                    ),
                  ],
                ),
              ),
            )
          else if (status == true)
            Text(
              '正常',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF10B981).withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  // 显示问题详情抽屉
  void _showIssueDetails(String category, String title) {
    if (_checkResult == null) return;
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    final relatedIssues = _checkResult!.issues
        .where((issue) => issue.category == category)
        .toList();

    if (relatedIssues.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部手柄
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textMuted.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 抽屉头部
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          '发现 ${relatedIssues.length} 项具体异常',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: theme.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: relatedIssues.map((issue) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.subtleBg.withValues(alpha: isDark ? 0.3 : 0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.cardBorder, width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            issue.type,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            issue.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          if (issue.logMessage != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                issue.logMessage!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: theme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: () => _fixIssues(context, relatedIssues),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                    foregroundColor: theme.primaryColor,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    side: BorderSide(
                      color: theme.primaryColor.withValues(alpha: isDark ? 0.4 : 0.25),
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                  child: const Text(
                    '立即修复此项异常',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDiagnostic() async {
    // 重置所有检查状态
    setState(() {
      _isRunning = true;
      _checkResult = null;
      _checkStates.clear();
      _checkMessages.clear();
    });

    try {
      // 获取当前登录用户ID
      final currentUser = Global.getLoggedInUser();
      if (currentUser == null) {
        throw Exception('用户未登录');
      }

      // 使用本地数据完整性检查器进行诊断
      final checker = DataIntegrityChecker();

      final IntegrityCheckResult checkResult = await checker.performUserCheck(
        currentUser.id,
        onProgress: (step, message, {IntegrityCheckResult? result}) async {
          if (mounted) {
            // 找到对应的检查项
            final checkItem = _checkItems.firstWhere(
              (item) => item['step'] == step,
              orElse: () => {},
            );

            if (checkItem.isNotEmpty) {
              final int itemId = checkItem['id'] as int;

              if (result == null) {
                // 刚开始检查，设置为进行中状态
                setState(() {
                  _checkStates[itemId] = false; // false 表示进行中
                });
              } else {
                // 检查完成，设置结果
                final String category = checkItem['category'] as String;
                final hasIssue =
                    result.issues.any((issue) => issue.category == category);

                setState(() {
                  _checkStates[itemId] =
                      hasIssue ? 'failed' : true; // true=通过, 'failed'=有问题
                });
              }
            }
          }
        },
      );

      // 检查完成后，统一更新所有项的状态
      setState(() {
        // 获取所有检查项的 category
        final checkItemCategories =
            _checkItems.map((item) => item['category'] as String).toSet();

        // 检查是否有未分类的问题
        final uncategorizedIssues = checkResult.issues
            .where((issue) => !checkItemCategories.contains(issue.category))
            .toList();

        if (uncategorizedIssues.isNotEmpty) {
          Global.logger.w(
              '发现 ${uncategorizedIssues.length} 个未分类的问题: ${uncategorizedIssues.map((i) => i.category).join(", ")}');
        }

        // 检查是否有 errors
        if (checkResult.errors.isNotEmpty) {
          Global.logger.w(
              '发现 ${checkResult.errors.length} 个错误: ${checkResult.errors.join(", ")}');
        }

        for (var item in _checkItems) {
          final int itemId = item['id'] as int;
          final String category = item['category'] as String;
          // 检查是否有这个类别的问题
          final hasIssue =
              checkResult.issues.any((issue) => issue.category == category);
          _checkStates[itemId] =
              hasIssue ? 'failed' : true; // true=通过, 'failed'=有问题
        }

        _checkResult = checkResult;
        _isRunning = false;
      });
    } catch (e, stackTrace) {
      setState(() {
        _isRunning = false;
      });

      // 记录详细的错误信息到检查结果中
      final errorResult = IntegrityCheckResult();
      errorResult.addIssue(
        '健康检查异常',
        '诊断过程中出现错误: $e',
        'general_error',
        stackTrace: stackTrace.toString(),
        logMessage: '健康检查: $e',
      );

      setState(() {
        _checkResult = errorResult;
      });

      ErrorHandler.handleError(e, stackTrace,
          logPrefix: '健康检查', userMessage: '诊断过程中出现错误', showToast: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('诊断过程中出现错误: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 修复特定问题
  Future<void> _fixIssues(
      BuildContext context, List<IntegrityIssue> issues) async {
    // 关闭详情对话框
    if (mounted) Navigator.pop(context);

    // 显示修复确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认修复'),
        content: Text('确定要修复这 ${issues.length} 个问题吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
            ),
            child: const Text('确定修复'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 获取当前登录用户
    final currentUser = Global.getLoggedInUser();
    if (currentUser == null) {
      ErrorHandler.handleError(Exception('用户未登录'), StackTrace.current,
          logPrefix: '修复问题', userMessage: '请先登录', showToast: true);
      return;
    }

    // 显示修复进度
    _showFixProgressDialog();

    try {
      // 使用本地数据完整性检查器进行修复
      final checker = DataIntegrityChecker();
      final fixResult = await checker.autoFix(_checkResult!, currentUser.id);

      // 在异步操作完成后处理 UI
      if (mounted) _handleFixResult(fixResult);
    } catch (e, stackTrace) {
      // 在异步操作完成后处理错误
      if (mounted) _handleFixError(e, stackTrace);
    }
  }

  // 显示修复进度对话框
  void _showFixProgressDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在修复问题...'),
          ],
        ),
      ),
    );
  }

  // 处理修复结果
  void _handleFixResult(IntegrityFixResult fixResult) {
    if (!mounted) return;

    // 关闭进度对话框
    Navigator.pop(context);

    // 显示修复结果
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修复完成'),
        content: Text(fixResult.hasFixed
            ? '已修复 ${fixResult.fixed.length} 个问题'
            : '没有需要修复的问题'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 重新运行健康检查
              _runDiagnostic();
            },
            child: const Text('重新检查'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 处理修复错误
  void _handleFixError(dynamic e, StackTrace stackTrace) {
    if (!mounted) return;

    // 关闭进度对话框
    Navigator.pop(context);

    ErrorHandler.handleError(e, stackTrace,
        logPrefix: '修复问题', userMessage: '修复过程中出现错误', showToast: true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('修复过程中出现错误: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _runAutoFix() async {
    if (_checkResult == null) return;

    // 获取当前登录用户
    final currentUser = Global.getLoggedInUser();
    if (currentUser == null) {
      ErrorHandler.handleError(Exception('用户未登录'), StackTrace.current,
          logPrefix: '自动修复', userMessage: '请先登录', showToast: true);
      return;
    }

    setState(() {
      _isRunning = true;
    });

    try {
      // 使用本地数据完整性检查器进行自动修复
      final checker = DataIntegrityChecker();
      final fixResult = await checker.autoFix(_checkResult!, currentUser.id);

      setState(() {
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fixResult.hasFixed
                ? '已修复 ${fixResult.fixed.length} 个问题'
                : '没有需要修复的问题'),
            backgroundColor: fixResult.hasFixed ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e, stackTrace) {
      setState(() {
        _isRunning = false;
      });

      ErrorHandler.handleError(e, stackTrace,
          logPrefix: '自动修复', userMessage: '修复过程中出现错误', showToast: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('修复过程中出现错误：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
