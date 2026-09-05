import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/theme/app_theme.dart';

class ChineseAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;
  final FocusNode focusNode;
  final int? score; // 匹配度得分
  final bool isScorePassed; // 当前得分是否满足通过条件（含核心词匹配）
  final bool isSentenceStep; // 是否是例句练习步骤
  final bool isAiEvaluating; // 是否正在进行大模型裁判

  const ChineseAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
    required this.focusNode,
    this.score,
    this.isScorePassed = false,
    this.isSentenceStep = false,
    this.isAiEvaluating = false,
  });

  @override
  State<ChineseAsrInputWidget> createState() => _ChineseAsrInputWidgetState();
}

class _ChineseAsrInputWidgetState extends State<ChineseAsrInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  StreamSubscription<double>? _meterSubscription;
  double _currentLevel = 0.0;
  static const List<double> _weights = [0.35, 0.65, 0.9, 1.0, 1.0, 0.9, 0.65, 0.35];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    StudyAudioSessionController.instance.meterLevelNotifier.addListener(_onMeterNotifierChanged);
    _meterSubscription = Asr().meterStream().listen(_onDirectLevelReceived);
    _syncWaveAnimation();
  }

  void _onMeterNotifierChanged() {
    final v = StudyAudioSessionController.instance.meterLevelNotifier.value;
    _applyLevel(v);
  }

  void _onDirectLevelReceived(double level) {
    _applyLevel(level);
  }

  void _applyLevel(double target) {
    if (!mounted) return;
    final clamped = target.clamp(0.0, 1.0);
    // 快速起跳 (Attack 0.75)，平缓自然衰减 (Decay 0.2)
    if (clamped > _currentLevel) {
      _currentLevel = _currentLevel * 0.25 + clamped * 0.75;
    } else {
      _currentLevel = _currentLevel * 0.8 + clamped * 0.2;
    }
  }

  @override
  void didUpdateWidget(covariant ChineseAsrInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asrState != widget.asrState) {
      _syncWaveAnimation();
    }
  }

  /// 波形动画按需启停：仅识别进行中(started)时运行，其余状态停止，
  /// 避免 AnimationController 无限 repeat 在非识别状态空转浪费资源。
  void _syncWaveAnimation() {
    if (widget.asrState == AsrState.started) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      if (_waveController.isAnimating) {
        _waveController.stop();
        _waveController.reset();
      }
    }
  }

  @override
  void dispose() {
    StudyAudioSessionController.instance.meterLevelNotifier.removeListener(_onMeterNotifierChanged);
    _meterSubscription?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  Widget _buildAiJudgingBadge(BuildContext context) {
    final accentColor = context.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 8.5,
            height: 8.5,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            'AI判定中...',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final accentColor = context.primaryColor;

    // 状态驱动反馈文字
    String statusText;
    if (widget.isAiEvaluating) {
      statusText = "AI裁判裁决中...";
    } else {
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
          if ((widget.score ?? 0) >= 85) {
            statusText = "释义精准";
          } else if ((widget.score ?? 0) >= 60) {
            statusText = "释义达标";
          } else if ((widget.score ?? 0) > 0) {
            statusText = "释义可提升";
          } else {
            statusText = widget.isSentenceStep ? "请说例句中文" : "请说中文释义";
          }
          break;
      }
    }

    final bool isPassed = widget.isScorePassed || (widget.isSentenceStep ? false : (widget.score ?? 0) >= 60);

    final scoreWidget = (widget.score != null && widget.score! > 0)
        ? Tooltip(
            message: '匹配度得分',
            triggerMode: TooltipTriggerMode.tap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isPassed
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                border: Border.all(
                  color: isPassed
                      ? Colors.green.withValues(alpha: 0.5)
                      : Colors.orange.withValues(alpha: 0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SizedBox(
                width: 25,
                child: Center(
                  child: Text(
                    '${widget.score ?? 0}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isPassed
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    final waveformWidget = SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: Listenable.merge([_waveController, StudyAudioSessionController.instance.meterLevelNotifier]),
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(8, (index) {
              // 默认静止状态 (纤细微型条)
              double height = 2.5;
              double alpha = 0.25;

              // 动态聆听状态：仅识别进行中(started)才波动
              if (widget.asrState == AsrState.started) {
                final double weight = _weights[index];
                final double phase = (_waveController.value * 2 * pi) + (index * 0.3 * pi);
                final double idleBreath = (sin(phase) + 1.0) / 2.0; // 0.0 ~ 1.0
                
                // 基础静音呼吸高度 (2.5 ~ 4.5 像素，纤细精致)
                final double baseHeight = 2.5 + 2.0 * idleBreath * weight;
                
                // 说话电平驱动增益 (Voice Dynamic Boost)
                // 说话时电平驱动波形瞬间高涨跃动 (高度可达到 12 ~ 18.5 像素)，视觉反馈极为充沛
                final double notifierVal = StudyAudioSessionController.instance.meterLevelNotifier.value;
                final double effectiveLevel = max(_currentLevel, notifierVal).clamp(0.0, 1.0);
                final double voiceWave = (sin(phase * 1.8 + index * 0.35) + 1.0) / 2.0;
                final double voiceBoost = effectiveLevel * 18.0 * weight * (0.4 + 0.6 * voiceWave);
                
                height = (baseHeight + voiceBoost).clamp(2.5, 19.0);
                alpha = (0.35 + 0.25 * idleBreath + 0.4 * effectiveLevel).clamp(0.2, 1.0);
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 2.5,
                height: height,
                decoration: BoxDecoration(
                  color: widget.isAiEvaluating
                      ? accentColor.withValues(alpha: 0.8)
                      : accentColor.withValues(alpha: alpha),
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: widget.isSentenceStep
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    waveformWidget,
                    const SizedBox(width: 12),
                    if (widget.isAiEvaluating) ...[
                      _buildAiJudgingBadge(context),
                    ] else ...[
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? Colors.white38 : Colors.black26,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (scoreWidget != null) ...[
                        const SizedBox(width: 6),
                        scoreWidget,
                      ],
                    ],
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    waveformWidget,
                    const SizedBox(height: 2),
                    if (widget.isAiEvaluating)
                      _buildAiJudgingBadge(context)
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDarkMode ? Colors.white54 : Colors.black45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (scoreWidget != null) ...[
                            const SizedBox(width: 4),
                            scoreWidget,
                          ],
                        ],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
