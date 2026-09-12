import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

class DataSanitizePage extends StatefulWidget {
  const DataSanitizePage({super.key});

  @override
  State<DataSanitizePage> createState() => _DataSanitizePageState();
}

class _DataSanitizePageState extends State<DataSanitizePage> {
  bool _isSanitizing = false;
  bool _isChecking = false;
  bool _isImageSanitizing = false;
  bool _isPopularitySanitizing = false;
  bool _isMeaningSanitizing = false;
  SystemHealthFixResult? _fixResult;
  SystemHealthCheckResult? _checkResult;
  SystemHealthFixResult? _popularityFixResult;
  SystemHealthFixResult? _imageFixResult;
  SystemHealthFixResult? _meaningFixResult;
  Timer? _statusTimer;
  Timer? _imageStatusTimer;
  Timer? _meaningStatusTimer;
  Timer? _dataStatusTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialPopularitySanitizeStatus();
    _checkInitialWordImageSanitizeStatus();
    _checkInitialMeaningSanitizeStatus();
    _checkInitialDataSanitizeStatus();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _imageStatusTimer?.cancel();
    _meaningStatusTimer?.cancel();
    _dataStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialWordImageSanitizeStatus() async {
    try {
      final res = await Api.client.getWordImageSanitizeStatus();
      if (!mounted) return;
      if (res.success && res.data != null) {
        final isRunning = res.data!.fixedCount == 1;
        if (isRunning) {
          setState(() {
            _isImageSanitizing = true;
            _imageFixResult = res.data;
          });
          _startPollingWordImageStatus();
        }
      }
    } catch (e) {
      // Ignore initial check error
    }
  }

  void _startPollingWordImageStatus() {
    _imageStatusTimer?.cancel();
    _imageStatusTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final res = await Api.client.getWordImageSanitizeStatus();
        if (!mounted) return;
        if (res.success && res.data != null) {
          final isRunning = res.data!.fixedCount == 1;
          setState(() {
            _imageFixResult = res.data;
            _isImageSanitizing = isRunning;
          });
          if (!isRunning) {
            timer.cancel();
            ToastUtil.success('单词配图清洗完成');
          }
        }
      } catch (e) {
        // Ignore background errors
      }
    });
  }

  Future<void> _checkInitialPopularitySanitizeStatus() async {
    try {
      final res = await Api.client.getWordPopularitySanitizeStatus();
      if (!mounted) return;
      if (res.success && res.data != null) {
        final isRunning = res.data!.fixedCount == 1;
        if (isRunning) {
          setState(() {
            _isPopularitySanitizing = true;
            _popularityFixResult = res.data;
          });
          _startPollingPopularityStatus();
        }
      }
    } catch (e) {
      // Ignore initial check error
    }
  }

  void _startPollingPopularityStatus() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final res = await Api.client.getWordPopularitySanitizeStatus();
        if (!mounted) return;
        if (res.success && res.data != null) {
          final isRunning = res.data!.fixedCount == 1;
          setState(() {
            _popularityFixResult = res.data;
            _isPopularitySanitizing = isRunning;
          });
          if (!isRunning) {
            timer.cancel();
            ToastUtil.success('单词常用度清洗完成');
          }
        }
      } catch (e) {
        // Ignore background errors
      }
    });
  }

  Future<void> _runWordPopularitySanitizing() async {
    if (_isSanitizing || _isChecking || _isPopularitySanitizing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('常用度数据清洗确认'),
        content: const Text(
            '该操作将启动后台异步任务，对通用词书的所有单词进行释义常用度清洗与补全：\n'
            '1. 从海词(dict.cn)查询并解析释义频率占比。\n'
            '2. 通过 AI 模型将现有释义与海词百分比释义进行语义对齐。\n'
            '3. 自动补全缺失的高频释义（频率 >= 10%）并配套生成例句及发音。\n'
            '4. 重新计算并排序释义的 popularity 序号。\n\n'
            '是否立即开始？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('开始', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isPopularitySanitizing = true;
      _popularityFixResult = null;
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.sanitizeWordPopularity();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _popularityFixResult = res.data;
        });
        ToastUtil.success('常用度清洗任务已在后台启动');
        _startPollingPopularityStatus();
      } else {
        ToastUtil.error('启动失败: ${res.msg}');
        setState(() {
          _isPopularitySanitizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('发生错误: $e');
        setState(() {
          _isPopularitySanitizing = false;
        });
      }
    }
  }

  Future<void> _checkInitialMeaningSanitizeStatus() async {
    try {
      final res = await Api.client.getMeaningSeparatorSanitizeStatus();
      if (!mounted) return;
      if (res.success && res.data != null) {
        final isRunning = res.data!.fixedCount == 1;
        if (isRunning) {
          setState(() {
            _isMeaningSanitizing = true;
            _meaningFixResult = res.data;
          });
          _startPollingMeaningStatus();
        }
      }
    } catch (e) {
      // Ignore initial check error
    }
  }

  void _startPollingMeaningStatus() {
    _meaningStatusTimer?.cancel();
    _meaningStatusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final res = await Api.client.getMeaningSeparatorSanitizeStatus();
        if (!mounted) return;
        if (res.success && res.data != null) {
          final isRunning = res.data!.fixedCount == 1;
          setState(() {
            _meaningFixResult = res.data;
            _isMeaningSanitizing = isRunning;
          });
          if (!isRunning) {
            timer.cancel();
            ToastUtil.success('释义项清洗完成');
          }
        }
      } catch (e) {
        // Ignore background errors
      }
    });
  }

  Future<void> _runMeaningSanitizing() async {
    if (_isSanitizing || _isChecking || _isPopularitySanitizing || _isImageSanitizing || _isMeaningSanitizing) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('释义项清洗确认'),
        content: const Text(
            '该操作将启动后台异步任务，逐条清洗释义项中非法的分号分隔：\n'
            '1. 扫描全库「用分号把多个义项挤在一条记录里」的释义项。\n'
            '2. 通过 AI 判定分号两侧是「同一义项的近义复述」还是「不同义项」。\n'
            '3. 近义合并为一条（逗号连接）；异义拆成多条独立释义项。\n'
            '4. 拆分产生的新释义项暂无例句，将由「系统健康检查」补全。\n\n'
            '修复后将产生同步日志。是否立即开始？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('开始清洗', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isMeaningSanitizing = true;
      _meaningFixResult = null;
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.sanitizeMeaningSeparators();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _meaningFixResult = res.data;
        });
        ToastUtil.success('释义项清洗任务已在后台启动');
        _startPollingMeaningStatus();
      } else {
        ToastUtil.error('启动失败: ${res.msg}');
        setState(() {
          _isMeaningSanitizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('发生错误: $e');
        setState(() {
          _isMeaningSanitizing = false;
        });
      }
    }
  }

  Future<void> _runDataSanitizeCheck() async {
    if (_isChecking || _isSanitizing) return;

    setState(() {
      _isChecking = true;
      _checkResult = null;
      _fixResult = null;
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.checkDataSanitization();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _checkResult = res.data;
        });
        if (_checkResult!.issues.isEmpty) {
          ToastUtil.success('全库数据非常整洁，未发现格式问题！');
        } else {
          ToastUtil.info('扫描完成，发现一些格式不规范的数据。');
        }
      } else {
        ToastUtil.error('检查失败: ${res.msg}');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('发生错误: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _runDataSanitizing() async {
    if (_isSanitizing || _isChecking || _isMeaningSanitizing || _isPopularitySanitizing || _isImageSanitizing) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据清洗确认'),
        content: const Text(
            '该操作将在后台扫描全库并自动修复不规范的数据格式：\n'
            '1. 音标归一为"裸音标"：移除首尾的斜线(/)与方括号([])，移除尾部残留逗号\n'
            '2. 移除单词、释义、例句末尾的多余逗号\n'
            '3. 清理损坏或无效的单词配图（如非图片文件、404错误HTML等）\n\n'
            '全量清洗需改写数万条记录并扫描全部配图，耗时较长，任务将在后台执行并显示进度。\n'
            '修复后将产生同步日志。是否立即开始？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('开始清洗', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isSanitizing = true;
      _fixResult = null;
      _checkResult = null; // 清洗后重置检查结果
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.sanitizeData();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _fixResult = res.data;
        });
        ToastUtil.success('数据清洗任务已在后台启动');
        _startPollingDataStatus();
      } else {
        ToastUtil.error('启动失败: ${res.msg}');
        setState(() {
          _isSanitizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('发生错误: $e');
        setState(() {
          _isSanitizing = false;
        });
      }
    }
  }

  void _startPollingDataStatus() {
    _dataStatusTimer?.cancel();
    _dataStatusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final res = await Api.client.getDataSanitizeStatus();
        if (!mounted) return;
        if (res.success && res.data != null) {
          final isRunning = res.data!.fixedCount == 1;
          setState(() {
            _fixResult = res.data;
            _isSanitizing = isRunning;
          });
          if (!isRunning) {
            timer.cancel();
            ToastUtil.success('数据清洗完成');
          }
        }
      } catch (e) {
        // Ignore background errors
      }
    });
  }

  Future<void> _checkInitialDataSanitizeStatus() async {
    try {
      final res = await Api.client.getDataSanitizeStatus();
      if (!mounted) return;
      if (res.success && res.data != null) {
        final isRunning = res.data!.fixedCount == 1;
        if (isRunning) {
          setState(() {
            _isSanitizing = true;
            _fixResult = res.data;
          });
          _startPollingDataStatus();
        }
      }
    } catch (e) {
      // Ignore initial check error
    }
  }

  Future<void> _runWordImageSanitizing() async {
    if (_isSanitizing || _isChecking || _isPopularitySanitizing || _isImageSanitizing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('单词配图清洗确认'),
        content: const Text(
            '该操作将启动后台异步任务，对全库单词配图进行清洗：\n'
            '1. 快速检查所有配图物理文件是否存在及数据格式合法性\n'
            '2. 识别并删除非图片/损坏文件（如 HTML 错误页）\n'
            '3. 清理对应的数据库记录并生成同步日志，修复客户端数据\n\n'
            '是否立即开始？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[700]),
            child: const Text('开始清洗', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isImageSanitizing = true;
      _imageFixResult = null;
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.sanitizeWordImages();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _imageFixResult = res.data;
        });
        ToastUtil.success('配图清洗任务已在后台启动');
        _startPollingWordImageStatus();
      } else {
        ToastUtil.error('启动失败: ${res.msg}');
        setState(() {
          _isImageSanitizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('发生错误: $e');
        setState(() {
          _isImageSanitizing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return AppScaffold(
      appBar: AppAppBar(
        title: '数据清洗工具',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntroCard(isDarkMode),
            const SizedBox(height: 20),
            if (_checkResult != null) _buildCheckResultCard(isDarkMode),
            if (_fixResult != null) _buildFixResultCard(isDarkMode),
            if (_imageFixResult != null) _buildWordImageFixResultCard(isDarkMode),
            if (_popularityFixResult != null) _buildPopularityFixResultCard(isDarkMode),
            if (_meaningFixResult != null) _buildMeaningFixResultCard(isDarkMode),
            const SizedBox(height: 30),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isAnyRunning = _isChecking || _isSanitizing || _isImageSanitizing || _isPopularitySanitizing || _isMeaningSanitizing;
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isAnyRunning ? null : _runDataSanitizeCheck,
              icon: Icon(_isChecking ? Icons.hourglass_empty : Icons.search),
              label: Text(_isChecking ? '正在扫描...' : '检查数据清洁状态'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isAnyRunning ? null : _runDataSanitizing,
              icon: Icon(_isSanitizing ? Icons.hourglass_empty : Icons.cleaning_services),
              label: Text(_isSanitizing ? '正在清洗...' : '立即开始清洗'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange[800],
                side: BorderSide(color: Colors.orange[800]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isAnyRunning ? null : _runWordImageSanitizing,
              icon: Icon(_isImageSanitizing ? Icons.hourglass_empty : Icons.broken_image_outlined),
              label: Text(_isImageSanitizing ? '正在清洗配图...' : '清洗单词配图'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purple[800],
                side: BorderSide(color: Colors.purple[800]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isAnyRunning ? null : _runWordPopularitySanitizing,
              icon: Icon(_isPopularitySanitizing ? Icons.hourglass_empty : Icons.auto_awesome),
              label: Text(_isPopularitySanitizing ? '正在清洗常用度...' : '清洗释义常用度'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal[800],
                side: BorderSide(color: Colors.teal[800]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isAnyRunning ? null : _runMeaningSanitizing,
              icon: Icon(_isMeaningSanitizing ? Icons.hourglass_empty : Icons.call_split),
              label: Text(_isMeaningSanitizing ? '正在清洗释义项...' : '清洗释义项分号'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo[800],
                side: BorderSide(color: Colors.indigo[800]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(bool isDarkMode) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[800]),
                const SizedBox(width: 10),
                const Text('功能说明', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 15),
            const Text(
              '本工具用于进行数据清理、格式修复与常用度数据对齐补全：',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 10),
            _buildBulletPoint('自动移除音标首尾的 /、[、] 等符号。'),
            _buildBulletPoint('清理单词、释义、词性及例句末尾残留的逗号。'),
            _buildBulletPoint('清理损坏或无效的单词配图（如非图片文件、404错误HTML等）。'),
            _buildBulletPoint('同步海词(dict.cn)释义频率占比，更新释义常用度。'),
            _buildBulletPoint('自动对齐并补全缺失的高频释义（频率 >= 10%）并配套生成例句与发音。'),
            _buildBulletPoint('清洗释义项中非法的分号分隔：近义合并为一条，异义拆成多条独立释义项。'),
            _buildBulletPoint('修复后的数据将生成同步日志，确保客户端数据一致。'),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildCheckResultCard(bool isDarkMode) {
    final issues = _checkResult!.issues;
    final isClean = issues.isEmpty;

    return Card(
      elevation: 2,
      color: isClean 
          ? (isDarkMode ? Colors.green.withValues(alpha: 0.1) : Colors.green[50])
          : (isDarkMode ? Colors.orange.withValues(alpha: 0.1) : Colors.orange[50]),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isClean ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isClean ? Icons.check_circle : Icons.warning, color: isClean ? Colors.green : Colors.orange),
                const SizedBox(width: 10),
                Text(isClean ? '数据非常整洁' : '扫描结果', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isClean ? Colors.green : Colors.orange[900])),
              ],
            ),
            const SizedBox(height: 15),
            if (isClean)
              const Text('未发现任何格式不规范的数据，无需清洗。')
            else ...[
              const Text('发现以下需要优化的数据项：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...issues.map((issue) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right, size: 20),
                    Expanded(child: Text('${issue.type}: ${issue.description}')),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFixResultCard(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: isDarkMode ? Colors.blue.withValues(alpha: 0.1) : Colors.blue[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_isSanitizing ? Icons.hourglass_top : Icons.done_all, color: Colors.blue),
                const SizedBox(width: 10),
                Text(
                  _isSanitizing ? '数据清洗执行中' : '数据清洗完成报告',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Divider(height: 25),
            ..._fixResult!.fixed.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isSanitizing ? msg : '✓ $msg',
                style: const TextStyle(fontSize: 14),
              ),
            )),
            if (_fixResult!.errors.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text('错误信息：', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ..._fixResult!.errors.map((err) => Text('! $err', style: const TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWordImageFixResultCard(bool isDarkMode) {
    if (_imageFixResult == null) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      color: isDarkMode ? Colors.purple.withValues(alpha: 0.1) : Colors.purple[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isImageSanitizing ? Icons.hourglass_top : Icons.done_all, 
                  color: Colors.purple[700]
                ),
                const SizedBox(width: 10),
                Text(
                  _isImageSanitizing ? '单词配图清洗执行中' : '单词配图清洗完成报告', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple[800])
                ),
              ],
            ),
            const SizedBox(height: 15),
            ..._imageFixResult!.fixed.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isImageSanitizing ? msg : '✓ $msg', 
                style: const TextStyle(fontSize: 14)
              ),
            )),
            if (_imageFixResult!.errors.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text('错误信息：', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ..._imageFixResult!.errors.map((err) => Text('! $err', style: const TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPopularityFixResultCard(bool isDarkMode) {
    if (_popularityFixResult == null) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      color: isDarkMode ? Colors.teal.withValues(alpha: 0.1) : Colors.teal[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isPopularitySanitizing ? Icons.hourglass_top : Icons.done_all, 
                  color: Colors.teal
                ),
                const SizedBox(width: 10),
                Text(
                  _isPopularitySanitizing ? '常用度清洗执行中' : '常用度清洗完成报告', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)
                ),
              ],
            ),
            const SizedBox(height: 15),
            ..._popularityFixResult!.fixed.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isPopularitySanitizing ? msg : '✓ $msg', 
                style: const TextStyle(fontSize: 14)
              ),
            )),
            if (_popularityFixResult!.errors.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text('错误信息：', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ..._popularityFixResult!.errors.map((err) => Text('! $err', style: const TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMeaningFixResultCard(bool isDarkMode) {
    if (_meaningFixResult == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      color: isDarkMode ? Colors.indigo.withValues(alpha: 0.1) : Colors.indigo[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isMeaningSanitizing ? Icons.hourglass_top : Icons.done_all,
                  color: Colors.indigo[700]
                ),
                const SizedBox(width: 10),
                Text(
                  _isMeaningSanitizing ? '释义项清洗执行中' : '释义项清洗完成报告',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo[800])
                ),
              ],
            ),
            const SizedBox(height: 15),
            ..._meaningFixResult!.fixed.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isMeaningSanitizing ? msg : '✓ $msg',
                style: const TextStyle(fontSize: 14)
              ),
            )),
            if (_meaningFixResult!.errors.isNotEmpty) ...[
              const SizedBox(height: 15),
              const Text('错误信息：', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ..._meaningFixResult!.errors.map((err) => Text('! $err', style: const TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ],
        ),
      ),
    );
  }
}
