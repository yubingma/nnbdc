import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nnbdc/util/game_sfx.dart';
import 'package:nnbdc/widget/game_joystick.dart';

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
  /// 动画能用到的全部姿势资源（见 _MonsterSpriteState.poseVocabulary 的说明）。
  /// 挂在公开类上，测试才够得着。
  static List<String> get poseVocabulary => _MonsterSpriteState.poseVocabulary;

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
  /// 「瘪嘴（被打中）」与「哭」这两张是单帧，提成常量避免测试词表与代码漂移。
  static const String _pout = 'pout';
  static const String _cry = 'cry';

  /// 动画**能用到**的全部姿势资源（测试据此断言四种姿势齐全、且磁盘上没有孤儿文件）。
  ///
  /// 为什么要单独列一份：姿势现在由状态机决定——`pout` 只在挨打时出现、`cry` 要挨满 3 下、
  /// `back_` 只在逃跑时出现。测试若靠「渲染一小会儿看引用了谁」当判据，
  /// 这些状态在短时间内根本走不到，判据就失效了（这两条测试此前正是因此失败）。
  static const List<String> poseVocabulary = [
    ..._walkFront,
    ..._walkBack,
    'front_stand',
    'back_stand_a',
    'back_stand_b',
    _pout,
    _cry,
    ..._allyPoses,
  ];

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
  static const List<String> _allyPoses = [
    'ally_stand',
    'ally_windup',
    'ally_throw'
  ];

  // ------------------------------------------------------ 怪群与宠物队
  //
  // 十几只小怪跑的是**同一条时间线**，只是各自错开相位——所以「一排接一排」与「混乱」
  // 都只是相位与横向偏移的差别，不必为每只再写一套逻辑。与 Python 侧 MONSTERS/ALLIES 一致。
  //
  // 每只小怪：(相位偏移比例, 横向偏移（占该处桥面半宽的比例）, 深度抖动(px), 尺寸抖动)
  // 深度抖动给得很大（±150）：只给小抖动的话，十几只全挤在桥的上半段，
  // 桥头与怪群之间空出一大片，「压过来」的势头就没了。
  static const List<List<double>> _monsters = [
    [0.00, -0.62, -60, 1.00],
    [0.05, 0.10, 130, 0.94],
    [0.09, 0.58, -100, 1.05],
    [0.16, -0.30, 70, 0.97],
    [0.21, 0.44, -140, 1.02],
    [0.26, -0.72, 30, 0.92],
    [0.33, 0.22, 100, 1.06],
    [0.38, -0.48, -80, 0.95],
    [0.44, 0.66, 150, 1.01],
    [0.52, -0.12, -120, 0.98],
    [0.58, -0.66, 90, 1.04],
    [0.63, 0.36, -40, 0.93],
    [0.71, -0.36, 120, 1.00],
    [0.77, 0.54, -110, 0.96],
    [0.84, -0.06, 50, 1.03],
    [0.91, 0.28, -90, 0.99],
  ];

  /// 我方小队：编成前后两排，整体可以左右移动（由左下/右下两个按钮控制）。
  /// 每项：(相对小队中心的横向偏移（占视口宽）, 深度偏移(px), 尺寸抖动)
  /// 后排更远、更高、略小；前排更近、更低、略大——这样两排才看得出纵深。
  static const List<List<List<double>>> _allyRows = [
    [
      [-0.034, -58, 0.97],
      [0.034, -50, 1.03]
    ], // 后排 2 只
    [
      [-0.055, 20, 1.04],
      [0.000, 28, 0.98],
      [0.055, 14, 1.06]
    ], // 前排 3 只
  ];

  /// 小队中心能移到的最大偏移（占画布宽的比例）。
  ///
  /// 这个值同时决定「走位答题」能不能生效：单词靶在桥两侧 1.45 倍半宽处，弹丸朝正前方飞，
  /// 玩家必须把小队推到最边上、让弹丸在靶子那一行正好落到靶子上。推得太近（例如 0.24）
  /// 弹丸到靶子那一行时会差出两百多画布像素，永远打不中。
  static const double _squadLimit = 0.40;

  /// 推满杆的走位速度（画布像素/秒）。
  static const double _squadSpeed = 520;

  /// 纵向能走到的两端（画布像素，相对 _allyGround）。
  ///
  /// 近端 0 = 就站桥头；远端 −170 停在水果线之前——再往前队伍就踩到水果、
  /// 和压上来的小怪叠在一起了。纵向走位还有个暗收益：站得越靠前，桥面半宽越小，
  /// 弹丸到达靶子那一行时横向落点越靠外，更容易够到两侧的单词靶。
  static const double _squadDepthNear = 0;
  static const double _squadDepthFar = -170;

  /// 我方小宠物脚底所在的行（不贴画布最底：App 侧背景走 BoxFit.cover，
  /// 在比 16:9 更宽的屏幕上会上下各裁掉约 9%，贴底的话脚会被切掉）。
  static const double _allyGround = 950;

  /// 相对同位置小怪的大小（原 0.85，用户要求再小一圈）。
  static const double _allyRatio = 0.55;

  static const double _tTotal = 6.80;
  static const double _walkHz = 1.05;

  /// 小队全部成员：(画布横向x, 脚底行, 身高, 第几排)。
  /// 整队跟着 [squadX] 左右平移、跟着 [depthOffset] 前后挪（正 = 朝镜头走）。
  static List<({double x, double ground, double h, int row})> _squadMembers(
      double squadX, double depthOffset) {
    final out = <({double x, double ground, double h, int row})>[];
    for (int ri = 0; ri < _allyRows.length; ri++) {
      for (final a in _allyRows[ri]) {
        final double gy = _allyGround + depthOffset + a[1];
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

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_tTotal * 1000).round()),
  );

  bool _preloaded = false;

  // ---- 玩法模拟状态：小怪状态机 + 弹丸 + 命中星芒
  final List<_Mob> _mobs = [];
  final List<_Nut> _nuts = [];
  final List<_Star> _stars = [];
  // ---- 答题状态
  int _questionIndex = 0;
  bool _asking = false; // true = 正在提问（有倒计时）；false = 问歇
  double _askDeadline = 0; // 倒计时截止时刻
  final List<_WordTarget> _words = [];
  String? _flash; // 判定结果提示
  double _flashUntil = 0;

  /// 增益等级：答对 +1、答错 −1。持久累积，只在重开时归零。
  int _buffLevel = 0;
  final List<_Fruit> _fruits = [];
  bool _lost = false;
  double _shotT = 0;
  int _shotIdx = 0;
  int _simClockMs = 0;
  double _simTime = 0; // 模拟累计时间（姿势与出手必须共用它）
  List<double> _petLastFire = List<double>.filled(5, -99);

  void _resetSim() {
    _mobs.clear();
    for (final m in _monsters) {
      _mobs.add(_Mob(m[1], m[2], m[3], m[0] * _entrySpread));
    }
    _fruits
      ..clear()
      ..addAll(_fruitLanes.map(_Fruit.new));
    _lost = false;
    _questionIndex = 0;
    _asking = false;
    _askDeadline = 0;
    _words.clear();
    _flash = null;
    _buffLevel = 0;
    _nuts.clear();
    _stars.clear();
    _simTime = 0;
    _shotT = 0;
    _shotIdx = 0;
    _petLastFire = List<double>.filled(5, -99);
    _squadX = 0;
    _squadDepth = 0;
    _moveX = 0;
    _moveY = 0;
  }

  /// 结算一题：答对随机奖励、答错罚火力；随后空一段再出下一题。
  void _answer(bool correct) {
    _asking = false;
    _askDeadline = _simTime + _gapSeconds; // 空一段，避免一题接一题
    _words.clear();
    if (correct) {
      _buffLevel++;
      _flash = '答对了！火力 ×${_fireFactor().toStringAsFixed(2)}（等级 $_buffLevel）';
    } else {
      _buffLevel--;
      _flash = '答错了…火力 ×${_fireFactor().toStringAsFixed(2)}（等级 $_buffLevel）';
    }
    _flashUntil = _simTime + 1.6;
    _questionIndex++;
  }

  /// 开火间隔的倍率（<1 更快）：0.8^增益等级，夹在上下限之间。
  double _fireFactor() =>
      math.pow(_buffStep, _buffLevel).toDouble().clamp(_fireMin, _fireMax);

  static double _nearnessOfMob(_Mob m) =>
      ((m.ground - 40) / 690).clamp(0.0, 1.0);

  /// 弹丸竖直向前飞；撞到**最靠前且没在哭**的那只就停（不穿透）。
  void _tickSim() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int dtMs = _simClockMs == 0 ? 0 : now - _simClockMs;
    _simClockMs = now;
    if (dtMs <= 0 || dtMs > 200) return;
    final double dt = dtMs / 1000;
    _simTime += dt;

    _moveSquad(dt); // 左摇杆走位：按住持续走、松手停
    if (_lost) return; // 已经输了就不再开火
    _shotT += dt;
    final double interval = _shotInterval * _fireFactor();
    if (_shotT >= interval) {
      _shotT -= interval;
      final squad = _squadMembers(_squadX, _squadDepth);
      final int shooter = _shotIdx % squad.length;
      final s = squad[shooter];
      final double handX = s.x + s.h * _handOffsetX;
      final double handH = s.h * _handOffsetY; // 手在 ally_windup 里的实际高度
      _nuts.add(_Nut(
        s.ground, // 深度＝出手那一刻站的地面行
        handH, // 离地高度＝手的高度，飞行中不变
        (handX - _canvasW / 2) / _bridgeHalf(s.ground), // 横向比例，飞行中保持不变
        _scaleAtGround(s.ground),
      ));
      _petLastFire[shooter] = _simTime; // 记下这只的出手时刻，供姿势使用
      _shotIdx++;
      GameSfx.instance.play(SfxKind.throwWhoosh, nearness: 1.0);
    }

    _nuts.removeWhere((n) {
      n.depth -= _nutForward * dt; // 向前推进（画面里向上、朝消失点收拢）
      final double sy = n.screenY;
      _Mob? hit;
      for (final m in _mobs) {
        if (m.transparent) continue;
        if ((n.x - m.x).abs() > m.h * 0.46) continue;
        if (sy <= m.ground && sy >= m.ground - m.h) {
          if (hit == null || m.ground > hit.ground) hit = m;
        }
      }
      // 打中单词靶 = 作答（靶子在平台前方）
      for (final w in _words) {
        if ((n.x - w.x).abs() > 70) continue;
        if (sy <= _WordTarget.depth + 50 && sy >= _WordTarget.depth - 70) {
          _answer(w.correct);
          return true; // 弹丸命中即消失
        }
      }
      if (hit == null) return n.depth < 40;
      hit.hit();
      _stars.add(_Star(n.x, sy, hit.hits >= _hitsToCry));
      GameSfx.instance.play(SfxKind.hit, nearness: _nearnessOfMob(hit));
      if (hit.state == 'cry') {
        GameSfx.instance.play(SfxKind.cry, nearness: _nearnessOfMob(hit));
      }
      return true;
    });

    for (final m in _mobs) {
      m.step(dt, _fruits);
    }

    // ---- 出题循环：空一段 → 提问并倒计时 → 判定 → 再空一段
    if (!_asking) {
      if (_simTime >= _askDeadline) {
        // 这里 _askDeadline 当「下次出题时刻」用
        _asking = true;
        _askDeadline = _simTime + _askSeconds;
        final _Question q =
            _demoQuestions[_questionIndex % _demoQuestions.length];
        final bool rightCorrect = math.Random().nextBool();
        final double hw = _bridgeHalf(_wordDepth);
        _words
          ..clear()
          ..add(_WordTarget(rightCorrect ? q.wrongWord : q.word, !rightCorrect,
              _canvasW / 2 - _wordLane * hw))
          ..add(_WordTarget(rightCorrect ? q.word : q.wrongWord, rightCorrect,
              _canvasW / 2 + _wordLane * hw));
      }
    } else if (_simTime >= _askDeadline) {
      _answer(false); // 倒计时内没作答 = 答错
    }

    // 水果全被抢走 → 判负。这里只是把状态标出来，画面由 build 输出。
    if (!_lost && _fruits.every((f) => f.taken)) _lost = true;
    for (final st in _stars) {
      st.age += dt;
    }
    _stars.removeWhere((st) => st.age >= 0.42);
  }

  /// 第 ai 只小宠物这一刻出哪一帧。
  ///
  /// **必须用模拟时钟 `_simTime` 推，不能用动画时钟 t**：出手时刻与姿势若各用各的时钟，
  /// 相位就会错开——画面上会出现「宠物还站着，子弹已经从手里飞出去了」。
  String _allyPoseFromShot(int ai) {
    // ally_windup **只能有一个含义：手扬到最高点＝出手那一帧**。
    //
    // 这里原先还有一条「出手前 0.18 秒先摆出 windup 当预备动作」的分支，
    // 于是同一张图被赋予了「预备」和「出手」两个含义——
    // 玩家看到手先扬起来、过 0.18 秒子弹才出去，反馈就是「晚了」。
    // 去掉后：stand →（手到顶点＋子弹同帧出现）→ throw 收势 → stand。
    final double age = _simTime - _petLastFire[ai];
    if (age >= 0 && age < _windupHold) return 'ally_windup';
    if (age >= _windupHold && age < _windupHold + 0.22) return 'ally_throw';
    return 'ally_stand';
  }

  // ---- 小队走位：左下摇杆给出方向与推杆量，按住持续走、松手停
  double _squadX = 0.0; // 横向（占画布宽的比例）
  double _squadDepth = 0.0; // 纵向（画布像素，正 = 朝镜头走）
  double _moveX = 0.0, _moveY = 0.0; // 左摇杆：方向 × 推杆量（屏幕坐标）

  /// 每帧按摇杆推杆量积分，不做缓动：摇杆给的是方向和力度，不是目标位置。
  void _moveSquad(double dt) {
    if (_moveX == 0 && _moveY == 0) return;
    _squadX = (_squadX + _moveX * _squadSpeed / _canvasW * dt)
        .clamp(-_squadLimit, _squadLimit);
    _squadDepth = (_squadDepth + _moveY * _squadSpeed * dt)
        .clamp(_squadDepthFar, _squadDepthNear);
  }

  @override
  void initState() {
    super.initState();
    // 音效现在由玩法模拟直接触发（命中了才响），不再是「按固定时间表猜」。
    // 小队位置由手指直接决定，不需要每帧推进
    _clock.addListener(_tickSim);
    _resetSim();
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
    final frames = <String>{
      ..._walkFront,
      ..._walkBack,
      ..._allyPoses,
      'pout',
      'cry'
    };
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

  /// 先冲过头再回弹，用于星芒的爆开。与 Python 侧 ease_out_back 一致。
  static double _easeOutBack(double x, {double s = 1.7}) {
    final double t = x - 1;
    return t * t * ((s + 1) * t + s) + 1;
  }

  static double _easeOutElastic(double x,
      {double amp = 0.5, double period = 0.32}) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return 1 +
        amp *
            math.pow(2, -10 * x) *
            math.sin((x - period / 4) * (2 * math.pi) / period);
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
            Widget groundShadow(double cx, double feetY, double imgH) =>
                Positioned(
                  left: cx - imgH * 0.28,
                  top: feetY - imgH * 0.0575,
                  width: imgH * 0.56,
                  height: imgH * 0.115,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF5C483A).withValues(alpha: 0.30),
                          blurRadius: imgH * 0.10,
                        ),
                      ],
                      borderRadius: BorderRadius.all(
                          Radius.elliptical(imgH * 0.28, imgH * 0.0575)),
                    ),
                  ),
                );

            // 注意：Positioned 必须是 Stack 的直接子节点，不能再包一层 Opacity
            // （实测会抛 Incorrect use of ParentDataWidget），所以透明度放在 Positioned 内部。
            Widget unitImage(
                    ({double cx, double imgH, double imgW, double top}) pl,
                    String asset,
                    double sqX,
                    double sqY,
                    double rot,
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
                child: Image.asset(_bg,
                    fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              ),
            ];

            // ---- 怪群：由玩法模拟驱动（竖直弹丸 + 命中驱动的挨打/哭/逃）
            final ordered = List<_Mob>.from(_mobs)
              ..sort((a, b) => a.ground.compareTo(b.ground));
            for (final mb in ordered) {
              if (mb.waiting) continue; // 还没上桥
              final (double sqX, double sqY) = mb.squash();
              final double cx = mb.x +
                  (mb.state == 'cry'
                      ? math.sin(mb.timer * math.pi * 2 * 19) * 3.2
                      : 0);
              final pl = place(cx, mb.ground, mb.h);
              children.add(groundShadow(pl.cx, toScreenY(mb.ground), pl.imgH));
              for (final _PoseLayer pose in mb.poses()) {
                if (pose.opacity <= 0.001) continue;
                children
                    .add(unitImage(pl, pose.asset, sqX, sqY, 0, pose.opacity));
              }
            }

            // ---- 我方小队：前后两排，整体随 _squadX 左右移动
            final squad =
                _MonsterSpriteState._squadMembers(_squadX, _squadDepth);
            for (int ai = 0; ai < squad.length; ai++) {
              final m2 = squad[ai];
              final double bob =
                  -0.022 * math.cos(2 * math.pi * 0.9 * t + ai * 1.3);
              final pl = place(m2.x, m2.ground, m2.h);
              children.add(groundShadow(pl.cx, toScreenY(m2.ground), pl.imgH));
              children.add(unitImage(
                  pl, _allyPoseFromShot(ai), 1 - bob * 0.55, 1 + bob, 0));
            }

            children.add(Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MonsterFxPainter(
                      cover: cover,
                      offX: offX,
                      offY: offY,
                      nuts: _nuts,
                      stars: _stars,
                      mobs: _mobs,
                      fruits: _fruits),
                ),
              ),
            ));

            // ---- 答题 UI：顶部释义 + 倒计时；单词靶画在平台**前方**（可射击）
            if (_asking) {
              final _Question q =
                  _demoQuestions[_questionIndex % _demoQuestions.length];
              final double left =
                  (_askDeadline - _simTime).clamp(0.0, _askSeconds);
              final double wy = offY + _WordTarget.depth * cover;
              for (final w in _words) {
                final double wx = offX + w.x * cover;
                children.add(Positioned(
                  left: wx - 80,
                  top: wy - 26,
                  child: Container(
                    width: 160,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23303F).withValues(alpha: 0.80),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.60),
                          width: 1.6),
                    ),
                    child: Text(w.text,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                  ),
                ));
              }
              // 顶部：中文释义 + 倒计时（时限内不作答就算答错）
              children.add(Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 7),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1C2230).withValues(alpha: 0.74),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(q.meaning,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2)),
                      ),
                      const SizedBox(height: 6),
                      // 倒计时条：越短越快见底
                      SizedBox(
                        width: 190,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: left / _askSeconds,
                            minHeight: 6,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.25),
                            valueColor: AlwaysStoppedAnimation<Color>(left < 2
                                ? const Color(0xFFFF7A7A)
                                : const Color(0xFF7BE38B)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ));
            }
            if (_flash != null && _simTime < _flashUntil) {
              children.add(Positioned(
                top: 92,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(_flash!,
                      style: TextStyle(
                          color: _flash!.startsWith('答对')
                              ? const Color(0xFF7BE38B)
                              : const Color(0xFFFF8A8A),
                          fontSize: 19,
                          fontWeight: FontWeight.w600)),
                ),
              ));
            }

            // ---- 左下虚拟摇杆：小队走位（按住持续走、松手停）
            // 右下角先留空，将来要加右摇杆/道具时直接摆进去。
            final EdgeInsets safe = MediaQuery.paddingOf(context);
            final double joyRadius = (c.maxHeight * 0.17).clamp(44.0, 72.0);
            children.add(Positioned(
              left: 6 + safe.left,
              bottom: 4 + safe.bottom,
              child: GameJoystick(
                radius: joyRadius,
                onChanged: (dir, mag) {
                  _moveX = dir.dx * mag;
                  _moveY = dir.dy * mag;
                },
                onEnd: () {
                  _moveX = 0;
                  _moveY = 0;
                },
              ),
            ));

            // 开局提示：这一版只有走位是手动操作，得先说清楚答题靠什么
            if (_simTime < 9) {
              children.add(Positioned(
                top: safe.top + 12,
                left: safe.left + 58,
                child: IgnorePointer(
                  child: Text(
                    '左摇杆走位 · 小宠物自动投掷\n把队伍挪到正确单词的下方',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.90),
                      shadows: const [
                        Shadow(color: Color(0x99000000), blurRadius: 8)
                      ],
                    ),
                  ),
                ),
              ));
            }

            // 水果被抢光：压一层提示 + 重新开始
            if (_lost) {
              children.add(Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '水果被小馋怪抢光了',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => setState(_resetSim),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                        ),
                        child:
                            const Text('再来一次', style: TextStyle(fontSize: 17)),
                      ),
                    ],
                  ),
                ),
              ));
            }

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
/// 玩法参数（与 tools/sprite_anim/render_anim.py 的同名常量一一对应）。
/// 出手点在小宠物素材图里的位置（**倍身高**）。
///
/// ⚠️ 要从 **ally_windup** 量，不是 ally_throw！逐行测手臂最高点：
///   ally_stand y=173、**ally_windup y=161（最高，手到顶点）**、ally_throw y=194（比 windup 还低 33px）。
/// 也就是说出手动作的语义是「抬手 windup → **顶点出手** → 甩臂 throw（收势）」。
/// 原先绑在 ally_throw（收势）上，所以子弹总是晚一步。
/// 该图里手在 (420, 171)：横向 (420−264)/399 = 0.39、高度 (515−171)/399 = 0.86。
const double _handOffsetX = 0.38;
const double _handOffsetY = 0.86;

/// 手举到顶点（ally_windup）后停留多久切到甩臂收势。
const double _windupHold = 0.18;

/// 投掷物向前的推进速度（每帧减少的深度）。
///
/// 不做抛物线：用户判断在手机上根本看不出来，反而绕。只要出手位置对、朝消失点收拢就够了。
const double _nutForward = 420;
// 每隔多久一发，轮流由小队成员投出。
// 平衡口径：到达率 16 只 / 15 秒 ≈ 1.1 只/秒；火力 1/0.20 = 5 发/秒 ÷ 每只 3 发
// ≈ 1.7 只/秒，留出余量。原来进场只跨 9 秒（1.8 只/秒）而火力只够 1.4 只/秒，必然崩。
const double _shotInterval = 0.20;
const double _mobWalkSpeed = 50; // 小怪的移动速度（96→58→50，逐步放慢给玩家时间）
const double _mobFleeSpeed = 215; // 逃跑速度
const double _recoilTime = 0.34; // 被打退一下的时长
const double _cryTime = 0.80; // 原地哭的时长
const int _hitsToCry = 3; // 挨几下会哭

/// 水果摆在「小怪」与「投手」之间那一排的深度。
const double _fruitDepth = 700;

/// 水果的横向位置（占该处桥面半宽的比例）。
const List<double> _fruitLanes = [-0.62, -0.31, 0.0, 0.31, 0.62];

/// 小怪走到离水果这么近（画布像素）就算拿到了。
const double _stealRadius = 46;

/// 离目标水果线还有多远（**深度差**，不是直线距离）才开始拐弯。更远时保持车道直走。
///
/// 原来是全场都在寻路，于是小怪一进场就往最近的水果扑、看着全挤到中间。
/// 加了这条之后：进场阶段按各自车道均匀铺开（桥面越近越宽，天然越走越散），
/// 只有进到后半段才向水果集中——正是需求里要的「后半段才向水果密集处集中」。
const double _seekRadius = 300;

// ---------------------------------------------------------------- 答题平台
//
// 桥两侧贴着岸边的加宽平台（「桥肩」），从水果那一行一直延伸到镜头前。
// 为什么不做成「深处那一小块」：队伍只能左右移动，深处它够不着。
// 做成从水果行延伸到近处，队伍**只靠左右移动就能滑上去**，不必新增前后移动的操作。
const double _platDepthFar = _fruitDepth; // 平台的最深处（＝水果那一行）
const double _platDepthNear = 1020; // 延伸到队伍脚下再往前一点
/// 平台外沿（占该处桥面半宽的比例）；>1 表示伸出桥面之外。
const double _platOuter = 1.90;

// 出题节奏：先空一段（不上题，避免一题接一题），再给一段答题时间，超时算答错。
const double _gapSeconds = 2.5;
const double _askSeconds = 6.0;

/// 单词靶的位置：在平台**前方**（更深），站在平台上朝正前方射击正好打到它。
const double _wordDepth = 560;
const double _wordLane = 1.45;

// 增益就是**一个等级**：答对 +1、答错 −1（用户明确要求，持久累积、不清零）。
// 火力倍率 = 0.8^等级，夹在上下限之间。
//
// 为什么要夹：开火间隔趋近 0 在工程上不可能（帧率、音效通道都有限），
// 而等级为负时 0.8^n 会越乘越大也会失控。与其让它自己崩掉，
// 不如显式设上下限并写清楚原因。
const double _buffStep = 0.8;
const double _fireMin = 0.25; // 最快：开火间隔缩到 25%
const double _fireMax = 3.0; // 最慢：拖到 3 倍

/// 单词靶：给中文释义，左右各一个英文单词，打中哪个就是选哪个。
class _WordTarget {
  _WordTarget(this.text, this.correct, this.x);
  final String text;
  final bool correct;
  final double x;
  static const double depth = _wordDepth;
}

/// 题目：给中文释义，在桥两侧的两个英文单词里选对的那个。
/// 先用内置的小词表跑通机制；将来接真实词典（dictWords）。
class _Question {
  const _Question(this.word, this.wrongWord, this.meaning);
  final String word; // 正确答案（含释义）
  final String wrongWord; // 干扰项
  final String meaning; // 顶部显示的中文释义
}

const List<_Question> _demoQuestions = [
  _Question('bridge', 'fridge', '桥'),
  _Question('apple', 'maple', '苹果'),
  _Question('brave', 'grave', '勇敢的'),
  _Question('listen', 'glisten', '听'),
  _Question('quiet', 'quite', '安静的'),
];

/// 开局桥面是空的：小怪在这段时间内**错开**从桥那头走上来。
/// 这个量直接决定到达率，是平衡的第一杠杆。
/// 用各自的相位当错开量，所以进场顺序天然是乱的、不是列队。
const double _entrySpread = 15.0;

/// 一颗水果。被小怪拿到就 taken，永久消失；5 颗都没了玩家就输了。
class _Fruit {
  _Fruit(this.lane);
  final double lane;
  bool taken = false;
  double get depth => _fruitDepth;
  double get x =>
      _MonsterSpriteState._canvasW / 2 +
      lane * _MonsterSpriteState._bridgeHalf(depth);
}

/// 一只小怪：`walk`（朝最近的水果走）→ 走到就 `flee`（拿着水果跑）。
/// 中途被命中 `recoil` → 挨满 3 下 `cry` → `flee`（没拿到东西，空手跑）。

///
/// 为什么不沿用「按相位跑固定时间线」：需求是「弹丸竖直向前、打最前面那只、不穿透」，
/// 那挨打与哭就必须**由命中触发**，否则会出现「弹丸打中 A，却是 B 在哭」的矛盾。
class _Mob {
  _Mob(this.lane, this.dj, this.sj, this.entryDelay)
      : gy = _MonsterSpriteState._groundFar;

  /// 还没上桥：不画也不动。
  bool get waiting => entryDelay > 0;

  double lane; // 可变：寻路时要横向修正
  final double dj, sj;
  double gy;

  /// 还要等多久才上桥。>0 表示还没进场（不画、不动）。
  double entryDelay;
  bool carrying = false; // 是否已经抢到水果（拿着跑）
  int hits = 0;
  String state = 'walk';
  double timer = 0, sinceHit = 99, walkT = 0;

  double get ground => gy + dj;
  double get x =>
      _MonsterSpriteState._canvasW / 2 +
      lane * _MonsterSpriteState._bridgeHalf(ground);
  double get h =>
      _MonsterSpriteState._charBase *
      _MonsterSpriteState._scaleAtGround(ground) *
      sj;

  /// 正在哭或逃跑的小怪不挡弹丸——「除非正在哭，否则不要穿透」。
  bool get transparent => state == 'cry' || state == 'flee';

  void hit() {
    hits++;
    sinceHit = 0;
    if (hits >= _hitsToCry) {
      state = 'cry';
      timer = _cryTime;
    } else {
      state = 'recoil';
      timer = _recoilTime;
    }
  }

  /// 朝目标二维移动：**深度和横向同时修正**，所以能看见它拐弯，
  /// 而不是只会在自己那一列往正前方走。进到抢水果的距离就判定拿走。
  void _seek(_Fruit f, double dt) {
    final double dx = f.x - x;
    final double dg = f.depth - ground;
    final double dist = math.sqrt(dx * dx + dg * dg);
    if (dist <= _stealRadius) {
      f.taken = true;
      carrying = true;
      state = 'flee'; // 满足：拿着水果转身跑
      timer = 0;
      return;
    }
    final double step = _mobWalkSpeed * dt;
    final double ngy = ground + dg / dist * step;
    final double nx = x + dx / dist * step;
    gy = ngy - dj;
    lane = (nx - _MonsterSpriteState._canvasW / 2) /
        _MonsterSpriteState._bridgeHalf(ngy);
  }

  void step(double dt, List<_Fruit> fruits) {
    if (waiting) {
      entryDelay -= dt;
      return;
    }
    sinceHit += dt;
    if (state == 'walk' || state == 'flee' || state == 'hold') walkT += dt;
    switch (state) {
      case 'walk':
        // 找「最近的一颗还在的水果」。只剩一颗时所有小怪都会朝它走——
        // 这是「取最近」的自然结果，不需要为「只剩一颗」写特判。
        _Fruit? best;
        double bestD = double.infinity;
        for (final f in fruits) {
          if (f.taken) continue;
          final double dx = f.x - x, dg = f.depth - ground;
          final double dd = dx * dx + dg * dg;
          if (dd < bestD) {
            bestD = dd;
            best = f;
          }
        }
        if (best == null) return; // 水果被抢光，没什么可抢了
        // 门槛必须看**深度差**，不能看到水果的直线距离：
        // 直线距离的话，横向离得远的小怪（水果被抢剩几颗时很常见）永远进不了门槛，
        // 会径直走过水果线、再一路走到镜头前——表现就是「有的小怪直接从桥上走过去，
        // 也不往水果靠」。用深度差则所有小怪都在同一深度开始横向收拢。
        if (best.depth - ground <= _seekRadius) {
          _seek(best, dt); // 后半段：向水果集中
        } else {
          gy += _mobWalkSpeed * dt; // 前半段：保持车道直行，均匀铺开
        }
      case 'hold':
        break;
      case 'recoil':
        timer -= dt;
        if (timer <= 0) state = 'walk';
      case 'cry':
        timer -= dt;
        if (timer <= 0) state = 'flee';
      case 'flee':
        gy -= _mobFleeSpeed * dt;
        if (ground < _MonsterSpriteState._groundFleeEnd - 60) {
          gy = _MonsterSpriteState._groundFar; // 跑远了，从桥那头重来
          hits = 0;
          carrying = false; // 新来一只，空手
          state = 'walk';
          timer = 0;
          entryDelay = 1.2; // 稍等一下再上桥，别刚从画面外回来就冒出来
        }
    }
  }

  /// 这一刻该出什么姿势。
  List<_PoseLayer> poses() {
    if (state == 'cry') {
      return const [(asset: _MonsterSpriteState._cry, opacity: 1.0)];
    }
    if (state == 'flee') {
      return [
        _MonsterSpriteState._walkPose(
            _MonsterSpriteState._walkBack, walkT, _MonsterSpriteState._walkHz)
      ];
    }
    if (state == 'recoil') {
      return const [(asset: _MonsterSpriteState._pout, opacity: 1.0)];
    }
    return [
      _MonsterSpriteState._walkPose(
          _MonsterSpriteState._walkFront, walkT, _MonsterSpriteState._walkHz)
    ];
  }

  /// 挨打那一下的挤压回弹（弹性曲线，越往后越平）。
  (double, double) squash() {
    if (sinceHit > 0.62) return (1.0, 1.0);
    final double k = sinceHit / 0.62;
    final double e =
        _MonsterSpriteState._easeOutElastic(k, amp: 0.55, period: 0.36);
    final double w = e * (1 - k) * 1.35 * (hits >= _hitsToCry ? 1.0 : 0.6);
    return (
      _MonsterSpriteState._lerp(1.0, 1.16, w),
      _MonsterSpriteState._lerp(1.0, 0.80, w)
    );
  }
}

/// 飞行中的投掷物。**不追目标**，只朝正前方（桥的远端）飞。
///
/// 屏幕上那个 y 其实同时表达了「深度」和「离地高度」两件事，所以拆开存：
///   * [depth]  脚下的地面行，向前推进（决定透视缩放与横向收拢）
///   * [height] 离地高度，恒定在出手时的手部高度
///   屏幕上画在 depth - height 处——于是它一边向远处去、一边在画面上抬高。
/// 横向用 [laneFrac]（占该处桥面半宽的比例）保持恒定：这是世界坐标里的直线，
/// 投影到屏幕上就自然朝消失点收拢，也自然变小。
/// 一次只扔出**一个**东西。
class _Nut {
  _Nut(this.depth, this.height, this.laneFrac, this.scale0);
  double depth;
  final double height;
  final double laneFrac;
  final double scale0;
  double get x =>
      _MonsterSpriteState._canvasW / 2 +
      laneFrac * _MonsterSpriteState._bridgeHalf(depth);
  double get screenY => depth - height;
}

/// 命中星芒。
class _Star {
  _Star(this.x, this.y, this.big);
  final double x, y;
  final bool big;
  double age = 0;
}

class _MonsterFxPainter extends CustomPainter {
  _MonsterFxPainter({
    required this.cover,
    required this.offX,
    required this.offY,
    required this.nuts,
    required this.stars,
    required this.mobs,
    required this.fruits,
  });

  final double cover;
  final double offX;
  final double offY;
  final List<_Nut> nuts;
  final List<_Star> stars;
  final List<_Mob> mobs;
  final List<_Fruit> fruits;

  double _x(double canvasX) => offX + canvasX * cover;

  double _y(double canvasY) => offY + canvasY * cover;

  /// 一颗水果（程序化占位：圆果 + 叶子 + 高光）。将来换成正式美术。
  void _fruit(Canvas canvas, double cx, double cy, double r) {
    final Paint body = Paint()..color = const Color(0xFFE8552F);
    canvas.drawCircle(Offset(cx, cy), r, body);
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.14)
          ..color = const Color(0xFF9E2F14));
    // 左上高光
    canvas.drawCircle(Offset(cx - r * 0.33, cy - r * 0.33), r * 0.26,
        Paint()..color = const Color(0x99FFD9CC));
    // 叶子
    final Path leaf = Path()
      ..moveTo(cx, cy - r * 0.92)
      ..quadraticBezierTo(
          cx + r * 0.78, cy - r * 1.66, cx + r * 0.30, cy - r * 1.86)
      ..quadraticBezierTo(cx + r * 0.05, cy - r * 1.52, cx, cy - r * 0.92)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF4E9B4A));
    // 果柄
    canvas.drawLine(
        Offset(cx, cy - r * 0.72),
        Offset(cx, cy - r * 1.12),
        Paint()
          ..strokeWidth = math.max(1.2, r * 0.17)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF7A4A22));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ---- 水果：画在所有人下面（地面上的一排）
    for (final f in fruits) {
      if (f.taken) continue;
      final double r = 26 *
          _MonsterSpriteState._fx *
          cover *
          (_MonsterSpriteState._scaleAtGround(f.depth) / 0.52).clamp(0.5, 1.4);
      _fruit(canvas, _x(f.x), _y(f.depth) - r * 1.05, r);
    }

    // ---- 两侧答题平台（桥肩）：从水果那一行延伸到近处
    for (final int side in const [-1, 1]) {
      final double yFar = _platDepthFar;
      final double yNear = _platDepthNear;
      final double hFar = _MonsterSpriteState._bridgeHalf(yFar);
      final double hNear = _MonsterSpriteState._bridgeHalf(yNear);
      final double innerFar = side * hFar;
      final double outerFar = side * hFar * _platOuter;
      final double innerNear = side * hNear;
      final double outerNear = side * hNear * _platOuter;
      final Path plat = Path()
        ..moveTo(_x(_MonsterSpriteState._canvasW / 2 + innerFar), _y(yFar))
        ..lineTo(_x(_MonsterSpriteState._canvasW / 2 + outerFar), _y(yFar))
        ..lineTo(_x(_MonsterSpriteState._canvasW / 2 + outerNear), _y(yNear))
        ..lineTo(_x(_MonsterSpriteState._canvasW / 2 + innerNear), _y(yNear))
        ..close();
      canvas.drawPath(plat, Paint()..color = const Color(0xFFD9C08A));
      canvas.drawPath(
          plat,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, 3 * cover)
            ..color = const Color(0xFF8A6B3A));
    }

    // ---- 投掷物：一次只画一个，不拖尾迹。大小按所在深度的透视缩放。
    for (final n in nuts) {
      final double k = _MonsterSpriteState._scaleAtGround(n.depth) /
          (n.scale0 == 0 ? 1 : n.scale0);
      _nut(canvas, _x(n.x), _y(n.screenY), n.depth * 1.4,
          22 * _MonsterSpriteState._fx * cover * k.clamp(0.45, 1.4));
    }

    // ---- 命中星芒
    for (final st in stars) {
      _star(canvas, _x(st.x), _y(st.y), st.age / 0.42,
          (st.big ? 1.0 : 0.6) * _MonsterSpriteState._fx);
    }

    // ---- 飙泪：正在哭、以及哭着逃跑的小怪
    for (final m in mobs) {
      final bool crying = m.state == 'cry';
      final bool fleeingCry = m.state == 'flee';
      if (!crying && !fleeingCry) continue;
      // 哭是从进入 cry 状态算起的；逃跑时继续飙（位置跟着走）
      final double cryAge = crying ? (_cryTime - m.timer) : (_cryTime + 0.6);
      final double cx = m.x;
      final double gy = m.ground;
      final double h = m.h;
      for (int i = 0; i < 30; i++) {
        final double age = cryAge - i * 0.09;
        if (age < 0 || age > 0.65) continue;
        final double side = i.isEven ? -1 : 1;
        final double tx = _x(cx + side * h * 0.10 + side * h * 1.9 * age);
        final double ty = _y(gy - h * 0.62 - h * (1.2 * age - 3.2 * age * age));
        if (fleeingCry) {
          // 背对镜头：落在脑袋轮廓内的泪珠看不见（否则像从后脑勺飙出来）
          final double u = (tx - _x(cx)) / (h * 0.42 * cover);
          final double v = (ty - _y(gy - h * 0.50)) / (h * 0.52 * cover);
          if (u * u + v * v < 1.0) continue;
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(tx, ty),
            width: 25 * _MonsterSpriteState._fx * cover,
            height: 35 * _MonsterSpriteState._fx * cover,
          ),
          Paint()
            ..color = const Color(0xFF9FD8F5)
                .withValues(alpha: 0.9 * (1 - age / 0.7)),
        );
      }
    }
  }

  /// 命中的星芒。与 Python 侧 fx_impact 同构——16 个顶点交替半径的星形（外圈 r、内圈 0.42r），
  /// 叠一层向中心缩到 0.62 的白色内星，再套一个圆环描边，最后整体做模糊。
  void _star(Canvas canvas, double cx, double cy, double k, double scale) {
    if (k <= 0 || k >= 1) return;
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
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.64),
        fill);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.64),
        stroke);
    canvas.drawArc(
        Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 1.2),
        200 * math.pi / 180,
        140 * math.pi / 180,
        false,
        Paint()
          ..color = const Color(0xFF7E542E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.14));
    canvas.restore();
  }

  @override
  // 每帧都要重画：弹丸、星芒、泪珠都是逐帧变化的
  bool shouldRepaint(_MonsterFxPainter old) => true;
}
