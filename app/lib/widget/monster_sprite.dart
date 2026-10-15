import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 小馋怪的走路/被打哭/逃跑动画。
///
/// 这是 `tools/sprite_anim/render_anim.py`（Python 逐帧渲染版）在 App 里的等价实现，
/// 两边的时间线、位移轨道、挤压拉伸幅度必须**逐项对齐**——任何一侧调整都要同步另一侧。
/// 经验与本条管线的判据见 `.agents/skills/sprite-walk-animation/SKILL.md`。
///
/// 素材已由 `tools/sprite_anim/pack_app_assets.py` 预处理过：剥了烘焙阴影、扶正了身体、
/// 烘死了镜像，并归一化到同一块画布（脚底对齐在同一条线上）。所以这里只需要一个
/// 缩放系数，不需要再做任何几何修正。
class MonsterSprite extends StatefulWidget {
  const MonsterSprite({super.key, this.loop = true});

  /// 是否循环播放整段动画。
  final bool loop;

  @override
  State<MonsterSprite> createState() => _MonsterSpriteState();
}

/// 一个动画相位：显示哪张图、以多大不透明度。
/// 走路用定格切换（单一姿势、不透明度 1）；只有「走近→瘪嘴」「瘪嘴→哭」
/// 这类换姿势的瞬间才做短暂交叉淡入。
typedef _PoseLayer = ({String asset, double opacity});

class _MonsterSpriteState extends State<MonsterSprite>
    with SingleTickerProviderStateMixin {
  // ------------------------------------------------------------ 素材
  static const String _dir = 'assets/images/monster/';
  static const String _bg = '${_dir}bg_bridge.jpg';

  /// 正面走路循环：8 帧 = 2 步。顺序即相位顺序，与 Python 侧 CURATED_FRONT 一致。
  static const List<String> _walkFront = [
    'front_stand',
    'front_leg_r_mid',
    'front_leg_r_high',
    'front_leg_r_mid',
    'front_stand',
    'front_leg_l_mid',
    'front_leg_l_high',
    'front_leg_l_mid',
  ];

  /// 背面（逃跑）循环，与 Python 侧 CURATED_BACK 一致。
  static const List<String> _walkBack = [
    'back_stand_a',
    'back_leg_mid',
    'back_leg_high',
    'back_leg_mid',
    'back_stand_b',
    'back_leg_mid_mirror',
    'back_leg_high_mirror',
    'back_leg_mid_mirror',
  ];

  // ------------------------------------------------------------ 画布与素材几何
  // 与 Python 的横屏视口（1920×1080）同坐标，两边必须一起改；
  // 导出画布的尺寸与脚底位置来自 pack_app_assets.py。
  static const double _canvasW = 1920;
  static const double _canvasH = 1080;
  static const double _imgW = 528;
  static const double _imgH = 537;
  static const double _imgFeetY = 517;
  static const double _refH = 480;

  // ------------------------------------------------------------ 行进轨道与透视
  // 横屏的纵向可视范围只有竖屏的一半多一点，轨道与透视缩放是整套重定的，
  // 不是把竖屏那几个数按比例缩一下。
  static const double _groundFar = 300;
  static const double _groundNear = 860;
  static const double _groundBounce = 740;
  static const double _groundSettle = 845;
  static const double _scaleY0 = 240;
  static const double _scaleY1 = 920;
  static const double _scaleS0 = 0.22;
  static const double _scaleS1 = 0.52;

  /// 挤压拉伸的支点必须落在**脚底**上：脚踩死、身体自己起伏。
  /// 整体平移会让脚离地、整体旋转会让底座变跷跷板，两者都会被读成打滑。
  static const Alignment _feetPivot = Alignment(0, 0.9257);

  // ------------------------------------------------------------ 时间线（秒）
  static const double _tTotal = 8.80;
  static const double _tImpact = 3.40;
  static const double _tCry = 3.95;
  static const double _tFlee = 6.20;
  static const double _turn = 0.30;

  // ------------------------------------------------------------ 运动参数
  /// 每秒完成的走路循环数；一个循环 = 2 步。这是步频的唯一旋钮。
  static const double _walkHz = 1.05;
  static const double _bobSquash = 0.030;
  static const double _swayFlee = 0.008;
  static const double _leanFlee = 3.5;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_tTotal * 1000).round()),
  );

  bool _preloaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.loop) {
      _clock.repeat();
    } else {
      _clock.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloaded) return;
    _preloaded = true;
    // 进页面就把**全部**帧预解码。
    //
    // 不做这一步的后果是实测出来的：Flutter 只在 Image 组件第一次被构建时才去解码，
    // 于是第一次切到瘪嘴、第一次切到哭脸、第一次转到背面时，那一帧还没解码完，
    // 角色会整个消失一下（截图里 t=3.55 / t=4.4 / t=7.4 就是这么空掉的）。
    // 这些姿势要等到 3.4 秒后才用得上，而 14 张小图预解码只要几毫秒，所以进页面
    // 提前点火就足够，不必卡住动画等它完成。
    final frames = <String>{..._walkFront, ..._walkBack, 'pout', 'cry'};
    for (final name in frames) {
      precacheImage(AssetImage('$_dir$name.png'), context);
    }
    precacheImage(const AssetImage(_bg), context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 工具函数（与 Python 逐项对应）
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _smoothstep(double x) {
    final double t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _track(double t, List<(double, double)> keys) {
    if (t <= keys.first.$1) return keys.first.$2;
    if (t >= keys.last.$1) return keys.last.$2;
    for (int i = 0; i + 1 < keys.length; i++) {
      final (double t0, double v0) = keys[i];
      final (double t1, double v1) = keys[i + 1];
      if (t >= t0 && t <= t1) {
        return _lerp(v0, v1, (t - t0) / math.max(1e-6, t1 - t0));
      }
    }
    return keys.last.$2;
  }

  static double _easeOutElastic(double x, {double amp = 0.5, double period = 0.32}) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return 1 + amp * math.pow(2, -10 * x) * math.sin((x - period / 4) * (2 * math.pi) / period);
  }

  /// 透视：越靠下（离镜头越近）越大。与 Python 的 scale_at_ground 一致。
  static double _scaleAtGround(double y) {
    final double k = ((y - _scaleY0) / (_scaleY1 - _scaleY0)).clamp(0.0, 1.0);
    return _lerp(_scaleS0, _scaleS1, k);
  }

  static _PoseLayer _walkPose(List<String> frames, double t, double hz) {
    // 纯定格切换。绝不能在相邻走路帧之间做交叉淡入：alpha 合成是 source-over，
    // 下层那一帧会以残余不透明度整只透出来，看起来就是凭空多出一个身体的重影。
    final int i = ((t * hz * frames.length) % frames.length).floor();
    return (asset: frames[i], opacity: 1);
  }

  /// 当前这一时刻要画哪些层。换姿势时返回两层做短暂交叉淡入，走路时只返回一层。
  List<_PoseLayer> _posesAt(double t) {
    if (t < _tImpact) {
      return [_walkPose(_walkFront, t, _walkHz)];
    }
    if (t < _tImpact + 0.18) {
      final double k = _smoothstep((t - _tImpact) / 0.18);
      return [
        _walkPose(_walkFront, t, _walkHz).let((p) => (asset: p.asset, opacity: 1 - k)),
        (asset: 'pout', opacity: k),
      ];
    }
    if (t < _tCry) return [(asset: 'pout', opacity: 1)];
    if (t < _tCry + 0.22) {
      final double k = _smoothstep((t - _tCry) / 0.22);
      return [(asset: 'pout', opacity: 1 - k), (asset: 'cry', opacity: k)];
    }
    if (t < _tFlee) return [(asset: 'cry', opacity: 1)];
    if (t < _tFlee + _turn) {
      final double k = _smoothstep((t - _tFlee) / _turn);
      return [
        (asset: 'cry', opacity: 1 - k),
        _walkPose(_walkBack, t, _walkHz * 1.9).let((p) => (asset: p.asset, opacity: k)),
      ];
    }
    return [_walkPose(_walkBack, t, _walkHz * 1.9)];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final double t = _clock.value * _tTotal;
        return LayoutBuilder(
          builder: (context, c) {
            // 画布(1080×1920) → 屏幕的映射必须和背景的 BoxFit.cover **完全一致**：
            // 取较大的那一维做统一缩放，多出来的部分居中裁掉。若这里另算一套
            // （例如 x 用 maxWidth/1080、y 用 maxHeight/1920），角色会既被拉伸变形、
            // 又和桥面透视对不上——实测屏幕是 390×844 而画布是 9:16，差得很远。
            final double cover =
                math.max(c.maxWidth / _canvasW, c.maxHeight / _canvasH);
            final double offX = (c.maxWidth - _canvasW * cover) / 2;
            final double offY = (c.maxHeight - _canvasH * cover) / 2;
            double toScreenX(double x) => offX + x * cover;
            double toScreenY(double y) => offY + y * cover;

            // ---- 地面位置（画布坐标 → 屏幕）
            final double gyCanvas;
            if (t < _tImpact) {
              gyCanvas = _track(t, [(0, _groundFar), (_tImpact, _groundNear)]);
            } else if (t < _tFlee) {
              gyCanvas = _track(t, [
                (_tImpact, _groundNear),
                (_tImpact + .10, _groundBounce),
                (_tImpact + .34, _groundSettle - 8),
                (_tCry, _groundSettle),
                (_tFlee, _groundSettle),
              ]);
            } else {
              gyCanvas = _track(t, [(_tFlee, _groundSettle), (_tTotal, _groundFar)]);
            }

            // ---- 挤压拉伸与摇摆
            double sqX = 1, sqY = 1, rot = 0, swayFrac = 0;
            if (t < _tImpact) {
              // 起伏做在「以脚底为支点的挤压拉伸」上：脚不动，身体自己起伏
              final double bob = -_bobSquash * math.cos(2 * math.pi * _walkHz * 2 * t);
              sqY *= 1 + bob;
              sqX *= 1 - bob * 0.55;
            }
            if (t >= _tImpact && t < _tImpact + 0.75) {
              final double k = (t - _tImpact) / 0.75;
              final double e = _easeOutElastic(k, amp: 0.55, period: 0.36);
              sqY = _lerp(1.0, 0.80, e * (1 - k) * 1.35);
              sqX = _lerp(1.0, 1.16, e * (1 - k) * 1.35);
              rot = math.sin(k * math.pi * 3) * 5 * (1 - k);
            }
            if (t >= _tFlee) {
              final double ph = 2 * math.pi * (_walkHz * 1.9) * t;
              rot += _leanFlee * math.sin(ph);
              swayFrac = _swayFlee * math.sin(ph);
            }
            // 转身：横向压扁再弹回，把「转过去」这个动作补出来
            if (t >= _tFlee && t < _tFlee + _turn * 1.6) {
              final double k = (t - _tFlee) / (_turn * 1.6);
              sqX *= math.max(0.52, math.cos(k * math.pi).abs());
            }
            // 哭的时候左右抖
            final double shakeCanvas =
                (t >= _tCry && t < _tFlee) ? math.sin(t * math.pi * 2 * 19) * 3.2 : 0;

            // 角色在画布上的高度 → 屏幕高度；再换算成「图片要画多大」
            // （图片里角色只占 _refH，画布还留了边）。
            final double charCanvasH = 900 * _scaleAtGround(gyCanvas);
            final double imgH = charCanvasH * cover * (_imgH / _refH);
            final double imgW = imgH * (_imgW / _imgH);
            final double cx = toScreenX(_canvasW / 2 + shakeCanvas + swayFrac * charCanvasH);
            final double feetY = toScreenY(gyCanvas);
            final double top = feetY - imgH * (_imgFeetY / _imgH);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.asset(_bg, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                ),
                // 落地影：程序单独画在地面上，不跟着角色缩放变形。
                // 长宽比与柔度照 Python 侧对齐（宽 = 角色高×0.62、高 = 宽×0.20、
                // 中心落在脚底那条线上），否则会读成脚下一根发黑的道杠。
                Positioned(
                  left: cx - imgH * 0.28,
                  top: feetY - imgH * 0.0575,
                  width: imgH * 0.56,
                  height: imgH * 0.115,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5C483A).withValues(alpha: 0.30),
                          blurRadius: imgH * 0.10,
                        ),
                      ],
                      borderRadius: BorderRadius.all(Radius.elliptical(imgH * 0.28, imgH * 0.0575)),
                    ),
                  ),
                ),
                for (final _PoseLayer p in _posesAt(t))
                  Positioned(
                    left: cx - imgW / 2,
                    top: top,
                    width: imgW,
                    height: imgH,
                    child: Opacity(
                      opacity: p.opacity.clamp(0.0, 1.0),
                      child: Transform(
                        alignment: _feetPivot,
                        transform: Matrix4.identity()
                          ..rotateZ(rot * math.pi / 180)
                          ..scaleByDouble(sqX, sqY, 1, 1),
                        child: Image.asset('$_dir${p.asset}.png',
                            fit: BoxFit.fill, filterQuality: FilterQuality.high),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MonsterFxPainter(
                        t: t,
                        cover: cover,
                        offX: offX,
                        offY: offY,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 被打中的星芒、眼泪、脚下尘土、逃跑时的速度线。
///
/// 坐标一律走与角色相同的画布→屏幕映射，否则特效会和角色错位。
class _MonsterFxPainter extends CustomPainter {
  _MonsterFxPainter({
    required this.t,
    required this.cover,
    required this.offX,
    required this.offY,
  });

  final double t;
  final double cover;
  final double offX;
  final double offY;

  double _x(double canvasX) => offX + canvasX * cover;

  double _y(double canvasY) => offY + canvasY * cover;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = _x(_MonsterSpriteState._canvasW / 2);
    final double gy = _groundCanvasY(t);
    final double groundY = _y(gy);
    // 角色大约半身高处，特效都挂在这个高度附近
    final double bodyY = groundY - 520 * _scaleAt(t) * cover;

    // 飞向小馋怪的果子：1.45s 起抛出、3.40s 命中，是「被打中」的因。
    // 少了它，后面那下挤压和星芒就成了没来由的。
    if (t >= 1.45 && t < _MonsterSpriteState._tImpact) {
      final double k = (t - 1.45) / (_MonsterSpriteState._tImpact - 1.45);
      final double nx = cx + size.width * 0.13 * (1 - k);
      final double ny = groundY - 900 * _scaleAt(t) * 0.30 * cover
          - size.height * 0.375 * (1 - k) + 30 * cover;
      for (int j = 0; j < 3; j++) {
        _nut(canvas, nx + j * 26 * cover, ny + j * 20 * cover,
            k * 900 + j * 40, (17 - j * 3) * cover);
      }
      _nut(canvas, nx, ny, k * 900, 20 * cover);
    }

    // 被打中的星芒
    final double fi = t - _MonsterSpriteState._tImpact;
    if (fi >= 0 && fi < 0.55) {
      final double k = fi / 0.55;
      final double r = (40 + 150 * _MonsterSpriteState._easeOutElastic(k, amp: 0.55)) * cover;
      final Paint p = Paint()
        ..color = Colors.white.withValues(alpha: (1 - k) * 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11 * cover
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 6; i++) {
        final double a = i * math.pi / 3 + k * 0.5;
        canvas.drawLine(
          Offset(cx + math.cos(a) * r * 0.35, bodyY + math.sin(a) * r * 0.35),
          Offset(cx + math.cos(a) * r, bodyY + math.sin(a) * r),
          p,
        );
      }
    }

    // 哭：往两侧飞的小泪珠
    if (t >= _MonsterSpriteState._tCry && t < _MonsterSpriteState._tFlee + 0.3) {
      final double base = t - _MonsterSpriteState._tCry;
      final Paint tear = Paint()..color = const Color(0xFF9FD8F5).withValues(alpha: 0.9);
      for (int i = 0; i < 10; i++) {
        final double born = i * 0.14;
        final double age = base - born;
        if (age < 0 || age > 0.8) continue;
        final double side = i.isEven ? -1 : 1;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              cx + side * 62 * cover * (0.4 + age * 2.2),
              bodyY + age * 300 * cover - 40 * cover,
            ),
            width: 20 * cover,
            height: 28 * cover,
          ),
          tear,
        );
      }
    }

    // 脚下尘土
    if (t < _MonsterSpriteState._tImpact || t >= _MonsterSpriteState._tFlee) {
      for (int i = 0; i < 6; i++) {
        final double ph = (t * 2.1 + i * 0.37) % 1.0;
        final double side = i.isEven ? -1 : 1;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + side * (26 + ph * 60) * cover, groundY - ph * 26 * cover),
            width: (46 - ph * 22) * cover,
            height: (20 - ph * 9) * cover,
          ),
          Paint()..color = const Color(0xFFDED4C4).withValues(alpha: 0.5 * (1 - ph)),
        );
      }
    }

    // 逃跑时的速度线
    if (t >= _MonsterSpriteState._tFlee + _MonsterSpriteState._turn) {
      final Paint line = Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 4 * cover
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 3; i++) {
        final double ph = (t * 3.0 + i * 0.33) % 1.0;
        final double x = cx + (i - 1) * 80 * cover;
        final double y0 = _y(gy - 520) + ph * 180 * cover;
        canvas.drawLine(Offset(x, y0), Offset(x, y0 + 150 * cover), line);
      }
    }
  }


  /// 一颗果子（椭圆 + 一道弧线），按角度旋转后贴上去。
  void _nut(Canvas canvas, double x, double y, double deg, double r) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(deg * math.pi / 180);
    final Paint fill = Paint()..color = const Color(0xFFC48C54);
    final Paint stroke = Paint()
      ..color = const Color(0xFF7E542E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.18);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.64), fill);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.64), stroke);
    canvas.drawArc(
        Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 1.2),
        200 * math.pi / 180, 140 * math.pi / 180, false,
        Paint()
          ..color = const Color(0xFF7E542E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.14));
    canvas.restore();
  }

  /// 角色当前在画布上的纵向位置，与 build 里的 gyCanvas 轨道一致。
  static double _groundCanvasY(double t) {
    if (t < _MonsterSpriteState._tImpact) {
      return _MonsterSpriteState._track(
          t, [(0, _MonsterSpriteState._groundFar), (_MonsterSpriteState._tImpact, _MonsterSpriteState._groundNear)]);
    }
    if (t < _MonsterSpriteState._tFlee) return _MonsterSpriteState._groundSettle;
    return _MonsterSpriteState._track(t, [
      (_MonsterSpriteState._tFlee, _MonsterSpriteState._groundSettle),
      (_MonsterSpriteState._tTotal, _MonsterSpriteState._groundFar),
    ]);
  }

  static double _scaleAt(double t) => _MonsterSpriteState._scaleAtGround(_groundCanvasY(t));

  @override
  bool shouldRepaint(_MonsterFxPainter old) => old.t != t;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
