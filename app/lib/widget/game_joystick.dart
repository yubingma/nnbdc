import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 虚拟摇杆（照王者荣耀的浮动底盘 + `flutter_joystick` 的全局坐标差值）。
///
/// 两个坑都踩过，这里一次说清：
///
/// 1. **手势必须用 [Listener] 的 pointer 事件，不能用 `GestureDetector` 的 pan**。
///    pan 的 `onPanDown` 在「轻点、没拖动」时也会触发，但那种手势达不到 pan 的 slop，
///    抬起时 `onPanEnd` 不会来——用来判断「有没有手指按着」的标志就会永远挂着，
///    表现就是「滑动两下之后摇杆彻底没反应」。pointer 的 DOWN / UP / CANCEL 是一定成对的。
/// 2. **偏移必须用 `PointerEvent.position`（全局）的差值算**，不要用 `localPosition`：
///    全局差值与组件怎么嵌套、屏幕怎么旋转无关。`flutter_joystick` 的
///    `CircleStickOffsetCalculator` 就是 `current.globalPosition − start.globalPosition`。
///    `localPosition` 只用来决定「底盘画在哪」。
///
/// 状态：闲置 → 按下（底盘中心 = 手指落点）→ 拖动（方向 = 手指相对落点）→ 松手归零。
/// **按下不产生方向**，杆只在手指真的移动之后才偏。
class GameJoystick extends StatefulWidget {
  const GameJoystick({
    super.key,
    required this.radius,
    required this.onChanged,
    this.onEnd,
    this.color = Colors.white,
  });

  /// 底盘半径（逻辑像素）。杆头半径是它的 0.32，杆头拖到最远正好贴着盘边。
  final double radius;

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

  /// 本次按下的底盘中心（本组件坐标，只用于绘制）。null = 闲置。
  Offset? _center;

  /// 按下那一刻的全局坐标。拖动偏移一律用「当前全局坐标 − 它」来算。
  Offset? _downGlobal;

  /// 杆相对底盘中心的位移，已夹在最大拖动半径内。
  Offset _knob = Offset.zero;

  /// 杆能拖到的最大半径 = 底盘半径 − 杆头半径（0.32r）。
  double get _maxTravel => widget.radius * 0.68;

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
      _downGlobal = e.position;
      _knob = Offset.zero;
    });
    // 按下这一帧不产生方向：手指只是搭在上面。
    widget.onChanged(Offset.zero, 0);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final Offset down = _downGlobal!;
    // 关键：全局坐标差值。横屏、嵌套布局、组件被 transform 时都不会错位。
    final Offset delta = e.position - down;
    final double dist = delta.distance;
    if (dist < 1) return;
    final double magnitude = math.min(1.0, dist / _maxTravel);
    setState(() => _knob = delta / dist * math.min(dist, _maxTravel));
    widget.onChanged(delta / dist, magnitude);
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() {
      _center = null;
      _downGlobal = null;
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
        ..color = color.withValues(alpha: edge),
    );

    // 四向小刻度：推到底有个参照，也给「这是方向杆」一个视觉暗示
    for (int i = 0; i < 4; i++) {
      final double ang = math.pi / 2 * i;
      canvas.drawCircle(
        center + Offset(math.cos(ang), math.sin(ang)) * radius * 0.84,
        2.0,
        Paint()..color = color.withValues(alpha: edge * 0.9),
      );
    }

    final double headR = radius * 0.32;
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
