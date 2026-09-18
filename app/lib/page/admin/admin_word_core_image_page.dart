import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

class AdminWordCoreImagePage extends StatefulWidget {
  const AdminWordCoreImagePage({super.key});

  @override
  State<AdminWordCoreImagePage> createState() => _AdminWordCoreImagePageState();
}

class _AdminWordCoreImagePageState extends State<AdminWordCoreImagePage> {
  Map<String, dynamic>? _taskStatus;
  Timer? _pollingTimer;
  final TextEditingController _testWordController = TextEditingController(text: 'spring');
  bool _isTestingSingle = false;

  String get _baseUrl => Api.useProdUrl ? Config.profiles["prod"]["service_url"] : Config.serviceUrl;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _testWordController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _fetchStatus();
      }
    });
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await Api.dio.get('$_baseUrl/admin/wordCoreImage/status.do');
      final res = response.data;
      if (res['success'] == true && mounted) {
        setState(() {
          _taskStatus = res['data'];
        });
      }
    } catch (_) {
      // 忽略轮询抖动异常
    }
  }

  Future<void> _startBatch() async {
    try {
      final response = await Api.dio.post(
        '$_baseUrl/admin/wordCoreImage/startBatch.do',
        queryParameters: {
          'userId': Global.getLoggedInUser()?.id,
        },
      );
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('成功启动全量批量提取与生图任务');
        _fetchStatus();
      } else {
        ToastUtil.error('启动失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _stopBatch() async {
    try {
      final response = await Api.dio.post(
        '$_baseUrl/admin/wordCoreImage/stopBatch.do',
        queryParameters: {
          'userId': Global.getLoggedInUser()?.id,
        },
      );
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('已发送平滑中止指令');
        _fetchStatus();
      } else {
        ToastUtil.error('中止失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _testSingleWord() async {
    final spell = _testWordController.text.trim();
    if (spell.isEmpty) {
      ToastUtil.error('请输入单词');
      return;
    }
    setState(() => _isTestingSingle = true);
    try {
      final response = await Api.dio.post(
        '$_baseUrl/admin/wordCoreImage/processSingle.do',
        queryParameters: {
          'spell': spell,
          'userId': Global.getLoggedInUser()?.id,
        },
      );
      final res = response.data;
      if (res['success'] == true) {
        final data = res['data'];
        final isApp = data['isApplicable'] == true;
        if (isApp) {
          ToastUtil.success('[$spell] 适合提取！核心意象: ${data['coreImage']}');
        } else {
          ToastUtil.info('[$spell] 判定不适合: ${data['notApplicableReason']}');
        }
        _fetchStatus();
      } else {
        ToastUtil.error('处理失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('测试异常: $e');
    } finally {
      if (mounted) setState(() => _isTestingSingle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0F1216) : const Color(0xFFF6F8FA);

    final bool isRunning = _taskStatus?['isRunning'] == true;
    final String statusMsg = _taskStatus?['statusMsg'] ?? '任务未启动';
    final int total = _taskStatus?['totalWords'] ?? 0;
    final int processed = _taskStatus?['processedWords'] ?? 0;
    final int applicable = _taskStatus?['applicableCount'] ?? 0;
    final int skipped = _taskStatus?['skippedCount'] ?? 0;
    final int failed = _taskStatus?['failedCount'] ?? 0;
    final String currentWord = _taskStatus?['currentWord'] ?? '';
    final List logs = _taskStatus?['recentLogs'] ?? [];

    final double progress = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: '一词多义核心意象批处理',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // 顶部控制看板
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF161B22) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 状态说明与启动/停止按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isRunning ? const Color(0xFF00E6B8) : Colors.grey,
                                  boxShadow: isRunning
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF00E6B8).withValues(alpha: 0.6),
                                            blurRadius: 6,
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRunning ? '后台批量执行中' : '系统就绪 (支持随时退出与重进)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isRunning ? const Color(0xFF00E6B8) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusMsg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: isRunning ? _stopBatch : _startBatch,
                      icon: Icon(isRunning ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
                      label: Text(isRunning ? '中止任务' : '开始全量提取'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning ? Colors.redAccent : const Color(0xFF00C79A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 进度条
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '处理进度: ${(progress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (currentWord.isNotEmpty)
                          Text(
                            '当前: $currentWord',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00C79A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: isDarkMode ? Colors.white12 : Colors.black12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C79A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 关键指标卡片网格
                Row(
                  children: [
                    _buildStatCard('总词库', '$total', Colors.blue, isDarkMode),
                    const SizedBox(width: 8),
                    _buildStatCard('已扫描', '$processed', Colors.purple, isDarkMode),
                    const SizedBox(width: 8),
                    _buildStatCard('意象命中', '$applicable', const Color(0xFF00C79A), isDarkMode),
                    const SizedBox(width: 8),
                    _buildStatCard('已跳过', '$skipped', Colors.grey, isDarkMode),
                    if (failed > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatCard('失败', '$failed', Colors.redAccent, isDarkMode),
                    ]
                  ],
                ),
                const SizedBox(height: 12),

                // 单词快速测试工具条
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _testWordController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '输入单词测试核心意象 (如 spring, bank)',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white24 : Colors.black12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: _isTestingSingle ? null : _testSingleWord,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: _isTestingSingle
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('单词测试', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 实时产出流瀑布展示
          Expanded(
            child: _buildRecentLogList(logs, isDarkMode),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, bool isDarkMode) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDarkMode ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLogList(List logs, bool isDarkMode) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              '暂无处理记录\n点击上方「开始全量提取」启动后台自动化任务',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = logs[index];
        final String word = log['word'] ?? '';
        final bool isApp = log['type'] == 'APPLICABLE';
        final String coreImage = log['coreImage'] ?? '';
        final String reason = log['reason'] ?? '';
        final String imageStatus = log['imageStatus'] ?? '';
        final String? imageUrl = log['imageUrl'];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 状态图标
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isApp
                      ? const Color(0xFF00E6B8).withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Icon(
                    isApp ? Icons.auto_awesome : Icons.remove_circle_outline,
                    size: 16,
                    color: isApp ? const Color(0xFF00E6B8) : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 词汇与意象内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          word,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (isApp ? const Color(0xFF00E6B8) : Colors.grey)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isApp ? '核心意象命中' : '已跳过 (单一释义)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isApp ? const Color(0xFF00A882) : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (isApp)
                      Text(
                        '意象: $coreImage',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white70 : const Color(0xFF24292F),
                        ),
                      )
                    else
                      Text(
                        '原因: $reason',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                  ],
                ),
              ),

              // 生图状态或缩略图
              if (isApp)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: imageStatus == 'SUCCESS'
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          imageStatus == 'SUCCESS' ? '已生图' : '生成中...',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: imageStatus == 'SUCCESS' ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Icon(Icons.image_outlined, size: 14, color: Colors.grey),
                      ]
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
