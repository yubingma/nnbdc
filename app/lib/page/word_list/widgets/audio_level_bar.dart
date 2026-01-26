import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../state.dart';

/// 音量水平条
class AudioLevelBar extends StatelessWidget {
  final List<double> waveLevels;
  final ValueNotifier<double> meterLevelNotifier;
  final bool showDebugValue;

  const AudioLevelBar({
    super.key,
    required this.waveLevels,
    required this.meterLevelNotifier,
    this.showDebugValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    const barCount = 8;

    return SizedBox(
      height: 48,
      child: ValueListenableBuilder<double>(
        valueListenable: meterLevelNotifier,
        builder: (context, _, __) {
          final List<double> samples = List<double>.from(waveLevels);
          if (samples.isEmpty) {
            return _buildPlaceholder(isDarkMode);
          }

          final int n = samples.length;
          final int bars = barCount;
          final double bucketSize = n / bars;
          final List<double> buckets = List<double>.generate(bars, (i) {
            final start = (i * bucketSize).floor();
            final end = (((i + 1) * bucketSize).ceil()).clamp(start + 1, n);
            double maxv = 0.0;
            for (int k = start; k < end; k++) {
              if (samples[k] > maxv) maxv = samples[k];
            }
            return maxv;
          });

          final barsRow = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(bars, (i) {
              final v = buckets[i].clamp(0.0, 1.0);
              final h = 1.0 + v * 47.0;
              return Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    height: h,
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: Color.lerp(AppTheme.gradientStartColor, AppTheme.gradientEndColor, v),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }),
          );

          if (!showDebugValue) return barsRow;

          return Stack(
            children: [
              barsRow,
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    color: Colors.transparent,
                    child: Text(
                      meterLevelNotifier.value.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 9,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(bool isDarkMode) {
    return Row(
      children: List.generate(
        16,
        (i) => Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFEAEAEA),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
