import 'package:flutter/material.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

/// 系统健康检查页面（管理员专用）
class SystemHealthCheckPage extends StatefulWidget {
  const SystemHealthCheckPage({super.key});

  @override
  State<SystemHealthCheckPage> createState() => _SystemHealthCheckPageState();
}

class _SystemHealthCheckPageState extends State<SystemHealthCheckPage> {
  bool _isRunning = false;
  SystemHealthResult? _checkResult;

  // 每项检查的状态：null=未开始, false=进行中, true=通过, 'failed'=失败
  final Map<int, dynamic> _checkStates = {};
  final Map<int, String?> _checkMessages = {};

  // 检查项配置
  static const List<Map<String, dynamic>> _checkItems = [
    {
      'id': 1,
      'title': '系统词典完整性',
      'step': 1,
      'category': 'system_dict_integrity'
    },
    {'id': 2, 'title': '用户词典完整性', 'step': 2, 'category': 'user_dict_integrity'},
    {'id': 3, 'title': '学习进度合理性', 'step': 3, 'category': 'learning_progress'},
    {'id': 4, 'title': '数据库版本一致性', 'step': 4, 'category': 'db_version'},
    {
      'id': 5,
      'title': '通用词典完整性',
      'step': 5,
      'category': 'common_dict_integrity'
    },
    {'id': 6, 'title': '网络连接', 'step': 6, 'category': 'network_connectivity'},
    {'id': 7, 'title': '后端服务器连通性', 'step': 7, 'category': 'backend_server'},
    {'id': 8, 'title': '游戏服务器连通性', 'step': 8, 'category': 'game_server'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor =
        isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('系统健康检查'),
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
                      Icon(Icons.admin_panel_settings,
                          color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '系统健康检查',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '检查整个系统的健康状态，包括所有词书、学习进度和服务器连通性：',
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
                        item['category'] as String,
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
              onPressed: _isRunning ? null : _runSystemDiagnostic,
              icon: Icon(_isRunning ? Icons.hourglass_empty : Icons.search),
              label: Text(_isRunning
                  ? '检查中...'
                  : (_checkResult == null ? '开始检查' : '重新检查')),
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
                    isHealthy ? '检查完成，系统状态正常' : '发现 $totalIssues 个问题',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
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

  Widget _buildCheckItemWithStatus(
      String text, dynamic status, bool isDarkMode, String category) {
    IconData icon;
    Color iconColor;
    bool isFailed = false;

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
      isFailed = true;
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
          // 失败时显示详情按钮
          if (isFailed && _checkResult != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _showIssueDetails(category, text),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '详情',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 显示问题详情对话框
  void _showIssueDetails(String category, String title) {
    if (_checkResult == null) return;

    // 根据 category 过滤出相关的问题
    final relatedIssues = _checkResult!.issues
        .where((issue) => issue.category == category)
        .toList();

    if (relatedIssues.isEmpty) {
      return;
    }

    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          shape: const CircleBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                // 内容区域
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: relatedIssues.map((issue) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF2D2D2D)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 问题类型
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange[600],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      issue.type,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w400,
                                        fontSize: 16,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // 问题描述
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDarkMode
                                        ? Colors.grey[600]!
                                        : Colors.grey[200]!,
                                  ),
                                ),
                                child: Text(
                                  issue.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: isDarkMode
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                              // 如果有日志信息，显示日志
                              if (issue.logMessage != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.blue[600],
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '日志信息',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w400,
                                              fontSize: 14,
                                              color: Colors.blue[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.blue[100]!,
                                          ),
                                        ),
                                        child: Text(
                                          issue.logMessage!,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'monospace',
                                            height: 1.4,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // 如果有堆栈跟踪，显示堆栈
                              if (issue.stackTrace != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            color: Colors.red[600],
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '异常堆栈',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w400,
                                              fontSize: 14,
                                              color: Colors.red[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.red[100]!,
                                          ),
                                        ),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                            issue.stackTrace!,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontFamily: 'monospace',
                                              height: 1.3,
                                              color: Colors.red[700],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
                // 底部按钮
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color:
                        isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 修复按钮
                      if (relatedIssues.isNotEmpty) ...[
                        TextButton(
                          onPressed: () => _fixSystemIssues(context, relatedIssues),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            foregroundColor: Colors.green,
                          ),
                          child: const Text(
                            '修复',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          '关闭',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runSystemDiagnostic() async {
    // 重置所有检查状态
    setState(() {
      _isRunning = true;
      _checkResult = null;
      _checkStates.clear();
      _checkMessages.clear();
    });

    try {
      final result = SystemHealthResult();

      // 1. 检查系统词典完整性
      await _checkSystemDictIntegrity(result, 1);

      // 2. 检查用户词典完整性
      await _checkUserDictIntegrity(result, 2);

      // 3. 检查学习进度合理性
      await _checkLearningProgress(result, 3);

      // 4. 检查数据库版本一致性
      await _checkDbVersionConsistency(result, 4);

      // 5. 检查通用词典完整性
      await _checkCommonDictIntegrity(result, 5);

      // 6. 检查网络连接
      await _checkNetworkConnectivity(result, 6);

      // 7. 检查后端服务器连通性
      await _checkBackendServer(result, 7);

      // 8. 检查游戏服务器连通性
      await _checkGameServer(result, 8);

      setState(() {
        _checkResult = result;
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('系统诊断过程中出现错误: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkSystemDictIntegrity(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final apiResult = await Api.client.checkSystemDictIntegrity();

      // 添加更多调试信息
      Global.logger.d(
          'API调用结果: success=${apiResult.success}, data=${apiResult.data != null}');
      if (apiResult.data != null) {
        Global.logger.d('API数据: ${apiResult.data}');
      }

      if (apiResult.success && apiResult.data != null) {
        final data = apiResult.data!;

        // 添加调试日志
        Global.logger.d(
            '系统词典完整性检查结果: isHealthy=${data.isHealthy}, issuesCount=${data.issues.length}');
        Global.logger.d('isHealthy类型: ${data.isHealthy.runtimeType}');
        Global.logger.d('isHealthy == false: ${data.isHealthy == false}');
        Global.logger.d('issues.isNotEmpty: ${data.issues.isNotEmpty}');

        if ((data.isHealthy == false) && data.issues.isNotEmpty) {
          for (final issue in data.issues) {
            result.addIssue(
                issue.type, issue.description, 'system_dict_integrity');
          }
          setState(() {
            _checkStates[step] = 'failed';
          });
        } else {
          setState(() {
            _checkStates[step] = true; // 通过
          });
        }
      } else {
        result.addIssue(
            '系统词典完整性', 'API调用失败: ${apiResult.msg}', 'system_dict_integrity');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查系统词典完整性时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '系统词典完整性',
        '检查系统词典完整性时出错: $e',
        'system_dict_integrity',
        stackTrace: stackTrace.toString(),
        logMessage: '系统词典完整性检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkUserDictIntegrity(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final apiResult = await Api.client.checkUserDictIntegrity();

      if (apiResult.success && apiResult.data != null) {
        final data = apiResult.data!;

        if ((data.isHealthy == false) && data.issues.isNotEmpty) {
          for (final issue in data.issues) {
            result.addIssue(
                issue.type, issue.description, 'user_dict_integrity');
          }
          setState(() {
            _checkStates[step] = 'failed';
          });
        } else {
          setState(() {
            _checkStates[step] = true; // 通过
          });
        }
      } else {
        result.addIssue(
            '用户词典完整性', 'API调用失败: ${apiResult.msg}', 'user_dict_integrity');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查用户词典完整性时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '用户词典完整性',
        '检查用户词典完整性时出错: $e',
        'user_dict_integrity',
        stackTrace: stackTrace.toString(),
        logMessage: '用户词典完整性检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkLearningProgress(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final apiResult = await Api.client.checkLearningProgress();

      if (apiResult.success && apiResult.data != null) {
        final data = apiResult.data!;

        if ((data.isHealthy == false) && data.issues.isNotEmpty) {
          for (final issue in data.issues) {
            result.addIssue(issue.type, issue.description, 'learning_progress');
          }
          setState(() {
            _checkStates[step] = 'failed';
          });
        } else {
          setState(() {
            _checkStates[step] = true; // 通过
          });
        }
      } else {
        result.addIssue(
            '学习进度合理性', 'API调用失败: ${apiResult.msg}', 'learning_progress');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查学习进度合理性时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '学习进度合理性',
        '检查学习进度合理性时出错: $e',
        'learning_progress',
        stackTrace: stackTrace.toString(),
        logMessage: '学习进度合理性检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkDbVersionConsistency(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final apiResult = await Api.client.checkDbVersionConsistency();

      if (apiResult.success && apiResult.data != null) {
        final data = apiResult.data!;

        if ((data.isHealthy == false) && data.issues.isNotEmpty) {
          for (final issue in data.issues) {
            result.addIssue(issue.type, issue.description, 'db_version');
          }
          setState(() {
            _checkStates[step] = 'failed';
          });
        } else {
          setState(() {
            _checkStates[step] = true; // 通过
          });
        }
      } else {
        result.addIssue('数据库版本一致性', 'API调用失败: ${apiResult.msg}', 'db_version');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查数据库版本一致性时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '数据库版本一致性',
        '检查数据库版本一致性时出错: $e',
        'db_version',
        stackTrace: stackTrace.toString(),
        logMessage: '数据库版本一致性检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkCommonDictIntegrity(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final apiResult = await Api.client.checkCommonDictIntegrity();

      if (apiResult.success && apiResult.data != null) {
        final data = apiResult.data!;

        if ((data.isHealthy == false) && data.issues.isNotEmpty) {
          for (final issue in data.issues) {
            result.addIssue(
                issue.type, issue.description, 'common_dict_integrity');
          }
          setState(() {
            _checkStates[step] = 'failed';
          });
        } else {
          setState(() {
            _checkStates[step] = true; // 通过
          });
        }
      } else {
        result.addIssue(
            '通用词典完整性', 'API调用失败: ${apiResult.msg}', 'common_dict_integrity');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查通用词典完整性时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '通用词典完整性',
        '检查通用词典完整性时出错: $e',
        'common_dict_integrity',
        stackTrace: stackTrace.toString(),
        logMessage: '通用词典完整性检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkNetworkConnectivity(
      SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      final networkUtil = NetworkUtil();
      final isConnected = await networkUtil.isConnected();

      if (!isConnected) {
        result.addIssue('网络不可用', '设备未连接到网络或无法访问互联网', 'network_connectivity');
        setState(() {
          _checkStates[step] = 'failed';
        });
      } else {
        final connectionType = await networkUtil.getConnectionType();
        Global.logger.d('网络连接正常，连接类型: $connectionType');
        setState(() {
          _checkStates[step] = true; // 通过
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查网络连接时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '网络检查失败',
        '无法检查网络连接状态: $e',
        'network_connectivity',
        stackTrace: stackTrace.toString(),
        logMessage: '网络连接检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkBackendServer(SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      // 使用 Dio 直接调用API
      final dio = Dio(BaseOptions(
        baseUrl: Config.serviceUrl,
        connectTimeout: const Duration(seconds: 5),
      ));

      // 尝试调用一个简单的API来检查后端连通性
      final response = await dio.get(
        '/getGameHallData.do',
        options:
            Options(validateStatus: (status) => status! < 500), // 允许非200状态码
      );

      if (response.statusCode != null && response.statusCode! < 500) {
        Global.logger.d('后端服务器连通性正常，状态码: ${response.statusCode}');
        setState(() {
          _checkStates[step] = true; // 通过
        });
      } else {
        result.addIssue('后端服务器无响应', '后端服务器返回错误状态: ${response.statusCode}',
            'backend_server');
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查后端服务器时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '后端服务器连接失败',
        '无法连接到后端服务器: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}',
        'backend_server',
        stackTrace: stackTrace.toString(),
        logMessage: '后端服务器检查: $e',
      );
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  Future<void> _checkGameServer(SystemHealthResult result, int step) async {
    setState(() {
      _checkStates[step] = false; // 进行中
    });

    try {
      // 检查 socket.io 连接状态
      final socketClient = SocketIoClient.instance;

      // 尝试连接socket服务器
      socketClient.connect();

      // 等待一小段时间让连接建立
      await Future.delayed(const Duration(seconds: 2));

      // 检查连接状态
      if (socketClient.isConnectedToSocketServer) {
        Global.logger.d('游戏服务器连接正常');
        // 检查完后立即断开
        socketClient.disconnect();
        setState(() {
          _checkStates[step] = true; // 通过
        });
      } else {
        result.addIssue('游戏服务器连接失败', '无法建立WebSocket连接到游戏服务器', 'game_server');
        socketClient.disconnect();
        setState(() {
          _checkStates[step] = 'failed';
        });
      }
    } catch (e, stackTrace) {
      Global.logger.e('检查游戏服务器时出错: $e', error: e, stackTrace: stackTrace);
      result.addIssue(
        '游戏服务器检查失败',
        '检查游戏服务器连接时出错: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}',
        'game_server',
        stackTrace: stackTrace.toString(),
        logMessage: '游戏服务器检查: $e',
      );
      // 确保断开连接
      try {
        SocketIoClient.instance.disconnect();
      } catch (e, stackTrace) {
        // 断开连接失败不影响检查结果，但需要记录
        Global.logger.w('断开Socket连接失败', error: e, stackTrace: stackTrace);
      }
      setState(() {
        _checkStates[step] = 'failed';
      });
    }
  }

  // 修复特定系统问题
  Future<void> _fixSystemIssues(BuildContext context, List<SystemHealthIssue> issues) async {
    // 关闭详情对话框
    Navigator.pop(context);
    
    // 显示修复确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认修复'),
        content: Text('确定要修复这 ${issues.length} 个系统问题吗？'),
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
    
    if (confirmed != true) return;
    
    // 显示修复进度
    _showSystemFixProgressDialog();
    
    try {
      // 收集需要修复的问题类型
      final issueTypes = <String>[];
      for (final issue in issues) {
        if (!issueTypes.contains(issue.category)) {
          issueTypes.add(issue.category);
        }
      }
      
      // 调用后端API进行自动修复（禁用自动加载进度条）
      Api.disableAutoLoading = true;
      final apiResult = await Api.client.autoFixSystemIssues(issueTypes);
      Api.disableAutoLoading = false;
      
      // 在异步操作完成后处理UI
      if (mounted) _handleSystemFixResult(apiResult);
    } catch (e, stackTrace) {
      // 确保在异常情况下也重置自动加载标志
      Api.disableAutoLoading = false;
      // 在异步操作完成后处理错误
      if (mounted) _handleSystemFixError(e, stackTrace);
    }
  }

  // 显示系统修复进度对话框
  void _showSystemFixProgressDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在修复系统问题...'),
          ],
        ),
      ),
    );
  }

  // 处理系统修复结果
  void _handleSystemFixResult(Result<SystemHealthFixResult> apiResult) {
    if (!mounted) return;
    
    // 关闭进度对话框
    Navigator.pop(context);
    
    if (apiResult.success && apiResult.data != null) {
      final fixResult = apiResult.data!;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修复完成'),
          content: Text(
            fixResult.fixedCount > 0 
              ? '已修复 ${fixResult.fixedCount} 个问题'
              : '没有需要修复的问题'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // 重新运行系统诊断
                _runSystemDiagnostic();
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
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修复失败'),
          content: Text(apiResult.msg ?? '修复过程中出现未知错误'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  // 处理系统修复错误
  void _handleSystemFixError(dynamic e, StackTrace stackTrace) {
    if (!mounted) return;
    
    // 关闭进度对话框
    Navigator.pop(context);
    
    Global.logger.e('修复系统问题时出错', error: e, stackTrace: stackTrace);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('修复过程中出现错误: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _runAutoFix() async {
    if (_checkResult == null) return;

    // 显示修复进度对话框
    _showSystemFixProgressDialog();

    try {
      // 收集需要修复的问题类型
      final issueTypes = <String>[];
      for (final issue in _checkResult!.issues) {
        if (!issueTypes.contains(issue.category)) {
          issueTypes.add(issue.category);
        }
      }

      if (issueTypes.isEmpty) {
        // 关闭进度对话框
        Navigator.pop(context);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('没有需要修复的问题'),
              backgroundColor: Colors.blue,
            ),
          );
        }
        return;
      }

      // 调用后端API进行自动修复（禁用自动加载进度条）
      Api.disableAutoLoading = true;
      final apiResult = await Api.client.autoFixSystemIssues(issueTypes);
      Api.disableAutoLoading = false;

      // 在异步操作完成后处理UI
      if (mounted) _handleSystemFixResult(apiResult);
    } catch (e, stackTrace) {
      // 确保在异常情况下也重置自动加载标志
      Api.disableAutoLoading = false;
      // 在异步操作完成后处理错误
      if (mounted) _handleSystemFixError(e, stackTrace);
    }
  }
}

/// 系统健康检查结果
class SystemHealthResult {
  final List<String> errors = [];
  final List<SystemHealthIssue> issues = [];

  void addError(String error) {
    errors.add(error);
  }

  void addIssue(String type, String description, String category,
      {String? stackTrace, String? logMessage}) {
    issues.add(SystemHealthIssue(type, description, category,
        stackTrace: stackTrace, logMessage: logMessage));
  }

  bool hasIssue(String category) {
    return issues.any((issue) => issue.category == category);
  }

  bool get hasErrors => errors.isNotEmpty;
  bool get hasIssues => issues.isNotEmpty;
  bool get isHealthy => !hasErrors && !hasIssues;

  int get totalIssues => errors.length + issues.length;
}

/// 系统健康问题
class SystemHealthIssue {
  final String type;
  final String description;
  final String category;
  final String? stackTrace;
  final String? logMessage;

  SystemHealthIssue(this.type, this.description, this.category,
      {this.stackTrace, this.logMessage});
}
