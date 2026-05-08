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
  SystemHealthFixResult? _fixResult;

  Future<void> _runDataSanitizing() async {
    if (_isSanitizing) return;

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
            if (_fixResult != null) _buildResultCard(isDarkMode),
            const SizedBox(height: 30),
            Center(
              child: SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSanitizing ? null : _runDataSanitizing,
                  icon: Icon(_isSanitizing ? Icons.hourglass_empty : Icons.cleaning_services),
                  label: Text(_isSanitizing ? '正在清洗...' : '立即开始清洗'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[800],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildResultCard(bool isDarkMode) {
    return Card(
      elevation: 2,
      color: isDarkMode ? Colors.green.withValues(alpha: 0.1) : Colors.green[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 10),
                const Text('清洗执行报告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
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
