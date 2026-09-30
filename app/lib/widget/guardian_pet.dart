import 'dart:math';

import 'package:flutter/material.dart';

/// 记忆守护兽的轻动效组件。
///
/// 三层素材叠加驱动，互不干扰：
///   - 身体层 `layers/guardian_gel_正面_身体层.png`：负责呼吸位移与挤压拉伸
///   - 情绪层 `moods/mood_*.png`：负责眨眼与情绪交叉淡入（与身体层像素级重合）
///   - 光核层 `layers/guardian_gel_正面_光核层.png`：负责发光脉冲
///
/// 参数依据 `design/ui/pet_motion_preview.html` 的手感原型，两边必须一起改。
class GuardianPet extends StatefulWidget {
  const GuardianPet({
    super.key,
    this.mood = PetMood.excited,
    this.height = 180,
    this.breathPeriod = const Duration(milliseconds: 2600),
    this.breathAmplitude = 1.0,
    this.blinkInterval = const Duration(seconds: 4),
    this.animate = true,
    this.onTap,
  });

  final PetMood mood;
  final double height;
  final Duration breathPeriod;
  final double breathAmplitude;
  final Duration blinkInterval;
  final bool animate;
  final VoidCallback? onTap;

  @override
  State<GuardianPet> createState() => _GuardianPetState();
}

/// 宠物情绪，与 `assets/images/pet/moods/` 里的图一一对应。
enum PetMood {
  excited('mood_excited'),
  happy('mood_happy'),
  hungry('mood_hungry'),
  sad('mood_sad'),
  sleepy('mood_sleepy');

  const PetMood(this.assetName);

  final String assetName;

  /// 情绪对光核脉冲周期的影响：越没精神，脉冲越慢。
  Duration get corePeriod => switch (this) {
        PetMood.happy => const Duration(milliseconds: 2000),
        PetMood.hungry => const Duration(milliseconds: 3600),
        PetMood.sad => const Duration(milliseconds: 4400),
        PetMood.sleepy => const Duration(milliseconds: 6000),
        PetMood.excited => const Duration(milliseconds: 2600),
      };

  /// 情绪对整体色彩的影响：消沉与昏睡时降低饱和与亮度。
  double get saturation => switch (this) {
        PetMood.sad => 0.62,
        PetMood.sleepy => 0.50,
        _ => 1.0,
      };

  double get brightness => switch (this) {
        PetMood.sad => 0.92,
        PetMood.sleepy => 0.86,
        _ => 1.0,
      };
}

class _GuardianPetState extends State<GuardianPet> with TickerProviderStateMixin {
  static const String _assetDir = 'assets/images/pet/';
  static const String _bodyLayer = '${_assetDir}layers/guardian_gel_正面_身体层.png';
  static const String _coreLayer = '${_assetDir}layers/guardian_gel_正面_光核层.png';
  static const String _moodDir = '${_assetDir}moods/';

  late final AnimationController _breath = AnimationController(vsync: this, duration: widget.breathPeriod)..repeat(reverse: true);
  late final AnimationController _core = AnimationController(vsync: this, duration: widget.mood.corePeriod)..repeat(reverse: true);
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final AnimationController _jelly = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  final Random _random = Random();

  @override
  void didUpdateWidget(covariant GuardianPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.breathPeriod != widget.breathPeriod) {
      _breath.duration = widget.breathPeriod;
      if (_breath.isAnimating) _breath.repeat(reverse: true);
    }
    if (oldWidget.mood != widget.mood) {
      _core.duration = widget.mood.corePeriod;
      if (_core.isAnimating) _core.repeat(reverse: true);
    }
    if (oldWidget.animate != widget.animate) {
      widget.animate ? _start() : _stop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  void _start() {
    _breath.repeat(reverse: true);
    _core.repeat(reverse: true);
    _scheduleBlink();
  }

  void _stop() {
    _breath.stop();
    _core.stop();
    _blink.stop();
  }

  /// 眨眼间隔带随机抖动，固定间隔会显得机械。
  void _scheduleBlink() {
    if (!mounted) return;
    final base = widget.blinkInterval.inMilliseconds;
    final delay = (base * (0.6 + _random.nextDouble() * 0.8)).round();
    Future.delayed(Duration(milliseconds: delay), () async {
      if (!mounted || !widget.animate) return;
      await _blink.forward(from: 0);
      await _blink.reverse();
      _scheduleBlink();
    });
  }

  void _handleTap() {
    widget.onTap?.call();
    _jelly.forward(from: 0);
  }

  @override
  void dispose() {
    _breath.dispose();
    _core.dispose();
    _blink.dispose();
    _jelly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height * 581 / 1116;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_saturationMatrix(widget.mood.saturation, widget.mood.brightness)),
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _core, _blink, _jelly]),
          builder: (context, child) {
            // 呼吸：位移 ±2.2px、缩放 1 → 0.992
            final breathT = Curves.easeInOut.transform(_breath.value);
            final lift = (1 - 2 * breathT) * 2.2 * widget.breathAmplitude;
            final breathScale = 1 - 0.008 * widget.breathAmplitude * breathT;

            // 挤压拉伸：0.94 → 1.05 → 1
            final jellyT = _jelly.value;
            final jellyScale = jellyT == 0
                ? 1.0
                : 1 + 0.07 * sin(jellyT * pi) * (1 - jellyT) - 0.03 * sin(jellyT * 2 * pi) * (1 - jellyT);

            return Transform.translate(
              offset: Offset(0, -lift),
              child: Transform.scale(
                scale: breathScale * jellyScale,
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: width,
                  height: widget.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(_bodyLayer, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                      Opacity(
                        opacity: 1 - _blink.value,
                        child: Image.asset('$_moodDir${widget.mood.assetName}.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
                      ),
                      // 光核脉冲：透明度 0.45 → 0.9，缩放 0.94 → 1.06
                      Align(
                        alignment: const Alignment(0, 0.28),
                        child: Opacity(
                          opacity: 0.45 + 0.45 * _core.value,
                          child: Transform.scale(
                            scale: 0.94 + 0.12 * _core.value,
                            child: SizedBox(
                              width: width * 0.7,
                              height: widget.height * 0.38,
                              child: Image.asset(_coreLayer, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 饱和度与亮度矩阵（0~1 缩放到 Flutter 的 ColorFilter 矩阵）。
  static List<double> _saturationMatrix(double saturation, double brightness) {
    const lumR = 0.2126;
    const lumG = 0.7152;
    const lumB = 0.0722;
    final s = saturation;
    final b = brightness;
    return <double>[
      (lumR * (1 - s) + s) * b, lumG * (1 - s) * b, lumB * (1 - s) * b, 0, 0,
      lumR * (1 - s) * b, (lumG * (1 - s) + s) * b, lumB * (1 - s) * b, 0, 0,
      lumR * (1 - s) * b, lumG * (1 - s) * b, (lumB * (1 - s) + s) * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}
