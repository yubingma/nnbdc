import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nnbdc/util/game_sfx.dart';

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
  /// 900 → 620 → 430：配合加宽的桥面，让「每排五六只」放得下。
  static const double _charBase = 430;

  /// 与角色同比例缩放的特效尺寸倍率。角色变小了，坚果 / 星芒 / 眼泪 / 尘土也得跟着变小，
  /// 否则它们相对角色会显得越来越大——这类「绝对像素」的尺寸最容易漏。
  static const double _fx = _charBase / 900.0;

  // ------------------------------------------------------------ 行进轨道与透视
  // 横屏的纵向可视范围只有竖屏的一半多一点，轨道与透视缩放是整套重定的，
  // 不是把竖屏那几个数按比例缩一下。
  // 角色行进轨道。_groundDefeat 是「走到全程约一半、被打倒」的位置——
  // 需求是「小馋怪走到大约屏幕一半距离时已经被打倒 3 次」。
  // 进场起点与出场终点都必须在**画面之外**：可见的画布纵向范围约 y 106~1092
  // （手机横屏下 BoxFit.cover 会裁掉上下各约 9%）。原来起点 300、终点 200 都在画面内，
  // 于是小怪是「凭空出现」、逃跑完又跳回起点闪一下。改成屏外→屏外，接缝自然看不见。
  static const double _groundFar = 40;
  static const double _groundDefeat = 580;
  static const double _groundLift = 500;
  static const double _groundSettle = 575;
  static const double _groundFleeEnd = 30;
  // 透视斜坡的起点跟着下移到画面之外，远处的小怪才会「由小变大」地走进来；
  // 原来斜坡从 y=240 才开始，240 以上是一段恒定的 0.22，走进来时大小不变。
  static const double _scaleY0 = 60;
  static const double _scaleY1 = 920;
  static const double _scaleS0 = 0.15;
  static const double _scaleS1 = 0.52;

  /// 挤压拉伸的支点必须落在**脚底**上：脚踩死、身体自己起伏。
  /// 整体平移会让脚离地、整体旋转会让底座变跷跷板，两者都会被读成打滑。
  static const Alignment _feetPivot = Alignment(0, 0.9181);

  /// 我方小宠物当前该出哪一帧。投掷必须和坚果脱手对齐（_nutLaunch），
  /// 早了自己先动、晚了坚果凭空出现。
  static const List<String> _allyPoses = ['ally_stand', 'ally_windup', 'ally_throw'];

  // ------------------------------------------------------ 怪群与宠物队
  //
  // 十几只小怪跑的是**同一条时间线**，只是各自错开相位——所以「一排接一排」与「混乱」
  // 都只是相位与横向偏移的差别，不必为每只再写一套逻辑。与 Python 侧 MONSTERS/ALLIES 一致。
  //
  // 每只小怪：(相位偏移比例, 横向偏移（占该处桥面半宽的比例）, 深度抖动(px), 尺寸抖动)
  // 深度抖动给得很大（±150）：只给小抖动的话，十几只全挤在桥的上半段，
  // 桥头与怪群之间空出一大片，「压过来」的势头就没了。
  static const List<List<double>> _monsters = [
    [0.00, -0.62, -60, 1.00], [0.05, 0.10, 130, 0.94], [0.09, 0.58, -100, 1.05],
    [0.16, -0.30, 70, 0.97], [0.21, 0.44, -140, 1.02], [0.26, -0.72, 30, 0.92],
    [0.33, 0.22, 100, 1.06], [0.38, -0.48, -80, 0.95], [0.44, 0.66, 150, 1.01],
    [0.52, -0.12, -120, 0.98], [0.58, -0.66, 90, 1.04], [0.63, 0.36, -40, 0.93],
    [0.71, -0.36, 120, 1.00], [0.77, 0.54, -110, 0.96], [0.84, -0.06, 50, 1.03],
    [0.91, 0.28, -90, 0.99],
  ];

  /// 我方小队：编成前后两排，整体可以左右移动（由左下/右下两个按钮控制）。
  /// 每项：(相对小队中心的横向偏移（占视口宽）, 深度偏移(px), 尺寸抖动)
  /// 后排更远、更高、略小；前排更近、更低、略大——这样两排才看得出纵深。
  static const List<List<List<double>>> _allyRows = [
    [[-0.034, -58, 0.97], [0.034, -50, 1.03]],                    // 后排 2 只
    [[-0.055, 20, 1.04], [0.000, 28, 0.98], [0.055, 14, 1.06]],    // 前排 3 只
  ];

  /// 小队中心能移到的最大偏移（占视口宽的比例）。
  /// 0.24 的来历：小队所在深度上桥面横向约占 17.8%~82.2%，而小队本身约 ±9% 宽，
  /// 所以中心最多挪到 74%/26% —— 再往外就从桥边掉下去了（第一版给了 0.34，会露半边）。
  static const double _squadLimit = 0.24;

  /// 小队移动速度（占视口宽的比例 / 秒），**恒定**。
  /// 0.40 约等于 1.2 秒横穿整条可移动范围（0.55 时用户反馈稍快）。
  ///
  /// 摇杆只当**方向开关**用：过了死区就按这个速度走，与推杆量无关。
  /// 第一版做成「推得越远越快」的模拟量，用户明确不要，改成恒定速度。
  static const double _squadSpeed = 0.40;

  /// 左下角摇杆的尺寸（逻辑像素）。底盘固定不动，只有中间的杆会跟手。
  static const double _stickBase = 138;
  static const double _stickKnob = 58;
  /// 杆能推到的最大半径（归一化到 1 就是推到底）。
  static const double _stickRadius = 46;

  /// 谁能被打到：只有「最前排」的小怪。后排被前排挡着，打不到。
  /// 判定用深度抖动 —— 它本来就是「比平均更靠前/更靠后」的意思，正好当排次用。
  static const double _frontRowDj = 0.0;

  /// 小队全部成员：(画布横向x, 脚底行, 身高, 第几排)。整体跟着 [squadX] 左右平移。
  static List<({double x, double ground, double h, int row})> _squadMembers(double squadX) {
    final out = <({double x, double ground, double h, int row})>[];
    for (int ri = 0; ri < _allyRows.length; ri++) {
      for (final a in _allyRows[ri]) {
        final double gy = _allyGround + a[1];
        out.add((
          x: _canvasW / 2 + _canvasW * (squadX + a[0]),
          ground: gy,
          h: _charBase * _scaleAtGround(gy) * _allyRatio * a[2],
          row: ri,
        ));
      }
    }
    return out;
  }

  /// 某一深度处桥面的半宽（画布像素）。小怪的横向偏移是「该处桥面半宽的比例」，
  /// 乘它才不会站到水里去；深处窄、近处宽，本身就是透视的一部分。
  static double _bridgeHalf(double y) {
    final double k = (y / _canvasH).clamp(0.0, 1.0);
    return _canvasW * _lerp(0.10, 0.38, k);
  }

  /// 某只小怪在「它自己的时间」tt 上的状态。
  static ({double gy, bool approaching, bool walking, double sqX, double sqY, double rot, double shake})
      _unitState(double tt, {bool front = true}) {
    final double gy;
    if (tt < _tImpact) {
      gy = _track(tt, [(0, _groundFar), (_tHit3, _groundDefeat)]);
    } else if (tt < _tFlee) {
      gy = _track(tt, [
        (_tHit3, _groundDefeat),
        (_tHit3 + .10, _groundLift),
        (_tHit3 + .34, _groundSettle - 8),
        (_tCry, _groundSettle),
        (_tFlee, _groundSettle),
      ]);
    } else {
      gy = _track(tt, [(_tFlee, _groundSettle), (_tTotal, _groundFleeEnd)]);
    }

    final bool approaching = tt < _tImpact;
    final bool walking = tt >= _tFlee;
    double turnSq = 1.0;
    if (tt >= _tFlee && tt < _tFlee + _turn * 1.6) {
      final double k = (tt - _tFlee) / (_turn * 1.6);
      turnSq = math.max(0.52, math.cos(k * math.pi).abs());
    }
    double sqX = 1, sqY = 1, rot = 0;
    // 后排打不到：没有挨打的挤压回弹，也不会哭（否则会出现「没被打中却在哭」的矛盾）
    for (int i = 0; front && i < _hits.length; i++) {
      final double hit = _hits[i];
      if (tt < hit || tt >= hit + 0.75) continue;
      final double k = (tt - hit) / 0.75;
      final double e = _easeOutElastic(k, amp: 0.55, period: 0.36);
      final double amp = i == _hits.length - 1 ? 1.0 : 0.45;
      sqY *= _lerp(1.0, 0.80, e * (1 - k) * 1.35 * amp);
      sqX *= _lerp(1.0, 1.16, e * (1 - k) * 1.35 * amp);
      rot += math.sin(k * math.pi * 3) * 5 * (1 - k) * amp;
    }
    if (approaching) {
      final double bob = -_bobSquash * math.cos(2 * math.pi * _walkHz * 2 * tt);
      sqY *= 1 + bob;
      sqX *= 1 - bob * 0.55;
    }
    if (walking) {
      rot += _leanFlee * math.sin(2 * math.pi * (_walkHz * 2.0) * tt);
    }
    sqX *= turnSq;
    final double shake = (front && tt >= _tCry && tt < _tFlee)
        ? math.sin(tt * math.pi * 2 * 19) * 3.2
        : 0;
    return (gy: gy, approaching: approaching, walking: walking,
        sqX: sqX, sqY: sqY, rot: rot, shake: shake);
  }

  /// 某只小宠物这一刻出哪一帧。它负责哪几次投掷由投掷表决定；
  /// 一律用「环形距离」判断，否则跨循环边界的那几次会漏掉抬手动作。
  static String _allyPoseFor(double t, List<({double gh, int mi, int hj, int ai})> events, int ai) {
    for (final e in events) {
      if (e.ai != ai) continue;
      final double launch = (e.gh - _nutFlight) % _cycle;
      if ((t - (launch - _allyWindupLead)) % _cycle < _allyWindupLead) return 'ally_windup';
      if ((t - launch) % _cycle < _allyThrowHold) return 'ally_throw';
    }
    return 'ally_stand';
  }

  /// 把整个场景里所有「该出声的时刻」摊平成一张表。
  ///
  /// 和投掷表同一个套路：每只小怪跑同一条时间线、只是相位不同，
  /// 所以每个事件的全域时刻 = 相位 + 该事件在自己时间线上的时刻（对循环取模）。
  /// 排序之后，动画每推进一帧就只需要看「这一帧跨过了哪几个事件」。
  static List<({double time, SfxKind kind, int mi})> _sfxSchedule() {
    final out = <({double time, SfxKind kind, int mi})>[];
    for (int i = 0; i < _monsters.length; i++) {
      final double base = _monsters[i][0] * _cycle;
      for (final double h in _hits) {
        out.add((time: (base + h) % _cycle, kind: SfxKind.hit, mi: i));
        out.add((time: (base + h - _nutFlight) % _cycle, kind: SfxKind.throwWhoosh, mi: i));
      }
      out.add((time: (base + _tCry) % _cycle, kind: SfxKind.cry, mi: i));
      // 逃跑的脚步声：整段逃跑里稀疏地铺几下，靠 GameSfx 去重收敛成一层窸窣声
      for (int k = 0; k < 9; k++) {
        out.add((time: (base + _tFlee + k * 0.26) % _cycle, kind: SfxKind.step, mi: i));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// 把「最前排小怪的三次命中」摊平成一张投掷表。
  ///
  /// 与小怪各自为战的版本有两点区别，都是需求带来的：
  ///   1. **只有最前排的小怪**会被打到——后排被前排挡着；
  ///   2. 每次命中挑「**同列最近**」的那只小宠物来投，而不是轮流派。
  ///      这样弹道才是朝正前方（屏幕上方）出去的，而不是四散乱飞；
  ///      也正好对应「投掷武器的范围在队形正上方」。
  static List<({double gh, int mi, int hj, int ai})> _nutSchedule() {
    final members = _squadMembers(0);
    final events = <({double gh, int mi, int hj, int ai})>[];
    for (int i = 0; i < _monsters.length; i++) {
      final double dj = _monsters[i][2];
      if (dj <= _frontRowDj) continue;
      for (int j = 0; j < _hits.length; j++) {
        final stHit = _unitState(_hits[j]);
        final double gyHit = stHit.gy + dj;
        final double tx = _canvasW / 2 + _monsters[i][1] * _bridgeHalf(gyHit);
        int ai = 0;
        double best = double.infinity;
        for (int k = 0; k < members.length; k++) {
          final double d = (members[k].x - tx).abs();
          if (d < best) {
            best = d;
            ai = k;
          }
        }
        events.add((gh: (_monsters[i][0] * _cycle + _hits[j]) % _cycle, mi: i, hj: j, ai: ai));
      }
    }
    events.sort((a, b) => a.gh.compareTo(b.gh));
    return events;
  }

  static const double _allyGround = 950;    // 脚底所在的行（不贴画布最底：App 侧背景走
                                            // BoxFit.cover，在比 16:9 更宽的屏幕上会裁掉上下约 9%）
  static const double _allyRatio = 0.55;    // 相对同位置小馋怪的大小（原 0.85，用户要求再小一圈）
  static const double _allyWindupLead = 0.30;  // 抬手提前量
  static const double _allyThrowHold = 0.24;   // 挥出姿势保持
  static const double _nutFlight = 0.42;       // 坚果飞行时间

  static const List<double> _hits = [1.00, 1.80, 2.60];
  static const double _tHit3 = 2.60;
  static const double _tImpact = _tHit3;   // 第三下即打倒
  static const double _tCry = 3.15;
  static const double _tFlee = 3.95;
  static const double _tTotal = 6.80;
  static const double _cycle = _tTotal;   // 一只小怪的完整循环＝整个循环的时长
  static const double _turn = 0.30;

  // ------------------------------------------------------------ 运动参数
  /// 每秒完成的走路循环数；一个循环 = 2 步。这是步频的唯一旋钮。
  static const double _walkHz = 1.05;
  static const double _bobSquash = 0.030;
  static const double _leanFlee = 3.5;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_tTotal * 1000).round()),
  );

  bool _preloaded = false;

  // ---- 小队左右移动：左下角摇杆控制
  double _squadX = 0.0;        // 当前小队中心（占视口宽的比例），平滑趋近 _squadTarget
  double _squadTarget = 0.0;
  /// 摇杆的**方向意图**：-1 往左、0 不动、+1 往右。
  ///
  /// 它由「手指这一帧往哪边滑」决定（看 delta 的正负），**不是**手指相对底盘中心的位置。
  /// 第一版用的是后者，于是想换向必须先把手指拖回圆心另一侧——
  /// 那 46px 的空程就是用户感觉到的「迟钝」。看滑动方向就没有这段空程。
  int _stickDir = 0;

  /// 轮盘里那根杆的**视觉**位置（-1~+1），只跟手，不参与操控判断。
  double _stickKnobX = 0.0;
  int _moveClockMs = 0;

  /// 每帧推进小队位置：摇杆只给方向，速度恒定，方向来自「手往哪边滑」。
  ///
  /// 两个「不做」都是踩出来的：
  ///   * **不做「推得越远越快」**——用户明确要恒定速度；
  ///   * **不做插值缓动**——第一版写成 `_squadX += (_squadTarget - _squadX) * dt/90`，
  ///     想避免画面一跳一跳，但那正是用户感觉到的「迟钝、像有惯性」。
  ///     摇杆要的就是直接跟手，位置直接等于积分结果。
  void _advanceSquad() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int dtMs = _moveClockMs == 0 ? 0 : now - _moveClockMs;
    _moveClockMs = now;
    // 掉帧或切后台回来时 dt 会很大，直接跳过这一帧，别让队伍瞬移
    if (dtMs <= 0 || dtMs > 200) return;
    if (_stickDir != 0) {
      _squadTarget = (_squadTarget + _stickDir * _squadSpeed * dtMs / 1000)
          .clamp(-_squadLimit, _squadLimit);
    }
    _squadX = _squadTarget;    // 直接跟手，没有惯性
  }

  /// 杆的视觉位置：跟手，限制在半径内。
  void _moveStickKnob(Offset local) {
    final double v = ((local.dx - _stickBase / 2) / _stickRadius).clamp(-1.0, 1.0);
    if (v != _stickKnobX) setState(() => _stickKnobX = v);
  }

  /// 方向只看「手往哪边滑」。用每帧位移而不是相对圆心的位置，
  /// 所以手指一往回滑立刻换向，没有需要越过圆心的空程。
  /// 阈值 0.8 逻辑像素：滤掉手指静止时的抖动，又不影响慢速拖动。
  void _updateStickDir(Offset delta) {
    if (delta.dx.abs() < 0.8) return;
    final int dir = delta.dx.isNegative ? -1 : 1;
    if (dir != _stickDir) setState(() => _stickDir = dir);
  }

  /// 左下角的移动摇杆（王者荣耀那种）：底盘固定，中间的杆跟手，松手回中。
  ///
  /// 右下角**故意留空**——将来放道具栏。
  Widget _joystick() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        _moveStickKnob(e.localPosition);   // 按下不改方向：没滑动就不该起步
      },
      onPointerMove: (PointerMoveEvent e) {
        _moveStickKnob(e.localPosition);
        _updateStickDir(e.delta);
      },
      onPointerUp: (_) => setState(() {
        _stickDir = 0;
        _stickKnobX = 0;
      }),
      onPointerCancel: (_) => setState(() {
        _stickDir = 0;
        _stickKnobX = 0;
      }),
      child: SizedBox(
        width: _stickBase,
        height: _stickBase,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 底盘
            Container(
              width: _stickBase,
              height: _stickBase,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1C2230).withValues(alpha: 0.42),
                border: Border.all(color: Colors.white.withValues(alpha: 0.40), width: 1.8),
              ),
            ),
            // 中间那根杆：按推杆量偏移，最多到 _stickRadius
            Transform.translate(
              offset: Offset(_stickKnobX * _stickRadius, 0),
              child: Container(
                width: _stickKnob,
                height: _stickKnob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.0),
                ),
                child: const Icon(Icons.swap_horiz, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 音效事件的触发靠「这一帧跨过了哪几个事件」来判断，所以要记住上一帧的时刻。
  static final List<({double time, SfxKind kind, int mi})> _sfxEvents = _sfxSchedule();
  double? _sfxPrevT;

  /// 某只小怪在全域时刻 [time] 的远近程度（0 = 最远、1 = 最近），用于音效音量。
  static double _nearnessOf(int mi, double time) {
    final double tt = (time - _monsters[mi][0] * _cycle) % _cycle;
    final double gy = _unitState(tt).gy + _monsters[mi][2];
    // 脚步最远处约 y=40、最近处约 y=730（含深度抖动上限），据此归一
    return ((gy - 40) / 690).clamp(0.0, 1.0);
  }

  /// 每帧推进时把跨过的事件播出来。
  void _fireSfx(double prev, double now) {
    for (final e in _sfxEvents) {
      // 循环会在 t 从 6.8 跳回 0 时把区间折断，两端都要算上
      final bool crossed = now >= prev
          ? (e.time > prev && e.time <= now)
          : (e.time > prev || e.time <= now);
      if (!crossed) continue;
      GameSfx.instance.play(e.kind, nearness: _nearnessOf(e.mi, e.time));
    }
  }

  @override
  void initState() {
    super.initState();
    // 第一帧只用来记住起点，不触发音效——否则进页面会一次性爆出一串声音
    _clock.addListener(() {
      final double now = _clock.value * _tTotal;
      final double? prev = _sfxPrevT;
      _sfxPrevT = now;
      if (prev != null) _fireSfx(prev, now);
      _advanceSquad();
    });
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
    // 音效播放器也一起预加载。不预加载的话第一次命中要等解码，那一下就没了。
    unawaited(GameSfx.instance.prewarm());
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
  List<_PoseLayer> _posesAt(double t, {bool front = true}) {
    if (!front) {
      // 后排没被打到：正面走到头，直接转身退回去，不瘪嘴也不哭
      return [_walkPose(t >= _tFlee ? _walkBack : _walkFront, t, _walkHz)];
    }
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

            // 把「一个角色摆在画布某处」抽出来：画布坐标 → 屏幕，并算出图片该画多大。
            // 图片里角色只占 _refH，画布还留了边，所以要再乘一次比例。
            ({double cx, double imgH, double imgW, double top}) place(
                double xCanvas, double groundCanvas, double heightCanvas) {
              final double h = heightCanvas * cover * (_imgH / _refH);
              return (
                cx: toScreenX(xCanvas),
                imgH: h,
                imgW: h * (_imgW / _imgH),
                top: toScreenY(groundCanvas) - h * (_imgFeetY / _imgH),
              );
            }

            // 落地影：程序单独画在地面上，不跟着角色缩放变形。长宽比与柔度照 Python 侧对齐
            // （宽 = 角色高×0.62、高 = 宽×0.20、中心落在脚底那条线上），否则会读成一根黑杠。
            Widget groundShadow(double cx, double feetY, double imgH) => Positioned(
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
                      borderRadius:
                          BorderRadius.all(Radius.elliptical(imgH * 0.28, imgH * 0.0575)),
                    ),
                  ),
                );

            // 注意：Positioned 必须是 Stack 的直接子节点，不能再包一层 Opacity
            // （实测会抛 Incorrect use of ParentDataWidget），所以透明度放在 Positioned 内部。
            Widget unitImage(({double cx, double imgH, double imgW, double top}) pl,
                    String asset, double sqX, double sqY, double rot,
                    [double opacity = 1.0]) =>
                Positioned(
                  left: pl.cx - pl.imgW / 2,
                  top: pl.top,
                  width: pl.imgW,
                  height: pl.imgH,
                  child: Transform(
                    alignment: _feetPivot,
                    transform: Matrix4.identity()
                      ..rotateZ(rot * math.pi / 180)
                      ..scaleByDouble(sqX, sqY, 1, 1),
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Image.asset('$_dir$asset.png',
                          fit: BoxFit.fill, filterQuality: FilterQuality.high),
                    ),
                  ),
                );

            final children = <Widget>[
              Positioned.fill(
                child: Image.asset(_bg, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              ),
            ];

            // ---- 怪群：一排接一排地压上来。每只跑同一条时间线，只是相位错开。
            for (final m in _monsters) {
              final double tt = (t - m[0] * _cycle) % _cycle;
              final st = _unitState(tt);
              final double gy = st.gy + m[2];
              final double x = _canvasW / 2 + m[1] * _bridgeHalf(gy);
              final double hCanvas = _charBase * _scaleAtGround(gy) * m[3];
              final pl = place(x + st.shake, gy, hCanvas);
              children.add(groundShadow(pl.cx, toScreenY(gy), pl.imgH));
              for (final _PoseLayer pose in _posesAt(tt)) {
                if (pose.opacity <= 0.001) continue;
                children.add(unitImage(pl, pose.asset, st.sqX, st.sqY, st.rot, pose.opacity));
              }
            }

            // ---- 我方小队：前后两排，整体随 _squadX 左右移动
            final events = _nutSchedule();
            final squad = _MonsterSpriteState._squadMembers(_squadX);
            for (int ai = 0; ai < squad.length; ai++) {
              final m2 = squad[ai];
              final double bob = -0.022 * math.cos(2 * math.pi * 0.9 * t + ai * 1.3);
              final pl = place(m2.x, m2.ground, m2.h);
              children.add(groundShadow(pl.cx, toScreenY(m2.ground), pl.imgH));
              children.add(unitImage(pl, _allyPoseFor(t, events, ai),
                  1 - bob * 0.55, 1 + bob, 0));
            }

            children.add(Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MonsterFxPainter(
                      t: t, cover: cover, offX: offX, offY: offY, squadX: _squadX),
                ),
              ),
            ));

            // 左下角摇杆控制小队左右移动；右下角留空，将来放道具
            children.add(Positioned(left: 22, bottom: 16, child: _joystick()));

            return Stack(clipBehavior: Clip.none, children: children);
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
    required this.squadX,
  });

  final double t;
  final double cover;
  final double offX;
  final double offY;

  /// 小队当前中心（占视口宽的比例）——投掷起点要跟着队伍走。
  final double squadX;

  double _x(double canvasX) => offX + canvasX * cover;

  double _y(double canvasY) => offY + canvasY * cover;

  @override
  void paint(Canvas canvas, Size size) {
    // ---- 坚果：按投掷表，从负责那只小宠物手上飞向「命中那一刻」那只小怪的身体位置。
    // 终点取命中时刻而不是当前位置，否则坚果会追着跑、永远差一截。
    for (final e in _MonsterSpriteState._nutSchedule()) {
      final double launch = (e.gh - _MonsterSpriteState._nutFlight) % _MonsterSpriteState._cycle;
      final double d = (t - launch) % _MonsterSpriteState._cycle;
      if (d >= _MonsterSpriteState._nutFlight) continue;
      final double k = d / _MonsterSpriteState._nutFlight;
      final m = _MonsterSpriteState._monsters[e.mi];
      final stHit = _MonsterSpriteState._unitState(_MonsterSpriteState._hits[e.hj]);
      final double gyHit = stHit.gy + m[2];
      final double tx = _x(_MonsterSpriteState._canvasW / 2 +
          m[1] * _MonsterSpriteState._bridgeHalf(gyHit));
      final double ty = _y(gyHit -
          _MonsterSpriteState._charBase * _MonsterSpriteState._scaleAtGround(gyHit) * m[3] * 0.45);
      final m2 = _MonsterSpriteState._squadMembers(squadX)[e.ai];
      final double hx = _x(m2.x + m2.h * 0.30);
      final double hy = _y(m2.ground - m2.h * 0.62);
      final double nx = hx + (tx - hx) * k;
      final double ny = hy + (ty - hy) * k - size.height * 0.13 * math.sin(math.pi * k);
      for (int jj = 0; jj < 3; jj++) {
        _nut(canvas, nx + jj * 26 * _MonsterSpriteState._fx * cover,
            ny + jj * 20 * _MonsterSpriteState._fx * cover,
            k * 900 + jj * 40, (17 - jj * 3) * _MonsterSpriteState._fx * cover);
      }
      _nut(canvas, nx, ny, k * 900, 20 * _MonsterSpriteState._fx * cover);
    }

    // ---- 逐只小怪：星芒 / 眼泪 / 尘土 / 逃跑速度线
    for (final m in _MonsterSpriteState._monsters) {
      final double tt = (t - m[0] * _MonsterSpriteState._cycle) % _MonsterSpriteState._cycle;
      final st = _MonsterSpriteState._unitState(tt);
      final double gy = st.gy + m[2];
      final double h = _MonsterSpriteState._charBase * _MonsterSpriteState._scaleAtGround(gy) * m[3];
      final double mx = _x(_MonsterSpriteState._canvasW / 2 +
          m[1] * _MonsterSpriteState._bridgeHalf(gy) + st.shake);
      final double feet = _y(gy);

      final bool front = m[2] > _MonsterSpriteState._frontRowDj;
      for (int hi = 0; front && hi < _MonsterSpriteState._hits.length; hi++) {
        final double fi = tt - _MonsterSpriteState._hits[hi];
        if (fi <= 0 || fi >= 0.42) continue;
        // 前两下的小星芒缩到六成，第三下（打倒）才是满的
        _star(canvas, mx, feet - h * 0.55 * cover, fi / 0.42,
            (hi == _MonsterSpriteState._hits.length - 1 ? 1.0 : 0.6) * _MonsterSpriteState._fx);
      }

      // 飙泪：向两旁喷出去的弹道。
      //
      // 时间线上原来只哭到 T_FLEE+0.3，现在一路飙到逃跑途中——转身跑远还拖着
      // 一条泪迹，喜感主要来自这里。
      //
      // 关键一：每颗泪珠按**它出生那一刻小怪的位置**算，而不是按小怪当前位置。
      // 按当前位置画的话泪珠会黏在脸上跟着跑；按出生位置画，跑动时泪珠会留在身后，
      // 自然拉成一条轨迹。unitState() 是纯函数，所以这件事可以直接算，不需要粒子表。
      //
      // 关键二：**背对镜头时泪珠要被脑袋挡住**。眼睛长在脑袋正面，转身之后眼睛在
      // 背面，无条件画在最上层会看起来像「从后脑勺飙出来的眼泪」。所以背对时把
      // 落在脑袋轮廓椭圆内的泪珠跳过——它一飞出轮廓，自然就出现了。
      final bool back = tt >= _MonsterSpriteState._tFlee + _MonsterSpriteState._turn;
      final double headCy = feet - h * 0.50 * cover;
      final double headRx = h * 0.42 * cover;
      final double headRy = h * 0.52 * cover;
      for (int i = 0; i < 30; i++) {
        final double birth = _MonsterSpriteState._tCry + i * 0.09;
        if (birth > tt) break;
        final double age = tt - birth;
        if (age > 0.65) continue;
        final stB = _MonsterSpriteState._unitState(birth);
        final double gyB = stB.gy + m[2];
        final double hB =
            _MonsterSpriteState._charBase * _MonsterSpriteState._scaleAtGround(gyB) * m[3];
        // 起点在**眼角外侧**：两眼各从自己那一侧出发，否则会像从两眼之间冒出来
        final double side = i.isEven ? -1 : 1;
        final double ex = _x(_MonsterSpriteState._canvasW / 2 +
                m[1] * _MonsterSpriteState._bridgeHalf(gyB) +
                stB.shake +
                side * hB * 0.10);
        final double ey = _y(gyB - hB * 0.62);
        // 横向每秒 1.9 个身高（从眼角算最远约 1.33 个身高）——必须明显超出脑袋轮廓
        // （横向半径 0.42 身高），否则背对镜头时整段都被挡住、等于看不见。
        // 纵向先上抛、再被"重力"拉回来。
        final double tx = ex + side * hB * 1.9 * age * cover;
        final double ty = ey - hB * (1.2 * age - 3.2 * age * age) * cover;
        if (back) {
          final double u = (tx - mx) / headRx;
          final double v = (ty - headCy) / headRy;
          if (u * u + v * v < 1.0) continue; // 还在脑袋后面，看不见
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(tx, ty),
            width: 25 * _MonsterSpriteState._fx * cover,
            height: 35 * _MonsterSpriteState._fx * cover,
          ),
          Paint()..color = const Color(0xFF9FD8F5).withValues(alpha: 0.9 * (1 - age / 0.7)),
        );
      }
      if (st.approaching || st.walking) {
        for (int i = 0; i < 2; i++) {
          final double ph = (tt * 2.2 + i * 0.5) % 1.0;
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(mx + (i * 2 - 1) * h * 0.22 * cover, feet),
              width: (46 - ph * 22) * _MonsterSpriteState._fx * cover / 3,
              height: (20 - ph * 9) * _MonsterSpriteState._fx * cover / 3,
            ),
            Paint()..color = const Color(0xFFDED4C4).withValues(alpha: 0.5 * (1 - ph)),
          );
        }
      }
      if (tt >= _MonsterSpriteState._tFlee + _MonsterSpriteState._turn && tt < _MonsterSpriteState._tTotal) {
        final Paint line = Paint()
          ..color = Colors.white.withValues(alpha: 0.22 * (1 - (tt - _MonsterSpriteState._tFlee) / 2.4))
          ..strokeWidth = 4 * _MonsterSpriteState._fx * cover
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final double ph = (tt * 3.0 + i * 0.33) % 1.0;
          final double x = mx + (i - 1) * 80 * _MonsterSpriteState._fx * cover;
          final double y0 = _y(gy - h * 1.2) + ph * 180 * _MonsterSpriteState._fx * cover;
          canvas.drawLine(Offset(x, y0), Offset(x, y0 + 150 * _MonsterSpriteState._fx * cover), line);
        }
      }
    }
  }

  /// 命中的星芒。与 Python 侧 fx_impact 同构——16 个顶点交替半径的星形（外圈 r、内圈 0.42r），
  /// 叠一层向中心缩到 0.62 的白色内星，再套一个圆环描边，最后整体做模糊。
  void _star(Canvas canvas, double cx, double cy, double k, double scale) {
    final double r = _MonsterSpriteState._lerp(
            26, 235, _MonsterSpriteState._easeOutBack(math.min(1.0, k * 1.4))) *
        cover *
        scale;
    final double a = 1.0 - k;
    final Path star = Path();
    for (int i = 0; i < 16; i++) {
      final double ang = math.pi * 2 * i / 16;
      final double rr = r * (i.isOdd ? 0.42 : 1.0);
      final Offset o = Offset(cx + math.cos(ang) * rr, cy + math.sin(ang) * rr);
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
    canvas.translate(cx, cy);
    canvas.scale(0.62);
    canvas.translate(-cx, -cy);
    canvas.drawPath(
        star,
        Paint()
          ..color = const Color(0xFFFFFDF5).withValues(alpha: 0.94 * a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * cover));
    canvas.restore();
    canvas.drawCircle(
        Offset(cx, cy),
        r * 0.95,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, 10 * a) * cover
          ..color = Colors.white.withValues(alpha: 0.67 * a));
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


  @override
  bool shouldRepaint(_MonsterFxPainter old) => old.t != t;
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
