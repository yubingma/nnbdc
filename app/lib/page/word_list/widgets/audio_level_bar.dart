import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../state.dart';
import '../../../util/study_audio_session_controller.dart';

/// 词表页面音量波形条（与背单词页面统一的声学动力学波形）
class AudioLevelBar extends StatefulWidget {
  final List<double>? waveLevels;
  final ValueNotifier<double>? meterLevelNotifier;
  final bool showDebugValue;

  const AudioLevelBar({
    super.key,
    this.waveLevels,
    this.meterLevelNotifier,
    this.showDebugValue = false,
  });

  @override
  State<AudioLevelBar> createState() => _AudioLevelBarState();
}

class _AudioLevelBarState extends State<AudioLevelBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  double _currentLevel = 0.0;
  static const List<double> _weights = [0.35, 0.65, 0.9, 1.0, 1.0, 0.9, 0.65, 0.35];

  ValueNotifier<double> get _activeNotifier =>
      widget.meterLevelNotifier ??
      StudyAudioSessionController.instance.meterLevelNotifier;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _activeNotifier.addListener(_onMeterChanged);
  }

  void _onMeterChanged() {
    final target = _activeNotifier.value.clamp(0.0, 1.0);
    // 快速起跳 (Attack 0.75)，平缓自然衰落 (Decay 0.2)
    if (target > _currentLevel) {
      _currentLevel = _currentLevel * 0.25 + target * 0.75;
    } else {
      _currentLevel = _currentLevel * 0.8 + target * 0.2;
    }
  }

  @override
  void didUpdateWidget(covariant AudioLevelBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meterLevelNotifier != widget.meterLevelNotifier) {
      (oldWidget.meterLevelNotifier ?? StudyAudioSessionController.instance.meterLevelNotifier)
          .removeListener(_onMeterChanged);
      _activeNotifier.addListener(_onMeterChanged);
    }
  }

  @override
  void dispose() {
    _activeNotifier.removeListener(_onMeterChanged);
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final accentStart = AppTheme.gradientStartColor;
    final accentEnd = AppTheme.gradientEndColor;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_waveController, _activeNotifier]),
        builder: (context, _) {
          final effectiveLevel = max(_currentLevel, _activeNotifier.value).clamp(0.0, 1.0);

          final barsRow = Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(8, (index) {
              final weight = _weights[index];
              final phase = (_waveController.value * 2 * pi) + (index * 0.3 * pi);
              final idleBreath = (sin(phase) + 1.0) / 2.0; // 0.0 ~ 1.0

              // 基础静音呼吸高度 (2.0 ~ 3.5 像素，纤细精致)
              final baseHeight = 2.0 + 1.5 * idleBreath * weight;

              // 说话电平连续激励 (随声浪自然起伏，最高可达 11.5 像素)
              final voiceWave = (sin(phase * 1.8 + index * 0.35) + 1.0) / 2.0;
              final voiceBoost = effectiveLevel * 7.5 * weight * (0.4 + 0.6 * voiceWave);

              final h = (baseHeight + voiceBoost).clamp(2.0, 11.5);
              final alpha = (0.35 + 0.25 * idleBreath + 0.4 * effectiveLevel).clamp(0.2, 1.0);
              final barColor = Color.lerp(accentStart, accentEnd, weight * (0.3 + 0.7 * effectiveLevel))!;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                width: 2.0,
                height: h,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(1.0),
                ),
              );
            }),
          );

          final content = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: barsRow,
          );

          if (!widget.showDebugValue) return content;

          return Stack(
            alignment: Alignment.center,
            children: [
              barsRow,
              Positioned(
                right: 0,
                top: 0,
                child: Text(
                  _activeNotifier.value.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 8,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
