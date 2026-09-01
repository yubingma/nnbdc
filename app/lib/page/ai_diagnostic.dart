import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/services/ai_model_manager.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/state.dart';

class AiDiagnosticPage extends StatefulWidget {
  const AiDiagnosticPage({super.key});

  @override
  State<AiDiagnosticPage> createState() => _AiDiagnosticPageState();
}

class _AiDiagnosticPageState extends State<AiDiagnosticPage> {
  bool _isChecking = false;
  String _diagnosticResult = '';
  Map<String, dynamic> _statusInfo = {};

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
      _diagnosticResult = '正在诊断...\n';
      _statusInfo = {};
    });

    try {
      final buffer = StringBuffer();

      // 1. 检查平台支持
      buffer.writeln('=== 平台支持检查 ===');
      String platformName = 'Unknown';
      if (PlatformUtils.isAndroid) {
        platformName = 'Android';
      } else if (PlatformUtils.isIOS) {
        platformName = 'iOS';
      } else if (PlatformUtils.isMacOS) {
        platformName = 'macOS';
      } else if (PlatformUtils.isWindows) {
        platformName = 'Windows';
      } else if (PlatformUtils.isWeb) {
        platformName = 'Web';
      }

      buffer.writeln('当前平台: $platformName');
      buffer.writeln('是否Android: ${PlatformUtils.isAndroid}');
      buffer.writeln('是否iOS: ${PlatformUtils.isIOS}');
      buffer.writeln('是否macOS: ${PlatformUtils.isMacOS}');
      buffer.writeln('');

      // 2. 检查AI服务状态
      buffer.writeln('=== AI服务状态 ===');
      final aiService = AiService();
      buffer.writeln('当前能力等级: ${aiService.capabilityLevel}');
      buffer.writeln('运行时类型: ${aiService.runtime.runtimeType}');
      buffer.writeln('是否为Noop运行时: ${aiService.runtime is NoopAiRuntime}');
      buffer.writeln('');

      // 3. 检查模型状态
      buffer.writeln('=== 模型状态检查 ===');
      final modelManager = AiModelManager();
      final localState = await modelManager.loadLocalState();

      if (localState != null) {
        buffer.writeln('✓ 模型状态文件存在');
        buffer.writeln('  Profile: ${localState.profile.name}');
        buffer.writeln('  版本: ${localState.version}');
        buffer.writeln('  本地路径: ${localState.localPath}');
        buffer.writeln('  大小: ${(localState.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');

        // 检查文件是否存在
        final file = File(localState.localPath);
        final fileExists = await file.exists();
        buffer.writeln('  文件存在: ${fileExists ? "✓" : "✗"}');

        _statusInfo['modelState'] = {
          'exists': true,
          'profile': localState.profile.name,
          'version': localState.version,
          'path': localState.localPath,
          'fileExists': fileExists,
        };
      } else {
        buffer.writeln('✗ 未找到模型状态文件');
        _statusInfo['modelState'] = {'exists': false};
      }
      buffer.writeln('');

      // 4. 检查Android特定状态
      if (PlatformUtils.isAndroid) {
        buffer.writeln('=== Android平台检查 ===');
        try {
          final channel = const MethodChannel('com.nnbdc.ai_inference');

          // 检查能力
          final capResult = await channel.invokeMethod('checkCapability');
          buffer.writeln('设备能力检查结果: $capResult');
          _statusInfo['androidCapability'] = capResult;

          // 如果模型存在，尝试检查加载状态
          if (localState != null && localState.localPath.isNotEmpty) {
            try {
              final loadResult = await channel.invokeMethod('loadModel', {
                'modelPath': localState.localPath,
              });
              buffer.writeln('模型加载尝试结果: $loadResult');
              _statusInfo['loadModelResult'] = loadResult;
            } catch (e) {
              buffer.writeln('模型加载调用失败: $e');
              _statusInfo['loadModelError'] = e.toString();
            }
          }
        } catch (e) {
          buffer.writeln('Android原生通道调用失败: $e');
          _statusInfo['channelError'] = e.toString();
        }
        buffer.writeln('');
      }

      // 5. 建议和解决方案
      buffer.writeln('=== 诊断建议 ===');
      if (aiService.capabilityLevel == AiCapabilityLevel.none) {
        if (_statusInfo['modelState']?['exists'] == true) {
          if (_statusInfo['modelState']?['fileExists'] == true) {
            buffer.writeln('✓ 模型文件存在但AI服务未正确初始化');
            buffer.writeln('建议: 重新初始化AI运行时');
            if (PlatformUtils.isAndroid) {
              buffer.writeln('执行: await initializeAndroidAiRuntime()');
            } else if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
              buffer.writeln('执行: await initializeAppleAiRuntime()');
            }
          } else {
            buffer.writeln('✗ 模型状态文件指向的文件不存在');
            buffer.writeln('建议: 重新下载模型');
            buffer.writeln('执行: 在AI激活页面重新激活');
          }
        } else {
          buffer.writeln('✗ 未检测到模型');
          buffer.writeln('建议: 前往AI激活页面下载模型');
        }
      } else {
        buffer.writeln('✓ AI服务运行正常');
      }

      setState(() {
        _diagnosticResult = buffer.toString();
        _isChecking = false;
      });
    } catch (e, st) {
      Global.logger.e('诊断过程异常', error: e, stackTrace: st);
      setState(() {
        _diagnosticResult = '诊断失败: $e\n\n请查看日志获取详细信息';
        _isChecking = false;
      });
    }
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
        title: 'AI诊断工具',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: cardColor,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.health_and_safety, color: AppTheme.primaryColor, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'AI健康诊断',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '此工具可以帮助诊断AI助教功能的问题',
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: cardColor,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '诊断结果',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        if (_isChecking) const CircularProgressIndicator(strokeWidth: 2),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: SelectableText(
                        _diagnosticResult,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: textColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isChecking ? null : _runDiagnostics,
              icon: const Icon(Icons.refresh),
              label: const Text('重新诊断'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            if (_statusInfo.isNotEmpty) ...[
              Card(
                color: cardColor,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '详细状态信息',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(_statusInfo),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
