import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// 泡泡单词定义
class BubbleWord {
  final String word;
  final String meaning;
  const BubbleWord(this.word, this.meaning);
}

/// 泡泡实体对象
class BubbleItem {
  final int id;
  final BubbleWord wordData;
  double x;
  double y;
  final double baseX;
  final double radius;
  final double speed; // 上升速度 (px/s)
  final double swingAmplitude; // 左右摆动幅度
  final double swingFreq; // 左右摆动频率
  final double phase; // 初始相位
  final Color baseColor; // 泡泡色调
  bool isPopping = false;
  double popProgress = 0.0;
  bool isWrongJiggle = false;
  double jiggleProgress = 0.0;

  BubbleItem({
    required this.id,
    required this.wordData,
    required this.x,
    required this.y,
    required this.baseX,
    required this.radius,
    required this.speed,
    required this.swingAmplitude,
    required this.swingFreq,
    required this.phase,
    required this.baseColor,
  });
}

/// 爆破飞溅水珠粒子
class PopParticle {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  Color color;
  double life; // 0.0 ~ 1.0 (1.0 为出生, 0.0 为消亡)
  final double maxLife;

  PopParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.color,
    required this.life,
  }) : maxLife = life;
}

/// 飘字动效 (+10, Combo)
class FloatingText {
  double x;
  double y;
  final String text;
  final Color color;
  double life = 1.0;

  FloatingText({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
  });
}

/// 空气区堆积的死泡泡（灰暗石化浮沫）
class DeadBubbleItem {
  final int id;
  final String word;
  double x;
  double y;
  final double radius;
  bool isPopping = false;
  double popProgress = 0.0;

  DeadBubbleItem({
    required this.id,
    required this.word,
    required this.x,
    required this.y,
    this.radius = 26.0,
  });
}

/// 弹道类型
enum ProjectileType { needle, mine }

/// 弹道飞行物（净化金针 / 攻击水雷）
class GameProjectile {
  final ProjectileType type;
  double x;
  double y;
  final double startX;
  final double startY;
  final double targetX;
  final double targetY;
  double progress = 0.0;
  DeadBubbleItem? targetBubble;

  GameProjectile.needle({
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
    this.targetBubble,
  })  : type = ProjectileType.needle,
        startX = x,
        startY = y;

  GameProjectile.mine({
    required this.startX,
    required this.startY,
    required this.targetX,
    required this.targetY,
  })  : type = ProjectileType.mine,
        x = startX,
        y = startY;
}

/// 泡泡升空对战（体验版）
class BubbleBattlePreviewPage extends StatefulWidget {
  const BubbleBattlePreviewPage({super.key});

  @override
  State<BubbleBattlePreviewPage> createState() => _BubbleBattlePreviewPageState();
}

class _BubbleBattlePreviewPageState extends State<BubbleBattlePreviewPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // 内置常用精选高频单词库（便于离线体验）
  final List<BubbleWord> _vocabList = const [
    BubbleWord('summer', '夏天'),
    BubbleWord('happy', '快乐 / 幸福'),
    BubbleWord('father', '父亲'),
    BubbleWord('good', '优秀的 / 好的'),
    BubbleWord('ocean', '海洋'),
    BubbleWord('sunshine', '阳光'),
    BubbleWord('dream', '梦想'),
    BubbleWord('breeze', '微风'),
    BubbleWord('friend', '朋友'),
    BubbleWord('journey', '旅程'),
    BubbleWord('courage', '勇气'),
    BubbleWord('wonder', '奇迹 / 惊叹'),
    BubbleWord('memory', '回忆'),
    BubbleWord('treasure', '宝藏'),
    BubbleWord('crystal', '水晶'),
    BubbleWord('harmony', '和谐'),
    BubbleWord('starlight', '星光'),
    BubbleWord('miracle', '神迹'),
  ];

  // 泡泡配色盘
  final List<Color> _bubbleColors = const [
    Color(0xFF60A5FA), // 浅海蓝
    Color(0xFFA78BFA), // 梦幻紫
    Color(0xFF34D399), // 薄荷绿
    Color(0xFFF472B6), // 珊瑚粉
    Color(0xFFFBBF24), // 暖阳金
    Color(0xFF38BDF8), // 天空青
  ];

  final Random _rand = Random();

  // 游戏进行状态（纯生存淘汰制，无需多余倒计时）
  int _scorePlayer = 0;
  int _scoreOpponent = 20;
  int _comboCount = 0;
  double _opponentPressure = 0.0; // 对手被水雷轰击压沉深度 (达到 120px 溃败)
  bool _isGameOver = false;
  bool _isPlayerWon = false;
  String _gameOverReason = '';

  // 道具数量
  int _attackProps = 1;
  int _purgeProps = 1;

  // 当前目标词
  late BubbleWord _targetWord;

  // 泡泡列表与粒子、死泡、弹道列表
  final List<BubbleItem> _bubbles = [];
  final List<PopParticle> _particles = [];
  final List<FloatingText> _floatingTexts = [];
  final List<DeadBubbleItem> _deadBubbles = [];
  final List<GameProjectile> _projectiles = [];
  int _nextBubbleId = 0;

  // 虚拟对手计时器（模拟对手戳泡）与受击震动
  double _opponentTimer = 0.0;
  double _opponentShake = 0.0;

  // 水面惩罚线：y 坐标从顶部往下压
  // 基准高度 140 (顶部 HUD 下方), 随死泡泡数量往下压沉
  static const double baseWaterY = 140.0;
  double _waterSurfaceY = baseWaterY;
  double _targetWaterSurfaceY = baseWaterY;
  double _wavePhase = 0.0;

  @override
  void initState() {
    super.initState();
    _targetWord = _vocabList[0];
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _startNewRound(Size size) {
    if (_isGameOver) return;
    _bubbles.clear();

    // 1. 选取目标词
    _targetWord = _vocabList[_rand.nextInt(_vocabList.length)];

    // 2. 选取 3 个不重复干扰词
    final remaining = _vocabList.where((w) => w.word != _targetWord.word).toList()..shuffle(_rand);
    final distractors = remaining.take(3).toList();

    // 3. 组成 4 个候选项并打乱
    final roundWords = [_targetWord, ...distractors]..shuffle(_rand);

    // 4. 4 个独立泳道，确保横向分散绝不粘连
    final lanes = [0, 1, 2, 3]..shuffle(_rand);
    const double margin = 45.0;
    final double usableWidth = size.width - margin * 2;
    final double laneWidth = usableWidth / 4;

    for (int i = 0; i < 4; i++) {
      final int lane = lanes[i];
      final double baseX = margin + lane * laneWidth + laneWidth / 2 + (_rand.nextDouble() - 0.5) * 8;
      const double radius = 38.0;
      final Color color = _bubbleColors[_rand.nextInt(_bubbleColors.length)];
      final double speed = 40.0 + _rand.nextDouble() * 25.0; // 40~65 px/s
      final double startY = size.height + 40.0 + i * 55.0 + _rand.nextDouble() * 20.0;

      _bubbles.add(BubbleItem(
        id: _nextBubbleId++,
        wordData: roundWords[i],
        x: baseX,
        y: startY,
        baseX: baseX,
        radius: radius,
        speed: speed,
        swingAmplitude: 8.0 + _rand.nextDouble() * 6.0,
        swingFreq: 1.2 + _rand.nextDouble() * 0.8,
        phase: _rand.nextDouble() * 2 * pi,
        baseColor: color,
      ));
    }
  }

  void _updateWaterPressure(Size size) {
    _targetWaterSurfaceY = min(size.height * 0.72, baseWaterY + _deadBubbles.length * 30.0);
  }

  void _addDeadBubble(String word, Size size) {
    _comboCount = 0;
    _deadBubbles.add(DeadBubbleItem(
      id: _nextBubbleId++,
      word: word,
      x: size.width * 0.5,
      y: _waterSurfaceY - 30.0,
    ));
    _updateWaterPressure(size);
    HapticFeedback.lightImpact();
  }

  bool _firePurgeNeedle(Size size) {
    if (_deadBubbles.isEmpty) {
      _floatingTexts.add(FloatingText(
        x: size.width * 0.5,
        y: _waterSurfaceY - 20,
        text: '水面已无死泡负担!',
        color: const Color(0xFF38BDF8),
      ));
      return false;
    }
    final target = _deadBubbles.first;
    _projectiles.add(GameProjectile.needle(
      x: target.x,
      y: size.height - 120,
      targetX: target.x,
      targetY: target.y,
      targetBubble: target,
    ));
    HapticFeedback.mediumImpact();
    return true;
  }

  void _fireAttackMine(Size size) {
    _projectiles.add(GameProjectile.mine(
      startX: size.width * 0.5,
      startY: size.height - 120,
      targetX: 52,
      targetY: 52,
    ));
    HapticFeedback.heavyImpact();
    _floatingTexts.add(FloatingText(
      x: size.width * 0.5,
      y: size.height - 160,
      text: '🚀 水雷出膛 轰击对手!',
      color: const Color(0xFFF87171),
    ));
  }

  void _resetGame() {
    setState(() {
      _scorePlayer = 0;
      _scoreOpponent = 20;
      _comboCount = 0;
      _opponentPressure = 0.0;
      _attackProps = 1;
      _purgeProps = 1;
      _isGameOver = false;
      _isPlayerWon = false;
      _gameOverReason = '';
      _deadBubbles.clear();
      _projectiles.clear();
      _waterSurfaceY = baseWaterY;
      _targetWaterSurfaceY = baseWaterY;
      _bubbles.clear();
      _particles.clear();
      _floatingTexts.clear();
    });

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);
    _startNewRound(size);
  }

  void _onTick(Duration elapsed) {
    if (_isGameOver) return;

    final double dt = (_lastElapsed == Duration.zero)
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    if (dt <= 0 || dt > 0.1) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);

    // 初始生成首轮
    if (_bubbles.isEmpty && !_isGameOver) {
      _startNewRound(size);
    }

    // 1. 波浪动态推进与水面平滑追随
    _wavePhase += dt * 3.0;
    _waterSurfaceY += (_targetWaterSurfaceY - _waterSurfaceY) * min(1.0, dt * 6.0);

    // 2. 检验是否触底危险死亡线（海面被死泡压沉淘汰）
    if (_waterSurfaceY >= size.height * 0.74) {
      _isGameOver = true;
      _isPlayerWon = false;
      _gameOverReason = '⚠️ 我方海面被死泡严重压沉，不幸淹没淘汰！';
      HapticFeedback.vibrate();
    }

    // 3. 虚拟对手计时器与受击晃动恢复
    if (_opponentShake > 0) {
      _opponentShake = max(0.0, _opponentShake - dt);
    }
    _opponentTimer += dt;
    if (_opponentTimer > 4.5) {
      _opponentTimer = 0.0;
      _scoreOpponent += 10;
      _floatingTexts.add(FloatingText(
        x: 80,
        y: 110,
        text: '+10',
        color: const Color(0xFFF97316),
      ));
    }

    // 4. 泡泡防重叠物理软排斥
    for (int i = 0; i < _bubbles.length; i++) {
      for (int j = i + 1; j < _bubbles.length; j++) {
        final b1 = _bubbles[i];
        final b2 = _bubbles[j];
        if (b1.isPopping || b2.isPopping) continue;

        final double dx = b2.x - b1.x;
        final double dy = b2.y - b1.y;
        final double dist = sqrt(dx * dx + dy * dy);
        final double minDist = b1.radius + b2.radius + 16.0;
        if (dist < minDist && dist > 0.001) {
          final double overlap = (minDist - dist) * 0.5;
          final double nx = dx / dist;
          final double ny = dy / dist;
          b1.x -= nx * overlap;
          b1.y -= ny * overlap;
          b2.x += nx * overlap;
          b2.y += ny * overlap;
        }
      }
    }

    // 5. 泡泡物理运动与越界判定
    bool targetWordExpired = false;
    for (int i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];

      if (b.isPopping) {
        b.popProgress += dt * 5.0;
        if (b.popProgress >= 1.0) {
          _bubbles.removeAt(i);
        }
        continue;
      }

      if (b.isWrongJiggle) {
        b.jiggleProgress += dt * 8.0;
        if (b.jiggleProgress >= 1.0) {
          b.isWrongJiggle = false;
          b.jiggleProgress = 0.0;
        }
      }

      b.y -= b.speed * dt;
      b.x += sin(elapsed.inMilliseconds / 1000.0 * b.swingFreq + b.phase) * (b.swingAmplitude * 0.05);

      // 触及海平面：若是目标词漏过，变成死泡泡堆到空气区！
      if (b.y - b.radius <= _waterSurfaceY) {
        if (b.wordData.word == _targetWord.word) {
          targetWordExpired = true;
          _addDeadBubble(b.wordData.word, size);
          _floatingTexts.add(FloatingText(
            x: b.x,
            y: _waterSurfaceY + 20,
            text: '漏词！死泡堆积压顶',
            color: const Color(0xFFEF4444),
          ));
        }
        _createBurstParticles(b.x, _waterSurfaceY, b.baseColor, count: 6);
        _bubbles.removeAt(i);
      }
    }

    if (targetWordExpired) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isGameOver) {
          setState(() {
            _startNewRound(size);
          });
        }
      });
    }

    // 6. 排布空气区死泡泡位置（整齐吸附在海浪正上方）
    final int deadCount = _deadBubbles.length;
    for (int i = 0; i < deadCount; i++) {
      final db = _deadBubbles[i];
      final int cols = min(5, max(1, deadCount));
      final int colIndex = i % 5;
      final int rowIndex = i ~/ 5;
      final double colWidth = (size.width - 60) / cols;
      db.x = 30 + colIndex * colWidth + colWidth / 2;
      db.y = _waterSurfaceY - 26.0 - rowIndex * 40.0;

      if (db.isPopping) {
        db.popProgress += dt * 6.0;
        if (db.popProgress >= 1.0) {
          _deadBubbles.removeAt(i);
          _updateWaterPressure(size);
          break;
        }
      }
    }

    // 7. 弹道飞行物更新（金针 & 水雷）
    for (int i = _projectiles.length - 1; i >= 0; i--) {
      final p = _projectiles[i];
      if (p.type == ProjectileType.needle) {
        p.y -= 750.0 * dt;
        if (p.y <= p.targetY) {
          // 击中死泡！
          p.targetBubble?.isPopping = true;
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFF94A3B8), count: 14);
          _floatingTexts.add(FloatingText(
            x: p.targetX,
            y: p.targetY - 15,
            text: '💥 死泡破裂！海面抬升',
            color: const Color(0xFF38BDF8),
          ));
          _projectiles.removeAt(i);
        }
      } else if (p.type == ProjectileType.mine) {
        p.progress += dt * 1.8;
        p.x = p.startX + (p.targetX - p.startX) * p.progress;
        p.y = p.startY + (p.targetY - p.startY) * p.progress - sin(p.progress * pi) * 120.0;
        if (p.progress >= 1.0) {
          // 砸中对手！
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFFEF4444), count: 18);
          _opponentShake = 0.4;
          _opponentPressure += 40.0;
          _floatingTexts.add(FloatingText(
            x: 100,
            y: 50,
            text: '💥 对手水面被砸低 40px！',
            color: const Color(0xFFF87171),
          ));
          if (_opponentPressure >= 120.0) {
            _isGameOver = true;
            _isPlayerWon = true;
            _gameOverReason = '🚀 重力水雷彻底击沉对手海面，获得全胜！';
            HapticFeedback.heavyImpact();
          }
          _projectiles.removeAt(i);
        }
      }
    }

    // 8. 粒子运动更新
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 20.0 * dt;
      p.life -= dt;
      if (p.life <= 0) {
        _particles.removeAt(i);
      }
    }

    // 9. 浮字动效更新
    for (int i = _floatingTexts.length - 1; i >= 0; i--) {
      final ft = _floatingTexts[i];
      ft.y -= 30.0 * dt;
      ft.life -= dt * 1.2;
      if (ft.life <= 0) {
        _floatingTexts.removeAt(i);
      }
    }

    setState(() {});
  }

  /// 答对时触发
  void _onCorrectWordTapped(BubbleItem b) {
    b.isPopping = true;
    _scorePlayer += 10;
    _comboCount++;

    HapticFeedback.mediumImpact();
    _createBurstParticles(b.x, b.y, b.baseColor, count: 16);

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);

    // 连击 >= 2: 自动发射金针刺破死泡，水面抬升！
    if (_comboCount >= 2 && _deadBubbles.isNotEmpty) {
      _firePurgeNeedle(size);
    }

    // 达成连击增加道具点数
    if (_comboCount % 2 == 0) {
      _attackProps++;
      _purgeProps++;
      _floatingTexts.add(FloatingText(
        x: size.width * 0.5,
        y: size.height - 180,
        text: '🎁 连击获得战术道具！',
        color: const Color(0xFFFBBF24),
      ));
    }

    final String comboBonus = _comboCount > 1 ? ' Combo x$_comboCount!' : '';
    _floatingTexts.add(FloatingText(
      x: b.x,
      y: b.y - 15,
      text: '+10$comboBonus',
      color: const Color(0xFF38BDF8),
    ));

    // 其余迷惑泡泡破裂并延时开启新一题
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_isGameOver) {
        for (final other in _bubbles) {
          if (other != b && !other.isPopping) {
            _createBurstParticles(other.x, other.y, other.baseColor, count: 6);
          }
        }
        setState(() {
          _startNewRound(size);
        });
      }
    });
  }

  /// 答错时触发
  void _onWrongWordTapped(BubbleItem b) {
    b.isWrongJiggle = true;
    b.jiggleProgress = 0.0;
    _scorePlayer = max(0, _scorePlayer - 5);

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);
    _addDeadBubble(b.wordData.word, size);

    _floatingTexts.add(FloatingText(
      x: b.x,
      y: b.y - 10,
      text: '-5 答错石化下沉!',
      color: const Color(0xFFEF4444),
    ));
  }

  /// 生成水珠破裂粒子
  void _createBurstParticles(double x, double y, Color color, {int count = 12}) {
    for (int i = 0; i < count; i++) {
      final double angle = _rand.nextDouble() * 2 * pi;
      final double speed = 60.0 + _rand.nextDouble() * 120.0;
      _particles.add(PopParticle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        radius: 2.0 + _rand.nextDouble() * 2.5,
        color: color,
        life: 0.35 + _rand.nextDouble() * 0.3,
      ));
    }
  }

  /// 点击屏幕戳泡泡
  void _handleTapDown(TapDownDetails details) {
    if (_isGameOver) return;

    final tapPos = details.localPosition;

    for (int i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];
      if (b.isPopping) continue;

      final double dist = (Offset(b.x, b.y) - tapPos).distance;
      if (dist <= b.radius + 10) {
        if (b.wordData.word == _targetWord.word) {
          _onCorrectWordTapped(b);
        } else {
          _onWrongWordTapped(b);
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF03142B),
      body: GestureDetector(
        onTapDown: _handleTapDown,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // 1. 全屏深海水下渲染（水流、波浪水面、上升气泡、死泡堆积、弹道、破裂粒子）
            Positioned.fill(
              child: CustomPaint(
                painter: _UnderseaScenePainter(
                  bubbles: _bubbles,
                  particles: _particles,
                  floatingTexts: _floatingTexts,
                  deadBubbles: _deadBubbles,
                  projectiles: _projectiles,
                  waterSurfaceY: _waterSurfaceY,
                  wavePhase: _wavePhase,
                ),
              ),
            ),

            // 2. 顶部返回与控制栏
            Positioned(
              top: topPadding + 6,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '海底泡泡对战预览',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                    onPressed: _resetGame,
                  ),
                ],
              ),
            ),

            // 3. 顶部对战 HUD 状态栏（对手 vs 我方 + 倒计时）
            Positioned(
              top: topPadding + 44,
              left: 16,
              right: 16,
              child: _buildVsStatusBar(),
            ),

            // 4. 当前目标词提示胶囊（仅中文释义）
            Positioned(
              top: topPadding + 112,
              left: 30,
              right: 30,
              child: _buildTargetPromptCard(),
            ),

            // 5. 水面下沉压迫警示条
            if (_deadBubbles.isNotEmpty)
              Positioned(
                top: max(topPadding + 160, _waterSurfaceY - 32),
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      '⚠️ 空气区死泡: ${_deadBubbles.length} 个 | 水面下沉 ${(_waterSurfaceY - baseWaterY).toInt()}px',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

            // 6. 底部战术道具栏（🚀 砸水雷 & 🎯 戳死泡）
            Positioned(
              bottom: bottomPadding + 14,
              left: 16,
              right: 16,
              child: _buildPropsBar(size),
            ),

            // 7. 游戏结束弹窗
            if (_isGameOver)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Center(
                    child: Container(
                      width: size.width * 0.82,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F223D),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isPlayerWon
                                ? Icons.emoji_events_rounded
                                : Icons.sentiment_dissatisfied_rounded,
                            size: 56,
                            color: _isPlayerWon
                                ? const Color(0xFFFBBF24)
                                : Colors.blueGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isPlayerWon ? '挑战胜利！' : '本局惜败',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _gameOverReason.isNotEmpty
                                ? _gameOverReason
                                : '我方得分: $_scorePlayer  |  对手得分: $_scoreOpponent',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _resetGame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text('再来一局体验',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 顶部对战拉锯栏（双方比分 + 头像 + 倒计时）
  Widget _buildVsStatusBar() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧：对手（受击时左右抖动）
          Transform.translate(
            offset: Offset(_opponentShake > 0 ? sin(_opponentShake * 40) * 6 : 0, 0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFF97316),
                  child: Icon(Icons.person_outline, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '对手(慢速躺平)',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '$_scoreOpponent',
                      style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFFB923C),
                          fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          // 中间 VS 徽标（生存淘汰制，无需多余倒计时）
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'VS',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const Spacer(),

          // 右侧：我方
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '我方(冲刺连击)',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500),
              ),
              Text(
                '$_scorePlayer',
                style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFF0284C7),
            child: Icon(Icons.face, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  /// 目标词提示卡片（仅出中文释义，不暴露英文单词）
  Widget _buildTargetPromptCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.touch_app_rounded, color: Color(0xFF38BDF8), size: 18),
          const SizedBox(width: 8),
          Text(
            '请戳破对应英文：',
            style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500),
          ),
          Text(
            _targetWord.meaning,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFBBF24),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部对战战术道具栏
  Widget _buildPropsBar(Size size) {
    return Row(
      children: [
        // 道具 1: 🚀 砸水雷 (攻击对手，压低对手水面 40px)
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_attackProps > 0) {
                setState(() {
                  _attackProps--;
                });
                _fireAttackMine(size);
              } else {
                _floatingTexts.add(FloatingText(
                  x: size.width * 0.3,
                  y: size.height - 100,
                  text: '连击即可获得水雷!',
                  color: Colors.white70,
                ));
              }
            },
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDC2626), Color(0xFFEA580C)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🚀', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    '砸水雷压对手 ($_attackProps)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 道具 2: 🎯 戳死泡 (净化飞针，刺破死泡抬升海面)
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_purgeProps > 0) {
                final success = _firePurgeNeedle(size);
                if (success) {
                  setState(() {
                    _purgeProps--;
                  });
                }
              } else {
                _floatingTexts.add(FloatingText(
                  x: size.width * 0.7,
                  y: size.height - 100,
                  text: '连击即可获得飞针!',
                  color: Colors.white70,
                ));
              }
            },
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    '戳死泡抬海面 ($_purgeProps)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 海底世界与泡泡高保真绘制器
class _UnderseaScenePainter extends CustomPainter {
  final List<BubbleItem> bubbles;
  final List<PopParticle> particles;
  final List<FloatingText> floatingTexts;
  final List<DeadBubbleItem> deadBubbles;
  final List<GameProjectile> projectiles;
  final double waterSurfaceY;
  final double wavePhase;

  _UnderseaScenePainter({
    required this.bubbles,
    required this.particles,
    required this.floatingTexts,
    required this.deadBubbles,
    required this.projectiles,
    required this.waterSurfaceY,
    required this.wavePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制深海背景多层渐变
    final Rect fullRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF042654), // 水面附近透光蓝
          Color(0xFF021B3D),
          Color(0xFF010E24), // 深渊沉暗蓝
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bgPaint);

    // 2. 绘制顶部透射下来的光柱 (Light Caustics)
    final lightRayPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    final rayPath = Path()
      ..moveTo(size.width * 0.1, 0)
      ..lineTo(size.width * 0.4, 0)
      ..lineTo(size.width * 0.65, size.height)
      ..lineTo(size.width * 0.25, size.height)
      ..close();
    canvas.drawPath(rayPath, lightRayPaint);

    final rayPath2 = Path()
      ..moveTo(size.width * 0.6, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(size.width * 0.95, size.height)
      ..lineTo(size.width * 0.5, size.height)
      ..close();
    canvas.drawPath(rayPath2, lightRayPaint);

    // 3. 绘制海床底部珊瑚与水草剪影
    _drawSeabed(canvas, size);

    // 4. 绘制上升彩色泡泡
    for (final b in bubbles) {
      _drawBubble(canvas, b);
    }

    // 5. 绘制水珠破裂粒子
    for (final p in particles) {
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, particlePaint);
    }

    // 6. 绘制水面波浪线与水面下沉遮罩 (Water Surface)
    _drawWaterSurface(canvas, size);

    // 7. 绘制空气区堆积的死泡泡（灰暗石化浮沫）
    for (final db in deadBubbles) {
      _drawDeadBubble(canvas, db);
    }

    // 8. 绘制弹道飞行物（净化金针 / 攻击水雷）
    for (final p in projectiles) {
      _drawProjectile(canvas, p);
    }

    // 9. 绘制漂浮跳字
    for (final ft in floatingTexts) {
      final textSpan = TextSpan(
        text: ft.text,
        style: TextStyle(
          color: ft.color.withValues(alpha: ft.life.clamp(0.0, 1.0)),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 4,
            ),
          ],
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ft.x - tp.width / 2, ft.y - tp.height / 2));
    }
  }

  /// 绘制单个精致透明彩色气泡
  void _drawBubble(Canvas canvas, BubbleItem b) {
    if (b.isPopping) {
      final scale = 1.0 + b.popProgress * 0.4;
      final alpha = (1.0 - b.popProgress).clamp(0.0, 1.0);
      final popPaint = Paint()
        ..color = b.baseColor.withValues(alpha: alpha * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(Offset(b.x, b.y), b.radius * scale, popPaint);
      return;
    }

    double scaleX = 1.0;
    double scaleY = 1.0;
    if (b.isWrongJiggle) {
      final phase = b.jiggleProgress * pi * 4;
      final delta = sin(phase) * 0.18 * (1.0 - b.jiggleProgress);
      scaleX = 1.0 + delta;
      scaleY = 1.0 - delta;
    }

    canvas.save();
    canvas.translate(b.x, b.y);
    canvas.scale(scaleX, scaleY);

    final bubbleRect = Rect.fromCircle(center: Offset.zero, radius: b.radius);

    // 泡体径向渐变
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          b.baseColor.withValues(alpha: 0.18),
          b.baseColor.withValues(alpha: 0.35),
          b.baseColor.withValues(alpha: 0.65),
        ],
        stops: const [0.0, 0.4, 0.8, 1.0],
      ).createShader(bubbleRect);
    canvas.drawCircle(Offset.zero, b.radius, bodyPaint);

    // 泡泡外轮廓光圈
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset.zero, b.radius, rimPaint);

    // 顶部高光
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final highlightRect = Rect.fromCenter(
      center: Offset(-b.radius * 0.32, -b.radius * 0.32),
      width: b.radius * 0.32,
      height: b.radius * 0.16,
    );
    canvas.save();
    canvas.rotate(-pi / 4);
    canvas.drawOval(highlightRect, highlightPaint);
    canvas.restore();

    // 绘制泡泡内的英文单词
    final textSpan = TextSpan(
      text: b.wordData.word,
      style: TextStyle(
        color: Colors.white,
        fontSize: b.radius > 45 ? 14 : 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: b.radius * 1.8);

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  /// 绘制空气区的死泡泡（灰暗石化浮沫）
  void _drawDeadBubble(Canvas canvas, DeadBubbleItem db) {
    if (db.isPopping) {
      final scale = 1.0 + db.popProgress * 0.5;
      final alpha = (1.0 - db.popProgress).clamp(0.0, 1.0);
      final popPaint = Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: alpha * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(Offset(db.x, db.y), db.radius * scale, popPaint);
      return;
    }

    final center = Offset(db.x, db.y);
    final rect = Rect.fromCircle(center: center, radius: db.radius);

    // 灰色石化渐变
    final deadPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.9,
        colors: [
          const Color(0xFF64748B),
          const Color(0xFF334155),
          const Color(0xFF0F172A),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, db.radius, deadPaint);

    // 粗糙灰色外环
    final rimPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, db.radius, rimPaint);

    // 单词字样
    final textSpan = TextSpan(
      text: db.word,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.75),
        fontSize: 10,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.lineThrough,
        decorationColor: Colors.redAccent,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: db.radius * 1.8);
    tp.paint(canvas, Offset(db.x - tp.width / 2, db.y - tp.height / 2));
  }

  /// 绘制弹道飞行物
  void _drawProjectile(Canvas canvas, GameProjectile p) {
    if (p.type == ProjectileType.needle) {
      // 金色飞针
      final needlePaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(p.x, p.y + 16),
        Offset(p.x, p.y - 10),
        needlePaint,
      );
      // 针尖星芒
      final glowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y - 10), 3.0, glowPaint);
    } else {
      // 黑色水雷
      final minePaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 10.0, minePaint);

      // 引信小火花
      final sparkPaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x + 8, p.y - 8), 3.5, sparkPaint);
    }
  }

  /// 绘制波浪水面与压顶惩罚区
  void _drawWaterSurface(Canvas canvas, Size size) {
    final Path wavePath = Path();
    wavePath.moveTo(0, 0);
    wavePath.lineTo(0, waterSurfaceY);

    const int waveSteps = 24;
    for (int i = 0; i <= waveSteps; i++) {
      final double x = size.width * (i / waveSteps);
      final double waveOffset = sin(wavePhase + (i / waveSteps) * 4 * pi) * 6.0;
      wavePath.lineTo(x, waterSurfaceY + waveOffset);
    }

    wavePath.lineTo(size.width, 0);
    wavePath.close();

    // 水面以上的暗色空气遮罩
    final surfacePaint = Paint()
      ..color = const Color(0xFF010A17).withValues(alpha: 0.88);
    canvas.drawPath(wavePath, surfacePaint);

    // 水面波光高光线
    final waveLinePath = Path();
    waveLinePath.moveTo(0, waterSurfaceY);
    for (int i = 0; i <= waveSteps; i++) {
      final double x = size.width * (i / waveSteps);
      final double waveOffset = sin(wavePhase + (i / waveSteps) * 4 * pi) * 6.0;
      waveLinePath.lineTo(x, waterSurfaceY + waveOffset);
    }
    final waveLinePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(waveLinePath, waveLinePaint);
  }

  /// 绘制海底珊瑚沙滩剪影
  void _drawSeabed(Canvas canvas, Size size) {
    final seabedPaint = Paint()
      ..color = const Color(0xFF010915)
      ..style = PaintingStyle.fill;

    final seabedPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height - 40)
      ..quadraticBezierTo(size.width * 0.25, size.height - 65, size.width * 0.5, size.height - 45)
      ..quadraticBezierTo(size.width * 0.75, size.height - 25, size.width, size.height - 50)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(seabedPath, seabedPaint);

    // 海藻草丛剪影
    final weedPaint = Paint()
      ..color = const Color(0xFF031A26).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.15, size.height - 30), 24, weedPaint);
    canvas.drawCircle(Offset(size.width * 0.82, size.height - 35), 28, weedPaint);
  }

  @override
  bool shouldRepaint(covariant _UnderseaScenePainter oldDelegate) => true;
}
