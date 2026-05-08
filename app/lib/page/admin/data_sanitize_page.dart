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
  SystemHealthFixResult? _fixResult;
  SystemHealthCheckResult? _checkResult;

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
    if (_isSanitizing || _isChecking) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据清洗确认'),
        content: const Text(
            '该操作将扫描全库并自动修复不规范的数据格式：\n'
            '1. 移除音标前后的斜线(/)和方括号([])\n'
            '2. 移除单词、释义、例句末尾的多余逗号\n\n'
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
    });

    try {
      final res = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.sanitizeData();
      });

      if (!mounted) return;

      if (res.success) {
        setState(() {
          _fixResult = res.data;
          _checkResult = null; // 清洗后重置检查结果
        });
        ToastUtil.success('数据清洗完成');
      } else {
        ToastUtil.error('清洗失败: ${res.msg}');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('发生错误: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSanitizing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
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
            const SizedBox(height: 30),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isChecking || _isSanitizing) ? null : _runDataSanitizeCheck,
              icon: Icon(_isChecking ? Icons.hourglass_empty : Icons.search),
              label: Text(_isChecking ? '正在扫描...' : '检查数据清洁状态'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
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
              onPressed: (_isSanitizing || _isChecking) ? null : _runDataSanitizing,
              icon: Icon(_isSanitizing ? Icons.hourglass_empty : Icons.cleaning_services),
              label: Text(_isSanitizing ? '正在清洗...' : '立即开始清洗'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange[800],
                side: BorderSide(color: Colors.orange[800]!),
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
              '本工具用于修复因 AI 生成或导入过程中产生的常见格式问题：',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 10),
            _buildBulletPoint('自动移除音标首尾的 /、[、] 等符号。'),
            _buildBulletPoint('清理单词、释义、词性及例句末尾残留的逗号。'),
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
            const Row(
              children: [
                Icon(Icons.done_all, color: Colors.blue),
                const SizedBox(width: 10),
                const Text('清洗执行报告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 15),
            Text('本次操作共修复记录数：${_fixResult!.fixedCount}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(height: 25),
            ..._fixResult!.fixed.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('✓ $msg', style: const TextStyle(fontSize: 14)),
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
}
