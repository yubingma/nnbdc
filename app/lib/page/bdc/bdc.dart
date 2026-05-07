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
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:flutter/scheduler.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/phoneme_util.dart';
import 'package:provider/provider.dart';

import '../../api/enum.dart';
import '../../api/vo.dart';
import '../../config.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../state.dart';
import '../../util/asr.dart';
import '../../util/asr_util.dart';
import '../../constants.dart';
import '../../util/utils.dart';
import '../../db/user_extensions.dart';
import '../../util/error_handler.dart';
import '../../theme/app_theme.dart';
import '../../util/learning_service.dart';
import '../../util/fsrs.dart';
import '../../widget/handwriting_board.dart';
import '../../util/study_config.dart';
import '../../util/analytics_util.dart';
import '../../util/app_clock.dart';

import "models/bdc_page_args.dart";
import "models/word_ui_state.dart";
import "widgets/word_images_widget.dart";
import "widgets/chinese_asr_input_widget.dart";
import "widgets/english_asr_input_widget.dart";
part 'dialogs/bdc_dialogs.dart';
part 'widgets/bdc_ui_components.dart';
part 'controllers/bdc_logic_extension.dart';

class BdcPage extends StatefulWidget {
  const BdcPage({super.key});

  @override
  BdcPageState createState() {
    return BdcPageState();
  }
}

class BdcPageState extends State<BdcPage> with TickerProviderStateMixin {
  /// 用于给 extension 中的方法调用，避免使用 setState 时出现 lint 错误
  void updateUI(VoidCallback fn) {
    setState(fn);
  }


  bool dataLoaded = false;
  bool _isGettingNextWord = false;
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

  Future<List<LearningLog>>? _learningHistoryFuture;
  FsrsRating? _lowestRatingForCurrentWord;
  FsrsRating? _assessmentRating; // 记录今日测评环节的评分结果


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
  bool _autoJumpAfterCorrectCh2En = false;
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

  /// 底部按钮是否可用（用于不认识/再学学按钮的500ms延时限制）
  bool _buttonsEnabled = false;

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

  /// 历史记录
  final List<GetWordResult> _history = [];
  /// 缓存每个单词的 UI 状态，用于在回顾模式中恢复
  final Map<String, WordUIState> _wordUIStates = {};
  int _historyIndex = -1; // -1 表示当前词



  GetWordResult? _presentWord;
  double _slideDirection = 1.0; // 1.0 为向后（显示新内容从右进入），-1.0 为向前（显示旧内容从左进入）
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
      physics: const BouncingScrollPhysics(),
      child: _buildChoiceList(),
    ));

    return children;
  }

  /// 重新初始化TabController

  /// 根据当前tab状态处理ASR启动/停止逻辑

  /// 实际执行ASR启动/停止逻辑

  @override
  void initState() {
    super.initState();
    // 进门先关 ASR，确保状态干净
    Asr().stopAsr();
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

        // 记录用户偏好：使用键盘输入
        final config = StudyConfig.fromCurrentUser();
        if (!config.preferKeyboardInSpelling) {
          config.preferKeyboardInSpelling = true;
          config.saveToCurrentUser();
        }

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
    // 异步预加载音素字典，避免用户说话时才开始解析导致的延迟
    unawaited(PhonemeUtil.load());
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




  /// 设置ASR上下文短语（当前单词的释义子项(说中文)或当前单词的拼写(说英文)）

  /// 启动ASR并播放提示音

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
    final asrPerfStart = DateTime.now();
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
            final phonemeStart = DateTime.now();
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
                candidateStrings, _word!.spell);
            Global.logger.d('[PERF] selectBestCandidateWithPhonemeAndScore 耗时: ${DateTime.now().difference(phonemeStart).inMilliseconds}ms (candidates: ${candidateStrings.length})');
            _currentScore = result.score;
            processedResult =
                AsrUtil.preprocessEnglish(result.text, _word!.spell);
            Global.logger.d(
                '~~~~~ASR: Selected & Preprocessed: "$processedResult" (score: ${result.score})');
          } else {
            processedResult = bestCandidate;
            _currentScore = null;
          }
        } else if (_studyStep == StudyStep.en2Ch.json) {
          // 英→中模式：UI 显示最佳候选，但背后匹配逻辑会遍历所有 _currentAsrCandidates
          processedResult = AsrUtil.preprocess(bestCandidate);
          _currentScore = null;
          Global.logger.d(
              '~~~~~ASR [en2Ch]: Stored ${candidateStrings.length} candidates, showing best: $processedResult');
        } else {
          processedResult = bestCandidate;
          _currentScore = null;
        }
      } else {
        // 单个结果处理
        _currentAsrCandidates = [event.toString()];
        if (_studyStep == StudyStep.ch2En.json) {
          if (_word != null) {
            final pre = AsrUtil.preprocessEnglish(event, _word!.spell);
            final phonemeStart2 = DateTime.now();
            final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
                [pre], _word!.spell);
            Global.logger.d('[PERF] selectBestCandidateWithPhonemeAndScore (single) 耗时: ${DateTime.now().difference(phonemeStart2).inMilliseconds}ms');
            processedResult = result.text;
            _currentScore = result.score;
          } else {
            processedResult = event;
            _currentScore = null;
          }
        } else {
          processedResult = AsrUtil.preprocess(event);
          Global.logger.d('~~~~~ASR: Chinese processed result: $processedResult');
        }
      }
    } catch (e) {
      Global.logger.e('ASR: Error processing result: $e');
      processedResult = AsrUtil.preprocess(event.toString());
      _currentAsrCandidates = [event.toString()];
    }

    if (mounted) {
      Global.logger.d('[PERF] onAsrResult 预处理总耗时: ${DateTime.now().difference(asrPerfStart).inMilliseconds}ms');
      if (oldScore != _currentScore) {
        setState(() {}); // 触发 UI 刷新以实时显示最新的发音评分（即使没通过也能让用户看到反馈分数变化）
      }
      checkAsrResult(asrInput: processedResult, isVoice: true);
    }
  }


  checkAsrResult({String? asrInput, bool isVoice = false}) async {
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
      // 不再直接返回，允许空字符串更新 _handlingChinese 以刷新 UI
    }
    // 如果 ASR 未启动，且键盘也未弹出，且没有焦点，说明可能是 ASR 停止后的残留结果，跳过处理并清空
    // 如果是在手写模式下，或者是键盘弹出的情况下，允许通过检查
    bool isHandwritingOrKeyboard = _showHandwritingBoard ||
        _isKeyboardVisible ||
        _meaningFocusNode.hasFocus;

    // 如果输入框中的文本与正在处理的文本相同，则直接返回, 避免无谓的性能损耗
    // 核心优化：如果是显式 ASR 输入（语音或手写），即使文本相同也允许继续，防止因之前的异步状态竞争导致“识别出正确文本但不跳转”的问题
    if (asrInput != null || inputText != _handlingChinese) {
      Global.logger.d(
          'BDC CHECK_ASR: Processing input. asrInput=$asrInput, inputText=$inputText, oldHandling=$_handlingChinese');
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

    if (_hasFinishedAnswering) {
      if (asrInput == null) {
        return;
      }
    }

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
        _doHandleTabChangeForAsr();
        SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
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
        _firstMatchTime = AppClock.now();
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

          // 英→中模式下说对了单词的示意时，不自动填上正确英文拼写
          // if (asrInput != null) {
          //   _meaningController.text = _word!.spell;
          // }

          if (!_autoJumpAfterCorrect || _historyIndex != -1) {
            Global.logger.d(
                'BDC [en2Ch]: 非极速模式，拼写正确，准备关闭沉浸式输入界面. _showHandwritingBoard=false, unfocusing');
            _meaningFocusNode.unfocus();
            setState(() {
              _showHandwritingBoard = false; // 立即关闭当前输入界面回到当前单词
            });
            _doHandleTabChangeForAsr();
          }
          if (!wasAlreadyCorrect) {
            // 同步计算 FSRS 评分
            FsrsRating rating = FsrsRating.good; // 默认 Good
            int? rTime;
            if (_wordStartTime != null) {
              final timeToUse =
                  (_asrPassRuleCache == 'ALL' && _firstMatchTime != null)
                      ? _firstMatchTime!
                      : AppClock.now();
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

            if (_lowestRatingForCurrentWord == null) {
              _lowestRatingForCurrentWord = rating;
            } else {
              if (rating.index < _lowestRatingForCurrentWord!.index) {
                _lowestRatingForCurrentWord = rating;
              }
            }
            rating = _lowestRatingForCurrentWord!;

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
                final now = AppClock.now();
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
            SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
        _playingCorrectSounds.add(soundFuture);
        debugPrint(
            'checkAsrResult: 添加提示音到列表，当前有 ${_playingCorrectSounds.length} 个提示音正在播放');

        // 等待音频播放完成，然后再等待短暂延迟后执行后续逻辑
        soundFuture.whenComplete(() {
          Future.delayed(const Duration(milliseconds: 150)).then((_) async {
            _playingCorrectSounds.remove(soundFuture);
            if (_playingCorrectSounds.isEmpty && _hasFinishedAnswering) {
              if (wasAlreadyCorrect) return;

              if (_autoJumpAfterCorrect && _historyIndex == -1 && _lastFsrsRating != null) {
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

      // 判定逻辑：
      // 1. 严格字母匹配（忽略特殊符号如 - ' 空格，但字母必须 100% 一致）
      String filteredInput = inputText.replaceAll(RegExp(r'[^a-z]'), '');
      String filteredTarget = correctSpell.replaceAll(RegExp(r'[^a-z]'), '');
      bool isMatch = filteredInput == filteredTarget;

      Global.logger.d(
          'BDC CHECK_ASR [ch2En]: filteredInput="$filteredInput", filteredTarget="$filteredTarget", isMatch=$isMatch, isVoice=$isVoice');

      // 2. 只有语音输入才允许“音素相似度”兜底容错
      if (!isMatch &&
          isVoice &&
          _currentScore != null &&
          _currentScore! >= Constants.phonemeMatchThreshold) {
        Global.logger.d(
            'Ch2En (Voice): 拼写不匹配，但音素相似度达到阈值，判定通过');
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
            _doHandleTabChangeForAsr();
          }
          SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
          return;
        }

        _hasFinishedAnswering = true;

        // 计算 FSRS 评分
        FsrsRating rating = FsrsRating.good; // 默认 Good
        int? rTime;
        if (_wordStartTime != null) {
          final responseTime =
              AppClock.now().difference(_wordStartTime!).inSeconds;
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
                (_currentScore == null || _currentScore! >= 60)) {
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

        if (_lowestRatingForCurrentWord == null) {
          _lowestRatingForCurrentWord = rating;
        } else {
          if (rating.index < _lowestRatingForCurrentWord!.index) {
            _lowestRatingForCurrentWord = rating;
          }
        }
        rating = _lowestRatingForCurrentWord!;

        String reason = "回答耗时${rTime ?? '-'}秒";
        if (usedTranslation) {
          reason += "，查看了例句翻译";
        } else if (_hintTapCount > 0) {
          reason += "，查看提示$_hintTapCount次";
        }
        reason += "，评分: ${rating.label}";

        _lastFsrsRatingReason = reason;

        // 在调用 _onAnswerCorrect 前彻底停止当前识别会话，以便让UI层收到停止状态进而停止波浪动画。
        // 在 iOS 上必须同步等待停止完成，否则后续立即起播音频会产生资源争抢，导致听不到声音或大幅延迟。
        await asr.stopAsr();
        _onAnswerCorrect(rating);
      }
    }
  }



  /// 播放句子发音按钮处理函数

  getNextWord(bool gotoNext, {FsrsRating? fsrsRating}) async {
    final startTime = DateTime.now();
    Global.logger.d('[BDC Performance] === getNextWord 开始 ===');
    if (_isGettingNextWord) {
      Global.logger.d('getNextWord: 已经在获取中，跳过重复请求');
      return;
    }

    _saveCurrentWordState();

    // 历史模式处理
    if (_historyIndex != -1) {
      if (gotoNext) {
        // 在离开回看状态前，把用户最终改动的 FSRS 结果落库持久化
        final lw = _currentGetWordResult?.learningWord;
        if (lw != null && _fsrsItem != null && _lastFsrsRating != null) {
          StudyBo().saveHistoryFSRSUpdate(
            currWord: lw,
            nextFsrs: _fsrsItem!,
            newRating: _lastFsrsRating!,
          );
          _saveCurrentWordState();
          _persistLastWordHistoryItem();
        }

        _slideDirection = 1.0;
        _historyIndex++;
        if (_historyIndex >= _history.length) {
          // 回到“当前”状态
          _historyIndex = -1;

          _currentGetWordResult = _presentWord;
          handleWord(_currentGetWordResult);
          Global.logger.d('[BDC Performance] getNextWord(历史模式回退) 耗时: ${DateTime.now().difference(startTime).inMilliseconds} ms');
          return;
        } else {
          // 查看历史记录中的下一个
          _currentGetWordResult = _history[_historyIndex];
          handleWord(_currentGetWordResult);
          Global.logger.d('[BDC Performance] getNextWord(查看历史记录) 耗时: ${DateTime.now().difference(startTime).inMilliseconds} ms');
          return;
        }
      } else {
        // 刷新当前历史记录页 (不常见，但作为防御)
        _currentGetWordResult = _history[_historyIndex];
        handleWord(_currentGetWordResult);
        Global.logger.d('[BDC Performance] getNextWord(刷新当前历史) 耗时: ${DateTime.now().difference(startTime).inMilliseconds} ms');
        return;
      }
    }

    _isGettingNextWord = true;
    try {
      final stopAsrStartTime = DateTime.now();
      // 停止当前 ASR 任务并确保状态同步（Hot Stop 会在 Native 层处理，此处需保证状态为 Stopped）
      await asr.stopAsr();
      await asr.reset();
      _meaningFocusNode.unfocus();
      _showHandwritingBoard = false;
      _meaningController.text = '';
      _handlingChinese = '';
      _currentAsrCandidates = [];
      _firstMatchTime = null;
      _hintTapCount = 0;
      _highlightedWordImg = null;
      _wordImageEdited = false;
      Global.logger.d('[BDC Performance] getNextWord 停止 ASR 耗时: ${DateTime.now().difference(stopAsrStartTime).inMilliseconds} ms');

      // 如果要获取下一个单词，先将当前单词存入历史
      if (gotoNext && _currentGetWordResult != null) {
        _slideDirection = 1.0;
        // 只有非“已完成”且非“无词”的结果才存入历史
        if (!_currentGetWordResult!.finished && !_currentGetWordResult!.noWord) {
          _history.add(_currentGetWordResult!);
          
          // 持久化上一个单词
          _persistLastWordHistoryItem();

          if (_history.length > 20) {
            final removed = _history.removeAt(0);
            final removedId = removed.learningWord?.word.id;
            if (removedId != null) {
              _wordUIStates.remove(removedId);
            }
          }
        }
      }

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
        final apiStartTime = DateTime.now();
        final result = await StudyBo()
            .getWord(_isWordMastered, actualGotoNext, fsrsRating: fsrsRating);
        Global.logger.d('[BDC Performance] StudyBo().getWord 接口耗时: ${DateTime.now().difference(apiStartTime).inMilliseconds} ms');
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

      final handleStartTime = DateTime.now();
      handleWord(_currentGetWordResult,
          isFromBatchWordList: isFromBatchWordList);
      Global.logger.d('[BDC Performance] getNextWord 调用 handleWord 启动耗时(异步开始): ${DateTime.now().difference(handleStartTime).inMilliseconds} ms');
    } catch (e, stackTrace) {
      Global.logger.e('获取下一个单词时发生异常', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
        // 显示错误提示，并提供重试按钮
        _showErrorWidget('加载单词失败: ${e.toString()}');
      }
    } finally {
      _isGettingNextWord = false;
      Global.logger.d('[BDC Performance] === getNextWord 结束，总耗时: ${DateTime.now().difference(startTime).inMilliseconds} ms ===');
    }
  }

  _goToPreviousWord() async {
    if (_history.isEmpty) return;

    _saveCurrentWordState();

    // 停止当前任务的 ASR 和发音
    await asr.stopAsr();
    await _audioPlayer.stop();

    _slideDirection = -1.0;

    if (_historyIndex == -1) {
      // 从“当前”进入历史模式
      _presentWord = _currentGetWordResult;

      _historyIndex = _history.length - 1;
    } else if (_historyIndex > 0) {
      // 在历史中继续向后回退
      _historyIndex--;
    } else {
      // 已经到历史最顶端
      return;
    }

    _currentGetWordResult = _history[_historyIndex];
    handleWord(_currentGetWordResult);
  }

  /// 显示错误提示界面，提供重试和返回选项

  /// 播放单词和第一个例句


  /// 初始化选择题数据

  final email = TextEditingController();





  Widget renderPage() {
    if (_word == null) {
      return Container();
    }

    if (_showHandwritingBoard || _meaningFocusNode.hasFocus) {
      return _buildFullscreenImmersiveInputMode();
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (details) {},
                onHorizontalDragEnd: (details) {},
                child: _buildMainContent(),
              ),
            ),
            _buildBottomButtons(),
          ],
        ),
        if (_historyIndex != -1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  bottom: 2,
                  left: 20,
                  right: 20),
              color: Colors.orange.withValues(alpha: 0.9),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        '回顾模式',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '-${_history.length - _historyIndex}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 构建全屏沉浸式输入模式（支持手写和键盘）
  /// 构建全屏沉浸式输入模式（支持手写和键盘）

  /// 构建题目内容区域

  /// 构建TabBar

  /// 构建主要内容区域

  /// 构建底部按钮


  resetHighlightedWordImg() {
    setState(() {
      _highlightedWordImg = null;
    });
  }


  /// 放大单词配图对话框




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
            AppClock.now().difference(_wordStartTime!).inSeconds;
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

      if (_lowestRatingForCurrentWord == null) {
        _lowestRatingForCurrentWord = rating;
      } else {
        if (rating.index < _lowestRatingForCurrentWord!.index) {
          _lowestRatingForCurrentWord = rating;
        }
      }
      rating = _lowestRatingForCurrentWord!;

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
      if (_lowestRatingForCurrentWord == null) {
        _lowestRatingForCurrentWord = FsrsRating.again;
      } else {
        if (FsrsRating.again.index < _lowestRatingForCurrentWord!.index) {
          _lowestRatingForCurrentWord = FsrsRating.again;
        }
      }
      //不认识或答案错误（错误提示音不需要等待，因为不会跳转到下一个单词）
      SoundUtil.playAssetSoundConcurrent('failed.mp3', 1.5, 1.0);
      showWordDetail(_word!, true,
          fsrsRating: _lowestRatingForCurrentWord, reason: "选错了答案，评分: 忘记"); // 传递true表示本次回答错误
    }
  }

  showWordDetail(var word, bool isAnswerWrong, {FsrsRating? fsrsRating, String? reason}) async {
    // 本次如果确定有评分（如选择了不认识），就算还未跳转下一题，也应立刻结算本地 FSRS 预览，让用户在返回时可以看到评分状态。
    if (fsrsRating != null) {
      if (_lowestRatingForCurrentWord == null) {
        _lowestRatingForCurrentWord = fsrsRating;
      } else {
        if (fsrsRating.index < _lowestRatingForCurrentWord!.index) {
          _lowestRatingForCurrentWord = fsrsRating;
        }
      }
      _lastFsrsRating = _lowestRatingForCurrentWord;
      _lastFsrsRatingReason = reason ?? "系统判定错误或不熟，评分: ${_lowestRatingForCurrentWord!.label}";
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
          final now = AppClock.now();
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

    var bottomBtn = ElevatedButton(
      style: ElevatedButton.styleFrom(
        foregroundColor: context.read<DarkMode>().isDarkMode
            ? Colors.black
            : Colors.white,
        backgroundColor: context.read<DarkMode>().isDarkMode
            ? Colors.white
            : AppTheme.primaryColor,
        minimumSize: const Size(double.infinity, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {
        Get.back();
        getNextWord(true, fsrsRating: fsrsRating);
      },
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: 0,
            child: Icon(Icons.arrow_forward, size: 20),
          ),
          Expanded(
            child: Text(
              '下一词',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Icon(Icons.arrow_forward, size: 20),
        ],
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









  /// 构建拼写练习按钮






  /// 音标行

  /// 题目区的例句行(单词的第一个例句)



  /// 隐藏括号内的内容，避免在"中→英"模式下暴露答案

  /// 隐藏答案按钮中可能暴露答案的内容

  /// 显示调试浮窗，查看今日取词状态

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
