import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:nnbdc/page/index.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_list/batch_words.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:flutter/scheduler.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';

import '../api/enum.dart';
import '../api/vo.dart';
import '../config.dart';
import '../db/db.dart';
import '../global.dart';
import '../state.dart';
import '../util/asr.dart';
import '../util/asr_util.dart';
import '../constants.dart';
import '../util/utils.dart';
import '../db/user_extensions.dart';
import '../util/error_handler.dart';
import '../theme/app_theme.dart';
import '../util/learning_service.dart';
import '../util/fsrs.dart';
import '../widget/handwriting_board.dart';
import '../util/study_config.dart';
import '../util/analytics_util.dart';

class BdcPageArgs {
  /// 从哪个页面进入本页面
  String? fromPage;

  BdcPageArgs(this.fromPage);

  Map<String, dynamic> toMap() {
    return {
      "fromPage": fromPage,
    };
  }

  String toJson() => json.encode(toMap());

  factory BdcPageArgs.fromMap(Map<String, dynamic> map) {
    return BdcPageArgs(
      map["fromPage"],
    );
  }

  factory BdcPageArgs.fromJson(String value) {
    return BdcPageArgs.fromMap(json.decode(value));
  }
}

class WordImagesWidget extends StatefulWidget {
  final List<WordImageVo> images;
  final bool isEditMode;
  final Function(WordImageVo) onImageTap;
  final String? highlightedWordImg;
  final int maxImages;

  const WordImagesWidget({
    super.key,
    required this.images,
    required this.isEditMode,
    required this.onImageTap,
    this.highlightedWordImg,
    this.maxImages = 2,
  });

  @override
  State<WordImagesWidget> createState() => _WordImagesWidgetState();
}

class _WordImagesWidgetState extends State<WordImagesWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用实际可用宽度而不是屏幕宽度
        final availableWidth = constraints.maxWidth;
        final imageCount = 2; // 每行显示2张图片
        final spacing = 12.0; // 固定间距

        // 动态计算较大图片的宽度，同时在Web上限制最大尺寸
        double imageWidth = (availableWidth - spacing) / imageCount - 0.1;
        if (PlatformUtils.isWeb && imageWidth > 320.0) {
          imageWidth = 320.0;
        }
        final imageHeight = imageWidth * 0.75; // 4:3比例计算高度

        return Container(
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          width: availableWidth,
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center, // 居中对齐
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: spacing,
            runSpacing: 12.0, // 行间距
            children: [
              for (var image in widget.images.take(widget.maxImages))
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Global.logger
                        .d('GestureDetector onTap image: ${image.imageFile}');
                    widget.onImageTap(image);
                  },
                  child: SizedBox(
                    width: imageWidth,
                    child: IgnorePointer(
                      ignoring: true,
                      child: Image.network(
                        '${Config.wordImageBaseUrl}${image.imageFile}',
                        width: imageWidth,
                        height: imageHeight,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                                color: Colors.indigoAccent,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          // 图片加载失败，显示错误图标，不尝试解码
                          return const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.red,
                              size: 24,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 预览单词配图的大图弹窗（使用当前上下文）
void _showImagePreviewWithContext(BuildContext context, WordImageVo image,
    {VoidCallback? onDeleted}) {
  Global.logger.d('showDialog start for image: ${image.imageFile}');
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      Global.logger.d('showDialog builder for image: ${image.imageFile}');
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 作者昵称
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 8, right: 40, bottom: 8),
                      child: Text(
                        '上传: ${Util.getNickNameOfUser(image.author)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    // 大图
                    Image.network(
                      '${Config.wordImageBaseUrl}${image.imageFile}',
                      width: PlatformUtils.isWeb ? 720.0 : double.infinity,
                      height: PlatformUtils.isWeb ? 480.0 : 360.0,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.red, size: 48),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // 右上角关闭按钮
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 右下角删除按钮（仅作者本人或管理员可见）
            if (image.author.id == Global.getLoggedInUser()?.id ||
                (Global.getLoggedInUser()?.isAdmin ?? false) ||
                (Global.getLoggedInUser()?.isSuperAdmin ?? false))
              Positioned(
                right: 8,
                bottom: 8,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                  onPressed: () async {
                    try {
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      final result = await Api.client.deleteWordImage(
                          image.id, Global.getLoggedInUser()!.id);
                      if (result.success) {
                        ToastUtil.info('删除成功');
                        // 本地同步移除
                        if (onDeleted != null) {
                          onDeleted();
                        }
                      } else {
                        ToastUtil.error(result.msg ?? '删除失败');
                      }
                    } catch (e, s) {
                      Global.logger.e('删除图片异常', error: e, stackTrace: s);
                      ToastUtil.error('删除异常');
                    }
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ChineseAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;
  final FocusNode focusNode;

  const ChineseAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
    required this.focusNode,
  });

  @override
  State<ChineseAsrInputWidget> createState() => _ChineseAsrInputWidgetState();
}

class _ChineseAsrInputWidgetState extends State<ChineseAsrInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  StreamSubscription<double>? _meterSubscription;
  double _currentLevel = 0.0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _meterSubscription = Asr().meterStream().listen((level) {
      if (mounted) {
        setState(() {
          // 增加平滑处理，避免剧烈抖动
          _currentLevel = _currentLevel * 0.8 + level * 0.2;
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _meterSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final accentColor = AppTheme.primaryColor;

    // 状态驱动反馈文字
    String statusText;
    switch (widget.asrState) {
      case AsrState.started:
        statusText = "正在倾听...";
        break;
      case AsrState.stopping:
      case AsrState.unknown:
        statusText = "正在处理中...";
        break;
      case AsrState.initialized:
      case AsrState.stopped:
        statusText = "";
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 波纹动画反馈 (始终显示以保持布局稳定)
          SizedBox(
            height: 20,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (index) {
                    // 默认静止状态（准备就绪/处理中）
                    double height = 4.0;
                    double alpha = 0.2;

                    // 动态聆听状态
                    if (widget.asrState == AsrState.started) {
                      // 基础呼吸扫描值（用于待机）
                      final double breath = sin(
                          (_waveController.value + (index * 0.125)) * pi * 2);

                      // 提高阈值 (原 0.01) 到 0.12 以过滤 iPad 等设备的高灵敏微弱底噪
                      if (_currentLevel > 0.12) {
                        // 正在说话：高敏捷跳动波形
                        final randomFactor = 0.5 + _random.nextDouble();
                        // 减小放大倍数 (原 100) 到 35，避免动不动就满格，且波形更平滑
                        height = 6.0 + (35 * _currentLevel * randomFactor);
                        if (height > 20) height = 20;
                        alpha = 0.6 + (2.0 * _currentLevel);
                        if (alpha > 1.0) alpha = 1.0;
                      } else {
                        // 待机静音：基础颜色深、振幅明显的呼吸波纹
                        height = 5.0 + (6.0 * (breath + 1) / 2);
                        alpha = 0.4 + (0.3 * (breath + 1) / 2);
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 2.5,
                      height: height,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: alpha),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 10,
              color: isDarkMode ? Colors.white38 : Colors.black26,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class EnglishAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;
  final FocusNode focusNode;
  final int? score; // 新增：评分

  const EnglishAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
    required this.focusNode,
    this.score,
  });

  @override
  State<EnglishAsrInputWidget> createState() => _EnglishAsrInputWidgetState();
}

class _EnglishAsrInputWidgetState extends State<EnglishAsrInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  StreamSubscription<double>? _meterSubscription;
  double _currentLevel = 0.0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _meterSubscription = Asr().meterStream().listen((level) {
      if (mounted) {
        setState(() {
          // 增加平滑处理，避免剧烈抖动
          _currentLevel = _currentLevel * 0.8 + level * 0.2;
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _meterSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final accentColor = AppTheme.primaryColor;

    // 状态驱动反馈文字
    String statusText;
    switch (widget.asrState) {
      case AsrState.started:
        statusText = "正在倾听...";
        break;
      case AsrState.stopping:
      case AsrState.unknown:
        statusText = "正在处理中...";
        break;
      case AsrState.initialized:
      case AsrState.stopped:
        statusText = "发音评分";
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 波纹动画反馈
          SizedBox(
            height: 20,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (index) {
                    // 默认静止状态（准备就绪/处理中）
                    double height = 4.0;
                    double alpha = 0.2;

                    // 动态聆听状态
                    if (widget.asrState == AsrState.started) {
                      // 基础呼吸扫描值（用于待机）
                      final double breath = sin(
                          (_waveController.value + (index * 0.125)) * pi * 2);

                      // 提高阈值 (原 0.01) 到 0.12 以过滤 iPad 等设备的高灵敏微弱底噪
                      if (_currentLevel > 0.12) {
                        // 正在说话：高敏捷跳动波形
                        final randomFactor = 0.5 + _random.nextDouble();
                        // 减小放大倍数 (原 100) 到 35，避免动不动就满格，且波形更平滑
                        height = 6.0 + (35 * _currentLevel * randomFactor);
                        if (height > 20) height = 20;
                        alpha = 0.6 + (2.0 * _currentLevel);
                        if (alpha > 1.0) alpha = 1.0;
                      } else {
                        // 待机静音：基础颜色深、振幅明显的呼吸波纹
                        height = 5.0 + (6.0 * (breath + 1) / 2);
                        alpha = 0.4 + (0.3 * (breath + 1) / 2);
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 2.5,
                      height: height,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: alpha),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  color: isDarkMode ? Colors.white38 : Colors.black26,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.score != null && widget.score! > 0) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: '发音评分',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.score! >= 60
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      border: Border.all(
                        color: widget.score! >= 60
                            ? Colors.green.withValues(alpha: 0.5)
                            : Colors.orange.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${widget.score}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color:
                            widget.score! >= 60 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class BdcPage extends StatefulWidget {
  const BdcPage({super.key});

  @override
  BdcPageState createState() {
    return BdcPageState();
  }
}

class BdcPageState extends State<BdcPage> with TickerProviderStateMixin {
  String _getStudyStageLabel() {
    final lw = _currentGetWordResult?.learningWord;
    if (lw == null) return "";
    return (lw.reps ?? 0) == 0 ? "(测评)" : "(巩固)";
  }

  bool dataLoaded = false;
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  static const int batchSize = 10;
  late List<UserStudyStepVo> activeUserStudySteps;
  var errorReportController = TextEditingController();
  late Asr asr;
  bool _showSentenceTranslation = false;

  /// 释义输入框
  late final SpellingTextEditingController _meaningController =
      SpellingTextEditingController(
    getTargetSpell: () => _word?.spell,
    baseColor: AppTheme.primaryColor,
  );

  /// 释义输入框焦点控制
  final FocusNode _meaningFocusNode = FocusNode();

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// 说意/英拼写面板的滚动控制
  final ScrollController _speakPanelScrollController = ScrollController();

  /// AudioPlayer 是否已被释放的标志
  bool _audioPlayerDisposed = false;

  late BdcPageArgs _args;

  /// 是否允许用户点击下一词按钮离开当前单词（英→中模式下，用户asr回答正确了至少一个释义）
  bool _canLeaveCurrWord = false;

  /// 正在进行匹配的asr输入，防止重复处理，影响性能
  var _handlingChinese = "";

  /// 标志位：是否正在由[给点提示]/[清除提示]修改文本，避免触发 checkAsrResult
  bool _isUpdatingByHint = false;

  /// 当前正在学习的单词
  GetWordResult? _currentGetWordResult;

  /// 正确答案的索引号
  int _correctAnswerIndex = 0;
  
  /// 用户刚点击的选项索引号（用于答题后颜色反馈）
  int? _selectedAnswerIndex;
  
  /// 用户考后翻牌查看翻译的选项索引
  final Set<int> _flippedAnswerIndices = {};

  /// 当前单词是否回答正确
  bool _hasFinishedAnswering = false;

  /// 当前单词是否已经掌握
  bool _isWordMastered = false;

  /// 当前单词的第一个例句
  String? _englishDigestOfFirstSentence;

  String? _studyStep;

  /// 当前单词
  WordVo? _word;

  /// 当前单词的Wrapper，供recite模式使用
  WordWrapper? _wordWrapper;

  /// 当前单词及其他备选单词
  List<WordVo>? _words;

  /// 缓存 ASR 通过规则，避免在处理过程频繁查库导致性能问题和死锁挂起
  String _asrPassRuleCache = 'ONE';

  late bool _showAnswerButtons;

  late StreamSubscription _keyboardSubscription;

  late bool _isKeyboardVisible;

  // 底部按钮实际高度，用于为做题区内容预留空间，避免被遮挡
  final GlobalKey _bottomButtonsKey = GlobalKey();

  // 题目区和做题区之间的统一间距
  static const double _questionAnswerGap = 8.0;

  /// 控制做题区、题目区和底部按钮的边框是否显示
  final bool _showBorders = false;

  var _isDarkMode = false;

  final _isEditMode = false;

  String? _highlightedWordImg;

  bool _wordImageEdited = false;

  late AnimationController _soundController;
  late AnimationController _wordSoundController;
  late AnimationController _sentenceSoundController;
  // 当前发音评分
  int? _currentScore;

  /// 答对后是否自动跳转到下一个单词 (极速模式)
  bool _autoJumpAfterCorrectCh2En = true;
  bool _autoJumpAfterCorrectEn2Ch = false;

  bool get _autoJumpAfterCorrect {
    if (_studyStep == StudyStep.ch2En.json) {
      return _autoJumpAfterCorrectCh2En;
    }
    return _autoJumpAfterCorrectEn2Ch;
  }

  set _autoJumpAfterCorrect(bool value) {
    if (_studyStep == StudyStep.ch2En.json) {
      _autoJumpAfterCorrectCh2En = value;
    } else {
      _autoJumpAfterCorrectEn2Ch = value;
    }
  }

  /// 是否保持在拼写输入界面 (图钉模式)

  /// 当前单词的 FSRS 预览结果
  FSRSItem? _fsrsItem;

  /// 距离上次复习的天数
  int? _daysSinceLastReview;

  /// 记录当前单词的评分，延后到点击“下一个”或自动跳转时保存
  FsrsRating? _lastFsrsRating;
  String? _lastFsrsRatingReason;

  final Map<String, bool> _playingStates = {
    'word': false, // 单词发音
    'sentence': false, // 例句发音
  };

  /// 当前正在播放的所有提示音 Future 列表，用于等待所有提示音播放完成
  final List<Future<void>> _playingCorrectSounds = [];

  /// 当前 ASR 会议返回的所有候选结果，用于在英→中模式下进行多重探测
  List<String> _currentAsrCandidates = [];

  /// 学习时长计时器
  Timer? _learningTimer;
  int _accumulatedSeconds = 0;

  /// 进度条连击计数，用于触发调试浮窗
  int _progressBarTapCount = 0;
  Timer? _progressBarTapTimer;

  /// 当前单词学习的开始时间
  DateTime? _wordStartTime;
  DateTime? _firstMatchTime;
  int _hintTapCount = 0;

  /// Tab控制器，用于管理说/选两个tab
  TabController? _tabController;

  /// 记住当前选中的tab索引，避免总是切回"说"tab
  int _currentTabIndex = 0; // 默认选择"说"tab

  /// 是否显示手写板
  bool _showHandwritingBoard = false;

  /// 判断当前是否在"说"tab
  bool get _isInSpeakTab {
    if (!_shouldShowSpeakTab) return false;
    return _tabController?.index == 0;
  }

  /// 判断是否应该显示"说"tab
  /// 根据平台ASR支持情况和学习模式决定
  bool get _shouldShowSpeakTab {
    // 如果平台不支持ASR，隐藏"说"tab
    if (!PlatformUtils.isAsrSupported()) return false;

    // 如果是"中→英"模式，需要英文ASR支持
    if (_studyStep == StudyStep.ch2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }

    // "英→中"模式，只要支持ASR即可（iOS和Android都支持中文ASR）
    return true;
  }

  /// 动态生成tabs列表
  List<Tab> get _dynamicTabs {
    List<Tab> tabs = [];

    if (_shouldShowSpeakTab) {
      tabs.add(Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, size: 18),
            const SizedBox(width: 4),
            const Text('说'),
          ],
        ),
      ));
    }

    tabs.add(Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, size: 18),
          const SizedBox(width: 4),
          const Text('选'),
        ],
      ),
    ));

    return tabs;
  }

  /// 动态生成TabBarView的children
  List<Widget> get _dynamicTabBarViewChildren {
    List<Widget> children = [];

    if (_shouldShowSpeakTab) {
      // 说意/说英tab
      children.add(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildSpeakPanel()),
        ],
      ));
    }

    // 选择题tab
    children.add(SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _buildChoiceList(),
        ],
      ),
    ));

    return children;
  }

  /// 重新初始化TabController
  void _reinitializeTabController() {
    // 记住当前tab索引
    if (_tabController != null) {
      _currentTabIndex = _tabController!.index;
    }

    // 注意：不在这里 dispose 旧的 TabController，避免在手势处理中
    // 仍然引用旧 controller 时触发 "used after being disposed" 异常。
    // 旧的 controller 会在页面整体 dispose 时统一释放。
    _tabController = TabController(length: _dynamicTabs.length, vsync: this);

    // 确保索引在有效范围内
    if (_currentTabIndex >= _dynamicTabs.length) {
      _currentTabIndex = _dynamicTabs.length - 1; // 选择最后一个tab
    }

    // 设置到之前选中的tab
    _tabController!.index = _currentTabIndex;

    // 重新添加监听器
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        // Tab正在切换中
        return;
      }

      // 更新当前tab索引
      _currentTabIndex = _tabController!.index;

      _handleTabChangeForAsr();
    });
  }

  /// 根据当前tab状态处理ASR启动/停止逻辑
  void _handleTabChangeForAsr() {
    _doHandleTabChangeForAsr();
  }

  /// 实际执行ASR启动/停止逻辑
  void _doHandleTabChangeForAsr() {
    if (_isInSpeakTab) {
      // 当前在"说"tab
      _firstMatchTime = null;

      // 如果ASR已经启动且状态正确，计时器已经开始或将在_startAsrWithHint中重置
      if (asr.state == AsrState.started && !_isKeyboardVisible) {
        Global.logger.d('BDC: 当前在"说"tab，ASR已启动，保持计时');
        return;
      }
      // 将在此处设置初始计时，防止_startAsrWithHint被跳过或延迟太久
      _wordStartTime = DateTime.now();

      // 启动ASR
      Global.logger.d('BDC: 当前在"说"tab，启动ASR (studyStep=$_studyStep)');
      if (!_isKeyboardVisible) {
        // 设置上下文短语
        _setAsrContextualPhrases();
        final language = decideAsrLanguage();
        Global.logger.d('BDC: 准备启动ASR，语言=${language.locale}');
        // 启动ASR并播放提示音
        _startAsrWithHint(language);
      }
    } else {
      // 当前在"选"tab，从切换这一刻重新开始计时（之前的播放时间或 ASR 等待时间不计入）
      _wordStartTime = DateTime.now();
      _firstMatchTime = null;

      // 如果当前在"选"tab，如果ASR已经停止，不需要再次停止

      // 如果当前在"选"tab，如果ASR已经停止，不需要再次停止
      if (asr.state == AsrState.stopped || asr.state == AsrState.initialized) {
        Global.logger.d('BDC: 当前在"选"tab，ASR已停止，跳过重复停止');
        return;
      }
      // 当前在"选"tab，停止ASR
      Global.logger.d('BDC: 当前在"选"tab，停止ASR');
      asr.stopAsr();
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(SoundUtil.configureAudioSession());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final argsJson = GetStorage().read<String>("BdcPageArgs");
    if (argsJson != null) {
      _args = BdcPageArgs.fromJson(argsJson);
    } else {
      _args = BdcPageArgs('unknown');
    }

    // 初始化两个动画控制器
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _sentenceSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _meaningController.addListener(() {
      checkAsrResult();
    });

    // 监听输入框焦点，进入沉浸式文本输入模式
    _meaningFocusNode.addListener(() {
      if (_meaningFocusNode.hasFocus) {
        // 停止 ASR
        Global.logger.d('BDC: 输入框获取焦点，停止 ASR');
        asr.stopMicrophone(); // 彻底停止 ASR
        setState(() {}); // 触发进入沉浸式模式
      } else {
        setState(() {}); // 触发退出沉浸式模式
      }
    });

    // 监听输入法键盘弹出和隐藏
    var keyboardVisibilityController = KeyboardVisibilityController();
    _isKeyboardVisible = keyboardVisibilityController.isVisible;
    _keyboardSubscription =
        keyboardVisibilityController.onChange.listen((bool visible) {
      _isKeyboardVisible = visible;
      if (_isKeyboardVisible) {
        // 键盘弹出时，彻底停止ASR并关闭麦克风
        asr.stopMicrophone();
      } else {
        // 键盘隐藏时，复用与Tab切换一致的ASR启动/停止逻辑
        if (_isInSpeakTab) {
          _setAsrContextualPhrases();
        }
        _handleTabChangeForAsr();
      }
      setState(() {});
    });

    asr = Asr();
    //asr.initAsr(onAsrResult);
    asr.addStateListener((state) {
      if (!mounted) return;
      // 避免在其他页面构建过程中直接触发 BdcPage 的 setState，
      // 在非空闲阶段改为下一帧再刷新，防止 "setState during build" 异常
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase == SchedulerPhase.idle ||
          phase == SchedulerPhase.postFrameCallbacks) {
        setState(() {});
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    });

    _soundController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _startLearningTimer();

    loadData();
  }

  void _startLearningTimer() {
    _learningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _accumulatedSeconds++;
      if (_accumulatedSeconds % 10 == 0) {
        _syncLearningTimeToDb();
      }
    });
  }

  Future<void> _syncLearningTimeToDb() async {
    if (_accumulatedSeconds <= 0) return;
    int secsToSync = _accumulatedSeconds;
    _accumulatedSeconds = 0;

    try {
      final user = Global.getLoggedInUser();
      if (user == null) return;
      final dao = MyDatabase.instance.usersDao;
      final dbUser = await dao.getUserById(user.id);
      if (dbUser != null) {
        // 重置今日学习时长（如果不是今天）
        int todaySecs = dbUser.todayLearningSeconds ?? 0;
        if (dbUser.lastLearningDate != null) {
          final now = DateTime.now();
          if (dbUser.lastLearningDate!.year != now.year ||
              dbUser.lastLearningDate!.month != now.month ||
              dbUser.lastLearningDate!.day != now.day) {
            todaySecs = 0;
          }
        }

        final newTotal = (dbUser.totalLearningSeconds ?? 0) + secsToSync;
        final newToday = todaySecs + secsToSync;

        final updatedDbUser = dbUser.copyWith(
          totalLearningSeconds: drift.Value(newTotal),
          todayLearningSeconds: drift.Value(newToday),
          lastLearningDate: drift.Value(DateTime.now()),
        );

        await dao.saveUser(updatedDbUser, true);
        Global.updateUserCache(updatedDbUser);
      }
    } catch (e) {
      Global.logger.e("同步学习时长失败", error: e);
      // 如果失败把时间加回去
      _accumulatedSeconds += secsToSync;
    }
  }

  AsrLanguage decideAsrLanguage() {
    Global.logger.d(
        'BDC: decideAsrLanguage() - studyStep=$_studyStep, meaning.json=${StudyStep.ch2En.json}, word.json=${StudyStep.en2Ch.json}');
    if (_studyStep == StudyStep.ch2En.json) {
      Global.logger.d('BDC: 决定使用英文ASR (中→英模式)');
      return AsrLanguage.english;
    }
    Global.logger.d('BDC: 决定使用中文ASR (英→中模式)');
    return AsrLanguage.chinese;
  }

  /// 设置ASR上下文短语（当前单词的释义子项(说中文)或当前单词的拼写(说英文)）
  void _setAsrContextualPhrases() {
    // 禁止下发上下文短语，以满足用户“无判断、无偏见”的原始识别需求
    /*
    try {
      WordVo? word = _currentGetWordResult?.learningWord?.word;
      if (word != null) {
        ...
      }
    } catch (e) {
      Global.logger.d('设置ASR上下文短语失败: $e');
    }
    */
  }

  /// 启动ASR并播放提示音
  Future<void> _startAsrWithHint(AsrLanguage language) async {
    // 如果ASR已经在运行中，不需要重复启动
    if (asr.state == AsrState.started) {
      Global.logger.d('BDC: ASR已经在运行中，跳过重复启动');
      return;
    }

    try {
      await asr.startAsr(language);
      Global.logger.d('BDC: ASR启动成功，播放提示音并计时');
      // startAsr 后立即播放提示音：mixWithOthers 保证录音和播放可共存
      // 注意：不在此处先 stopAsr 再播再 startAsr，那样会多两次音频会话切换产生额外噪音
      if (PlatformUtils.isIOS) {
        // iOS上AVAudioEngine启动后需要一小段缓冲时间，否则紧接着播放音频会产生发颤或杂音
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await SoundUtil.playAsrReadyHintSound();
      _wordStartTime = DateTime.now();
    } catch (e, stackTrace) {
      Global.logger.e('BDC: ASR启动失败', error: e, stackTrace: stackTrace);
      // 即使启动抛出异常，如果 ASR 状态已经是 started（iOS 上会抛异常但实际已启动），
      // 仍然需要播放提示音，提示用户可以开始说话
      if (asr.state == AsrState.started) {
        Global.logger.d('BDC: ASR状态为started，播放提示音并计时');
        if (PlatformUtils.isIOS) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
        await SoundUtil.playAsrReadyHintSound();
        _wordStartTime = DateTime.now();
      }
    } finally {}
  }

  @override
  void dispose() {
    _learningTimer?.cancel();
    _syncLearningTimeToDb();

    asr.removeStateListener((state) {
      if (mounted) {
        setState(() {});
      }
    });
    asr.dispose();
    asr.stopMicrophone();
    _keyboardSubscription.cancel();
    _tabController?.dispose();
    _meaningFocusNode.dispose();
    _speakPanelScrollController.dispose();
    _soundController.dispose();
    _wordSoundController.dispose();
    _sentenceSoundController.dispose();
    GetStorage().remove("BdcPageArgs");

    // 标记 AudioPlayer 为已释放
    _audioPlayerDisposed = true;

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        _audioPlayer.dispose();
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace,
            logPrefix: '释放 AudioPlayer 时出错', showToast: false);
      }
    });

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _asrDebounceTimer?.cancel();
    super.dispose();
  }

  Timer? _asrDebounceTimer;

  onAsrResult(event) async {
    // 预处理ASR结果，然后更新 meaningController
    String processedResult;
    int? oldScore = _currentScore;

    // 统一处理JSON格式的候选结果（适用于所有模式）
    try {
      // 尝试解析JSON格式的候选结果
      Map<String, dynamic>? resultData;
      try {
        resultData = jsonDecode(event);
      } catch (e) {
        // 如果不是JSON格式，当作单个结果处理
        resultData = null;
      }

      if (resultData != null && resultData.containsKey('candidates')) {
        // 处理多个候选结果
        List<dynamic> candidates = resultData['candidates'];
        List<String> candidateStrings =
            candidates.map((e) => e.toString()).toList();
        String bestCandidate = resultData['best'] ?? candidateStrings.first;

        _currentAsrCandidates = candidateStrings;

        if (_studyStep == StudyStep.ch2En.json) {
          if (_word != null) {
            // 中→英模式：结合拼写相似度和音素相似度的智能选择
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
                candidateStrings, _word!.spell);
            if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = result.score;
            processedResult =
                AsrUtil.preprocessEnglish(result.text, _word!.spell);
            Global.logger.d(
                'ASR: Selected & Preprocessed: "$processedResult" (score: ${result.score})');
          } else {
            processedResult = bestCandidate;
            if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = null;
          }
        } else if (_studyStep == StudyStep.en2Ch.json) {
          // 英→中模式：UI 显示最佳候选，但背后匹配逻辑会遍历所有 _currentAsrCandidates
          processedResult = AsrUtil.preprocess(bestCandidate);
          if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = null;
          Global.logger.d(
              'ASR [en2Ch]: Stored ${candidateStrings.length} candidates, showing best: $processedResult');
        } else {
          processedResult = bestCandidate;
          if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = null;
        }
      } else {
        // 单个结果处理
        _currentAsrCandidates = [event.toString()];
        if (_studyStep == StudyStep.ch2En.json) {
          if (_word != null) {
            final pre = AsrUtil.preprocessEnglish(event, _word!.spell);
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
                [pre], _word!.spell);
            processedResult = result.text;
            if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = result.score;
          } else {
            processedResult = event;
            if (!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) _currentScore = null;
          }
        } else {
          processedResult = AsrUtil.preprocess(event);
          Global.logger.d('ASR: Chinese processed result: $processedResult');
        }
      }
    } catch (e) {
      Global.logger.e('ASR: Error processing result: $e');
      processedResult = AsrUtil.preprocess(event.toString());
      _currentAsrCandidates = [event.toString()];
    }

    if (mounted) {
      if ((!_hasFinishedAnswering || _lastFsrsRating == FsrsRating.again) && oldScore != _currentScore) {
        setState(() {}); // 触发 UI 刷新以实时显示最新的发音评分（即使没通过也能让用户看到反馈分数变化）
      }
      checkAsrResult(asrInput: processedResult);
    }
  }

  void _onAnswerCorrect(FsrsRating rating) async {
    _hasFinishedAnswering = true;
    _canLeaveCurrWord = true;

    if (!_autoJumpAfterCorrect) {
      Global.logger.d(
          'BDC: 非极速模式，拼写正确，准备关闭沉浸式输入界面. _showHandwritingBoard=false, unfocusing');
      _meaningFocusNode.unfocus();
      setState(() {
        _showHandwritingBoard = false; // 立即关闭且回到主界面
      });
    }

    // 计算 FSRS 预览结果
    final lw = _currentGetWordResult?.learningWord;
    if (lw != null) {
      final fsrs = FSRS();

      // 计算距离上次复习的天数
      _daysSinceLastReview = 0;
      if (lw.lastLearningDate != null) {
        final lastDate = DateTime(lw.lastLearningDate!.year,
            lw.lastLearningDate!.month, lw.lastLearningDate!.day);
        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        _daysSinceLastReview = todayDate.difference(lastDate).inDays;
      }

      if (lw.stability == null || lw.stability == 0.0) {
        _fsrsItem = fsrs.init(rating);
      } else {
        final prevItem = FSRSItem(
          stability: lw.stability!,
          difficulty: lw.difficulty!,
          elapsedDays: _daysSinceLastReview ?? 0,
          scheduledDays: lw.scheduledDays ?? 0,
          reps: lw.reps ?? 0,
          lapses: lw.lapses ?? 0,
          state: FsrsStateExt.fromInt(lw.state),
        );
        _fsrsItem = fsrs.next(prevItem, rating, _daysSinceLastReview ?? 0);
      }
    }

    _lastFsrsRating = rating;

    if (!_autoJumpAfterCorrect && _wordWrapper != null) {
      final meaningItems = _wordWrapper!.word.getMergedMeaningItems();
      for (var i = 0; i < meaningItems.length; i++) {
        var parts = splitMeaning2Parts(meaningItems[i].meaning!);
        for (var j = 0; j < parts.length; j++) {
          if (!_wordWrapper!.asrMatchedMeaningItemParts.contains(Pair(i, j)) &&
              !_wordWrapper!.asrRevealedMeaningItemParts.contains(Pair(i, j))) {
            _wordWrapper!.asrRevealedMeaningItemParts.add(Pair(i, j));
          }
        }
      }
    }

    if (mounted) {
      setState(() {}); // 立即显示 FSRS 和完整释义
    }

    if (PlatformUtils.isIOS) {
      // 给 iOS 音频引擎短暂的 150ms 使缓冲队列刷新，避免 ASR 重置与立即起播发生抢占导致声音发抖发颤
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // 播放正确提示音
    final soundFuture =
        SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.5, 0.2);
    soundFuture.whenComplete(() async {
      // 播放一遍单词的标准发音
      await SoundUtil.playPronounceSound2(_word!, _audioPlayer);

      if (_autoJumpAfterCorrect) {
        getNextWord(true, fsrsRating: rating);
      }
    });
  }

  checkAsrResult({String? asrInput}) async {
    if (asrInput != null) {
      _isUpdatingByHint = false;
    }
    if (_isUpdatingByHint) return;
    String inputText = asrInput ?? _meaningController.text;

    Global.logger.d(
        'BDC CHECK_ASR: Start. inputText=$inputText, _handlingChinese=$_handlingChinese, _studyStep=$_studyStep, asr.state=${asr.state}, _isKeyboardVisible=$_isKeyboardVisible, _meaningFocusNode.hasFocus=${_meaningFocusNode.hasFocus}, _wordWrapper=${_wordWrapper != null}, _word=${_word != null}');

    if (inputText.isEmpty) {
      if (_currentScore != null) {
        setState(() {
          _currentScore = null;
        });
      }
      return;
    }
    // 如果 ASR 未启动，且键盘也未弹出，且没有焦点，说明可能是 ASR 停止后的残留结果，跳过处理并清空
    // 如果是在手写模式下，或者是键盘弹出的情况下，允许通过检查
    bool isHandwritingOrKeyboard = _showHandwritingBoard ||
        _isKeyboardVisible ||
        _meaningFocusNode.hasFocus;

    // 如果输入框中的文本与正在处理的文本相同，则直接返回, 避免无谓的性能损耗
    if (inputText != _handlingChinese) {
      Global.logger.d(
          'BDC CHECK_ASR: Update _handlingChinese from "$_handlingChinese" to "$inputText"');
      _handlingChinese = inputText;

      // No setState here to prevent extreme UI repaints on every partial ASR result
    } else {
      Global.logger.d(
          'BDC CHECK_ASR: _handlingChinese hasn\'t changed ("$_handlingChinese"), returning early.');
      return;
    }

    // 如果已经答对，且并未处于练习拼写的看板模式（或者看板是固定模式），则跳过处理。
    // 但是如果是“答错（Again）”的战损状态，我们允许 ASR 活跃，以便用户练习跟读！
    // 如果已经完成作答（_hasFinishedAnswering 为 true），我们仍然允许 ASR 活跃处理结果，
    // 以便在“再学学”或者其它模式下让用户继续通过 ASR 练习发音并得到正确/失败的反馈。
    // 这种情况下，后续的 match 逻辑中 wasAlreadyCorrect 为 true，从而仅播放音效而不重新计分。
    if (_hasFinishedAnswering && !_showHandwritingBoard) {
      Global.logger.d('checkAsrResult: 单词已答对/已评价，允许 ASR 结果继续处理以便用户练习跟读。');
    }

    final bool wasAlreadyCorrect = _hasFinishedAnswering;

    if (asr.state != AsrState.started &&
        asr.state != AsrState.initialized &&
        !isHandwritingOrKeyboard) {
      Global.logger.w('收到归属于旧会话的结果($inputText)，但当前无活跃输入途径，跳过处理');
      if (mounted) {
        if (asrInput == null) {
          _meaningController.text = '';
        }
        setState(() {
          _currentScore = null;
        });
      }
      return;
    }

    if (_studyStep == StudyStep.en2Ch.json ||
        _studyStep == StudyStep.ch2En.json) {
      if (_wordWrapper == null || _word == null) {
        Global.logger.w(
            'checkAsrResult: _wordWrapper 或 _word 为空，跳过处理。目前 _wordWrapper=${_wordWrapper != null}, _word=${_word != null}');
        return; // 在 _wordWrapper 加载完成前，不消耗此次 ASR 结果
      }
    }

    if (_studyStep == StudyStep.en2Ch.json) {
      // 额外检测：如果是正在进行拼写练习（打开了看板），则判定其英文拼写是否正确
      if (_showHandwritingBoard &&
          inputText.trim().toLowerCase() == _word!.spell.toLowerCase()) {
        if (asrInput != null) {
          _meaningController.text = _word!.spell;
        }
        _meaningFocusNode.unfocus();
        setState(() {
          _showHandwritingBoard = false;
        });
        SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.5, 0.2);
        return;
      }

      // 英→中：验证中文释义
      late MeaningMatchResult result;

      // 核心改动：如果当前输入框内容匹配上一刻 ASR 处理出的 processedResult，说明它是通过 ASR 触发的，
      // 此时我们使用记录下的 _currentAsrCandidates 列表进行多重探测。
      // 否则（如用户手动编辑键盘输入），我们只使用输入框当前文本。
      final isFromAsr =
          asrInput != null || _meaningController.text == _handlingChinese;
      final inputs = isFromAsr ? _currentAsrCandidates : [_handlingChinese];

      result = matchInputChineseWithMeaningItems(
        _wordWrapper!,
        inputs,
      );

      // 检查用户说出的正确释义数量是否达到要求
      final total = result.totalCount;
      final matched = result.matchedCount;
      if (_firstMatchTime == null && matched >= 1) {
        _firstMatchTime = DateTime.now();
      }
      bool isMatch = _isAsrPassSync(total, matched);
      _hasFinishedAnswering = wasAlreadyCorrect || isMatch;

      Global.logger.d(
          'BDC CHECK_ASR [en2Ch]: result(total=$total, matched=$matched, newMatchCount=${result.newMatchCount}), isMatch=$isMatch, _hasFinishedAnswering=$_hasFinishedAnswering, requires pass rule: $_asrPassRuleCache');

      // 如果本次有新增匹配，播放音效并设置状态 
      if (result.newMatchCount > 0) {
        setState(() {
          _canLeaveCurrWord = true;
        });

        // 核心修复：如果已完全答对（满足通过规则），在播放提示音前立即停止 ASR，释放音频通道以杜绝反馈音颤抖，并让UI层收到停止状态进而停止波浪动画。
        if (isMatch) {
          // 彻底停止当前识别会话
          await asr.stopAsr();

          if (asrInput != null) {
            _meaningController.text = _word!.spell;
          }

          if (!_autoJumpAfterCorrect) {
            Global.logger.d(
                'BDC [en2Ch]: 非极速模式，拼写正确，准备关闭沉浸式输入界面. _showHandwritingBoard=false, unfocusing');
            _meaningFocusNode.unfocus();
            setState(() {
              _showHandwritingBoard = false; // 立即关闭当前输入界面回到当前单词
            });
          }
          if (!wasAlreadyCorrect) {
            // 同步计算 FSRS 评分
            FsrsRating rating = FsrsRating.good; // 默认 Good
            int? rTime;
            if (_wordStartTime != null) {
              final timeToUse =
                  (_asrPassRuleCache == 'ALL' && _firstMatchTime != null)
                      ? _firstMatchTime!
                      : DateTime.now();
              final responseTime =
                  timeToUse.difference(_wordStartTime!).inSeconds;
              rTime = responseTime;
              if (asrInput == null) {
                // 键盘输入（打字）方式：给予较宽松的时间
                if (responseTime < 12) {
                  rating = FsrsRating.easy;
                } else if (responseTime >= 25) {
                  rating = FsrsRating.hard;
                }
              } else {
                // 语音输入：标准时间
                if (responseTime < 8) {
                  rating = FsrsRating.easy;
                } else if (responseTime >= 18) {
                  rating = FsrsRating.hard;
                }
              }
            }

            bool usedTranslation = _showSentenceTranslation;
            // 英中模式下提示中文字的惩罚极大约束：点2次直接 Again，点1次降两档！
            if (_hintTapCount >= 2 || usedTranslation) {
              rating = FsrsRating.again;
            } else if (_hintTapCount == 1) {
              if (rating == FsrsRating.easy) {
                rating = FsrsRating.hard;
              } else if (rating == FsrsRating.good) {
                rating = FsrsRating.again;
              } else if (rating == FsrsRating.hard) {
                rating = FsrsRating.again;
              }
            }

            String reason = "回答耗时${rTime ?? '-'}秒";
            if (usedTranslation) {
              reason += "，查看了例句翻译";
            } else if (_hintTapCount > 0) {
              reason += "，查看提示$_hintTapCount次";
            }
            reason += "，评分: ${rating.label}";

            _lastFsrsRatingReason = reason;
            _lastFsrsRating = rating;

            // 计算 FSRS 预览结果
            final lw = _currentGetWordResult?.learningWord;
            if (lw != null) {
              final fsrs = FSRS();
              _daysSinceLastReview = 0;
              if (lw.lastLearningDate != null) {
                final lastDate = DateTime(lw.lastLearningDate!.year,
                    lw.lastLearningDate!.month, lw.lastLearningDate!.day);
                final now = DateTime.now();
                final todayDate = DateTime(now.year, now.month, now.day);
                _daysSinceLastReview = todayDate.difference(lastDate).inDays;
              }
              if (lw.stability == null || lw.stability == 0.0) {
                _fsrsItem = fsrs.init(rating);
              } else {
                final prevItem = FSRSItem(
                  stability: lw.stability!,
                  difficulty: lw.difficulty!,
                  elapsedDays: _daysSinceLastReview ?? 0,
                  scheduledDays: lw.scheduledDays ?? 0,
                  reps: lw.reps ?? 0,
                  lapses: lw.lapses ?? 0,
                  state: FsrsStateExt.fromInt(lw.state),
                );
                _fsrsItem =
                    fsrs.next(prevItem, rating, _daysSinceLastReview ?? 0);
              }
            }

            // 同步展示所有释义
            if (!_autoJumpAfterCorrect && _wordWrapper != null) {
              final meaningItems = _wordWrapper!.word.getMergedMeaningItems();
              for (var i = 0; i < meaningItems.length; i++) {
                var parts = splitMeaning2Parts(meaningItems[i].meaning!);
                for (var j = 0; j < parts.length; j++) {
                  if (!_wordWrapper!.asrMatchedMeaningItemParts
                          .contains(Pair(i, j)) &&
                      !_wordWrapper!.asrRevealedMeaningItemParts
                          .contains(Pair(i, j))) {
                    _wordWrapper!.asrRevealedMeaningItemParts.add(Pair(i, j));
                  }
                }
              }
            }

            if (mounted) setState(() {});
          }
        }

        // 并发播放提示音，支持多个提示音同时播放，互不干扰
        // 将提示音 Future 添加到列表中，用于后续等待所有提示音播放完成

        if (PlatformUtils.isIOS && _hasFinishedAnswering) {
          await Future.delayed(const Duration(milliseconds: 150));
        }

        final soundFuture =
            SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.5, 0.2);
        _playingCorrectSounds.add(soundFuture);
        debugPrint(
            'checkAsrResult: 添加提示音到列表，当前有 ${_playingCorrectSounds.length} 个提示音正在播放');

        // 等待音频播放完成，然后再等待短暂延迟后执行后续逻辑
        soundFuture.whenComplete(() {
          Future.delayed(const Duration(milliseconds: 150)).then((_) async {
            _playingCorrectSounds.remove(soundFuture);
            if (_playingCorrectSounds.isEmpty && _hasFinishedAnswering) {
              if (wasAlreadyCorrect) return;

              if (_autoJumpAfterCorrect && _lastFsrsRating != null) {
                await getNextWord(true, fsrsRating: _lastFsrsRating!);
              }
            }
          });
        });
      }
    } else if (_studyStep == StudyStep.ch2En.json) {
      // 中→英：验证英文单词拼写
      String inputText =
          (asrInput ?? _meaningController.text).trim().toLowerCase();
      String correctSpell = _word!.spell.toLowerCase();

      // 判定通过条件：
      // 1. 精确拼写匹配（preprocessEnglish 已做过编辑距离/映射表救援）
      // 2. 音素相似度达到阈值（兜底同音词场景，如 mail vs male）
      bool isMatch = inputText == correctSpell;
      Global.logger.d(
          'BDC CHECK_ASR [ch2En]: inputText="$inputText", correctSpell="$correctSpell", basic_match=$isMatch, _currentScore=$_currentScore');
      if (!isMatch &&
          asrInput != null &&
          _currentScore != null &&
          _currentScore! >= Constants.phonemeMatchThreshold) {
        Global.logger.d(
            'Ch2En: 拼写不匹配("$inputText" != "$correctSpell")，但音素相似度($_currentScore)达到阈值(${Constants.phonemeMatchThreshold})，判定通过');
        isMatch = true;
      }

      if (isMatch) {
        Global.logger.d('BDC CHECK_ASR [ch2En]: Match SUCCESS!');
        if (asrInput != null) {
          _isUpdatingByHint = true;
          setState(() {
            _meaningController.text = _word!.spell;
            if (_wordWrapper != null) {
              _wordWrapper!.hintLetterCount = _word!.spell.length;
            }
          });
        }

        // 如果之前已经答对了，现在是在沉浸式面板里练习拼写，则仅处理 UI 关闭与音效
        if (wasAlreadyCorrect) {
          if (_showHandwritingBoard) {
            _meaningFocusNode.unfocus();
            setState(() {
              _showHandwritingBoard = false;
            });
          }
          SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.5, 0.2);
          return;
        }

        _hasFinishedAnswering = true;

        // 计算 FSRS 评分
        FsrsRating rating = FsrsRating.good; // 默认 Good
        int? rTime;
        if (_wordStartTime != null) {
          final responseTime =
              DateTime.now().difference(_wordStartTime!).inSeconds;
          rTime = responseTime;

          if (asrInput == null) {
            // 键盘拼写模式：因为打字慢，所以给予非常宽松的时间
            if (responseTime < 15) {
              rating = FsrsRating.easy;
            } else if (responseTime >= 35) {
              rating = FsrsRating.hard;
            }
          } else {
            // 语音识别模式：标准时间
            if (responseTime < 6 &&
                (_currentScore == null || _currentScore! >= 90)) {
              rating = FsrsRating.easy; // Easy
            } else if (responseTime >= 15) {
              rating = FsrsRating.hard; // Hard
            }
          }
        }

        bool usedTranslation = _showSentenceTranslation;
        // 如果点击提示次数 >= 2 (包括长按的 Full Hint) 或看了翻译，直接视为不会 (Again)
        // 如果只有 1 次，则原基础上下降一档
        if (_hintTapCount >= 2 || usedTranslation) {
          rating = FsrsRating.again;
        } else if (_hintTapCount == 1) {
          if (rating == FsrsRating.easy) {
            rating = FsrsRating.good;
          } else if (rating == FsrsRating.good) {
            rating = FsrsRating.hard;
          } else if (rating == FsrsRating.hard) {
            rating = FsrsRating.again;
          }
        }

        String reason = "回答耗时${rTime ?? '-'}秒";
        if (usedTranslation) {
          reason += "，查看了例句翻译";
        } else if (_hintTapCount > 0) {
          reason += "，查看提示$_hintTapCount次";
        }
        reason += "，评分: ${rating.label}";

        _lastFsrsRatingReason = reason;

        // 在调用 _onAnswerCorrect 前彻底停止当前识别会话，以便让UI层收到停止状态进而停止波浪动画。
        await asr.stopAsr();
        _onAnswerCorrect(rating);
      }
    }
  }

  bool _isAsrPassSync(int totalParts, int matchedParts) {
    Global.logger.d(
        '_isAsrPass: asrPassRule=$_asrPassRuleCache, totalParts=$totalParts, matchedParts=$matchedParts');

    bool result;
    switch (_asrPassRuleCache) {
      case 'ALL':
        result = matchedParts >= totalParts && totalParts > 0;
        break;
      case 'HALF':
        result = matchedParts >= ((totalParts + 1) >> 1);
        break;
      case 'ONE':
      default:
        result = matchedParts >= 1;
        break;
    }
    Global.logger.d('_isAsrPassSync result: $result');
    return result;
  }

  Future<void> loadData() async {
    try {
      // 获取5个展示单词
      List<String> displayWords = [];
      try {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getLastLoggedInUser();
        if (user != null) {
          final query = db.select(db.learningWords)
            ..where((tbl) => tbl.userId.equals(user.id) & tbl.batchId.isBiggerThanValue(0));
          final todayWords = await query.get();
          
          var newWords = todayWords.where((w) => w.state == 0).toList();
          var reviewWords = todayWords.where((w) => w.state != 0).toList();
          
          newWords.shuffle();
          reviewWords.shuffle();
          
          var selectedWords = [];
          selectedWords.addAll(newWords.take(5));
          if (selectedWords.length < 5) {
            selectedWords.addAll(reviewWords.take(5 - selectedWords.length));
          }
          
          for (var w in selectedWords) {
            final wordItem = await db.wordsDao.getWordById(w.wordId);
            if (wordItem != null && wordItem.spell.isNotEmpty) {
              displayWords.add(wordItem.spell);
            }
          }
        }
      } catch (e) {
        Global.logger.e('获取展示单词失败: $e');
      }

      // 在下一帧显示初始化反馈的提示框
      BuildContext? dialogContext;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            dialogContext = ctx;
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final textColor = isDark ? Colors.white : Colors.black87;
            
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (displayWords.isNotEmpty) ...[

                      const SizedBox(height: 24),
                      // 错落有致的展示
                      ...displayWords.asMap().entries.map((entry) {
                        int idx = entry.key;
                        String word = entry.value;
                        // 为了艺术排版，单词交错且字体大小不同
                        Alignment align = Alignment.center;
                        if (idx % 2 == 1) align = Alignment.centerLeft;
                        if (idx % 2 == 0 && idx != 0) align = Alignment.centerRight;
                        if (idx == 0 || idx == 4) align = Alignment.center;
                        
                        double fontSize = 32.0;
                        if (idx == 0) fontSize = 38.0;
                        if (idx == 4) fontSize = 28.0;

                        return Container(
                          alignment: align,
                          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          child: Text(
                            word,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              color: textColor.withValues(alpha: 1.0 - (idx * 0.15)),
                              shadows: [
                                Shadow(
                                  offset: const Offset(1, 1),
                                  blurRadius: 2,
                                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 32),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            "正在初始化语音识别引擎...",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      });

      // 预加载语音识别模型（耗时操作）
      await asr.preloadModels();

      // 如果模型加载完成且弹窗还在，或者 dialogContext 已赋值，将其关闭
      // 等待一个极短的时间，确保 postFrameCallback 执行并且 dialog 已经弹出
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      if (dialogContext != null) {
        // ignore: use_build_context_synchronously
        Navigator.of(dialogContext!).pop();
      } else {
        // 若上面因为某些原因 dialogContext 还未赋值但 dialog 被弹出了
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (dialogContext != null) {
            Navigator.of(dialogContext!).pop();
          } else if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
      }

      // 保证音频会话配置已完成
      await SoundUtil.configureAudioSession();

      MyDatabase.instance.localParamsDao.getIsDarkMode().then((value) {
        if (mounted) {
          setState(() {
            _isDarkMode = value;
          });
        }
      });

      final studyConfig = StudyConfig.fromCurrentUser();
      // _asrPassRuleCache = studyConfig.asrPassRule; // This will be an int (0-100)
      if (mounted) {
        _asrPassRuleCache = studyConfig.asrPassRule;
      }
      setState(() {
        // _isDarkMode = isDarkMode; // This line is now handled by the .then() block above
        // final studyConfig = StudyConfig.fromCurrentUser(); // Already defined above
        _autoJumpAfterCorrectCh2En = studyConfig.autoJumpAfterCorrectCh2En;
        _autoJumpAfterCorrectEn2Ch = studyConfig.autoJumpAfterCorrectEn2Ch;
      });

      // 获取用户的学习步骤配置（已激活的学习步骤)
      var stepsResult = await StudyBo().getActiveUserStudySteps();
      if (!stepsResult.success || stepsResult.data == null) {
        Global.logger.e(
            'loadData: 获取激活学习步骤失败: code=${stepsResult.code}, msg=${stepsResult.msg}');
        ToastUtil.error(stepsResult.msg ?? '获取学习步骤失败');
        return;
      }
      activeUserStudySteps = stepsResult.data!;

      Global.logger.d('开始加载单词数据...');
      await getNextWord(false);
      if (_currentGetWordResult == null) {
        Global.logger
            .e('loadData: _currentGetWordResult is null after getNextWord');
        ToastUtil.error('获取单词失败');
        return;
      }
      if (_currentGetWordResult!.finished || _currentGetWordResult!.noWord) {
        return;
      }
    } catch (e, stackTrace) {
      Global.logger.e('loadData: 发生未捕获异常', error: e, stackTrace: stackTrace);
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'loadData');
    }
  }

  /// 播放句子发音按钮处理函数
  Future<void> playFirstSentence() async {
    if (_englishDigestOfFirstSentence != null && !_audioPlayerDisposed) {
      try {
        await SoundUtil.playSentenceSound2(
            _englishDigestOfFirstSentence!, _audioPlayer);
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace,
            logPrefix: '播放例句失败', showToast: false);
      }
    }
  }

  getNextWord(bool gotoNext, {FsrsRating? fsrsRating}) async {
    try {
      // 停止当前 ASR 任务并确保状态同步（Hot Stop 会在 Native 层处理，此处需保证状态为 Stopped）
      await asr.stopAsr();
      _meaningFocusNode.unfocus();
      _showHandwritingBoard = false;
      _meaningController.text = '';
      _handlingChinese = '';
      _currentAsrCandidates = [];
      _firstMatchTime = null;
      _hintTapCount = 0;
      _highlightedWordImg = null;
      _wordImageEdited = false;

      //如果是从批次单词列表跳转来的，则第一次从服务端取单词时，通知服务端进入下一个学习批次
      bool isFromBatchWordList = false;
      if (_args.fromPage != null && _args.fromPage == 'batch_word_list') {
        isFromBatchWordList = true;
        // 立即清除标记，通过参数传递给 handleWord
        _args.fromPage = null;
        await GetStorage().write("BdcPageArgs", _args.toJson());
      }

      // 循环读取，直到获取到非“已掌握”单词（如果是 gotoNext=true，服务端可能会自动跳过已掌握词，但前端也要防御）
      int triedCount = 0;
      while (true) {
        bool actualGotoNext = triedCount == 0 ? gotoNext : true;
        final result = await StudyBo()
            .getWord(_isWordMastered, actualGotoNext, fsrsRating: fsrsRating);
        triedCount++;

        if (!result.success) {
          if (result.code == 'NEW_DAY') {
            if (!mounted) return;
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('新的一天'),
                content: const Text('已进入新的一天，将开始新的学习。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            Get.offAllNamed('/index', arguments: IndexPageArgs(0));
            return;
          }
          Global.logger.e(
              'getNextWord: 获取单词结果失败: code=${result.code}, msg=${result.msg}');
          ToastUtil.error(result.msg ?? '获取单词失败');
          return;
        }

        _currentGetWordResult = result.data;
        if (_currentGetWordResult == null) break;

        // 如果单词已掌握，重置状态并继续获取下一个单词
        if (_currentGetWordResult!.wordMastered) {
          _isWordMastered = false;
          fsrsRating = null; // 后续跳词不需要评分
          continue;
        }
        break;
      }

      handleWord(_currentGetWordResult,
          isFromBatchWordList: isFromBatchWordList);
    } catch (e, stackTrace) {
      Global.logger.e('获取下一个单词时发生异常', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
        // 显示错误提示，并提供重试按钮
        _showErrorWidget('加载单词失败: ${e.toString()}');
      }
    }
  }

  /// 显示错误提示界面，提供重试和返回选项
  void _showErrorWidget(String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400]),
            const SizedBox(width: 8),
            const Text('出错了'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMessage),
              const SizedBox(height: 8),
              const Text(
                '您可以尝试重新加载或返回上一页。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('返回'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                dataLoaded = false;
              });
              // 重新加载当前单词
              getNextWord(false);
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 播放单词和第一个例句
  Future<void> playWordAndFirstSentence(
      UserVo user, bool forcePlayWord, bool startAsrWhenFinish) async {
    // 等待所有提示音播放完成，避免与单词发音重叠
    // 使用列表快照，避免在等待过程中列表被修改
    final soundsToWait = List<Future<void>>.from(_playingCorrectSounds);
    if (soundsToWait.isNotEmpty) {
      await Future.wait(soundsToWait);
    }

    // 保存当前的 studyStep 和 word，用于在 finally 块中检查是否已经改变
    final savedStudyStep = _studyStep;
    final savedWordId = _word?.id;

    // 判断是否真的有音频要播，如果什么都不播（比如中英模式），需要给 finally 知道直接启动 ASR
    final studyConfig = StudyConfig.fromCurrentUser();
    bool willPlayWord = _studyStep == StudyStep.en2Ch.json &&
        (studyConfig.autoPlayWord || forcePlayWord);
    bool willPlaySentence =
        _studyStep == StudyStep.en2Ch.json && studyConfig.autoPlaySentence;

    // 如果不需要播放音频，为了保证流程顺畅且不受到 await ASR.stopAsr() 的延迟影响
    // 直接进入 finally 块的判断，快速拉起 ASR
    if (!willPlayWord && !willPlaySentence) {
      Global.logger.d('BDC: 由于无需播放音频，继续走到 finally 快速启动 ASR');
    } else {
      // 需要播放的话，确保停止 ASR 任务（Hot Stop）
      await asr.stopAsr();
    }

    try {
      // 在英→中模式下，播放单词发音
      if (willPlayWord) {
        await SoundUtil.playPronounceSound2(_word!, _audioPlayer);
      }
      // 在英→中模式下，播放例句发音
      if (willPlaySentence) {
        await playFirstSentence();
      }
    } finally {
      // 播音结束后，如果当前在"说"tab且键盘未弹出，则统一交给 _handleTabChangeForAsr 控制ASR启动
      // 注意：检查 studyStep 和 word 是否已经改变，如果改变了说明有新的单词加载，就不应该启动ASR
      if (!PlatformUtils.isWeb && _isInSpeakTab && !_isKeyboardVisible) {
        // 检查 studyStep 和 word 是否还是原来的值
        if (savedStudyStep == _studyStep && savedWordId == _word?.id) {
          Global.logger.d(
              'BDC: playWordAndFirstSentence 播放完成，准备启动ASR (studyStep=$_studyStep, wordId=${_word?.id})');
          _handleTabChangeForAsr();
        } else {
          Global.logger.d(
              'BDC: playWordAndFirstSentence 播放完成，但单词已改变，跳过ASR启动 (savedStudyStep=$savedStudyStep => studyStep=$_studyStep, savedWordId=$savedWordId => wordId=${_word?.id})');
        }
      } else {
        Global.logger.d(
            'BDC: playWordAndFirstSentence 播放完成，但跳过ASR启动 (isInSpeakTab=$_isInSpeakTab, isKeyboardVisible=$_isKeyboardVisible)');
      }
    }
  }

  void handleWord(final GetWordResult? getWordResult,
      {bool isFromBatchWordList = false}) async {
    // 异步拉取最新 ASR 规则并缓存，避免后续同步处理挂起
    final config = StudyConfig.fromCurrentUser();
    _asrPassRuleCache = config.asrPassRule;

    setState(() {
      _fsrsItem = null;
      _lastFsrsRating = null;
    });

    try {
      if (getWordResult == null) {
        Global.logger.d('getWordResult 为空');
        ToastUtil.error('获取单词失败');
        return;
      }

      if (getWordResult.finished) {
        Navigator.pop(context);
        Get.toNamed("/finish");
        return;
      } else if (getWordResult.noWord) {
        Global.logger.d('getWordResult.noWord为true,跳转到选择词书页面');
        Get.toNamed("/select_book");
        return;
      }

      // 检查当前学习模式是否超出范围
      if (getWordResult.stepIndex >= activeUserStudySteps.length) {
        Global.logger.d('无效的学习模式: ${getWordResult.stepIndex}');
        ToastUtil.error('学习模式配置错误');
        return;
      }

      // 获取当前学习步骤
      final currentStep =
          activeUserStudySteps[getWordResult.stepIndex].studyStep;

      // 如果当前学习步骤是列表模式，显示单词列表
      if (currentStep == 'List') {
        var nextWordBtn = ElevatedButton.icon(
          icon:
              const Icon(Icons.navigate_next, size: 24.0, color: Colors.white),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          label: const Text('继续'),
          onPressed: () async {
            Get.back(result: true);
            // 给 UI 一个缓冲时间，确保列表页面完全关闭并清理 ASR 状态后再进入下一步
            await Future.delayed(const Duration(milliseconds: 100));

            // 完成当前批次列表学习
            await StudyBo().completeListStepForCurrentBatch();
            _args.fromPage = 'batch_word_list';
            await GetStorage().write("BdcPageArgs", _args.toJson());
            await getNextWord(false);
          },
        );
        // 在获取下一个单词前，停止 ASR 任务（Hot Stop）
        await asr.stopAsr();
        await asr.reset();
        if (!mounted) return;
        final wasMounted = mounted;
        if (!wasMounted) return;
        toBatchWordsListPage('单词列表', true, nextWordBtn, context)
            ?.then((result) async {
          if (!mounted) return;
          if (result == null) {
            Navigator.pop(context);
          }
        });
        return;
      }

      _isWordMastered = false;

      String? oldStudyStep = _studyStep;
      _studyStep = activeUserStudySteps[getWordResult.stepIndex].studyStep;

      // 极端防御：如果在渲染新单词时 ASR 状态依然是 started（通常是异步时序导致），强制同步一次状态
      // 确保 _handleTabChangeForAsr 能够触发新的 _startAsr() 而不是认为已经启动
      if (asr.state == AsrState.started && oldStudyStep == _studyStep) {
        Global.logger.w('BDC: 检测到 ASR 残留状态，准备通过 stopAsr 确保下一环节能正常启动');
        await asr.stopAsr();
      }

      // 只有在模式真正改变时，才重新初始化 ASR（防止在相同模式下刷新导致 ASR 意外停止）
      // 注意：getNextWord 已经执行过 stopAsr + reset，此处无需重复，否则会触发额外的
      // iOS Audio Engine tear-down，产生听感噪音。
      if (oldStudyStep == null || oldStudyStep != _studyStep) {
        Global.logger.i('BDC: 学习模式从 $oldStudyStep 切换到 $_studyStep，初始化 ASR 监听');
        await asr.initAsr(onAsrResult);

        // 临时禁用侵入式的 microphone pre-warm，因为它会与后续即时的 startAsr 产生竞争并打断音频流程
        // if (_shouldShowSpeakTab) {
        //   unawaited(asr.startMicrophone());
        // }
      }

      // 重新初始化TabController以适应动态tabs
      _reinitializeTabController();

      if (getWordResult.learningWord?.word == null) {
        Global.logger.e(
            '处理单词失败：获取到的单词数据中 learningWord.word 为空。 stepIndex=${getWordResult.stepIndex}, finished=${getWordResult.finished}');
        ToastUtil.error('单词数据加载错误');
        return;
      }
      _word = getWordResult.learningWord!.word;
      _canLeaveCurrWord = false;
      _hasFinishedAnswering = false;
      _selectedAnswerIndex = null;
      _flippedAnswerIndices.clear();
      _showSentenceTranslation = false;
      _isUpdatingByHint = false;
      _currentScore = null; // 重置发音评分，防止携带上一个单词的分数

      // 如果仅返回了ID，则本地补全单词详情与释义
      if (_word != null && (_word!.spell.isEmpty)) {
        try {
          final db = MyDatabase.instance;
          final local = await db.wordsDao.getWordById(_word!.id!);
          if (local != null) {
            _word!
              ..spell = local.spell
              ..shortDesc = local.shortDesc
              ..longDesc = local.longDesc
              ..pronounce = local.pronounce
              ..americaPronounce = local.americaPronounce
              ..britishPronounce = local.britishPronounce
              ..popularity = local.popularity;
          }
          final user = Global.getLoggedInUser();
          if (user != null) {
            final mis =
                await WordBo().getMeaningItemsForWord(_word!.id!, user.id);
            _word!.meaningItems = mis;
          }

          // 本地加载单词配图，填充到 currentGetWordResult.images
          try {
            final imgsQuery = db.select(db.wordImages)
              ..where((tbl) => tbl.wordId.equals(_word!.id!));
            final imgs = await imgsQuery.get();
            final imageVos = <WordImageVo>[];
            for (final img in imgs) {
              final author = await db.usersDao.getUserById(img.authorId);
              // WordImageVo 需要非空作者，这里用占位作者避免空指针
              UserVo authorVo = UserVo.c2(author?.id ?? '0')
                ..nickName = (author?.nickName ?? '');
              imageVos.add(WordImageVo(
                img.id,
                img.imageFile,
                img.hand,
                img.foot,
                authorVo,
              ));
            }
            _currentGetWordResult?.images = imageVos;
          } catch (e) {
            Global.logger.w('本地加载单词图片失败', error: e);
          }
        } catch (e) {
          Global.logger.w('本地补全单词失败', error: e);
        }
      }
      _wordWrapper = WordWrapper(_word!, null);

      // 渲染第一个例句
      _englishDigestOfFirstSentence = null; // 先设置为 null
      final allSentences = await _word!.getSentences();
      if (allSentences.isNotEmpty) {
        _englishDigestOfFirstSentence = allSentences[0].englishDigest;
      }

      var user = Global.getLoggedInUserNotNull();

      if (_studyStep == StudyStep.en2Ch.json) {
        playWordAndFirstSentence(await user.toUserVo(), false, false);
      } else if (_studyStep == StudyStep.ch2En.json) {
        playWordAndFirstSentence(await user.toUserVo(), true, false);
      }
      _initChoiceData(getWordResult, user);
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '处理单词');
      ToastUtil.error('处理单词时出错');
      // 异常时也要设置 dataLoaded，避免白屏
      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
        // 显示错误提示，让用户可以选择重试或返回
        _showErrorWidget('处理单词时出错: ${e.toString()}');
      }
      return;
    }

    _showAnswerButtons = StudyConfig.fromCurrentUser().showAnswersDirectly;

    setState(() {
      dataLoaded = true;
      // 只有在不在"说"tab时才直接启动计时（"说"tab会等 ASR 准备好以后再启动计时）
      if (!_isInSpeakTab) {
        _wordStartTime = DateTime.now();
      }
    });

    // 自动获取焦点，提升输入效率
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasFinishedAnswering) {
        _meaningFocusNode.requestFocus();
      }
    });

    // 如果在数据加载期间（如等待数据库查询）已经有语音结果提前到达，手动触发一次校验
    if (_meaningController.text.isNotEmpty && _handlingChinese.isEmpty) {
      Global.logger.i('BDC: 单词加载完成，发现加载期间缓存的语音结果，主动触发校验');
      checkAsrResult();
    }
  }

  /// 初始化选择题数据
  void _initChoiceData(GetWordResult getWordResult, User user) {
    try {
      if (_studyStep == StudyStep.en2Ch.json ||
          _studyStep == StudyStep.ch2En.json) {
        // 把当前单词及混淆单词放入数组，并随机打乱
        if (getWordResult.otherWords == null ||
            getWordResult.otherWords!.length < 2) {
          final actualLength = getWordResult.otherWords?.length ?? 0;
          Global.logger.e('混淆单词数量（$actualLength）不足');
          ToastUtil.error('混淆单词数量（$actualLength）不足，请稍后重试');
          return;
        }

        _words = <WordVo>[];
        _words!.add(_word!);
        _words!.add(getWordResult.otherWords![0]);
        _words!.add(getWordResult.otherWords![1]);
        _words!.shuffle();

        // 在打乱的单词数组中找到正确的（当前学习的）
        for (var i = 0; i < _words!.length; i++) {
          if (_words![i] == _word) {
            _correctAnswerIndex = i + 1;
            break;
          }
        }

        if (StudyConfig.fromCurrentUser().enableAllWrong) {
          // 备选答案中含[都不对]
          // 随机选择一个单词索引号（1～3），从数组中删除该单词
          var rnd = Random();
          var indexToDelete = 1 + rnd.nextInt(3 - 1);
          _words!.removeAt(indexToDelete - 1);

          // 添加[都不对]选项
          var mockWord = WordVo.c2("[ 都不对 ]");
          mockWord.setMeaningStr("[ 都不对 ]");
          _words!.add(mockWord);

          if (indexToDelete == _correctAnswerIndex) {
            // 恰好删除了正确的单词，此时[都不对]应成为正确答案
            _correctAnswerIndex = 3;
          } else {
            // 在调整过的单词数组中重新找到正确的（当前学习的）
            for (var i = 0; i < _words!.length; i++) {
              if (_words![i] == _word) {
                _correctAnswerIndex = i + 1;
                break;
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      Global.logger.e('初始化选择题数据时发生异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('初始化选择题失败，请稍后重试');
    }
  }

  final email = TextEditingController();
  Widget _buildSettingItem(String title, bool value, Function(bool) onChanged,
      {Widget? customTrailing, String? subtitle}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      dense: true,
      title: Text(
        title,
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontFamily: "NotoSansSC",
                fontSize: 12,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.6),
              ),
            )
          : null,
      trailing: customTrailing ??
          Transform.scale(
            scale: 0.5,
            alignment: Alignment.centerRight,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: Global.highlight,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      onTap: () {
        if (customTrailing == null) {
          onChanged(!value);
        }
      },
    );
  }

  Widget _buildAsrPassRuleSelector(
      String currentValue, Function(String) onChanged) {
    const Map<String, String> options = {
      'ONE': '说出一个意思即可',
      'HALF': '说出半数意思',
      'ALL': '说出全部意思',
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      dense: true,
      title: Text(
        '语音识别通过规则',
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        options[currentValue] ?? '说出一个意思即可',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 12,
          color: Theme.of(context)
              .textTheme
              .bodySmall
              ?.color
              ?.withValues(alpha: 0.6),
        ),
      ),
      trailing: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: onChanged,
        itemBuilder: (BuildContext context) {
          return options.entries.map((entry) {
            return PopupMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                style: const TextStyle(
                  fontFamily: "NotoSansSC",
                  fontSize: 13,
                ),
              ),
            );
          }).toList();
        },
        child: SizedBox(
          width: 48,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              Icons.arrow_drop_down,
              color: Global.highlight,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showSettingDlg() async {
    // 在StatefulBuilder外部初始化本地状态
    var currentUser = Global.getLoggedInUser();
    var studyConfig = StudyConfig.fromCurrentUser();
    var localAutoPlayWord = studyConfig.autoPlayWord;
    var localAutoPlaySentence = studyConfig.autoPlaySentence;
    var localShowAnswersDirectly = studyConfig.showAnswersDirectly;
    var localEnableAllWrong = studyConfig.enableAllWrong;
    var localAsrPassRule = studyConfig.asrPassRule;
    var localAutoJumpAfterCorrectCh2En = studyConfig.autoJumpAfterCorrectCh2En;
    var localAutoJumpAfterCorrectEn2Ch = studyConfig.autoJumpAfterCorrectEn2Ch;

    if (!mounted) return;

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Global.highlight.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      color: Global.highlight,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '学习设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Global.highlight,
                        fontFamily: "NotoSansSC",
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: min(MediaQuery.of(context).size.width * 0.92, 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFF9F9F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                width: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final List<Widget> items = [
                                _buildSettingItem(
                                  '深色模式',
                                  _isDarkMode,
                                  (value) {
                                    setState(() {
                                      _isDarkMode = value;
                                    });
                                    MyDatabase.instance.localParamsDao
                                        .saveIsDarkMode(value);
                                    context
                                        .read<DarkMode>()
                                        .setIsDarkMode(value);
                                  },
                                  customTrailing: Transform.translate(
                                    offset: const Offset(20, 0),
                                    child: Transform.scale(
                                      scale: 1.8,
                                      alignment: Alignment.centerRight,
                                      child: DayNightSwitcherIcon(
                                        isDarkModeEnabled: _isDarkMode,
                                        onStateChanged: (isDarkModeEnabled) {
                                          setState(() {
                                            _isDarkMode = isDarkModeEnabled;
                                          });
                                          MyDatabase.instance.localParamsDao
                                              .saveIsDarkMode(
                                                  isDarkModeEnabled);
                                          context
                                              .read<DarkMode>()
                                              .setIsDarkMode(isDarkModeEnabled);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                _buildAsrPassRuleSelector(
                                  localAsrPassRule,
                                  (value) {
                                    setState(() {
                                      localAsrPassRule = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '自动播放单词发音',
                                  localAutoPlayWord,
                                  (value) {
                                    setState(() {
                                      localAutoPlayWord = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '自动播放例句',
                                  localAutoPlaySentence,
                                  (value) {
                                    setState(() {
                                      localAutoPlaySentence = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '直接显示备选答案',
                                  localShowAnswersDirectly,
                                  (value) {
                                    setState(() {
                                      localShowAnswersDirectly = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '备选答案含[都不对]选项',
                                  localEnableAllWrong,
                                  (value) {
                                    setState(() {
                                      localEnableAllWrong = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '答对自动跳转(中英极速模式)',
                                  localAutoJumpAfterCorrectCh2En,
                                  (value) {
                                    setState(() {
                                      localAutoJumpAfterCorrectCh2En = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '答对自动跳转(英中极速模式)',
                                  localAutoJumpAfterCorrectEn2Ch,
                                  (value) {
                                    setState(() {
                                      localAutoJumpAfterCorrectEn2Ch = value;
                                    });
                                  },
                                ),
                              ];

                              return Column(
                                children: [
                                  for (int i = 0; i < items.length; i++) ...[
                                    if (i > 0)
                                      Divider(
                                        height: 1,
                                        thickness: 0.5,
                                        indent: 16,
                                        endIndent: 16,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                                .withValues(alpha: 0.08)
                                            : Colors.grey
                                                .withValues(alpha: 0.2),
                                      ),
                                    items[i],
                                  ]
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 88,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: const Text('取消',
                            style: TextStyle(
                                fontSize: 13, fontFamily: "NotoSansSC")),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 88,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Global.highlight,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          // 保存所有设置
                          if (currentUser != null) {
                            var studyConfigToSave =
                                StudyConfig.fromCurrentUser();
                            studyConfigToSave.autoPlayWord = localAutoPlayWord;
                            studyConfigToSave.autoPlaySentence =
                                localAutoPlaySentence;
                            studyConfigToSave.showAnswersDirectly =
                                localShowAnswersDirectly;
                            studyConfigToSave.enableAllWrong =
                                localEnableAllWrong;
                            studyConfigToSave.autoJumpAfterCorrectCh2En =
                                localAutoJumpAfterCorrectCh2En;
                            studyConfigToSave.autoJumpAfterCorrectEn2Ch =
                                localAutoJumpAfterCorrectEn2Ch;
                            studyConfigToSave.asrPassRule = localAsrPassRule;
                            await studyConfigToSave.saveToCurrentUser();
                          }

                          // 在异步操作后检查context是否仍然有效
                          if (context.mounted) {
                            _asrPassRuleCache = localAsrPassRule;
                            _autoJumpAfterCorrectCh2En =
                                localAutoJumpAfterCorrectCh2En;
                            _autoJumpAfterCorrectEn2Ch =
                                localAutoJumpAfterCorrectEn2Ch;
                            Navigator.pop(context, true);
                          }
                        },
                        child: const Text('确定',
                            style: TextStyle(
                                fontSize: 13,
                                fontFamily: "NotoSansSC",
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          });
        });

    if (choice ?? false) {
      // 设置已在确定按钮中保存，这里刷新界面
      try {
        // 刷新界面，以体现最新配置
        await asr.stopAsr();
        handleWord(_currentGetWordResult);
      } catch (e) {
        ToastUtil.error('刷新界面失败: $e');
      }
    }
  }

  Future<void> showErrorReportDlg() async {
    errorReportController.text = '';
    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            final isDark = context.watch<DarkMode>().isDarkMode;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Global.highlight.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.report_problem_outlined,
                        color: Global.highlight, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '问题反馈',
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        fontFamily: "NotoSansSC",
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Global.highlight,
                      ),
                    ),
                  ],
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请输入单词(${_word!.spell})的报错内容',
                        textScaler: const TextScaler.linear(1.0),
                        style: const TextStyle(
                          fontFamily: "NotoSansSC",
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1F2430)
                              : const Color(0xFFF7FAFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TextField(
                            controller: errorReportController,
                            minLines: 4,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              hintText: '请尽量描述具体问题，方便我们快速修复',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    '取消',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(fontFamily: "NotoSansSC"),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Global.highlight,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    '提交',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(fontFamily: "NotoSansSC"),
                  ),
                ),
              ],
            );
          });
        });

    if (choice ?? false) {
      var result = await UserBo()
          .saveErrorReport(_word!.spell, errorReportController.text);
      if (result.success) {
        ToastUtil.info('报错成功！感谢你付出宝贵时间');
      } else {
        ToastUtil.error((result.msg!));
      }
    }
  }

  Widget renderPage() {
    if (_word == null) {
      return Container();
    }

    if (_showHandwritingBoard || _meaningFocusNode.hasFocus) {
      return _buildFullscreenImmersiveInputMode();
    }

    return Column(
      children: [
        Expanded(
          child: _buildMainContent(),
        ),
        _buildBottomButtons(),
      ],
    );
  }

  /// 构建全屏沉浸式输入模式（支持手写和键盘）
  Widget _buildFullscreenImmersiveInputMode() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    // 获取合并后的所有释义项
    final meaningItems = _word?.getMergedMeaningItems() ?? [];
    final combinedMeaning = meaningItems
        .map((m) => "${m.ciXing ?? ''} ${m.meaning ?? ''}")
        .join("; ");

    return Container(
      color: isDarkMode ? const Color(0xFF121212) : Colors.white,
      child: Column(
        children: [
          // 顶部显示一行中文释义
          Container(
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '请拼写单词：',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      Text(
                        combinedMeaning,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _autoJumpAfterCorrect ? Icons.bolt : Icons.bolt_outlined,
                    color: _autoJumpAfterCorrect
                        ? Colors.amber
                        : (isDarkMode ? Colors.white38 : Colors.black38),
                    size: 20,
                  ),
                  tooltip:
                      _autoJumpAfterCorrect ? '极速模式：答对自动下个词' : '极速模式：答对停在当前词',
                  onPressed: () async {
                    setState(() {
                      _autoJumpAfterCorrect = !_autoJumpAfterCorrect;
                    });
                    if (_studyStep == StudyStep.ch2En.json) {
                      var config = StudyConfig.fromCurrentUser();
                      config.autoJumpAfterCorrectCh2En = _autoJumpAfterCorrect;
                      await config.saveToCurrentUser();
                    } else {
                      var config = StudyConfig.fromCurrentUser();
                      config.autoJumpAfterCorrectEn2Ch = _autoJumpAfterCorrect;
                      await config.saveToCurrentUser();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _meaningFocusNode.unfocus();
                    setState(() {
                      _showHandwritingBoard = false;
                    });
                  },
                ),
              ],
            ),
          ),
          // 全屏输入区：打字与手写结合
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  // 1. 手写板区域
                  Expanded(
                    child: HandwritingBoard(
                      showCloseButton: false,
                      onRecognized: (text) {
                        _isUpdatingByHint = false;
                        setState(() {
                          _meaningController.text = text;
                        });
                        checkAsrResult();
                      },
                      onCancel: () {
                        _meaningFocusNode.unfocus();
                        setState(() {
                          _showHandwritingBoard = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 2. 打字输入框
                  Container(
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _meaningFocusNode.hasFocus
                            ? AppTheme.primaryColor.withValues(alpha: 0.3)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _meaningController,
                      focusNode: _meaningFocusNode,
                      autofocus: true,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        // 移除这里的动态颜色设定，由 Controller 内部控制
                      ),
                      decoration: InputDecoration(
                        hintText: '在此键入单词...',
                        hintStyle: TextStyle(
                          fontSize: 32,
                          color: (isDarkMode ? Colors.white : Colors.black)
                              .withValues(alpha: 0.2),
                          fontWeight: FontWeight.normal,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        _isUpdatingByHint = false;
                        setState(() {});
                        if (value.isNotEmpty && _word?.spell != null) {
                          if (Util.equalsIgnoreCase(value, _word!.spell)) {
                            checkAsrResult();
                          }
                        }
                      },
                      onSubmitted: (value) {
                        _meaningFocusNode.unfocus();
                        checkAsrResult();
                      },
                    ),
                  ),
                  // 底部提示
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '支持键盘输入与手写混合使用',
                      style: TextStyle(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.24)
                            : Colors.black.withValues(alpha: 0.24),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建题目内容区域
  Widget _buildQuestionContent() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.zero,
          topRight: Radius.zero,
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: _showBorders
            ? Border.all(
                color: const Color.fromARGB(255, 11, 118, 3),
                width: 10,
              )
            : null,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            leftPadding,
            0,
            rightPadding,
            max(
                kTextTabBarHeight + 6.0,
                MediaQuery.of(context).viewPadding.bottom +
                    kTextTabBarHeight)), // 预留底部TabBar空间，避免遮挡
        child: Column(
          children: [
            // 英→中模式整合卡片
            if (_studyStep == StudyStep.en2Ch.json &&
                _currentGetWordResult?.learningWord?.word != null)
              _buildWordStepCard(),
            // 中→英模式整合卡片
            if (_studyStep == StudyStep.ch2En.json &&
                _currentGetWordResult?.learningWord?.word != null)
              _buildMeaningStepCard(),

            _buildPhoneticRow(),
            _buildFirstSentenceRow(),
          ],
        ),
      ),
    );
  }

  /// 构建浮动的TabBar
  Widget _buildFloatingTabBar() {
    // 确保 TabController 的长度与 tabs 数量匹配
    // 如果 TabController 未初始化或其长度与 tabs 数量不匹配，则重新初始化
    final currentTabsLength = _dynamicTabs.length;
    if (_tabController == null || _tabController!.length != currentTabsLength) {
      // 如果 TabController 还未初始化或长度不匹配，立即重新初始化
      _reinitializeTabController();
      // 如果重新初始化后仍然为 null（理论上不应该发生），返回空 widget
      if (_tabController == null) {
        return const SizedBox.shrink();
      }
    }

    return Positioned(
      bottom: 0,
      left: leftPadding,
      right: rightPadding,
      child: Container(
        decoration: BoxDecoration(
          color: context.watch<DarkMode>().isDarkMode
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF8F9FA),
          border: Border(
            top: BorderSide(
              color: context.watch<DarkMode>().isDarkMode
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          indicatorColor: context.watch<DarkMode>().isDarkMode
              ? Colors.white
              : Colors.black,
          indicatorWeight: 2,
          dividerColor: Colors.transparent,
          dividerHeight: 0,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          labelColor: context.watch<DarkMode>().isDarkMode
              ? Colors.white
              : Colors.black,
          unselectedLabelColor: context.watch<DarkMode>().isDarkMode
              ? Colors.white54
              : Colors.grey.shade400,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          tabs: _dynamicTabs,
        ),
      ),
    );
  }

  /// 构建主要内容区域
  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部学习进度条
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _progressBarTapCount++;
            _progressBarTapTimer?.cancel();

            // 添加震动反馈
            HapticFeedback.lightImpact();

            if (_progressBarTapCount >= 5) {
              _progressBarTapCount = 0;
              _showDebugOverlay();
            } else {
              // 提示还差几次
              _progressBarTapTimer =
                  Timer(const Duration(milliseconds: 3000), () {
                _progressBarTapCount = 0;
              });
            }
          },
          child: Container(
            margin: EdgeInsets.fromLTRB(
                0, MediaQuery.of(context).padding.top + 8, 0, 0),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4), // 进一步减小垂直间距以整体上移下方元素
            child: Container(
              height: 3, // 从 6 改为 3
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1.5), // 从 3 改为 1.5
                color: context.watch<DarkMode>().isDarkMode
                    ? const Color(0xFF2C2C2C)
                    : const Color(0xFFF0F2F5),
              ),
              child: _currentGetWordResult?.progress != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final maxValue =
                            _currentGetWordResult!.progress![1].toDouble();
                        final width = constraints.maxWidth;

                        // 计算批次颜色：从红色(0) -> 蓝色(0.5) -> 绿色(1.0) 渐变
                        // 根据白天/黑夜模式调整基础透明度
                        final bool isDarkMode =
                            context.watch<DarkMode>().isDarkMode;
                        final double baseAlpha =
                            isDarkMode ? 0.25 : 0.15; // 黑夜模式稍明显一点，白天模式更淡

                        // 获取批次的基础颜色（不透明度）
                        // 修改：所有批次都使用最后一个批次的颜色（绿色）
                        Color getBatchBaseColor(
                            int batchIndex, int totalBatches) {
                          return isDarkMode
                              ? Colors.white
                              : const Color(0xFF1A1A1A);
                        }

                        Color getBatchColor(int batchIndex, int totalBatches) {
                          // 所有批次都使用统一的半透明绿色作为背景色
                          return getBatchBaseColor(batchIndex, totalBatches)
                              .withValues(alpha: baseAlpha);
                        }

                        // 计算批次数量（基于单词数量，每批次10个单词）
                        final modeCount = activeUserStudySteps.length;

                        // 【根本原因修复】检查 modeCount 和 maxValue 是否有效
                        // 如果学习步骤未配置或进度数据无效，不渲染进度条
                        if (modeCount <= 0 || maxValue <= 0 || width <= 0) {
                          return const SizedBox.shrink();
                        }

                        final wordCount = (maxValue / modeCount).ceil();
                        final batchWordCount = 10;
                        final totalBatches =
                            max(1, (wordCount / batchWordCount).ceil());

                        // 计算当前进度所在的批次索引
                        final currentProgress =
                            _currentGetWordResult!.progress![0].toDouble();
                        // 当前步进对应的单词索引
                        final currentWordIndex = min(
                            (currentProgress / modeCount).floor(),
                            wordCount - 1);
                        final currentBatchIndex = min(
                            (currentWordIndex / batchWordCount).floor(),
                            totalBatches - 1);
                        // 获取当前批次的鲜艳颜色作为进度条前景色
                        final progressColor =
                            getBatchBaseColor(currentBatchIndex, totalBatches);

                        return Stack(
                          children: [
                            // 批次背景色层（基于单词批次）
                            Row(
                              children: List.generate(totalBatches, (index) {
                                final isLastBatch = index == totalBatches - 1;
                                // 计算该批次包含的单词数
                                final startWordIndex = index * batchWordCount;
                                final endWordIndex = min(
                                    (index + 1) * batchWordCount, wordCount);
                                final batchWords =
                                    endWordIndex - startWordIndex;
                                // 转换为进度条宽度（乘以模式数）
                                final batchSteps = batchWords * modeCount;
                                final batchWidth =
                                    (batchSteps / maxValue) * width;
                                return Container(
                                  width: batchWidth,
                                  decoration: BoxDecoration(
                                    color: getBatchColor(index, totalBatches),
                                    borderRadius: BorderRadius.horizontal(
                                      left: index == 0
                                          ? const Radius.circular(1.5)
                                          : Radius.zero,
                                      right: isLastBatch
                                          ? const Radius.circular(1.5)
                                          : Radius.zero,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            ClipRRect(
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(1.5)),
                              child: FAProgressBar(
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(1.5)),
                                currentValue: currentProgress,
                                maxValue: maxValue,
                                displayText: '',
                                direction: Axis.horizontal,
                                displayTextStyle: const TextStyle(
                                    color: Color(0x00000000), fontSize: 0),
                                backgroundColor: Colors.transparent,
                                progressColor: progressColor,
                                animatedDuration:
                                    const Duration(milliseconds: 300),
                              ),
                            ),
                            // 批次分隔线（只在批次边界处显示）
                            if (totalBatches > 1)
                              ...List.generate(totalBatches - 1, (index) {
                                // 计算批次边界对应的进度位置
                                final boundaryWordIndex =
                                    (index + 1) * batchWordCount;
                                final boundaryStep =
                                    boundaryWordIndex * modeCount;
                                final left = (boundaryStep / maxValue) * width;
                                // 只有当计算出的位置在进度条范围内时才显示
                                if (left <= 0 || left >= width) {
                                  return const SizedBox.shrink();
                                }
                                return Positioned(
                                  left: left,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1.5,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),

        // 顶部按钮
        _buildTopButtonsRow(),
        // 顶部按钮和题目区之间的间距
        const SizedBox(height: 8),
        // 题目区 - 使用flex=3（增大高度，便于显示较长题目）
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              // 题目内容区域
              _buildQuestionContent(),
              // 浮动的TabBar
              _buildFloatingTabBar(),
            ],
          ),
        ),
        // 题目区和做题区之间的统一间距
        SizedBox(height: _questionAnswerGap),
        // 做题区 - 使用flex=2
        Expanded(
          flex: 2,
          child: Container(
            // 做题区背景色 - 浅绿色调
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _showBorders
                  ? Border.all(
                      color: Colors.blue,
                      width: 10,
                    )
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, 0),
            child: (_showAnswerButtons ||
                    _studyStep == StudyStep.en2Ch.json ||
                    _studyStep == StudyStep.ch2En.json)
                ? Column(
                    children: [
                      Expanded(
                        child: (_studyStep == StudyStep.en2Ch.json ||
                                _studyStep == StudyStep.ch2En.json)
                            ? TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: _dynamicTabBarViewChildren,
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildChoiceList(),
                                  Expanded(child: _buildSpeakPanel()),
                                ],
                              ),
                      ),
                    ],
                  )
                : InkWell(
                    key: const Key('bdc_do_question_btn'),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app_outlined),
                            Text('点此做题'),
                          ],
                        ),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        _showAnswerButtons = true;
                      });
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// 构建底部按钮
  Widget _buildBottomButtons() {
    return Container(
      key: _bottomButtonsKey,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 如果已经完成回答（_hasFinishedAnswering），且不是自动跳词（或者本次是打错 Again），则展现出评分面板使用户可见且可调整
          if (_hasFinishedAnswering &&
              (!_autoJumpAfterCorrect || _lastFsrsRating == FsrsRating.again))
            _buildFsrsResultPanel(),
          Container(
            // 底部按钮区背景色 - 紫色调
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _showBorders
                  ? Border.all(
                      color: context.watch<DarkMode>().isDarkMode
                          ? const Color(0xFF9C27B0) // 深色模式：紫色边框
                          : const Color(0xFF7B1FA2), // 浅色模式：深紫色边框
                      width: 2,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_showAnswerButtons || _studyStep == StudyStep.en2Ch.json)
                  ElevatedButton(
                    key: const Key('bdc_not_know_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.white.withValues(alpha: 0.1)
                          : const Color(0xFFF5F5F5),
                      foregroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.white70
                          : const Color(0xFF666666),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => showWordDetail(_word, true,
                        fsrsRating: FsrsRating.again, reason: "主动点击了不再认识，评分: 忘记"),
                    child: const Text('不认识',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                if (_showAnswerButtons || _studyStep == StudyStep.en2Ch.json)
                  ElevatedButton(
                    key: const Key('bdc_study_again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.white.withValues(alpha: 0.1)
                          : const Color(0xFFF5F5F5),
                      foregroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.white70
                          : const Color(0xFF666666),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => showWordDetail(_word, false,
                        fsrsRating: FsrsRating.good, reason: "主动点击了再学学，评分: 良好"),
                    child: const Text('再学学',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                if (_canLeaveCurrWord)
                  ElevatedButton(
                    key: const Key('bdc_next_word_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.white
                          : AppTheme.primaryColor,
                      foregroundColor: context.watch<DarkMode>().isDarkMode
                          ? Colors.black
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () =>
                        getNextWord(true, fsrsRating: _lastFsrsRating),
                    child: const Text('下一词',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SizedBox spellExerciseTextField(String wordSpell) {
    TextStyle textStyle =
        const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    double width = Util.getTextWidth(wordSpell, textStyle);
    return SizedBox(
      width: width * 1.3,
      height: 26,
      child: TextField(
        textAlign: TextAlign.center,
        controller: _wordWrapper!.spellController,
        focusNode: _wordWrapper!.focusNode,
        autofocus: true,
        // 仅保留下边框样式（听音选意模式专用）
        decoration: InputDecoration(
          isCollapsed: true,
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Global.highlight),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        keyboardType: TextInputType.visiblePassword,
        maxLines: 1,
        onChanged: (value) {
          // 拼写正确，播放发音并关闭输入法
          if (Util.equalsIgnoreCase(_word!.spell, value)) {
            SoundUtil.playPronounceSound(_word!);
            Util.closeIme();
          }
          setState(() {});
        },
        style: textStyle,
      ),
    );
  }

  resetHighlightedWordImg() {
    setState(() {
      _highlightedWordImg = null;
    });
  }

  Future<bool> wordImageHasBeenVoted(var wordImage) async {
    return (await MyDatabase.instance.votedWordImagesDao.getVotedWordImageById(
            Global.getLoggedInUser()!.id, wordImage.id)) !=
        null;
  }

  /// 放大单词配图对话框
  Future<void> showEditPicDlg(
      BuildContext context, WordImageVo wordImage) async {
    Future<bool>? voteFuture;
    showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 100),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FractionalTranslation(
              translation: Offset(1 - animation.value, 0), // 从中部出现
              child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(builder: (context, dialogSetState) {
            voteFuture ??= wordImageHasBeenVoted(wordImage);
            return Align(
              alignment: const Alignment(0, 0),
              child: Container(
                width: PlatformUtils.isWeb
                    ? 600
                    : MediaQuery.of(context).size.width,
                height: PlatformUtils.isWeb ? 480 : 320,
                margin: MediaQuery.of(context).viewInsets,
                // 当软键盘弹出时，对话框自动上移
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                color: context.read<DarkMode>().isDarkMode
                    ? const Color(0xff333333)
                    : Colors.white,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            child: Image.network(
                                '${Config.wordImageBaseUrl}${wordImage.imageFile}',
                                width: PlatformUtils.isWeb ? 400 : 200,
                                height: PlatformUtils.isWeb ? 300 : 150,
                                fit: BoxFit.contain, loadingBuilder:
                                    (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.indigoAccent,
                                  strokeWidth: 2,
                                ),
                              );
                            }, errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.red,
                                  size: 32,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                'by：${Util.getNickNameOfUser(wordImage.author)}'),
                          ],
                        ),
                      ),
                      FutureBuilder<bool>(
                          future: voteFuture,
                          builder: (BuildContext context,
                              AsyncSnapshot<bool> snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.done) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.favorite_outline,
                                            size: 24,
                                            color: snapshot.data!
                                                ? Util.voteColorDisabled(
                                                    context)
                                                : Util.voteColorEnabled(
                                                    context),
                                          ),
                                          Text(' ${wordImage.hand}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: snapshot.data!
                                                      ? Util.voteColorDisabled(
                                                          context)
                                                      : Util.voteColorEnabled(
                                                          context))),
                                        ],
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client
                                            .handWordImage(wordImage.id);
                                        if (result.success) {
                                          MyDatabase.instance.votedWordImagesDao
                                              .createEntity(VotedWordImage(
                                                  userId:
                                                      Global.getLoggedInUser()!
                                                          .id,
                                                  imageId: wordImage.id,
                                                  vote: 'HAND'));
                                          wordImage.hand += 1;
                                          _wordImageEdited = true;
                                          voteFuture = Future.value(true);
                                          if (mounted) {
                                            dialogSetState(() {});
                                          }
                                        } else {
                                          ToastUtil.error(result.msg!);
                                        }
                                      }),
                                  InkWell(
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 24),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.heart_broken_outlined,
                                              size: 24,
                                              color: snapshot.data!
                                                  ? Util.voteColorDisabled(
                                                      context)
                                                  : Util.voteColorEnabled(
                                                      context),
                                            ),
                                            Text(' ${wordImage.foot}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: snapshot.data!
                                                        ? Util
                                                            .voteColorDisabled(
                                                                context)
                                                        : Util.voteColorEnabled(
                                                            context))),
                                          ],
                                        ),
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client
                                            .footWordImage(wordImage.id);
                                        if (result.success) {
                                          MyDatabase.instance.votedWordImagesDao
                                              .createEntity(VotedWordImage(
                                                  userId:
                                                      Global.getLoggedInUser()!
                                                          .id,
                                                  imageId: wordImage.id,
                                                  vote: 'FOOT'));
                                          wordImage.foot += 1;
                                          _wordImageEdited = true;
                                          voteFuture = Future.value(true);
                                          if (mounted) {
                                            dialogSetState(() {});
                                          }
                                        } else {
                                          ToastUtil.error(result.msg!);
                                        }
                                      }),
                                ],
                              );
                            } else {
                              return Container();
                            }
                          }),
                      Container(
                        margin: const EdgeInsets.fromLTRB(0, 32, 0, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (wordImage.author.id ==
                                    Global.getLoggedInUser()!.id ||
                                (Global.getLoggedInUser()!.isAdmin ?? false) ||
                                (Global.getLoggedInUser()!.isSuperAdmin ??
                                    false))
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.red, // foreground
                                ),
                                child: const Text('删除'),
                                onPressed: () {
                                  // 先关闭对话框，再执行异步操作
                                  resetHighlightedWordImg();
                                  Navigator.pop(context, false);

                                  // 然后执行异步删除操作
                                  Api.client
                                      .deleteWordImage(wordImage.id,
                                          Global.getLoggedInUser()!.id)
                                      .then((result) {
                                    if (result.success) {
                                      ToastUtil.info("删除成功");
                                    } else {
                                      ToastUtil.error(result.msg!);
                                    }

                                    if (mounted) {
                                      reloadWord();
                                    }
                                  });
                                },
                              ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('关闭'),
                              onPressed: () {
                                resetHighlightedWordImg();
                                Navigator.pop(context, false);
                                if (_wordImageEdited) {
                                  reloadWord();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        });
  }

  void giveALittleHint(WordWrapper word) {
    setState(() {
      _hintTapCount++;
      word.hintLetterCount++;
      // 中英模式 或 正在进行拼写练习：提供英文拼写提示
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        final spell = word.word.spell;
        if (word.hintLetterCount > spell.length) {
          word.hintLetterCount = spell.length;
        }
        _isUpdatingByHint = true;
        _meaningController.text = spell.substring(0, word.hintLetterCount);
      }
    });
  }

  void giveFullHint(WordWrapper word) {
    setState(() {
      _hintTapCount = 2; // 长按直接视为严重提示
      word.hintLetterCount = word.word.spell.length;
      // 中英模式 或 正在进行拼写练习：拼写提示
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        _isUpdatingByHint = true;
        _meaningController.text = word.word.spell;
      }
    });
  }

  void clearHint(WordWrapper word) {
    setState(() {
      word.hintLetterCount = 0;
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        _isUpdatingByHint = true;
        _meaningController.text = '';
      }
    });
  }

  onAnswerClicked(var selectedAnswerIndex) async {
    // 已经选过了：再次点击时触发对应选项的3D翻牌效果，展示另一层释义
    if (_selectedAnswerIndex != null) {
      int wordIndex = selectedAnswerIndex - 1;
      if (_words != null && wordIndex >= 0 && wordIndex < _words!.length) {
        WordVo clickedWord = _words![wordIndex];
        if (clickedWord.spell == "[ 都不对 ]") return;
        
        setState(() {
          if (_flippedAnswerIndices.contains(wordIndex)) {
            _flippedAnswerIndices.remove(wordIndex);
          } else {
            _flippedAnswerIndices.add(wordIndex);
          }
        });
      }
      return;
    }

    // 评分已经通过其它方式（如语音、跳过）出来了，但在本模式还没点击过
    // 点击时希望能有颜色反馈（点击后再反馈，而非一切换模式就反馈），同时也触发翻牌
    if (_hasFinishedAnswering) {
      int wordIndex = selectedAnswerIndex - 1;
      setState(() {
        _selectedAnswerIndex = selectedAnswerIndex;
        if (_words != null && wordIndex >= 0 && wordIndex < _words!.length) {
          WordVo clickedWord = _words![wordIndex];
          if (clickedWord.spell != "[ 都不对 ]") {
            _flippedAnswerIndices.add(wordIndex);
          }
        }
      });
      return;
    }

    setState(() {
      _selectedAnswerIndex = selectedAnswerIndex;
    });

    _hasFinishedAnswering = selectedAnswerIndex == _correctAnswerIndex;
    if (_hasFinishedAnswering) {
      // 计算 FSRS 评分
      FsrsRating rating = FsrsRating.good; // 默认 Good
      int? rTime;
      if (_wordStartTime != null) {
        final responseTime =
            DateTime.now().difference(_wordStartTime!).inSeconds;
        rTime = responseTime;
        if (responseTime < 8) {
          rating = FsrsRating.easy; // Easy
        } else if (responseTime >= 18) {
          rating = FsrsRating.hard; // Hard
        }
      }

      bool usedTranslation = _showSentenceTranslation;
      // 如果点击提示次数 >= 2 (包括长按的 Full Hint) 或看了翻译，直接记录为不会 (Again)
      // 如果仅点了一次，下降一档
      if (_hintTapCount >= 2 || usedTranslation) {
        rating = FsrsRating.again;
      } else if (_hintTapCount == 1) {
        if (rating == FsrsRating.easy) {
          rating = FsrsRating.good;
        } else if (rating == FsrsRating.good) {
          rating = FsrsRating.hard;
        } else if (rating == FsrsRating.hard) {
          rating = FsrsRating.again;
        }
      }

      String reason = "回答耗时${rTime ?? '-'}秒";
      if (usedTranslation) {
        reason += "，查看了例句翻译";
      } else if (_hintTapCount > 0) {
        reason += "，查看提示$_hintTapCount次";
      }
      reason += "，评分: ${rating.label}";

      _lastFsrsRatingReason = reason;
      _onAnswerCorrect(rating);
    } else {
      //不认识或答案错误（错误提示音不需要等待，因为不会跳转到下一个单词）
      SoundUtil.playAssetSoundConcurrent('failed.mp3', 1.5, 0.2);
      showWordDetail(_word!, true,
          fsrsRating: FsrsRating.again, reason: "选错了答案，评分: 忘记"); // 传递true表示本次回答错误
    }
  }

  showWordDetail(var word, bool isAnswerWrong, {FsrsRating? fsrsRating, String? reason}) async {
    // 本次如果确定有评分（如选择了不认识），就算还未跳转下一题，也应立刻结算本地 FSRS 预览，让用户在返回时可以看到评分状态。
    if (fsrsRating != null) {
      _lastFsrsRating = fsrsRating;
      _lastFsrsRatingReason = reason ?? "系统判定错误或不熟，评分: ${fsrsRating.label}";
      _hasFinishedAnswering = true; // 将界面切入“结束当前作答”状态，以展示下拉按钮
      _canLeaveCurrWord = true;
      _meaningFocusNode.unfocus();

      final lw = _currentGetWordResult?.learningWord;
      if (lw != null) {
        final fsrs = FSRS();
        _daysSinceLastReview = 0;
        if (lw.lastLearningDate != null) {
          final lastDate = DateTime(lw.lastLearningDate!.year,
              lw.lastLearningDate!.month, lw.lastLearningDate!.day);
          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          _daysSinceLastReview = todayDate.difference(lastDate).inDays;
        }
        if (lw.stability == null || lw.stability == 0.0) {
          _fsrsItem = fsrs.init(fsrsRating);
        } else {
          final prevItem = FSRSItem(
            stability: lw.stability!,
            difficulty: lw.difficulty!,
            elapsedDays: _daysSinceLastReview ?? 0,
            scheduledDays: lw.scheduledDays ?? 0,
            reps: lw.reps ?? 0,
            lapses: lw.lapses ?? 0,
            state: FsrsStateExt.fromInt(lw.state),
          );
          _fsrsItem =
              fsrs.next(prevItem, fsrsRating, _daysSinceLastReview ?? 0);
        }
      }
      if (mounted) setState(() {});
    }

    var bottomBtn = Container(
      decoration: BoxDecoration(
        color: context.read<DarkMode>().isDarkMode
            ? Colors.white
            : AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          getNextWord(true, fsrsRating: fsrsRating);
        },
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '下一词 ',
              style: TextStyle(
                color: context.read<DarkMode>().isDarkMode
                    ? Colors.black
                    : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(Icons.arrow_forward,
                color: context.read<DarkMode>().isDarkMode
                    ? Colors.black
                    : Colors.white,
                size: 20),
          ],
        ),
      ),
    );
    await Get.toNamed('/word_detail',
        arguments: WordDetailPageArgs(word, false, bottomBtn, isAnswerWrong));

    // 从详情页返回后，自动恢复 ASR 状态
    if (mounted) {
      _handleTabChangeForAsr();
    }
  }

  reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }

  Future<void> _playWithAnimation(
      Future<void> Function() playSound, String audioType) async {
    setState(() {
      _playingStates[audioType] = true;
    });

    final controller =
        audioType == 'word' ? _wordSoundController : _sentenceSoundController;
    controller.repeat();

    // 播音开始前停止 ASR 任务（Hot Stop），消除硬件切换产生的杂音
    await asr.stopAsr();

    try {
      await playSound();
    } finally {
      if (mounted) {
        setState(() {
          _playingStates[audioType] = false;
        });
        controller.stop();
        controller.reset();

        // 播音结束后，如果当前在"说"tab且键盘未弹出，则统一交给 _handleTabChangeForAsr 控制ASR启动
        if (_isInSpeakTab && !_isKeyboardVisible) {
          Global.logger.d('BDC: 播音结束，准备根据当前状态决定是否启动ASR ($audioType)');
          _handleTabChangeForAsr();
        }
      }
    }
  }

  Widget buildWordSoundButton(WordVo word, AudioPlayer audioPlayer) {
    // 在拼写和音标显示的情况下使用小按钮
    if (_studyStep == StudyStep.en2Ch.json) {
      return Transform.translate(
          offset: Offset(6.0, 1.0),
          child: InkWell(
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _wordSoundController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_wordSoundController.value < 0.5 ? 0 : -2,
                          0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
                      child: Icon(
                        _playingStates['word']!
                            ? (_wordSoundController.value < 0.5
                                ? Icons.volume_up
                                : Icons.volume_down)
                            : Icons.volume_up,
                        color: _playingStates['word']!
                            ? Colors.teal[300]
                            : Colors.grey[500],
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              if (!_playingStates['word']!) {
                _playWithAnimation(
                    () => SoundUtil.playPronounceSound2(word, audioPlayer),
                    'word');
              }
            },
          ));
    }

    // 其他情况下使用中等大小的圆形按钮
    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _playingStates['word']!
            ? const Color(0xFF1A1A1A)
            : Colors.grey[200],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (!_playingStates['word']!) {
              _playWithAnimation(
                  () => SoundUtil.playPronounceSound2(word, audioPlayer),
                  'word');
            }
          },
          child: Center(
            child: AnimatedBuilder(
              animation: _wordSoundController,
              builder: (context, child) {
                return Icon(
                  _playingStates['word']!
                      ? (_wordSoundController.value < 0.5
                          ? Icons.volume_up
                          : Icons.volume_down)
                      : Icons.volume_up,
                  color:
                      _playingStates['word']! ? Colors.white : Colors.grey[600],
                  size: 28,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSentenceSoundButton() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        child: AnimatedBuilder(
          animation: _sentenceSoundController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2,
                  0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
              child: Icon(
                _playingStates['sentence']!
                    ? (_sentenceSoundController.value < 0.5
                        ? Icons.volume_up
                        : Icons.volume_down)
                    : Icons.volume_up,
                color: _playingStates['sentence']!
                    ? Colors.teal[300]
                    : Colors.grey[500],
                size: 18,
              ),
            );
          },
        ),
        onTap: () {
          if (!_playingStates['sentence']! &&
              _englishDigestOfFirstSentence != null) {
            _playWithAnimation(
                () => SoundUtil.playSentenceSound2(
                    _englishDigestOfFirstSentence!, _audioPlayer),
                'sentence');
          }
        },
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Container(
      height: 32, // 恢复原高度
      width: label != null ? null : 32, // 对于无标签的按钮，设置固定宽度形成圆形
      padding: EdgeInsets.symmetric(
        horizontal: label != null ? 8 : 4, // 调整无标签按钮的水平内边距
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(label != null ? 16 : 16),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDarkMode ? Colors.white70 : const Color(0xFF333333),
                size: 14,
              ),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label,
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color:
                        isDarkMode ? Colors.white70 : const Color(0xFF333333),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopButtonsRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), // 完全移除顶部向上的 padding，让按钮更加贴着进度条
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 返回按钮
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode
                  ? const Color(0xFF2C2C2C)
                  : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.watch<DarkMode>().isDarkMode
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (_currentGetWordResult != null && _currentGetWordResult!.progress != null && _currentGetWordResult!.progress!.length >= 2) {
                    final completed = _currentGetWordResult!.progress![0];
                    final total = _currentGetWordResult!.progress![1];
                    AnalyticsUtil.trackStudyQuitEarly(completed, total - completed);
                  }
                  Navigator.pop(context);
                },
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: context.watch<DarkMode>().isDarkMode
                      ? Colors.white70
                      : const Color(0xFF333333),
                  size: 18,
                ),
              ),
            ),
          ),
          // 右侧按钮组
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                // 已掌握按钮
                _buildTopActionButton(
                  icon: Icons.check_circle_outline,
                  label: '掌握',
                  onTap: () {
                    _hasFinishedAnswering = true;
                    _isWordMastered = true;
                    ToastUtil.info("不再学习 ${_word!.spell}");
                    getNextWord(true);
                  },
                ),

                // 编辑开关 - 仅在meaning模式下且非Web平台显示

                // 报错按钮
                _buildTopActionButton(
                  icon: Icons.report_problem_outlined,
                  label: '报错',
                  onTap: () => showErrorReportDlg(),
                ),

                // 查词按钮
                _buildTopActionButton(
                  icon: Icons.search_rounded,
                  onTap: () => Get.toNamed('/search'),
                ),

                // 设置按钮
                _buildTopActionButton(
                  icon: Icons.settings_outlined,
                  onTap: () => showSettingDlg(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerContent(String text) {
    if (text.isEmpty) return const SizedBox();

    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final lines = text.split('\n');
    List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;

      // 使用正则表达式匹配词性（如n.、v.、adj.等）
      final ciXingRegex = RegExp(r'^([a-z]+\.)');
      final match = ciXingRegex.firstMatch(line);

      if (match != null) {
        // 获取词性部分
        String ciXing = match.group(1)!;
        // 获取释义部分
        String meaning = line.substring(match.end);

        widgets.add(
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$ciXing ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color:
                        isDarkMode ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
                TextSpan(
                  text: _hideAnswerLeakContent(meaning),
                  style: TextStyle(
                    fontFamily: "NotoSansSC",
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Text(
            line,
            style: TextStyle(
              fontFamily: "NotoSansSC",
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
            ),
          ),
        );
      }

      // 添加行间距（除了最后一行）
      if (i < lines.length - 1) {
        widgets.add(const SizedBox(width: 16));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widgets,
      ),
    );
  }

  Widget _buildChoiceList() {
    if (!(_studyStep == StudyStep.en2Ch.json ||
        _studyStep == StudyStep.ch2En.json)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (var index = 0; index < (_words?.length ?? 0); index++)
          Builder(
            builder: (context) {
              Color bgColor;
              Color borderColor;
              final isDarkMode = context.watch<DarkMode>().isDarkMode;

              if (_selectedAnswerIndex != null) {
                if ((index + 1) == _correctAnswerIndex) {
                  bgColor = Colors.green.withValues(alpha: isDarkMode ? 0.25 : 0.15);
                  borderColor = Colors.green;
                } else if ((index + 1) == _selectedAnswerIndex) {
                  bgColor = Colors.red.withValues(alpha: isDarkMode ? 0.25 : 0.15);
                  borderColor = Colors.red;
                } else {
                  bgColor = isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA);
                  borderColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
                }
              } else {
                bgColor = isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA);
                borderColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
              }

              return Padding(
                padding: _studyStep == StudyStep.ch2En.json
                    ? const EdgeInsets.symmetric(vertical: 3)
                    : const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onAnswerClicked(index + 1),
                        child: Stack(
                          children: [
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 300),
                          crossFadeState: _flippedAnswerIndices.contains(index)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: _buildAnswerContent(
                              _studyStep == StudyStep.ch2En.json
                                  ? (_words?[index].spell.isNotEmpty == true ? _words![index].spell : '无对应英文')
                                  : (_words?[index].getMeaningStr().isNotEmpty == true ? _words![index].getMeaningStr() : '无对应释义'),
                            ),
                          ),
                          secondChild: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: _buildAnswerContent(
                              _studyStep == StudyStep.ch2En.json
                                  ? (_words?[index].getMeaningStr().isNotEmpty == true ? _words![index].getMeaningStr() : '无对应释义')
                                  : (_words?[index].spell.isNotEmpty == true ? _words![index].spell : '无对应英文'),
                            ),
                          ),
                        ),
                            if ((_hasFinishedAnswering || _selectedAnswerIndex != null) &&
                                (_words?[index].spell != "[ 都不对 ]"))
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(
                                  Icons.sync,
                                  size: 16,
                                  color: isDarkMode ? Colors.white30 : Colors.black26,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSpeakPanel() {
    if (!((_studyStep == StudyStep.en2Ch.json ||
            _studyStep == StudyStep.ch2En.json) &&
        _word != null)) {
      return const SizedBox.shrink();
    }
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶栏：音频波纹 + 提示/清除按钮 (固定浮动在上方)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.watch<DarkMode>().isDarkMode
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFF8F9FA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(
              color: context.watch<DarkMode>().isDarkMode
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.03),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 语音波形反馈
              Expanded(
                child: _studyStep == StudyStep.en2Ch.json
                    ? ChineseAsrInputWidget(
                        controller: _meaningController,
                        asrState: asr.state,
                        onStartAsr: (language) => asr.startAsr(language),
                        isKeyboardVisible: _isKeyboardVisible,
                        focusNode: _meaningFocusNode,
                      )
                    : EnglishAsrInputWidget(
                        controller: _meaningController,
                        asrState: asr.state,
                        onStartAsr: (language) => asr.startAsr(language),
                        isKeyboardVisible: _isKeyboardVisible,
                        focusNode: _meaningFocusNode,
                        score: _currentScore,
                      ),
              ),

              const SizedBox(width: 8),

              // 功能按钮区
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPanelButton(
                    icon: Icons.emoji_objects_rounded,
                    label: '提示',
                    onTap: () => giveALittleHint(_wordWrapper!),
                    onLongPress: () => giveFullHint(_wordWrapper!),
                  ),
                  const SizedBox(width: 6),
                  _buildPanelButton(
                    icon: Icons.refresh,
                    label: '清除',
                    onTap: () => clearHint(_wordWrapper!),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. 滚动区域：中文释义 / 拼写提示
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode
                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.8)
                  : const Color(0xFFF8F9FA).withValues(alpha: 0.8),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(
                left: BorderSide(
                    color: context.watch<DarkMode>().isDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
                right: BorderSide(
                    color: context.watch<DarkMode>().isDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
                bottom: BorderSide(
                    color: context.watch<DarkMode>().isDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
              ),
            ),
            child: SingleChildScrollView(
              controller: _speakPanelScrollController,
              physics: _showHandwritingBoard
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: EdgeInsets.zero,
              child: _studyStep == StudyStep.en2Ch.json
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...renderAsrMeaningItems(_wordWrapper!,
                            isDarkMode: context.read<DarkMode>().isDarkMode),
                        const SizedBox(height: 16),
                        _buildSpellingExerciseButton(isDarkMode),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '说出单词发音 或 直接拼写：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.watch<DarkMode>().isDarkMode
                                ? const Color(0xFFD1D5DB)
                                : const Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 拼写练习按钮 (替代原来的 TextField)
                        _buildSpellingExerciseButton(isDarkMode),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建拼写练习按钮
  Widget _buildSpellingExerciseButton(bool isDarkMode) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            _isUpdatingByHint = true;
            _meaningController.clear();
            _isUpdatingByHint = false;
            setState(() {
              _showHandwritingBoard = true;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: context.watch<DarkMode>().isDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note,
                    color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: _meaningController.text.isEmpty
                      ? Text(
                          '拼写练习',
                          style: TextStyle(
                            fontSize: 20,
                            color: (isDarkMode ? Colors.white : Colors.black)
                                .withValues(alpha: 0.2),
                            fontWeight: FontWeight.normal,
                          ),
                        )
                      : RichText(
                          text: SpellingTextEditingController
                              .buildSpellingTextSpan(
                            _meaningController.text,
                            _word?.spell ?? "",
                            _meaningController.text.trim().toLowerCase() !=
                                    (_word?.spell.toLowerCase() ?? "")
                                ? Colors.red
                                : (isDarkMode ? Colors.white : Colors.black),
                            const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _updateFsrsRating(FsrsRating newRating) {
    setState(() {
      _lastFsrsRating = newRating;

      // 重新计算 FSRS 预览结果
      final lw = _currentGetWordResult?.learningWord;
      if (lw != null) {
        final fsrs = FSRS();
        _daysSinceLastReview = 0;
        if (lw.lastLearningDate != null) {
          final lastDate = DateTime(lw.lastLearningDate!.year,
              lw.lastLearningDate!.month, lw.lastLearningDate!.day);
          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          _daysSinceLastReview = todayDate.difference(lastDate).inDays;
        }
        if (lw.stability == null || lw.stability == 0.0) {
          _fsrsItem = fsrs.init(newRating);
        } else {
          final prevItem = FSRSItem(
            stability: lw.stability!,
            difficulty: lw.difficulty!,
            elapsedDays: _daysSinceLastReview ?? 0,
            scheduledDays: lw.scheduledDays ?? 0,
            reps: lw.reps ?? 0,
            lapses: lw.lapses ?? 0,
            state: FsrsStateExt.fromInt(lw.state),
          );
          _fsrsItem = fsrs.next(prevItem, newRating, _daysSinceLastReview ?? 0);
        }
      }
    });
  }

  void _showRatingModifyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('修改今日评分',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        '评分影响该单词今后的复习频率。如果自动评分不合实际，可手动修正',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (_lastFsrsRatingReason != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_lastFsrsRatingReason',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primaryColor,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...FsrsRating.values.map((rating) {
                Color ratingColor;
                final isDarkMode = context.read<DarkMode>().isDarkMode;
                switch (rating) {
                  case FsrsRating.again:
                    ratingColor = isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F);
                    break;
                  case FsrsRating.hard:
                    ratingColor = isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00);
                    break;
                  case FsrsRating.easy:
                    ratingColor = isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32);
                    break;
                  case FsrsRating.good:
                    ratingColor = AppTheme.primaryColor;
                    break;
                }

                return ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  title: Text(
                    rating.label,
                    style: TextStyle(
                      color: ratingColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: _lastFsrsRating == rating
                      ? Icon(Icons.check, color: ratingColor)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _updateFsrsRating(rating);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFsrsResultPanel() {
    if (_fsrsItem == null) return const SizedBox();
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white38 : Colors.black38;

    // 获取本次操作的评估标签和颜色
    String ratingLabel = _lastFsrsRating?.label ?? '未知';
    Color ratingColor;

    switch (_lastFsrsRating) {
      case FsrsRating.again:
        ratingColor =
            isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F); // 深红色
        break;
      case FsrsRating.hard:
        ratingColor =
            isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00); // 橘色
        break;
      case FsrsRating.easy:
        ratingColor =
            isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32); // 深绿色
        break;
      case FsrsRating.good:
      default:
        ratingColor =
            isDarkMode ? AppTheme.primaryColor : AppTheme.primaryColor;
        break;
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: _showRatingModifyDialog,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 14, color: ratingColor),
                  const SizedBox(width: 4),
                  Text(
                    '今日测评: $ratingLabel',
                    style: TextStyle(
                      fontSize: 11,
                      color: ratingColor,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dashed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('|',
                style: TextStyle(
                    fontSize: 10, color: textColor.withValues(alpha: 0.3))),
          ),
          Icon(Icons.event_note_outlined, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: '下次复习: ',
                    style: TextStyle(fontSize: 11, color: textColor)),
                TextSpan(
                  text: '${_fsrsItem!.scheduledDays}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                    text: '天后',
                    style: TextStyle(fontSize: 11, color: textColor)),
              ],
            ),
          ),
          if (_wordWrapper?.word.id != null)
            FutureBuilder(
              future: MyDatabase.instance.learningLogsDao.getHistory(
                  Global.getLoggedInUser()!.id, _wordWrapper!.word.id!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox();
                }
                final historyCount = (snapshot.data as List?)?.length ?? 0;
                if (historyCount == 0) {
                  return const SizedBox();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _showLearningHistoryDialog,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 14,
                              color: textColor.withValues(alpha: 0.75)),
                          const SizedBox(width: 2),
                          Text(
                            '$historyCount',
                            style: TextStyle(
                                fontSize: 11,
                                color: textColor.withValues(alpha: 0.8),
                                height: 1.1),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  void _showLearningHistoryDialog() async {
    final wordId = _wordWrapper?.word.id;
    if (wordId == null) return;

    final history = await MyDatabase.instance.learningLogsDao
        .getHistory(Global.getLoggedInUser()!.id, wordId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final isDarkMode = context.watch<DarkMode>().isDarkMode;
        final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDarkMode ? Colors.white70 : Colors.black87;

        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('记忆历史',
              style: TextStyle(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          content: history.isEmpty
              ? Text('暂无记忆历史',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6)))
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final log = history[index];
                      final rating = FsrsRatingExt.fromInt(log.rating);
                      final timeStr =
                          '${log.createTime.year}-${log.createTime.month.toString().padLeft(2, '0')}-${log.createTime.day.toString().padLeft(2, '0')} ${log.createTime.hour.toString().padLeft(2, '0')}:${log.createTime.minute.toString().padLeft(2, '0')}';

                      Color ratingColor;
                      switch (rating) {
                        case FsrsRating.again:
                          ratingColor = Colors.redAccent;
                          break;
                        case FsrsRating.hard:
                          ratingColor = Colors.orangeAccent;
                          break;
                        case FsrsRating.good:
                          ratingColor = AppTheme.primaryColor;
                          break;
                        case FsrsRating.easy:
                          ratingColor = Colors.greenAccent;
                          break;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ratingColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: ratingColor.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                rating.label,
                                style: TextStyle(
                                    color: ratingColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                            text: '下次复习: ',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        TextSpan(
                                          text: '${log.scheduledDays}',
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                            text: '天后',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: textColor.withValues(alpha: 0.3)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      },
    );
  }

  Widget _buildPanelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color:
              isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDarkMode
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 音标行
  Widget _buildPhoneticRow() {
    if (!(_currentGetWordResult?.learningWord?.word != null &&
        _studyStep != StudyStep.en2Ch.json)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode
            ? const Color(0xFF2C2C2C)
            : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_studyStep != StudyStep.ch2En.json)
            Flexible(
              child: Text(
                Util.getWordDefaultPronounce(
                            _currentGetWordResult!.learningWord!.word)
                        .isEmpty
                    ? ''
                    : '[${Util.getWordDefaultPronounce(_currentGetWordResult!.learningWord!.word)}]',
                style: TextStyle(
                  color: context.watch<DarkMode>().isDarkMode
                      ? const Color(0xFFD1D5DB)
                      : const Color(0xFF4B5563),
                  fontFamily: "NotoSans",
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (_studyStep != StudyStep.ch2En.json)
            buildWordSoundButton(
                _currentGetWordResult!.learningWord!.word, _audioPlayer),
        ],
      ),
    );
  }

  /// 题目区的例句行(单词的第一个例句)
  Widget _buildFirstSentenceRow() {
    if (!(_word?.sentences != null &&
        _word!.sentences!.isNotEmpty &&
        _studyStep != StudyStep.ch2En.json &&
        _studyStep != StudyStep.en2Ch.json)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode
                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.5)
                  : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              child: AnimatedBuilder(
                animation: _sentenceSoundController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(
                        _sentenceSoundController.value < 0.5 ? 0 : -2, 0),
                    child: Icon(
                      _playingStates['sentence']!
                          ? (_sentenceSoundController.value < 0.5
                              ? Icons.volume_up
                              : Icons.volume_down)
                          : Icons.volume_up,
                      color: _playingStates['sentence']!
                          ? Colors.teal[300]
                          : Colors.grey[500],
                      size: 24,
                    ),
                  );
                },
              ),
              onTap: () {
                if (!_playingStates['sentence']! &&
                    _englishDigestOfFirstSentence != null) {
                  _playWithAnimation(
                      () => SoundUtil.playSentenceSound2(
                          _englishDigestOfFirstSentence!, _audioPlayer),
                      'sentence');
                }
              },
            ),
          ),
          Expanded(
            child: Util.makeEnglishSpanText(
                _word!.sentences![0].english!,
                _word!.spell,
                true,
                context,
                false,
                null,
                true,
                FontWeight.w300),
          ),
        ],
      ),
    );
  }

  Widget _buildWordStepCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.watch<DarkMode>().isDarkMode
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '英→中 ${_getStudyStageLabel()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: context.watch<DarkMode>().isDarkMode
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    key: const Key('current_word_spell'),
                    _currentGetWordResult!.learningWord!.word.spell,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 36,
                      color: context.watch<DarkMode>().isDarkMode
                          ? Colors.white
                          : const Color(0xFF1A1A1A),
                      fontFamily: 'Roboto',
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        Util.getWordDefaultPronounce(
                                    _currentGetWordResult!.learningWord!.word)
                                .isEmpty
                            ? ''
                            : '[${Util.getWordDefaultPronounce(_currentGetWordResult!.learningWord!.word)}]',
                        style: TextStyle(
                          color: context.watch<DarkMode>().isDarkMode
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFF4B5563),
                          fontFamily: "NotoSans",
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    buildWordSoundButton(
                        _currentGetWordResult!.learningWord!.word,
                        _audioPlayer),
                  ],
                ),
                if (_word?.sentences != null &&
                    _word!.sentences!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Util.makeEnglishSpanText(
                                _word!.sentences![0].english!,
                                _word!.spell,
                                true,
                                context,
                                false,
                                null,
                                true,
                                FontWeight.w300),
                            if (!_showSentenceTranslation)
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _showSentenceTranslation = true;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      '显示翻译',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Util.makeChineseSpanText(
                                  _word!.sentences![0].chinese ?? '',
                                  context,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: context.watch<DarkMode>().isDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(left: 8, top: 2),
                        decoration: BoxDecoration(
                          color: context.watch<DarkMode>().isDarkMode
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedBuilder(
                            animation: _sentenceSoundController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(
                                    _sentenceSoundController.value < 0.5
                                        ? 0
                                        : -2,
                                    0),
                                child: Icon(
                                  _playingStates['sentence']!
                                      ? (_sentenceSoundController.value < 0.5
                                          ? Icons.volume_up
                                          : Icons.volume_down)
                                      : Icons.volume_up,
                                  color: _playingStates['sentence']!
                                      ? (context.watch<DarkMode>().isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A))
                                      : Colors.grey[500],
                                  size: 24,
                                ),
                              );
                            },
                          ),
                          onTap: () {
                            if (!_playingStates['sentence']! &&
                                _englishDigestOfFirstSentence != null) {
                              _playWithAnimation(
                                  () => SoundUtil.playSentenceSound2(
                                      _englishDigestOfFirstSentence!,
                                      _audioPlayer),
                                  'sentence');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeaningStepCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.watch<DarkMode>().isDarkMode
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '中→英 ${_getStudyStageLabel()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: context.watch<DarkMode>().isDarkMode
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          // 释义/图片/配图按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 释义
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0;
                          i <
                              _currentGetWordResult!.learningWord!.word
                                  .getMergedMeaningItems()
                                  .length;
                          i++)
                        Padding(
                          padding: EdgeInsets.only(
                              right: i ==
                                      _currentGetWordResult!.learningWord!.word
                                              .getMergedMeaningItems()
                                              .length -
                                          1
                                  ? 0
                                  : 16.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                _currentGetWordResult!.learningWord!.word
                                        .getMergedMeaningItems()[i]
                                        .ciXing ??
                                    '',
                                style: const TextStyle(
                                    color: Color(0xFF999999),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _hideParenthesesContent(_currentGetWordResult!
                                        .learningWord!.word
                                        .getMergedMeaningItems()[i]
                                        .meaning ??
                                    ''),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: context.watch<DarkMode>().isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // 图片 (仅对管理员开放)
                if ((Global.getLoggedInUser()?.isAdmin == true) &&
                    _currentGetWordResult?.images != null)
                  Column(
                    children: [
                      if (_currentGetWordResult!.images!.isNotEmpty &&
                          _studyStep != StudyStep.ch2En.json)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              '图片: ${_currentGetWordResult!.images!.length}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400)),
                        ),
                      WordImagesWidget(
                        images: _currentGetWordResult!.images!,
                        isEditMode: _isEditMode,
                        highlightedWordImg: _highlightedWordImg,
                        maxImages: 2,
                        onImageTap: (image) {
                          Global.logger
                              .d('show dialog for image: ${image.imageFile}');
                          _showImagePreviewWithContext(context, image,
                              onDeleted: () {
                            _currentGetWordResult?.images
                                ?.removeWhere((e) => e.id == image.id);
                            setState(() {});
                          });
                        },
                      ),
                    ],
                  ),
                // 配图按钮
                if (_isEditMode)
                  InkWell(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 24.0),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: context.watch<DarkMode>().isDarkMode
                              ? Colors.black
                              : Colors.white,
                          backgroundColor: context.watch<DarkMode>().isDarkMode
                              ? Colors.white
                              : AppTheme.primaryColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        label: const Text('添加配图'),
                        onPressed: () {
                          if (_currentGetWordResult?.learningWord?.word.id !=
                              null) {
                            Get.toNamed('/pic_search',
                                    arguments: PicSearchPageArgs(
                                        _currentGetWordResult!
                                            .learningWord!.word.id!,
                                        _currentGetWordResult!
                                            .learningWord!.word.spell))!
                                .then((value) => reloadWord());
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 隐藏括号内的内容，避免在"中→英"模式下暴露答案
  String _hideParenthesesContent(String text) {
    if (text.isEmpty) return text;

    // 使用正则表达式匹配括号及其内容
    // 匹配中文括号（）和英文括号()
    final parenthesesRegex = RegExp(r'[（(][^）)]*[）)]');

    // 替换所有括号及其内容为空字符串
    String result = text.replaceAll(parenthesesRegex, '');

    // 清理可能留下的多余空格和标点
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'[;；]\s*[;；]'), '；');
    result = result.replaceAll(RegExp(r'[,，]\s*[,，]'), '，');

    return result;
  }

  /// 隐藏答案按钮中可能暴露答案的内容
  String _hideAnswerLeakContent(String text) {
    if (text.isEmpty) return text;

    String result = text;

    // 1. 隐藏括号内的内容（如：死亡(decease的过去式) -> 死亡）
    final parenthesesRegex = RegExp(r'[（(][^）)]*[）)]');
    result = result.replaceAll(parenthesesRegex, '');

    // 2. 隐藏英文单词拼写（如：decease的过去式 -> ***的过去式）
    // 匹配英文单词后跟中文的情况
    final englishWordRegex = RegExp(r'\b[a-zA-Z]+\b(?=的|是|为|，|；|\.|$)');
    result = result.replaceAll(englishWordRegex, '***');

    // 3. 清理可能留下的多余空格和标点
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceAll(RegExp(r'[;；]\s*[;；]'), '；');
    result = result.replaceAll(RegExp(r'[,，]\s*[,，]'), '，');

    return result;
  }

  /// 显示调试浮窗，查看今日取词状态
  void _showDebugOverlay() async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    // 获取今日所有学习单词及其状态
    final words = await LearningService.getTodayLearningWordsFromDb(user.id);
    final activeSteps = activeUserStudySteps;

    // 获取用户已掌握的单词 ID 集，用于准确反映调度状态
    final masteredWords = await MyDatabase.instance.masteredWordsDao
        .getMasteredWordsForUser(user.id);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toSet();

    // 助手函数：判断单词是否已掌握 (调度层的一致性逻辑)
    bool isEffectivelyMastered(dynamic word) {
      if (masteredWordIds.contains(word.wordId)) {
        return true;
      }
      if (word.stability != null &&
          (word.stability ?? 0.0) >= Constants.graduationStability) {
        return true;
      }
      return false;
    }

    // 获取单词的拼写
    final Map<String, String> spellings = {};
    for (var w in words) {
      if (!spellings.containsKey(w.wordId)) {
        final wordData =
            await MyDatabase.instance.wordsDao.getWordById(w.wordId);
        spellings[w.wordId] = wordData?.spell ?? w.wordId;
      }
    }

    if (!mounted) return;

    // 分批次并按照学习序号排序
    words.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (a.batchId ?? 0).compareTo(b.batchId ?? 0);
      }
      return a.learningOrder.compareTo(b.learningOrder);
    });

    // 分组：底层调度系统固定是 10 个词为一个学习循环（也就是一个 Batch）
    const int batchSize = 10;
    final Map<int, List<dynamic>> batches = {};
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      // 计算其实际属于第几个调度轮次 (从 1 开始)
      final chunkId = (i ~/ batchSize) + 1;
      batches.putIfAbsent(chunkId, () => []).add(w);
    }

    // 计算即将到来的待办单元格 sequence
    List<Map<String, dynamic>> pendingCells = [];
    for (var batchId in batches.keys) {
      final batchWords = batches[batchId]!;
      for (int sIndex = 0; sIndex < activeSteps.length; sIndex++) {
        for (var w in batchWords) {
          if (w.todayLearnedTimes == sIndex) {
            pendingCells.add({'wordId': w.wordId, 'sIndex': sIndex});
          }
        }
      }
    }

    String? nextWordId;
    int? nextStepIndex;
    String? currentWordId = _currentGetWordResult?.learningWord?.word.id;

    if (pendingCells.isNotEmpty) {
      int currentIndex = -1;
      if (currentWordId != null) {
        currentIndex =
            pendingCells.indexWhere((cell) => cell['wordId'] == currentWordId);
      }

      if (currentIndex != -1 && currentIndex + 1 < pendingCells.length) {
        nextWordId = pendingCells[currentIndex + 1]['wordId'];
        nextStepIndex = pendingCells[currentIndex + 1]['sIndex'];
      } else if (currentIndex == -1) {
        nextWordId = pendingCells[0]['wordId'];
        nextStepIndex = pendingCells[0]['sIndex'];
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Debug",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final bool isDark = context.watch<DarkMode>().isDarkMode;
        final Color textColor = isDark ? Colors.white : Colors.black87;
        final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

        Widget buildLegendItem(bool done, bool mastered, String label) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green
                      : (isDark
                          ? Colors.white24
                          : Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: mastered
                      ? BorderRadius.circular(2)
                      : BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: subTextColor)),
            ],
          );
        }

        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 5 * anim1.value, sigmaY: 5 * anim1.value),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
              child: AlertDialog(
                backgroundColor: isDark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.9),
                elevation: 24,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.analytics_outlined,
                              color: Colors.blueAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日取词流水线',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '实时调度状态可视化',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: subTextColor,
                                  fontWeight: FontWeight.normal),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        buildLegendItem(true, false, '学过'),
                        buildLegendItem(false, false, '未学'),
                        buildLegendItem(true, true, '已掌握'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.blueAccent, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('当前',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('下一个',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 0.5),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                content: SizedBox(
                  width: 400,
                  height: 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: words.isEmpty
                        ? Center(
                            child: Text(
                              '今日还没有学习单词',
                              style: TextStyle(color: subTextColor),
                            ),
                          )
                        : ListView.builder(
                            itemCount: batches.keys.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (ctx, index) {
                              // 确保批次 ID 按顺序排列
                              final sortedBatchIds = batches.keys.toList()
                                ..sort();
                              int batchId = sortedBatchIds[index];
                              final batchWords = batches[batchId]!;

                              // 判断是否为当前批次
                              final bool isCurrentBatch = batchWords
                                  .any((w) => w.wordId == currentWordId);

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrentBatch
                                        ? Colors.blueAccent
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                    width: isCurrentBatch ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Batch $batchId',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: textColor),
                                    ),
                                    const SizedBox(height: 12),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Word Headers
                                          Row(
                                            children: [
                                              const SizedBox(
                                                  width:
                                                      60), // Space for step names
                                              ...batchWords.map((w) {
                                                final isCurrentWord =
                                                    _currentGetWordResult
                                                            ?.learningWord
                                                            ?.word
                                                            .id ==
                                                        w.wordId;
                                                return Tooltip(
                                                  message:
                                                      spellings[w.wordId] ??
                                                          w.wordId,
                                                  child: Container(
                                                    width: 30,
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    height:
                                                        70, // Room for rotated text
                                                    child: RotatedBox(
                                                      quarterTurns:
                                                          3, // text going up
                                                      child: Text(
                                                        spellings[w.wordId] ??
                                                            w.wordId,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isCurrentWord
                                                              ? Colors
                                                                  .blueAccent
                                                              : textColor,
                                                          fontWeight:
                                                              isCurrentWord
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                              const SizedBox(
                                                  width:
                                                      16), // Padding right for scrolling
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          // Data Rows (Steps)
                                          ...List.generate(activeSteps.length,
                                              (sIndex) {
                                            final stepInfo =
                                                activeSteps[sIndex];
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: [
                                                  SizedBox(
                                                    width: 60,
                                                    child: Text(
                                                      '${sIndex + 1}: ${stepInfo.studyStep}',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: subTextColor),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  ...batchWords.map((w) {
                                                    // Is the user learning this exact word in this exact step right now?
                                                    final isCurrentStep =
                                                        _currentGetWordResult
                                                                    ?.learningWord
                                                                    ?.word
                                                                    .id ==
                                                                w.wordId &&
                                                            w.todayLearnedTimes ==
                                                                sIndex;
                                                    final isNextStep =
                                                        nextWordId ==
                                                                w.wordId &&
                                                            nextStepIndex ==
                                                                sIndex;
                                                    // 已掌握的唯一标准：稳定度大于等于毕业阈值，或者在已掌握表中
                                                    final isWordFinished =
                                                        isEffectivelyMastered(
                                                            w);

                                                    // 从用户视角看：如果我处于这个环节，或者处于之后的环节，或者单词已掌握，则该格显绿
                                                    final isStepCompleted =
                                                        isWordFinished ||
                                                            w.todayLearnedTimes >
                                                                sIndex ||
                                                            isCurrentStep;

                                                    return Container(
                                                      width: 30,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Container(
                                                        width: 14,
                                                        height: 14,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isStepCompleted
                                                              ? Colors.green
                                                              : (isDark
                                                                  ? Colors
                                                                      .white24
                                                                  : Colors.grey
                                                                      .withValues(
                                                                          alpha:
                                                                              0.3)),
                                                          borderRadius:
                                                              isWordFinished
                                                                  ? BorderRadius
                                                                      .circular(
                                                                          3)
                                                                  : BorderRadius
                                                                      .circular(
                                                                          7), // 矩形(圆角3)/圆形(圆角7)
                                                          border: isCurrentStep
                                                              ? Border.all(
                                                                  color: Colors
                                                                      .blueAccent,
                                                                  width: 2)
                                                              : (isNextStep
                                                                  ? Border.all(
                                                                      color: Colors
                                                                          .orange,
                                                                      width: 2)
                                                                  : null),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                  const SizedBox(
                                                      width:
                                                          16), // Padding right for scrolling
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                actions: [
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('我知道了',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 桌面版本最大内容宽度，自动居中显示
    final isDesktop = PlatformUtils.isWindows ||
        PlatformUtils.isLinux ||
        PlatformUtils.isMacOS;
    const double maxContentWidth = 600.0;

    Widget pageContent =
        (!dataLoaded) ? const Center(child: Text('')) : renderPage();

    if (isDesktop) {
      pageContent = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: pageContent,
        ),
      );
    }

    return KeyboardDismissOnTap(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: null,
        body: Container(
          color: context.watch<DarkMode>().isDarkMode
              ? const Color(0xFF121212)
              : Colors.white,
          child: pageContent,
        ),
      ),
    );
  }
}
