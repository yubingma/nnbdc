import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/platform_util.dart';
import '../util/study_audio_session_controller.dart';

/// 打卡印章组件
///
/// 具备高保真双环印泥质感，并支持极具冲击力与仪式感的“凌空盖下”物理重击动效：
/// - 俯冲下落（Scale 2.5 -> 1.0）
/// - 落地重击瞬间触发 [HapticFeedback.heavyImpact] 与 [StudyAudioSessionController.playStampSound]
/// - 激荡向外扩散的同心冲击波光环（Shockwave Ripple）
/// - 阻尼回弹震颤（Bounce & Settle）
class DakaStampBadge extends StatefulWidget {
  /// 印章尺寸（正方形宽高）
  final double size;

  /// 是否为加量批次（打卡成功 vs 加量达成）
  final bool isExtraRound;

  /// 是否在初次挂载时播放盖章下落动画（默认为 true）
  final bool animate;

  /// 动画延迟启动时间
  final Duration delay;

  /// 印章主色调（默认经典朱砂红）
  final Color? color;

  /// 着陆冲击瞬间回调（可用于震动周边卡片或触发额外庆祝动效）
  final VoidCallback? onHit;

  const DakaStampBadge({
    super.key,
    this.size = 86.0,
    this.isExtraRound = false,
    this.animate = true,
    this.delay = const Duration(milliseconds: 150),
    this.color,
    this.onHit,
  });

  @override
  State<DakaStampBadge> createState() => _DakaStampBadgeState();
}

class _DakaStampBadgeState extends State<DakaStampBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _dropScaleAnimation;
  late final Animation<double> _bounceScaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _rotationAnimation;
  late final Animation<double> _rippleScaleAnimation;
  late final Animation<double> _rippleOpacityAnimation;

  bool _hasHit = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    // 0.0 ~ 0.52 (约 320ms)：高速俯冲下坠（2.5x -> 1.0x）
    _dropScaleAnimation = Tween<double>(begin: 2.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.52, curve: Curves.easeInCubic),
      ),
    );

    // 0.52 ~ 1.0 (约 300ms)：着陆触底回弹阻尼（1.0 -> 1.08 -> 0.97 -> 1.0）
    _bounceScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 0.97)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.97, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 30,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.52, 1.0),
      ),
    );

    // 透明度淡入：前 22% 时间快速显形
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.22, curve: Curves.easeIn),
      ),
    );

    // 旋转收紧：从 -22° 收束至经典印章微倾斜 -10°
    _rotationAnimation = Tween<double>(
      begin: -22.0 * math.pi / 180.0,
      end: -10.0 * math.pi / 180.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.52, curve: Curves.easeOutCubic),
      ),
    );

    // 冲击波光环：着陆瞬间（0.52）向外激荡扩散（0.8x -> 1.75x）
    _rippleScaleAnimation = Tween<double>(begin: 0.8, end: 1.75).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.52, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    // 冲击波光环透明度：0.52 时刻最亮，随后消散为 0
    _rippleOpacityAnimation = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.52, 0.95, curve: Curves.easeOutQuad),
      ),
    );

    _controller.addListener(_checkHitPoint);

    // 单元测试环境下直接置为完成态，避免 Timer 阻断测试 pumpAndSettle
    if (widget.animate && !PlatformUtils.isTesting) {
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    } else {
      _controller.value = 1.0;
    }
  }

  void _checkHitPoint() {
    // 当动画到达 0.52 临界点时，触发触底重击反馈（音效 + 震动）
    if (!_hasHit && _controller.value >= 0.52) {
      _hasHit = true;
      _triggerHitFeedback();
    }
  }

  void _triggerHitFeedback() {
    if (PlatformUtils.isTesting) {
      widget.onHit?.call();
      return;
    }

    // 1. 系统触觉震动重反馈
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // 2. 播放清脆厚实的印章敲击音效
    try {
      StudyAudioSessionController.instance.playStampSound();
    } catch (_) {}

    // 3. 外部联动回调
    widget.onHit?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stampColor = widget.color ?? const Color(0xFFEF4444);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (!widget.animate || PlatformUtils.isTesting) {
          return Transform.rotate(
            angle: -10.0 * math.pi / 180.0,
            child: _buildStampBody(stampColor),
          );
        }

        final isAfterHit = _controller.value >= 0.52;
        final currentScale = isAfterHit
            ? _bounceScaleAnimation.value
            : _dropScaleAnimation.value;

        return Opacity(
          opacity: _opacityAnimation.value,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 冲击着陆波（Ripple Shockwave）
              if (isAfterHit && _rippleOpacityAnimation.value > 0.01)
                Transform.scale(
                  scale: _rippleScaleAnimation.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: stampColor.withValues(alpha: _rippleOpacityAnimation.value),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),

              // 主体印章
              Transform.rotate(
                angle: _rotationAnimation.value,
                child: Transform.scale(
                  scale: currentScale,
                  child: _buildStampBody(stampColor),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 绘制精致双环朱砂印泥/钢印质感印章主体
  Widget _buildStampBody(Color color) {
    final size = widget.size;
    final primaryText = widget.isExtraRound ? '已加量' : '已打卡';
    final subText = widget.isExtraRound ? 'SUPER HERO' : 'VERIFIED';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(
          color: color,
          width: 2.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.04),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.8),
            width: 1.2,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: size * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 顶部星光与 PAOPAO 标示（FittedBox 自适应防溢出）
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, color: color, size: size * 0.10),
                  SizedBox(width: size * 0.015),
                  Text(
                    'PAOPAO',
                    style: TextStyle(
                      color: color,
                      fontSize: size * 0.085,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(width: size * 0.015),
                  Icon(Icons.star_rounded, color: color, size: size * 0.10),
                ],
              ),
            ),
            SizedBox(height: size * 0.035),

            // 中间核心大字（横向防溢出自适应，带上下精致细刻线）
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.03,
                vertical: size * 0.015,
              ),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: color.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  primaryText,
                  style: TextStyle(
                    color: color,
                    fontSize: size * 0.18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            SizedBox(height: size * 0.035),

            // 底部检验/通关英文小印
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                subText,
                style: TextStyle(
                  color: color.withValues(alpha: 0.9),
                  fontSize: size * 0.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
