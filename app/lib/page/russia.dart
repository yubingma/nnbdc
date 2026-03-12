import 'dart:async' as async;
import 'dart:math';
import 'dart:ui' as ui;

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

class RussiaPageState extends State<RussiaPage> with AutomaticKeepAliveClientMixin {
  bool dataLoaded = false;
 
  @override
  bool get wantKeepAlive => true;

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
    gameHall = Get.arguments[0];
    exceptRoom = Get.arguments[1];
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

  int _buildCount = 0;
  DateTime _lastBuildReport = DateTime.now();

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin requirement
    if (!dataLoaded) {
      return const Center(child: Text('waiting...'));
    }
 
    screenWidth = MediaQuery.of(context).size.width;
    // 核心优化：使用 RepaintBoundary 隔离 Flutter 渲染与游戏渲染，
    // 并使用稳定的 Key 确保 Widget 不会被重新卸载挂载。
    return RepaintBoundary(
      child: GameWidget(
        key: const ValueKey('RussiaGameWidget'),
        game: myGame,
      ),
    );
  }
}
 
/// 全局缓存，避免在游戏过程中重复进行昂贵的文字排版测量
class GameLayoutCache {
  static double? standardWordHeight;
  static double? standardFontSize;
  static double lastUIScale = -1;
  static double lastPlaygroundH = -1;
 
  static void ensureInitialized(double uiScale, double playgroundH) {
    if (standardWordHeight != null && lastUIScale == uiScale && lastPlaygroundH == playgroundH) {
      return;
    }
 
    lastUIScale = uiScale;
    lastPlaygroundH = playgroundH;
 
    final TextStyle base = const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      fontFamily: 'NotoSansSC',
    );
 
    double computeFontSizeForLines(double availableHeight, int lines) {
      double low = 8.0;
      double high = 64.0;
      for (int i = 0; i < 15; i++) { // 减少迭代次数，15次足够精准
        final double mid = (low + high) / 2.0;
        final testPaint = TextPaint(style: base.copyWith(fontSize: mid));
        final double lineH = testPaint.getLineMetrics('Hg').height;
        if (lineH * lines <= availableHeight) {
          low = mid;
        } else {
          high = mid;
        }
      }
      return low;
    }
 
    final double available = playgroundH * uiScale - 4;
    standardFontSize = computeFontSizeForLines(available, 10);
    final TextPaint paint = TextPaint(style: base.copyWith(fontSize: standardFontSize));
    standardWordHeight = paint.getLineMetrics('Hg').height;
 
    Global.logger.d('[Perf] GameLayoutCache initialized: FontSize=${standardFontSize?.toStringAsFixed(1)}, WordHeight=${standardWordHeight?.toStringAsFixed(1)}');
  }
}

class BottomJet extends PositionComponent {
  late Sprite brickImg;
  bool _brickImgLoaded = false;
  Rect? _lastRect;
  ui.Image? _cachedImage;
  bool _isBaking = false;

  BottomJet() {
    add(RectangleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size.setValues(width, bottomJetInitHeight);
    anchor = Anchor.topLeft;
    // 异步加载图片，加载完成后标记并尝试重新烘焙
    Flame.images.load('brick.png').then((img) {
      brickImg = Sprite(img);
      _brickImgLoaded = true;
      if (_lastRect != null) _bake(); // 如果已经有尺寸，则重新烘焙
    });
  }

  @override
  void onRemove() {
    _cachedImage?.dispose();
    super.onRemove();
  }

  Future<void> _bake() async {
    if (_isBaking || width <= 0 || height <= 0) return;
    _isBaking = true;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = size.toRect();

    // 1. 背景渐变
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF4A90E2), const Color(0xFF357ABD), const Color(0xFF2E5F8A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);

    final RRect roundedRect = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(roundedRect, paint);

    // 2. 顶部高光
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0.2), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(rect.left + 1, rect.top + 1, rect.width - 2, 6.0));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 1, rect.top + 1, rect.width - 2, 6.0), const Radius.circular(5)), highlightPaint);

    // 3. 边框
    final borderPaint = Paint()
      ..color = const Color(0xFF5BA3F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(roundedRect, borderPaint);

    // 4. 砖块纹理
    if (_brickImgLoaded) {
      final brickWidth = (brickImg.image.width.toDouble() / 2.0); // 缩小一点显示更精致
      final actualBrickHeight = (brickImg.srcSize.y * (brickWidth / brickImg.srcSize.x));

      for (double y = 0; y < height; y += actualBrickHeight) {
        for (double x = 0; x < width; x += brickWidth) {
          brickImg.render(
            canvas,
            position: Vector2(x, y),
            size: Vector2(brickWidth, actualBrickHeight),
            overridePaint: Paint()..color = Colors.white.withValues(alpha: 0.1), // 增加一点透明度融合背景
          );
        }
      }
    } else {
      // 回退逻辑：手动绘制线条
      final brickPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.25;
      const currentBrickWidth = 32.0;
      for (var i = 1; i * brickHeight <= height; i++) {
        for (var j = 1; j * currentBrickWidth <= width; j++) {
          canvas.drawRect(Rect.fromLTWH((j - 1) * currentBrickWidth, (i - 1) * brickHeight + 1, currentBrickWidth, brickHeight), brickPaint);
        }
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    _cachedImage = img;
    _isBaking = false;
  }

  @override
  void render(Canvas canvas) {
    if (width <= 0 || height <= 0) return;

    if (_lastRect != size.toRect()) {
      _lastRect = size.toRect();
      _bake();
    }

    if (_cachedImage != null) {
      canvas.drawImage(_cachedImage!, Offset.zero, Paint());
    } else {
      // 降级绘制：如果尚未烘焙完成，画个纯色占位
      canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFF357ABD));
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
  Rect? _lastRect;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size.setValues(width, height);
    anchor = Anchor.topLeft;
  }

  ui.Image? _cachedImage;
  bool _isBaking = false;

  @override
  void onRemove() {
    _cachedImage?.dispose();
    super.onRemove();
  }

  Future<void> _bake() async {
    if (_isBaking || width <= 0 || height <= 0) return;
    _isBaking = true;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = size.toRect();

    // 1. 背景
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF1A1A2E).withValues(alpha: 0.7), const Color(0xFF16213E).withValues(alpha: 0.7), const Color(0xFF0F3460).withValues(alpha: 0.7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final RRect roundedRect = RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(8), topRight: const Radius.circular(8));
    canvas.drawRRect(roundedRect, bgPaint);

    // 2. 边框
    final borderPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(roundedRect, borderPaint);

    // 3. 网格
    final gridPaint = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (double x = 20; x < width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }
    for (double y = 20; y < height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    _cachedImage = img;
    _isBaking = false;
  }

  @override
  void render(Canvas canvas) {
    if (width <= 0 || height <= 0) return;

    if (_lastRect != size.toRect()) {
      _lastRect = size.toRect();
      _bake();
    }

    if (_cachedImage != null) {
      canvas.drawImage(_cachedImage!, Offset.zero, Paint());
    }
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

  /// 计算单词的标准高度（使用缓存）
  static double calculateWordHeight(double uiScale) {
    GameLayoutCache.ensureInitialized(uiScale, playGroundHeight);
    return GameLayoutCache.standardWordHeight!;
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
  // 状态记录，用于在 update 中判定是否需要刷新按钮布局
  String? _lastGameState;
  bool? _lastIsPlaying;
  bool? _lastIsShowingResult;
  bool? _lastIsExercise;
  int? _lastWordCount;
  bool? _lastCountdownSeconds; // 这里存的是 (countdownSeconds > 0)
  double? _lastSizeX;
  bool _reportedFallBForCurrentWord = false;

  // 状态记录，减少 redundant 更新
  int _lastProps0 = -1;
  int _lastProps1 = -1;

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
        uiScale = max(1.0, min(MediaQuery.of(context).size.width / 390.0, min(MediaQuery.of(context).size.height / 844.0, 2.0)));

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
        gameResultHint2.text = '积分 $scoreStr, 魔法泡泡 $cowDungStr';
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
      SoundUtil.playAssetSound('door.mp3', 2.5, 0.5, 2000, 0);
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
      SoundUtil.playAssetSound('door.mp3', 2.5, 0.5, 2000, 0);
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
        SoundUtil.playAssetSound('failed.mp3', 1, 1, 2000, 0);
      } else {
        if (!isExercise) {
          appendMsg(0, '牛牛', '胜利啦！');
        }
        SoundUtil.playAssetSound('victory.mp3', 1, 1, 2000, 0);
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
        SoundUtil.playAssetSound('magic.mp3', 1.0, 1.0, 2000, 0);
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

          Global.logger
              .d('游戏积分和魔法泡泡已更新：积分${scoreAdjust > 0 ? "+$scoreAdjust" : scoreAdjust}, 魔法泡泡${cowDungAdjust > 0 ? "+$cowDungAdjust" : cowDungAdjust}');
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
      SoundUtil.playAssetSound('failed.mp3', 1.0, 1.0, 2000, 0);

      // 显示离开按钮
      if (exitBtn.parent == null) {
        add(exitBtn);
      }
    });
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
  }

  @override
  void update(double dt) {
    final sw = Stopwatch()..start();
    super.update(dt);
    final elapsed = sw.elapsedMicroseconds / 1000.0;
    _perfTracker.totalUpdateTime += elapsed;
    if (elapsed > _perfTracker.maxUpdateTime) _perfTracker.maxUpdateTime = elapsed;

    // 不再周期上报B侧ETA；改为在收到新wordB时上报一次

    // 状态记录，减少 redundant 更新
    if (playerA.props[0] > 0) {
      if (_lastProps0 != playerA.props[0]) {
        _lastProps0 = playerA.props[0];
        plusPropsCount.text = '$_lastProps0';
      }
      if (plusPropsCount.parent == null) add(plusPropsCount);
      plusBtn.setAlpha(255);
    } else {
      if (plusPropsCount.parent != null) plusPropsCount.removeFromParent();
      _lastProps0 = -1;
      plusBtn.setAlpha(50);
    }

    if (playerA.props[1] > 0) {
      if (_lastProps1 != playerA.props[1]) {
        _lastProps1 = playerA.props[1];
        minusPropsCount.text = '$_lastProps1';
      }
      if (minusPropsCount.parent == null) add(minusPropsCount);
      minusBtn.setAlpha(255);
    } else {
      if (minusPropsCount.parent != null) minusPropsCount.removeFromParent();
      _lastProps1 = -1;
      minusBtn.setAlpha(50);
    }

    // 状态记录，或屏幕尺寸改变时，跳过每一帧的冗余计算
    final bool shouldRebuildButtons = _lastGameState != gameState ||
        _lastIsPlaying != isPlaying ||
        _lastIsShowingResult != isShowingResult ||
        _lastIsExercise != isExercise ||
        _lastWordCount != (isPlaying ? playerA.otherWordMeanings.length : 0) ||
        _lastCountdownSeconds != (countdownSeconds > 0) ||
        _lastSizeX != size.x ||
        !_buttonSizeInitialized;

    if (shouldRebuildButtons) {
      _lastGameState = gameState;
      _lastIsPlaying = isPlaying;
      _lastIsShowingResult = isShowingResult;
      _lastIsExercise = isExercise;
      _lastWordCount = isPlaying ? playerA.otherWordMeanings.length : 0;
      _lastCountdownSeconds = (countdownSeconds > 0);
      _lastSizeX = size.x;

      var visibleButtons = <MyButton>[];

      if (gameState == 'ready' && !playerA.started && !isPlaying && !isShowingResult) {
        visibleButtons.add(startGameBtn);
      }

      bool isPrivateRoom = Get.arguments != null &&
          (Get.arguments is List && Get.arguments.length > 2) &&
          (((Get.arguments[2] as Map?)?.containsKey('mode') == true && (Get.arguments[2] as Map)['mode'] == 'createPrivate') ||
              ((Get.arguments[2] as Map?)?.containsKey('joinRoomId') == true));

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

      // 批量处理按钮的添加/移除
      for (var btn in allButtons) {
        final bool shouldVisible = visibleButtons.contains(btn);
        if (shouldVisible) {
          if (!contains(btn)) add(btn);
        } else {
          if (contains(btn)) btn.removeFromParent();
        }
      }

      final double propsBottom = max(
        minusBtn.y + minusBtn.height,
        plusBtn.y + plusBtn.height,
      );
      var nextBtnY = max(
        playerA.playGround.y + playerA.playGround.height + 16.0 + 48.0 + 12.0 * uiScale,
        propsBottom + 12.0 * uiScale,
      );
      final double btnGap = 12.0 * uiScale;
      final double answersExtraScale = isPlaying && playerA.otherWordMeanings.isNotEmpty ? 1.1 : 1.0;

      final double gWidth = (size.x > 0) ? size.x : screenWidth;
      final double targetBtnWidth = (gWidth > 600) ? 460.0 : gWidth - 32;
      final double nextBtnX = (gWidth - targetBtnWidth) / 2;

      final double gHeight = size.y > 0 ? size.y : 800.0;
      final double availableHeight = gHeight - nextBtnY - 32.0;

      double totalNeededHeight = 0.0;
      final List<double> targetPaddings = [];

      for (var btn in visibleButtons) {
        final MyButtonTextComponent btnUp = btn.button! as MyButtonTextComponent;
        final bool isAnswerBtn = btn == answer1Btn || btn == answer2Btn || btn == answer3Btn || btn == answer4Btn || btn == answer5Btn;

        final double textHeight = (btnUp.textRenderer as TextPaint).getLineMetrics(btnUp.text).height;
        // 调整内边距：从 56 降至 36，使高度更紧凑
        final double basePadding = (isAnswerBtn ? 1.5 : 1.3) * (36.0 * answersExtraScale);
        targetPaddings.add(basePadding);
        totalNeededHeight += (textHeight + basePadding + 8.0);
      }

      if (visibleButtons.isNotEmpty) {
        totalNeededHeight += btnGap * (visibleButtons.length - 1);
      }

      double scaleS = (availableHeight < totalNeededHeight && totalNeededHeight > 0) ? (availableHeight / totalNeededHeight).clamp(0.4, 1.0) : 1.0;

      for (int i = 0; i < visibleButtons.length; i++) {
        final btn = visibleButtons[i];
        final MyButtonTextComponent btnUp = btn.button! as MyButtonTextComponent;
        final MyButtonTextComponent btnDown = btn.buttonDown! as MyButtonTextComponent;

        TextStyle tsUp = (btnUp.textRenderer as TextPaint).style;
        final double origFontSize = 15 * uiScale;
        final double targetFontSize = max(14.0, origFontSize * scaleS);

        if (tsUp.fontSize != targetFontSize) {
          final newTR = TextPaint(style: tsUp.copyWith(fontSize: targetFontSize));
          btnUp.textRenderer = newTR;
          btnDown.textRenderer = newTR;
        }

        final double newPadding = max(24.0, targetPaddings[i] * scaleS);
        btnUp.verticalPadding = newPadding;
        btnDown.verticalPadding = newPadding;

        final double lineHeight = (btnUp.textRenderer as TextPaint).getLineMetrics(btnUp.text).height;
        // 调整高度，从 72 降至 54
        final double finalBtnHeight = max(54.0, (lineHeight + newPadding));
        btn.x = nextBtnX;
        btn.y = nextBtnY;
        btn.size.setValues(targetBtnWidth, finalBtnHeight);
 
        btnUp.size.setFrom(btn.size);
        btnDown.size.setFrom(btn.size);
 
        nextBtnY += finalBtnHeight + btnGap;
      }
      _buttonSizeInitialized = true;
    }
 
    // 显示/隐藏玩家信息：已优化，仅在状态变化时操作
    final bool shouldShowPanelA = !isPlaying && playerA.userGameInfo != null;
    if (shouldShowPanelA) {
      if (playerA.userInfoPanel.parent == null) add(playerA.userInfoPanel);
    } else {
      if (playerA.userInfoPanel.parent != null) remove(playerA.userInfoPanel);
    }

    final bool shouldShowPanelB = !isPlaying && (playerB.userGameInfo != null || gameState == 'waiting');
    if (shouldShowPanelB) {
      if (playerB.userInfoPanel.parent == null) add(playerB.userInfoPanel);
    } else {
      if (playerB.userInfoPanel.parent != null) remove(playerB.userInfoPanel);
    }

    // 显示/隐藏比赛结果提示：仅在必要时操作组件树
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

  // 缓存 Paint 和 Shader
  final Paint _spacePaint = Paint();
  Rect? _lastRect;

  // 烘焙缓存
  ui.Image? _cachedGalaxyTexture;
  bool _isBaking = false;

  @override
  void onRemove() {
    _cachedGalaxyTexture?.dispose();
    super.onRemove();
  }

  Future<void> _bakeGalaxy(double w, double h) async {
    if (_isBaking) return;
    _isBaking = true;

    // 手机端关键优化：不要烘焙全分辨率图像，尤其是 2K/4K 屏幕。
    // 使用固定的适中分辨率进行烘焙，然后渲染时拉伸，视觉效果几乎无损但性能翻倍。
    const double bakeW = 512.0;
    final double bakeH = (h / w) * bakeW;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(bakeW / 2, bakeH / 2);

    _drawSpiralArmStatic(canvas, center, bakeW, bakeH, baseHue: const Color(0xFF80D8FF), angleOffset: 0.0);
    _drawSpiralArmStatic(canvas, center, bakeW, bakeH, baseHue: const Color(0xFFFF80AB), angleOffset: pi);

    final picture = recorder.endRecording();
    final img = await picture.toImage(bakeW.toInt(), bakeH.toInt());
    _cachedGalaxyTexture = img;
    _isBaking = false;
  }

  void _drawSpiralArmStatic(Canvas canvas, Offset center, double w, double h, {required Color baseHue, required double angleOffset}) {
    final armLen = max(w, h) * 0.9;
    final turns = 2.2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleOffset);

    // 核心光晕：也烘焙进来，避免每帧绘制
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        140,
        [const Color(0xFFFFF59D).withValues(alpha: 0.18), Colors.transparent],
      );
    canvas.drawCircle(Offset.zero, 140, glowPaint);

    final Random rand = Random(angleOffset == 0.0 ? 42 : 24);

    for (double r = 40; r < armLen; r += 24) {
      final theta = r / armLen * turns * 2 * pi;
      final x = r * cos(theta);
      final y = r * sin(theta) * 0.5;
      final fade = (1.0 - r / armLen).clamp(0.0, 1.0);
      final radius = 60 * fade + 20;

      final fogPaint = Paint()
        ..shader = RadialGradient(
          colors: [baseHue.withValues(alpha: 0.15 * fade), baseHue.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));

      canvas.drawCircle(Offset(x, y), radius, fogPaint);

      final starCount = 4 + rand.nextInt(6);
      for (int i = 0; i < starCount; i++) {
        final sx = x + (rand.nextDouble() - 0.5) * 20;
        final sy = y + (rand.nextDouble() - 0.5) * 16;
        final size = 0.6 + rand.nextDouble() * 0.8;

        const palette = [Color(0xFFFFF59D), Color(0xFF80D8FF), Color(0xFFB388FF), Color(0xFFFF8A80)];
        final starColor = palette[rand.nextInt(palette.length)];

        canvas.drawCircle(Offset(sx, sy), 4 + size * 2, Paint()..color = starColor.withValues(alpha: 0.08));
        canvas.drawCircle(Offset(sx, sy), size, Paint()..color = starColor.withValues(alpha: 0.7));
      }
    }
    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    t += dt * 0.05;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    width = size.x;
    height = size.y;
  }

  final Paint _noFilterPaint = Paint()..filterQuality = ui.FilterQuality.none;
  Offset? _cachedDrawOffset;

  @override
  void render(Canvas canvas) {
    if (width <= 0 || height <= 0) return;

    final rect = Rect.fromLTWH(0, 0, width, height);

    // 1. 绘制深空底色
    if (_lastRect != rect) {
      _lastRect = rect;
      _spacePaint.shader = ui.Gradient.radial(
        const Offset(0.5, 0.3), // 简化 Alignment
        1.2 * max(width, height),
        const [Color(0xFF05070E), Color(0xFF0A0F1E), Color(0xFF0E1630)],
        [0.0, 0.6, 1.0],
      );
      _bakeGalaxy(width, height);
    }
    canvas.drawRect(rect, _spacePaint);

    // 2. 绘制烘焙好的星系图层
    if (_cachedGalaxyTexture != null) {
      _cachedDrawOffset ??= Offset(-_cachedGalaxyTexture!.width / 2, -_cachedGalaxyTexture!.height / 2);
      canvas.save();
      canvas.translate(width / 2, height / 2);
      canvas.rotate(t);
      canvas.scale(width / _cachedGalaxyTexture!.width, height / _cachedGalaxyTexture!.height);
      canvas.drawImage(_cachedGalaxyTexture!, _cachedDrawOffset!, _noFilterPaint);
      canvas.restore();
    }
  }
}

class GalaxyBackground extends PositionComponent {
  double t = 0;

  // 缓存 Paint 和 Shader
  final Paint _spacePaint = Paint();
  final Paint _nebulaPaint = Paint();
  final Paint _starPaint = Paint()..color = Colors.white;
  Rect? _lastRect;

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

    if (_lastRect != rect) {
      _lastRect = rect;
      _spacePaint.shader = RadialGradient(
        center: Alignment(0.0, -0.2),
        radius: 1.2,
        colors: const [
          Color(0xFF060912),
          Color(0xFF0A0F1E),
          Color(0xFF0E1630),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);
    }

    canvas.drawRect(rect, _spacePaint);

    // 星云光晕
    _drawNebula(canvas, rect, const Color(0xFF5C6BC0), 0.35, 0.25, 220, 0.35);
    _drawNebula(canvas, rect, const Color(0xFF26C6DA), -0.25, -0.1, 180, 0.45);
    _drawNebula(canvas, rect, const Color(0xFFAB47BC), 0.1, 0.4, 240, 0.3);

    // 星空粒子层
    _drawStars(canvas, rect, count: 120, sizeMin: 0.6, sizeMax: 1.4, speed: 0.06, twinkle: 0.5);
    _drawStars(canvas, rect, count: 60, sizeMin: 1.2, sizeMax: 2.0, speed: 0.03, twinkle: 0.8);
  }

  // 缓存星云 Shader
  final Map<int, Shader> _nebulaShaderCache = {};
  final Map<int, Offset> _nebulaLastCenterCache = {};

  void _drawNebula(Canvas canvas, Rect rect, Color color, double ax, double ay, double radius, double alpha) {
    final double timeOffset = t * 0.1;
    final cx = rect.center.dx + rect.width * ax * (0.6 + 0.4 * sin(timeOffset + ax));
    final cy = rect.center.dy + rect.height * ay * (0.6 + 0.4 * cos(timeOffset + ay));
    final r = radius * (0.9 + 0.1 * sin(t * 0.2 + ax + ay));
    final center = Offset(cx, cy);

    final int cacheKey = color.value ^ (radius.toInt() << 16);
    if (_nebulaLastCenterCache[cacheKey] != center) {
      _nebulaLastCenterCache[cacheKey] = center;
      _nebulaShaderCache[cacheKey] = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * 0.45),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    }

    _nebulaPaint.shader = _nebulaShaderCache[cacheKey];
    canvas.drawCircle(center, r, _nebulaPaint);
  }

  void _drawStars(Canvas canvas, Rect rect,
      {required int count, required double sizeMin, required double sizeMax, required double speed, required double twinkle}) {
    // 使用固定种子以保持星星位置稳定，仅随时间平移
    final rand = Random(4242);
    for (int i = 0; i < count; i++) {
      final x = rand.nextDouble() * rect.width;
      final y = (rand.nextDouble() * rect.height + t * speed * rect.height) % rect.height;
      final s = sizeMin + rand.nextDouble() * (sizeMax - sizeMin);
      final a = 0.3 + 0.7 * (0.5 + 0.5 * sin((i * 12.9898 + t * (2.0 + speed))));
      _starPaint.color = Colors.white.withValues(alpha: (a * twinkle).clamp(0.2, 1.0));
      canvas.drawCircle(Offset(x, y), s, _starPaint);
    }
  }
}

class UserInfoPanel extends PositionComponent with HasGameReference<MyGame> {
  Player player;
  
  // 缓存常见的文字渲染器，避免重新分配
  static final Map<double, TextPaint> _nickRendererCache = {};
  
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

  // 缓存状态：减少 update 循环中的 redundant 更新
  String? _lastNickName;
  int? _lastScore;
  int? _lastCowDung;
  String? _lastWinLost;
  String? _lastRatio;
  bool? _lastIsWon;
  int? _lastScoreAdj;
  int? _lastCowAdj;
  bool? _lastStarted;
  int? _lastMsgRoomId;

  late final TextPaint _winPaint;
  late final TextPaint _losePaint;

  UserInfoPanel(this.player) : super(priority: 2) {
    _winPaint = TextPaint(
        style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
    _losePaint = TextPaint(
        style: const TextStyle(color: Color(0xFFF44336), fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC', shadows: [
      Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
    ]));
  }

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
    final bool isBWithoutOpponent = player.type == 'B' && !game.isPlaying && game.playerB.userGameInfo == null && game.gameState == 'waiting';

    final bool isPrivateMode = Get.arguments != null &&
        (Get.arguments is List && Get.arguments.length > 2) &&
        (((Get.arguments[2] as Map?)?.containsKey('mode') == true && (Get.arguments[2] as Map)['mode'] == 'createPrivate') ||
            ((Get.arguments[2] as Map?)?.containsKey('joinRoomId') == true));

    if (isBWithoutOpponent) {
      if (isPrivateMode &&
          Get.arguments != null &&
          Get.arguments is List &&
          Get.arguments.length > 2 &&
          (Get.arguments[2] as Map?)?.containsKey('mode') == true &&
          (Get.arguments[2] as Map)['mode'] == 'createPrivate') {
        if (friendlyMatchHint.parent == null) add(friendlyMatchHint);
      } else {
        friendlyMatchHint.removeFromParent();
      }

      if (waitingHint.parent == null) add(waitingHint);

      if (isPrivateMode) {
        if (privateRoomHint.parent == null || _lastMsgRoomId != game.roomId) {
          _lastMsgRoomId = game.roomId;
          privateRoomHint.text = '房间号：${game.roomId}';
          if (privateRoomHint.parent == null) add(privateRoomHint);
        }
      } else {
        privateRoomHint.removeFromParent();
        _lastMsgRoomId = null;
      }

      nickName.removeFromParent();
      score.removeFromParent();
      cowDung.removeFromParent();
      contest.removeFromParent();
      winRatio.removeFromParent();
      scoreAdjust.removeFromParent();
      cowDungAdjust.removeFromParent();
      startedStatus.removeFromParent();
      _lastNickName = null;
    } else if (!game.isPlaying && player.userGameInfo != null) {
      waitingHint.removeFromParent();
      friendlyMatchHint.removeFromParent();
      privateRoomHint.removeFromParent();

      final info = player.userGameInfo!;
      final String rawNick = info.nickName;
      if (_lastNickName != rawNick) {
        _lastNickName = rawNick;
        final String baseNick = '昵　称： $rawNick';
        final double maxWidth = player.playGround.width - 32;
        // 缓存 ellipsize 结果，避免每帧重复计算
        nickName.text = _ellipsize(baseNick, (nickName.textRenderer as TextPaint), maxWidth);
      }

      if (_lastScore != info.score) {
        _lastScore = info.score;
        score.text = '游戏分： $_lastScore';
      }

      if (_lastCowDung != info.cowDung) {
        _lastCowDung = info.cowDung;
        cowDung.text = '魔法泡泡： $_lastCowDung';
      }

      final String winLostStr = '${info.winCount} | ${info.lostCount}';
      if (_lastWinLost != winLostStr) {
        _lastWinLost = winLostStr;
        contest.text = '胜　负： $_lastWinLost';
      }

      final totalCount = info.winCount + info.lostCount;
      final String ratioStr = totalCount == 0 ? '-' : '${info.winCount * 100 ~/ totalCount}%';
      if (_lastRatio != ratioStr) {
        _lastRatio = ratioStr;
        winRatio.text = '胜　率： $_lastRatio';
      }

      if (player.isWonInLastGame != null) {
        if (_lastIsWon != player.isWonInLastGame || _lastScoreAdj != player.scoreAdjust || _lastCowAdj != player.cowdungAdjust) {
          _lastIsWon = player.isWonInLastGame;
          _lastScoreAdj = player.scoreAdjust;
          _lastCowAdj = player.cowdungAdjust;
          final bool won = _lastIsWon!;
          scoreAdjust.textRenderer = won ? _winPaint : _losePaint;
          cowDungAdjust.textRenderer = won ? _winPaint : _losePaint;
          final String prefix = won ? '+' : '-';
          scoreAdjust.text = '积分 $prefix${_lastScoreAdj!.abs()}';
          cowDungAdjust.text = '魔法泡泡 $prefix${_lastCowAdj!.abs()}';
        }
        if (scoreAdjust.parent == null) add(scoreAdjust);
        if (cowDungAdjust.parent == null) add(cowDungAdjust);
      } else {
        scoreAdjust.removeFromParent();
        cowDungAdjust.removeFromParent();
        _lastIsWon = null;
      }

      if (nickName.parent == null) {
        add(nickName);
        add(score);
        add(cowDung);
        add(contest);
        add(winRatio);
      }

      if (_lastStarted != player.started) {
        _lastStarted = player.started;
        startedStatus.text = _lastStarted! ? '已开始' : '未开始...';
      }
      if (startedStatus.parent == null) add(startedStatus);
    } else {
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
    // 增加简易缓存：如果同样的输入和约束，直接返回
    if (_lastEllipsizeInput == text && _lastEllipsizeWidth == maxWidth) return _lastEllipsizeResult!;
    
    _lastEllipsizeInput = text;
    _lastEllipsizeWidth = maxWidth;

    if (renderer.getLineMetrics(text).width <= maxWidth) {
      _lastEllipsizeResult = text;
      return text;
    }
    // 逐步裁剪并添加省略号
    String t = text;
    const String dots = '...';
    final double dotsW = renderer.getLineMetrics(dots).width;
    while (t.isNotEmpty && renderer.getLineMetrics(t).width + dotsW > maxWidth) {
      t = t.substring(0, t.length - 1);
    }
    _lastEllipsizeResult = t.isEmpty ? dots : '$t$dots';
    return _lastEllipsizeResult!;
  }
  
  String? _lastEllipsizeInput;
  double? _lastEllipsizeWidth;
  String? _lastEllipsizeResult;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    Rect rect = size.toRect();

    if (_lastRect != rect) {
      _lastRect = rect;
      _bgPaint.shader = LinearGradient(
        colors: [
          const Color(0xFF2D2D2D).withValues(alpha: 0.7),
          const Color(0xFF1A1A1A).withValues(alpha: 0.7),
          const Color(0xFF0D0D0D).withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

      _borderPaint.shader = LinearGradient(
        colors: [
          const Color(0xFF4A90E2).withValues(alpha: 0.7),
          const Color(0xFF357ABD).withValues(alpha: 0.7),
          const Color(0xFF4A90E2).withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

      _glossPaint.shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.1),
          Colors.white.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        begin: Alignment.topCenter,
        end: Alignment.center,
      ).createShader(rect);
    }

    final panelShape = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(panelShape, _bgPaint);

    // 边框
    canvas.drawRRect(panelShape, _borderPaint);

    // 内部光泽
    final glossRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.left + 2, rect.top + 2, rect.width - 4, rect.height * 0.3),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: const Radius.circular(0),
      bottomRight: const Radius.circular(0),
    );
    canvas.drawRRect(glossRect, _glossPaint);
  }

  // 缓存 Paint 和 Shader
  final Paint _bgPaint = Paint();
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _glossPaint = Paint();
  Rect? _lastRect;
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
  double _t = 0.0;
  late double _baseX;

  DroppingWordSprite(String text, this.player) : super(text: text, textRenderer: _alivePaint) {
    add(RectangleHitbox()..collisionType = CollisionType.active);
  }

  static final TextPaint _alivePaint = makeAlivePaint();
  static final TextPaint _deadPaint = makeDeadPaint();

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
    if (isDead) return; // 关键优化：死亡单词完全停止逻辑计算
    super.update(dt);

    // 按屏幕缩放比例调整下落速度，保证不同屏幕用时一致
    y += 20 * game.uiScale * dt;
    // 轻微左右摆动
    _t += dt;
    final double amp = 4.0 * (game.uiScale);
    final double freq = 2.2;
    x = _baseX + sin(_t * freq) * amp;
  }

  // 不覆写 render，使用父类默认实现

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (skipCollision || hasLanded) {
      return;
    }
    if ((other is BottomJet || other is DroppingWordSprite) && !isDead) {
      if (!game.tryBeginLanding(player)) return;
      hasLanded = true;
      isDead = true;
 
      // 优化：死亡后变为被动且停止参与物理计算
      _hitbox?.collisionType = CollisionType.passive;
 
      // 样式切换
      textRenderer = TextPaint(style: DroppingWordSprite.makeDeadPaint().style.copyWith(fontSize: _fixedFontSize));
      text = text;
 
      if (player == game.playerA) {
        y = game.getDeadWordsTopY(game.playerA) - height;
        if (!game.playerA.deadWords.contains(this)) {
          game.playerA.deadWords.add(this);
        }
        if (game.playerA.droppingWordSprite == this) game.playerA.droppingWordSprite = null;
      } else {
        y = game.getDeadWordsTopY(game.playerB) - height;
        if (!game.playerB.deadWords.contains(this)) {
          game.playerB.deadWords.add(this);
        }
        if (game.playerB.droppingWordSprite == this) game.playerB.droppingWordSprite = null;
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

class MyButtonTextComponent extends PositionComponent {
  late String text;
  late TextRenderer textRenderer;
  late Color borderColor;
  late Color backColor;
  late MyGame myGame;
  late bool isPressed;
  final double opacity; // 0.0 ~ 1.0 半透明系数
  double verticalPadding; // 竖向内边距影响按钮整体高度（目前布局引擎主控高度）

  // 点击动效状态
  bool _clickEffectActive = false;
  double _clickEffectT = 0.0; // seconds
  static const double _clickEffectDuration = 0.28; // seconds
  Vector2? _cachedTextPos;

  MyButtonTextComponent(this.text, this.textRenderer, this.backColor, this.borderColor, this.myGame, this.verticalPadding,
      {this.isPressed = false, this.opacity = 0.8})
      : super(position: Vector2.zero());

  // 缓存绘制资源
  final Paint _bgPaint = Paint();
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  Rect? _lastRect;
  double? _lastOpacity;
  bool? _lastIsPressed;

  TextPaint? _cachedOpacityPaint;
  double? _lastTextOpacity;
  TextRenderer? _lastOriginalRenderer;

  // 截断文本相关缓存
  String? _cachedDisplayExText;
  double? _cachedTextW;
  double? _cachedTextH;
  String? _lastInputText;
  double? _lastConstraintWidth;
  TextPaint? _lastActiveTextPaint;

  @override
  void update(double dt) {
    super.update(dt);
    // 更新点击动效时间轴
    if (_clickEffectActive) {
      _clickEffectT += dt;
      if (_clickEffectT >= _clickEffectDuration) {
        _clickEffectActive = false;
        _clickEffectT = 0.0;
      }
    }
  }

  void triggerClickEffect() {
    _clickEffectActive = true;
    _clickEffectT = 0.0;
  }

  // 烘焙缓存：按钮背景一旦渲染过就不再每一帧都进行绘图计算
  static ui.Image? _cachedNormalBg;
  static ui.Image? _cachedPressedBg;
  static double _lastBakeW = -1;
  static double _lastBakeH = -1;

  @override
  void render(Canvas canvas) {
    if (size.x <= 0 || size.y <= 0) return;

    final Rect rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // 如果尺寸变化，清理背景缓存进行重新烘焙
    if (_lastBakeW != size.x || _lastBakeH != size.y) {
      _lastBakeW = size.x;
      _lastBakeH = size.y;
      _cachedNormalBg?.dispose();
      _cachedPressedBg?.dispose();
      _cachedNormalBg = null;
      _cachedPressedBg = null;
    }

    // 按需烘焙背景
    if (isPressed) {
      _cachedPressedBg ??= _bakeBg(rect, true);
    } else {
      _cachedNormalBg ??= _bakeBg(rect, false);
    }

    final ui.Image bg = isPressed ? _cachedPressedBg! : _cachedNormalBg!;
    canvas.drawImage(bg, Offset.zero, Paint());

    // 点击动效遮罩
    if (_clickEffectActive) {
      final double p = (_clickEffectT / _clickEffectDuration).clamp(0.0, 1.0);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), Paint()..color = Colors.black.withValues(alpha: 0.18 * (1 - p)));
    }

    // 绘制文本
    _cachedTextPos ??= Vector2.zero();
    _cachedTextPos!.setValues((size.x - _cachedTextW!) / 2, (size.y - _cachedTextH!) / 2 - 1);
    _cachedOpacityPaint!.render(canvas, _cachedDisplayExText!, _cachedTextPos!);
  }

  ui.Image _bakeBg(Rect rect, bool pressed) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    
    // 背景渐变
    paint.shader = LinearGradient(
      colors: pressed 
        ? [const Color(0xFF2E5F8A).withValues(alpha: opacity), const Color(0xFF357ABD).withValues(alpha: opacity)]
        : [const Color(0xFF4A90E2).withValues(alpha: opacity), const Color(0xFF357ABD).withValues(alpha: opacity), const Color(0xFF2E5F8A).withValues(alpha: opacity)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(rect);
    
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, paint);
    
    // 边框
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = (pressed ? const Color(0xFF4A90E2) : const Color(0xFF5BA3F5)).withValues(alpha: opacity);
    canvas.drawRRect(rrect, borderPaint);

    return recorder.endRecording().toImageSync(rect.width.toInt(), rect.height.toInt());
  }

  // 由外部在点击时调用，启动动效
  void startClickEffect() {
    _clickEffectActive = true;
    _clickEffectT = 0.0;
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
    // 仅在尺寸不一致时同步，减少属性设置开销
    if (size != ownerButton.size) {
      size.setFrom(ownerButton.size);
    }
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
