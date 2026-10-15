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
  static const String _dir = 'assets/images/bridge/';
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
  static const double _imgFeetY = 515;
  static const double _refH = 480;

  /// 角色的基准身高（画布像素）：实际身高 = 本值 × 透视缩放。与 Python 侧 CHAR_BASE 一致。
  /// 2026-10-15 由 900 调到 620：配合加宽的桥面，让桥上放得下更多单位。
  static const double _charBase = 620;

  /// 与角色同比例缩放的特效尺寸倍率。角色变小了，坚果 / 星芒 / 眼泪 / 尘土也得跟着变小，
  /// 否则它们相对角色会显得越来越大——这类「绝对像素」的尺寸最容易漏。
  static const double _fx = _charBase / 900.0;

  // ------------------------------------------------------------ 行进轨道与透视
  // 横屏的纵向可视范围只有竖屏的一半多一点，轨道与透视缩放是整套重定的，
  // 不是把竖屏那几个数按比例缩一下。
  // 角色行进轨道。_groundDefeat 是「走到全程约一半、被打倒」的位置——
  // 需求是「小馋怪走到大约屏幕一半距离时已经被打倒 3 次」。
  static const double _groundFar = 300;
  static const double _groundDefeat = 580;
  static const double _groundLift = 500;
  static const double _groundSettle = 575;
  static const double _groundFleeEnd = 200;
  static const double _scaleY0 = 240;
  static const double _scaleY1 = 920;
  static const double _scaleS0 = 0.22;
  static const double _scaleS1 = 0.52;

  /// 挤压拉伸的支点必须落在**脚底**上：脚踩死、身体自己起伏。
  /// 整体平移会让脚离地、整体旋转会让底座变跷跷板，两者都会被读成打滑。
  static const Alignment _feetPivot = Alignment(0, 0.9181);

  /// 我方小宠物当前该出哪一帧。投掷必须和坚果脱手对齐（_nutLaunch），
  /// 早了自己先动、晚了坚果凭空出现。
  static const List<String> _allyPoses = ['ally_stand', 'ally_windup', 'ally_throw'];

  static String _allyPoseAt(double t) {
    for (final double launch in _nutLaunches) {
      if (t >= launch - _allyWindupLead && t < launch) return 'ally_windup';
      if (t >= launch && t < launch + _allyThrowHold) return 'ally_throw';
    }
    return 'ally_stand';
  }

  // ------------------------------------------- 我方小宠物（站在桥头、背对镜头、投掷坚果）
  // 与 Python 侧 render_anim.py 的同名常量逐项对齐。
  static const double _allyGround = 950;    // 脚底所在的行
  static const double _allyOffsetX = -0.12; // 横向位置：略偏桥面左侧，别挡住压过来的小馋怪
  static const double _allyRatio = 0.85;    // 相对同位置小馋怪的大小
  static const double _allyWindupLead = 0.30;  // 抬手提前量
  static const double _allyThrowHold = 0.24;   // 挥出姿势保持
  /// 三次脱手时刻，与三次命中一一对齐。
  static const List<double> _nutLaunches = [0.58, 1.38, 2.18];

  // ------------------------------------------------------------ 时间线（秒）
  // 三次命中都在「走到全程一半」之前发生：_tHit3 就是走到 _groundDefeat 的时刻。
  // 间距 0.8 秒，对应「投掷频率高一点」。
  static const List<double> _hits = [1.00, 1.80, 2.60];
  static const double _tHit3 = 2.60;
  static const double _tImpact = _tHit3;   // 第三下即打倒
  static const double _tCry = 3.15;
  static const double _tFlee = 4.60;
  static const double _tTotal = 6.80;
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
    final frames = <String>{..._walkFront, ..._walkBack, ..._allyPoses, 'pout', 'cry'};
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

  /// 先冲过头再回弹，用于星芒的爆开。与 Python 侧 ease_out_back 一致。
  static double _easeOutBack(double x, {double s = 1.7}) {
    final double t = x - 1;
    return t * t * ((s + 1) * t + s) + 1;
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
              gyCanvas = _track(t, [(0, _groundFar), (_tHit3, _groundDefeat)]);
            } else if (t < _tFlee) {
              gyCanvas = _track(t, [
                (_tHit3, _groundDefeat),
                (_tHit3 + .10, _groundLift),
                (_tHit3 + .34, _groundSettle - 8),
                (_tCry, _groundSettle),
                (_tFlee, _groundSettle),
              ]);
            } else {
              gyCanvas = _track(t, [(_tFlee, _groundSettle), (_tTotal, _groundFleeEnd)]);
            }

            // ---- 挤压拉伸与摇摆
            double sqX = 1, sqY = 1, rot = 0, swayFrac = 0;
            if (t < _tImpact) {
              // 起伏做在「以脚底为支点的挤压拉伸」上：脚不动，身体自己起伏
              final double bob = -_bobSquash * math.cos(2 * math.pi * _walkHz * 2 * t);
              sqY *= 1 + bob;
              sqX *= 1 - bob * 0.55;
            }
            // 三次命中都做挤压回弹：前两下只是被打退（幅度小），第三下才是打倒。
            // 不做的话三次命中在画面上读不出区别，只会看到坚果一颗颗飞过去。
            for (int i = 0; i < _hits.length; i++) {
              final double hit = _hits[i];
              if (t < hit || t >= hit + 0.75) continue;
              final double k = (t - hit) / 0.75;
              final double e = _easeOutElastic(k, amp: 0.55, period: 0.36);
              final double amp = i == _hits.length - 1 ? 1.0 : 0.45;
              sqY *= _lerp(1.0, 0.80, e * (1 - k) * 1.35 * amp);
              sqX *= _lerp(1.0, 1.16, e * (1 - k) * 1.35 * amp);
              rot += math.sin(k * math.pi * 3) * 5 * (1 - k) * amp;
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

            // 把「一个角色摆在画布某个位置」抽出来，小馋怪与我方小宠物共用同一套几何，
            // 免得两边各算一遍再对不上。
            ({double cx, double imgH, double imgW, double top}) place(
                double xCanvas, double groundCanvas, double scaleRatio) {
              final double canvasH = _charBase * _scaleAtGround(groundCanvas) * scaleRatio;
              final double h = canvasH * cover * (_imgH / _refH);
              return (
                cx: toScreenX(xCanvas),
                imgH: h,
                imgW: h * (_imgW / _imgH),
                top: toScreenY(groundCanvas) - h * (_imgFeetY / _imgH),
              );
            }

            // 我方小宠物：站在桥头、背对镜头。脚底、横向位置、大小都与 Python 侧一致。
            final p = place(_canvasW / 2 + _canvasW * _allyOffsetX, _allyGround, _allyRatio);
            final double allyFeetY = toScreenY(_allyGround);
            final double allyBob = -0.022 * math.cos(2 * math.pi * 0.9 * t);
            final String allyPose = _allyPoseAt(t);

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
                // 我方小宠物画在小馋怪之后：它离镜头最近，本来就该盖在上面。
                Positioned(
                  left: p.cx - p.imgH * 0.28,
                  top: allyFeetY - p.imgH * 0.0575,
                  width: p.imgH * 0.56,
                  height: p.imgH * 0.115,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5C483A).withValues(alpha: 0.30),
                          blurRadius: p.imgH * 0.10,
                        ),
                      ],
                      borderRadius: BorderRadius.all(Radius.elliptical(p.imgH * 0.28, p.imgH * 0.0575)),
                    ),
                  ),
                ),
                Positioned(
                  left: p.cx - p.imgW / 2,
                  top: p.top,
                  width: p.imgW,
                  height: p.imgH,
                  child: Transform(
                    alignment: _feetPivot,
                    transform: Matrix4.identity()
                      ..scaleByDouble(1 - allyBob * 0.55, 1 + allyBob, 1, 1),
                    child: Image.asset('$_dir$allyPose.png',
                        fit: BoxFit.fill, filterQuality: FilterQuality.high),
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
    final double bodyY =
        groundY - _MonsterSpriteState._charBase * 0.55 * _scaleAt(t) * cover;

    // 飞向小馋怪的果子：1.45s 起抛出、3.40s 命中，是「被打中」的因。
    // 少了它，后面那下挤压和星芒就成了没来由的。
    // 三次投掷的坚果，各自从我方小宠物的手飞向「命中那一刻」小馋怪的身体位置。
    // 终点取命中时刻而不是当前位置，否则坚果会追着跑、永远差一截。
    for (int i = 0; i < _MonsterSpriteState._hits.length; i++) {
      final double hit = _MonsterSpriteState._hits[i];
      final double launch = _MonsterSpriteState._nutLaunches[i];
      if (t < launch || t >= hit) continue;
      final double k = (t - launch) / (hit - launch);
      final double gAtHit = _MonsterSpriteState._track(
          hit, [(0, _MonsterSpriteState._groundFar), (_MonsterSpriteState._tHit3, _MonsterSpriteState._groundDefeat)]);
      final double allyH =
          _MonsterSpriteState._charBase *
              _MonsterSpriteState._scaleAtGround(_MonsterSpriteState._allyGround) *
              _MonsterSpriteState._allyRatio;
      final double hx = offX +
          (_MonsterSpriteState._canvasW / 2 +
                  _MonsterSpriteState._canvasW * _MonsterSpriteState._allyOffsetX +
                  allyH * 0.30) *
              cover;
      final double hy = offY + (_MonsterSpriteState._allyGround - allyH * 0.62) * cover;
      final double tx = cx;
      final double ty = offY +
          (gAtHit - _MonsterSpriteState._charBase * _MonsterSpriteState._scaleAtGround(gAtHit) * 0.45) *
              cover;
      final double nx = hx + (tx - hx) * k;
      final double ny =
          hy + (ty - hy) * k - size.height * 0.13 * math.sin(math.pi * k);   // 抛一条弧线
      for (int j = 0; j < 3; j++) {
        _nut(canvas, nx + j * 26 * _MonsterSpriteState._fx * cover,
            ny + j * 20 * _MonsterSpriteState._fx * cover,
            k * 900 + j * 40, (17 - j * 3) * _MonsterSpriteState._fx * cover);
      }
      _nut(canvas, nx, ny, k * 900, 20 * _MonsterSpriteState._fx * cover);
    }

    // 被打中的星芒：与 Python 侧 fx_impact 同构——16 个顶点交替半径的星形
    // （外圈 r、内圈 0.42r），叠一层向中心缩到 0.62 的白色内星，再套一个圆环描边，
    // 最后整体做模糊。画成六条细白线和视频里差得很远，所以照搬。
    for (int hi = 0; hi < _MonsterSpriteState._hits.length; hi++) {
      final double fi = t - _MonsterSpriteState._hits[hi];
      if (fi <= 0 || fi >= 0.42) continue;
      final double k = fi / 0.42;
      // 前两下的小星芒缩到六成，第三下（打倒）才是满的
      final double amp = hi == _MonsterSpriteState._hits.length - 1 ? 1.0 : 0.6;
      final double r = _MonsterSpriteState._lerp(
              26, 235, _MonsterSpriteState._easeOutBack(math.min(1.0, k * 1.4))) *
          cover *
          amp *
          _MonsterSpriteState._fx;
      final double a = 1.0 - k;
      final Path star = Path();
      for (int i = 0; i < 16; i++) {
        final double ang = math.pi * 2 * i / 16;
        final double rr = r * (i.isOdd ? 0.42 : 1.0);
        final Offset o = Offset(cx + math.cos(ang) * rr, bodyY + math.sin(ang) * rr);
        if (i == 0) {
          star.moveTo(o.dx, o.dy);
        } else {
          star.lineTo(o.dx, o.dy);
        }
      }
      star.close();
      canvas.drawPath(
          star,
          Paint()
            ..color = const Color(0xFFFFF0AA).withValues(alpha: 0.90 * a)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * cover));
      canvas.save();
      canvas.translate(cx, bodyY);
      canvas.scale(0.62);
      canvas.translate(-cx, -bodyY);
      canvas.drawPath(
          star,
          Paint()
            ..color = const Color(0xFFFFFDF5).withValues(alpha: 0.94 * a)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * cover));
      canvas.restore();
      canvas.drawCircle(
          Offset(cx, bodyY),
          r * 0.95,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, 10 * a) * cover
            ..color = Colors.white.withValues(alpha: 0.67 * a));
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
              cx + side * 62 * _MonsterSpriteState._fx * cover * (0.4 + age * 2.2),
              bodyY + age * 300 * _MonsterSpriteState._fx * cover - 40 * _MonsterSpriteState._fx * cover,
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
            width: (46 - ph * 22) * _MonsterSpriteState._fx * cover,
            height: (20 - ph * 9) * _MonsterSpriteState._fx * cover,
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
    if (t < _MonsterSpriteState._tHit3) {
      return _MonsterSpriteState._track(t, [
        (0, _MonsterSpriteState._groundFar),
        (_MonsterSpriteState._tHit3, _MonsterSpriteState._groundDefeat),
      ]);
    }
    if (t < _MonsterSpriteState._tFlee) return _MonsterSpriteState._groundSettle;
    return _MonsterSpriteState._track(t, [
      (_MonsterSpriteState._tFlee, _MonsterSpriteState._groundSettle),
      (_MonsterSpriteState._tTotal, _MonsterSpriteState._groundFleeEnd),
    ]);
  }

  static double _scaleAt(double t) => _MonsterSpriteState._scaleAtGround(_groundCanvasY(t));

  @override
  bool shouldRepaint(_MonsterFxPainter old) => old.t != t;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
