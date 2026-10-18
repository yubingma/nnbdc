import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/tts.dart';
import '../api/vo.dart';
import '../global.dart';
import '../util/prefs.dart';
import '../util/word_pack_queue.dart';

/// 削砖块 · 下落方块实体
class BrickItem {
  final int id;
  final String word;
  final bool isTarget;
  double x;
  double y;
  final double baseX;
  final double radius;
  final double speed;
  final double swingAmplitude;
  final double swingFreq;
  final double phase;
  final Color baseColor;
  bool isPopping = false;
  double popProgress = 0.0;
  bool isWrongJiggle = false;
  double jiggleProgress = 0.0;

  BrickItem({
    required this.id,
    required this.word,
    required this.isTarget,
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

/// 碎砖爆破微粒
class BrickParticle {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  Color color;
  double life;
  final double maxLife;

  BrickParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.color,
    required this.life,
  }) : maxLife = life;
}

/// 飘字动效
class BrickFloatingText {
  double x;
  double y;
  final String text;
  final Color color;
  double life = 1.0;

  BrickFloatingText({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
  });
}

/// 竞技场散落微光粒子
class BrickAmbientParticle {
  double x;
  double y;
  double radius;
  double speed;
  double phase;
  double swingAmp;
  double alpha;

  BrickAmbientParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.swingAmp,
    required this.alpha,
  });
}

/// 削砖块 · 经典下落方块对战独立页面
class BrickPage extends StatefulWidget {
  const BrickPage({super.key});

  @override
  BrickPageState createState() => BrickPageState();
}

class BrickPageState extends State<BrickPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  bool dataLoaded = false;
  late GameHallVo gameHall;
  late int? exceptRoom;
  Map<String, dynamic>? extraArgs;
  bool isExercise = false;

  bool get isPrivateRoomHost => extraArgs?['mode'] == 'createPrivate';
  bool get isPrivateRoomGuest => extraArgs?['joinRoomId'] != null;
  bool get isInPrivateRoom => isPrivateRoomHost || isPrivateRoomGuest;

  bool isPlaying = false;
  bool myStarted = false;
  bool opponentStarted = false;
  int myHp = 10;
  int opponentHp = 10;
  static const int maxHp = 10;
  int myCombo = 0;
  int propsStarfish = 0;
  int propsMine = 0;

  String myUserId = '';
  String myNickName = '';
  String opponentUserId = '';
  String opponentNickName = '等待对手加入...';
  int? roomId;
  String gameState = 'waiting';

  WordVo? currWord;
  final List<String> distractorWords = [];
  bool hasMistakeInCurrentWord = false;

  final List<BrickItem> bricks = [];
  final List<BrickParticle> particles = [];
  final List<BrickFloatingText> _floatingTexts = [];
  final List<BrickAmbientParticle> _ambientParticles = [];

  final Random rand = Random();
  int nextBrickId = 1;
  int myWordIndex = 0;

  double _hitFlash = 0.0;
  double _healFlash = 0.0;
  double _screenShake = 0.0;
  double opponentShake = 0.0;
  double wavePhase = 0.0;

  static const List<Color> brickColors = [
    Color(0xFF38BDF8),
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFFA78BFA),
  ];

  final WordPackQueue _wordPack = WordPackQueue();
  final List<Map<String, dynamic>> _pendingUserCmds = [];
  final Tts _tts = Tts();

  late final _BrickSocketStatusListener _socketStatusListener;
  bool isIntroPlaying = false;
  double introProgress = 0.0;
  final Duration introDuration = const Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tts.init();
    LoadingUtils.disableApiLoading();

    for (int i = 0; i < 24; i++) {
      _ambientParticles.add(BrickAmbientParticle(
        x: rand.nextDouble() * 400,
        y: rand.nextDouble() * 800,
        radius: 1.5 + rand.nextDouble() * 2.5,
        speed: 12.0 + rand.nextDouble() * 22.0,
        phase: rand.nextDouble() * 2 * pi,
        swingAmp: 3.0 + rand.nextDouble() * 6.0,
        alpha: 0.15 + rand.nextDouble() * 0.35,
      ));
    }

    SocketIoClient.instance.connect();
    SocketIoClient.instance.setInRussiaGame(true);
    _socketStatusListener = _BrickSocketStatusListener(this);
    SocketIoClient.instance.registerSocketStatusListener(_socketStatusListener);

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    if (dataLoaded) return;
    final routeArgs = GoRouterState.of(context).extra;
    if (routeArgs == null || routeArgs is! List || routeArgs.isEmpty) {
      ToastUtil.error('进入房间参数错误');
      if (mounted) context.pop();
      return;
    }

    gameHall = routeArgs[0] as GameHallVo;
    exceptRoom = routeArgs.length > 1 ? routeArgs[1] as int? : null;
    if (routeArgs.length > 2 && routeArgs[2] is Map<String, dynamic>) {
      extraArgs = routeArgs[2] as Map<String, dynamic>;
    }

    final user = Global.getLoggedInUser();
    myUserId = user?.id ?? '';
    myNickName = user?.nickName ?? '我';

    _setupSocketListeners();
    _enterHallAndRoom();

    if (mounted) {
      setState(() {
        dataLoaded = true;
      });
    }
  }

  void _setupSocketListeners() {
    final socket = SocketIoClient.instance.socket;

    socket.off('roomId');
    socket.on('roomId', (data) {
      if (!mounted) return;
      setState(() {
        roomId = (data is num) ? data.toInt() : int.tryParse(data.toString());
      });
    });

    socket.off('enterWait');
    socket.on('enterWait', (data) {
      if (!mounted || isPlaying) return;
      setState(() {
        gameState = 'waiting';
        myStarted = false;
        opponentStarted = false;
        opponentUserId = '';
        opponentNickName = '等待对手加入...';
      });
    });

    socket.off('enterReady');
    socket.on('enterReady', (data) {
      if (!mounted || isPlaying) return;
      setState(() {
        gameState = 'ready';
        myStarted = false;
        opponentStarted = false;
        if (opponentNickName == '等待对手加入...' || opponentNickName.isEmpty) {
          opponentNickName = '对手';
        }
      });
    });

    socket.off('enterRoom');
    socket.on('enterRoom', (data) {
      if (!mounted || data == null) return;
      String? incomingUserId;
      String? incomingNickName;
      if (data is List && data.isNotEmpty) {
        incomingUserId = data[0]?.toString();
        if (data.length > 1) {
          incomingNickName = data[1]?.toString();
        }
      } else if (data is Map) {
        incomingUserId = (data['id'] ?? data['userId'])?.toString();
        incomingNickName = (data['displayNickName'] ?? data['nickName'])?.toString();
      }

      if (incomingUserId != null && incomingUserId != myUserId) {
        setState(() {
          opponentUserId = incomingUserId!;
          opponentNickName = (incomingNickName != null && incomingNickName.isNotEmpty)
              ? incomingNickName
              : '对手';
          opponentStarted = false;
          gameState = 'ready';
        });
      }
    });

    socket.off('userStarted');
    socket.on('userStarted', (userId) {
      if (!mounted) return;
      final idStr = userId?.toString();
      if (idStr == myUserId) {
        setState(() {
          myStarted = true;
        });
      } else {
        setState(() {
          opponentStarted = true;
        });
      }
    });

    socket.off('sysCmd');
    socket.on('sysCmd', (cmd) {
      if (!mounted) return;
      if (cmd == 'BEGIN') {
        isExercise = false;
        _onGameStart();
      } else if (cmd == 'BEGIN_EXERCISE') {
        isExercise = true;
        _onGameStart();
      }
    });

    socket.off('wordPack');
    socket.on('wordPack', (data) {
      if (!mounted || !isPlaying) return;
      _handleWordPack(data);
    });

    socket.off('stackSync');
    socket.on('stackSync', (data) {
      if (!mounted || !isPlaying || data == null || data is! List) return;
      final userId = data[0]?.toString();
      final stackCount = (data.length > 1 && data[1] is num) ? (data[1] as num).toInt() : 0;
      final remainingHp = max(0, maxHp - stackCount);
      if (userId == myUserId) {
        setState(() => myHp = remainingHp);
      } else {
        setState(() => opponentHp = remainingHp);
      }
    });

    socket.off('gameResultNotice');
    socket.on('gameResultNotice', (data) {
      if (!mounted) return;
      _handleGameOver(data);
    });

    socket.off('leaveRoom');
    socket.on('leaveRoom', (data) {
      if (!mounted || isPlaying) return;
      setState(() {
        opponentUserId = '';
        opponentNickName = '等待对手加入...';
        opponentStarted = false;
        gameState = 'waiting';
      });
    });
  }

  void _cleanupSocketListeners() {
    final socket = SocketIoClient.instance.socket;
    socket.off('roomId');
    socket.off('enterWait');
    socket.off('enterReady');
    socket.off('enterRoom');
    socket.off('userStarted');
    socket.off('sysCmd');
    socket.off('wordPack');
    socket.off('stackSync');
    socket.off('gameResultNotice');
    socket.off('leaveRoom');
  }

  void _enterHallAndRoom() {
    final mode = extraArgs?['mode'];
    final joinId = extraArgs?['joinRoomId'];

    if (mode == 'createPrivate') {
      sendUserCmd('CREATE_PRIVATE_ROOM', [gameHall.id]);
    } else if (joinId != null) {
      sendUserCmd('JOIN_ROOM_BY_ID', [gameHall.id, joinId.toString()]);
    } else {
      sendUserCmd('ENTER_GAME_HALL', [gameHall.id, (exceptRoom ?? -1).toString()]);
    }
  }

  void sendUserCmd(String cmd, List<dynamic> args) {
    final socket = SocketIoClient.instance.socket;
    final payload = {
      'system': 'russia',
      'cmd': cmd,
      'args': args,
    };
    if (!socket.connected) {
      _pendingUserCmds.add(payload);
      Global.logger.w('SocketIoClient: 连接已断开，指令[$cmd]排队等待重连补发');
      return;
    }
    socket.emit('userCmd', payload);
  }

  void _flushPendingUserCmds() {
    if (_pendingUserCmds.isEmpty) return;
    final socket = SocketIoClient.instance.socket;
    if (!socket.connected) return;

    final queue = List<Map<String, dynamic>>.from(_pendingUserCmds);
    _pendingUserCmds.clear();
    Global.logger.d('SocketIoClient: 重连后补发 ${queue.length} 条排队指令');
    for (final payload in queue) {
      socket.emit('userCmd', payload);
    }
  }

  void _onSocketReconnected() {
    if (!mounted) return;
    _flushPendingUserCmds();
  }

  void _onSocketDisconnected() {}

  void _onGameStart() {
    setState(() {
      isPlaying = true;
      myHp = maxHp;
      opponentHp = maxHp;
      myCombo = 0;
      propsMine = 0;
      propsStarfish = 0;
      myWordIndex = 0;
      isIntroPlaying = true;
      introProgress = 0.0;
      bricks.clear();
      particles.clear();
      _floatingTexts.clear();
    });

    _wordPack.reset();
    _requestWordPack(0);
  }

  void _requestWordPack(int fromIndex) {
    _wordPack.markRequested(fromIndex);
    sendUserCmd('GET_WORD_PACK', [fromIndex]);
  }

  void _handleWordPack(dynamic data) {
    if (data is! List || data.length < 2) return;
    _wordPack.accept((data[0] as num).toInt(), List<dynamic>.from(data[1] as List));
    _playNextWordFromPack();
  }

  void _playNextWordFromPack() {
    if (!mounted || !isPlaying || isIntroPlaying) return;
    if (currWord != null) return;

    final entry = _wordPack.wordAt(myWordIndex);
    if (entry != null) {
      _applyWordEntry(entry);
    }

    final requestFrom = _wordPack.packRequestFor(myWordIndex);
    if (requestFrom != null) {
      sendUserCmd('GET_WORD_PACK', [requestFrom]);
    }
  }

  void _applyWordEntry(dynamic data) {
    try {
      final wordVo = WordVo.fromJson(data[0]);
      currWord = wordVo;
      distractorWords.clear();
      if (data.length >= 4 && data[3] is List) {
        final list = data[3] as List;
        for (final item in list) {
          distractorWords.add(item.toString());
        }
      } else {
        final fallbacks = ['ocean', 'sunshine', 'courage', 'miracle', 'journey'];
        for (final w in fallbacks) {
          if (w != wordVo.spell && distractorWords.length < 3) {
            distractorWords.add(w);
          }
        }
      }

      final mediaQuery = MediaQuery.maybeOf(context);
      final size = mediaQuery?.size ?? const Size(390, 844);
      _spawnBricksForRound(size);

      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && isPlaying && currWord != null) {
          final meaning = currWord!.meaningStr ?? currWord!.getMeaningStr();
          if (meaning.isNotEmpty) {
            final firstPart = meaning.split(RegExp(r'[;；,\n]')).first.trim();
            _tts.speak(firstPart);
          }
        }
      });
    } catch (e) {
      Global.logger.e('削砖块解析单词出错: $e');
    }
  }

  void _reportAnswer(String answerResult) {
    final word = currWord;
    if (word == null) return;
    final int wordIndex = myWordIndex++;
    sendUserCmd('ANSWER', [wordIndex, answerResult, word.spell]);
    currWord = null;
    _playNextWordFromPack();
  }

  void _spawnBricksForRound(Size size) {
    bricks.clear();
    hasMistakeInCurrentWord = false;
    if (currWord == null) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final topPadding = max(mediaQuery?.padding.top ?? 44.0, 16.0);
    final double barrierY = topPadding + 130.0;

    final roundOptions = [currWord!.spell, ...distractorWords.take(2)]..shuffle(rand);
    final slotXOffsets = [0.26, 0.50, 0.74]..shuffle(rand);
    final speeds = [40.0, 50.0, 60.0]..shuffle(rand);

    for (int i = 0; i < roundOptions.length && i < 3; i++) {
      const double radius = 48.0;
      final double baseX = size.width * slotXOffsets[i] + (rand.nextDouble() - 0.5) * 6.0;
      final double startY = barrierY + 28.0 + (rand.nextDouble() - 0.5) * 6.0;
      final Color color = brickColors[i % brickColors.length];

      bricks.add(BrickItem(
        id: nextBrickId++,
        word: roundOptions[i],
        isTarget: roundOptions[i] == currWord!.spell,
        x: baseX,
        y: startY,
        baseX: baseX,
        radius: radius,
        speed: speeds[i],
        swingAmplitude: 3.0 + rand.nextDouble() * 3.0,
        swingFreq: 1.0 + rand.nextDouble() * 0.5,
        phase: rand.nextDouble() * 2 * pi,
        baseColor: color,
      ));
    }
  }

  void _onTick(Duration elapsed) {
    final double dt = (_lastElapsed == Duration.zero)
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);
    final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
    final double bottomBarTopY = size.height - (max(bottomPadding, 10.0) + 54.0);

    wavePhase += dt * 2.2;
    for (final ap in _ambientParticles) {
      ap.y += ap.speed * dt;
      ap.x += sin(ap.phase + wavePhase) * (ap.swingAmp * dt);
      if (ap.y > size.height + 20) {
        ap.y = -20;
        ap.x = rand.nextDouble() * size.width;
      }
    }

    if (_hitFlash > 0) _hitFlash = max(0.0, _hitFlash - dt * 1.5);
    if (_healFlash > 0) _healFlash = max(0.0, _healFlash - dt * 1.5);
    if (_screenShake > 0) _screenShake = max(0.0, _screenShake - dt * 4.0);

    if (!isPlaying) {
      if (mounted) setState(() {});
      return;
    }

    if (isIntroPlaying) {
      introProgress = min(1.0, introProgress + dt * 1000 / introDuration.inMilliseconds);
      if (introProgress >= 1.0) {
        isIntroPlaying = false;
        _playNextWordFromPack();
      }
    }

    // 砖块重力下落与触底判定
    bool targetBrickExpired = false;
    for (int i = bricks.length - 1; i >= 0; i--) {
      final b = bricks[i];
      if (b.isPopping) {
        b.popProgress += dt * 5.0;
        if (b.popProgress >= 1.0) bricks.removeAt(i);
        continue;
      }
      if (b.isWrongJiggle) {
        b.jiggleProgress += dt * 8.0;
        if (b.jiggleProgress >= 1.0) {
          b.isWrongJiggle = false;
          b.jiggleProgress = 0.0;
        }
      }

      b.y += b.speed * dt;
      b.x = b.baseX + sin(b.phase + wavePhase * b.swingFreq) * b.swingAmplitude;

      // 触及底部警戒线
      if (b.y + b.radius * 0.7 >= bottomBarTopY) {
        if (b.isTarget) targetBrickExpired = true;
        bricks.removeAt(i);
      }
    }

    if (targetBrickExpired && currWord != null) {
      _applyDamage(1, reason: '方块触底 -1 HP!');
      _reportAnswer('WRONG');
    }

    // 碎砖微粒
    for (int i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        particles.removeAt(i);
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }

    // 飘字动效
    for (int i = _floatingTexts.length - 1; i >= 0; i--) {
      final ft = _floatingTexts[i];
      ft.life -= dt * 1.5;
      ft.y -= 35.0 * dt;
      if (ft.life <= 0) _floatingTexts.removeAt(i);
    }

    if (mounted) setState(() {});
  }

  void _onCorrectBrickTapped(BrickItem brick) {
    if (!isPlaying || brick.isPopping) return;
    brick.isPopping = true;
    _spawnBrickExplosion(brick.x, brick.y, brick.baseColor);

    myCombo++;
    if (myCombo % 3 == 0) {
      if (rand.nextBool()) {
        propsMine++;
        _floatingTexts.add(BrickFloatingText(x: brick.x, y: brick.y, text: '💣 获得导弹!', color: const Color(0xFFEF4444)));
      } else {
        propsStarfish++;
        _floatingTexts.add(BrickFloatingText(x: brick.x, y: brick.y, text: '⭐ 获得神星!', color: const Color(0xFF10B981)));
      }
    } else {
      _floatingTexts.add(BrickFloatingText(x: brick.x, y: brick.y, text: '连击 +$myCombo', color: const Color(0xFF38BDF8)));
    }

    _reportAnswer(hasMistakeInCurrentWord ? 'WRONG' : 'CORRECT');
  }

  void _onWrongBrickTapped(BrickItem brick) {
    if (!isPlaying) return;
    hasMistakeInCurrentWord = true;
    brick.isWrongJiggle = true;
    brick.jiggleProgress = 0.0;
    _applyDamage(1, reason: '选错方块 -1 HP!');
  }

  void _spawnBrickExplosion(double x, double y, Color baseColor) {
    for (int i = 0; i < 16; i++) {
      final double angle = rand.nextDouble() * 2 * pi;
      final double speed = 60.0 + rand.nextDouble() * 140.0;
      particles.add(BrickParticle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        radius: 2.0 + rand.nextDouble() * 3.5,
        color: baseColor,
        life: 0.35 + rand.nextDouble() * 0.3,
      ));
    }
  }

  void _applyDamage(int amount, {String reason = '受损 -1 HP!'}) {
    if (!isPlaying) return;
    setState(() {
      myHp = max(0, myHp - amount);
      myCombo = 0;
      _hitFlash = 1.0;
      _screenShake = 1.0;
    });

    _floatingTexts.add(BrickFloatingText(
      x: 100,
      y: 200,
      text: reason,
      color: const Color(0xFFEF4444),
    ));

    sendUserCmd('REPORT_STACK_ROWS', [maxHp - myHp]);
    if (myHp <= 0) {
      sendUserCmd('GAME_OVER', ['A']);
    }
  }

  void _useProps(int propsIdx) {
    if (!isPlaying) return;
    if (propsIdx == 0 && propsMine > 0) {
      propsMine--;
      sendUserCmd('USE_PROPS', [propsIdx]);
      _floatingTexts.add(BrickFloatingText(x: 200, y: 300, text: '🚀 导弹发射!', color: const Color(0xFFEF4444)));
      setState(() => opponentHp = max(0, opponentHp - 1));
    } else if (propsIdx == 1 && propsStarfish > 0) {
      propsStarfish--;
      sendUserCmd('USE_PROPS', [propsIdx]);
      _floatingTexts.add(BrickFloatingText(x: 200, y: 300, text: '✨ 防线修复 +1!', color: const Color(0xFF10B981)));
      setState(() => myHp = min(maxHp, myHp + 1));
      sendUserCmd('REPORT_STACK_ROWS', [maxHp - myHp]);
    }
  }

  void _handleGameOver(dynamic data) {
    setState(() {
      isPlaying = false;
    });

    bool isWin = false;
    if (data is List && data.isNotEmpty) {
      isWin = data[0]?.toString() == myUserId;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          isWin ? '🏆 削砖大捷！' : '💥 防线失守',
          style: TextStyle(
            color: isWin ? const Color(0xFFFBBF24) : const Color(0xFFEF4444),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          isWin ? '恭喜你成功击垮对方防线，赢得本局胜利！' : '方块堆叠超限，再接再厉削退方块！',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('返回大厅', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tts.stop();
    SocketIoClient.instance.setInRussiaGame(false);
    SocketIoClient.instance.removeSocketStatusListener(_socketStatusListener);
    _cleanupSocketListeners();
    sendUserCmd('LEAVE_HALL', []);
    SocketIoClient.instance.disconnect();
    LoadingUtils.enableApiLoading();
    Prefs.applyFullScreenMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!dataLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final topPadding = max(mediaQuery.padding.top, 16.0);
    final bottomPadding = max(mediaQuery.padding.bottom, 10.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 独立专属方块竞技场绘制
          GestureDetector(
            onTapDown: (details) {
              final pos = details.localPosition;
              for (final b in bricks) {
                if (b.isPopping) continue;
                final rect = Rect.fromCenter(
                  center: Offset(b.x, b.y),
                  width: b.radius * 2.1,
                  height: b.radius * 1.35,
                );
                if (rect.contains(pos)) {
                  if (b.isTarget) {
                    _onCorrectBrickTapped(b);
                  } else {
                    _onWrongBrickTapped(b);
                  }
                  break;
                }
              }
            },
            child: CustomPaint(
              painter: _BrickScenePainter(
                bricks: bricks,
                particles: particles,
                floatingTexts: _floatingTexts,
                ambientParticles: _ambientParticles,
                bottomBarTopY: mediaQuery.size.height - bottomPadding - 54.0,
              ),
            ),
          ),

          // 2. 顶部房间信息与状态栏
          Positioned(
            top: topPadding + 4,
            left: 12,
            right: 12,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                  onPressed: () => context.pop(),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.grid_view_rounded, color: Color(0xFFF59E0B), size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '削砖块 · ${gameHall.hallName}${roomId != null ? ' · 房号$roomId' : ''}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!isPlaying)
                  ElevatedButton(
                    onPressed: () {
                      sendUserCmd('START_GAME', []);
                      setState(() => myStarted = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(myStarted ? '等待对手...' : '开始对战', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
              ],
            ),
          ),

          // 3. 双方血量槽（10格方块堆叠展示）
          Positioned(
            top: topPadding + 52,
            left: 20,
            right: 20,
            child: Row(
              children: [
                _buildHpIndicator(label: '我方防线', hp: myHp, isMine: true),
                const SizedBox(width: 20),
                _buildHpIndicator(label: opponentNickName, hp: opponentHp, isMine: false),
              ],
            ),
          ),

          // 4. 当前释义卡片
          if (isPlaying && currWord != null)
            Positioned(
              top: topPadding + 98,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4), width: 1.2),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('选择对应的英文方块消除', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      currWord!.meaningStr ?? currWord!.getMeaningStr(),
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

          // 5. 底部道具操作栏
          Positioned(
            bottom: bottomPadding + 6,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPropBtn(
                  icon: Icons.rocket_launch_rounded,
                  label: '轰击对手',
                  count: propsMine,
                  color: const Color(0xFFEF4444),
                  onTap: () => _useProps(0),
                ),
                _buildPropBtn(
                  icon: Icons.auto_awesome_rounded,
                  label: '修复防线',
                  count: propsStarfish,
                  color: const Color(0xFF10B981),
                  onTap: () => _useProps(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHpIndicator({required String label, required int hp, required bool isMine}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: List.generate(10, (idx) {
              final active = idx < hp;
              return Expanded(
                child: Container(
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? (isMine ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPropBtn({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: count > 0 ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: count > 0 ? color.withValues(alpha: 0.7) : Colors.white10,
            width: count > 0 ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: count > 0 ? color : Colors.white24, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: count > 0 ? Colors.white : Colors.white24, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: count > 0 ? color : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 削砖块专属场景绘制器
class _BrickScenePainter extends CustomPainter {
  final List<BrickItem> bricks;
  final List<BrickParticle> particles;
  final List<BrickFloatingText> floatingTexts;
  final List<BrickAmbientParticle> ambientParticles;
  final double bottomBarTopY;

  _BrickScenePainter({
    required this.bricks,
    required this.particles,
    required this.floatingTexts,
    required this.ambientParticles,
    required this.bottomBarTopY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 深邃的方块竞技场科技背景渐变
    final Rect fullRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0F172A),
          Color(0xFF1E1B4B),
          Color(0xFF0F172A),
        ],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bgPaint);

    // 2. 纵深科技网格线条
    final gridPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.04)
      ..strokeWidth = 1.0;
    for (double x = 0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // 3. 散落微星光浮尘
    for (final ap in ambientParticles) {
      final pPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: ap.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(ap.x, ap.y), ap.radius, pPaint);
    }

    // 4. 底部警戒防线基座（方块触底警戒线）
    final barrierPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFEF4444).withValues(alpha: 0.1),
          const Color(0xFFEF4444).withValues(alpha: 0.8),
          const Color(0xFFEF4444).withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, bottomBarTopY, size.width, 2))
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, bottomBarTopY), Offset(size.width, bottomBarTopY), barrierPaint);

    // 5. 下落方块绘制
    for (final b in bricks) {
      _drawBrick(canvas, b);
    }

    // 6. 爆破微粒
    for (final p in particles) {
      final pPaint = Paint()
        ..color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, pPaint);
    }

    // 7. 飘字
    for (final ft in floatingTexts) {
      final tp = TextPainter(
        text: TextSpan(
          text: ft.text,
          style: TextStyle(
            color: ft.color.withValues(alpha: ft.life.clamp(0.0, 1.0)),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ft.x - tp.width / 2, ft.y));
    }
  }

  void _drawBrick(Canvas canvas, BrickItem b) {
    if (b.isPopping) {
      final scale = 1.0 + b.popProgress * 0.4;
      final alpha = (1.0 - b.popProgress).clamp(0.0, 1.0);
      final popPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(b.x, b.y),
            width: b.radius * 2.1 * scale,
            height: b.radius * 1.35 * scale,
          ),
          const Radius.circular(12),
        ),
        popPaint,
      );
      return;
    }

    double scaleX = 1.0;
    double scaleY = 1.0;
    if (b.isWrongJiggle) {
      final phase = b.jiggleProgress * pi * 4;
      final delta = sin(phase) * 0.16 * (1.0 - b.jiggleProgress);
      scaleX = 1.0 + delta;
      scaleY = 1.0 - delta;
    }

    canvas.save();
    canvas.translate(b.x, b.y);
    canvas.scale(scaleX, scaleY);

    final double brickW = b.radius * 2.1;
    final double brickH = b.radius * 1.35;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: brickW, height: brickH),
      const Radius.circular(14),
    );

    // 阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(rrect.shift(const Offset(0, 3)), shadowPaint);

    // 本体渐变
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          b.baseColor.withValues(alpha: 0.95),
          Color.lerp(b.baseColor, Colors.black, 0.25)!,
        ],
      ).createShader(rrect.outerRect);
    canvas.drawRRect(rrect, fillPaint);

    // 高光横条
    final hlRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-brickW / 2 + 2, -brickH / 2 + 2, brickW - 4, brickH * 0.38),
      const Radius.circular(11),
    );
    final hlPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(hlRect.outerRect);
    canvas.drawRRect(hlRect, hlPaint);

    // 微边框
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(rrect, borderPaint);

    // 英文单词
    final textPainter = TextPainter(
      text: TextSpan(
        text: b.word,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          shadows: [
            Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1.2)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: brickW - 12);

    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrickScenePainter oldDelegate) => true;
}

class _BrickSocketStatusListener implements SocketStatusListener {
  _BrickSocketStatusListener(this.page);

  final BrickPageState page;

  @override
  void onConnected() => page._onSocketReconnected();

  @override
  void onDisconnected() => page._onSocketDisconnected();
}
