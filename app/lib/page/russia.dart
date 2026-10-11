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
import 'package:nnbdc/util/tts.dart';
import 'package:nnbdc/util/utils.dart';
import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../services/throttled_sync_service.dart';
import '../util/app_clock.dart';
import '../util/prefs.dart';
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

/// 弹道类型
enum ProjectileType {
  needle,       // 使用道具：飞针直奔血条
  mine,         // 使用道具：水雷弧线轰击血条
  rewardMine,   // 获得道具：水雷能量球飞向左下角道具区
  rewardNeedle, // 获得道具：飞针能量球飞向右下角道具区
}

/// 飞行弹道与战利品光球
class GameProjectile {
  final ProjectileType type;
  double x;
  double y;
  final double startX;
  final double startY;
  final double targetX;
  final double targetY;
  double progress = 0.0;

  GameProjectile.needle({
    required this.x,
    required this.y,
    required this.targetX,
    required this.targetY,
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

  GameProjectile.rewardMine({
    required this.startX,
    required this.startY,
    required this.targetX,
    required this.targetY,
  })  : type = ProjectileType.rewardMine,
        x = startX,
        y = startY;

  GameProjectile.rewardNeedle({
    required this.startX,
    required this.startY,
    required this.targetX,
    required this.targetY,
  })  : type = ProjectileType.rewardNeedle,
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

  // 双方玩家数据与资产战绩
  String myUserId = '';
  String myNickName = '';
  int myScore = 0;
  int myCombo = 0;
  int myMaxCombo = 0;
  int myWordIndex = 0;
  int attackProps = 0;
  int purgeProps = 0;
  double mineSlotScale = 1.0;
  double needleSlotScale = 1.0;
  bool myStarted = false;
  int myTotalScore = 0;
  int myCowDung = 0;
  int myWinCount = 0;
  int myLostCount = 0;
  final Set<String> _wrongWordsInGame = {};

  String opponentUserId = '';
  String opponentNickName = '等待对手加入...';
  int opponentScore = 0;
  double opponentShake = 0.0;
  bool opponentStarted = false;
  int opponentTotalScore = 0;
  int opponentWinCount = 0;
  int opponentLostCount = 0;
  int opponentScoreAdjust = 0;

  // 当前目标词与泡泡
  WordVo? currWord;
  List<String> distractorWords = [];
  final List<BubbleItem> bubbles = [];
  final List<PopParticle> particles = [];
  final List<FloatingText> floatingTexts = [];
  final List<GameProjectile> projectiles = [];
  final List<AmbientBubble> ambientBubbles = [];
  int nextBubbleId = 0;
  bool hasMistakeInCurrentWord = false;

  // 10 格对战血条生命系统（每答错/受击一次扣 1 格，10 格耗尽战败）
  static const int maxHp = 10;
  int myHp = maxHp;
  int opponentHp = maxHp;
  double wavePhase = 0.0;

  final Tts _tts = Tts();

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
    // 游戏页面进入沉浸式粘性全屏模式（隐藏系统状态栏与底部手势条，达到沉浸式视觉）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initAmbientBubbles();
    _tts.init();
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
    _tts.stop();
    SocketIoClient.instance.setInRussiaGame(false);
    _cleanupSocketListeners();
    sendUserCmd('LEAVE_HALL', []);
    SocketIoClient.instance.disconnect();
    LoadingUtils.enableApiLoading();
    // 退出游戏，恢复系统全局 UI 模式
    Prefs.applyFullScreenMode();
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
      myTotalScore = user.gameScore;
      myCowDung = user.cowDung;
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
      if (isPlaying) return;
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
      if (isPlaying) return;
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
            myTotalScore = info.score;
            myCowDung = info.cowDung;
            myWinCount = info.winCount;
            myLostCount = info.lostCount;
          });
        } else {
          setState(() {
            opponentUserId = info.userId;
            if (info.nickName.isNotEmpty) {
              opponentNickName = info.nickName;
            }
            opponentTotalScore = info.score;
            opponentWinCount = info.winCount;
            opponentLostCount = info.lostCount;
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
      final int currentCount = (propsType == 0) ? attackProps : purgeProps;

      if (count > currentCount) {
        final mediaQuery = MediaQuery.maybeOf(context);
        final size = mediaQuery?.size ?? const Size(390, 844);
        final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
        final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
        final double targetX = (propsType == 0) ? 36.0 : size.width - 36.0;
        final double targetY = size.height - bottomBarHeight * 0.5;
        final double startX = size.width * 0.5;
        final double startY = size.height * 0.42;

        floatingTexts.add(FloatingText(
          x: startX,
          y: startY - 24,
          text: '🔥 连击奖励! 获得【${propsType == 0 ? "重力水雷" : "净化飞针"}】',
          color: const Color(0xFFFBBF24),
        ));

        if (propsType == 0) {
          projectiles.add(GameProjectile.rewardMine(
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
          ));
        } else {
          projectiles.add(GameProjectile.rewardNeedle(
            startX: startX,
            startY: startY,
            targetX: targetX,
            targetY: targetY,
          ));
        }
      } else {
        setState(() {
          if (propsType == 0) {
            attackProps = count;
          } else {
            purgeProps = count;
          }
        });
      }
    });

    socket.off('propsUsed');
    socket.on('propsUsed', (data) {
      if (!mounted) return;
      final String fromUserId = data[0].toString();
      final int propsType = data[1] as int;

      if (fromUserId != myUserId) {
        // 对手使用了道具
        if (propsType == 0) {
          // 对手对我发射了水雷！我方生命扣 1 格
          _applyDamage(1, '💥 遭受对手水雷轰击！-1 HP');
        } else {
          // 对手使用了飞针治愈自己！对手生命加 1 格
          setState(() {
            opponentHp = min(maxHp, opponentHp + 1);
          });
          floatingTexts.add(FloatingText(
            x: 70,
            y: 120,
            text: '💖 对手治愈 +1 HP',
            color: const Color(0xFFFBBF24),
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
        myTotalScore = max(0, myTotalScore + sAdjust);
        myCowDung = max(0, myCowDung + cAdjust);
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

    socket.off('scoreAdjustPublic');
    socket.on('scoreAdjustPublic', (data) {
      if (!mounted || data == null || data is! List || data.isEmpty) return;
      final String uId = data[0]?.toString() ?? '';
      final int sDelta = (data.length > 1 && data[1] is int) ? data[1] as int : 0;
      if (uId == opponentUserId) {
        setState(() {
          opponentScoreAdjust = sDelta;
          opponentTotalScore = max(0, opponentTotalScore + sDelta);
        });
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
      'scoreAdjustPublic',
      'noEnoughCowDung',
    ]) {
      socket.off(event);
    }
  }

  void _handleStartButtonClicked() {
    final bool hasOpponent = opponentUserId.isNotEmpty || gameState == 'ready';
    if (hasOpponent) {
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
      myMaxCombo = 0;
      myWordIndex = 0;
      scoreAdjust = 0;
      cowDungAdjust = 0;
      opponentScoreAdjust = 0;
      _wrongWordsInGame.clear();
      myHp = maxHp;
      opponentHp = maxHp;
      attackProps = 0;
      purgeProps = 0;
      isPlaying = true;
      gameState = 'playing';
      isShowingResult = false;
      myStarted = false;
      opponentStarted = false;
      projectiles.clear();
      bubbles.clear();
      particles.clear();
      floatingTexts.clear();
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

      // 题目区是中文释义，使用本地 TTS 只朗读第一个释义，利落清晰不泄题
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && isPlaying && currWord != null) {
          final meaning = _getFirstMeaningForTts(currWord!);
          if (meaning.isNotEmpty) {
            _tts.speak(meaning);
          }
        }
      });
    } catch (e) {
      Global.logger.e('解析 wordA 出错: $e');
    }
  }

  /// 提取用于 TTS 朗读的第一个纯中文释义（截取第一个分号/逗号前的内容，精简干练）
  String _getFirstMeaningForTts(WordVo word) {
    if (word.meaningItems != null && word.meaningItems!.isNotEmpty) {
      for (final item in word.meaningItems!) {
        final m = item.meaning?.trim() ?? '';
        if (m.isNotEmpty) {
          final first = m.split(RegExp(r'[;；,，/、\n]')).firstWhere(
                (p) => p.trim().isNotEmpty,
                orElse: () => m,
              );
          final clean = first.trim();
          if (clean.isNotEmpty) return clean;
        }
      }
    }
    final pure = Util.pureMeaningStr(word);
    final firstLine = pure.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '';
    final parts = firstLine.split(RegExp(r'[;；,，/、]'));
    final first = parts.firstWhere((p) => p.trim().isNotEmpty, orElse: () => firstLine);
    return first.trim();
  }

  void _handleWordB(dynamic data) {
    try {
      final answerResult = data[0].toString();
      if (answerResult == 'true') {
        setState(() {
          opponentScore += 10;
        });
        final mediaQuery = MediaQuery.maybeOf(context);
        final size = mediaQuery?.size ?? const Size(390, 844);
        floatingTexts.add(FloatingText(
          x: size.width - 70,
          y: 110,
          text: '+10',
          color: const Color(0xFFF97316),
        ));
      }
    } catch (_) {}
  }

  void _handleLoser(String loserId) {
    _tts.stop();
    final bool amILoser = (loserId == myUserId);
    setState(() {
      isPlaying = false;
      gameState = (opponentUserId.isNotEmpty) ? 'ready' : 'waiting';
      myStarted = false;
      opponentStarted = false;
      isShowingResult = true;
      isWonInLastGame = !amILoser;
      if (amILoser) {
        myLostCount++;
        if (opponentUserId.isNotEmpty) opponentWinCount++;
        myHp = 0;
      } else {
        myWinCount++;
        if (opponentUserId.isNotEmpty) opponentLostCount++;
        opponentHp = 0;
      }
      bubbles.clear();
      projectiles.clear();
      floatingTexts.clear();
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
    hasMistakeInCurrentWord = false;
    if (currWord == null) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
    final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
    final double bottomBarTopY = size.height - bottomBarHeight;

    final roundOptions = [currWord!.spell, ...distractorWords.take(2)]..shuffle(rand);
    // 3 个均分居中横向泳道，与左右道具槽及屏幕边缘保持优雅距离
    final slotXOffsets = [0.26, 0.50, 0.74]..shuffle(rand);
    // 上升速度梯度：有快有慢，拉开层次
    final speeds = [38.0, 48.0, 58.0]..shuffle(rand);

    for (int i = 0; i < roundOptions.length && i < 3; i++) {
      const double radius = 48.0; // 饱满梦幻大泡泡，排版更舒适
      final double baseX = size.width * slotXOffsets[i] + (rand.nextDouble() - 0.5) * 6.0;
      // 从底栏上边缘直接探出一半：圆心置于上边缘微靠上位置，上半球与主体文字立即露在底栏上方海水中
      final double startY = bottomBarTopY - 2.0 + (rand.nextDouble() - 0.5) * 4.0;
      final Color color = bubbleColors[i % bubbleColors.length];
      final double speed = speeds[i] + (rand.nextDouble() - 0.5) * 4.0;

      bubbles.add(BubbleItem(
        id: nextBubbleId++,
        word: roundOptions[i],
        isTarget: roundOptions[i] == currWord!.spell,
        x: baseX,
        y: startY,
        baseX: baseX,
        radius: radius,
        speed: speed,
        swingAmplitude: 5.0 + rand.nextDouble() * 4.0,
        swingFreq: 1.0 + rand.nextDouble() * 0.5,
        phase: rand.nextDouble() * 2 * pi,
        baseColor: color,
      ));
    }
  }

  void _applyDamage(int amount, [String reason = '答错 -1 HP!']) {
    if (!isPlaying) return;
    setState(() {
      myHp = max(0, myHp - amount);
      myCombo = 0;
    });
    HapticFeedback.heavyImpact();
    // 向服务端上报当前堆叠行数（堆叠 10 行淘汰，即 10 - myHp）
    sendUserCmd('REPORT_STACK_ROWS', [maxHp - myHp]);

    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);

    floatingTexts.add(FloatingText(
      x: size.width * 0.28,
      y: 95,
      text: reason,
      color: const Color(0xFFEF4444),
    ));

    // 血条消耗完战败
    if (myHp <= 0) {
      sendUserCmd('GAME_OVER', ['A']);
    }
  }

  bool _firePurgeNeedle(Size size) {
    if (myHp >= maxHp) {
      floatingTexts.add(FloatingText(
        x: size.width * 0.28,
        y: 95,
        text: '生命值已满格！',
        color: const Color(0xFF38BDF8),
      ));
      return false;
    }
    setState(() {
      purgeProps = max(0, purgeProps - 1);
      myHp = min(maxHp, myHp + 1);
    });
    sendUserCmd('USE_PROPS', [1]);
    sendUserCmd('REPORT_STACK_ROWS', [maxHp - myHp]);
    HapticFeedback.mediumImpact();

    // 治愈光针弹道（从右下角飞针小图标射向左侧我方顶部血条）
    final mediaQuery = MediaQuery.maybeOf(context);
    final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
    final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
    projectiles.add(GameProjectile.needle(
      x: size.width - 36,
      y: size.height - bottomBarHeight * 0.5,
      targetX: size.width * 0.25,
      targetY: 80,
    ));

    floatingTexts.add(FloatingText(
      x: size.width * 0.28,
      y: 95,
      text: '💖 飞针治愈 +1 HP!',
      color: const Color(0xFF34D399),
    ));
    return true;
  }

  void _fireAttackMine(Size size) {
    setState(() {
      attackProps = max(0, attackProps - 1);
      opponentHp = max(0, opponentHp - 1);
    });
    sendUserCmd('USE_PROPS', [0]);
    HapticFeedback.heavyImpact();

    // 弧线水雷弹道（从左下角水雷小图标轰击右侧对手顶部血条区）
    final mediaQuery = MediaQuery.maybeOf(context);
    final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
    final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
    projectiles.add(GameProjectile.mine(
      startX: 36,
      startY: size.height - bottomBarHeight * 0.5,
      targetX: size.width * 0.75,
      targetY: 80,
    ));

    floatingTexts.add(FloatingText(
      x: size.width * 0.72,
      y: 95,
      text: '🚀 水雷轰击 对手 -1 HP!',
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
    final topPadding = max(mediaQuery?.padding.top ?? 44.0, 16.0);
    final double barrierY = topPadding + 130.0;

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

    if (opponentShake > 0) {
      opponentShake = max(0.0, opponentShake - dt);
    }

    // 1. 泡泡软斥力防重叠
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

    // 2. 泡泡物理运动与出界判定
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

      // 触及能量警戒线：泡泡顶端触碰即碰撞爆破，绝不侵入上方 UI 区域
      if (b.y - b.radius <= barrierY) {
        if (b.isTarget) {
          targetWordExpired = true;
          _applyDamage(1, '漏答 -1 HP!');
          _createBurstParticles(b.x, barrierY, const Color(0xFFEF4444), count: 14);
        } else {
          _createBurstParticles(b.x, barrierY, b.baseColor, count: 8);
        }
        bubbles.removeAt(i);
      }
    }

    if (targetWordExpired && currWord != null) {
      sendUserCmd('GET_NEXT_WORD', [myWordIndex++, 'false', currWord!.spell]);
    }

    // 3. 弹道飞行物更新
    for (int i = projectiles.length - 1; i >= 0; i--) {
      final p = projectiles[i];
      if (p.type == ProjectileType.needle) {
        p.y -= 750.0 * dt;
        if (p.y <= p.targetY) {
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFF34D399), count: 12);
          projectiles.removeAt(i);
        }
      } else if (p.type == ProjectileType.mine) {
        p.progress += dt * 1.8;
        p.x = p.startX + (p.targetX - p.startX) * p.progress;
        p.y = p.startY + (p.targetY - p.startY) * p.progress - sin(p.progress * pi) * 120.0;
        if (p.progress >= 1.0) {
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFFEF4444), count: 18);
          opponentShake = 0.4;
          projectiles.removeAt(i);
        }
      } else if (p.type == ProjectileType.rewardMine) {
        p.progress += dt * 1.1; // 飞行约 0.9s，给用户充足的视觉注意跟踪时间
        p.x = p.startX + (p.targetX - p.startX) * p.progress;
        p.y = p.startY + (p.targetY - p.startY) * p.progress - sin(p.progress * pi) * 90.0;
        // 飞行途中生成尾迹火花
        if (rand.nextDouble() < 0.6) {
          particles.add(PopParticle(
            x: p.x,
            y: p.y,
            vx: (rand.nextDouble() - 0.5) * 30.0,
            vy: (rand.nextDouble() - 0.5) * 30.0,
            radius: 2.0,
            color: const Color(0xFFF97316),
            life: 0.35,
          ));
        }
        if (p.progress >= 1.0) {
          attackProps++;
          mineSlotScale = 1.45; // 触发左下角水雷槽果冻弹跳
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFFF97316), count: 20);
          floatingTexts.add(FloatingText(
            x: p.targetX,
            y: p.targetY - 32,
            text: '+1 💣',
            color: const Color(0xFFF97316),
          ));
          StudyAudioSessionController.instance.playSoundEffect('magic.mp3', speed: 1.25, volume: 0.15);
          HapticFeedback.mediumImpact();
          projectiles.removeAt(i);
        }
      } else if (p.type == ProjectileType.rewardNeedle) {
        p.progress += dt * 1.1;
        p.x = p.startX + (p.targetX - p.startX) * p.progress;
        p.y = p.startY + (p.targetY - p.startY) * p.progress - sin(p.progress * pi) * 90.0;
        // 飞行途中生成尾迹火花
        if (rand.nextDouble() < 0.6) {
          particles.add(PopParticle(
            x: p.x,
            y: p.y,
            vx: (rand.nextDouble() - 0.5) * 30.0,
            vy: (rand.nextDouble() - 0.5) * 30.0,
            radius: 2.0,
            color: const Color(0xFF34D399),
            life: 0.35,
          ));
        }
        if (p.progress >= 1.0) {
          purgeProps++;
          needleSlotScale = 1.45; // 触发右下角飞针槽果冻弹跳
          _createBurstParticles(p.targetX, p.targetY, const Color(0xFF34D399), count: 20);
          floatingTexts.add(FloatingText(
            x: p.targetX,
            y: p.targetY - 32,
            text: '+1 💖',
            color: const Color(0xFF34D399),
          ));
          StudyAudioSessionController.instance.playSoundEffect('magic.mp3', speed: 1.25, volume: 0.15);
          HapticFeedback.mediumImpact();
          projectiles.removeAt(i);
        }
      }
    }

    // 道具槽弹性缩放衰减恢复
    if (mineSlotScale > 1.0) {
      mineSlotScale = max(1.0, mineSlotScale - dt * 2.5);
    }
    if (needleSlotScale > 1.0) {
      needleSlotScale = max(1.0, needleSlotScale - dt * 2.5);
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
    HapticFeedback.mediumImpact();
    _createBurstParticles(b.x, b.y, b.baseColor, count: 16);

    // 用户在泡泡中戳中了正确的英文单词：停止中文 TTS 并播放清脆泡泡破裂音效 (bubble-pop.wav)
    _tts.stop();
    StudyAudioSessionController.instance.playSoundEffect('bubble-pop.wav', speed: 1.0, volume: 1.0);

    final bool isFirstTrySuccess = !hasMistakeInCurrentWord;

    if (isFirstTrySuccess) {
      // 只有第一次直接选对，才算真正的答对！
      myScore += 10;
      myCombo++;
      if (myCombo > myMaxCombo) {
        myMaxCombo = myCombo;
      }

      // 连对奖励战术道具（每连对 3 次随机奖励水雷或飞针，从当前爆破的泡泡飞向底部道具区）
      if (myCombo % 3 == 0) {
        final mediaQuery = MediaQuery.maybeOf(context);
        final size = mediaQuery?.size ?? const Size(390, 844);
        final bottomPadding = mediaQuery?.padding.bottom ?? 0.0;
        final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
        final double mineTargetX = 36.0;
        final double mineTargetY = size.height - bottomBarHeight * 0.5;
        final double needleTargetX = size.width - 36.0;
        final double needleTargetY = size.height - bottomBarHeight * 0.5;

        // 在爆破泡泡处浮现醒目提示，告知用户道具来源于连击！
        floatingTexts.add(FloatingText(
          x: b.x,
          y: b.y - 32,
          text: '🔥 $myCombo 连对! 道具掉落',
          color: const Color(0xFFFBBF24),
        ));

        if (rand.nextBool()) {
          // 获得治愈飞针：从当前爆破泡泡飞向右下角飞针道具区，飞抵后入库
          projectiles.add(GameProjectile.rewardNeedle(
            startX: b.x,
            startY: b.y,
            targetX: needleTargetX,
            targetY: needleTargetY,
          ));
        } else {
          // 获得重力水雷：从当前爆破泡泡飞向左下角水雷道具区，飞抵后入库
          projectiles.add(GameProjectile.rewardMine(
            startX: b.x,
            startY: b.y,
            targetX: mineTargetX,
            targetY: mineTargetY,
          ));
        }
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
    } else {
      // 之前点错过干扰词，靠排除法最终点对：本题算答错，不计入得分与 Combo
      myCombo = 0;
      floatingTexts.add(FloatingText(
        x: b.x,
        y: b.y - 15,
        text: '排除完成 (算错题)',
        color: const Color(0xFFFBBF24),
      ));

      // 向服务端上报答错并拉取下一词
      if (currWord != null) {
        sendUserCmd('GET_NEXT_WORD', [myWordIndex++, 'false', currWord!.spell]);
      }
    }
  }

  void _onWrongWordTapped(BubbleItem b) {
    // 标记本题已发生错选，后续即便点对也是排除法算错
    hasMistakeInCurrentWord = true;

    // 戳破当前选错的干扰词泡泡，避免重复点击
    b.isPopping = true;
    myScore = max(0, myScore - 5);

    StudyAudioSessionController.instance.playSoundEffect('bubble-pop.wav', speed: 0.9, volume: 0.8);
    _applyDamage(1, '答错 -1 HP!');
    _createBurstParticles(b.x, b.y, const Color(0xFFEF4444), count: 14);
    HapticFeedback.lightImpact();

    // 1. 将误认的干扰词精准收录至生词本
    _wrongWordsInGame.add(b.word);
    WordBo().addRawWord(b.word, '游戏错选');
    // 2. 将当前本题目标词也收录至生词本
    if (currWord != null) {
      _wrongWordsInGame.add(currWord!.spell);
      WordBo().addRawWord(currWord!.spell, '游戏');
    }

    // 不切换下一词，允许用户继续点击剩余泡泡直到点对为止！
    floatingTexts.add(FloatingText(
      x: b.x,
      y: b.y - 10,
      text: '生词本收录: ${b.word}',
      color: const Color(0xFFF87171),
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
    final topPadding = max(MediaQuery.of(context).padding.top, 16.0);
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
                  projectiles: projectiles,
                  ambientBubbles: ambientBubbles,
                  barrierY: topPadding + 130.0,
                  wavePhase: wavePhase,
                ),
              ),
            ),

            // 2. 顶部导航与房间控制
            Positioned(
              top: topPadding + 4,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () {
                      context.pop();
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bubble_chart_rounded, color: Color(0xFF38BDF8), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '${gameHall.hallName}${roomId != null ? ' · 房号$roomId' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.95),
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

            // 3. 顶部对战拉锯栏（药丸比分仪表盘）
            Positioned(
              top: topPadding + 44,
              left: 20,
              right: 20,
              child: _buildVsStatusBar(),
            ),

            // 4. 等待/开始游戏浮层
            if (!isPlaying && !isShowingResult)
              Positioned.fill(
                child: _buildWaitingOverlay(),
              ),

            // 5. 底部整合控制与题目栏：左侧水雷道具 + 中间中文释义题目 + 右侧飞针道具
            if (isPlaying)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(size, bottomPadding),
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

  /// 顶部对战药丸比分仪表盘（对标参考设计：左橙右蓝药丸条 + 居中大勋章徽标 + 头像与下方昵称）
  Widget _buildVsStatusBar() {
    final bool hasOpponent = opponentUserId.isNotEmpty;
    final bool isBot = opponentUserId.startsWith('bot_');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 中间连接的药丸比分横条（左橙右蓝长槽）
              Container(
                height: 38,
                margin: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF032B69).withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Row(
                    children: [
                      // 左半段：翡翠绿我方生命槽（10 格比例）
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double totalWidth = constraints.maxWidth;
                            final double ratio = (myHp / maxHp).clamp(0.0, 1.0);
                            return Stack(
                              children: [
                                // 空血槽底色（深蓝暗黑）
                                Container(
                                  color: const Color(0xFF0B172D).withValues(alpha: 0.9),
                                ),
                                // 翡翠绿活跃生命条（从左向中心充满，掉血退缩）
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    width: totalWidth * ratio,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF34D399), Color(0xFF059669)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                // 10 等分微弱刻度分割线
                                Row(
                                  children: List.generate(maxHp, (i) => Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            width: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )),
                                ),
                                // 中央生命值与爱心图标
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 24, right: 28),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$myHp / $maxHp',
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                              shadows: [
                                                Shadow(
                                                  color: Color(0xFF032B69),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      // 右半段：橙红对手生命槽（10 格比例）
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double totalWidth = constraints.maxWidth;
                            final double ratio = (opponentHp / maxHp).clamp(0.0, 1.0);
                            return Stack(
                              children: [
                                // 空血槽底色（深蓝暗黑）
                                Container(
                                  color: const Color(0xFF0B172D).withValues(alpha: 0.9),
                                ),
                                // 橙红活跃生命条（向右中心充满，掉血退缩）
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    width: totalWidth * ratio,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                // 10 等分微弱刻度分割线
                                Row(
                                  children: List.generate(maxHp, (i) => Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            width: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )),
                                ),
                                // 中央生命值与爱心图标
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 28, right: 24),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '$opponentHp / $maxHp',
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                              shadows: [
                                                Shadow(
                                                  color: Color(0xFF032B69),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. 左侧突出我方圆形头像（带「我」角标）
              Positioned(
                left: 0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF032B69).withValues(alpha: 0.45),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF0284C7),
                        child: Icon(
                          Icons.face_5_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    // 参考设计同款「我」角标
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Text(
                          '我',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. 右侧突出对手圆形头像（受击震动）
              Positioned(
                right: 0,
                child: Transform.translate(
                  offset: Offset(opponentShake > 0 ? sin(opponentShake * 40) * 6 : 0, 0),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF032B69).withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: hasOpponent ? const Color(0xFFEA580C) : const Color(0xFF64748B),
                      child: Icon(
                        isBot
                            ? Icons.smart_toy_rounded
                        : (hasOpponent ? Icons.face_rounded : Icons.person_outline),
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),

              // 4. 正中央圆形大勋章徽标（VS）
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0284C7), Color(0xFF034A9E)],
                  ),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.65),
                      blurRadius: 10,
                    ),
                    BoxShadow(
                      color: const Color(0xFF032B69).withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // 5. 下方左右对应的昵称与准备状态
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // 我方昵称
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    myNickName.isNotEmpty ? myNickName : '我方',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95),
                      shadows: [
                        Shadow(
                          color: const Color(0xFF032B69).withValues(alpha: 0.8),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (myStarted) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('已就绪',
                          style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              // 对手昵称
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (opponentStarted) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('已就绪',
                          style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    opponentNickName,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95),
                      shadows: [
                        Shadow(
                          color: const Color(0xFF032B69).withValues(alpha: 0.8),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _buildTargetPromptCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      alignment: Alignment.center,
      child: Text(
        currWord?.meaningStr ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFFFDE047),
          letterSpacing: 0.3,
          shadows: [
            Shadow(
              color: Color(0xFF032B69),
              blurRadius: 6,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部整合操作与题目栏：左侧水雷道具 + 中间中文释义题目 + 右侧飞针道具
  Widget _buildBottomBar(Size size, double bottomPadding) {
    final double bottomBarHeight = max(bottomPadding, 10.0) + 54.0;
    return Container(
      height: bottomBarHeight,
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 5,
        bottom: max(bottomPadding, 8.0),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF031634).withValues(alpha: 0.90),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAttackMineProp(size),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTargetPromptCard(),
          ),
          const SizedBox(width: 8),
          _buildPurgeNeedleProp(size),
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

  /// 左侧给对手用的战术道具小图标（重力水雷）
  Widget _buildAttackMineProp(Size size) {
    final bool hasProp = attackProps > 0;
    return Transform.scale(
      scale: mineSlotScale,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (hasProp) {
            _fireAttackMine(size);
          } else {
            floatingTexts.add(FloatingText(
              x: 55,
              y: size.height - 120,
              text: '连对3次可得水雷!',
              color: Colors.white70,
            ));
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: hasProp
                      ? const [Color(0xFFDC2626), Color(0xFF991B1B)]
                      : [
                          const Color(0xFF1E293B).withValues(alpha: 0.8),
                          const Color(0xFF0F172A).withValues(alpha: 0.8),
                        ],
                ),
                border: Border.all(
                  color: hasProp
                      ? const Color(0xFFF87171)
                      : Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: hasProp
                    ? [
                        BoxShadow(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: const Center(
                child: Text('💣', style: TextStyle(fontSize: 20)),
              ),
            ),
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                decoration: BoxDecoration(
                  color: hasProp ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '$attackProps',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧给自己加血的战术道具小图标（治愈飞针）
  Widget _buildPurgeNeedleProp(Size size) {
    final bool hasProp = purgeProps > 0;
    return Transform.scale(
      scale: needleSlotScale,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (hasProp) {
            _firePurgeNeedle(size);
          } else {
            floatingTexts.add(FloatingText(
              x: size.width - 55,
              y: size.height - 120,
              text: '连对3次可得飞针!',
              color: Colors.white70,
            ));
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: hasProp
                      ? const [Color(0xFF059669), Color(0xFF047857)]
                      : [
                          const Color(0xFF1E293B).withValues(alpha: 0.8),
                          const Color(0xFF0F172A).withValues(alpha: 0.8),
                        ],
                ),
                border: Border.all(
                  color: hasProp
                      ? const Color(0xFF34D399)
                      : Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: hasProp
                    ? [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: const Center(
                child: Text('💖', style: TextStyle(fontSize: 20)),
              ),
            ),
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                decoration: BoxDecoration(
                  color: hasProp ? const Color(0xFF10B981) : const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '$purgeProps',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 游戏结算与用户分数面板
  Widget _buildResultDialog(Size size) {
    final bool isWon = (isWonInLastGame == true);
    final int totalMatches = myWinCount + myLostCount;
    final double winRate = totalMatches > 0 ? (myWinCount * 100.0 / totalMatches) : 0.0;
    final String myDisplayScore = '$myScore';
    final String oppDisplayScore = '$opponentScore';

    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(size.width * 0.90, 410.0),
            maxHeight: size.height * 0.92,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isWon
                    ? const Color(0xFFFBBF24).withValues(alpha: 0.35)
                    : Colors.cyanAccent.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isWon ? const Color(0xFFFBBF24) : Colors.cyanAccent).withValues(alpha: 0.15),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 25,
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 顶部荣誉徽标与大标题
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isWon
                            ? [const Color(0xFFFDE68A), const Color(0xFFF59E0B)]
                            : [const Color(0xFF94A3B8), const Color(0xFF475569)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isWon ? const Color(0xFFF59E0B) : const Color(0xFF475569)).withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isWon ? Icons.emoji_events_rounded : Icons.shield_outlined,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isWon ? '挑战胜利！' : '本局惜败',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isWon ? '击溃对手生命 · 荣耀加冕' : '生命值耗尽 · 汲取经验再战',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2. 本局对决战报卡片（Battle Stats）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // 我方对决得分
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF38BDF8),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          myNickName.isEmpty ? '我方' : myNickName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF7DD3FC),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        myDisplayScore,
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          fontFeatures: [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '分',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (myHp > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      myHp > 0 ? '❤️ 残余 $myHp HP' : '💔 0 HP',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: myHp > 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 居中 VS 标志
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                'VS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),

                            // 对手对决得分
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF97316),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          opponentNickName.isEmpty ? '对手' : opponentNickName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFFDBA74),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        oppDisplayScore,
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '分',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (opponentHp > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      opponentHp > 0 ? '❤️ 残余 $opponentHp HP' : '💔 0 HP',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: opponentHp > 0 ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                        const SizedBox(height: 10),

                        // 局内数据高光（最高连击、答题数）
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFFBBF24)),
                                const SizedBox(width: 3),
                                Text(
                                  '最高连击 $myMaxCombo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.15)),
                            Row(
                              children: [
                                const Icon(Icons.my_location_rounded, size: 13, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 4),
                                Text(
                                  '作答 $myWordIndex 题',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. 用户总天梯积分与资产卡片（Rank & Asset Growth）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        // 天梯总积分与变动
                        _buildStatRow(
                          icon: Icons.military_tech_rounded,
                          iconColor: const Color(0xFFFBBF24),
                          label: '天梯总积分',
                          valueText: '$myTotalScore',
                          deltaText: scoreAdjust >= 0 ? '+$scoreAdjust' : '$scoreAdjust',
                          isPositive: scoreAdjust >= 0,
                          showDelta: true,
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                        const SizedBox(height: 8),

                        // 魔法泡泡资产与变动
                        _buildStatRow(
                          icon: Icons.bubble_chart_rounded,
                          iconColor: const Color(0xFF38BDF8),
                          label: '魔法泡泡',
                          valueText: '$myCowDung',
                          deltaText: cowDungAdjust >= 0 ? '+$cowDungAdjust' : '$cowDungAdjust',
                          isPositive: cowDungAdjust >= 0,
                          showDelta: true,
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                        const SizedBox(height: 8),

                        // 战绩胜率
                        _buildStatRow(
                          icon: Icons.leaderboard_rounded,
                          iconColor: const Color(0xFFA78BFA),
                          label: '排位战绩',
                          valueText: '${winRate.toStringAsFixed(1)}%',
                          subValueText: '$myWinCount胜 / $myLostCount负',
                          showDelta: false,
                        ),
                      ],
                    ),
                  ),

                  // 4. 生词本与零失误贴心提示
                  if (_wrongWordsInGame.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_rounded, size: 15, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已将 ${_wrongWordsInGame.length} 个失误词收录至生词本（${_wrongWordsInGame.take(2).join(", ")}${_wrongWordsInGame.length > 2 ? " 等" : ""}）',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isWon)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.22)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF34D399)),
                          SizedBox(width: 6),
                          Text(
                            '✨ 本局零失误，精彩绝伦！',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6EE7B7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // 5. 底部操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          context.pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('离开大厅', style: TextStyle(fontSize: 14)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          elevation: 4,
                          shadowColor: const Color(0xFF0284C7).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          '再来一局',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 结算面板指标行
  Widget _buildStatRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String valueText,
    String? deltaText,
    String? subValueText,
    bool isPositive = true,
    bool showDelta = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const Spacer(),
        Text(
          valueText,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (subValueText != null) ...[
          const SizedBox(width: 6),
          Text(
            '($subValueText)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
        if (showDelta && deltaText != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: (isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              deltaText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isPositive ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 海底世界与超写实通透泡泡高保真绘制器
class _UnderseaScenePainter extends CustomPainter {
  final List<BubbleItem> bubbles;
  final List<PopParticle> particles;
  final List<FloatingText> floatingTexts;
  final List<GameProjectile> projectiles;
  final List<AmbientBubble> ambientBubbles;
  final double barrierY;
  final double wavePhase;

  _UnderseaScenePainter({
    required this.bubbles,
    required this.particles,
    required this.floatingTexts,
    required this.projectiles,
    required this.ambientBubbles,
    required this.barrierY,
    required this.wavePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 蔚蓝通透明亮的海水渐变背景（与参考设计同款高饱和梦幻蔚蓝）
    final Rect fullRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF299BF6), // 顶部浅海透光蓝
          Color(0xFF1473E6), // 中层清澈蔚蓝
          Color(0xFF094EBE), // 下层深蔚蓝
          Color(0xFF063B96), // 海底沉稳海蓝
        ],
        stops: [0.0, 0.32, 0.70, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bgPaint);

    // 2. 穿透海面的多道丁达尔阳光光束（Sun Rays / God Rays）
    _drawSunRays(canvas, size);

    // 3. 散落漂浮的微小氛围气泡
    _drawAmbientBubbles(canvas);

    // 4. 海底珊瑚礁岩石与海草植被（参考设计同款插画剪影）
    _drawSeabedAndWeeds(canvas, size);

    // 5. 题目卡片下方的晶莹微光能量警戒线（天花板防护屏障）
    _drawEnergyBarrier(canvas, size);

    // 6. 上升的超拟真梦幻彩色通透泡泡
    for (final b in bubbles) {
      _drawBubble(canvas, b);
    }

    // 6. 爆破飞溅水珠微粒
    for (final p in particles) {
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, particlePaint);
    }

    // 7. 弹道飞行物
    for (final p in projectiles) {
      _drawProjectile(canvas, p);
    }

    // 10. 飘字动效
    for (final ft in floatingTexts) {
      final textSpan = TextSpan(
        text: ft.text,
        style: TextStyle(
          color: ft.color.withValues(alpha: ft.life.clamp(0.0, 1.0)),
          fontSize: 16.5,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: const Color(0xFF032B69).withValues(alpha: 0.8),
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

  /// 绘制穿透海面的丁达尔太阳光束（God Rays）
  void _drawSunRays(Canvas canvas, Size size) {
    // 光束 1：偏左主光束
    final ray1 = Path()
      ..moveTo(size.width * 0.15, 0)
      ..lineTo(size.width * 0.38, 0)
      ..lineTo(size.width * 0.62, size.height * 0.88)
      ..lineTo(size.width * 0.28, size.height * 0.88)
      ..close();
    final p1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.13),
          Colors.cyanAccent.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawPath(ray1, p1);

    // 光束 2：中央次光束
    final ray2 = Path()
      ..moveTo(size.width * 0.48, 0)
      ..lineTo(size.width * 0.65, 0)
      ..lineTo(size.width * 0.95, size.height * 0.75)
      ..lineTo(size.width * 0.72, size.height * 0.75)
      ..close();
    final p2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.cyanAccent.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawPath(ray2, p2);

    // 光束 3：左上纤细斜束
    final ray3 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.16, 0)
      ..lineTo(size.width * 0.32, size.height * 0.6)
      ..lineTo(size.width * 0.10, size.height * 0.6)
      ..close();
    final p3 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(ray3, p3);
  }

  /// 绘制散落的微小氛围气泡
  void _drawAmbientBubbles(Canvas canvas) {
    for (final ab in ambientBubbles) {
      final center = Offset(ab.x, ab.y);
      // 微光外圈
      final rimPaint = Paint()
        ..color = Colors.white.withValues(alpha: ab.alpha * 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(center, ab.radius, rimPaint);

      // 半透明微泡内芯
      final fillPaint = Paint()
        ..color = Colors.white.withValues(alpha: ab.alpha * 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, ab.radius, fillPaint);

      // 微小高光点
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: ab.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(ab.x - ab.radius * 0.35, ab.y - ab.radius * 0.35),
        max(0.6, ab.radius * 0.3),
        dotPaint,
      );
    }
  }

  /// 绘制海底珊瑚礁岩石与多层长海草（扎根于屏幕最底部海床，水草修长茂盛，即使有答案区也能大面积露在答案区上方）
  void _drawSeabedAndWeeds(Canvas canvas, Size size) {
    final double seabedY = size.height;

    // 1. 右侧远景深蓝珊瑚岩石层
    final bgRockPath = Path()
      ..moveTo(size.width * 0.40, seabedY)
      ..quadraticBezierTo(size.width * 0.60, seabedY - 110, size.width * 0.82, seabedY - 95)
      ..quadraticBezierTo(size.width * 0.94, seabedY - 70, size.width, seabedY - 80)
      ..lineTo(size.width, seabedY)
      ..close();
    final bgRockPaint = Paint()
      ..color = const Color(0xFF073A8A).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawPath(bgRockPath, bgRockPaint);

    // 2. 右侧近景湖蓝珊瑚岩石层
    final fgRockPath = Path()
      ..moveTo(size.width * 0.52, seabedY)
      ..quadraticBezierTo(size.width * 0.70, seabedY - 80, size.width * 0.86, seabedY - 60)
      ..quadraticBezierTo(size.width * 0.95, seabedY - 45, size.width, seabedY - 50)
      ..lineTo(size.width, seabedY)
      ..close();
    final fgRockPaint = Paint()
      ..color = const Color(0xFF0C4CA4).withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fgRockPath, fgRockPaint);

    // 3. 左侧主要长海草丛（扎根于屏幕物理底部，长达 180~255px，高挑舒展，从答案区上方自然探出摇曳）
    _drawWeedStem(canvas, Offset(size.width * 0.04, seabedY), 255.0, -28.0, const Color(0xFF08418E), wavePhase);
    _drawWeedStem(canvas, Offset(size.width * 0.08, seabedY), 215.0, 22.0, const Color(0xFF0A4B9E), wavePhase + 1.2);
    _drawWeedStem(canvas, Offset(size.width * 0.13, seabedY), 240.0, -18.0, const Color(0xFF073880), wavePhase + 2.4);
    _drawWeedStem(canvas, Offset(size.width * 0.18, seabedY), 180.0, 16.0, const Color(0xFF094696), wavePhase + 0.8);

    // 4. 右侧岩石缝隙中的长水草（长达 150~185px，从岩石后方与答案区右上方探出摆动）
    _drawWeedStem(canvas, Offset(size.width * 0.72, seabedY), 185.0, 22.0, const Color(0xFF0B50A8), wavePhase + 1.8);
    _drawWeedStem(canvas, Offset(size.width * 0.79, seabedY), 150.0, -14.0, const Color(0xFF0D5BBF), wavePhase + 3.0);
    _drawWeedStem(canvas, Offset(size.width * 0.86, seabedY), 170.0, 18.0, const Color(0xFF094696), wavePhase + 0.5);
  }

  /// 绘制单个海草叶片（带自然海浪起伏微摆动）
  void _drawWeedStem(Canvas canvas, Offset base, double height, double curveOffset, Color color, double phase) {
    final Path path = Path();
    final double sway = sin(phase) * 8.0;
    final double effectiveCurve = curveOffset + sway;
    final double midY = base.dy - height * 0.55;
    final double topY = base.dy - height;

    path.moveTo(base.dx - 3.5, base.dy);
    path.quadraticBezierTo(base.dx + effectiveCurve, midY, base.dx + effectiveCurve * 0.6, topY);
    path.quadraticBezierTo(base.dx + effectiveCurve + 4.5, midY + 4, base.dx + 4.5, base.dy);
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  /// 绘制超拟真通透高光彩色泡泡（1:1 对标参考设计）
  void _drawBubble(Canvas canvas, BubbleItem b) {
    if (b.isPopping) {
      final scale = 1.0 + b.popProgress * 0.45;
      final alpha = (1.0 - b.popProgress).clamp(0.0, 1.0);
      final popPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(Offset(b.x, b.y), b.radius * scale, popPaint);
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

    final double r = b.radius;
    final bubbleRect = Rect.fromCircle(center: Offset.zero, radius: r);

    // 1. 泡泡球体内部：极度通透微彩渐变（透出深蓝海水，具有肥皂泡般的轻盈质感）
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 0.95,
        colors: [
          Colors.white.withValues(alpha: 0.12),
          b.baseColor.withValues(alpha: 0.08),
          b.baseColor.withValues(alpha: 0.22),
          b.baseColor.withValues(alpha: 0.45),
        ],
        stops: const [0.0, 0.45, 0.8, 1.0],
      ).createShader(bubbleRect);
    canvas.drawCircle(Offset.zero, r, bodyPaint);

    // 2. 彩色薄膜辉光环（Rim Ring & Film Glow）
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset.zero, r, rimPaint);

    final colorRimPaint = Paint()
      ..color = b.baseColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;
    canvas.drawCircle(Offset.zero, r - 0.5, colorRimPaint);

    // 3. 左上方主高光月牙弧（Primary Crescent Highlight，核心高光）
    final highlightPath = Path();
    final double hlR = r * 0.82;
    highlightPath.addArc(
      Rect.fromCircle(center: Offset.zero, radius: hlR),
      -pi * 0.82,
      pi * 0.36,
    );
    final hlPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(2.5, r * 0.075);
    canvas.drawPath(highlightPath, hlPaint);

    // 4. 主高光旁的小点高光（Secondary Highlight Dot）
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final double dotAngle = -pi * 0.38;
    final double dotDist = r * 0.78;
    canvas.drawCircle(
      Offset(cos(dotAngle) * dotDist, sin(dotAngle) * dotDist),
      max(1.8, r * 0.05),
      dotPaint,
    );

    // 5. 右下方次环境反光弧（Rim Reflection，模拟水下漫反射）
    final bottomRimPath = Path();
    final double btmR = r * 0.84;
    bottomRimPath.addArc(
      Rect.fromCircle(center: Offset.zero, radius: btmR),
      pi * 0.15,
      pi * 0.28,
    );
    final btmPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.5, r * 0.045);
    canvas.drawPath(bottomRimPath, btmPaint);

    // 6. 泡泡中心单词（纯白、粗体、高对比度）
    final textSpan = TextSpan(
      text: b.word,
      style: TextStyle(
        color: Colors.white,
        fontSize: r >= 44 ? 17 : 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        shadows: [
          Shadow(
            color: const Color(0xFF032B69).withValues(alpha: 0.7),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 1.85);

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
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
    } else if (p.type == ProjectileType.mine) {
      final minePaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 10.0, minePaint);
      final sparkPaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x + 8, p.y - 8), 3.5, sparkPaint);
    } else if (p.type == ProjectileType.rewardMine) {
      // 获得道具水雷：璀璨橙红微光光球，带有柔和光晕和专属水雷图标
      final outerGlow = Paint()
        ..color = const Color(0xFFEA580C).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 19.0, outerGlow);

      final corePaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 13.0, corePaint);

      final textPainter = TextPainter(
        text: const TextSpan(text: '💣', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(p.x - textPainter.width / 2, p.y - textPainter.height / 2));
    } else if (p.type == ProjectileType.rewardNeedle) {
      // 获得道具飞针：晶莹翡翠绿微光光球，带有治愈光晕与专属治愈图标
      final outerGlow = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 19.0, outerGlow);

      final corePaint = Paint()
        ..color = const Color(0xFF059669)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), 13.0, corePaint);

      final textPainter = TextPainter(
        text: const TextSpan(text: '💖', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(p.x - textPainter.width / 2, p.y - textPainter.height / 2));
    }
  }

  /// 绘制题目卡片下方的晶莹微光能量警戒线（防冲顶天花板屏障）
  void _drawEnergyBarrier(Canvas canvas, Size size) {
    if (barrierY <= 0) return;

    // 1. 柔和发光光晕（模糊微光带，两端渐隐）
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          const Color(0xFF38BDF8).withValues(alpha: 0.15),
          const Color(0xFF38BDF8).withValues(alpha: 0.35),
          const Color(0xFF38BDF8).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, barrierY - 4, size.width, 8))
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width * 0.06, barrierY), Offset(size.width * 0.94, barrierY), glowPaint);

    // 2. 核心纤细青白能量流线
    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, barrierY - 1, size.width, 2))
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width * 0.08, barrierY), Offset(size.width * 0.92, barrierY), linePaint);

    // 3. 左右两侧微小能量晶体端点（高雅微光水滴点缀）
    final anchorPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.08, barrierY), 2.2, anchorPaint);
    canvas.drawCircle(Offset(size.width * 0.92, barrierY), 2.2, anchorPaint);
  }

  @override
  bool shouldRepaint(covariant _UnderseaScenePainter oldDelegate) => true;
}
