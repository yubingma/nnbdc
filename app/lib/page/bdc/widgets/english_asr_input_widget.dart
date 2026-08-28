import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/state.dart';

class EnglishAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;
  final FocusNode focusNode;
  final int? score; // 新增：评分
  final bool isSentenceStep; // 新增：是否是例句练习步骤

  const EnglishAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
    required this.focusNode,
    this.score,
    this.isSentenceStep = false,
  });

  @override
  State<EnglishAsrInputWidget> createState() => _EnglishAsrInputWidgetState();
}

class _EnglishAsrInputWidgetState extends State<EnglishAsrInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  StreamSubscription<double>? _meterSubscription;
  double _currentLevel = 0.0;
  static const List<double> _weights = [0.35, 0.6, 0.85, 1.0, 1.0, 0.85, 0.6, 0.35];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _meterSubscription = Asr().meterStream().listen((level) {
      if (mounted) {
        setState(() {
          // 音频电平平滑滤波：快速响应上升 (Attack)，平缓衰减回落 (Decay)
          if (level > _currentLevel) {
            _currentLevel = _currentLevel * 0.35 + level * 0.65;
          } else {
            _currentLevel = _currentLevel * 0.82 + level * 0.18;
          }
        });
      }
    });
    _syncWaveAnimation();
  }

  @override
  void didUpdateWidget(covariant EnglishAsrInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWaveAnimation();
  }

  /// 波形动画按需启停：仅识别进行中(started)时运行，其余状态停止，
  /// 避免 AnimationController 无限 repeat 在非识别状态空转浪费资源。
  void _syncWaveAnimation() {
    if (widget.asrState == AsrState.started) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else {
      if (_waveController.isAnimating) _waveController.stop();
    }
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
        statusText = widget.isSentenceStep ? "请说例句英文" : "请说单词发音";
        break;
    }

    final scoreWidget = Visibility(
      visible: widget.score != null && widget.score! > 0,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: Tooltip(
        message: '发音评分',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: (widget.score ?? 0) >= 60
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            border: Border.all(
              color: (widget.score ?? 0) >= 60
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.orange.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: SizedBox(
            width: 25,
            child: Center(
              child: Text(
                '${widget.score ?? 0}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: (widget.score ?? 0) >= 60
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final waveformWidget = SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(8, (index) {
              // 默认静止状态
              double height = 4.0;
              double alpha = 0.2;

              // 动态聆听状态：仅识别进行中(started)才波动。
              if (widget.asrState == AsrState.started) {
                final double weight = _weights[index];
                final double phase = (_waveController.value * 2 * pi) + (index * 0.28 * pi);
                final double idleWave = (sin(phase) + 1.0) / 2.0; // 0.0 ~ 1.0
                
                // 基础呼吸高度 (3.5 ~ 6.5)
                final double idleHeight = 3.5 + 3.0 * idleWave * weight;
                
                // 说话电平连续激励 (随声浪自然起伏，最高可达 16.5)
                final double activeWave = (sin(phase * 1.5 + index * 0.2) + 1.0) / 2.0;
                final double voiceBoost = _currentLevel * 10.0 * weight * (0.6 + 0.4 * activeWave);
                
                height = (idleHeight + voiceBoost).clamp(3.5, 18.0);
                alpha = (0.35 + 0.25 * idleWave + 0.4 * _currentLevel).clamp(0.2, 1.0);
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
    );

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: widget.isSentenceStep
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  waveformWidget,
                  const SizedBox(width: 12),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDarkMode ? Colors.white38 : Colors.black26,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  scoreWidget,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  waveformWidget,
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDarkMode ? Colors.white54 : Colors.black45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      scoreWidget,
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
