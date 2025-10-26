import 'dart:async' as async;
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
import 'package:get/get.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/loading_utils.dart';

import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../services/throttled_sync_service.dart';
import '../util/app_clock.dart';
import '../util/sound.dart';
import 'index.dart';

const brickHeight = 14.0;
late double screenWidth;
const playGroundHeight = 250.0;
const playGroundY = 32.0;
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
    if (Get.arguments == null || Get.arguments is! List || Get.arguments.length < 2) {
      Future.delayed(Duration.zero, () {
        // 延迟到下一个tick执行，避免导航冲突
        Get.toNamed('/index', arguments: IndexPageArgs(3));
      });
      return false;
    }
    gameHall = Get.arguments[0];
    exceptRoom = Get.arguments[1];
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
      return const Center(child: Text('waiting...'));
    }
    screenWidth = MediaQuery.of(context).size.width;
    myGame = MyGame(gameHall, exceptRoom, context, this);
    return GameWidget(
      game: myGame,
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

  @override
  Future<void> render(Canvas canvas) async {
    Rect rect = size.toRect();

    // 绘制渐变背景
    Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF4A90E2),
          const Color(0xFF357ABD),
          const Color(0xFF2E5F8A),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);

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

  @override
  void render(Canvas canvas) {
    Rect rect = size.toRect();

    // 绘制渐变背景（半透明 0.7）
    Paint backgroundPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF1A1A2E).withValues(alpha: 0.7),
          const Color(0xFF16213E).withValues(alpha: 0.7),
          const Color(0xFF0F3460).withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

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
    // 使用与DroppingWordSprite相同的字体计算逻辑
    final TextStyle base = TextStyle(
      fontSize: 22 * uiScale,
      fontWeight: FontWeight.w500,
      fontFamily: 'NotoSansSC',
    );

    // 计算10行目标下的字体大小
    final double available = playGroundHeight * uiScale - 4;

    double computeFontSizeForLines(double availableHeight, int lines) {
      double low = 8.0;
      double high = 64.0;
      for (int i = 0; i < 18; i++) {
        final double mid = (low + high) / 2.0;
        final testPaint = TextPaint(style: base.copyWith(fontSize: mid));
        final double lineH = testPaint.getLineMetrics('Hg').height;
        if (lineH * lines <= availableHeight) {
          low = mid; // 可以更大
        } else {
          high = mid; // 太大，缩小
        }
      }
      return low;
    }

    final double fontSize = computeFontSizeForLines(available, 10);
    final TextPaint paint = TextPaint(style: base.copyWith(fontSize: fontSize));
    return paint.getLineMetrics('Hg').height;
  }

  late SpriteComponent plusBtn;
  late SpriteComponent minusBtn;
  late TextComponent plusPropsCount;
  late TextComponent minusPropsCount;
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
  bool _buttonSizeInitialized = false;
  // 标记是否已为当前wordB上报过ETA
  bool _reportedFallBForCurrentWord = false;

  // 串行化每侧的落地处理，避免并发导致重复入栈
  bool _landingAInProgress = false;
  bool _landingBInProgress = false;
  // 说明：机器人道具使用逻辑由后端控制；前端不做本地自动触发

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
        uiScale = max(1.0, min(MediaQuery.of(context).size.width / 390.0, 2.0));

  // 背景切换逻辑已移除

  @override
  Future<void> onLoad() async {
    await super.onLoad();
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
      ..anchor = Anchor.topCenter
      ..x = plusBtn.x
      ..y = plusBtn.y + plusBtn.height - 10;
    add(plusPropsCount);
    minusPropsCount = TextComponent(text: '0', textRenderer: textRender)
      ..anchor = Anchor.topCenter
      ..x = minusBtn.x
      ..y = minusBtn.y + minusBtn.height - 10;
    add(minusPropsCount);

    startGameBtn = MyButton('开始比赛', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(startGameBtn);
    startGameBtn.onReleased = () {
      startMatch();
    };

    changeRoomBtn = MyButton(makeChangeRoomBtnText(), this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(changeRoomBtn);
    changeRoomBtn.onReleased = () {
      changeRoom();
    };

    exerciseBtn = MyButton('单人练习', this)
      ..width = screenWidth
      ..height = 50;
    allButtons.add(exerciseBtn);
    exerciseBtn.onReleased = () {
      exercise();
    };

    exitBtn = MyButton('离开', this)
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
    answer1Btn.onReleased = () {
      onAnswerClicked(1);
    };
    answer2Btn.onReleased = () {
      onAnswerClicked(2);
    };
    answer3Btn.onReleased = () {
      onAnswerClicked(3);
    };
    answer4Btn.onReleased = () {
      onAnswerClicked(4);
    };
    answer5Btn.onReleased = () {
      onAnswerClicked(5);
    };

    // 比赛结果提示文字 - 重新排版并美化
    textRender = TextPaint(
        style:
            TextStyle(color: const Color(0xFF4CAF50), fontSize: 16 * uiScale, fontWeight: FontWeight.w300, fontFamily: 'NotoSansSC', shadows: const [
      Shadow(
        color: Colors.black87,
        offset: Offset(2, 2),
        blurRadius: 4,
      ),
      Shadow(
        color: Color(0xFF81C784),
        offset: Offset(-1, -1),
        blurRadius: 2,
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

    // 倒计时文字 - 重新排版并美化
    var countdownRender = TextPaint(
        style: TextStyle(
            color: const Color(0xFFFFD700),
            fontSize: 18 * uiScale,
            fontWeight: FontWeight.normal,
            fontFamily: 'NotoSansSC',
            shadows: const [
          Shadow(
            color: Colors.black87,
            offset: Offset(2, 2),
            blurRadius: 4,
          ),
          Shadow(
            color: Color(0xFFFFA726),
            offset: Offset(-1, -1),
            blurRadius: 2,
          ),
          Shadow(
            color: Color(0xFFFFEB3B),
            offset: Offset(0, 0),
            blurRadius: 8,
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
    return '换房间 (当前房号: $roomId)';
  }

  TextRenderer textRenderOfGameResultHint(bool? won) {
    if (won == null) {
      return TextPaint(
          style: TextStyle(color: Colors.white, fontSize: 16 * uiScale, fontWeight: FontWeight.w300, fontFamily: 'NotoSansSC', shadows: const [
        Shadow(
          color: Colors.black87,
          offset: Offset(2, 2),
          blurRadius: 4,
        ),
        Shadow(
          color: Colors.white24,
          offset: Offset(-1, -1),
          blurRadius: 2,
        ),
      ]));
    } else if (won) {
      return TextPaint(
          style: TextStyle(
              color: const Color(0xFF4CAF50),
              fontSize: 18 * uiScale,
              fontWeight: FontWeight.w300,
              fontFamily: 'NotoSansSC',
              shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(2, 2),
              blurRadius: 4,
            ),
            Shadow(
              color: Color(0xFF81C784),
              offset: Offset(-1, -1),
              blurRadius: 2,
            ),
            Shadow(
              color: Color(0xFF4CAF50),
              offset: Offset(0, 0),
              blurRadius: 6,
            ),
          ]));
    } else {
      return TextPaint(
          style: TextStyle(
              color: const Color(0xFFF44336),
              fontSize: 18 * uiScale,
              fontWeight: FontWeight.w300,
              fontFamily: 'NotoSansSC',
              shadows: const [
            Shadow(
              color: Colors.black87,
              offset: Offset(2, 2),
              blurRadius: 4,
            ),
            Shadow(
              color: Color(0xFFEF5350),
              offset: Offset(-1, -1),
              blurRadius: 2,
            ),
            Shadow(
              color: Color(0xFFF44336),
              offset: Offset(0, 0),
              blurRadius: 6,
            ),
          ]));
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
      // 选对了
      if (playerA.droppingWordSprite != null) {
        // 爆炸特效与音效，音效结束后再取下一词
        final Future<void> fx = playExplosionAtDropping(playerA.droppingWordSprite!, volume: 1.0);
        playerA.droppingWordSprite?.removeFromParent();
        playerA.droppingWordSprite = null;
        fx.then((_) {
          sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, 'true', playerA.currWord!.spell]);
        });
        return;
      }
      sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, 'true', playerA.currWord!.spell]);
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
    var y = getDeadWordsTopY(player);
    final sprite = player.droppingWordSprite;
    if (sprite != null) {
      // 已经处理过落地，直接返回（幂等保护）
      if (sprite.isDead || sprite.skipCollision || (sprite as dynamic).hasLanded == true) {
        endLanding(player);
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
      final Future<void> thud = SoundUtil.playAssetSoundCut('thud.mp3', 1.0, thudVolume, const Duration(milliseconds: 350));

      // 触顶判负：单词落地后，操场剩余高度不足以再容纳一个单词
      final double playgroundTop = player.playGround.y;
      final double remaining = sprite.y - playgroundTop; // 顶部到操场顶的剩余高度
      if (remaining < sprite.height) {
        isPlaying = false;
        sendGameOverCmd(player.type);
        endLanding(player);
        return;
      }

      // A方落地后请求下一个单词（保持与碰撞分支一致的时序：待音效播放结束）
      if (player == playerA) {
        thud.then((_) {
          sendUserCmd('GET_NEXT_WORD', [playerA.wordIndex++, 'false', playerA.currWord!.spell]);
          endLanding(player);
        });
      } else {
        // B方无需取词，也结束落地状态
        thud.then((_) => endLanding(player));
      }
    } else {
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
    // 音效：使用 bubble-pop，时长与落地音效一致（350ms），播放完成后再继续
    await SoundUtil.playAssetSoundCut('bubble-pop.mp3', 1.0, volume, const Duration(milliseconds: 350));
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
      // 已改为仅上报机器人(B侧)的ETA
      SoundUtil.playPronounceSound(playerA.currWord!);
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
          final Future<void> fx = playExplosionAtDropping(playerB.droppingWordSprite!, volume: bSideSfxVolume);
          playerB.droppingWordSprite?.removeFromParent();
          playerB.droppingWordSprite = null;
          fx.then((_) {
            playerB.currWord = nextWord;
            newDroppingWord(playerB.currWord!, playerB.otherWordMeanings, playerB);
            _reportFallEtaBOnce();
          });
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
      SoundUtil.playAssetSound('door.mp3', 2.5, 0.5);
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
      SoundUtil.playAssetSound('door.mp3', 2.5, 0.5);
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

      if (aIsLoser || user == Global.getLoggedInUser()!.id) {
        if (isExercise) {
          isExercise = false;
          gameResultHint1.text = '游戏结束！';
          gameResultHint2.text = '回答错误的单词，已被自动加入到生词本';
          gameResultHint1.textRenderer = textRenderOfGameResultHint(null);
          gameResultHint2.textRenderer = textRenderOfGameResultHint(null);
        } else {
          gameResultHint1.text = '失败了，别灰心，继续努力！';
          gameResultHint2.text = '回答错误的单词，已被自动加入到生词本';
          gameResultHint1.textRenderer = textRenderOfGameResultHint(false);
          gameResultHint2.textRenderer = textRenderOfGameResultHint(false);
          appendMsg(0, '牛牛', '失败了，别灰心，继续努力！');
        }
        SoundUtil.playAssetSound('failed.mp3', 1, 1);
      } else {
        gameResultHint1.text = '胜利啦！';
        gameResultHint2.text = '回答错误的单词，已被自动加入到生词本';
        gameResultHint1.textRenderer = textRenderOfGameResultHint(true);
        gameResultHint2.textRenderer = textRenderOfGameResultHint(true);
        appendMsg(0, '牛牛', '胜利啦！');
        SoundUtil.playAssetSound('victory.mp3', 1, 1);
      }
    });

    socket.off('giveProps');
    socket.on('giveProps', (data) {
      if (!isExercise) {
        var propsType = data[0];
        var propsCount = data[1];
        playerA.props[propsType] = propsCount;

        // 显示道具获得提示
        String propsName = propsType == 0 ? "加一行" : "减一行";
        appendMsg(0, "牛牛", "恭喜！连续答对5次，获得道具【$propsName】");

        // 播放道具获得音效（A方音效音量）
        SoundUtil.playAssetSound('magic.mp3', 1.0, 1.0);
      }
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
      
      // 更新本地数据库（前端优先架构）
      try {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getLastLoggedInUser();
        
        if (user != null) {
          // 更新用户的游戏积分和泡泡糖
          final newGameScore = user.gameScore + scoreAdjust;
          final newCowDung = user.cowDung + cowDungAdjust;
          
          await db.usersDao.saveUser(
            user.copyWith(
              gameScore: newGameScore,
              cowDung: newCowDung,
            ),
            true,
          );
          
          // 记录泡泡糖变更日志
          if (cowDungAdjust != 0) {
            final log = UserCowDungLog(
              id: AppClock.now().millisecondsSinceEpoch.toString(),
              userId: user.id,
              delta: cowDungAdjust,
              cowDung: newCowDung,
              theTime: AppClock.now(),
              reason: cowDungAdjust > 0 ? "游戏胜利奖励" : "游戏失败惩罚",
            );
            await db.userCowDungLogsDao.insertEntity(log, true);
          }
          
          // 触发数据库同步
          ThrottledDbSyncService().requestSync();
          
          Global.logger.d('游戏积分和泡泡糖已更新：积分${scoreAdjust > 0 ? "+$scoreAdjust" : scoreAdjust}, 泡泡糖${cowDungAdjust > 0 ? "+$cowDungAdjust" : cowDungAdjust}');
        }
      } catch (e, stackTrace) {
        Global.logger.e('更新游戏积分和泡泡糖失败: $e', stackTrace: stackTrace);
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

    Get.offAndToNamed('/russia', arguments: [gameHall, roomId]);
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
    Map? extra = Get.arguments != null && Get.arguments is List && Get.arguments.length > 2 ? Get.arguments[2] as Map? : null;
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
    // 估算至触底剩余时间：使用与reportFallEta相同的速度估计（20px/s），A/B同坐标系
    final dwTop = getDeadWordsTopY(playerB);
    final remain = (dwTop - curr.height) - curr.y;
    final double v = 20.0 * uiScale; // px/s，与下落速度一致按比例缩放
    final double etaSec = remain > 0 ? (remain / v) : 0.0;
    final int etaMs = (etaSec * 1000).clamp(0, 60000).toInt();
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
      SoundUtil.playAssetSound('failed.mp3', 1.0, 1.0);

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

    var visibleButtons = <MyButton>[];

    if (gameState == 'ready' && !playerA.started && !isPlaying && !isShowingResult) {
      visibleButtons.add(startGameBtn);
    }

    // 判断是否为私房模式
    bool isPrivateRoom = Get.arguments != null &&
        (Get.arguments is List && Get.arguments.length > 2) &&
        (((Get.arguments[2] as Map?)?.containsKey('mode') == true && (Get.arguments[2] as Map)['mode'] == 'createPrivate') ||
            ((Get.arguments[2] as Map?)?.containsKey('joinRoomId') == true));

    // 在非游戏状态且非私房模式下显示换房间按钮
    if (!isPlaying && !isShowingResult && !isPrivateRoom) {
      visibleButtons.add(changeRoomBtn);
    }

    if (!isPlaying && !isShowingResult) {
      visibleButtons.add(exerciseBtn);
    }

    // 在非游戏状态时显示离开按钮，但在倒计时期间不显示
    if (!isPlaying && countdownSeconds == 0) {
      visibleButtons.add(exitBtn);
    }

    // 背景切换已移除

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
    final double btnGap = 12.0 * uiScale; // 按钮之间的间隔
    final double answersExtraScale = isPlaying && playerA.otherWordMeanings.isNotEmpty ? 1.1 : 1.0;

    // 预计算每个按钮的基础行高与内边距，并估算总高度
    final List<double> baseLineHeights = [];
    final List<double> basePaddings = [];
    final int n = visibleButtons.length;
    double totalBaseHeight = 0.0;
    for (var btn in visibleButtons) {
      final MyButtonTextComponent btnUp = btn.button! as MyButtonTextComponent;
      final bool isAnswerBtn = btn == answer1Btn || btn == answer2Btn || btn == answer3Btn || btn == answer4Btn || btn == answer5Btn;
      final double textHeight = (btnUp.textRenderer as TextPaint).getLineMetrics(btnUp.text).height;
      final double basePadding = (isAnswerBtn ? 1.1 : 1.0) * max(16.0, textHeight * 1.1) * answersExtraScale;
      final double visualHeight = textHeight + basePadding + 16.0;
      baseLineHeights.add(textHeight);
      basePaddings.add(basePadding);
      totalBaseHeight += visualHeight;
    }
    if (n > 0) {
      totalBaseHeight += btnGap * (n - 1);
    }
    final double availableHeight = size.y - nextBtnY - 16.0;
    double scaleS = 1.0;
    if (!_buttonSizeInitialized && totalBaseHeight > availableHeight && totalBaseHeight > 0) {
      scaleS = (availableHeight / totalBaseHeight).clamp(0.4, 1.0);
    }

    // 计算参考字号：优先使用已添加到场景中的任意一个按钮的字号，确保后续新出现按钮与之保持一致
    double referenceFontSize = 15.0 * uiScale;
    for (final b in visibleButtons) {
      if (contains(b)) {
        final MyButtonTextComponent up = b.button! as MyButtonTextComponent;
        final double? fs = (up.textRenderer as TextPaint).style.fontSize;
        if (fs != null) {
          referenceFontSize = fs;
          break;
        }
      }
    }

    // 应用缩放并布局
    for (int i = 0; i < visibleButtons.length; i++) {
      final btn = visibleButtons[i];
      btn
        ..x = nextBtnX
        ..y = nextBtnY;

      final MyButtonTextComponent btnUp = btn.button! as MyButtonTextComponent;
      final MyButtonTextComponent btnDown = btn.buttonDown! as MyButtonTextComponent;

      // 字号按需缩放，但不小于12；仅在首次全局布局时计算
      if (!_buttonSizeInitialized) {
        TextStyle tsUp = (btnUp.textRenderer as TextPaint).style;
        TextStyle tsDown = (btnDown.textRenderer as TextPaint).style;
        final double origFontSize = (tsUp.fontSize ?? 15 * uiScale);
        final double targetFontSize = max(12.0, origFontSize * scaleS);
        if (targetFontSize != origFontSize) {
          btnUp.textRenderer = TextPaint(style: tsUp.copyWith(fontSize: targetFontSize));
          btnDown.textRenderer = TextPaint(style: tsDown.copyWith(fontSize: targetFontSize));
        }
      } else if (!contains(btn)) {
        // 全局已初始化，但该按钮是首次显示：按参考字号归一化其字体大小
        TextStyle tsUp = (btnUp.textRenderer as TextPaint).style;
        TextStyle tsDown = (btnDown.textRenderer as TextPaint).style;
        final double origFontSize = (tsUp.fontSize ?? 15 * uiScale);
        final double targetFontSize = max(12.0, referenceFontSize);
        if ((tsUp.fontSize ?? origFontSize) != targetFontSize) {
          btnUp.textRenderer = TextPaint(style: tsUp.copyWith(fontSize: targetFontSize));
        }
        if ((tsDown.fontSize ?? origFontSize) != targetFontSize) {
          btnDown.textRenderer = TextPaint(style: tsDown.copyWith(fontSize: targetFontSize));
        }
      }

      // 重新测量行高并计算内边距
      final double lineHeight = (btnUp.textRenderer as TextPaint).getLineMetrics(btnUp.text).height;
      final double basePadding = basePaddings[i];
      // 仅在首次全局布局时计算内边距；若为后续首次出现的按钮，则按参考字号比例归一化其内边距
      final double newPadding = _buttonSizeInitialized ? btnUp.verticalPadding : max(16.0, basePadding * scaleS);
      if (!_buttonSizeInitialized) {
        btnUp.verticalPadding = newPadding;
        btnDown.verticalPadding = newPadding;
      } else if (!contains(btn)) {
        // 参考字号与原始字号的比例，复用到 padding 上，确保高度一致
        final double origFontSize = 15.0 * uiScale;
        final double s = (referenceFontSize / origFontSize).clamp(0.4, 1.5);
        final double normalizedPadding = max(16.0, basePadding * s);
        btnUp.verticalPadding = normalizedPadding;
        btnDown.verticalPadding = normalizedPadding;
      }

      if (!contains(btn)) {
        add(btn);
      }

      // 同步 HudButtonComponent 的命中区域到背景尺寸，确保整块可点
      final double btnWidth = screenWidth - 16;
      final Size compSize = Size(btnWidth, lineHeight + newPadding);
      btn.size = Vector2(compSize.width, compSize.height);
      nextBtnY += compSize.height + 16.0 + btnGap; // 16 为顶部偏移补偿
    }
    _buttonSizeInitialized = true;

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

  @override
  void update(double dt) {
    super.update(dt);
    t += dt * 0.05; // 更慢的旋转速度（原来的一半）
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    width = size.x;
    height = size.y;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, width, height);

    // 深色空间底色
    final space = RadialGradient(
      center: Alignment(0.0, -0.2),
      radius: 1.2,
      colors: const [Color(0xFF05070E), Color(0xFF0A0F1E), Color(0xFF0E1630)],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = space);

    // 旋转的星系臂
    final center = Offset(rect.center.dx, rect.center.dy * 0.9);
    _drawSpiralArm(canvas, center, baseHue: const Color(0xFF80D8FF), angleOffset: 0.0);
    _drawSpiralArm(canvas, center, baseHue: const Color(0xFFFF80AB), angleOffset: pi);

    // 核心光晕
    final core = RadialGradient(
      colors: [
        const Color(0xFFFFF59D).withValues(alpha: 0.18),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: center, radius: 140));
    canvas.drawCircle(center, 140, Paint()..shader = core);
  }

  void _drawSpiralArm(Canvas canvas, Offset center, {required Color baseHue, required double angleOffset}) {
    final starPaint = Paint()..color = Colors.white;
    final armLen = max(width, height) * 0.9;
    final turns = 2.2; // 螺旋圈数

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t + angleOffset);

    // 多次沿半径方向绘制薄雾与星点
    for (double r = 40; r < armLen; r += 24) {
      final theta = r / armLen * turns * 2 * pi;
      final x = r * cos(theta);
      final y = r * sin(theta) * 0.5; // 拉伸让臂更收拢

      // 臂上薄雾
      final fade = (1.0 - r / armLen).clamp(0.0, 1.0);
      final fog = RadialGradient(
        colors: [
          baseHue.withValues(alpha: 0.18 * fade),
          baseHue.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 60 * fade + 20));
      canvas.drawCircle(Offset(x, y), 60 * fade + 20, Paint()..shader = fog);

      // 星点：每个簇内星点数量与属性随机（稳定随机，避免闪烁跳变）
      final stepSeed = (r * 97).toInt() + (angleOffset == 0.0 ? 17 : 37);
      final rand = Random(stepSeed);
      final starCount = 3 + rand.nextInt(7); // 3..9个
      for (int i = 0; i < starCount; i++) {
        final jitterX = (rand.nextDouble() - 0.5) * 20;
        final jitterY = (rand.nextDouble() - 0.5) * 16;
        final sx = x + jitterX;
        final sy = y + jitterY;
        final size = 0.6 + rand.nextDouble() * 0.8;

        // 随机但稳定的星点颜色
        const palette = [
          Color(0xFFFFF59D), // warm yellow
          Color(0xFF80D8FF), // cyan
          Color(0xFFB388FF), // lilac
          Color(0xFFFF8A80), // soft red
          Color(0xFFA5D6A7), // mint
        ];
        final starColor = palette[rand.nextInt(palette.length)];

        // 轻微闪烁
        final twinkle = (0.85 + 0.15 * sin(t * 1.3 + sx * 0.02 + sy * 0.03)).clamp(0.0, 1.0);

        // 光晕（径向渐变）- 弱化
        final haloRadius = 4 + size * 2;
        final haloShader = RadialGradient(
          colors: [
            starColor.withValues(alpha: 0.12 * twinkle),
            starColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(sx, sy), radius: haloRadius));
        canvas.drawCircle(Offset(sx, sy), haloRadius, Paint()..shader = haloShader);

        // 核心星点
        starPaint.color = starColor.withValues(alpha: 0.85 * twinkle);
        canvas.drawCircle(Offset(sx, sy), size, starPaint);

        // 高光点
        final highlightAlpha = (0.5 + 0.5 * twinkle).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(sx, sy), size * 0.35, Paint()..color = Colors.white.withValues(alpha: highlightAlpha));
      }
    }

    canvas.restore();
  }
}

class GalaxyBackground extends PositionComponent {
  double t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    t += dt;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    width = size.x;
    height = size.y;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, width, height);

    // 宇宙底色
    final space = RadialGradient(
      center: Alignment(0.0, -0.2),
      radius: 1.2,
      colors: const [
        Color(0xFF060912),
        Color(0xFF0A0F1E),
        Color(0xFF0E1630),
      ],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = space);

    // 星云光晕
    _drawNebula(canvas, rect, const Color(0xFF5C6BC0), 0.35, 0.25, 220, 0.35);
    _drawNebula(canvas, rect, const Color(0xFF26C6DA), -0.25, -0.1, 180, 0.45);
    _drawNebula(canvas, rect, const Color(0xFFAB47BC), 0.1, 0.4, 240, 0.3);

    // 星空粒子层
    _drawStars(canvas, rect, count: 120, sizeMin: 0.6, sizeMax: 1.4, speed: 0.06, twinkle: 0.5);
    _drawStars(canvas, rect, count: 60, sizeMin: 1.2, sizeMax: 2.0, speed: 0.03, twinkle: 0.8);
  }

  void _drawNebula(Canvas canvas, Rect rect, Color color, double ax, double ay, double radius, double alpha) {
    final cx = rect.center.dx + rect.width * ax * (0.6 + 0.4 * sin(t * 0.1 + ax));
    final cy = rect.center.dy + rect.height * ay * (0.6 + 0.4 * cos(t * 0.1 + ay));
    final r = radius * (0.9 + 0.1 * sin(t * 0.2 + ax + ay));
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: alpha * 0.45),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, Paint()..shader = shader);
  }

  void _drawStars(Canvas canvas, Rect rect,
      {required int count, required double sizeMin, required double sizeMax, required double speed, required double twinkle}) {
    final rand = Random(4242 + (t * 1000).floor());
    final paint = Paint()..color = Colors.white;
    for (int i = 0; i < count; i++) {
      final x = rand.nextDouble() * rect.width;
      final y = (rand.nextDouble() * rect.height + t * speed * rect.height) % rect.height;
      final s = sizeMin + rand.nextDouble() * (sizeMax - sizeMin);
      final a = 0.3 + 0.7 * (0.5 + 0.5 * sin((i * 12.9898 + t * (2.0 + speed))));
      paint.color = Colors.white.withValues(alpha: (a * twinkle).clamp(0.2, 1.0));
      canvas.drawCircle(Offset(x, y), s, paint);
    }
  }
}

class UserInfoPanel extends PositionComponent with HasGameReference<MyGame> {
  Player player;
  late TextComponent nickName;
  late TextComponent score;
  late TextComponent cowDung;

  late TextComponent contest;
  late TextComponent winRatio;

  late TextComponent scoreAdjust;
  late TextComponent cowDungAdjust;
  // 开始状态（底部居中）
  late TextComponent startedStatus;

  // 等待提示组件
  late TextComponent waitingHint;

  // 私房提示组件
  late TextComponent privateRoomHint;

  // 熟人约战提示组件
  late TextComponent friendlyMatchHint;

  UserInfoPanel(this.player) : super(priority: 2);

  @override
  Future<void> onLoad() async {
    final double s = game.uiScale;
    nickName = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: Colors.white, fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = 16;
    score = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF81C784), fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = nickName.y + nickName.height + 4;
    cowDung = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFFFFB74D), fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = score.y + score.height + 4;
    contest = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF64B5F6), fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = cowDung.y + cowDung.height + 4;
    winRatio = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFFBA68C8), fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = contest.y + contest.height + 4;
    scoreAdjust = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: Colors.white, fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = winRatio.y + winRatio.height + 16;
    cowDungAdjust = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: Colors.white, fontSize: 15 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..x = 16
      ..y = scoreAdjust.y + scoreAdjust.height + 4;

    // 初始化熟人约战提示组件
    friendlyMatchHint = TextComponent(
        text: '👥 熟人约战',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF9575CD), fontSize: 14 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 - 40;

    // 初始化等待提示组件
    waitingHint = TextComponent(
        text: '等待对手进入...',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFFFFA726), fontSize: 14 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2;

    // 初始化私房提示组件
    privateRoomHint = TextComponent(
        text: '房间号：${game.roomId}',
        textRenderer: TextPaint(
            style: TextStyle(color: const Color(0xFF64B5F6), fontSize: 14 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..anchor = Anchor.center
      ..x = width / 2
      ..y = height / 2 + 40;

    // 初始化开始状态文本（底部居中）
    startedStatus = TextComponent(
        text: '',
        textRenderer: TextPaint(
            style: TextStyle(color: Colors.white, fontSize: 14 * s, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ])))
      ..anchor = Anchor.bottomCenter
      ..x = width / 2
      ..y = height - 8;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 检查是否为B玩家且没有对手
    bool isBPlayerWithoutOpponent = player.type == 'B' && !game.isPlaying && game.playerB.userGameInfo == null && game.gameState == 'waiting';

    bool isPrivateRoom = Get.arguments != null &&
        (Get.arguments is List && Get.arguments.length > 2) &&
        (((Get.arguments[2] as Map?)?.containsKey('mode') == true && (Get.arguments[2] as Map)['mode'] == 'createPrivate') ||
            ((Get.arguments[2] as Map?)?.containsKey('joinRoomId') == true));

    if (isBPlayerWithoutOpponent) {
      // 只有通过"开房间"进入时才显示熟人约战提示
      if (isPrivateRoom &&
          Get.arguments != null &&
          Get.arguments is List &&
          Get.arguments.length > 2 &&
          (Get.arguments[2] as Map?)?.containsKey('mode') == true &&
          (Get.arguments[2] as Map)['mode'] == 'createPrivate') {
        if (friendlyMatchHint.parent == null) {
          add(friendlyMatchHint);
        }
      } else {
        friendlyMatchHint.removeFromParent();
      }

      if (waitingHint.parent == null) {
        add(waitingHint);
      }

      // 如果是私房模式，显示私房提示
      if (isPrivateRoom) {
        if (privateRoomHint.parent == null) {
          privateRoomHint.text = '房间号：${game.roomId}';
          add(privateRoomHint);
        }
      } else {
        privateRoomHint.removeFromParent();
      }

      // 隐藏其他信息组件
      nickName.removeFromParent();
      score.removeFromParent();
      cowDung.removeFromParent();
      contest.removeFromParent();
      winRatio.removeFromParent();
      scoreAdjust.removeFromParent();
      cowDungAdjust.removeFromParent();
      startedStatus.removeFromParent();
    } else if (!game.isPlaying && player.userGameInfo != null) {
      // 隐藏等待提示、熟人约战提示和私房提示
      waitingHint.removeFromParent();
      friendlyMatchHint.removeFromParent();
      privateRoomHint.removeFromParent();

      // 昵称单独一行，限制宽度不超过playground，超出使用省略号
      final String baseNick = '昵　称： ${player.userGameInfo!.nickName}';
      final double maxWidth = player.playGround.width - 32; // 左右各16px内边距
      nickName.text = _ellipsize(baseNick, (nickName.textRenderer as TextPaint), maxWidth);
      score.text = '游戏分： ${player.userGameInfo!.score}';
      cowDung.text = '泡泡糖： ${player.userGameInfo!.cowDung}';
      contest.text = '胜　负： ${player.userGameInfo!.winCount} | ${player.userGameInfo!.lostCount}';

      if (player.userGameInfo!.winCount + player.userGameInfo!.lostCount == 0) {
        winRatio.text = '胜　率： -';
      } else {
        winRatio.text = '胜　率： ${player.userGameInfo!.winCount * 100.0 ~/ (player.userGameInfo!.winCount + player.userGameInfo!.lostCount)}%';
      }

      // 只有在有上一局游戏结果时才显示积分/泡泡糖调整信息
      if (player.isWonInLastGame != null) {
        if (player.isWonInLastGame!) {
          scoreAdjust.textRenderer = TextPaint(
              style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ]));
          cowDungAdjust.textRenderer = TextPaint(
              style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ]));
          scoreAdjust.text = '积分 +${player.scoreAdjust}';
          cowDungAdjust.text = '泡泡糖 +${player.cowdungAdjust}';
        } else {
          scoreAdjust.textRenderer = TextPaint(
              style: const TextStyle(color: Color(0xFFF44336), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ]));
          cowDungAdjust.textRenderer = TextPaint(
              style: const TextStyle(color: Color(0xFFF44336), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(1, 1),
              blurRadius: 2,
            ),
          ]));
          scoreAdjust.text = '积分 -${player.scoreAdjust.abs()}';
          cowDungAdjust.text = '泡泡糖 -${player.cowdungAdjust.abs()}';
        }
        // 有游戏结果时才添加积分/泡泡糖调整组件
        if (scoreAdjust.parent == null) {
          add(scoreAdjust);
        }
        if (cowDungAdjust.parent == null) {
          add(cowDungAdjust);
        }
      } else {
        // 没有游戏结果时，移除积分/泡泡糖调整组件
        scoreAdjust.removeFromParent();
        cowDungAdjust.removeFromParent();
      }

      // 添加基本信息组件
      if (nickName.parent == null) {
        add(nickName);
        add(score);
        add(cowDung);
        add(contest);
        add(winRatio);
      }
      // 更新并显示开始状态（底部居中，不显示“状态”二字）
      startedStatus.text = player.started ? '已开始' : '未开始...';
      if (startedStatus.parent == null) {
        add(startedStatus);
      }
    } else {
      // 隐藏所有组件
      waitingHint.removeFromParent();
      nickName.removeFromParent();
      score.removeFromParent();
      cowDung.removeFromParent();
      contest.removeFromParent();
      winRatio.removeFromParent();
      scoreAdjust.removeFromParent();
      cowDungAdjust.removeFromParent();
      startedStatus.removeFromParent();
    }
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

    // 渐变背景（上圆下直角，半透明 0.7）
    final bgShader = LinearGradient(
      colors: [
        const Color(0xFF2D2D2D).withValues(alpha: 0.7),
        const Color(0xFF1A1A1A).withValues(alpha: 0.7),
        const Color(0xFF0D0D0D).withValues(alpha: 0.7),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);
    final bgPaint = Paint()..shader = bgShader;
    final panelShape = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(panelShape, bgPaint);

    // 边框（上圆下直角，半透明 0.7）
    final borderPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF4A90E2).withValues(alpha: 0.7),
          const Color(0xFF357ABD).withValues(alpha: 0.7),
          const Color(0xFF4A90E2).withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(panelShape, borderPaint);

    // 内部光泽（仅顶部区域）
    final glossPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.1),
          Colors.white.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        begin: Alignment.topCenter,
        end: Alignment.center,
      ).createShader(rect);
    final glossRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.left + 2, rect.top + 2, rect.width - 4, rect.height * 0.3),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(glossRect, glossPaint);
  }
}

class DroppingWordSprite extends TextComponent with HasGameReference<MyGame>, CollisionCallbacks {
  static TextPaint _buildTextPaint(Color color, {FontWeight weight = FontWeight.w300}) {
    final scale = 1.0; // 初值，实际大小在 onGameResize 中按场地高度自适应
    return TextPaint(style: TextStyle(color: color, fontSize: 22 * scale, fontWeight: weight, fontFamily: 'NotoSansSC'));
  }

  // 即时生成，避免静态缓存旧样式
  static TextPaint makeAlivePaint() => _buildTextPaint(const Color(0xFF4CAF50), weight: FontWeight.w500);
  static TextPaint makeDeadPaint() => _buildTextPaint(const Color(0xFFFF0000), weight: FontWeight.w500);
  var isDead = false;
  // 幂等控制：无论因碰撞或代码强制落地，都只处理一次
  bool hasLanded = false;
  // 当通过代码强制落地时，跳过碰撞回调中的落地处理，避免重复落地
  bool skipCollision = false;
  late Player player;
  double _fixedFontSize = 16.0;
  // 拖曳与摆动效果
  final List<double> _trailYs = <double>[];
  static const int _trailMax = 6;
  double _trailSampleAcc = 0.0;
  static const double _trailSampleInterval = 0.03; // seconds
  double _t = 0.0;
  late double _baseX;

  DroppingWordSprite(String text, this.player) : super(text: text, textRenderer: makeAlivePaint()) {
    add(RectangleHitbox());
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // 固定字号：按10行目标计算一次后保持不变
    final double available = player.playGround.height - 4;
    final TextStyle base = (textRenderer as TextPaint).style;

    double computeFontSizeForLines(double availableHeight, int lines) {
      double low = 8.0;
      double high = 64.0;
      for (int i = 0; i < 18; i++) {
        final double mid = (low + high) / 2.0;
        final testPaint = TextPaint(style: base.copyWith(fontSize: mid));
        final double lineH = testPaint.getLineMetrics('Hg').height;
        if (lineH * lines <= availableHeight) {
          low = mid; // 可以更大
        } else {
          high = mid; // 太大，缩小
        }
      }
      return low;
    }

    _fixedFontSize = computeFontSizeForLines(available, 10);
    textRenderer = TextPaint(style: base.copyWith(fontSize: _fixedFontSize));
    _baseX = x;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isDead) {
      // 按屏幕缩放比例调整下落速度，保证不同屏幕用时一致
      y += 20 * game.uiScale * dt;
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
    } else {
      final TextStyle base = makeDeadPaint().style;
      textRenderer = TextPaint(style: base.copyWith(fontSize: _fixedFontSize));
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
      hasLanded = true;
      isDead = true;
      _trailYs.clear();
      // 即刻切换到红色文本，刷新文本内容以触发重绘
      final TextStyle base = DroppingWordSprite.makeDeadPaint().style;
      textRenderer = TextPaint(style: base.copyWith(fontSize: _fixedFontSize));
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
      final Future<void> thud = SoundUtil.playAssetSoundCut('thud.mp3', 1.0, thudVolume, const Duration(milliseconds: 350));

      // 触顶条件：落地后剩余高度不足以再容纳一个单词
      final double playgroundTop = game.playerA.playGround.y; // 同侧均可用其 y 作为操场顶部
      final double remaining = y - playgroundTop;
      if (remaining < height) {
        game.isPlaying = false;
        game.sendGameOverCmd(player.type);
        game.endLanding(player);
      } else {
        if (player == game.playerA) {
          // 等落地音效播放结束后再取下一个单词
          thud.then((_) {
            game.sendUserCmd('GET_NEXT_WORD', [game.playerA.wordIndex++, 'false', game.playerA.currWord!.spell]);
            game.endLanding(player);
          });
        } else {
          thud.then((_) => game.endLanding(player));
        }
      }
    }
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (other is BottomJet) {}
  }
}

class MyButtonTextComponent extends TextComponent {
  late Color borderColor;
  late Color backColor;
  late MyGame myGame;
  late bool isPressed;
  final double opacity; // 0.0 ~ 1.0 半透明系数
  double verticalPadding; // 竖向内边距，影响按钮整体高度
  // 点击动效状态
  bool _clickEffectActive = false;
  double _clickEffectT = 0.0; // seconds
  static const double _clickEffectDuration = 0.28; // seconds

  MyButtonTextComponent(String text, TextPaint textRenderer, this.backColor, this.borderColor, this.myGame, this.verticalPadding,
      {this.isPressed = false, this.opacity = 0.8})
      : super(text: '  $text', textRenderer: textRenderer, position: Vector2.zero());

  void _computeSize() {
    final double btnWidth = myGame.screenWidth - 16;
    final double textW = textRenderer.getLineMetrics(text).width;
    if (textW > btnWidth) {
      while (textRenderer.getLineMetrics('$text... ').width > btnWidth && text.isNotEmpty) {
        super.text = text.substring(0, text.length - 2);
      }
      super.text = '$text...';
    }
    final double textHeight = textRenderer.getLineMetrics(text).height;
    final double bgHeight = textHeight + verticalPadding;
    size = Vector2(btnWidth, bgHeight);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _computeSize();
    // 更新点击动效时间轴
    if (_clickEffectActive) {
      _clickEffectT += dt;
      if (_clickEffectT >= _clickEffectDuration) {
        _clickEffectActive = false;
        _clickEffectT = 0.0;
      }
    }
  }

  @override
  set text(String text) {
    super.text = '  $text';
  }

  @override
  void render(Canvas canvas) {
    // 背景与点击区域：使用 update 中计算的 size
    _computeSize();
    final double textHeight = textRenderer.getLineMetrics(text).height;
    final double bgHeight = size.y;
    Rect rect = Rect.fromLTWH(0, 0, size.x, size.y);

    Color scaleAlpha(Color c, double scale) {
      final double a = ((c.a) * scale).clamp(0.0, 1.0);
      return c.withValues(alpha: a);
    }

    // 绘制渐变背景
    Paint backgroundPaint = Paint();
    if (isPressed) {
      backgroundPaint.shader = LinearGradient(
        colors: [
          scaleAlpha(const Color(0xFF2E5F8A), opacity),
          scaleAlpha(const Color(0xFF357ABD), opacity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    } else {
      backgroundPaint.shader = LinearGradient(
        colors: [
          scaleAlpha(const Color(0xFF4A90E2), opacity),
          scaleAlpha(const Color(0xFF357ABD), opacity),
          scaleAlpha(const Color(0xFF2E5F8A), opacity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    }

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
      ..color = (isPressed ? const Color(0xFF4A90E2) : const Color(0xFF5BA3F5)).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(roundedRect, borderPaint);

    // 绘制内部光泽效果
    // 去除顶部高光

    // 半透明文本（仅调透明度），并将文本垂直居中绘制
    final originalRenderer = textRenderer;
    final originalTextPaint = originalRenderer is TextPaint ? originalRenderer : TextPaint(style: const TextStyle());
    final ts = originalTextPaint.style;
    final scaledColor = (ts.color ?? Colors.white).withValues(alpha: (ts.color?.a ?? 1.0) * opacity);
    final scaledShadows = ts.shadows
        ?.map((s) => Shadow(
              color: s.color.withValues(alpha: s.color.a * opacity),
              offset: s.offset,
              blurRadius: s.blurRadius,
            ))
        .toList();
    textRenderer = TextPaint(style: ts.copyWith(color: scaledColor, shadows: scaledShadows));

    final double offsetY = (bgHeight - textHeight) / 2;
    canvas.save();
    canvas.translate(0, offsetY);
    super.render(canvas);
    canvas.restore();
    textRenderer = originalRenderer;
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

class MyButton extends HudButtonComponent {
  MyButton(String text, MyGame myGame)
      : super(
            button: MyButtonTextComponent(
                text,
                TextPaint(
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: "NotoSansSC",
                        fontSize: 15 * myGame.uiScale,
                        fontWeight: FontWeight.w400,
                        shadows: const [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ])),
                const Color(0xFF4A90E2),
                const Color(0xFF5BA3F5),
                myGame,
                44.0, // 普通态按钮的垂直内边距（默认更高）
                isPressed: false,
                opacity: 0.8),
            buttonDown: MyButtonTextComponent(
                text,
                TextPaint(
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: "NotoSansSC",
                        fontSize: 15 * myGame.uiScale,
                        fontWeight: FontWeight.w400,
                        shadows: const [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ])),
                const Color(0xFF2E5F8A),
                const Color(0xFF4A90E2),
                myGame,
                44.0,
                isPressed: true,
                opacity: 0.8),
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
  void onTapUp(TapUpEvent event) {
    // 启动点击特效
    (ownerButton.button as MyButtonTextComponent).startClickEffect();
    // 在动画结束时复位按下态
    Future.delayed(const Duration(milliseconds: 280), () {
      (ownerButton.button as MyButtonTextComponent).isPressed = false;
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
