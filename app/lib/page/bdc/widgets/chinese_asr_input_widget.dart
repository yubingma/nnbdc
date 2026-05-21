import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/state.dart';

class ChineseAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;
  final FocusNode focusNode;

  const ChineseAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
    required this.focusNode,
  });

  @override
  State<ChineseAsrInputWidget> createState() => _ChineseAsrInputWidgetState();
}

class _ChineseAsrInputWidgetState extends State<ChineseAsrInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  StreamSubscription<double>? _meterSubscription;
  double _currentLevel = 0.0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _meterSubscription = Asr().meterStream().listen((level) {
      if (mounted) {
        setState(() {
          // 增加平滑处理，避免剧烈抖动
          _currentLevel = _currentLevel * 0.8 + level * 0.2;
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _meterSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final accentColor = AppTheme.primaryColor;

    // 状态驱动反馈文字
    String statusText;
    switch (widget.asrState) {
      case AsrState.started:
        statusText = "正在倾听...";
        break;
      case AsrState.stopping:
      case AsrState.unknown:
        statusText = "正在处理中...";
        break;
      case AsrState.initialized:
      case AsrState.stopped:
        statusText = "";
        break;
    }

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 波纹动画反馈 (始终显示以保持布局稳定)
          SizedBox(
            height: 20,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (index) {
                    // 默认静止状态（准备就绪/处理中）
                    double height = 4.0;
                    double alpha = 0.2;

                    // 动态聆听或就绪状态
                    if (widget.asrState == AsrState.started ||
                        widget.asrState == AsrState.initialized) {
                      // 基础呼吸扫描值（用于待机）
                      final double breath = sin(
                          (_waveController.value + (index * 0.125)) * pi * 2);

                      // 提高阈值 (原 0.01) 到 0.12 以过滤 iPad 等设备的高灵敏微弱底噪
                      if (_currentLevel > 0.12) {
                        // 正在说话：高敏捷跳动波形
                        final randomFactor = 0.5 + _random.nextDouble();
                        // 减小放大倍数 (原 100) 到 35，避免动不动就满格，且波形更平滑
                        height = 6.0 + (35 * _currentLevel * randomFactor);
                        if (height > 20) height = 20;
                        alpha = 0.6 + (2.0 * _currentLevel);
                        if (alpha > 1.0) alpha = 1.0;
                      } else {
                        // 待机静音：基础颜色深、振幅明显的呼吸波纹
                        height = 5.0 + (6.0 * (breath + 1) / 2);
                        alpha = 0.4 + (0.3 * (breath + 1) / 2);
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 2.5,
                      height: height,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: alpha),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 10,
              color: isDarkMode ? Colors.white38 : Colors.black26,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ));
  }
}
