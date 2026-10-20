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
import '../util/study_audio_session_controller.dart';
import '../util/platform_util.dart';
import '../util/prefs.dart';
import '../util/word_pack_queue.dart';

/// 消砖块 · 下落英文单词大方块
class BrickItem {
  final int id;
  final String word;
  final bool isTarget;
  double x;
  double y;
  final double baseX;
  final double width;
  final double height;
  final double speed;
  final double swingAmplitude;
  final double swingFreq;
  final double phase;
  final Color baseColor;
  bool isPopping = false;
  double popProgress = 0.0;
  bool isWrongJiggle = false;
  double jiggleProgress = 0.0;

  /// 本题已答错：方块不再接受点击，加速坠落到堆叠顶部后垒进底部。
  bool isDoomed = false;

  BrickItem({
    required this.id,
    required this.word,
    required this.isTarget,
    required this.x,
    required this.y,
    required this.baseX,
    required this.width,
    required this.height,
    required this.speed,
    required this.swingAmplitude,
    required this.swingFreq,
    required this.phase,
    required this.baseColor,
  });
}

/// 底部堆积的失败方块层（死词层）
class BrickStackRow {
  final String word;
  final Color color;

  BrickStackRow({required this.word, required this.color});
}

/// 底部中文释义选项实体
class BrickOption {
  final String label;
  final String text;
  final bool isCorrect;
  bool isSelected = false;
  bool isWrong = false;

  BrickOption({
    required this.label,
    required this.text,
    required this.isCorrect,
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

/// 消砖块 · 经典下落消除独立对战页面（英选中还原版）
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
  int opponentHp = 10;
  static const int maxHp = 10;

  /// 方块高度与"0 层堆叠时一题的下落时间"。
  /// 这两个值同时决定客户端速度和上报给服务端的节奏，改动后服务端会自动跟随。
  static const double brickHeight = 58.0;
  /// 0 层堆叠时一题从出生到触底的时间；调大就是整体放慢。
  static const double baseFallSeconds = 7.2;

  /// 我方生命值由底部死词层数唯一决定：堆满 10 层即防线失守。
  /// 这样"堆叠高度 / 血条 / 服务端 stackRows"三者天然是同一个事实，不会再各算一套。
  int get myHp => max(0, maxHp - stackRows.length);

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

  final List<BrickItem> bricks = [];
  /// 底部已堆积的失败方块，从下往上垒；行数就等于 maxHp - myHp。
  final List<BrickStackRow> stackRows = [];
  final List<BrickOption> currentOptions = [];
  final List<BrickParticle> particles = [];
  final List<BrickFloatingText> _floatingTexts = [];
  final List<BrickAmbientParticle> _ambientParticles = [];

  final Random rand = Random();
  int nextBrickId = 1;
  int myWordIndex = 0;
  /// 对手已经作答的题目数量。
  int opponentWordCount = 0;
  /// 当前服务端是否会推 wordCountSync 绝对计数。
  /// 线上服务端还没升级时没有这个事件，退回到用既有的 wordB 一条条累加；
  /// 一旦收到 wordCountSync，就改用服务端绝对数，避免两套计数重复累加。
  bool _serverSendsWordCount = false;

  double _hitFlash = 0.0;
  double _healFlash = 0.0;
  double _screenShake = 0.0;
  double opponentShake = 0.0;
  double wavePhase = 0.0;

  /// 本局胜负是否已经展示过（本地血尽与随后到达的服务端 loser 事件只结算一次）
  bool _resultShown = false;

  static const List<Color> brickColors = [
    Color(0xFF38BDF8),
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFFA78BFA),
  ];

  final WordPackQueue _wordPack = WordPackQueue();
  /// 共享词序的索引 → 单词拼写。收到词包时顺手记下来，
  /// 这样对手进度落后（索引落在已经换掉的旧包）时也能显示他当前那道题。
  final Map<int, String> _spellByIndex = {};
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
    // 消砖块是纵向堆叠玩法，锁定竖屏，避免横屏把下落行程和答题区一起压扁
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tts.init();
    // 提前装载音效池和答对音，避免第一题答对时因首次解码而听不到声音
    StudyAudioSessionController.instance.prewarm();
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
        StudyAudioSessionController.instance.playSoundEffect('door.mp3', volume: 0.65);
        HapticFeedback.lightImpact();
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
      if (!mounted || !isPlaying) return;
      _handleStackSync(data);
    });

    socket.off('wordCountSync');
    socket.on('wordCountSync', (data) {
      if (!mounted || data is! List || data.length < 2) return;
      // 只要收到过任意一条，就说明服务端支持绝对计数，后续不再用 wordB 累加
      _serverSendsWordCount = true;
      final String userId = data[0]?.toString() ?? '';
      if (userId == myUserId) return; // 我方进度直接用本地 myWordIndex，避免两套计数
      final int count = (data[1] is num) ? (data[1] as num).toInt() : 0;
      setState(() => opponentWordCount = count);
    });

    // 旧服务端的兼容路径：它没有 wordCountSync，但每答一题都会给对手推一条 wordB。
    // 收到第一条 wordCountSync 后这个累加自动停用，不会和新协议重复计数。
    socket.off('wordB');
    socket.on('wordB', (data) {
      if (!mounted || !isPlaying || _serverSendsWordCount) return;
      setState(() => opponentWordCount++);
    });

    socket.off('gameResultNotice');
    socket.on('gameResultNotice', (data) {
      if (!mounted) return;
      // 断线期间被判负的补发提示，只是一条文字通知，不是本局的结算事件
      ToastUtil.error(data?.toString() ?? '');
    });

    socket.off('loser');
    socket.on('loser', (loserId) {
      if (!mounted) return;
      _handleLoser(loserId);
    });

    socket.off('giveProps');
    socket.on('giveProps', (data) {
      if (!mounted || data is! List || data.length < 2) return;
      _handleGiveProps((data[0] as num).toInt(), (data[1] as num).toInt());
    });

    socket.off('propsUsed');
    socket.on('propsUsed', (data) {
      if (!mounted || data is! List || data.length < 2) return;
      _handlePropsUsed(data[0]?.toString() ?? '', (data[1] as num).toInt());
    });

    // 服务端已经不在这一局里（断线期间被判负、房间已解散）：继续出题只会石沉大海
    socket.off('gameNotInProgress');
    socket.on('gameNotInProgress', (data) {
      if (!mounted) return;
      _handleGameNotInProgress(data?.toString() ?? '');
    });

    socket.off('forceClose');
    socket.on('forceClose', (data) {
      if (!mounted) return;
      _handleForceClose(data?.toString() ?? '');
    });

    // 智慧果不够时 START_GAME 不会真正开始；把“已就绪”退回可再次点开始的状态
    socket.off('noEnoughCowDung');
    socket.on('noEnoughCowDung', (data) {
      if (!mounted) return;
      setState(() => myStarted = false);
      final int need = (data is num) ? data.toInt() : 10;
      ToastUtil.error('智慧果不足，无法开始游戏！\n至少需要: $need');
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
    for (final event in [
      'roomId',
      'enterWait',
      'enterReady',
      'enterRoom',
      'userStarted',
      'sysCmd',
      'wordPack',
      'stackSync',
      'wordCountSync',
      'wordB',
      'gameResultNotice',
      'loser',
      'giveProps',
      'propsUsed',
      'gameNotInProgress',
      'forceClose',
      'noEnoughCowDung',
      'leaveRoom',
    ]) {
      socket.off(event);
    }
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
      stackRows.clear();
      opponentHp = maxHp;
      myCombo = 0;
      propsMine = 0;
      propsStarfish = 0;
      myWordIndex = 0;
      opponentWordCount = 0;
      isIntroPlaying = true;
      introProgress = 0.0;
      _resultShown = false;
      currWord = null;
      distractorWords.clear();
      bricks.clear();
      currentOptions.clear();
      particles.clear();
      _floatingTexts.clear();
    });

    _wordPack.reset();
    _spellByIndex.clear();
    _reportGamePacing();
    _requestWordPack(0);
  }

  /// 把本局真实的"初始下落时间 + 每层消耗的行程比例"上报给服务端。
  /// 服务端用它计算机器人的触底窗口，这样以后只改客户端的 baseFallSeconds
  /// 或竞技场/行高，服务端会自动跟随，不会留着旧速度常数。
  void _reportGamePacing() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final size = mediaQuery?.size ?? const Size(390, 844);
    final topPadding = max(mediaQuery?.padding.top ?? 44.0, 16.0);
    final arenaBottomY = _arenaBottomY(size.height, mediaQuery?.padding.bottom ?? 0.0);
    final double startY = topPadding + 62.0;
    final double fallDistance = max(80.0, arenaBottomY - startY - brickHeight / 2);
    final double rowHeight = _stackRowHeight(arenaBottomY, topPadding);
    sendUserCmd('GAME_PACING', [
      (baseFallSeconds * 1000).round(),
      rowHeight / fallDistance,
    ]);
  }

  void _requestWordPack(int fromIndex) {
    _wordPack.markRequested(fromIndex);
    sendUserCmd('GET_WORD_PACK', [fromIndex]);
  }

  void _handleWordPack(dynamic data) {
    if (data is! List || data.length < 2) return;
    final int fromIndex = (data[0] as num).toInt();
    final entries = List<dynamic>.from(data[1] as List);
    // 把这一包词的索引→拼写记下来，供"对手当前单词"按索引回查
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is List && entry.isNotEmpty && entry[0] is Map) {
        final spell = (entry[0] as Map)['spell']?.toString();
        if (spell != null && spell.isNotEmpty) {
          _spellByIndex[fromIndex + i] = spell;
        }
      }
    }
    _wordPack.accept(fromIndex, entries);
    _playNextWordFromPack();
  }

  /// 从共享词序里取出第 index 个词的拼写；本地还没收到这一段时返回 null。
  String? _spellAt(int index) => _spellByIndex[index];

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
      }

      final mediaQuery = MediaQuery.maybeOf(context);
      final size = mediaQuery?.size ?? const Size(390, 844);
      _spawnBricksForRound(size, data);

      // 发音朗读下落中的英文单词
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && isPlaying && currWord != null) {
          _tts.speak(currWord!.spell);
        }
      });
    } catch (e) {
      Global.logger.e('消砖块解析单词出错: $e');
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

  void _spawnBricksForRound(Size size, dynamic wireWordData) {
    bricks.clear();
    currentOptions.clear();
    if (currWord == null) return;

    final mediaQuery = MediaQuery.maybeOf(context);
    final topPadding = max(mediaQuery?.padding.top ?? 44.0, 16.0);
    final double startY = topPadding + 62.0;

    // 1. 生成自上而下缓缓掉落的单一目标英文单词大方块
    const double brickW = 230.0;
    final Color color = brickColors[myWordIndex % brickColors.length];
    // 初始下落时间固定为 baseFallSeconds：竞技场变高后速度同步放大，避免场地变大把节奏拖慢
    final double arenaBottomY = _arenaBottomY(size.height, mediaQuery?.padding.bottom ?? 0.0);
    final double fallDistance = max(80.0, arenaBottomY - startY - brickHeight / 2);
    final double speed = fallDistance / baseFallSeconds;

    bricks.add(BrickItem(
      id: nextBrickId++,
      word: currWord!.spell,
      isTarget: true,
      x: size.width / 2,
      y: startY,
      baseX: size.width / 2,
      width: brickW,
      height: brickHeight,
      speed: speed,
      swingAmplitude: 3.5,
      swingFreq: 1.2,
      phase: 0.0,
      baseColor: color,
    ));

    // 2. 提取 3 个中文释义选项（1 正确 + 2 干扰）
    String correctMeaning = (currWord!.meaningStr ?? currWord!.getMeaningStr()).trim();
    if (correctMeaning.isEmpty) correctMeaning = '该词核心释义';

    final List<String> distractorMeanings = [];
    if (wireWordData is List && wireWordData.length > 1 && wireWordData[1] is List) {
      final list = wireWordData[1] as List;
      for (final m in list) {
        final s = m?.toString().trim() ?? '';
        if (s.isNotEmpty && s != correctMeaning && !distractorMeanings.contains(s)) {
          distractorMeanings.add(s);
        }
      }
    }

    final fallbackMeanings = [
      'n. 机会；良机；时机',
      'adj. 卓越的；显著的',
      'v. 探索；探寻；钻研',
      'n. 旅程；长途旅行',
      'adj. 勇敢的；无畏的',
      'v. 维持；保持；保养',
      'n. 挑战；质疑；考验',
      'adj. 积极的；正向的',
      'v. 创造；创作；引起',
      'n. 目标；目的；靶子',
    ];
    for (final fm in fallbackMeanings) {
      if (distractorMeanings.length >= 2) break;
      if (fm != correctMeaning && !distractorMeanings.contains(fm)) {
        distractorMeanings.add(fm);
      }
    }

    final rawOptions = <({String text, bool isCorrect})>[
      (text: _formatMeaning(correctMeaning), isCorrect: true),
      (text: _formatMeaning(distractorMeanings[0]), isCorrect: false),
      (text: _formatMeaning(distractorMeanings[1]), isCorrect: false),
    ]..shuffle(rand);

    const labels = ['A', 'B', 'C'];
    for (int i = 0; i < rawOptions.length; i++) {
      currentOptions.add(BrickOption(
        label: labels[i],
        text: rawOptions[i].text,
        isCorrect: rawOptions[i].isCorrect,
      ));
    }

    setState(() {});
  }

  String _formatMeaning(String m) {
    final cleaned = m.replaceAll('\r', '').replaceAll('\n', ' ').trim();
    if (cleaned.length > 32) {
      return '${cleaned.substring(0, 30)}...';
    }
    return cleaned;
  }

  void _onOptionTapped(BrickOption opt) {
    if (!isPlaying || bricks.isEmpty || isIntroPlaying) return;
    final b = bricks.first;
    if (b.isPopping || b.isDoomed) return;

    // 玩家已经作答，停止正在朗读的单词，避免和答对/答错音效叠在一起
    _tts.stop();

    if (opt.isCorrect) {
      setState(() {
        opt.isSelected = true;
      });
      b.isPopping = true;
      _spawnBrickExplosion(b.x, b.y, b.baseColor);
      final bool ios = PlatformUtils.isIOS;
      StudyAudioSessionController.instance.playSoundEffect(
        ios ? 'correct_ios.wav' : 'correct.wav',
        volume: ios ? 0.35 : 0.6,
      );
      HapticFeedback.mediumImpact();

      myCombo++;
      if (myCombo % 3 == 0) {
        // 道具由服务端在收到本题答对后随机发放（giveProps），这里只提示掉落
        _floatingTexts.add(BrickFloatingText(
          x: b.x,
          y: b.y - 52,
          text: '🔥 $myCombo 连击！道具掉落',
          color: const Color(0xFFFBBF24),
        ));
      }
      _floatingTexts.add(BrickFloatingText(x: b.x, y: b.y, text: '连击 +$myCombo', color: const Color(0xFF38BDF8)));

      Future.delayed(const Duration(milliseconds: 220), () {
        if (!mounted || !isPlaying) return;
        _reportAnswer('true');
      });
    } else {
      // 答错：本题作废，方块加速坠到底部堆叠层，落地时统一扣血、上报答错
      setState(() {
        opt.isWrong = true;
        b.isWrongJiggle = true;
        b.jiggleProgress = 0.0;
        b.isDoomed = true;
      });
      HapticFeedback.heavyImpact();
      StudyAudioSessionController.instance.playSoundEffect('bubble-wrong.wav', volume: 0.55);
      _floatingTexts.add(BrickFloatingText(
        x: b.x,
        y: b.y - 30,
        text: '选错了，方块坠落…',
        color: const Color(0xFFF87171),
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
    final double barrierBottomY = _arenaBottomY(size.height, mediaQuery?.padding.bottom ?? 0.0);
    final double stackTopY = _stackTopY(barrierBottomY, mediaQuery?.padding.top ?? 44.0);

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
      if (mounted) setState(() {});
      return;
    }

    if (bricks.isNotEmpty) {
      final b = bricks.first;
      if (b.isPopping) {
        b.popProgress += dt * 3.5;
        if (b.popProgress >= 1.0) {
          bricks.clear();
        }
      } else {
        if (b.isWrongJiggle) {
          b.jiggleProgress += dt * 5.0;
          if (b.jiggleProgress >= 1.0) {
            b.isWrongJiggle = false;
            b.jiggleProgress = 0.0;
          }
        }
        // 答错的方块加速坠落；漏答的方块按原速下落。两者都落到堆叠顶面即垒起来。
        b.y += (b.isDoomed ? 520.0 : b.speed) * dt;
        b.x = b.baseX + sin(wavePhase * b.swingFreq) * b.swingAmplitude;

        if (b.y + b.height / 2 >= stackTopY) {
          _settleBrick(b, stackTopY);
        }
      }
    }

    for (int i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        particles.removeAt(i);
      } else {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 120.0 * dt;
      }
    }

    for (int i = _floatingTexts.length - 1; i >= 0; i--) {
      final ft = _floatingTexts[i];
      ft.life -= dt * 1.2;
      ft.y -= 28.0 * dt;
      if (ft.life <= 0) {
        _floatingTexts.removeAt(i);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _spawnBrickExplosion(double x, double y, Color baseColor) {
    for (int i = 0; i < 28; i++) {
      final angle = rand.nextDouble() * 2 * pi;
      final speed = 40.0 + rand.nextDouble() * 160.0;
      particles.add(BrickParticle(
        x: x + (rand.nextDouble() - 0.5) * 80.0,
        y: y + (rand.nextDouble() - 0.5) * 20.0,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 20.0,
        radius: 2.5 + rand.nextDouble() * 3.5,
        color: baseColor,
        life: 0.35 + rand.nextDouble() * 0.35,
      ));
    }
  }

  /// 下落竞技场底边：默认占屏幕高度的 60%；
  /// 屏幕较矮时优先给底部答题区（提示 + 三张释义卡 + 道具栏）留出足够高度，避免挤出屏幕。
  double _arenaBottomY(double screenHeight, double bottomInset) {
    final double bottomPanelHeight = 300.0 + max(0.0, bottomInset - 10.0);
    return min(screenHeight * 0.60, screenHeight - bottomPanelHeight);
  }

  /// 每一层死词砖占用的高度：把从出生点到防线的行程均分成 maxHp + 2 份，
  /// 多留两行余量，保证垒到第 10 层前仍有一小段可反应的下落距离。
  double _stackRowHeight(double barrierBottomY, double topPadding) {
    final double startY = max(topPadding, 16.0) + 62.0;
    return max(8.0, (barrierBottomY - startY) / (maxHp + 2));
  }

  /// 当前堆叠顶面（也是下一个方块真正的触底线）：堆得越高，下落行程越短。
  double _stackTopY(double barrierBottomY, double topPadding) {
    return barrierBottomY - stackRows.length * _stackRowHeight(barrierBottomY, topPadding);
  }

  void _addStackRows(int count, {String word = '', Color color = const Color(0xFF64748B)}) {
    for (int i = 0; i < count && stackRows.length < maxHp; i++) {
      stackRows.add(BrickStackRow(word: word, color: color));
    }
  }

  /// 方块落到堆叠顶面：垒成一层死词砖，扣 1 点防线生命，并上报本题答错。
  void _settleBrick(BrickItem b, double stackTopY) {
    if (!isPlaying) return;
    b.isPopping = true;
    b.popProgress = 0.0;
    _spawnBrickExplosion(b.x, stackTopY, const Color(0xFFEF4444));
    HapticFeedback.heavyImpact();
    // 先把本题判错上报给服务端，再在本地垒层并同步行数：
    // 服务端会为这次答错记一行，随后的 REPORT_STACK_ROWS 与它是同一个事实，取更严的一方即可。
    _reportAnswer('false');
    _applyDamage(
      1,
      reason: b.isDoomed ? '选错 -1 HP!' : '方块触底 -1 HP!',
      word: b.word,
      color: b.baseColor,
    );
  }

  void _applyDamage(int amount, {
    String reason = '受损 -1 HP!',
    String word = '',
    Color color = const Color(0xFF64748B),
  }) {
    if (!isPlaying) return;
    setState(() {
      _addStackRows(amount, word: word, color: color);
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
    // 方块砸进堆叠层 / 挨了对手攻击：一记沉重闷响。
    // 最后一击不播，交给结算的 failed/victory 音效，避免两个低频音叠在一起发闷。
    if (myHp > 0) {
      StudyAudioSessionController.instance.playSoundEffect('thud.mp3', speed: 0.9, volume: 0.65);
    }

    sendUserCmd('REPORT_STACK_ROWS', [stackRows.length]);
    if (myHp <= 0) {
      sendUserCmd('GAME_OVER', ['A']);
      _endGame(isWin: false);
    }
  }

  void _useProps(int propsIdx) {
    if (!isPlaying) return;
    if (propsIdx == 0 && propsMine > 0) {
      propsMine--;
      sendUserCmd('USE_PROPS', [propsIdx]);
      StudyAudioSessionController.instance.playSoundEffect('monster/throw_whoosh.wav', volume: 0.35);
      _floatingTexts.add(BrickFloatingText(x: 200, y: 300, text: '🚀 攻击 -1 HP!', color: const Color(0xFFEF4444)));
      setState(() => opponentHp = max(0, opponentHp - 1));
    } else if (propsIdx == 1 && propsStarfish > 0) {
      if (myHp >= maxHp) {
        _floatingTexts.add(BrickFloatingText(x: 200, y: 300, text: '防线已满格，无需治疗', color: const Color(0xFF38BDF8)));
        StudyAudioSessionController.instance.playSoundEffect('bubble-pop.wav', speed: 0.9, volume: 0.2);
        return;
      }
      propsStarfish--;
      setState(() => stackRows.removeLast());
      sendUserCmd('USE_PROPS', [propsIdx]);
      StudyAudioSessionController.instance.playSoundEffect('magic.mp3', speed: 1.25, volume: 0.4);
      _floatingTexts.add(BrickFloatingText(x: 200, y: 300, text: '✨ 治疗 +1 HP!', color: const Color(0xFF10B981)));
      sendUserCmd('REPORT_STACK_ROWS', [stackRows.length]);
    }
  }

  /// 服务端按时间推演出的权威堆叠行数：客户端挂后台、方块停在原地的那段时间会被补扣。
  /// 新协议载荷为 [userId, 堆叠行数, 原因]，广播给双方，对手的竖排血条据此更新；
  /// 旧服务端只发 [堆叠行数, 原因] 且只发给本人，这里兼容两种形态，避免升级服务端前血条失效。
  void _handleStackSync(dynamic data) {
    if (!mounted || !isPlaying || data is! List || data.isEmpty) return;

    final String userId;
    final int rows;
    final String reason;
    if (data.length >= 2 && data[1] is num) {
      userId = data[0]?.toString() ?? '';
      rows = (data[1] as num).toInt();
      reason = data.length > 2 ? data[2].toString() : '';
    } else if (data[0] is num) {
      userId = myUserId;
      rows = (data[0] as num).toInt();
      reason = data.length > 1 ? data[1].toString() : '';
    } else {
      return;
    }

    if (userId != myUserId) {
      setState(() {
        opponentHp = max(0, maxHp - rows);
      });
      return;
    }

    final int serverHp = max(0, maxHp - rows);
    // 两边对同一个事实各有一份推演，取更严的一方，服务端更宽松就不动本地
    if (serverHp >= myHp) return;

    final int lost = myHp - serverHp;
    setState(() {
      _addStackRows(lost);
      myCombo = 0;
      _hitFlash = 1.0;
    });
    _floatingTexts.add(BrickFloatingText(
      x: 100,
      y: 200,
      text: reason.isEmpty ? '⏳ 漏答 -$lost HP' : '⏳ $reason -$lost HP',
      color: const Color(0xFFEF4444),
    ));
    HapticFeedback.heavyImpact();
    if (myHp <= 0) {
      sendUserCmd('GAME_OVER', ['A']);
      _endGame(isWin: false);
    } else {
      // 服务端补扣（挂后台漏答）：用一记闷响提醒，最后一击交给结算音效
      StudyAudioSessionController.instance.playSoundEffect('thud.mp3', speed: 0.9, volume: 0.45);
    }
  }

  /// 服务端发放道具：数量以服务端为准，避免本地随机结果和真实库存各算一套。
  void _handleGiveProps(int propsType, int count) {
    setState(() {
      if (propsType == 0) {
        propsMine = count;
      } else {
        propsStarfish = count;
      }
    });
    _floatingTexts.add(BrickFloatingText(
      x: 200,
      y: 260,
      text: propsType == 0 ? '💣 获得攻击 ×$count' : '⭐ 获得治疗 ×$count',
      color: propsType == 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    ));
    StudyAudioSessionController.instance.playSoundEffect('bubble-pop.wav', speed: 1.2, volume: 0.3);
  }

  /// 对手使用道具：攻击扣我方 1 点防线，治疗给对手回 1 点。
  void _handlePropsUsed(String fromUserId, int propsType) {
    if (fromUserId == myUserId) return; // 自己用道具时已在本地即时表现
    if (propsType == 0) {
      _applyDamage(1, reason: '💥 遭受对手攻击！-1 HP');
    } else {
      setState(() => opponentHp = min(maxHp, opponentHp + 1));
      // 提示贴到右侧对手防线附近，让"对手把自己治回去了"这件事一眼可见
      final double screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 390;
      _floatingTexts.add(BrickFloatingText(
        x: screenWidth * 0.72,
        y: 220,
        text: '💚 对手治疗 +1 HP',
        color: const Color(0xFFFBBF24),
      ));
      // 对手治疗只给一个很远、很轻的魔法音，提示"对面把血回上去了"
      StudyAudioSessionController.instance.playSoundEffect('magic.mp3', speed: 1.35, volume: 0.15);
    }
  }

  void _handleLoser(dynamic loserId) {
    if (!mounted) return;
    final String id = loserId?.toString() ?? '';
    if (id.isEmpty) {
      Global.logger.e('消砖块: loser 事件缺少失败者ID，无法判定胜负');
      return;
    }
    _endGame(isWin: id != myUserId);
  }

  /// 本局结束（本地血尽或服务端判负广播 loser）：只结算一次。
  void _endGame({required bool isWin}) {
    if (!mounted || _resultShown) return;
    _resultShown = true;
    _tts.stop();
    StudyAudioSessionController.instance.playBlockingSound(
      isWin ? 'victory.mp3' : 'failed.mp3',
      timeoutMs: 2000,
    );
    setState(() {
      isPlaying = false;
      myStarted = false;
      if (isWin) {
        opponentHp = 0;
      } else {
        _addStackRows(maxHp - stackRows.length);
      }
      bricks.clear();
      currWord = null;
      currentOptions.clear();
      // 结算后 ticker 不再更新特效；不清掉的话最后一击的爆破微粒和飘字会永远定格在弹窗后面
      particles.clear();
      _floatingTexts.clear();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          isWin ? '🏆 消砖大捷！' : '💥 防线失守',
          style: TextStyle(
            color: isWin ? const Color(0xFFFBBF24) : const Color(0xFFEF4444),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          isWin ? '恭喜你成功击垮对方防线，赢得本局胜利！' : '错词方块堆满了防线，本局告负，再接再厉！',
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

  /// 服务端已经没有这一局了（断线期间被判负、房间已解散）：继续出题只会石沉大海
  void _handleGameNotInProgress(String cmd) {
    if (!mounted || _resultShown) return;
    _pendingUserCmds.clear();
    Global.logger.w('消砖块: 服务端已无本局对局（触发指令[$cmd]），退出对战界面');
    _exitBattleScreen('对局已结束或房间已解散，请重新开始');
  }

  /// 本连接被服务端顶掉（同一账号在别处登录）：退出对战界面
  void _handleForceClose(String reason) {
    if (!mounted || _resultShown) return;
    _pendingUserCmds.clear();
    Global.logger.w('消砖块: 连接被服务端关闭: $reason');
    _exitBattleScreen(reason.isEmpty ? '连接已被关闭' : '连接已被关闭：$reason');
  }

  void _exitBattleScreen(String message) {
    _tts.stop();
    setState(() {
      isPlaying = false;
      myStarted = false;
      stackRows.clear();
      bricks.clear();
      currWord = null;
      currentOptions.clear();
      particles.clear();
      _floatingTexts.clear();
    });
    ToastUtil.error(message);
    if (mounted) context.pop();
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    final double barrierBottomY = _arenaBottomY(mediaQuery.size.height, mediaQuery.padding.bottom);
    final double stackRowHeight = _stackRowHeight(barrierBottomY, topPadding);
    // 双方当前词都从同一份共享词序里按索引取，直接对照就能看出有没有被区别出题。
    // 对手已答 N 题时，他当前正在做的正是共享词序里索引 N 的那道题。
    final String myCurrentWord = _spellAt(myWordIndex) ?? currWord?.spell ?? '…';
    final String opponentCurrentWord = _spellAt(opponentWordCount) ?? '…';
    // 开局前 / 开场动画中还没有正在下落的词：名字上方不显示题号和当前单词
    final bool showBattleInfo = isPlaying && !isIntroPlaying && bricks.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 上半部下落竞技场绘制
          GestureDetector(
            onTap: () {
              if (currWord != null) {
                _tts.speak(currWord!.spell);
              }
            },
            child: CustomPaint(
              painter: _BrickScenePainter(
                bricks: bricks,
                stackRows: stackRows,
                particles: particles,
                floatingTexts: _floatingTexts,
                ambientParticles: _ambientParticles,
                barrierBottomY: barrierBottomY,
                stackRowHeight: stackRowHeight,
                maxStackRows: maxHp,
                myStackRows: stackRows.length,
                opponentStackRows: min(maxHp, max(0, maxHp - opponentHp)),
                opponentName: opponentNickName,
                myWordOrdinal: myWordIndex + 1,
                opponentWordOrdinal: opponentWordCount + 1,
                myCurrentWord: myCurrentWord,
                opponentCurrentWord: opponentCurrentWord,
                showBattleInfo: showBattleInfo,
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
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.grid_view_rounded, color: Color(0xFFF59E0B), size: 14),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '消砖块 · ${gameHall.hallName}${roomId != null ? ' · 房号$roomId' : ''}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (!isPlaying) ...[
                  const SizedBox(width: 8),
                  if (myStarted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.65), width: 1.0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF34D399)),
                          SizedBox(width: 4),
                          Text(
                            '已就绪',
                            style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: () {
                        sendUserCmd('START_GAME', []);
                        setState(() => myStarted = true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('开始对战', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    ),
                ],
              ],
            ),
          ),

          // 3. 双方竖排防线画在竞技场左右两侧（见画布），这里只保留答题区
          // 4. 下半部：中文释义三选一答题卡片区（紧凑块，提示、三张卡片、道具栏从上到下挨着排列）
          if (isPlaying)
            Positioned(
              top: barrierBottomY + 8,
              left: 18,
              right: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded, size: 13, color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(width: 4),
                      Text(
                        '看准上方单词，在方块触底前选出正确释义：',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < currentOptions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _buildOptionCard(currentOptions[i]),
                  ],
                  const SizedBox(height: 10),
                  // 道具操作栏紧贴答题卡片下方：治疗是给自己用的，放左侧（我方）；
                  // 攻击是打向对手的，放右侧（对手侧），位置和两侧竖排防线一一对应。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPropBtn(
                        icon: Icons.auto_awesome_rounded,
                        label: '治疗',
                        count: propsStarfish,
                        color: const Color(0xFF10B981),
                        onTap: () => _useProps(1),
                      ),
                      _buildPropBtn(
                        icon: Icons.rocket_launch_rounded,
                        label: '攻击',
                        count: propsMine,
                        color: const Color(0xFFEF4444),
                        onTap: () => _useProps(0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(BrickOption opt) {
    Color bgColor = const Color(0xFF1E293B).withValues(alpha: 0.88);
    Color borderColor = Colors.white.withValues(alpha: 0.12);
    Color textColor = Colors.white;

    if (opt.isSelected) {
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.35);
      borderColor = const Color(0xFF10B981);
      textColor = const Color(0xFF34D399);
    } else if (opt.isWrong) {
      bgColor = const Color(0xFFEF4444).withValues(alpha: 0.35);
      borderColor = const Color(0xFFEF4444);
      textColor = const Color(0xFFF87171);
    }

    return InkWell(
      onTap: () => _onOptionTapped(opt),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: opt.isSelected || opt.isWrong ? 1.5 : 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: opt.isSelected
                    ? const Color(0xFF10B981)
                    : (opt.isWrong ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.12)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  opt.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                opt.text,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

/// 消砖块专属场景绘制器
class _BrickScenePainter extends CustomPainter {
  final List<BrickItem> bricks;
  final List<BrickStackRow> stackRows;
  final List<BrickParticle> particles;
  final List<BrickFloatingText> floatingTexts;
  final List<BrickAmbientParticle> ambientParticles;
  final double barrierBottomY;
  final double stackRowHeight;
  final int maxStackRows;
  final int myStackRows;
  final int opponentStackRows;
  final String opponentName;
  final int myWordOrdinal;
  final int opponentWordOrdinal;
  final String myCurrentWord;
  final String opponentCurrentWord;
  final bool showBattleInfo;

  _BrickScenePainter({
    required this.bricks,
    required this.stackRows,
    required this.particles,
    required this.floatingTexts,
    required this.ambientParticles,
    required this.barrierBottomY,
    required this.stackRowHeight,
    required this.maxStackRows,
    required this.myStackRows,
    required this.opponentStackRows,
    required this.opponentName,
    required this.myWordOrdinal,
    required this.opponentWordOrdinal,
    required this.myCurrentWord,
    required this.opponentCurrentWord,
    required this.showBattleInfo,
  });

  double get _stackTopY => barrierBottomY - stackRows.length * stackRowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 深邃的方块竞技场背景
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

    // 4. 底部死词砖堆叠层
    _drawStack(canvas, size);

    // 5. 左右两侧竖排防线：格子高度与死词层完全同高，红色部分从底部往上长 = 堆叠高度
    _drawHpRail(canvas, size, left: true, lostRows: myStackRows, accent: const Color(0xFF34D399));
    _drawHpRail(canvas, size, left: false, lostRows: opponentStackRows, accent: const Color(0xFFF59E0B));
    _drawHpRailLabel(
      canvas,
      size,
      left: true,
      name: '我',
      word: myCurrentWord,
      ordinal: myWordOrdinal,
      showProgress: showBattleInfo,
      color: const Color(0xFF34D399),
    );
    _drawHpRailLabel(
      canvas,
      size,
      left: false,
      name: opponentName.isEmpty ? '对手' : opponentName,
      word: opponentCurrentWord,
      ordinal: opponentWordOrdinal,
      showProgress: showBattleInfo,
      color: const Color(0xFFF59E0B),
    );

    // 6. 当前堆叠顶面就是触底警戒线：堆得越高，这条线越往上压
    final double dangerLineY = _stackTopY;
    final barrierPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFEF4444).withValues(alpha: 0.15),
          const Color(0xFFEF4444).withValues(alpha: 0.9),
          const Color(0xFFEF4444).withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromLTWH(26, dangerLineY, size.width - 52, 2))
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(26, dangerLineY), Offset(size.width - 26, dangerLineY), barrierPaint);

    // 7. 下落单一目标英文单词大方块绘制
    for (final b in bricks) {
      _drawBrick(canvas, b);
    }

    // 8. 爆破微粒
    for (final p in particles) {
      final pPaint = Paint()
        ..color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x, p.y), p.radius, pPaint);
    }

    // 9. 飘字
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

  /// 底部死词层：从防线基准线往上垒，每层一个错词，越堆越高、越堆越窄的行程。
  void _drawStack(Canvas canvas, Size size) {
    for (int i = 0; i < stackRows.length; i++) {
      final row = stackRows[i];
      final double top = barrierBottomY - (i + 1) * stackRowHeight;
      final Rect rect = Rect.fromLTWH(26, top + 0.8, size.width - 52, stackRowHeight - 1.6);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));

      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(row.color, const Color(0xFF1E293B), 0.55)!,
            Color.lerp(row.color, const Color(0xFF0B1220), 0.74)!,
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, fill);

      final edge = Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRRect(rrect, edge);

      if (row.word.isEmpty || stackRowHeight < 12) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: row.word,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: min(12.0, stackRowHeight * 0.62),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 14);
      tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
    }
  }

  /// 单侧竖排防线：10 格从底部往上填，红色格子的高度与死词堆叠层严格同高。
  void _drawHpRail(Canvas canvas, Size size, {required bool left, required int lostRows, required Color accent}) {
    const double railWidth = 16.0;
    final double railHeight = maxStackRows * stackRowHeight;
    if (railHeight <= 0) return;
    final double railTop = barrierBottomY - railHeight;
    final double x = left ? 6.0 : size.width - 6.0 - railWidth;
    final RRect rail = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, railTop, railWidth, railHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(rail, Paint()..color = Colors.black.withValues(alpha: 0.30));
    canvas.drawRRect(
      rail,
      Paint()
        ..color = accent.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    const double gap = 1.5;
    final double cellHeight = max(2.0, stackRowHeight - gap * 2);
    for (int i = 0; i < maxStackRows; i++) {
      final bool filled = i >= maxStackRows - lostRows; // i=0 是最上面一格，所以从底部往上填
      final double cellTop = railTop + i * stackRowHeight + gap;
      final RRect cell = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2.5, cellTop, railWidth - 5, cellHeight),
        const Radius.circular(2),
      );
      if (!filled) {
        canvas.drawRRect(cell, Paint()..color = accent.withValues(alpha: 0.07));
        continue;
      }
      canvas.drawRRect(cell, Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.92));
      // 堆叠顶面那一格加一道高光，和中间那条警戒线对上
      if (i == maxStackRows - lostRows) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 2.5, cellTop, railWidth - 5, min(3.0, cellHeight)),
            const Radius.circular(2),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.5),
        );
      }
    }
  }

  /// 竖排防线顶部的三段信息：最上面是当前单词，下面是"第几个词"和名字。
  /// 双方都从同一份共享词序里按各自进度取词，摆在一起就能直接对照。
  /// 开局前 / 开场动画中还没有正在下落的词，此时只显示名字，不显示题号和单词。
  /// 生命值不再显示数字，直接看竖排亮了多少格即可。
  void _drawHpRailLabel(
    Canvas canvas,
    Size size, {
    required bool left,
    required String name,
    required String word,
    required int ordinal,
    required bool showProgress,
    required Color color,
  }) {
    final double railHeight = maxStackRows * stackRowHeight;
    final double railTop = barrierBottomY - railHeight;

    if (!showProgress) {
      final nameOnlyTp = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      final double height = nameOnlyTp.height;
      final double bgTop = railTop - height - 14;
      final double bgLeft = left ? 2.0 : size.width - 2.0 - (nameOnlyTp.width + 10);
      final RRect bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(bgLeft, bgTop, nameOnlyTp.width + 10, height + 6),
        const Radius.circular(8),
      );
      canvas.drawRRect(bg, Paint()..color = Colors.black.withValues(alpha: 0.42));
      canvas.drawRRect(
        bg,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      nameOnlyTp.paint(canvas, Offset(bgLeft + 5, bgTop + 3));
      return;
    }

    final currentTp = TextPainter(
      text: TextSpan(
        text: word,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);

    final countTp = TextPainter(
      text: TextSpan(
        text: '第$ordinal词',
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final nameTp = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 62);

    final double currentHeight = currentTp.height;
    final double metaHeight = max(countTp.height, nameTp.height);
    const double pad = 3;
    const double lineGap = 1;
    final double totalHeight = currentHeight + lineGap + metaHeight + pad * 2;
    final double bgTop = railTop - totalHeight - 8;
    final double currentY = bgTop + pad;
    final double metaY = currentY + currentHeight + lineGap;

    final double metaWidth = countTp.width + 5 + nameTp.width;
    final double contentWidth = max(currentTp.width, metaWidth);
    final double bgLeft = left ? 2.0 : size.width - 2.0 - (contentWidth + 10);
    final double contentLeft = bgLeft + 5;
    final double contentRight = contentLeft + contentWidth;

    final RRect bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(bgLeft, bgTop, contentWidth + 10, totalHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(bg, Paint()..color = Colors.black.withValues(alpha: 0.42));
    canvas.drawRRect(
      bg,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 当前单词在上：左侧靠左、右侧靠右，尽量贴近外侧避免被中间的下落方块挡住
    final double currentX = left ? contentLeft : contentRight - currentTp.width;
    currentTp.paint(canvas, Offset(currentX, currentY));

    // 题号贴外侧，名字在内侧
    final double countX = left ? contentLeft : contentRight - countTp.width;
    final double nameX = left ? countX + countTp.width + 5 : countX - 5 - nameTp.width;
    countTp.paint(canvas, Offset(countX, metaY + (metaHeight - countTp.height) / 2));
    nameTp.paint(canvas, Offset(nameX, metaY + (metaHeight - nameTp.height) / 2));
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
            width: b.width * scale,
            height: b.height * scale,
          ),
          const Radius.circular(16),
        ),
        popPaint,
      );
      return;
    }

    final double jiggleX = b.isWrongJiggle ? sin(b.jiggleProgress * pi * 4) * 6.0 : 0.0;
    final center = Offset(b.x + jiggleX, b.y);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    final rect = Rect.fromCenter(center: Offset.zero, width: b.width, height: b.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    // 方块外发光阴影
    final shadowPaint = Paint()
      ..color = b.baseColor.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(rrect, shadowPaint);

    // 基础渐变
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          b.baseColor,
          b.baseColor.withValues(alpha: 0.78),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // 顶部高光
    final hlRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(-b.width / 2 + 1, -b.height / 2 + 1, b.width - 2, b.height * 0.42),
      topLeft: const Radius.circular(15),
      topRight: const Radius.circular(15),
    );
    final hlPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.38),
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(hlRect.outerRect);
    canvas.drawRRect(hlRect, hlPaint);

    // 微边框
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(rrect, borderPaint);

    // 英文单词
    final textPainter = TextPainter(
      text: TextSpan(
        text: b.word,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          shadows: [
            Shadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 1.5)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: b.width - 16);

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
