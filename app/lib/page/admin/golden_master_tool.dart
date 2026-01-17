import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

class GoldenMasterToolPage extends StatefulWidget {
  const GoldenMasterToolPage({super.key});

  @override
  State<GoldenMasterToolPage> createState() => _GoldenMasterToolPageState();
}

class _GoldenMasterToolPageState extends State<GoldenMasterToolPage> {
  bool _isProcessing = false;
  bool _isFinished = false;
  String _statusMessage = '准备就绪';
  
  // 数据库概要信息
  int? _dbVersion;
  String? _dbPath;
  int? _totalTables;
  final Map<String, int> _tableCounts = {};

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('制作黄金母版数据库'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isFinished ? Icons.check_circle_outline : Icons.storage,
                    size: 80,
                    color: _isFinished ? Colors.green : AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '黄金母版制作工具',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isFinished)
                    Text(
                      '此工具将执行以下操作：\n'
                      '1. 清空并重建本地数据库（所有本地数据将丢失）\n'
                      '2. 切换至生产环境 API\n'
                      '3. 下载最新的通用词典\n'
                      '4. 查看数据库概要信息\n\n'
                      '制作完成后，请自行将黄金母版文件拷贝到app项目的assets/db目录下。',
                      style: TextStyle(
                        fontSize: 16, 
                        height: 1.5,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  
                  if (_isFinished) ...[
                    _buildSummaryCard(isDarkMode),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => exit(0),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('关闭 App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  if (_isProcessing) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      style: TextStyle(color: textColor, fontFamily: 'NotoSansSC'),
                    ),
                  ] else if (!_isFinished)
                    ElevatedButton.icon(
                      onPressed: _startProcessing,
                      icon: const Icon(Icons.rocket_launch),
                      label: const Text('立即开始制作'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Card(
      color: cardColor,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '数据库概要信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const Divider(height: 24),
            _buildInfoRow('数据库版本', '$_dbVersion', textColor),
            _buildInfoRow('数据库路径', _dbPath ?? '未知', textColor),
            _buildInfoRow('总表数', '$_totalTables', textColor),
            const SizedBox(height: 12),
            const Text(
              '数据统计:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ..._tableCounts.entries.map((e) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key, style: TextStyle(color: textColor.withOpacity(0.8))),
                  Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _startProcessing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('由于涉及到清空数据，请再次确认'),
        content: const Text('此操作将永久删除所有本地数据。您确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定制作', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _isFinished = false;
      _statusMessage = '正在初始化...';
    });

    try {
      // 1. 清空并重建本地数据库
      setState(() => _statusMessage = '正在清空并重建数据库...');
      await MyDatabase.instance.wipeAllTables();
      
      // 2. 切换至生产环境 API
      setState(() => _statusMessage = '正在切换至生产环境...');
      Api.useProdUrl = true;
      Api.resetClient();

      // 3. 触发下载通用词典
      setState(() => _statusMessage = '准备下载通用词典...');
      
      final commonDict = DictVo(
        Global.commonDictId, 
        '通用词典', 
        '通用词典', 
        null, 
        true, 
        true, 
        true, 
        null, 
        0, 
        AppClock.now()
      );

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => DictDownloadDialog(
            dicts: [commonDict],
            onComplete: () {
              Navigator.of(dialogContext).pop();
            },
          ),
        );
      }

      // 4. 获取概要信息
      setState(() => _statusMessage = '正在获取数据库统计信息...');
      await _getDbSummary();

      setState(() {
        _isProcessing = false;
        _isFinished = true;
        _statusMessage = '制作完成';
      });
      
    } catch (e) {
      Global.logger.e('制作黄金母版失败: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = '制作失败: $e';
      });
      ToastUtil.error('制作失败: $e');
      
      // 失败后恢复环境
      Api.useProdUrl = false;
      Api.resetClient();
    }
  }

  Future<void> _getDbSummary() async {
    final db = MyDatabase.instance;
    _dbVersion = db.schemaVersion;
    _dbPath = await MyDatabase.getDbFilePath();
    
    // 获取所有非系统表
    final tableResults = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'drift_%' ORDER BY name"
    ).get();
    
    _totalTables = tableResults.length;
    _tableCounts.clear();
    for (var row in tableResults) {
      final tableName = row.read<String>('name');
      try {
        final countResult = await db.customSelect('SELECT COUNT(*) as c FROM "$tableName"').getSingle();
        _tableCounts[tableName] = countResult.read<int>('c');
      } catch (e) {
        Global.logger.w('获取表 $tableName 计数失败: $e');
        _tableCounts[tableName] = -1; // 表示获取失败
      }
    }
  }
}
