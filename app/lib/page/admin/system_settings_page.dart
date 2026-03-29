import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  bool _isLoading = true;
  int _concurrencyLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final result = await Api.client.getAiStoryConfig();
      if (result.success && result.data != null) {
        setState(() {
          _concurrencyLimit = result.data!.data['concurrencyLimit'] as int;
          _isLoading = false;
        });
      } else {
        ToastUtil.error(result.msg ?? '获取配置失败');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    try {
      final result = await Api.client.saveAiStoryConfig(_concurrencyLimit);
      if (result.success) {
        ToastUtil.success('配置保存成功');
      } else {
        ToastUtil.error(result.msg ?? '保存失败');
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: '系统设置',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('AI 短文生成设置', isDarkMode),
                  const SizedBox(height: 12),
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bolt, color: Colors.amber),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  '并发上限',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                '$_concurrencyLimit',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: _concurrencyLimit.toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            label: '$_concurrencyLimit',
                            activeColor: AppTheme.primaryColor,
                            onChanged: (value) {
                              setState(() {
                                _concurrencyLimit = value.toInt();
                              });
                            },
                          ),
                          const Divider(),
                          const Text(
                            '限制同一时间允许多少个用户同时调用 AI 生成短文。建议根据服务器性能调优（推荐值：5-10）。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveConfig,
                      child: const Text('保存配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDarkMode) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        letterSpacing: 1.2,
      ),
    );
  }
}
