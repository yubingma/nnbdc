import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 虚拟摇杆（王者荣耀那种手感）。
///
/// 状态机：闲置 → 按下 → 拖动（**杆偏离圆心的位移**决定方向与推杆量）→ 抬起归零。
///
/// 必须守住的两条：
/// 1. 方向只能由「杆相对圆心的位移」决定。**不能**用「手指这一帧移动了多少」——
///    触屏在手指静止时不发移动事件，那样按住不动会被判成停下，表现为「摇杆时不时自己停住」。
/// 2. 不要加缓动/惯性。摇杆是方向与力度的直接表达，插值会让它像拖着一根橡皮筋。
class GameJoystick extends StatefulWidget {
  const GameJoystick({
    super.key,
    required this.radius,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.center,
    this.deadZone = 12,
    this.color = Colors.white,
  });

  /// 底盘半径（逻辑像素）。整块触摸区是它的 2.4 倍见方。
  final double radius;

  /// 死区（逻辑像素）：杆偏得比它近就算没推。
  final double deadZone;

  /// 方向（单位向量，屏幕坐标、y 向下为正）与推杆量（0~1）。
  final void Function(Offset direction, double magnitude) onChanged;

  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  /// 画在底盘中心的图标（例如「投」字），不参与触摸。
  final Widget? center;

  final Color color;

  @override
  State<GameJoystick> createState() => _GameJoystickState();
}

class _GameJoystickState extends State<GameJoystick> {
  /// 正在操作这块摇杆的手指；null = 闲置。同一时刻只认一根手指。
  int? _pointer;

  /// 杆相对圆心的像素位移，已夹在底盘半径内。
  Offset _knob = Offset.zero;

  Offset get _center => Offset(widget.radius * 1.2, widget.radius * 1.2);

  @override
  Widget build(BuildContext context) {
    final double side = widget.radius * 2.4;
    return SizedBox(
      width: side,
      height: side,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _JoystickPainter(
                  center: _center,
                  radius: widget.radius,
                  knob: _knob,
                  active: _pointer != null,
                  color: widget.color,
                ),
              ),
            ),
            if (widget.center != null)
              Positioned.fill(
                child: IgnorePointer(child: Center(child: widget.center)),
              ),
          ],
        ),
      ),
    );
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    widget.onStart?.call();
    _apply(e.localPosition);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _apply(e.localPosition);
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _release();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _release();
  }

  void _apply(Offset local) {
    final Offset delta = local - _center;
    final double dist = delta.distance;
    if (dist < widget.deadZone) {
      _setKnob(Offset.zero);
      widget.onChanged(Offset.zero, 0);
      return;
    }
    final double magnitude = math.min(1.0, dist / widget.radius);
    _setKnob(delta / dist * math.min(dist, widget.radius));
    widget.onChanged(delta / dist, magnitude);
  }

  void _release() {
    _pointer = null;
    _setKnob(Offset.zero);
    widget.onChanged(Offset.zero, 0);
    widget.onEnd?.call();
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
    final double face = active ? 0.30 : 0.16;
    final double edge = active ? 0.70 : 0.38;

    canvas.drawCircle(
        center, radius, Paint()..color = color.withValues(alpha: face));
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: edge));

    // 四向小刻度：让「推到底」有个参照，也提示这是方向杆而不是按钮
    for (int i = 0; i < 4; i++) {
      final double ang = math.pi / 2 * i;
      canvas.drawCircle(
        center + Offset(math.cos(ang), math.sin(ang)) * radius * 0.82,
        2.4,
        Paint()..color = color.withValues(alpha: edge),
      );
    }

    final Offset head = center + knob;
    canvas.drawCircle(head, radius * 0.46,
        Paint()..color = color.withValues(alpha: active ? 0.62 : 0.30));
    canvas.drawCircle(
        head,
        radius * 0.46,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: active ? 0.92 : 0.55));
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knob != knob || old.active != active || old.radius != radius;
}
