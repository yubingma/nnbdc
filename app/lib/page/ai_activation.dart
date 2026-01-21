import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/services/ai_model_manager.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/main.dart' as main_app;
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';

/// AI 功能激活页面
/// 面向最终用户的友好界面，帮助用户在本地激活 AI 功能
class AiActivationPage extends StatefulWidget {
  const AiActivationPage({super.key});

  @override
  State<AiActivationPage> createState() => _AiActivationPageState();
}

class _AiActivationPageState extends State<AiActivationPage> {
  bool _isLoading = false;
  bool _isActivated = false;
  String _currentStep = '';
  String? _errorMessage;
  double _downloadProgress = 0.0; // 下载进度 0.0 - 1.0
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isIntelMac = false; // 标记是否为 Intel Mac

  @override
  void initState() {
    super.initState();
    _checkArchitecture();
    _checkAiStatus();
  }
  
  /// 检查 Mac 架构
  Future<void> _checkArchitecture() async {
    if (!PlatformUtils.isMacOS) return;
    
    try {
      final result = await Process.run('uname', ['-m']);
      final arch = result.stdout.toString().trim();
      setState(() {
        _isIntelMac = arch != 'arm64';
      });
      if (_isIntelMac) {
        Global.logger.i('检测到 Intel Mac，AI 功能暂不支持');
      }
    } catch (e) {
      Global.logger.w('架构检测失败: $e');
    }
  }

  /// 检查 AI 功能是否已激活
  Future<void> _checkAiStatus() async {
    try {
      // 检查是否已下载模型文件
      final manager = AiModelManager();
      final localState = await manager.loadLocalState();
      
      setState(() {
        // 如果本地有模型文件，说明已激活
        _isActivated = localState != null && localState.localPath.isNotEmpty;
      });
      
      // 如果已激活但运行时未初始化，自动初始化（仅 macOS）
      if (_isActivated && 
          PlatformUtils.isMacOS && 
          AiService().capabilityLevel == AiCapabilityLevel.none) {
        Global.logger.i('检测到模型已下载但运行时未初始化，开始自动初始化...');
        await main_app.initializeMacOsAiRuntime();
      }
    } catch (e) {
      Global.logger.e('检查 AI 状态异常', error: e);
    }
  }

  /// 激活 AI 功能的主流程
  Future<void> _activateAi() async {
    if (!PlatformUtils.isMacOS) {
      setState(() {
        _errorMessage = '抱歉，AI 功能目前仅支持 macOS 平台';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentStep = '正在准备...';
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
    });

    try {
      final manager = AiModelManager();
      
      // 检查是否已有模型
      final existingState = await manager.loadLocalState();
      bool needDownload = existingState == null || existingState.localPath.isEmpty;
      
      if (needDownload) {
        // 1. 获取模型信息
        setState(() => _currentStep = '正在获取模型信息...');
        final metas = await manager.fetchRemoteMeta();
        
        if (metas.isEmpty) {
          throw Exception('无法获取模型信息，请检查网络连接');
        }
        
        final meta = metas[AiModelProfile.desktopFull];
        if (meta == null) {
          throw Exception('未找到适用的 AI 模型');
        }

        // 2. 下载模型文件（带进度回调）
        setState(() {
          _currentStep = '正在下载 AI 模型（约 ${(meta.sizeBytes / 1024 / 1024).toStringAsFixed(0)} MB）...';
          _totalBytes = meta.sizeBytes;
        });
        
        final state = await manager.ensureModel(
          AiModelProfile.desktopFull,
          onProgress: (progress, downloaded, total) {
            setState(() {
              _downloadProgress = progress;
              _downloadedBytes = downloaded;
              _totalBytes = total;
            });
          },
        );
        
        if (state == null) {
          throw Exception('模型下载失败，请稍后重试');
        }
      } else {
        Global.logger.i('模型已存在，跳过下载步骤');
      }

      // 3. 初始化 AI 运行时
      setState(() {
        _currentStep = '正在初始化 AI 引擎...';
        _downloadProgress = 0.0;
      });
      final success = await main_app.initializeMacOsAiRuntime();
      
      if (!success) {
        throw Exception('AI 引擎初始化失败');
      }

      // 激活成功
      setState(() {
        _isActivated = true;
        _currentStep = '';
      });
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => _buildSuccessDialog(),
        );
      }
    } catch (e, st) {
      Global.logger.e('AI 激活失败', error: e, stackTrace: st);
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _currentStep = '';
        _downloadProgress = 0.0;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 反激活 AI 功能
  Future<void> _deactivateAi() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
        final backgroundColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
        final textColor = isDarkMode ? Colors.white : Colors.black87;
        
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: Text('确认反激活', style: TextStyle(color: textColor)),
          content: Text(
            '这将卸载 AI 引擎并删除已下载的本地模型文件（约 500MB）。\n\n反激活后，你将无法在离线状态下使用 AI 智能解释功能。',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('确认反激活'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _currentStep = '正在反激活并清理模型...';
    });

    try {
      // 1. 停止并卸载运行时
      await main_app.deinitializeMacOsAiRuntime();
      
      // 2. 删除物理文件
      await AiModelManager().clearModel();
      
      setState(() {
        _isActivated = false;
        _currentStep = '';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 功能已反激活，本地模型已清理')),
        );
      }
    } catch (e, st) {
      Global.logger.e('AI 反激活失败', error: e, stackTrace: st);
      setState(() {
        _errorMessage = '反激活失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 构建激活成功对话框
  Widget _buildSuccessDialog() {
    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    
    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 32),
          const SizedBox(width: 12),
          Text('激活成功', style: TextStyle(color: textColor)),
        ],
      ),
      content: Text(
        'AI 功能已成功激活！\n\n现在你可以在单词详情页面使用 AI 智能解释功能，让学习更加高效。',
        style: TextStyle(color: textColor, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: 'AI 智能助手',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 功能介绍卡片
            Card(
              color: cardColor,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.psychology, color: AppTheme.primaryColor, size: 32),
                        const SizedBox(width: 12),
                        Text(
                          'AI 智能解释',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '激活 AI 功能后，你将获得：',
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(Icons.auto_awesome, '深度词义解析', '理解单词在不同语境下的细微差别', textColor, isDarkMode),
                    _buildFeatureItem(Icons.tips_and_updates, '记忆技巧', '获得个性化的单词记忆方法', textColor, isDarkMode),
                    _buildFeatureItem(Icons.translate, '地道用法', '学习单词的实际应用场景', textColor, isDarkMode),
                    _buildFeatureItem(Icons.offline_bolt, '本地运行', '数据完全保存在本地，保护隐私', textColor, isDarkMode),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Intel Mac 不支持提示
            if (_isIntelMac)
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '架构兼容性提示',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'AI 推理引擎目前仅支持 Apple Silicon (M1/M2/M3) Mac。\n\n检测到你的设备为 Intel Mac，暂时无法使用本地 AI 功能。',
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withValues(alpha: 0.8),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // 状态显示区域
            if (_isActivated) ...[
              Card(
                color: Colors.green.withValues(alpha: 0.1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI 功能已激活',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '你现在可以在单词详情页使用 AI 解释功能',
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 反激活按钮
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _deactivateAi,
                icon: const Icon(Icons.delete_outline),
                label: const Text('从本地彻底卸载 AI 功能'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]
            else ...[
              // 激活按钮
              ElevatedButton.icon(
                onPressed: (_isLoading || _isIntelMac) ? null : _activateAi,
                icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch),
                label: Text(
                  _isIntelMac 
                    ? '设备不支持' 
                    : (_isLoading ? '正在激活...' : '立即激活'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                ),
              ),
              // 进度提示
              if (_isLoading && _currentStep.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Card(
                    color: cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _currentStep,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          // 下载进度条
                          if (_downloadProgress > 0 && _totalBytes > 0) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                                minHeight: 8,
                                backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withValues(alpha: 0.6),
                                  ),
                                ),
                                Text(
                                  '${(_downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(_totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              
              // 错误提示
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Card(
                    color: Colors.red.withValues(alpha: 0.1),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '激活失败',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textColor.withValues(alpha: 0.7),
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
            ],
            
            const SizedBox(height: 24),
            
            // 系统要求说明
            Card(
              color: cardColor,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: textColor.withValues(alpha: 0.6), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '系统要求',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRequirementItem('平台支持', 'macOS（暂不支持其他平台）', textColor, isDarkMode),
                    _buildRequirementItem('存储空间', '约需 500 MB 可用空间', textColor, isDarkMode),
                    _buildRequirementItem('网络要求', '首次激活需要网络连接', textColor, isDarkMode),
                    _buildRequirementItem('使用方式', '激活后可离线使用', textColor, isDarkMode),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeatureItem(IconData icon, String title, String description, Color textColor, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRequirementItem(String label, String value, Color textColor, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
