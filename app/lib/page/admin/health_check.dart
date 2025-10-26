import 'package:flutter/material.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';
import 'package:provider/provider.dart';

/// 健康检查页面
class HealthCheckPage extends StatefulWidget {
  const HealthCheckPage({super.key});

  @override
  State<HealthCheckPage> createState() => _HealthCheckPageState();
}

class _HealthCheckPageState extends State<HealthCheckPage> {
  bool _isRunning = false;
  IntegrityCheckResult? _checkResult;
  IntegrityFixResult? _fixResult;
  
  // 每项检查的状态：null=未开始, false=进行中, true=通过, 'failed'=失败
  final Map<int, dynamic> _checkStates = {}; // 1=序号, 2=数量, 3=学习进度, 4=版本, 5=通用词典
  final Map<int, String?> _checkMessages = {};
  
  // 检查项配置
  static const List<Map<String, dynamic>> _checkItems = [
    {'id': 1, 'title': '您的词典单词序号连续性', 'step': 1, 'category': 'dict_word_sequence'},
    {'id': 2, 'title': '您的词典单词数量一致性', 'step': 2, 'category': 'dict_word_count'},
    {'id': 3, 'title': '您的学习进度合理性', 'step': 3, 'category': 'learning_progress'},
    {'id': 4, 'title': '您的数据库版本一致性', 'step': 4, 'category': 'user_db_version'},
    {'id': 5, 'title': '通用词典完整性', 'step': 5, 'category': 'common_dict_integrity'},
    {'id': 6, 'title': '网络连接', 'step': 6, 'category': 'network_connectivity'},
    {'id': 7, 'title': '后端服务器连通性', 'step': 7, 'category': 'backend_server'},
    {'id': 8, 'title': '游戏服务器连通性', 'step': 8, 'category': 'game_server'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('健康检查'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          if (_checkResult != null && _checkResult!.hasIssues)
            IconButton(
              onPressed: _isRunning ? null : _runAutoFix,
              icon: const Icon(Icons.build, color: Colors.white),
              tooltip: '自动修复',
            ),
        ],
      ),
      body: _buildContent(isDarkMode),
    );
  }

  Widget _buildContent(bool isDarkMode) {
    return _buildMainState(isDarkMode);
  }

  Widget _buildMainState(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '健康检查',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '检查您的系统和数据健康状态：',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 显示每个检查项的状态
                  ..._checkItems.map((item) => _buildCheckItemWithStatus(
                    item['title'] as String,
                    _checkStates[item['id'] as int],
                    isDarkMode,
                  )),
                ],
              ),
            ),
          ),
          // 显示检查结果提示
          if (_checkResult != null) ...[
            const SizedBox(height: 16),
            _buildResultSummary(isDarkMode),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isRunning ? null : _runDiagnostic,
              icon: Icon(_isRunning ? Icons.hourglass_empty : Icons.search),
              label: Text(_isRunning ? '检查中...' : (_checkResult == null ? '开始检查' : '重新检查')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSummary(bool isDarkMode) {
    final isHealthy = _checkResult!.isHealthy;
    final totalIssues = _checkResult!.totalIssues;
    
    return Card(
      color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isHealthy ? Icons.check_circle : Icons.warning,
              color: isHealthy ? Colors.green : Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHealthy ? '检查完成，所有项目正常' : '发现 $totalIssues 个问题',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (!isHealthy) ...[
                    const SizedBox(height: 4),
                    Text(
                      '请查看上述检查项了解详情',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(String text, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItemWithStatus(String text, dynamic status, bool isDarkMode) {
    IconData icon;
    Color iconColor;
    
    if (status == null) {
      // 尚未检查，显示灰色时钟
      icon = Icons.access_time;
      iconColor = Colors.grey;
    } else if (status == false) {
      // 正在进行中，显示蓝色时钟
      icon = Icons.access_time;
      iconColor = AppTheme.primaryColor;
    } else if (status == true) {
      // 通过，显示绿色对钩
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else {
      // 失败，显示红色叉
      icon = Icons.cancel;
      iconColor = Colors.red;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }



  Future<void> _runDiagnostic() async {
    // 重置所有检查状态
    setState(() {
      _isRunning = true;
      _checkResult = null;
      _fixResult = null;
      _checkStates.clear();
      _checkMessages.clear();
    });
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(
                  '发现问题 (${_checkResult!.issues.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._checkResult!.issues.map((issue) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.type,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      issue.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        issue.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildFixResultsSection(bool isDarkMode) {
    return Card(
      color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  '修复结果',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_fixResult!.hasFixed) ...[
              Text(
                '已修复项目 (${_fixResult!.fixed.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              ..._fixResult!.fixed.map((fix) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.check, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fix,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
            if (_fixResult!.hasErrors) ...[
              const SizedBox(height: 8),
              Text(
                '修复错误 (${_fixResult!.errors.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 4),
              ..._fixResult!.errors.map((error) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _runDiagnostic,
            icon: const Icon(Icons.refresh),
            label: const Text('重新诊断'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_checkResult!.hasIssues) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isRunning ? null : _runAutoFix,
              icon: const Icon(Icons.build),
              label: const Text('自动修复'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _runDiagnostic() async {
    // 重置所有检查状态
    setState(() {
      _isRunning = true;
      _checkResult = null;
      _fixResult = null;
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
                final hasIssue = result.issues.any((issue) => issue.category == category);
                
                setState(() {
                  _checkStates[itemId] = !hasIssue; // true=通过, 'failed'=有问题
                });
              }
            }
          }
        },
      );
      
      setState(() {
        _checkResult = checkResult;
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _isRunning = false;
      });
      
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

  Future<void> _runAutoFix() async {
    if (_checkResult == null) return;

    setState(() {
      _isRunning = true;
    });

    try {
      // 使用本地数据完整性检查器进行自动修复
      final checker = DataIntegrityChecker();
      final fixResult = await checker.autoFix(_checkResult!);
      
      setState(() {
        _fixResult = fixResult;
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fixResult.hasFixed 
                ? '已修复 ${fixResult.fixed.length} 个问题'
                : '没有需要修复的问题'
            ),
            backgroundColor: fixResult.hasFixed ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunning = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('修复过程中出现错误: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
