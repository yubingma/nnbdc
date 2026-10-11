import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../services/throttled_sync_service.dart';
import '../util/app_clock.dart';
import 'index.dart';

/// 泡泡实体
class BubbleItem {
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

  BubbleItem({
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

/// 爆破粒子
class PopParticle {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  Color color;
  double life;
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

/// 飘字动效
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

/// 空气区石化死泡泡
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

/// 飞行弹道
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

/// 海底微小散落氛围气泡
class AmbientBubble {
  double x;
  double y;
  double radius;
  double speed;
  double phase;
  double swingAmp;
  double alpha;

  AmbientBubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.swingAmp,
    required this.alpha,
  });
}

/// 泡泡对战（全新升级取代旧版俄罗斯方块）
class RussiaPage extends StatefulWidget {
  const RussiaPage({super.key});

  @override
  RussiaPageState createState() => RussiaPageState();
}

class RussiaPageState extends State<RussiaPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  bool dataLoaded = false;
  late GameHallVo gameHall;
  late int? exceptRoom;
  Map<String, dynamic>? extraArgs;
  bool isExercise = false;

  // 房间与通信状态
  int? roomId;
  String gameState = 'waiting'; // waiting, ready, playing, settled
  bool isPlaying = false;
  bool isShowingResult = false;
  bool? isWonInLastGame;
  int scoreAdjust = 0;
  int cowDungAdjust = 0;

  // 双方玩家数据
  String myUserId = '';
  String myNickName = '';
  int myScore = 0;
  int myCombo = 0;
  int myWordIndex = 0;
  int attackProps = 1;
  int purgeProps = 1;
  bool myStarted = false;

  String opponentUserId = '';
  String opponentNickName = '等待对手加入...';
  int opponentScore = 0;
  double opponentShake = 0.0;
  bool opponentStarted = false;

  // 当前目标词与泡泡
  WordVo? currWord;
  List<String> distractorWords = [];
  final List<BubbleItem> bubbles = [];
  final List<PopParticle> particles = [];
  final List<FloatingText> floatingTexts = [];
  final List<DeadBubbleItem> deadBubbles = [];
  final List<GameProjectile> projectiles = [];
  final List<AmbientBubble> ambientBubbles = [];
  int nextBubbleId = 0;

  // 水面惩罚线系统
  static const double baseWaterY = 140.0;
  double waterSurfaceY = baseWaterY;
  double targetWaterSurfaceY = baseWaterY;
  double wavePhase = 0.0;

  final Random rand = Random();
  final List<Color> bubbleColors = const [
    Color(0xFF38BDF8), // 晶莹透天蓝
    Color(0xFFFBBF24), // 暖金琥珀光
    Color(0xFFF472B6), // 霓裳浪漫粉
    Color(0xFF2DD4BF), // 清透薄荷绿
  ];

  @override
  void initState() {
    super.initState();
    _initAmbientBubbles();
    LoadingUtils.disableApiLoading();
    SocketIoClient.instance.connect();
    SocketIoClient.instance.setInRussiaGame(true);

    _ticker = createTicker(_onTick)..start();
  }

  void _initAmbientBubbles() {
    ambientBubbles.clear();
    for (int i = 0; i < 35; i++) {
      ambientBubbles.add(AmbientBubble(
        x: rand.nextDouble() * 400,
        y: rand.nextDouble() * 900,
        radius: 2.0 + rand.nextDouble() * 4.5,
        speed: 15.0 + rand.nextDouble() * 25.0,
        phase: rand.nextDouble() * 2 * pi,
        swingAmp: 3.0 + rand.nextDouble() * 5.0,
        alpha: 0.15 + rand.nextDouble() * 0.35,
      ));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadData();
  }

  @override
  void dispose() {
    _ticker.dispose();
    SocketIoClient.instance.setInRussiaGame(false);
    _cleanupSocketListeners();
    sendUserCmd('LEAVE_HALL', []);
    SocketIoClient.instance.disconnect();
    LoadingUtils.enableApiLoading();
    super.dispose();
  }

  Future<bool> checkArgs() async {
    final args = GoRouterState.of(context).extra;
    if (args == null || args is! List || args.length < 2) {
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        context.go('/index', extra: IndexPageArgs(3));
      });
      return false;
    }
    gameHall = args[0] as GameHallVo;
    exceptRoom = args[1] as int?;
    if (args.length >= 3 && args[2] is Map<String, dynamic>) {
      extraArgs = args[2] as Map<String, dynamic>;
    }
    return true;
  }

  Future<void> loadData() async {
    if (!await checkArgs()) return;
    if (dataLoaded) return;
    if (!mounted) return;

    final user = Global.getLoggedInUser();
    if (user != null) {
      myUserId = user.id;
      myNickName = user.nickName ?? '我方';
    }

    _setupSocketListeners();
    _enterRoom();

    setState(() {
      dataLoaded = true;
    });
  }

  void sendUserCmd(String cmd, List<dynamic> args) {
    final socket = SocketIoClient.instance.socket;
    if (!socket.connected) return;

    socket.emit('userCmd', {
      'system': 'russia',
      'cmd': cmd,
      'args': args,
    });
  }

  void _enterRoom() {
    if (extraArgs != null && extraArgs!['mode'] == 'createPrivate') {
      sendUserCmd('CREATE_PRIVATE_ROOM', [gameHall.id]);
    } else if (extraArgs != null && extraArgs!['joinRoomId'] != null) {
      sendUserCmd('JOIN_ROOM_BY_ID', [gameHall.id, extraArgs!['joinRoomId']]);
    } else {
      sendUserCmd('ENTER_GAME_HALL', [gameHall.id, exceptRoom ?? '']);
    }
  }

  void _setupSocketListeners() {
    final socket = SocketIoClient.instance.socket;

    socket.off('roomId');
    socket.on('roomId', (data) {
      if (!mounted) return;
      setState(() {
        roomId = data as int?;
      });
    });

    socket.off('enterWait');
    socket.on('enterWait', (data) {
      if (!mounted) return;
      setState(() {
        gameState = 'waiting';
        isPlaying = false;
        myStarted = false;
        opponentStarted = false;
        opponentUserId = '';
        opponentNickName = '等待对手加入...';
        opponentScore = 0;
      });
    });

    socket.off('enterReady');
    socket.on('enterReady', (data) {
      if (!mounted) return;
      setState(() {
        gameState = 'ready';
        isPlaying = false;
        myStarted = false;
        opponentStarted = false;
        // 既然房间已就绪，若此前因时序原因尚未解析出对手昵称，杜绝显示为矛盾的“等待对手加入...”
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
        });
      }
    });

    socket.off('userGameInfo');
    socket.on('userGameInfo', (data) {
      if (!mounted || data == null) return;
      try {
        final info = UserGameInfo.fromJson(Map<String, dynamic>.from(data as Map));
        if (info.userId == myUserId) {
          setState(() {
            if (info.nickName.isNotEmpty) {
              myNickName = info.nickName;
            }
          });
        } else {
          setState(() {
            opponentUserId = info.userId;
            if (info.nickName.isNotEmpty) {
              opponentNickName = info.nickName;
            }
          });
        }
      } catch (e) {
        Global.logger.w('解析 userGameInfo 异常: $e');
      }
    });

    socket.off('leaveRoom');
    socket.on('leaveRoom', (data) {
      if (!mounted) return;
      String? leftUserId;
      if (data is List && data.isNotEmpty) {
        leftUserId = data[0]?.toString();
      } else if (data is Map) {
        leftUserId = (data['id'] ?? data['userId'])?.toString();
      }
      if (leftUserId == null || leftUserId == opponentUserId) {
        setState(() {
          opponentUserId = '';
          opponentNickName = '等待对手加入...';
          opponentStarted = false;
          opponentScore = 0;
          if (gameState == 'ready') {
            gameState = 'waiting';
          }
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
        _onGameBegin();
      } else if (cmd == 'BEGIN_EXERCISE') {
        isExercise = true;
        _onGameBegin();
      }
    });

    socket.off('wordA');
    socket.on('wordA', (data) {
      if (!mounted || !isPlaying) return;
      _handleWordA(data);
    });

    socket.off('wordB');
    socket.on('wordB', (data) {
      if (!mounted || !isPlaying) return;
      _handleWordB(data);
    });

    socket.off('giveProps');
    socket.on('giveProps', (data) {
      if (!mounted) return;
      final int propsType = data[0] as int;
      final int count = data[1] as int;
      setState(() {
        if (propsType == 0) {
          attackProps = count;
        } else {
          purgeProps = count;
        }
      });
      floatingTexts.add(FloatingText(
        x: MediaQuery.of(context).size.width * 0.5,
        y: MediaQuery.of(context).size.height - 180,
        text: '🎁 获得道具【${propsType == 0 ? "重力水雷" : "净化飞针"}】!',
        color: const Color(0xFFFBBF24),
      ));
      StudyAudioSessionController.instance.playBlockingSound('magic.mp3', timeoutMs: 2000);
    });

    socket.off('propsUsed');
    socket.on('propsUsed', (data) {
      if (!mounted) return;
      final String fromUserId = data[0].toString();
      final int propsType = data[1] as int;

      if (fromUserId != myUserId) {
        // 对手使用了道具
        if (propsType == 0) {
          // 对方对我发射了水雷！
          _applyWaterPenalty(40.0);
          HapticFeedback.heavyImpact();
          floatingTexts.add(FloatingText(
            x: MediaQuery.of(context).size.width * 0.5,
            y: waterSurfaceY + 20,
            text: '💥 对手砸来重力水雷！海面下沉 40px',
            color: const Color(0xFFEF4444),
          ));
        } else {
          floatingTexts.add(FloatingText(
            x: 80,
            y: 90,
            text: '对手净化了死泡！',
            color: const Color(0xFF38BDF8),
          ));
        }
      }
    });

    socket.off('loser');
    socket.on('loser', (loserId) {
      if (!mounted) return;
      _handleLoser(loserId.toString());
    });

    socket.off('scoreAdjust');
    socket.on('scoreAdjust', (data) async {
      if (!mounted) return;
      final int sAdjust = data[0] as int;
      final int cAdjust = data[1] as int;

      setState(() {
        scoreAdjust = sAdjust;
        cowDungAdjust = cAdjust;
      });

      // 更新本地数据库
      try {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getLastLoggedInUser();
        if (user != null) {
          final newGameScore = user.gameScore + sAdjust;
          final newCowDung = user.cowDung + cAdjust;
          await db.usersDao.saveUser(
            user.copyWith(gameScore: newGameScore, cowDung: newCowDung),
            true,
          );
          if (cAdjust != 0) {
            final now = AppClock.now();
            final logEntity = UserCowDungLog(
              id: now.millisecondsSinceEpoch.toString(),
              userId: user.id,
              delta: cAdjust,
              cowDung: newCowDung,
              theTime: now,
              reason: cAdjust > 0 ? "游戏胜利奖励" : "游戏失败惩罚",
              createTime: now,
              updateTime: now,
            );
            await db.userCowDungLogsDao.insertEntity(logEntity, true);
          }
          ThrottledDbSyncService().requestSync();
        }
      } catch (e) {
        Global.logger.e('本地落库积分失败: $e');
      }
    });

    socket.off('noEnoughCowDung');
    socket.on('noEnoughCowDung', (cowDungPerGame) {
      ToastUtil.error('魔法泡泡不足，无法开始游戏！\n至少需要: ${cowDungPerGame ?? 10}');
    });
  }

  void _cleanupSocketListeners() {
    final socket = SocketIoClient.instance.socket;
    for (final event in [
      'roomId',
      'enterWait',
      'enterReady',
      'enterRoom',
      'userGameInfo',
      'leaveRoom',
      'userStarted',
      'sysCmd',
      'wordA',
      'wordB',
      'giveProps',
      'propsUsed',
      'loser',
      'scoreAdjust',
      'noEnoughCowDung',
    ]) {
      socket.off(event);
    }
  }

  void _handleStartButtonClicked() {
    if (gameState == 'ready') {
      setState(() {
        myStarted = true;
        isExercise = false;
      });
      sendUserCmd('START_GAME', []);
    } else {
      setState(() {
        myStarted = true;
        isExercise = true;
      });
      sendUserCmd('START_EXERCISE', []);
    }
  }

  void _onGameBegin() {
    setState(() {
      myScore = 0;
      opponentScore = 0;
      myCombo = 0;
      myWordIndex = 0;
      attackProps = 1;
      purgeProps = 1;
      isPlaying = true;
      gameState = 'playing';
      isShowingResult = false;
      myStarted = false;
      opponentStarted = false;
      deadBubbles.clear();
      projectiles.clear();
      bubbles.clear();
      particles.clear();
      floatingTexts.clear();
      waterSurfaceY = baseWaterY;
      targetWaterSurfaceY = baseWaterY;
    });

    // 索取第一个单词
    sendUserCmd('GET_NEXT_WORD', [myWordIndex++, '', '']);
  }

  void _handleWordA(dynamic data) {
    try {
      final wordVo = WordVo.fromJson(data[0]);
      currWord = wordVo;

      // 提取干扰词
      distractorWords.clear();
      if (data.length >= 4 && data[3] is List) {
        // 服务端新增的 3 个干扰词拼写
        final list = data[3] as List;
        for (final item in list) {
          distractorWords.add(item.toString());
        }
      } else {
        // 兼容降级备选词
        final fallbacks = ['ocean', 'sunshine', 'courage', 'miracle', 'journey'];
        for (final w in fallbacks) {
          if (w != wordVo.spell && distractorWords.length < 3) {
            distractorWords.add(w);
          }
        }
      }

      final mediaQuery = MediaQuery.maybeOf(context);
      final size = mediaQuery?.size ?? const Size(390, 844);
      _spawnBubblesForRound(size);

      // 延迟朗读正确发音
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && isPlaying && currWord != null) {
          StudyAudioSessionController.instance.playWordSound(currWord!);
        }
      });
    } catch (e) {
      Global.logger.e('解析 wordA 出错: $e');
    }
  }

  void _handleWordB(dynamic data) {
    try {
      final answerResult = data[0].toString();
      if (answerResult == 'true') {
        setState(() {
          opponentScore += 10;
        });
        floatingTexts.add(FloatingText(
          x: 80,
          y: 110,
          text: '+10',
          color: const Color(0xFFF97316),
        ));
      }
    } catch (_) {}
  }

  void _handleLoser(String loserId) {
    final bool amILoser = (loserId == myUserId);
    setState(() {
      isPlaying = false;
      isShowingResult = true;
      isWonInLastGame = !amILoser;
    });

    if (amILoser) {
      StudyAudioSessionController.instance.playBlockingSound('failed.mp3', timeoutMs: 2000);
      HapticFeedback.heavyImpact();
    } else {
      StudyAudioSessionController.instance.playBlockingSound('victory.mp3', timeoutMs: 2000);
      HapticFeedback.mediumImpact();
    }
  }

  void _spawnBubblesForRound(Size size) {
    bubbles.clear();
    if (currWord == null) return;

    final roundOptions = [currWord!.spell, ...distractorWords.take(3)]..shuffle(rand);
    // 采用交错错落的 X 位置，防止左右挤压
    final slotXOffsets = [0.22, 0.72, 0.38, 0.65]..shuffle(rand);

    for (int i = 0; i < roundOptions.length && i < 4; i++) {
      final double baseX = size.width * slotXOffsets[i] + (rand.nextDouble() - 0.5) * 16.0;
      const double radius = 47.0; // 饱满的梦幻大泡泡
      final Color color = bubbleColors[i % bubbleColors.length];
      final double speed = 36.0 + rand.nextDouble() * 20.0;
      final double startY = size.height + 40.0 + i * 85.0 + rand.nextDouble() * 25.0;

      bubbles.add(BubbleItem(
        id: nextBubbleId++,
        word: roundOptions[i],
        isTarget: roundOptions[i] == currWord!.spell,
        x: baseX,
        y: startY,
        baseX: baseX,
        radius: radius,
        speed: speed,
        swingAmplitude: 7.0 + rand.nextDouble() * 5.0,
        swingFreq: 1.1 + rand.nextDouble() * 0.6,
        phase: rand.nextDouble() * 2 * pi,
        baseColor: color,
      ));
    }
  }

  void _updateWaterPressure(Size size) {
    targetWaterSurfaceY = min(size.height * 0.72, baseWaterY + deadBubbles.length * 30.0);
  }

  void _applyWaterPenalty(double delta) {
    myCombo = 0;
    targetWaterSurfaceY = min(MediaQuery.of(context).size.height * 0.72, targetWaterSurfaceY + delta);
    HapticFeedback.lightImpact();
  }

  void _addDeadBubble(String word, Size size) {
    myCombo = 0;
    deadBubbles.add(DeadBubbleItem(
      id: nextBubbleId++,
      word: word,
      x: size.width * 0.5,
      y: waterSurfaceY - 30.0,
    ));
    _updateWaterPressure(size);
    sendUserCmd('REPORT_STACK_ROWS', [deadBubbles.length]);
  }

  bool _firePurgeNeedle(Size size) {
    if (deadBubbles.isEmpty) {
      floatingTexts.add(FloatingText(
        x: size.width * 0.5,
        y: waterSurfaceY - 20,
        text: '水面已无死泡负担!',
        color: const Color(0xFF38BDF8),
      ));
      return false;
    }
    final target = deadBubbles.first;
    projectiles.add(GameProjectile.needle(
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
    projectiles.add(GameProjectile.mine(
      startX: size.width * 0.5,
      startY: size.height - 120,
      targetX: 52,
      targetY: 52,
    ));
    sendUserCmd('USE_PROPS', [0]);
    HapticFeedback.heavyImpact();
    floatingTexts.add(FloatingText(
      x: size.width * 0.5,
      y: size.height - 160,
      text: '🚀 水雷出膛 轰击对手!',
      color: const Color(0xFFF87171),
    ));
  }

  void _onTick(Duration elapsed) {
    final double dt = (_lastElapsed == Duration.zero)
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);

    // 水波相位与氛围微泡漂浮（全局活跃）
    wavePhase += dt * 2.2;
    for (final ab in ambientBubbles) {
      ab.y -= ab.speed * dt;
      ab.x += sin(ab.phase + wavePhase * 1.5) * (ab.swingAmp * dt);
      if (ab.y < -20) {
        ab.y = size.height + 20 + rand.nextDouble() * 50;
        ab.x = rand.nextDouble() * size.width;
      }
    }

    if (!isPlaying) {
      if (mounted) setState(() {});
      return;
    }

    // 1. 水面波浪与平滑下沉
    waterSurfaceY += (targetWaterSurfaceY - waterSurfaceY) * min(1.0, dt * 6.0);

    // 触底死亡线判定
    if (waterSurfaceY >= size.height * 0.74) {
      sendUserCmd('GAME_OVER', ['A']);
      return;
    }

    if (opponentShake > 0) {
      opponentShake = max(0.0, opponentShake - dt);
    }

    // 2. 泡泡软斥力防重叠
    for (int i = 0; i < bubbles.length; i++) {
      for (int j = i + 1; j < bubbles.length; j++) {
        final b1 = bubbles[i];
        final b2 = bubbles[j];
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

    // 3. 泡泡物理运动与越界判定
    bool targetWordExpired = false;
    for (int i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      if (b.isPopping) {
        b.popProgress += dt * 5.0;
        if (b.popProgress >= 1.0) bubbles.removeAt(i);
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

      if (b.y - b.radius <= waterSurfaceY) {
        if (b.isTarget) {
          targetWordExpired = true;
          _addDeadBubble(b.word, size);
          floatingTexts.add(FloatingText(
            x: b.x,
            y: waterSurfaceY + 20,
            text: '漏词！死泡堆积压顶',
            color: const Color(0xFFEF4444),
          ));
        }
        _createBurstParticles(b.x, waterSurfaceY, b.baseColor, count: 6);
        bubbles.removeAt(i);
      }
    }

    if (targetWordExpired && currWord != null) {
      sendUserCmd('GET_NEXT_WORD', [myWordIndex++, 'false', currWord!.spell]);
    }

    // 4. 空气区死泡整齐排布
    final int deadCount = deadBubbles.length;
    for (int i = 0; i < deadCount; i++) {
      final db = deadBubbles[i];
      final int cols = min(5, max(1, deadCount));
      final int colIndex = i % 5;
      final int rowIndex = i ~/ 5;
      final double colWidth = (size.width - 60) / cols;
      db.x = 30 + colIndex * colWidth + colWidth / 2;
      db.y = waterSurfaceY - 26.0 - rowIndex * 40.0;

      if (db.isPopping) {
        db.popProgress += dt * 6.0;
        if (db.popProgress >= 1.0) {
          deadBubbles.removeAt(i);
          _updateWaterPressure(size);
          break;
        }
      }
    }

    // 5. 弹道飞行物更新
    for (int i = projectiles.length - 1; i >= 0; i--) {
      final p = projectiles[i];
      if (p.type == ProjectileType.needle) {
        p.y -= 750.0 * dt;
        if (p.y <= p.targetY) {
          p.targetBubble?.isPopping = true;
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFF94A3B8), count: 14);
          floatingTexts.add(FloatingText(
            x: p.targetX,
            y: p.targetY - 15,
            text: '💥 死泡破裂！海面抬升',
            color: const Color(0xFF38BDF8),
          ));
          projectiles.removeAt(i);
        }
      } else if (p.type == ProjectileType.mine) {
        p.progress += dt * 1.8;
        p.x = p.startX + (p.targetX - p.startX) * p.progress;
        p.y = p.startY + (p.targetY - p.startY) * p.progress - sin(p.progress * pi) * 120.0;
        if (p.progress >= 1.0) {
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFFEF4444), count: 18);
          opponentShake = 0.4;
          floatingTexts.add(FloatingText(
            x: 100,
            y: 50,
            text: '💥 对手水面被砸低 40px！',
            color: const Color(0xFFF87171),
          ));
          projectiles.removeAt(i);
        }
      }
    }

    // 6. 粒子更新
    for (int i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 20.0 * dt;
      p.life -= dt;
      if (p.life <= 0) particles.removeAt(i);
    }

    // 7. 飘字更新
    for (int i = floatingTexts.length - 1; i >= 0; i--) {
      final ft = floatingTexts[i];
      ft.y -= 30.0 * dt;
      ft.life -= dt * 1.2;
      if (ft.life <= 0) floatingTexts.removeAt(i);
    }

    setState(() {});
  }

  void _onCorrectWordTapped(BubbleItem b) {
    b.isPopping = true;
    myScore += 10;
    myCombo++;

    HapticFeedback.mediumImpact();
    _createBurstParticles(b.x, b.y, b.baseColor, count: 16);

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);

    if (myCombo >= 2 && deadBubbles.isNotEmpty) {
      _firePurgeNeedle(size);
    }

    final String comboBonus = myCombo > 1 ? ' Combo x$myCombo!' : '';
    floatingTexts.add(FloatingText(
      x: b.x,
      y: b.y - 15,
      text: '+10$comboBonus',
      color: const Color(0xFF38BDF8),
    ));

    // 向服务端上报答对并拉取下一词
    if (currWord != null) {
      sendUserCmd('GET_NEXT_WORD', [myWordIndex++, 'true', currWord!.spell]);
    }
  }

  void _onWrongWordTapped(BubbleItem b) {
    b.isWrongJiggle = true;
    b.jiggleProgress = 0.0;
    myScore = max(0, myScore - 5);

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);
    _addDeadBubble(b.word, size);

    if (currWord != null) {
      // 错词自动入生词本
      WordBo().addRawWord(currWord!.spell, '游戏');
      sendUserCmd('GET_NEXT_WORD', [myWordIndex++, 'false', currWord!.spell]);
    }

    floatingTexts.add(FloatingText(
      x: b.x,
      y: b.y - 10,
      text: '-5 答错石化下沉!',
      color: const Color(0xFFEF4444),
    ));
  }

  void _createBurstParticles(double x, double y, Color color, {int count = 12}) {
    for (int i = 0; i < count; i++) {
      final double angle = rand.nextDouble() * 2 * pi;
      final double speed = 60.0 + rand.nextDouble() * 120.0;
      particles.add(PopParticle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        radius: 2.0 + rand.nextDouble() * 2.5,
        color: color,
        life: 0.35 + rand.nextDouble() * 0.3,
      ));
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (!isPlaying) return;
    final tapPos = details.localPosition;

    for (int i = bubbles.length - 1; i >= 0; i--) {
      final b = bubbles[i];
      if (b.isPopping) continue;

      final double dist = (Offset(b.x, b.y) - tapPos).distance;
      if (dist <= b.radius + 10) {
        if (b.isTarget) {
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
            // 1. 水下深海与泡泡绘制
            Positioned.fill(
              child: CustomPaint(
                painter: _UnderseaScenePainter(
                  bubbles: bubbles,
                  particles: particles,
                  floatingTexts: floatingTexts,
                  deadBubbles: deadBubbles,
                  projectiles: projectiles,
                  waterSurfaceY: waterSurfaceY,
                  wavePhase: wavePhase,
                ),
              ),
            ),

            // 2. 顶部导航与房间控制
            Positioned(
              top: topPadding + 6,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () {
                      context.pop();
                    },
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
                        const Icon(Icons.bubble_chart_rounded, color: Color(0xFF38BDF8), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${gameHall.hallName}${roomId != null ? ' · 房号$roomId' : ''}',
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
                    icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22),
                    tooltip: '换房间',
                    onPressed: () {
                      sendUserCmd('LEAVE_HALL', []);
                      _enterRoom();
                    },
                  ),
                ],
              ),
            ),

            // 3. 顶部对战拉锯栏
            Positioned(
              top: topPadding + 44,
              left: 16,
              right: 16,
              child: _buildVsStatusBar(),
            ),

            // 4. 当前目标词提示（仅中文释义）
            if (isPlaying && currWord != null)
              Positioned(
                top: topPadding + 112,
                left: 30,
                right: 30,
                child: _buildTargetPromptCard(),
              ),

            // 5. 等待/开始游戏浮层
            if (!isPlaying && !isShowingResult)
              Positioned.fill(
                child: _buildWaitingOverlay(),
              ),

            // 6. 底部战术道具栏
            if (isPlaying)
              Positioned(
                bottom: bottomPadding + 14,
                left: 16,
                right: 16,
                child: _buildPropsBar(size),
              ),

            // 7. 结算弹窗
            if (isShowingResult)
              Positioned.fill(
                child: _buildResultDialog(size),
              ),
          ],
        ),
      ),
    );
  }

  /// 顶部对战双方 HUD
  Widget _buildVsStatusBar() {
    final bool hasOpponent = opponentUserId.isNotEmpty;
    final bool isBot = opponentUserId.startsWith('bot_');

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
          // 左侧：对手（受击左右抖动）
          Transform.translate(
            offset: Offset(opponentShake > 0 ? sin(opponentShake * 40) * 6 : 0, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: hasOpponent
                      ? const Color(0xFFF97316)
                      : Colors.white.withValues(alpha: 0.15),
                  child: Icon(
                    isBot
                        ? Icons.smart_toy_rounded
                        : (hasOpponent ? Icons.person_rounded : Icons.person_outline),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          opponentNickName,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600),
                        ),
                        if (opponentStarted) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF10B981), width: 0.5),
                            ),
                            child: const Text('已就绪',
                                style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '$opponentScore',
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (myStarted) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF10B981), width: 0.5),
                      ),
                      child: const Text('已就绪',
                          style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    myNickName.isNotEmpty ? myNickName : '我方',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Text(
                '$myScore',
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

  /// 目标词提示卡片（仅中文释义）
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
          Flexible(
            child: Text(
              currWord?.meaningStr ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFBBF24),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 等待与就绪状态卡片
  Widget _buildWaitingOverlay() {
    final bool isReady = (gameState == 'ready');
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xFF0F223D).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReady ? Icons.sports_esports_rounded : Icons.hourglass_top_rounded,
              color: isReady ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              myStarted
                  ? '已就绪，等待开赛...'
                  : (isReady ? '对手已就绪！' : '正在为您匹配对手...'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              myStarted
                  ? '双方准备完毕后将立即自动开赛'
                  : (isReady ? '点击下方按钮立即开始海底泡泡对战' : '若长时间未匹配，可点击下方开启单人练习'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: myStarted
                  ? null
                  : () {
                      _handleStartButtonClicked();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                disabledBackgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                myStarted
                    ? '等待对手中...'
                    : (isReady ? '开始对战' : '开始单人练习'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部道具操作栏
  Widget _buildPropsBar(Size size) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (attackProps > 0) {
                setState(() {
                  attackProps--;
                });
                _fireAttackMine(size);
              } else {
                floatingTexts.add(FloatingText(
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
                    '砸水雷压对手 ($attackProps)',
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
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (purgeProps > 0) {
                final success = _firePurgeNeedle(size);
                if (success) {
                  setState(() {
                    purgeProps--;
                  });
                  sendUserCmd('USE_PROPS', [1]);
                }
              } else {
                floatingTexts.add(FloatingText(
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
                    '戳死泡抬海面 ($purgeProps)',
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

  /// 结算弹窗
  Widget _buildResultDialog(Size size) {
    final bool isWon = (isWonInLastGame == true);
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          width: size.width * 0.84,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
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
                isWon ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
                size: 56,
                color: isWon ? const Color(0xFFFBBF24) : Colors.blueGrey,
              ),
              const SizedBox(height: 12),
              Text(
                isWon ? '挑战胜利！' : '本局惜败',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isWon
                    ? '已击沉对手海面！游戏分 ${scoreAdjust >= 0 ? "+$scoreAdjust" : scoreAdjust}, 魔法泡泡 ${cowDungAdjust >= 0 ? "+$cowDungAdjust" : cowDungAdjust}'
                    : '海面被死泡压沉淘汰。错误单词已自动收录至生词本！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      context.pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('离开大厅'),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        isShowingResult = false;
                      });
                      _handleStartButtonClicked();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('再来一局',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    // 1. 深海渐变背景
    final Rect fullRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF042654),
          Color(0xFF021B3D),
          Color(0xFF010E24),
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bgPaint);

    // 2. 透光光束
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

    // 3. 海床剪影
    _drawSeabed(canvas, size);

    // 4. 上升彩色泡泡
    for (final b in bubbles) {
      _drawBubble(canvas, b);
    }

    // 5. 爆破飞溅水珠粒子
    for (final p in particles) {
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, particlePaint);
    }

    // 6. 水面波浪与空气区
    _drawWaterSurface(canvas, size);

    // 7. 空气区死泡堆叠
    for (final db in deadBubbles) {
      _drawDeadBubble(canvas, db);
    }

    // 8. 弹道飞行物
    for (final p in projectiles) {
      _drawProjectile(canvas, p);
    }

    // 9. 飘字动效
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

    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset.zero, b.radius, rimPaint);

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

    final textSpan = TextSpan(
      text: b.word,
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

    final rimPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, db.radius, rimPaint);

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

  void _drawProjectile(Canvas canvas, GameProjectile p) {
    if (p.type == ProjectileType.needle) {
      final needlePaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(p.x, p.y + 16),
        Offset(p.x, p.y - 10),
        needlePaint,
      );
      final glowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y - 10), 3.0, glowPaint);
    } else {
      final minePaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 10.0, minePaint);
      final sparkPaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x + 8, p.y - 8), 3.5, sparkPaint);
    }
  }

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

    final surfacePaint = Paint()
      ..color = const Color(0xFF010A17).withValues(alpha: 0.88);
    canvas.drawPath(wavePath, surfacePaint);

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

    final weedPaint = Paint()
      ..color = const Color(0xFF031A26).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.15, size.height - 30), 24, weedPaint);
    canvas.drawCircle(Offset(size.width * 0.82, size.height - 35), 28, weedPaint);
  }

  @override
  bool shouldRepaint(covariant _UnderseaScenePainter oldDelegate) => true;
}
