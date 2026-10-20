import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 虚拟摇杆（照王者荣耀那套「浮动底盘」做的）。
///
/// 状态机：闲置 → 按下（**底盘中心 = 手指按下点**）→ 准备（移动超过 [startThreshold]
/// 才转拖动）→ 拖动（方向 = 手指相对底盘中心）→ 抬起（回中、归零）。
///
/// 三条必须守住的：
/// 1. **底盘中心跟着按下点走**，不是钉死在左下角。固定底盘时，玩家按在盘子边上，
///    按下那一刻就算出一个满力方向、杆头还会从中心跳到手指上——真机手感就是「一碰就走」。
/// 2. 方向只由「手指相对中心的位移」决定，不看「这一帧滑了多少」：触屏在手指静止时
///    不发移动事件，用增量判定会把「按住不动」误判成停下。
/// 3. 不加缓动/惯性，松手即停。
class GameJoystick extends StatefulWidget {
  const GameJoystick({
    super.key,
    required this.radius,
    required this.onChanged,
    this.onEnd,
    this.startThreshold = 10,
    this.color = Colors.white,
  });

  /// 底盘半径（逻辑像素）。杆头半径是它的 0.38，杆头拖到最远也只会贴着盘边。
  final double radius;

  /// 按下后至少移动这么远才进入拖动（逻辑像素）。低于它的抖动不产生方向。
  final double startThreshold;

  /// 方向（单位向量，屏幕坐标、y 向下为正）与推杆量（0~1）。
  final void Function(Offset direction, double magnitude) onChanged;

  final VoidCallback? onEnd;

  final Color color;

  @override
  State<GameJoystick> createState() => _GameJoystickState();
}

class _GameJoystickState extends State<GameJoystick> {
  /// 正在操作这块摇杆的手指；null = 闲置。同一时刻只认一根手指。
  int? _pointer;

  /// 本次按下的底盘中心（本组件坐标）。null = 闲置。
  Offset? _center;

  /// 杆相对底盘中心的位移，已夹在最大拖动半径内。
  Offset _knob = Offset.zero;

  /// 是否已越过准备阈值、进入拖动。
  bool _dragging = false;

  /// 杆能拖到的最大半径 = 底盘半径 − 杆头半径（0.38r），杆头才不会甩出盘子。
  double get _maxTravel => widget.radius * 0.62;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onDown(e, size),
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: CustomPaint(
            painter: _JoystickPainter(
              center: _center ?? _homeCenter(size),
              radius: widget.radius,
              knob: _knob,
              active: _center != null,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }

  /// 没按的时候，底盘停在这个区域的左下角，告诉玩家「这里可以按」。
  Offset _homeCenter(Size size) {
    final double r = widget.radius;
    return Offset(r + 16, size.height - r - 16);
  }

  void _onDown(PointerDownEvent e, Size size) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    setState(() {
      _center = _clampCenter(e.localPosition, size);
      _knob = Offset.zero;
      _dragging = false;
    });
    // 按下这一帧不产生方向：手指可能只是搭在上面。
    widget.onChanged(Offset.zero, 0);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final Offset center = _center!;
    final Offset delta = e.localPosition - center;
    final double dist = delta.distance;
    if (!_dragging) {
      if (dist < widget.startThreshold) return;
      _dragging = true;
    }
    final double magnitude = math.min(1.0, dist / _maxTravel);
    _setKnob(delta / dist * math.min(dist, _maxTravel));
    widget.onChanged(delta / dist, magnitude);
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _dragging = false;
    setState(() {
      _center = null;
      _knob = Offset.zero;
    });
    widget.onChanged(Offset.zero, 0);
    widget.onEnd?.call();
  }

  /// 底盘中心不能贴边，否则半个盘子会被屏幕裁掉。
  Offset _clampCenter(Offset p, Size size) {
    final double r = widget.radius;
    const double margin = 4;
    final double minX = r + margin;
    final double maxX = math.max(minX, size.width - r - margin);
    final double minY = r + margin;
    final double maxY = math.max(minY, size.height - r - margin);
    return Offset(p.dx.clamp(minX, maxX), p.dy.clamp(minY, maxY));
  }

  void _setKnob(Offset value) {
    if (_knob == value) return;
    setState(() => _knob = value);
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.center,
    required this.radius,
    required this.knob,
    required this.active,
    required this.color,
  });

  final Offset center;
  final double radius;
  final Offset knob;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double face = active ? 0.26 : 0.12;
    final double edge = active ? 0.62 : 0.32;

    canvas.drawCircle(
        center, radius, Paint()..color = color.withValues(alpha: face));
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2.0 : 1.4
          ..color = color.withValues(alpha: edge));

    // 四向小刻度：推到底有个参照，也给「这是方向杆」一个视觉暗示
    for (int i = 0; i < 4; i++) {
      final double ang = math.pi / 2 * i;
      canvas.drawCircle(
        center + Offset(math.cos(ang), math.sin(ang)) * radius * 0.84,
        2.0,
        Paint()..color = color.withValues(alpha: edge * 0.9),
      );
    }

    final double headR = radius * 0.38;
    final Offset head = center + knob;
    canvas.drawCircle(head, headR,
        Paint()..color = color.withValues(alpha: active ? 0.58 : 0.26));
    canvas.drawCircle(
        head,
        headR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: active ? 0.88 : 0.48));
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knob != knob || old.active != active || old.center != center;
}
