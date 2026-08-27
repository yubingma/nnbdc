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
  final int? score; // 新增：匹配度得分
  final bool isSentenceStep; // 新增：是否是例句练习步骤

  const ChineseAsrInputWidget({
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
    );

    _meterSubscription = Asr().meterStream().listen((level) {
      if (mounted) {
        setState(() {
          // 增加平滑处理，避免剧烈抖动
          _currentLevel = _currentLevel * 0.8 + level * 0.2;
        });
      }
    });
    _syncWaveAnimation();
  }

  @override
  void didUpdateWidget(covariant ChineseAsrInputWidget oldWidget) {
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
        statusText = widget.isSentenceStep ? "请说例句中文" : "请说中文释义";
        break;
    }

    final scoreWidget = Visibility(
      visible: widget.score != null && widget.score! > 0,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: Tooltip(
        message: '匹配度得分',
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
              // initialized 只是模型就绪(未录音/未按住PTT),不应波动。
              if (widget.asrState == AsrState.started) {
                final double breath = sin(
                    (_waveController.value + (index * 0.125)) * pi * 2);

                if (_currentLevel > 0.12) {
                  final randomFactor = 0.5 + _random.nextDouble();
                  height = 6.0 + (35 * _currentLevel * randomFactor);
                  if (height > 20) height = 20;
                  alpha = 0.6 + (2.0 * _currentLevel);
                  if (alpha > 1.0) alpha = 1.0;
                } else {
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
