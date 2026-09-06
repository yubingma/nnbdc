import 'dart:async' as async;
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame/particles.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/prefs.dart';

import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../services/throttled_sync_service.dart';
import '../util/app_clock.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'index.dart';

const brickHeight = 14.0;
late double screenWidth;
const playGroundHeight = 250.0;
const playGroundY = 60.0;
const bottomJetInitHeight = 2.0;
const bottomJetInitY = playGroundHeight + playGroundY;
// B方音效音量（相对于A方），统一从此处调整
const double bSideSfxVolume = 0.1;

class RussiaPage extends StatefulWidget {
  const RussiaPage({super.key});

  @override
  RussiaPageState createState() {
    return RussiaPageState();
  }
}

class RussiaPageState extends State<RussiaPage> {
  bool dataLoaded = false;

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  late GameHallVo gameHall;
  late int? exceptRoom;
  late MyGame myGame;

  /// 页面销毁时是否发送'LEAVE_HALL'命令
  bool leaveGameWhenDispose = true;

  Future<bool> checkArgs() async {
    final args = GoRouterState.of(context).extra;
    if (args == null || args is! List || args.length < 2) {
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        context.push('/index', extra: IndexPageArgs(3));
      });
      return false;
    }
    gameHall = args[0] as GameHallVo;
    exceptRoom = args[1] as int?;
    // args[2] 可选：{'mode':'createPrivate'} 或 {'joinRoomId': 123}
    return true;
  }

  @override
  void initState() {
    super.initState();

    // 禁用API调用时的loading窗口
    LoadingUtils.disableApiLoading();

    // 连接socket服务器
    SocketIoClient.instance.connect();

    // 告诉SocketIoClient当前在russia游戏页面
    SocketIoClient.instance.setInRussiaGame(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadData();
  }

  @override
  void dispose() {
    // 告诉SocketIoClient离开russia游戏页面
    SocketIoClient.instance.setInRussiaGame(false);

    // 移除断连监听器，避免内存泄漏
    if (dataLoaded) {
      SocketIoClient.instance.removeSocketStatusListener(
        _DisconnectListener(myGame, this),
      );
    }

    if (leaveGameWhenDispose) {
      myGame.leaveGame();
    }

    // 断开socket连接
    SocketIoClient.instance.disconnect();

    // 恢复API调用时的loading窗口
    LoadingUtils.enableApiLoading();

    super.dispose();
  }
  Future<void> loadData() async {
    if (!await checkArgs()) {
      return;
    }
    if (dataLoaded) return;
    if (!mounted) return;
    myGame = MyGame(gameHall, exceptRoom, context, this);
    setState(() {
      dataLoaded = true;
    });
  }

  /// 刷新页面
  void refreshPage() {
    Global.logger.d('开始刷新russia游戏页面');

    // 检查页面是否仍然挂载
    if (!mounted) {
      Global.logger.w('页面已销毁，跳过刷新操作');
      return;
    }

    // 如果当前有游戏实例，先清理资源
    if (dataLoaded) {
      // 移除断连监听器
      SocketIoClient.instance.removeSocketStatusListener(
        _DisconnectListener(myGame, this),
      );
      // 离开游戏
      myGame.leaveGame();
    }

    setState(() {
      dataLoaded = false;
    });
    loadData();
  }

  Widget renderPage() {
    return const Column();
  }

  @override
  Widget build(BuildContext context) {
    if (!dataLoaded) {
      return Container(
        color: const Color(0xFF0D1117),
        child: const Center(
          child: Text('waiting...', style: TextStyle(color: Colors.white70, decoration: TextDecoration.none)),
        ),
      );
    }
    return Container(
      color: const Color(0xFF0D1117),
      child: GameWidget(
        game: myGame,
      ),
    );
  }
}

class BottomJet extends PositionComponent {
  late Sprite brickImg;

  BottomJet() {
    add(RectangleHitbox());
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size.setValues(width, bottomJetInitHeight);
    anchor = Anchor.topLeft;
    var image = await Flame.images.load('brick.png');
    brickImg = Sprite(image);
  }

  Shader? _cachedShader;
  double? _lastHeight;

  @override
  void render(Canvas canvas) {
    Rect rect = size.toRect();

    // 绘制渐变背景
    if (_cachedShader == null || _lastHeight != height) {
      _lastHeight = height;
      _cachedShader = LinearGradient(
        colors: [
          const Color(0xFF4A90E2),
          const Color(0xFF357ABD),
          const Color(0xFF2E5F8A),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    }
    Paint backgroundPaint = Paint()..shader = _cachedShader;

    // 顶部圆角、底部直角
    final RRect roundedRect = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(roundedRect, backgroundPaint);

    // 绘制顶部高光（固定高度，不随千斤顶高度变化）
    const double fixedHighlightHeight = 6.0; // 固定高光高度
    final Rect highlightArea = Rect.fromLTWH(
      rect.left + 1,
      rect.top + 1,
      rect.width - 2,
      fixedHighlightHeight,
    );

    Paint highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.2),
          Colors.transparent,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(highlightArea);

    RRect highlightRect = RRect.fromRectAndRadius(
      highlightArea,
      const Radius.circular(5),
    );
    canvas.drawRRect(highlightRect, highlightPaint);

    // 绘制边框
    Paint borderPaint = Paint()
      ..color = const Color(0xFF5BA3F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(roundedRect, borderPaint);

    // 绘制砖块纹理
    const brickWidth = 32.0;
    Paint brickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.25;

    for (var i = 1; i * brickHeight <= height; i++) {
      for (var j = 1; j * brickWidth <= width; j++) {
        Rect brickRect = Rect.fromLTWH(
          (j - 1) * brickWidth,
          (i - 1) * brickHeight + 1,
          brickWidth,
          brickHeight,
        );
        canvas.drawRect(brickRect, brickPaint);
      }
    }
  }
}

class PlayGround extends PositionComponent {
  static const speed = 0.25;
  static const squareSize = 128.0;
  static Paint white = BasicPalette.white.paint();
  static Paint red = BasicPalette.red.paint();
  static Paint blue = BasicPalette.blue.paint();
  static Paint green = BasicPalette.green.paint();

  Shader? _cachedShader;

  @override
  void render(Canvas canvas) {
    Rect rect = size.toRect();

    // 绘制渐变背景（半透明 0.7）
    _cachedShader ??= LinearGradient(
      colors: [
        const Color(0xFF1A1A2E).withValues(alpha: 0.7),
        const Color(0xFF16213E).withValues(alpha: 0.7),
        const Color(0xFF0F3460).withValues(alpha: 0.7),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);

    Paint backgroundPaint = Paint()..shader = _cachedShader;

    // 顶部圆角、底部直角
    RRect roundedRect = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(roundedRect, backgroundPaint);

    // 绘制边框（半透明 0.7）
    Paint borderPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(roundedRect, borderPaint);

    // 绘制网格线
    Paint gridPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.15)
      ..strokeWidth = 1;

    // 垂直网格线
    for (double x = 20; x < width; x += 20) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        gridPaint,
      );
    }

    // 水平网格线
    for (double y = 20; y < height; y += 20) {
      canvas.drawLine(
        Offset(0, y),
        Offset(width, y),
        gridPaint,
      );
    }
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size.setValues(width, height);
    anchor = Anchor.topLeft;
  }
}

class Player {
  late String type;
  bool started = false;
  var props = [0, 0]; // 每种道具的数量
  var wordIndex = 0;

  //var deadWords = [];
  var correctCount = 0;
  var currWordTop = 0;
  var playGroundHeight = 200;
  var bottomTop = 200; // 千斤顶的顶端位置
  var bottomHeight = 0;
  WordVo? currWord;
  var otherWordMeanings = []; // 所有备选答案的内容
  var correctIndex = -1; // 正确答案序号
  String? userId;
  UserGameInfo? userGameInfo;
  late UserInfoPanel userInfoPanel;
  var deadWords = <DroppingWordSprite>[];
  DroppingWordSprite? droppingWordSprite;
  late PlayGround playGround;
  late BottomJet bottomJet;
  var scoreAdjust = 0;
  var cowdungAdjust = 0;
  bool? isWonInLastGame; // 上局比赛是否获胜

  Player(this.type);
}

class MyGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  final playerA = Player('A');
  final playerB = Player('B');
  final RussiaPageState pageState;

  // 断连检测相关
  bool _isDisconnected = false;
  late TextComponent _disconnectHint;
  Timer? _disconnectTimer;

  /// 计算单词的标准高度（基于字体信息）
  static double calculateWordHeight(double uiScale) {
    // 统一与 DroppingWordSprite.onLoad 逻辑：playground 高度的 1/10
    final double scaledPH = playGroundHeight * uiScale;
    return (scaledPH - 4) / 10.0;
  }

  late SpriteComponent plusBtn;
  late SpriteComponent minusBtn;
  late TextComponent plusPropsCount;
  late TextComponent minusPropsCount;
  late TextComponent vsBadge;
  late MyButton startGameBtn;
  late MyButton changeRoomBtn;
  late MyButton exerciseBtn;
  late MyButton exitBtn;
  late MyButton answer1Btn;
  late MyButton answer2Btn;
  late MyButton answer3Btn;
  late MyButton answer4Btn;
  late MyButton answer5Btn;
  late TextComponent gameResultHint1;
  late TextComponent gameResultHint2;
  late TextComponent countdownText;

  bool isPlaying = false;
  bool isShowingResult = false;
  int countdownSeconds = 0;
  var gameState = '';
  var allButtons = <MyButton>[];
  GameHallVo gameHall;
  late int? exceptRoom;
  var roomId = -1;
  var isExercise = false;
  var msgs = [];
  BuildContext context;
  double screenWidth;

  // 进入房间超时检测
  async.Timer? _enterRoomTimer;

  // 标记是否需要在socket连接成功后进入游戏大厅
  bool _needEnterHallAfterConnect = false;
  // 基于屏幕宽度计算的等比缩放系数（用于大屏设备，如 iPad）
  final double uiScale;
  // 按钮尺寸固定：渲染时仅计算一次，后续不再改变

  // 标记是否已为当前wordB上报过ETA
  bool _reportedFallBForCurrentWord = false;

  // 串行化每侧的落地处理，避免并发导致重复入栈
  bool _landingAInProgress = false;
  bool _landingBInProgress = false;
  // 说明：机器人道具使用逻辑由后端控制；前端不做本地自动触发
  // 布局缓存状态
  String? _lastGameState;
  bool? _lastIsPlaying;
  bool? _lastShowingResult;
  bool? _lastHasGameInfoA;
  bool? _lastHasGameInfoB;
  bool? _lastStarted;
  int? _lastWordCountA;
  bool? _lastHasCountdown;
  bool _needsButtonLayout = true;

  bool tryBeginLanding(Player player) {
    if (player == playerA) {
      if (_landingAInProgress) return false;
      _landingAInProgress = true;
      return true;
    } else {
      if (_landingBInProgress) return false;
      _landingBInProgress = true;
      return true;
    }
  }

  void endLanding(Player player) {
    if (player == playerA) {
      _landingAInProgress = false;
    } else {
      _landingBInProgress = false;
    }
  }

  // 按比例缩放后的尺寸（仅放大 playground 相关）
  late double scaledPlayGroundWidth;
  late double scaledPlayGroundHeight;
  late double scaledPlayGroundY;
  late double scaledBottomJetInitY;

  // 背景图层
  PositionComponent? backgroundLayer;

  MyGame(this.gameHall, this.exceptRoom, this.context, this.pageState)
      : screenWidth = MediaQuery.of(context).size.width,
        uiScale = max(1.0, min(MediaQuery.of(context).size.width / 390.0, min(MediaQuery.of(context).size.height / 844.0, 2.0)));

  // 背景切换逻辑已移除

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 性能预热：字体引擎极致预热
    // 仅仅 getLineMetrics 有时不足以触发 GPU 纹理上传，
    // 我们创建一个隐形的 TextComponent 强制引擎完成完整的绘制路径。
    final warmUpPaint = TextPaint(style: const TextStyle(fontSize: 24, fontFamily: 'NotoSansSC', color: Colors.transparent));
    final warmUpText = TextComponent(
      text: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ确定取消返回积分等级奖励卡顿预热', 
      textRenderer: warmUpPaint,
      position: Vector2(-9999, -9999), // 画在屏幕外
    );
    add(warmUpText);
    // 强制执行一次逻辑以触发内部缓存
    warmUpPaint.getLineMetrics(warmUpText.text);

    // 性能预热：提前配置音频会话
    async.unawaited(StudyAudioSessionController.instance.configureSession());

    // 基于屏幕宽度计算缩放后的布局尺寸
    const basePlayGroundWidth = 160.0;
    scaledPlayGroundWidth = basePlayGroundWidth * uiScale;
    scaledPlayGroundHeight = playGroundHeight * uiScale;
    scaledPlayGroundY = playGroundY * uiScale;
    // 让地板（BottomJet）的底边与 playground 底部重合
    // 即：地板顶边 = playground 底部 - 地板厚度
    scaledBottomJetInitY = scaledPlayGroundHeight + scaledPlayGroundY - bottomJetInitHeight;

    // 初始化断连提示组件
    _disconnectHint = TextComponent(
      text: '网络连接已断开，游戏即将退出...',
      textRenderer: TextPaint(
        style: TextStyle(
          color: Colors.red,
          fontSize: 16 * uiScale,
          fontWeight: FontWeight.w500,
          fontFamily: 'NotoSansSC',
          shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    )
      ..anchor = Anchor.bottomCenter
      ..x = size.x / 2
      ..y = size.y - 20
      ..priority = 1000; // 确保显示在最上层
    // 初始背景（在最底层）：缓慢旋转的银河系
    backgroundLayer = SpiralGalaxyBackground()
      ..width = size.x
      ..height = size.y
      ..x = 0
      ..y = 0
      ..priority = -100;
    add(backgroundLayer!);
    final playGroundMargin = max(8.0, (screenWidth - scaledPlayGroundWidth * 2) / 3);
    playerA.playGround = PlayGround()
      ..width = scaledPlayGroundWidth
      ..height = scaledPlayGroundHeight
      ..x = playGroundMargin
      ..y = scaledPlayGroundY;
    playerB.playGround = PlayGround()
      ..width = scaledPlayGroundWidth
      ..height = scaledPlayGroundHeight
      ..x = scaledPlayGroundWidth + playGroundMargin * 2
      ..y = scaledPlayGroundY;
    add(playerA.playGround);
    add(playerB.playGround);
    // 同步玩家用于逻辑判断的高度（等比缩放后）
    playerA.playGroundHeight = scaledPlayGroundHeight.toInt();
    playerB.playGroundHeight = scaledPlayGroundHeight.toInt();

    playerA.userInfoPanel = UserInfoPanel(playerA)
      ..width = playerA.playGround.width
      ..height = playerA.playGround.height
      ..x = playerA.playGround.x
      ..y = playerA.playGround.y;
    playerB.userInfoPanel = UserInfoPanel(playerB)
      ..width = playerB.playGround.width
      ..height = playerB.playGround.height
      ..x = playerB.playGround.x
      ..y = playerB.playGround.y;
    add(playerA.userInfoPanel);
    add(playerB.userInfoPanel);

    playerA.bottomJet = BottomJet()
      ..width = scaledPlayGroundWidth
      ..x = playGroundMargin
      ..y = scaledBottomJetInitY;
    add(playerA.bottomJet);

    playerB.bottomJet = BottomJet()
      ..width = scaledPlayGroundWidth
      ..x = scaledPlayGroundWidth + playGroundMargin * 2
      ..y = scaledBottomJetInitY;
    add(playerB.bottomJet);

    // 道具
    var minusImg = await Sprite.load('minus.png');
    minusBtn = SpriteComponent(position: Vector2(64.0, 64.0), sprite: minusImg, size: Vector2(48, 48))
      ..anchor = Anchor.topCenter
      ..x = playerA.playGround.x + playerA.playGround.width / 2
      ..y = playerA.playGround.y + playerA.playGround.height + 16;
    add(minusBtn);
    var plusImg = await Sprite.load('plus.png');
    plusBtn = SpriteComponent(position: Vector2(48.0, 64.0), sprite: plusImg, size: Vector2(48, 48))
      ..anchor = Anchor.topCenter
      ..setAlpha(255)
      ..x = playerB.playGround.x + playerB.playGround.width / 2
      ..y = playerB.playGround.y + playerB.playGround.height + 16;
    add(plusBtn);

    // 道具数量
    var textRender = TextPaint(
        style:
            TextStyle(color: const Color(0xFF4CAF50), fontSize: 14 * uiScale, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
      Shadow(
        color: Colors.black87,
        offset: Offset(1, 1),
        blurRadius: 2,
      ),
    ]));
    plusPropsCount = TextComponent(text: '0', textRenderer: textRender)
      ..anchor = Anchor.topRight
      ..x = plusBtn.x + plusBtn.width / 2
      ..y = plusBtn.y - 6;
    add(plusPropsCount);
    minusPropsCount = TextComponent(text: '0', textRenderer: textRender)
      ..anchor = Anchor.topRight
      ..x = minusBtn.x + minusBtn.width / 2
      ..y = minusBtn.y - 6;
    add(minusPropsCount);

    // 对战 VS 徽标（两面板之间中央，仅非比赛时显示）
    vsBadge = TextComponent(
        text: 'VS',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF6D8CFF), fontSize: 17 * uiScale, fontWeight: FontWeight.w800, fontFamily: 'NotoSansSC', letterSpacing: 1, shadows: const [
          Shadow(color: Colors.black87, offset: Offset(1, 1), blurRadius: 4),
          Shadow(color: Color(0xFF6D8CFF), offset: Offset(0, 0), blurRadius: 10),
        ])))
      ..anchor = Anchor.center
      ..x = (playerA.playGround.x + playerA.playGround.width + playerB.playGround.x) / 2
      ..y = playerA.playGround.y + playerA.playGround.height / 2
      ..priority = 3;
    add(vsBadge);

    startGameBtn = MyButton('开始比赛', this, style: ButtonStyle.primary)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(startGameBtn);
    startGameBtn.onReleased = () {
      startMatch();
    };

    changeRoomBtn = MyButton(makeChangeRoomBtnText(), this, style: ButtonStyle.secondary)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(changeRoomBtn);
    changeRoomBtn.onReleased = () {
      changeRoom();
    };

    exerciseBtn = MyButton('单人练习', this, style: ButtonStyle.secondary)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(exerciseBtn);
    exerciseBtn.onReleased = () {
      exercise();
    };

    exitBtn = MyButton('离开', this, style: ButtonStyle.tertiary)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(exitBtn);
    exitBtn.onReleased = () {
      Navigator.pop(context, true);
    };

    // 无设置：不再提供背景切换按钮

    // 答题按钮
    answer1Btn = MyButton('', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(answer1Btn);
    answer2Btn = MyButton('', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(answer2Btn);
    answer3Btn = MyButton('', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(answer3Btn);
    answer4Btn = MyButton('不认识', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(answer4Btn);
    answer5Btn = MyButton('结束练习', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(answer5Btn);
    answer1Btn.onPressed = () {
      onAnswerClicked(1);
    };
    answer2Btn.onPressed = () {
      onAnswerClicked(2);
    };
    answer3Btn.onPressed = () {
      onAnswerClicked(3);
    };
    answer4Btn.onPressed = () {
      onAnswerClicked(4);
    };
    answer5Btn.onReleased = () {
      onAnswerClicked(5);
    };

    // 比赛结果提示文字 - 清晰化：加粗 + 单层锐利投影
    textRender = TextPaint(
        style:
            TextStyle(color: const Color(0xFF4CAF50), fontSize: 16 * uiScale, fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC', shadows: const [
      Shadow(
        color: Colors.black87,
        offset: Offset(0, 2),
        blurRadius: 0,
      ),
    ]));
    gameResultHint1 = TextComponent(text: 'hint1', textRenderer: textRender)
      ..anchor = Anchor.topCenter
      ..x = screenWidth / 2
      ..y = playerA.playGround.y + playerA.playGround.height + 120;
    add(gameResultHint1);
    gameResultHint2 = TextComponent(text: 'hint2', textRenderer: textRender)
      ..anchor = Anchor.topCenter
      ..x = screenWidth / 2
      ..y = playerA.playGround.y + playerA.playGround.height + 160;
    add(gameResultHint2);

    // 倒计时文字 - 清晰化：加粗 + 干净金色 + 单层锐利投影
    var countdownRender = TextPaint(
        style: TextStyle(
            color: const Color(0xFFFFD54F),
            fontSize: 20 * uiScale,
            fontWeight: FontWeight.w700,
            fontFamily: 'NotoSansSC',
            shadows: const [
          Shadow(
            color: Colors.black87,
            offset: Offset(0, 2),
            blurRadius: 0,
          ),
        ]));
    countdownText = TextComponent(text: '', textRenderer: countdownRender)
      ..anchor = Anchor.topCenter
      ..x = screenWidth / 2
      ..y = playerA.playGround.y + playerA.playGround.height + 220;
    add(countdownText);

    initSocket();

    // 注意：不能立即调用 tryEnterGameHall，因为socket可能还未连接
    // 标记需要在连接成功后进入大厅，实际进入将在onConnected回调中执行
    _needEnterHallAfterConnect = true;

    // 如果socket已经连接（引用计数>1的复用连接情况），立即进入大厅
    var socket = SocketIoClient.instance.socket;
    if (socket.connected) {
      Global.logger.d('Socket已连接，立即进入游戏大厅');
      tryEnterGameHall();
      _needEnterHallAfterConnect = false;
    } else {
      Global.logger.d('Socket未连接，等待连接成功后进入游戏大厅');
    }

    //newDroppingWordA();

    //newDroppingWordA(playerB);
  }

  void leaveGame() {
    Global.logger.d('离开游戏，取消所有定时器');

    // 取消进入房间超时定时器
    _enterRoomTimer?.cancel();
    _enterRoomTimer = null;

    sendUserCmd('LEAVE_HALL', []);
  }

  void startCountdown() {
    countdownSeconds = 4;
    countdownText.text = '$countdownSeconds秒后重新开始';

    void updateCountdown() {
      if (countdownSeconds > 0) {
        countdownText.text = '$countdownSeconds秒后重新开始';
        countdownSeconds--;
        Future.delayed(const Duration(seconds: 1), updateCountdown);
      } else {
        countdownText.text = '';
      }
    }

    Future.delayed(const Duration(seconds: 1), updateCountdown);
  }

  String makeChangeRoomBtnText() {
    return '换房间 · 房号 $roomId';
  }

  TextRenderer textRenderOfGameResultHint(bool? won) {
    if (won == null) {
      return TextPaint(
          style: TextStyle(color: Colors.white, fontSize: 16 * uiScale, fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC', shadows: const [
        Shadow(
          color: Colors.black87,
          offset: Offset(0, 2),
          blurRadius: 0,
        ),
      ]));
    } else if (won) {
      return TextPaint(
          style: TextStyle(
              color: const Color(0xFF4CAF50),
              fontSize: 18 * uiScale,
              fontWeight: FontWeight.w700,
              fontFamily: 'NotoSansSC',
              shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(0, 2),
              blurRadius: 0,
            ),
          ]));
    } else {
      return TextPaint(
          style: TextStyle(
              color: const Color(0xFFF44336),
              fontSize: 18 * uiScale,
              fontWeight: FontWeight.w700,
              fontFamily: 'NotoSansSC',
              shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(0, 2),
              blurRadius: 0,
            ),
          ]));
    }
  }

  void _updateGameResultTexts(bool? isWon) {
    if (isExercise) {
      gameResultHint1.text = '练习结束！';
      gameResultHint2.text = '回答错误的单词，已被自动加入到生词本';
      gameResultHint1.textRenderer = textRenderOfGameResultHint(null);
      gameResultHint2.textRenderer = textRenderOfGameResultHint(null);
    } else {
      if (isWon == null) {
        gameResultHint1.text = '游戏结束！';
        gameResultHint2.text = '回答错误的单词，已被自动加入到生词本';
      } else {
        gameResultHint1.text = isWon ? '胜利啦！' : '失败了，别灰心，继续努力！';
        String scoreStr = playerA.scoreAdjust >= 0 ? "+${playerA.scoreAdjust}" : "${playerA.scoreAdjust}";
        String cowDungStr = playerA.cowdungAdjust >= 0 ? "+${playerA.cowdungAdjust}" : "${playerA.cowdungAdjust}";
        gameResultHint2.text = '游戏分 $scoreStr, 魔法泡泡 $cowDungStr';
      }
      gameResultHint1.textRenderer = textRenderOfGameResultHint(isWon);
      gameResultHint2.textRenderer = textRenderOfGameResultHint(isWon);
    }
  }

  void onAnswerClicked(btnIndex) {
    if (!isPlaying) {
      return;
    }

    if (btnIndex == 5) {
      // 练习结束
      isPlaying = false;
      sendGameOverCmd('A');
    } else if (btnIndex == playerA.correctIndex) {
      // 选对了：核心优化 - 立即抢先请求下一个单词，最大限度压缩网络往返感官延迟
      if (isPlaying) {
        sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, 'true', playerA.currWord!.spell]);
      }

      if (playerA.droppingWordSprite != null) {
        // 爆炸特效与音效异步执行
        async.unawaited(playExplosionAtDropping(playerA.droppingWordSprite!, volume: 1.0));
        playerA.droppingWordSprite?.removeFromParent();
        playerA.droppingWordSprite = null;
      }
      return;
    } else {
      // 选错了
      // 本地加入生词本（由前端负责，随后由同步机制推送到后端）
      try {
        final spell = playerA.currWord?.spell;
        if (spell != null && spell.isNotEmpty) {
          WordBo().addRawWord(spell, '游戏');
        }
      } catch (e, stackTrace) {
        // 添加生词失败不影响游戏流程，但需要记录
        Global.logger.w('添加生词失败', error: e, stackTrace: stackTrace);
      }
      dropWord2Bottom(playerA);
    }
  }

  void dropWord2Bottom(Player player) {
    // 落地串行化：已有落地在处理则忽略
    if (!tryBeginLanding(player)) {
      return;
    }
    try {
      var y = getDeadWordsTopY(player);
      final sprite = player.droppingWordSprite;
      if (sprite != null) {
        // 已经处理过落地，直接返回（幂等保护）
        if (sprite.isDead || sprite.skipCollision || (sprite as dynamic).hasLanded == true) {
          return;
        }
        // 标记跳过碰撞落地逻辑，避免重复触发落地
        sprite.skipCollision = true;
        sprite.y = y - sprite.height;
        // 手动完成一次落地堆叠
        sprite.isDead = true;
        // 立即切换为红色样式，并清空轨迹，避免残留绿边
        sprite._trailYs.clear();
        final TextStyle base = DroppingWordSprite.makeDeadPaint().style;
        sprite.textRenderer = TextPaint(style: base.copyWith(fontSize: sprite._fixedFontSize));
        sprite.text = sprite.text;
        sprite.hasLanded = true;
        if (player == playerA) {
          if (!playerA.deadWords.contains(sprite)) {
            playerA.deadWords.add(sprite);
          }
          if (playerA.droppingWordSprite == sprite) playerA.droppingWordSprite = null;
        } else {
          if (!playerB.deadWords.contains(sprite)) {
            playerB.deadWords.add(sprite);
          }
          if (playerB.droppingWordSprite == sprite) playerB.droppingWordSprite = null;
        }
        // 上报当前堆叠行数（仅 A 玩家上报）
        if (player == playerA) {
          final int rowsNow = playerA.deadWords.length;
          sendUserCmd('REPORT_STACK_ROWS', [rowsNow]);
        }
        // 播放落地音效（与碰撞保持一致的体验）
        final double thudVolume = (player == playerA) ? 1.0 : bSideSfxVolume;
        StudyAudioSessionController.instance.playSoundWithCut('thud.mp3', speed: 1.0, volume: thudVolume, maxPlay: const Duration(milliseconds: 1500));

        // 触顶判负：单词落地后，操场剩余高度不足以再容纳一个单词
        final double playgroundTop = player.playGround.y;
        final double remaining = sprite.y - playgroundTop; // 顶部到操场顶的剩余高度
        if (remaining < sprite.height) {
          isPlaying = false;
          sendGameOverCmd(player.type);
          return;
        }

        // A方落地后立即请求下一个单词，不再等待任何逻辑
        if (player == playerA) {
          sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, 'false', playerA.currWord!.spell]);
        }
      }
    } catch (e, st) {
      Global.logger.e('dropWord2Bottom 发生异常: $e', error: e, stackTrace: st);
    } finally {
      endLanding(player);
    }
  }

  // 在指定下落单词位置播放爆炸粒子与音效
  Future<void> playExplosionAtDropping(DroppingWordSprite sprite, {double volume = 1.0}) async {
    // 粒子（简单的烟花/碎片效果）
    final position = Vector2(sprite.x, sprite.y);
    final particle = ParticleSystemComponent(
      particle: Particle.generate(
        count: 24,
        lifespan: 0.35,
        generator: (i) {
          final rnd = Random();
          final speed = 80 + rnd.nextDouble() * 80;
          final angle = rnd.nextDouble() * 2 * pi;
          final vx = cos(angle) * speed;
          final vy = sin(angle) * speed;
          final color = Colors.primaries[rnd.nextInt(Colors.primaries.length)].shade300;
          return AcceleratedParticle(
            position: position.clone(),
            speed: Vector2(vx, vy),
            acceleration: Vector2(0, 320),
            child: CircleParticle(
              radius: 1.8,
              paint: Paint()..color = color,
            ),
          );
        },
      ),
    );
    add(particle);
    // 音效：使用 bubble-pop，增加时长到 1.5s 以确保播放完整
    await StudyAudioSessionController.instance.playSoundWithCut('bubble-pop.wav', speed: 1.0, volume: volume, maxPlay: const Duration(milliseconds: 1500));
  }

  void initSocket() {
    var socket = SocketIoClient.instance.socket;

    // 添加断连检测监听器
    SocketIoClient.instance.socketStatusListeners.add(
      _DisconnectListener(this, pageState),
    );

    // 添加服务端错误响应监听器
    socket.off('error');
    socket.on('error', (data) {
      String errorMsg = data is String ? data : (data['message'] ?? '未知错误');
      Global.logger.e('收到服务端错误: $errorMsg');
      safeShowToast('操作失败：$errorMsg');

      // 如果是进入房间相关的错误，取消超时定时器
      _enterRoomTimer?.cancel();
      _enterRoomTimer = null;
    });

    socket.off('sysCmd');
    socket.on('sysCmd', (cmd) {
      if (cmd == 'BEGIN_EXERCISE') {
        isExercise = true;
        startGame();
        appendMsg(0, '牛牛', '练习开始');
      } else if (cmd == 'BEGIN') {
        isExercise = false;
        startGame();
        appendMsg(0, '牛牛', '比赛开始');
      } else {
        safeShowToast('不支持的系统命令：$cmd');
      }
    });

    socket.off('wordA');
    socket.on('wordA', (data) {
      if (!isPlaying) {
        return;
      }

      playerA.currWord = WordVo.fromJson(data[0]);
      playerA.otherWordMeanings = data[1];

      // 为正确答案随机选择一个索引号（1～3）
      var rng = Random();
      var correctIndex = rng.nextInt(3) + 1;
      playerA.correctIndex = correctIndex;

      newDroppingWord(playerA.currWord!, playerA.otherWordMeanings, playerA);
      // 核心优化： staggered 错峰执行。
      // 新单词生成需要处理 UI 组件挂载，延迟 50ms 播放发音能避开瞬间 CPU 峰值。
      Future.delayed(const Duration(milliseconds: 50), () {
        if (isPlaying) {
          StudyAudioSessionController.instance.playWordSound(playerA.currWord!);
        }
      });
    });

    // 服务端通知：生词已加入（无需等待同步，前端可直接提示）
    // 不再需要服务端通知 rawWordAdded，前端在答错时即可本地加入

    socket.off('wordB');
    socket.on('wordB', (data) {
      if (!isPlaying) {
        return;
      }
      if (isExercise) {
        return;
      }
      var answerResult = data[0];
      // 新词抵达，重置"仅上报一次"的开关
      _reportedFallBForCurrentWord = false;
      if (answerResult == 'true') {
        final nextWord = WordVo.c2(data[1]);
        if (playerB.droppingWordSprite != null) {
          // B方爆炸声也使用 unawaited，不再阻塞下一词出现
          async.unawaited(playExplosionAtDropping(playerB.droppingWordSprite!, volume: bSideSfxVolume));
          playerB.droppingWordSprite?.removeFromParent();
          playerB.droppingWordSprite = null;
          
          playerB.currWord = nextWord;
          newDroppingWord(playerB.currWord!, playerB.otherWordMeanings, playerB);
          _reportFallEtaBOnce();
          return;
        }
        playerB.droppingWordSprite = null;
        playerB.currWord = nextWord;
        newDroppingWord(playerB.currWord!, playerB.otherWordMeanings, playerB);
        _reportFallEtaBOnce();
      } else if (answerResult == 'false') {
        dropWord2Bottom(playerB);
        playerB.currWord = WordVo.c2(data[1]);
        newDroppingWord(playerB.currWord!, playerB.otherWordMeanings, playerB);
        _reportFallEtaBOnce();
      } else {
        // 第一个单词, 还没有答题, 无所谓对错
        final nextWord = WordVo.c2(data[1]);
        playerB.currWord = nextWord;
        newDroppingWord(playerB.currWord!, playerB.otherWordMeanings, playerB);
        _reportFallEtaBOnce();
      }
    });

    socket.off('userGameInfo');
    socket.on('userGameInfo', (data) {
      var userGameInfo = UserGameInfo.fromJson(data);
      var player = userGameInfo.userId == Global.getLoggedInUser()!.id ? playerA : playerB;
      player.userGameInfo = userGameInfo;
    });

    socket.off('enterRoom');
    socket.on('enterRoom', (data) {
      var userId = data[0];
      var nickName = data[1];
      var player = userId == Global.getLoggedInUser()!.id ? playerA : playerB;
      player.userId = userId;
      // 清空上一局的游戏结果信息和开始状态（新用户进来，应该是干净的状态）
      player.isWonInLastGame = null;
      player.scoreAdjust = 0;
      player.cowdungAdjust = 0;
      player.started = false;
      StudyAudioSessionController.instance.playBlockingSound('door.mp3', speed: 2.5, volume: 0.5, timeoutMs: 2000);
      appendMsg(0, '牛牛', '$nickName进来了');
    });

    socket.off('leaveRoom');
    socket.on('leaveRoom', (data) {
      var userId = data[0];
      var nickName = data[1];
      var player = userId == Global.getLoggedInUser()!.id ? playerA : playerB;
      player.userId = null;
      player.userGameInfo = null;
      // 清空上一局的游戏结果信息和开始状态
      player.isWonInLastGame = null;
      player.scoreAdjust = 0;
      player.cowdungAdjust = 0;
      player.started = false;
      StudyAudioSessionController.instance.playBlockingSound('door.mp3', speed: 2.5, volume: 0.5, timeoutMs: 2000);
      appendMsg(0, '牛牛', '$nickName离开了');
    });

    socket.off('loser');
    socket.on('loser', (user) {
      isPlaying = false;
      isShowingResult = true;
      startCountdown(); // 开始倒计时
      Future.delayed(const Duration(milliseconds: 4000), () => {isShowingResult = false});

      // 重置双方的游戏开始状态，为下一局做准备
      playerA.started = false;
      playerB.started = false;

      // 判定输赢方：与双方的 userId 比较，确保 A/B 两侧都设置 isWonInLastGame
      final bool aIsLoser = (playerA.userId != null && user == playerA.userId);
      final bool bIsLoser = (playerB.userId != null && user == playerB.userId);

      if (aIsLoser) {
        playerA.isWonInLastGame = false;
        playerB.isWonInLastGame = true;
      } else if (bIsLoser) {
        playerA.isWonInLastGame = true;
        playerB.isWonInLastGame = false;
      } else {
        // 回退：如果服务端传的是当前登录用户ID的简化分支（兼容旧逻辑）
        if (user == Global.getLoggedInUser()!.id) {
          playerA.isWonInLastGame = false;
          playerB.isWonInLastGame = true;
        } else {
          playerA.isWonInLastGame = true;
          playerB.isWonInLastGame = false;
        }
      }

      // 设置文案与视觉反馈
      _updateGameResultTexts(playerA.isWonInLastGame);

      if (aIsLoser || user == Global.getLoggedInUser()!.id) {
        if (!isExercise) {
          appendMsg(0, '牛牛', '失败了，别灰心，继续努力！');
        }
        StudyAudioSessionController.instance.playBlockingSound('failed.mp3', speed: 1, volume: 1, timeoutMs: 2000);
      } else {
        if (!isExercise) {
          appendMsg(0, '牛牛', '胜利啦！');
        }
        StudyAudioSessionController.instance.playBlockingSound('victory.mp3', speed: 1, volume: 1, timeoutMs: 2000);
      }
    });

    socket.off('giveProps');
    socket.on('giveProps', (data) {
      var propsType = data[0];
      var propsCount = data[1];
      playerA.props[propsType] = propsCount;

      // 显示道具获得提示
      String propsName = propsType == 0 ? "加一行" : "减一行";
      appendMsg(0, "牛牛", "恭喜！连续答对5次，获得道具【$propsName】");

      // 道具用途说明（练习模式的辅助熟悉；用户可在弹窗中关闭不再显示）
      if (isExercise) {
        _showPropHint(propsType);
      }

      // 播放道具获得音效（A方音效音量）
      StudyAudioSessionController.instance.playBlockingSound('magic.mp3', speed: 1.0, volume: 1.0, timeoutMs: 2000);
    });

    socket.off('roomId');
    socket.on('roomId', (data) {
      roomId = data;
      Global.logger.d('收到房间号: $roomId');
      changeRoomBtn.text = makeChangeRoomBtnText();

      // 取消超时定时器
      _enterRoomTimer?.cancel();
      _enterRoomTimer = null;
    });

    // 监听魔法泡泡不足事件
    socket.off('noEnoughCowDung');
    socket.on('noEnoughCowDung', (cowDungPerGame) {
      safeShowToast('魔法泡泡不足，无法开始游戏！\n最少需要魔法泡泡: ${cowDungPerGame ?? "未知"}');
    });

    socket.off("enterWait");
    socket.on("enterWait", (data) {
      gameState = "waiting";
    });
    socket.on("enterReady", (data) {
      gameState = "ready";
    });

    socket.off("userStarted");
    socket.on("userStarted", (userId) {
      Player player;
      if (userId == playerA.userId) {
        player = playerA;
      } else {
        player = playerB;
      }
      player.started = true;
    });

    socket.off("scoreAdjust");
    socket.on("scoreAdjust", (data) async {
      int scoreAdjust = data[0];
      int cowDungAdjust = data[1];

      playerA.scoreAdjust = scoreAdjust;
      playerA.cowdungAdjust = cowDungAdjust;

      // 如果正在结算画面，更新结算文案
      if (isShowingResult) {
        _updateGameResultTexts(playerA.isWonInLastGame);
      }

      // 更新本地数据库（前端优先架构）
      try {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getLastLoggedInUser();

        if (user != null) {
          // 更新用户的游戏积分和魔法泡泡
          final newGameScore = user.gameScore + scoreAdjust;
          final newCowDung = user.cowDung + cowDungAdjust;

          await db.usersDao.saveUser(
            user.copyWith(
              gameScore: newGameScore,
              cowDung: newCowDung,
            ),
            true,
          );

          // 记录魔法泡泡变更日志
          if (cowDungAdjust != 0) {
            final now = AppClock.now();
            final log = UserCowDungLog(
              id: now.millisecondsSinceEpoch.toString(),
              userId: user.id,
              delta: cowDungAdjust,
              cowDung: newCowDung,
              theTime: now,
              reason: cowDungAdjust > 0 ? "游戏胜利奖励" : "游戏失败惩罚",
              createTime: now,
              updateTime: now,
            );
            await db.userCowDungLogsDao.insertEntity(log, true);
          }

          // 触发数据库同步
          ThrottledDbSyncService().requestSync();

          Global.logger
              .d('游戏积分和魔法泡泡已更新：游戏分${scoreAdjust > 0 ? "+$scoreAdjust" : scoreAdjust}, 魔法泡泡${cowDungAdjust > 0 ? "+$cowDungAdjust" : cowDungAdjust}');
        }
      } catch (e, stackTrace) {
        Global.logger.e('更新游戏积分和魔法泡泡失败: $e', stackTrace: stackTrace);
      }
    });

    // 公开的结算广播：用于在对手客户端展示 B 方结算
    socket.off('scoreAdjustPublic');
    socket.on('scoreAdjustPublic', (data) {
      var userId = data[0];
      var adjust = data[1] as int;
      var cowDung = data[2] as int;
      if (playerA.userId == userId) {
        playerA.scoreAdjust = adjust;
        playerA.cowdungAdjust = cowDung;
      } else if (playerB.userId == userId) {
        playerB.scoreAdjust = adjust;
        playerB.cowdungAdjust = cowDung;
      }
    });

    socket.off("propsUsed");
    socket.on("propsUsed", (data) {
      var userId = data[0];
      var propsIndex = data[1];
      var currNumber = data[2] as int;
      var nickName = data[3];
      appendMsg(0, "牛牛", "$nickName使用了道具");

      // 己方使用了道具
      if (userId == playerA.userId) {
        playerA.props[propsIndex] = currNumber;

        if (propsIndex == 0) {
          // 【加一行】
          liftUpDeadWords(playerB);
        } else if (propsIndex == 1) {
          // 【减一行】
          liftDownDeadWords(playerA);
        }
      } else {
        // 对方使用了道具
        if (propsIndex == 0) {
          // 【加一行】
          liftUpDeadWords(playerA);
        } else if (propsIndex == 1) {
          // 【减一行】
          liftDownDeadWords(playerB);
        }
      }
    });
  }

  appendMsg(senderId /* 发送者ID，为0表示系统 */, senderNickName, msg) {
    msgs.add({senderId: senderId, senderNickName: senderNickName, msg: msg});
  }

  // 双方开始游戏
  startGame() {
    isPlaying = true;
    playerA.isWonInLastGame = null;
    playerB.isWonInLastGame = null;
    playerA.scoreAdjust = 0;
    playerA.cowdungAdjust = 0;
    playerB.scoreAdjust = 0;
    playerB.cowdungAdjust = 0;
    resetProps();
    initGameForPlayer(playerA);
    initGameForPlayer(playerB);
    sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, '', '']);
  }

  sendGameOverCmd(loser) {
    sendUserCmd('GAME_OVER', [loser]);
  }

  initGameForPlayer(Player player) {
    player.wordIndex = 0;
    player.correctCount = 0;
    player.currWordTop = 0;
    player.bottomTop = player.playGroundHeight;
    player.bottomHeight = 0;
    player.started = false;
    cleanPlayGround(player);
  }

  void cleanPlayGround(Player player) {
    // 移除仍在空中的下落单词
    if (player.droppingWordSprite != null) {
      remove(player.droppingWordSprite!);
      player.droppingWordSprite = null;
    }
    // 清空已堆积的死亡单词
    removeAll(player.deadWords);
    player.deadWords.clear();
    player.bottomJet.height = bottomJetInitHeight;
    // 将地板顶边放到playground底部，使其与playground底边重合
    player.bottomJet.y = player.playGround.y + player.playGround.height - player.bottomJet.height;
    player.playGround.removeAll(player.playGround.children);
  }

  /// 道具清零
  resetProps() {
    playerA.props = [0, 0];
  }

  /// 安全地显示Toast（检查页面是否已销毁）
  void safeShowToast(String message, {bool isError = true}) {
    if (!pageState.mounted) {
      Global.logger.w('页面已销毁，跳过显示Toast: $message');
      return;
    }
    if (isError) {
      ToastUtil.error(message);
    } else {
      ToastUtil.success(message);
    }
  }

  /// 道具获得时的用途说明弹窗（可在弹窗中关闭，今后不再显示）
  void _showPropHint(int propsType) {
    final String key = 'russiaPropHintOff_${Global.currentUserId}';
    if (Prefs.read<bool>(key) == true) return; // 用户已关闭
    if (!pageState.mounted) return;

    final String name = propsType == 0 ? '加一行' : '减一行';
    final String desc = propsType == 0
        ? '在对手底部叠加一行方块，使对手更快触顶落败。'
        : '消去自己底部一行方块，缓解堆积压力。';

    // 练习模式：暂停游戏引擎，让用户安心阅读道具说明（关闭后恢复）
    pauseEngine();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        bool notAgain = false;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2127),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF374151), width: 1),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54, blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 道具图标（与游戏中 +/− 道具按钮一致的图标，加深印象）
                    Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3550),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF3B4E76), width: 1),
                      ),
                      child: Image.asset(
                        propsType == 0
                            ? 'assets/images/plus.png'
                            : 'assets/images/minus.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '获得道具【$name】',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE7EDF7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, height: 1.5, color: Color(0xFF9BB0C8)),
                    ),
                    const SizedBox(height: 18),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => notAgain = !notAgain),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: notAgain,
                            onChanged: (v) => setState(() => notAgain = v ?? false),
                            activeColor: const Color(0xFF6D8CFF),
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text(
                            '不再显示道具用途说明',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF9BB0C8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D8CFF),
                          foregroundColor: const Color(0xFF0B1222),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(21)),
                        ),
                        onPressed: () async {
                          if (notAgain) {
                            await Prefs.write(key, true);
                          }
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        child: const Text('知道了',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // 关闭说明框后恢复游戏
      if (pageState.mounted) {
        resumeEngine();
      }
    });
  }

  void sendUserCmd(cmd, args) {
    // 检查页面是否已销毁
    if (!pageState.mounted) {
      Global.logger.w('页面已销毁，跳过发送命令 - cmd: $cmd, args: $args');
      return;
    }

    var socket = SocketIoClient.instance.socket;

    // 检查 socket 连接状态
    if (!socket.connected) {
      Global.logger.e('发送命令失败：Socket未连接 - cmd: $cmd, args: $args');
      safeShowToast('网络连接已断开，请稍后重试');
      return;
    }

    Global.logger.d('发送用户命令 - cmd: $cmd, args: $args');
    socket.emit('userCmd', {'userId': Global.getLoggedInUser()!.id, 'system': 'russia', 'cmd': cmd, 'args': args});
  }

  void exercise() {
    if (roomId == -1) {
      safeShowToast('请稍等，正在进入房间...');
      return;
    }
    initGameForPlayer(playerA);
    sendUserCmd('START_EXERCISE', []);
  }

  void changeRoom() {
    if (roomId == -1) {
      safeShowToast('请稍等，正在进入房间...');
      return;
    }
    // 重新加载页面并进入新房间前，需要防止页面销毁时发送'LEAVE_HALL'命令，这是因为dispose方法执行时间不确定，有可能在进入新房间后才执行
    pageState.leaveGameWhenDispose = false;

    context.pushReplacement('/russia', extra: [gameHall, roomId]);
  }

  void startMatch() {
    if (roomId == -1) {
      safeShowToast('请稍等，正在进入房间...');
      return;
    }
    sendUserCmd("START_GAME", []);
  }

  /// 申请进入游戏大厅
  void tryEnterGameHall() {
    Global.logger.d('开始尝试进入游戏大厅 - hallId: ${gameHall.id}, exceptRoom: $exceptRoom');

    // 解析可选参数
    final args = GoRouterState.of(context).extra;
    Map? extra = args != null && args is List && args.length > 2 ? args[2] as Map? : null;
    if (extra != null && extra['mode'] == 'createPrivate') {
      Global.logger.d('创建私人房间模式');
      sendUserCmd('CREATE_PRIVATE_ROOM', [gameHall.id]);
    } else if (extra != null && extra['joinRoomId'] != null) {
      Global.logger.d('加入私人房间模式 - roomId: ${extra['joinRoomId']}');
      sendUserCmd('JOIN_ROOM_BY_ID', [gameHall.id, extra['joinRoomId']]);
    } else {
      Global.logger.d('进入普通游戏大厅模式');
      sendUserCmd('ENTER_GAME_HALL', [gameHall.id, exceptRoom]);
    }

    // 启动超时检测（15秒）
    _enterRoomTimer?.cancel();
    _enterRoomTimer = async.Timer(const Duration(seconds: 15), () {
      if (roomId == -1) {
        Global.logger.e('进入房间超时：15秒内未收到房间号');
        safeShowToast('进入房间失败，请检查网络连接或稍后重试');
      }
    });
  }

  void newDroppingWord(WordVo word, List otherWordMeanings, Player player) {
    // 强制保证同一侧同一时间只有一个下落单词
    if (player.droppingWordSprite != null) {
      // 若前一颗尚未入栈，直接移除之，避免出现多个同时下落
      remove(player.droppingWordSprite!);
      player.droppingWordSprite = null;
    }
    player.droppingWordSprite = DroppingWordSprite(word.spell, player)
      ..anchor = Anchor.topCenter
      ..x = player.playGround.x + player.playGround.width / 2
      ..y = player.playGround.y;
    // player.droppingWordSprite!.changePriorityWithoutResorting(1);
    add(player.droppingWordSprite!);

    if (player == playerA) {
      answer1Btn.text = playerA.correctIndex == 1 ? playerA.currWord!.getMeaningStr() : playerA.otherWordMeanings[0];
      answer2Btn.text = playerA.correctIndex == 2
          ? playerA.currWord!.getMeaningStr()
          : (playerA.correctIndex == 1 ? playerA.otherWordMeanings[0] : playerA.otherWordMeanings[1]);
      answer3Btn.text = playerA.correctIndex == 3 ? playerA.currWord!.getMeaningStr() : playerA.otherWordMeanings[1];
    }
  }

  double getDeadWordsTopY(Player player) {
    var deadWords = player.deadWords;
    return deadWords.isNotEmpty ? deadWords[deadWords.length - 1].y : player.bottomJet.y;
  }

  // 移除 A 侧 REPORT_FALL；仅保留 B 侧 REPORT_FALL_B（见 _reportFallEtaB）

  // 上报机器人(B侧)的触底ETA（仅当B侧是机器人时有效）
  void _reportFallEtaB() {
    // B侧必须存在下落中的单词
    final curr = playerB.droppingWordSprite;
    if (!isPlaying || curr == null || curr.isDead) return;
    // 估算至触底剩余时间：使用与下落速度严格一致的估计
    final dwTop = getDeadWordsTopY(playerB);
    
    // 核心优化：如果组件尚未 onLoad 完成（height 为 0），则使用标准行高预测
    final double h = curr.height > 0 ? curr.height : calculateWordHeight(uiScale);
    final remain = (dwTop - h) - curr.y;
    
    final double v = 35.0 * uiScale; // px/s，与下落速度(DroppingWordSprite.update)保持严格一致
    final double etaSec = remain > 0 ? (remain / v) : 0.0;
    // 转换毫秒，并引入较明显的网络补偿（如 120ms），抵消双向延迟
    // 这对于高叠（各词生命周期极短）情况至关重要，能让 server 提前触发下一词下发
    final int etaMs = (etaSec * 1000 - 120).clamp(0, 60000).toInt();
    sendUserCmd('REPORT_FALL_B', [etaMs]);
  }

  void _reportFallEtaBOnce() {
    if (_reportedFallBForCurrentWord) return;
    _reportedFallBForCurrentWord = true;
    _reportFallEtaB();
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    final touchPoint = event.localPosition;
    // 优先处理道具按钮的命中逻辑
    if (minusBtn.containsPoint(touchPoint)) {
      if (playerA.deadWords.isNotEmpty || playerA.bottomJet.height > brickHeight) {
        sendUserCmd("USE_PROPS", [1]);
      }
      return;
    }
    if (plusBtn.containsPoint(touchPoint)) {
      sendUserCmd("USE_PROPS", [0]);
      return;
    }

    // 手动触发按钮点击（确保整块区域点击都能触发 onReleased）
    bool isHit(MyButton btn, Vector2 p) {
      final double x0 = btn.x;
      final double y0 = btn.y;
      final double w = btn.size.x;
      final double h = btn.size.y;
      return p.x >= x0 && p.x <= x0 + w && p.y >= y0 && p.y <= y0 + h;
    }

    for (final btn in allButtons) {
      if (contains(btn) && isHit(btn, touchPoint)) {
        btn.onReleased?.call();
        return;
      }
    }
  }

  void liftUpDeadWords(Player player) {
    final deadWordTopY = getDeadWordsTopY(player);
    // 以最下方的一个单词高度作为"顶起"的单位
    final double delta = calculateWordHeight(uiScale);
    if (deadWordTopY - delta >= player.playGround.y + 32) {
      player.bottomJet.height += delta;
      player.bottomJet.y -= delta;
      // 重新按照新的地板位置自下而上排布所有已堆积单词
      for (var i = 0; i < player.deadWords.length; i++) {
        if (i == 0) {
          player.deadWords[i].y = player.bottomJet.y - player.deadWords[i].height;
        } else {
          player.deadWords[i].y = player.deadWords[i - 1].y - player.deadWords[i].height;
        }
      }
      // 同步堆叠行数给服务端：各自上报自己的 rows
      final int rows = player.deadWords.length;
      sendUserCmd('REPORT_STACK_ROWS', [rows]);
    }
  }

  void liftDownDeadWords(Player player) {
    // 计算标准行高
    final double delta = calculateWordHeight(uiScale);

    // 优先降低千斤顶（地板），若可降低则同时重新排布堆叠单词
    if (player.bottomJet.height > brickHeight) {
      player.bottomJet.height -= delta;
      player.bottomJet.y += delta;
      // 重新自下而上排布所有已堆积单词
      for (var i = 0; i < player.deadWords.length; i++) {
        if (i == 0) {
          player.deadWords[i].y = player.bottomJet.y - player.deadWords[i].height;
        } else {
          player.deadWords[i].y = player.deadWords[i - 1].y - player.deadWords[i].height;
        }
      }
      // 同步堆叠行数（行数未变，保持一致上报）
      final int rows = player.deadWords.length;
      sendUserCmd('REPORT_STACK_ROWS', [rows]);
    } else if (player.deadWords.isNotEmpty) {
      // 若地板无法继续下降，则消除最下方的一个单词
      var sprite = player.deadWords.removeAt(0);
      remove(sprite);
      // 重新自下而上排布剩余单词，填补空隙
      for (var i = 0; i < player.deadWords.length; i++) {
        if (i == 0) {
          player.deadWords[i].y = player.bottomJet.y - player.deadWords[i].height;
        } else {
          player.deadWords[i].y = player.deadWords[i - 1].y - player.deadWords[i].height;
        }
      }
      // 同步堆叠行数给服务端
      final int rows = player.deadWords.length;
      sendUserCmd('REPORT_STACK_ROWS', [rows]);
    }
  }

  // 显示断连提示并退出游戏
  void _showDisconnectHint() {
    // 显示断连提示
    if (_disconnectHint.parent == null) {
      add(_disconnectHint);
    }

    // 3秒后退出游戏
    Future.delayed(const Duration(seconds: 3), () {
      isPlaying = false;
      isShowingResult = true;

      // 显示断连结果
      gameResultHint1.text = '网络连接已断开';
      gameResultHint2.text = '游戏已退出，请检查网络连接';
      gameResultHint1.textRenderer = textRenderOfGameResultHint(false);
      gameResultHint2.textRenderer = textRenderOfGameResultHint(false);

      // 移除断连提示
      if (_disconnectHint.parent != null) {
        _disconnectHint.removeFromParent();
      }

      // 播放断连音效
      StudyAudioSessionController.instance.playBlockingSound('failed.mp3', speed: 1.0, volume: 1.0, timeoutMs: 2000);

      // 显示离开按钮
      if (exitBtn.parent == null) {
        add(exitBtn);
      }
    });
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (playerA.props[0] > 0) {
      plusBtn.setAlpha(255);
    } else {
      plusBtn.setAlpha(50);
    }
    if (playerA.props[1] > 0) {
      minusBtn.setAlpha(255);
    } else {
      minusBtn.setAlpha(50);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 不再周期上报B侧ETA；改为在收到新wordB时上报一次

    // 显示/隐藏 道具数量
    if (playerA.props[0] > 0) {
      plusPropsCount.text = '${playerA.props[0]}';
      if (plusPropsCount.parent == null) {
        add(plusPropsCount);
      }
    } else {
      if (plusPropsCount.parent != null) {
        plusPropsCount.removeFromParent();
      }
    }
    if (playerA.props[1] > 0) {
      minusPropsCount.text = '${playerA.props[1]}';
      if (minusPropsCount.parent == null) {
        add(minusPropsCount);
      }
    } else {
      if (minusPropsCount.parent != null) {
        minusPropsCount.removeFromParent();
      }
    }

    // 优化：仅在关键状态变化时更新布局，避免每帧进行复杂的字符串插值
    bool hasGameInfoA = playerA.userGameInfo != null;
    bool hasGameInfoB = playerB.userGameInfo != null;
    int wordCountA = playerA.otherWordMeanings.length;
    bool hasCountdown = countdownSeconds > 0;

    if (gameState != _lastGameState ||
        isPlaying != _lastIsPlaying ||
        isShowingResult != _lastShowingResult ||
        hasGameInfoA != _lastHasGameInfoA ||
        hasGameInfoB != _lastHasGameInfoB ||
        playerA.started != _lastStarted ||
        wordCountA != _lastWordCountA ||
        hasCountdown != _lastHasCountdown) {
      
      _lastGameState = gameState;
      _lastIsPlaying = isPlaying;
      _lastShowingResult = isShowingResult;
      _lastHasGameInfoA = hasGameInfoA;
      _lastHasGameInfoB = hasGameInfoB;
      _lastStarted = playerA.started;
      _lastWordCountA = wordCountA;
      _lastHasCountdown = hasCountdown;
      _needsButtonLayout = true;
    }

    if (_needsButtonLayout) {
      _needsButtonLayout = false;
      var visibleButtons = <MyButton>[];

      if (gameState == 'ready' && !playerA.started && !isPlaying && !isShowingResult) {
        visibleButtons.add(startGameBtn);
      }

      // 判断是否为私房模式
      final args = GoRouterState.of(context).extra;
      bool isPrivateRoom = args != null &&
          (args is List && args.length > 2) &&
          (((args[2] as Map?)?.containsKey('mode') == true && (args[2] as Map)['mode'] == 'createPrivate') ||
              ((args[2] as Map?)?.containsKey('joinRoomId') == true));

      // 在非游戏状态且非私房模式下显示换房间按钮
      if (!isPlaying && !isShowingResult && !isPrivateRoom) {
        visibleButtons.add(changeRoomBtn);
      }

      if (!isPlaying && !isShowingResult) {
        visibleButtons.add(exerciseBtn);
      }

      if (!isPlaying && countdownSeconds == 0) {
        visibleButtons.add(exitBtn);
      }

      if (isPlaying && playerA.otherWordMeanings.isNotEmpty) {
        visibleButtons.add(answer1Btn);
        visibleButtons.add(answer2Btn);
        visibleButtons.add(answer3Btn);
      }

      if (isPlaying && isExercise) {
        visibleButtons.add(answer4Btn);
        visibleButtons.add(answer5Btn);
      }

      // 隐藏不应显示的按钮
      for (var btn in allButtons) {
        if (!visibleButtons.contains(btn) && contains(btn)) {
          btn.removeFromParent();
        }
      }

      // 显示应当显示的按钮
      var nextBtnX = 8.0;
      // 起始位置：以"道具图标底部+间距"为准，确保不遮挡道具
      final double propsBottom = max(
        minusBtn.y + minusBtn.height,
        plusBtn.y + plusBtn.height,
      );
      var nextBtnY = max(
        // 操场底部 + 道具图标高度(48) + 基础间距
        playerA.playGround.y + playerA.playGround.height + 16.0 + 48.0 + 12.0 * uiScale,
        // 道具底部 + 间距
        propsBottom + 12.0 * uiScale,
      );
      final double btnGap = 14.0 * uiScale; // 按钮之间的间隔
      final double answersExtraScale = isPlaying && playerA.otherWordMeanings.isNotEmpty ? 1.1 : 1.0;

      // 预计算每个按钮的基础行高与内边距，并估算总高度
      // 统一按钮文本高度，避免因内容不同（如括号、数字）导致按钮高度微小差异 
      double unifiedTextHeight = 0;
      for (var btn in visibleButtons) {
        unifiedTextHeight = max(unifiedTextHeight, (btn.button! as MyButtonTextComponent).textHeight);
      }

      final List<double> baseLineHeights = [];
      final List<double> basePaddings = [];
      final int n = visibleButtons.length;
      double totalBaseHeight = 0.0;
      for (var btn in visibleButtons) { 
        final bool isAnswerBtn = btn == answer1Btn || btn == answer2Btn || btn == answer3Btn || btn == answer4Btn || btn == answer5Btn;
        final double basePadding = (isAnswerBtn ? 1.15 : 1.0) * max(16.0, unifiedTextHeight * 1.1) * answersExtraScale;
        final double visualHeight = unifiedTextHeight + basePadding;
        baseLineHeights.add(unifiedTextHeight);
        basePaddings.add(basePadding);
        totalBaseHeight += visualHeight;
      }
      if (n > 0) {
        totalBaseHeight += btnGap * (n - 1);
      }
      final double availableHeight = size.y - nextBtnY - 16.0;
      double scaleS = 1.0;
      if (totalBaseHeight > availableHeight && totalBaseHeight > 0) {
        scaleS = (availableHeight / totalBaseHeight).clamp(0.4, 1.0);
      }

      // 应用缩放并布局
      for (int i = 0; i < visibleButtons.length; i++) {
        final btn = visibleButtons[i];
        final bool isAnswerBtn = btn == answer1Btn || btn == answer2Btn || btn == answer3Btn || btn == answer4Btn || btn == answer5Btn;
        btn
          ..x = nextBtnX
          ..y = nextBtnY;

        final MyButtonTextComponent btnUp = btn.button! as MyButtonTextComponent;
        final MyButtonTextComponent btnDown = btn.buttonDown! as MyButtonTextComponent;

        // 统一计算目标字号与内边距：提高基础字号(15->18.2)，并应用答案按钮的额外缩放
        final double origFontSize = 18.2 * uiScale * (isAnswerBtn ? answersExtraScale : 1.0);
        final double targetFontSize = max(15.0, origFontSize * scaleS);
        final double basePadding = basePaddings[i];
        final double newPadding = max(16.0, basePadding * scaleS);

        // 应用字号（若不同）
        TextStyle tsUp = (btnUp.textRenderer as TextPaint).style;
        if ((tsUp.fontSize ?? 0) != targetFontSize) {
          btnUp.textRenderer = TextPaint(style: tsUp.copyWith(fontSize: targetFontSize));
          TextStyle tsDown = (btnDown.textRenderer as TextPaint).style;
          btnDown.textRenderer = TextPaint(style: tsDown.copyWith(fontSize: targetFontSize));
        }

        // 应用内边距（由于我们设置了 setter，它会自动更新组件 size）
        btnUp.verticalPadding = newPadding;
        btnDown.verticalPadding = newPadding;

        if (!contains(btn)) {
          add(btn);
        }

        // 同步 HudButtonComponent 的命中区域到背景尺寸，确保整块可点
        final double btnWidth = screenWidth - 16;
        final double lineHeight = unifiedTextHeight;
        final Size compSize = Size(btnWidth, lineHeight + newPadding);
        btn.size = Vector2(compSize.width, compSize.height);
        nextBtnY += compSize.height + btnGap;
      }
    }

    // 显示/隐藏玩家信息
    if (!isPlaying && playerA.userGameInfo != null) {
      if (playerA.userInfoPanel.parent == null) {
        add(playerA.userInfoPanel);
      }
    } else {
      if (playerA.userInfoPanel.parent != null) {
        remove(playerA.userInfoPanel);
      }
    }
    // B玩家信息面板显示逻辑：有用户信息时显示，或者在等待状态下显示（用于显示等待提示）
    if (!isPlaying && (playerB.userGameInfo != null || gameState == 'waiting')) {
      if (playerB.userInfoPanel.parent == null) {
        add(playerB.userInfoPanel);
      }
    } else {
      if (playerB.userInfoPanel.parent != null) {
        remove(playerB.userInfoPanel);
      }
    }

    // 对战 VS 徽标：随 A 方信息面板同显同隐
    if (!isPlaying && playerA.userGameInfo != null) {
      if (vsBadge.parent == null) {
        add(vsBadge);
      }
    } else if (vsBadge.parent != null) {
      vsBadge.removeFromParent();
    }

    // 显示/隐藏比赛结果提示
    if (isShowingResult) {
      if (gameResultHint1.parent == null) {
        add(gameResultHint1);
        add(gameResultHint2);
        add(countdownText);
      }
    } else {
      if (gameResultHint1.parent != null) {
        remove(gameResultHint1);
        remove(gameResultHint2);
        remove(countdownText);
      }
    }
  }
}

// 其他背景效果已移除，固定使用旋转银河系背景

class SpiralGalaxyBackground extends PositionComponent {
  double t = 0;
  double _twinkleT = 0;
  ui.Picture? _bakedArm1;
  ui.Picture? _bakedArm2;
  Shader? _cachedSpaceShader;
  
  // 重用 Paint 对象以减少分配
  final _starPaint = Paint()..color = Colors.white;
  final _fogPaint = Paint();
  final _haloPaint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    // 银河系自转转速降低到原来的 1/10；核心光晕闪烁单独计时，避免连眨眼也一并变慢
    t += dt * 0.001;
    _twinkleT += dt * 0.05;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (width != size.x || height != size.y) {
      width = size.x;
      height = size.y;
      _cachedSpaceShader = null;
      // 核心优化：在尺寸确定时立即烘焙，消灭 200ms 渲染尖峰
      // 使用 microtask 避免在此刻阻塞当前的 UI 排版决策
      async.Future.microtask(() => _bake(width, height));
    }
  }

  void _bake(double w, double h) {
    final armLen = max(w, h) * 0.9;
    
    ui.Picture bakeArm(Color baseHue) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final turns = 2.2;

      for (double r = 40; r < armLen; r += 24) {
        final theta = r / armLen * turns * 2 * pi;
        final x = r * cos(theta);
        final y = r * sin(theta) * 0.5;
        final fade = (1.0 - r / armLen).clamp(0.0, 1.0);
        
        final fog = RadialGradient(
          colors: [baseHue.withValues(alpha: 0.10 * fade), baseHue.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 60 * fade + 20));
        _fogPaint.shader = fog;
        canvas.drawCircle(Offset(x, y), 60 * fade + 20, _fogPaint);

        final rand = Random((r * 97).toInt());
        final starCount = 3 + rand.nextInt(7);
        for (int i = 0; i < starCount; i++) {
          final sx = x + (rand.nextDouble() - 0.5) * 20;
          final sy = y + (rand.nextDouble() - 0.5) * 16;
          final size = 0.6 + rand.nextDouble() * 0.8;
          const palette = [Color(0xFFFFF59D), Color(0xFF80D8FF), Color(0xFFB388FF), Color(0xFFFF8A80), Color(0xFFA5D6A7)];
          final starColor = palette[rand.nextInt(palette.length)];
          
          final haloRadius = 4 + size * 2;
          final haloShader = RadialGradient(
            colors: [starColor.withValues(alpha: 0.07), starColor.withValues(alpha: 0.0)],
          ).createShader(Rect.fromCircle(center: Offset(sx, sy), radius: haloRadius));
          _haloPaint.shader = haloShader;
          canvas.drawCircle(Offset(sx, sy), haloRadius, _haloPaint);
          
          _starPaint.color = starColor.withValues(alpha: 0.5);
          canvas.drawCircle(Offset(sx, sy), size, _starPaint);
          canvas.drawCircle(Offset(sx, sy), size * 0.35, Paint()..color = Colors.white.withValues(alpha: 0.8));
        }
      }
      return recorder.endRecording();
    }

    _bakedArm1 = bakeArm(const Color(0xFF80D8FF));
    _bakedArm2 = bakeArm(const Color(0xFFFF80AB));
  }

  @override
  void render(Canvas canvas) {
    // 降级保护：如果由于某种原因（如尺寸改变）导致烘焙失效，
    // 在 render 中同步烘焙会导致 200ms 卡顿，但为了画面正确仍需保留，
    // 不过通过 cache 机制，这应该只发生一次。
    if (_bakedArm1 == null) {
      _bake(width, height);
    }

    final rect = Rect.fromLTWH(0, 0, width, height);
    _cachedSpaceShader ??= RadialGradient(
      center: const Alignment(0.0, -0.2),
      radius: 1.2,
      colors: const [Color(0xFF05070E), Color(0xFF0A0F1E), Color(0xFF0E1630)],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(rect);
    
    final bgPaint = Paint()..shader = _cachedSpaceShader;
    canvas.drawRect(rect, bgPaint);

    final center = Offset(rect.center.dx, rect.center.dy * 0.9);
    final twinkle = (0.9 + 0.1 * sin(_twinkleT * 1.3)).clamp(0.0, 1.0);

    // 绘制预烘焙的星系臂
    if (_bakedArm1 != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t);
      canvas.drawPicture(_bakedArm1!);
      canvas.restore();
    }
    if (_bakedArm2 != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t + pi);
      canvas.drawPicture(_bakedArm2!);
      canvas.restore();
    }

    final core = RadialGradient(
      colors: [const Color(0xFFFFF59D).withValues(alpha: 0.10 * twinkle), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center, radius: 140));
    canvas.drawCircle(center, 140, Paint()..shader = core);
  }
}


class UserInfoPanel extends PositionComponent with HasGameReference<MyGame> {
  Player player;
  late TextComponent nickName;
  late TextComponent score;
  late TextComponent cowDung;
  late TextComponent contest;
  late TextComponent winRatio;

  // 计分板指标标签
  late TextComponent scoreLabel;
  late TextComponent cowDungLabel;
  late TextComponent contestLabel;
  late TextComponent winRatioLabel;

  // 头像首字母与角色标签
  late TextComponent avatarLetter;
  late TextComponent roleTag;

  late TextComponent scoreAdjust;
  late TextComponent cowDungAdjust;
  // 开始状态（底部胶囊）
  late TextComponent startedStatus;

  // 等待提示组件
  late TextComponent waitingHint;

  // 私房提示组件
  late TextComponent privateRoomHint;
  // 提示告知好友组件
  late TextComponent privateRoomTellFriendHint;

  // 熟人约战提示组件
  late TextComponent friendlyMatchHint;

  // 布局参数（onLoad 中计算，供 render 复用）
  late double _padX;
  late double _topPad;
  late double _avatarSize;
  late double _statusY;

  // 缓存属性
  String _lastNick = '';
  int _lastScore = -1;
  int _lastCowDung = -1;
  String _lastWinLoss = '';
  String _lastWinRatio = '';
  bool? _lastIsWon;
  int _lastScoreAdjust = -1;
  int _lastCowDungAdjust = -1;

  late TextPaint _successPaint;
  late TextPaint _failPaint;

  Shader? _cachedBgShader;
  Shader? _cachedBorderShader;
  Shader? _cachedGlossShader;

  UserInfoPanel(this.player) : super(priority: 2);

  @override
  Future<void> onLoad() async {
    final double s = game.uiScale;
    final double padX = 12 * s;
    final double topPad = 12 * s;
    final double avatarSize = 28 * s;
    final double colGap = 9 * s;
    final double colW = (width - padX * 2 - colGap) / 2;
    final double col2X = padX + colW + colGap;

    final TextPaint labelPaint = TextPaint(
        style: TextStyle(color: const Color(0xFF6E7E96), fontSize: 10 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC'));
    final TextPaint scorePaint = TextPaint(
        style: TextStyle(color: const Color(0xFF8FA6FF), fontSize: 17 * s, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC', letterSpacing: -0.4, shadows: const [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
    final TextPaint cowDungPaint = TextPaint(
        style: TextStyle(color: const Color(0xFFFBBF24), fontSize: 17 * s, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC', letterSpacing: -0.4, shadows: const [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
    final TextPaint recordPaint = TextPaint(
        style: TextStyle(color: const Color(0xFFB9C4D6), fontSize: 15 * s, fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC', letterSpacing: -0.2, shadows: const [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
    final TextPaint statusPaint = TextPaint(
        style: TextStyle(color: const Color(0xFFAEBACD), fontSize: 11 * s, fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC'));
    final double labelH = labelPaint.getLineMetrics('游戏').height;
    final double valueH = scorePaint.getLineMetrics('0').height;

    // 头像首字母
    avatarLetter = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF0B1222), fontSize: 14 * s, fontWeight: FontWeight.w800, fontFamily: 'NotoSansSC')))
      ..anchor = Anchor.center
      ..x = padX + avatarSize / 2
      ..y = topPad + avatarSize / 2;

    // 角色标签（我 / 对手），右上角
    roleTag = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF9FB6E8), fontSize: 9.5 * s, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC')))
      ..anchor = Anchor.topRight
      ..x = width - padX
      ..y = topPad + 1 * s;

    // 昵称（头像右侧，超宽省略号）
    nickName = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: Colors.white, fontSize: 12.5 * s, fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
        ])))
      ..x = padX + avatarSize + 8 * s
      ..y = topPad + 3 * s;

    // 2x2 指标网格
    final double metricTop = topPad + avatarSize + 12 * s;
    final double row1ValueY = metricTop + labelH + 3 * s;
    final double row2LabelY = row1ValueY + valueH + 10 * s;
    final double row2ValueY = row2LabelY + labelH + 3 * s;

    scoreLabel = TextComponent(text: '游戏分', textRenderer: labelPaint)..x = padX..y = metricTop;
    score = TextComponent(text: '', textRenderer: scorePaint)..x = padX..y = row1ValueY;
    cowDungLabel = TextComponent(text: '魔法泡泡', textRenderer: labelPaint)..x = col2X..y = metricTop;
    cowDung = TextComponent(text: '', textRenderer: cowDungPaint)..x = col2X..y = row1ValueY;
    contestLabel = TextComponent(text: '胜负', textRenderer: labelPaint)..x = padX..y = row2LabelY;
    contest = TextComponent(text: '', textRenderer: recordPaint)..x = padX..y = row2ValueY;
    winRatioLabel = TextComponent(text: '胜率', textRenderer: labelPaint)..x = col2X..y = row2LabelY;
    winRatio = TextComponent(text: '', textRenderer: recordPaint)..x = col2X..y = row2ValueY;

    // 状态胶囊（左侧圆点 + 文本），置于指标下方
    final double statusY = row2ValueY + valueH + 12 * s;
    startedStatus = TextComponent(
        text: '',
        textRenderer: statusPaint)
      ..x = padX + 16 * s
      ..y = statusY + 3 * s;
    _statusY = statusY;

    // 上局结果调整（仅在结算时显示）
    final double adjustY = statusY + 24 * s;
    scoreAdjust = TextComponent(text: '', textRenderer: statusPaint)..x = padX..y = adjustY;
    cowDungAdjust = TextComponent(text: '', textRenderer: statusPaint)..x = padX..y = adjustY + 15 * s;

    _padX = padX;
    _topPad = topPad;
    _avatarSize = avatarSize;

    // 初始化熟人约战提示组件
    friendlyMatchHint = TextComponent(
        text: '👥 熟人专属房间',
        textRenderer: TextPaint(
            style: TextStyle(
          color: const Color(0xFF2CD88F),
          fontSize: 14 * s,
          fontWeight: FontWeight.w700,
          fontFamily: 'NotoSansSC',
          shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        )))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 - 45;

    // 初始化等待提示组件
    waitingHint = TextComponent(
        text: '等待对手进入...',
        textRenderer: TextPaint(
            style: TextStyle(
          color: const Color(0xFFFFA726),
          fontSize: 13 * s,
          fontWeight: FontWeight.w500,
          fontFamily: 'NotoSansSC',
          shadows: const [
            Shadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        )))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 - 30;

    // 初始化私房提示组件（金色加粗高亮）
    privateRoomHint = TextComponent(
        text: '🔑 房间号：${game.roomId}',
        textRenderer: TextPaint(
            style: TextStyle(
          color: const Color(0xFFFBBF24),
          fontSize: 17 * s,
          fontWeight: FontWeight.w800,
          fontFamily: 'NotoSansSC',
          shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(1.5, 1.5),
              blurRadius: 4,
            ),
          ],
        )))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 + 8;

    // 初始化告知好友提示组件
    privateRoomTellFriendHint = TextComponent(
        text: '请告知好友房号',
        textRenderer: TextPaint(
            style: TextStyle(
          color: const Color(0xFF90CAF9),
          fontSize: 11.5 * s,
          fontWeight: FontWeight.w500,
          fontFamily: 'NotoSansSC',
          shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        )))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 + 32;

    _successPaint = TextPaint(
        style: TextStyle(color: const Color(0xFF4ADE80), fontSize: 11 * s, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC', shadows: const [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
    _failPaint = TextPaint(
        style: TextStyle(color: const Color(0xFFF87171), fontSize: 11 * s, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC', shadows: const [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 检查是否为B玩家且没有对手
    bool isBPlayerWithoutOpponent = player.type == 'B' && !game.isPlaying && game.playerB.userGameInfo == null && game.gameState == 'waiting';

    final args = GoRouterState.of(game.context).extra;
    bool isPrivateRoom = args != null &&
        (args is List && args.length > 2) &&
        (((args[2] as Map?)?.containsKey('mode') == true && (args[2] as Map)['mode'] == 'createPrivate') ||
            ((args[2] as Map?)?.containsKey('joinRoomId') == true));

    if (isBPlayerWithoutOpponent) {
      // 只有通过"开房间"进入时才显示熟人约战提示
      if (isPrivateRoom &&
          args.length > 2 &&
          (args[2] as Map?)?.containsKey('mode') == true &&
          (args[2] as Map)['mode'] == 'createPrivate') {
        if (friendlyMatchHint.parent == null) {
          add(friendlyMatchHint);
        }
      } else {
        friendlyMatchHint.removeFromParent();
      }

      if (waitingHint.parent == null) {
        add(waitingHint);
      }

      // 如果是私房模式，显示私房提示及告知好友提示
      if (isPrivateRoom) {
        final currentRoomText = game.roomId > 0 ? '🔑 房间号：${game.roomId}' : '🔑 正在获取房间号...';
        if (privateRoomHint.parent == null) {
          privateRoomHint.text = currentRoomText;
          add(privateRoomHint);
        } else if (privateRoomHint.text != currentRoomText) {
          privateRoomHint.text = currentRoomText;
        }

        if (privateRoomTellFriendHint.parent == null) {
          add(privateRoomTellFriendHint);
        }
      } else {
        privateRoomHint.removeFromParent();
        privateRoomTellFriendHint.removeFromParent();
      }

      // 隐藏其他信息组件
      _hideInfoComponents();
    } else if (!game.isPlaying && player.userGameInfo != null) {
      // 隐藏等待提示、熟人约战提示和私房提示
      waitingHint.removeFromParent();
      friendlyMatchHint.removeFromParent();
      privateRoomHint.removeFromParent();
      privateRoomTellFriendHint.removeFromParent();

      // 昵称（无前缀），并为右上角角色标签预留空间，超宽省略号
      final String baseNick = player.userGameInfo!.nickName;
      roleTag.text = player.type == 'A' ? '我' : '对手';
      if (baseNick != _lastNick) {
        _lastNick = baseNick;
        final double nickLeft = nickName.x;
        final double roleLeft = roleTag.x - roleTag.width;
        final double maxWidth = (roleLeft - nickLeft - 4 * game.uiScale).clamp(40.0, 200.0);
        nickName.text = _ellipsize(baseNick, (nickName.textRenderer as TextPaint), maxWidth);
        avatarLetter.text = baseNick.isEmpty ? '?' : baseNick[0];
      }

      // 2x2 指标值（无前缀）
      if (player.userGameInfo!.score != _lastScore) {
        _lastScore = player.userGameInfo!.score;
        score.text = '$_lastScore';
      }

      if (player.userGameInfo!.cowDung != _lastCowDung) {
        _lastCowDung = player.userGameInfo!.cowDung;
        cowDung.text = '$_lastCowDung';
      }

      final winLossStr = '${player.userGameInfo!.winCount} | ${player.userGameInfo!.lostCount}';
      if (winLossStr != _lastWinLoss) {
        _lastWinLoss = winLossStr;
        contest.text = _lastWinLoss;
      }

      String ratioStr;
      if (player.userGameInfo!.winCount + player.userGameInfo!.lostCount == 0) {
        ratioStr = '-';
      } else {
        ratioStr = '${player.userGameInfo!.winCount * 100 ~/ (player.userGameInfo!.winCount + player.userGameInfo!.lostCount)}%';
      }
      if (ratioStr != _lastWinRatio) {
        _lastWinRatio = ratioStr;
        winRatio.text = _lastWinRatio;
      }

      // 只有在有上一局游戏结果时才显示积分/魔法泡泡调整信息 
      if (player.isWonInLastGame != _lastIsWon || player.scoreAdjust != _lastScoreAdjust || player.cowdungAdjust != _lastCowDungAdjust) {
        _lastIsWon = player.isWonInLastGame;
        _lastScoreAdjust = player.scoreAdjust;
        _lastCowDungAdjust = player.cowdungAdjust;

        if (_lastIsWon != null) {
          if (_lastIsWon!) {
            scoreAdjust.textRenderer = _successPaint;
            cowDungAdjust.textRenderer = _successPaint;
            scoreAdjust.text = '游戏分 +$_lastScoreAdjust';
            cowDungAdjust.text = '魔法泡泡 +$_lastCowDungAdjust';
          } else {
            scoreAdjust.textRenderer = _failPaint;
            cowDungAdjust.textRenderer = _failPaint;
            scoreAdjust.text = '游戏分 -${_lastScoreAdjust.abs()}';
            cowDungAdjust.text = '魔法泡泡 -${_lastCowDungAdjust.abs()}';
          }
        }
        
        // 有游戏结果时才添加积分/魔法泡泡调整组件
        if (_lastIsWon != null) {
          if (scoreAdjust.parent == null) {
            add(scoreAdjust);
          }
          if (cowDungAdjust.parent == null) {
            add(cowDungAdjust);
          }
        } else {
          scoreAdjust.removeFromParent();
          cowDungAdjust.removeFromParent();
        }
      }

      // 显示基本信息组件
      if (nickName.parent == null) {
        add(nickName);
        add(score);
        add(cowDung);
        add(contest);
        add(winRatio);
        add(scoreLabel);
        add(cowDungLabel);
        add(contestLabel);
        add(winRatioLabel);
        add(avatarLetter);
        add(roleTag);
      }
      // 更新并显示开始状态（左侧胶囊，不显示“状态”二字）
      startedStatus.text = player.started ? '已开始' : '未开始...';
      if (startedStatus.parent == null) {
        add(startedStatus);
      }
    } else {
      // 隐藏所有组件
      waitingHint.removeFromParent();
      _hideInfoComponents();
    }
  }

  /// 隐藏信息卡的全部指标与状态组件
  void _hideInfoComponents() {
    nickName.removeFromParent();
    score.removeFromParent();
    cowDung.removeFromParent();
    contest.removeFromParent();
    winRatio.removeFromParent();
    scoreLabel.removeFromParent();
    cowDungLabel.removeFromParent();
    contestLabel.removeFromParent();
    winRatioLabel.removeFromParent();
    avatarLetter.removeFromParent();
    roleTag.removeFromParent();
    scoreAdjust.removeFromParent();
    cowDungAdjust.removeFromParent();
    startedStatus.removeFromParent();
  }

  String _ellipsize(String text, TextPaint renderer, double maxWidth) {
    // 快速通过：宽度已在范围内
    if (renderer.getLineMetrics(text).width <= maxWidth) {
      return text;
    }
    // 逐步裁剪并添加省略号
    String t = text;
    const String dots = '...';
    // 预留省略号宽度
    final double dotsW = renderer.getLineMetrics(dots).width;
    while (t.isNotEmpty && renderer.getLineMetrics(t).width + dotsW > maxWidth) {
      t = t.substring(0, t.length - 1);
    }
    return t.isEmpty ? dots : '$t$dots';
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    Rect rect = size.toRect();
    final double s = game.uiScale;
    final bool isMe = player.type == 'A';

    // 渐变背景（上圆下直角，半透明蓝灰磨砂）
    _cachedBgShader ??= LinearGradient(
      colors: [
        const Color(0xFF2A3550).withValues(alpha: 0.72),
        const Color(0xFF1E2740).withValues(alpha: 0.72),
        const Color(0xFF141A2C).withValues(alpha: 0.72),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);
    final bgPaint = Paint()..shader = _cachedBgShader;
    final panelShape = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(panelShape, bgPaint);

    // 边框（上圆下直角，半透明，主方色更亮以示区分）
    _cachedBorderShader ??= LinearGradient(
      colors: [
        (isMe ? const Color(0xFF6D8CFF) : const Color(0xFF8CA3C6)).withValues(alpha: isMe ? 0.65 : 0.40),
        (isMe ? const Color(0xFF4F6BF0) : const Color(0xFF6E86AC)).withValues(alpha: isMe ? 0.65 : 0.40),
        (isMe ? const Color(0xFF6D8CFF) : const Color(0xFF8CA3C6)).withValues(alpha: isMe ? 0.65 : 0.40),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);
    final borderPaint = Paint()
      ..shader = _cachedBorderShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawRRect(panelShape, borderPaint);

    // 内部光泽（仅顶部区域）
    _cachedGlossShader ??= LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0.08),
        Colors.white.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      begin: Alignment.topCenter,
      end: Alignment.center,
    ).createShader(rect);
    final glossPaint = Paint()..shader = _cachedGlossShader;
    final glossRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.left + 2, rect.top + 2, rect.width - 4, rect.height * 0.3),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(glossRect, glossPaint);

    // 头像圆形底（仅信息展示时绘制）
    if (nickName.parent != null) {
      final Rect avatarRect = Rect.fromLTWH(_padX, _topPad, _avatarSize, _avatarSize);
      final Paint avatarPaint = Paint()
        ..shader = LinearGradient(
          colors: isMe
              ? [const Color(0xFF8FA6FF), const Color(0xFF6D8CFF)]
              : [const Color(0xFFB7C6DD), const Color(0xFF93A1B8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(avatarRect);
      canvas.drawRRect(RRect.fromRectAndRadius(avatarRect, Radius.circular(_avatarSize / 2)), avatarPaint);

      // 角色标签胶囊底
      final double roleChipPadX = 7 * s;
      final double roleChipPadY = 5 * s;
      final Rect roleChipRect = Rect.fromLTWH(
        roleTag.x - roleTag.width - roleChipPadX,
        roleTag.y - roleChipPadY,
        roleTag.width + roleChipPadX * 2,
        roleTag.height + roleChipPadY * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(roleChipRect, Radius.circular(9 * s)),
        Paint()..color = (isMe ? const Color(0xFF6D8CFF) : const Color(0xFFFFFFFF)).withValues(alpha: isMe ? 0.18 : 0.08),
      );

      // 状态胶囊底 + 呼吸圆点
      final double capH = startedStatus.height + 8 * s;
      final Rect capRect = Rect.fromLTWH(
          _padX, _statusY, (startedStatus.x - _padX) + startedStatus.width + 7 * s, capH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(capRect, Radius.circular(9 * s)),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.07),
      );
      final Color dotColor = player.started ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24);
      canvas.drawCircle(
        Offset(_padX + 7 * s, _statusY + capH / 2),
        2.5 * s,
        Paint()..color = dotColor,
      );
    }
  }
}

class DroppingWordSprite extends TextComponent with HasGameReference<MyGame>, CollisionCallbacks {
  static TextPaint _buildTextPaint(Color color, {FontWeight weight = FontWeight.w300}) {
    final scale = 1.0; // 初值，实际大小在 onGameResize 中按场地高度自适应
    return TextPaint(style: TextStyle(color: color, fontSize: 22 * scale, fontWeight: weight, fontFamily: 'NotoSansSC'));
  }

  static final Map<int, TextPaint> _paintCache = {};

  static TextPaint makeAlivePaint() {
    return _paintCache.putIfAbsent(0xFF4CAF50, 
        () => _buildTextPaint(const Color(0xFF4CAF50), weight: FontWeight.w500));
  }
  
  static TextPaint makeDeadPaint() {
    return _paintCache.putIfAbsent(0xFFFF0000, 
        () => _buildTextPaint(const Color(0xFFFF0000), weight: FontWeight.w500));
  }
  var isDead = false;
  // 幂等控制：无论因碰撞或代码强制落地，都只处理一次
  bool hasLanded = false;
  // 当通过代码强制落地时，跳过碰撞回调中的落地处理，避免重复落地
  bool skipCollision = false;
  late Player player;
  
  // 静态缓存字号计算结果，避免每个单词出现都进行 18 次二分查找
  static double? _cachedFontSize;
  static double? _cachedAvailableHeight;

  double _fixedFontSize = 16.0;
  // 拖曳与摆动效果
  final List<double> _trailYs = <double>[];
  static const int _trailMax = 6;
  double _trailSampleAcc = 0.0;
  static const double _trailSampleInterval = 0.03; // seconds
  double _t = 0.0;
  late double _baseX;

  DroppingWordSprite(String text, this.player) : super(text: text, textRenderer: makeAlivePaint()) {
    add(RectangleHitbox()..collisionType = CollisionType.active);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    final double available = player.playGround.height - 4;
    
    // 如果缓存有效，直接使用，不再进行昂贵的二分查找
    if (_cachedFontSize != null && _cachedAvailableHeight == available) {
      _fixedFontSize = _cachedFontSize!;
    } else {
      final TextStyle base = (textRenderer as TextPaint).style;
      double low = 8.0;
      double high = 64.0;
      
      // 仅在第一次或尺寸变化时计算一次
      for (int i = 0; i < 18; i++) {
        final double mid = (low + high) / 2.0;
        final testPaint = TextPaint(style: base.copyWith(fontSize: mid));
        final double lineH = testPaint.getLineMetrics('Hg').height;
        if (lineH * 10 <= available) {
          low = mid;
        } else {
          high = mid;
        }
      }
      _fixedFontSize = low;
      _cachedFontSize = _fixedFontSize;
      _cachedAvailableHeight = available;
    }

    final TextStyle base = (textRenderer as TextPaint).style;
    textRenderer = TextPaint(style: base.copyWith(fontSize: _fixedFontSize));
    _baseX = x;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isDead) {
      // 按屏幕缩放比例调整下落速度，保证不同屏幕用时一致
      // 提升基础下落速度（从 20 提升到 35），增加游戏紧凑感
      final double speed = 35.0 * game.uiScale;
      y += speed * dt;
      // 轻微左右摆动
      _t += dt;
      final double amp = 4.0 * (game.uiScale);
      final double freq = 2.2;
      x = _baseX + sin(_t * freq) * amp;
      // 记录轨迹用于拖曳效果
      _trailSampleAcc += dt;
      if (_trailSampleAcc >= _trailSampleInterval) {
        _trailSampleAcc = 0.0;
        _trailYs.add(y);
        if (_trailYs.length > _trailMax) _trailYs.removeAt(0);
      }
    }
  }

  // 不覆写 render，使用父类默认实现

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (skipCollision || hasLanded) {
      return;
    }
    if ((other is BottomJet || other is DroppingWordSprite) && !isDead) {
      // 串行化：如该侧已有落地处理在进行，忽略本次碰撞
      if (!game.tryBeginLanding(player)) {
        return;
      }
      try {
        hasLanded = true;
        isDead = true;
        _trailYs.clear();
        // 即刻切换到红色文本，刷新文本内容以触发重绘
        textRenderer = makeDeadPaint();
        final style = (textRenderer as TextPaint).style;
        textRenderer = TextPaint(style: style.copyWith(fontSize: _fixedFontSize));
        
        // 优化：落地后将碰撞体积设为 passive，减少碰撞计算量
        children.query<RectangleHitbox>().forEach((h) => h.collisionType = CollisionType.passive);
        
        text = text;
        if (player == game.playerA) {
          // 第一块贴紧地板，后续在其之上逐行堆叠，确保 7 行布局对齐
          y = game.getDeadWordsTopY(game.playerA) - height;
          if (!game.playerA.deadWords.contains(this)) {
            game.playerA.deadWords.add(this);
          }
          if (game.playerA.droppingWordSprite == this) {
            game.playerA.droppingWordSprite = null;
          }
        } else {
          y = game.getDeadWordsTopY(game.playerB) - height;
          if (!game.playerB.deadWords.contains(this)) {
            game.playerB.deadWords.add(this);
          }
          if (game.playerB.droppingWordSprite == this) {
            game.playerB.droppingWordSprite = null;
          }
        }

        // 播放落地音效：B方音量为A方的1/4
        final double thudVolume = (player == game.playerA) ? 1.0 : bSideSfxVolume;
        StudyAudioSessionController.instance.playSoundWithCut('thud.mp3', speed: 1.0, volume: thudVolume, maxPlay: const Duration(milliseconds: 1500));

        // 触顶条件：落地后剩余高度不足以再容纳一个单词
        final double playgroundTop = game.playerA.playGround.y; // 同侧均可用其 y 作为操场顶部
        final double remaining = y - playgroundTop;
        if (remaining < height) {
          game.isPlaying = false;
          game.sendGameOverCmd(player.type);
        } else {
          if (player == game.playerA) {
            game.sendUserCmd('GET_NEXT_WORD', [game.playerA.wordIndex++, 'false', game.playerA.currWord!.spell]);
          }
          if (player == game.playerB) {
            // B 侧(通常为机器人)在本地触底后，立即上报 ETA=0，强制 server 端结束等待并下发下一词，消除高叠时的延迟
            game.sendUserCmd('REPORT_FALL_B', [0]);
          }
        }
      } catch (e, st) {
        Global.logger.e('DroppingWordSprite.onCollision 发生异常: $e', error: e, stackTrace: st);
      } finally {
        game.endLanding(player);
      }
    }
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (other is BottomJet) {}
  }
}

/// 按钮视觉层级（主 / 次 / 三级）
enum ButtonStyle {
  /// 主行动：强调填充（星际靛蓝）
  primary,
  /// 次级：玻璃描边
  secondary,
  /// 三级：幽灵弱化（离开等）
  tertiary,
}

class MyButtonTextComponent extends TextComponent {
  final ButtonStyle style;
  late MyGame myGame;
  late bool isPressed;
  final double opacity; // 0.0 ~ 1.0 半透明系数
  double _verticalPadding; // 竖向内边距，影响按钮整体高度
  double get verticalPadding => _verticalPadding;
  set verticalPadding(double value) {
    if (_verticalPadding != value) {
      _verticalPadding = value;
      _computeSize();
    }
  }
  // 点击动效状态
  bool _clickEffectActive = false;
  double _clickEffectT = 0.0; // seconds
  static const double _clickEffectDuration = 0.28; // seconds

  Shader? _cachedShader;
  bool? _shaderWasPressed;

  MyButtonTextComponent(String text, TextPaint originalRenderer, this.style, this.myGame, double initialVerticalPadding,
      {this.isPressed = false, this.opacity = 1.0})
      : _verticalPadding = initialVerticalPadding,
        super(text: text, position: Vector2.zero()) {
    // 预先缩放透明度
    final ts = originalRenderer.style;
    final scaledColor = (ts.color ?? Colors.white).withValues(alpha: (ts.color?.a ?? 1.0) * opacity);
    final scaledShadows = ts.shadows
        ?.map((s) => Shadow(
              color: s.color.withValues(alpha: s.color.a * opacity),
              offset: s.offset,
              blurRadius: s.blurRadius,
            ))
        .toList();
    textRenderer = TextPaint(style: ts.copyWith(color: scaledColor, shadows: scaledShadows));
    _computeSize();
  }

  double textHeight = 0;
  double textWidth = 0;

  @override
  set text(String value) {
    if (super.text != value) {
      super.text = value;
      _computeSize();
      _cachedShader = null; // 重置着色器
    }
  }

  void _computeSize() {
    final double btnWidth = myGame.screenWidth - 16;
    
    // 强制转换为单行：将换行符替换为空格，确保只显示一行
    if (text.contains('\n')) {
      super.text = text.replaceAll('\n', ' ').trim();
    }

    final double textW = textRenderer.getLineMetrics(text).width;
    if (textW > btnWidth) {
      String tempText = text;
      // 优化截断逻辑，避免索引越界
      while (tempText.isNotEmpty && textRenderer.getLineMetrics('$tempText...').width > btnWidth) {
        tempText = tempText.substring(0, tempText.length - 1);
      }
      super.text = '$tempText...';
    }
    textWidth = textRenderer.getLineMetrics(text).width;
    textHeight = textRenderer.getLineMetrics(text).height;
    final double bgHeight = textHeight + verticalPadding;
    size = Vector2(btnWidth, bgHeight);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 不再每帧调用 _computeSize()
    // 更新点击动效时间轴
    if (_clickEffectActive) {
      _clickEffectT += dt;
      if (_clickEffectT >= _clickEffectDuration) {
        _clickEffectActive = false;
        _clickEffectT = 0.0;
      }
    }
  }

  List<Color> _gradientColors(bool pressed) {
    switch (style) {
      case ButtonStyle.primary:
        return pressed
            ? [const Color(0xFF4F6BF0), const Color(0xFF6D8CFF)]
            : [const Color(0xFF6D8CFF), const Color(0xFF4F6BF0)];
      case ButtonStyle.secondary:
        return pressed
            ? [const Color(0xB32A3250), const Color(0xA6202838)]
            : [const Color(0xD92A3550), const Color(0xC61F2A40)];
      case ButtonStyle.tertiary:
        return [const Color(0x00000000), const Color(0x00000000)];
    }
  }

  Color _borderColorFor(bool pressed) {
    switch (style) {
      case ButtonStyle.primary:
        return const Color(0xFF9BB0FF).withValues(alpha: pressed ? 0.55 : 0.85);
      case ButtonStyle.secondary:
        return const Color(0xFFFFFFFF).withValues(alpha: pressed ? 0.30 : 0.50);
      case ButtonStyle.tertiary:
        return const Color(0x00000000);
    }
  }

  @override
  void render(Canvas canvas) {
    // 使用预先计算好的 size 和布局信息 
    Rect rect = Rect.fromLTWH(0, 0, size.x, size.y);

    Color scaleAlpha(Color c, double scale) {
      final double a = ((c.a) * scale).clamp(0.0, 1.0);
      return c.withValues(alpha: a);
    }

    // 绘制渐变背景
    if (_cachedShader == null || _shaderWasPressed != isPressed) {
      _shaderWasPressed = isPressed;
      _cachedShader = LinearGradient(
        colors: _gradientColors(isPressed).map((c) => scaleAlpha(c, opacity)).toList(),
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    }

    Paint backgroundPaint = Paint()..shader = _cachedShader;

    // 绘制圆角背景
    RRect roundedRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(roundedRect, backgroundPaint);
    // 点击动效：整块按钮区域的淡入淡出遮罩（无中心高光）
    if (_clickEffectActive) {
      final double p = (_clickEffectT / _clickEffectDuration).clamp(0.0, 1.0);
      final double ease = 1 - pow(1 - p, 3).toDouble(); // ease-out
      final double a = (0.18 * (1 - ease)).clamp(0.0, 0.18);
      final Paint overlay = Paint()..color = Colors.black.withValues(alpha: a);
      canvas.drawRRect(roundedRect, overlay);
    }

    // 绘制边框
    Paint borderPaint = Paint()
      ..color = _borderColorFor(isPressed).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(roundedRect, borderPaint);

    // 绘制内部光泽效果
    // 去除顶部高光

    // 半透明文本（仅调透明度），并将文本水平及垂直居中绘制
    final double offsetX = (size.x - textWidth) / 2;
    final double offsetY = (size.y - textHeight) / 2;
    canvas.save();
    canvas.translate(offsetX, offsetY);
    super.render(canvas);
    canvas.restore();
  }

  // 不覆盖 containsLocalPoint，让父组件统一处理点击区域

  // 由外部在点击时调用，启动动效
  void startClickEffect() {
    _clickEffectActive = true;
    _clickEffectT = 0.0;
    // 同时将整块按钮标记为按下态，命中区域一致
    isPressed = true;
  }
}

/// 依据按钮层级返回按钮文字样式
TextPaint _buttonTextPaint(ButtonStyle style, double scale) {
  final Color color = switch (style) {
    ButtonStyle.primary => const Color(0xFF0B1222),
    ButtonStyle.secondary => const Color(0xFFE7EDF7),
    ButtonStyle.tertiary => const Color(0xFF8A97AE),
  };
  final List<Shadow> shadows = style == ButtonStyle.primary
      ? const []
      : const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2)];
  return TextPaint(
      style: TextStyle(
          color: color,
          fontFamily: "NotoSansSC",
          fontSize: 15 * scale,
          fontWeight: FontWeight.w600,
          shadows: shadows));
}

class MyButton extends HudButtonComponent {
  MyButton(String text, MyGame myGame, {ButtonStyle style = ButtonStyle.secondary})
      : super(
            button: MyButtonTextComponent(
                text,
                _buttonTextPaint(style, myGame.uiScale),
                style,
                myGame,
                44.0, // 普通态按钮的垂直内边距（默认更高）
                isPressed: false,
                opacity: 1.0),
            buttonDown: MyButtonTextComponent(
                text,
                _buttonTextPaint(style, myGame.uiScale),
                style,
                myGame,
                44.0,
                isPressed: true,
                opacity: 1.0),
            position: Vector2(8, 0));

  set text(String text) {
    (button! as MyButtonTextComponent).text = text;
    (buttonDown! as MyButtonTextComponent).text = text;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    // 使用父组件尺寸作为命中区域，确保在整块按钮背景内抬起都会触发 onReleased
    return point.x >= 0 && point.y >= 0 && point.x <= size.x && point.y <= size.y;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_MyButtonTapArea(this));
  }
}

class _MyButtonTapArea extends PositionComponent with TapCallbacks {
  final MyButton ownerButton;
  _MyButtonTapArea(this.ownerButton) {
    priority = 9999; // 确保接收到点击
    position = Vector2.zero();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 同步覆盖整个按钮区域
    size = ownerButton.size;
    position = Vector2.zero();
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    return point.x >= 0 && point.y >= 0 && point.x <= size.x && point.y <= size.y;
  }

  @override
  void onTapDown(TapDownEvent event) {
    // 立即启动点击特效，提供触觉反馈
    (ownerButton.button as MyButtonTextComponent).startClickEffect();
    (ownerButton.button as MyButtonTextComponent).isPressed = true;
    
    // 立即触发 onPressed 逻辑
    ownerButton.onPressed?.call();
  }

  @override
  void onTapUp(TapUpEvent event) {
    // 在抬起时复位按下态
    Future.delayed(const Duration(milliseconds: 100), () {
      if (ownerButton.button != null) {
        (ownerButton.button as MyButtonTextComponent).isPressed = false;
      }
    });
    ownerButton.onReleased?.call();
  }
}

class MyCrate extends SpriteComponent {
  // creates a component that renders the crate.png sprite, with size 16 x 16
  MyCrate() : super(size: Vector2.all(264));

  @override
  Future<void> onLoad() async {
    sprite = await Sprite.load('1.jpg');
    anchor = Anchor.topLeft;
    position = Vector2(100, 100);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // We don't need to set the position in the constructor, we can set it directly here since it will
    // be called once before the first time it is rendered.
    position = size / 2;
  }
}

// 背景切换已取消：固定使用旋转银河系

// 断连监听器类
class _DisconnectListener implements SocketStatusListener {
  final MyGame game;
  final RussiaPageState pageState;

  _DisconnectListener(this.game, this.pageState);

  @override
  void onConnected() {
    // 如果标记了需要在连接后进入大厅，现在执行
    if (game._needEnterHallAfterConnect) {
      Global.logger.d('Socket连接成功，开始进入游戏大厅');
      game._needEnterHallAfterConnect = false;
      game.tryEnterGameHall();
    }

    // 连接恢复时隐藏断连提示
    if (game._isDisconnected) {
      game._isDisconnected = false;
      if (game._disconnectHint.parent != null) {
        game._disconnectHint.removeFromParent();
      }
      // 取消断连定时器（如果存在）
      if (game._disconnectTimer != null) {
        game._disconnectTimer = null;
      }

      // 如果之前在比赛中断连了，连接恢复时刷新页面
      if (game.isPlaying) {
        Global.logger.d('比赛中网络连接已恢复，刷新russia游戏页面');
        // 检查页面是否仍然挂载
        if (pageState.mounted) {
          pageState.refreshPage();
        } else {
          Global.logger.w('页面已销毁，跳过刷新操作'); 
        }
      } else {
        Global.logger.d('非比赛状态网络连接已恢复，无需刷新页面');
      }
    }
  }

  @override
  void onDisconnected() {
    // 在russia页面中，只在比赛中才显示断连提示
    if (!game._isDisconnected) {
      game._isDisconnected = true;

      // 只在比赛中才显示断连提示
      if (game.isPlaying) {
        Global.logger.w('比赛中检测到断连，显示提示');
        game._showDisconnectHint();
      } else {
        Global.logger.d('非比赛状态检测到断连，不显示提示');
      }
    }
  }
}

