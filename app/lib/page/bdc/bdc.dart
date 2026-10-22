import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/meaning_render_util.dart';
import 'package:provider/provider.dart' hide Consumer;

import '../../api/enum.dart';
import '../../api/vo.dart';
import '../../config.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../state.dart';
import '../../event/events.dart';
import '../../services/level_service.dart';
import '../../theme/app_theme.dart';
import '../../util/analytics_util.dart';
import '../../util/app_clock.dart';
import '../../util/client_error_reporter.dart';
import '../../util/learning_service.dart';
import '../../util/study_config.dart';
import '../../util/study_steps_service.dart';
import '../../util/study_track.dart';
import '../../util/performance_watchdog.dart';
import '../../util/phase_presentation_tracker.dart';
import '../../util/prefs.dart';
import '../../util/utils.dart';
import '../../widget/handwriting_board.dart';
import '../../widget/data_missing_guide.dart';
import '../../widget/learning_history_dialog.dart';
import '../../widget/pronunciation_accent_badge.dart';
import '../../widget/sound_wave_icon.dart';
import '../../widget/pronunciation_accent_dialog.dart';
import '../../widget/minimal_flow_button.dart';
import '../../widget/theme_select_dialog.dart';
import 'providers/answer_mode.dart';
import 'providers/bdc_notifier.dart';
import 'providers/bdc_state.dart';
import 'providers/bdc_state_ui_signature.dart';
import "widgets/chinese_asr_input_widget.dart";
import "widgets/english_asr_input_widget.dart";
import "widgets/word_images_widget.dart";
import "widgets/study_guide_overlay.dart";
import "widgets/mastered_fly_animation.dart";

part 'dialogs/bdc_dialogs.dart';
part 'widgets/bdc_ui_components.dart';

class BdcPage extends ConsumerStatefulWidget {
  const BdcPage({super.key});

  @override
  BdcPageState createState() {
    return BdcPageState();
  }
}

class BdcPageState extends ConsumerState<BdcPage> with TickerProviderStateMixin {
  /// 缓存当前渲染帧的状态快照，供非 build 期的事件回调安全读取，消除非 build 期 ref.watch 隐患
  BdcState? _activeState;

  /// 用于给 extension 中的方法调用，避免使用 setState 时出现 lint错误
  int _buildCount = 0;
  String _lastSetStateTag = 'init';
  void updateUI(VoidCallback fn, {String tag = 'unknown'}) {
    _lastSetStateTag = tag;
    if (mounted) setState(fn);
  }

  /// 缓存当前主题模式，避免 48 处 `DarkMode` watch 重复注册
  late bool _cachedIsDarkMode;

  static const double leftPadding = 16;
  static const double rightPadding = 16;
  
  var errorReportController = TextEditingController();
  
  /// 释义输入框焦点控制
  final FocusNode _meaningFocusNode = FocusNode();

  /// 手写板状态 key：键盘手动编辑输入框时，用于清掉手写板的"提前回显"预览，
  /// 避免用户用键盘删掉文字后又被手写预览回填。
  final GlobalKey<HandwritingBoardState> _handwritingBoardKey =
      GlobalKey<HandwritingBoardState>();

  /// 例句答案区(可编辑识别结果)焦点控制
  final FocusNode _sentenceAnswerFocusNode = FocusNode();

  /// 顶级音频播放器，委托给全局控制器维护的单例实例
  ja.AudioPlayer get _audioPlayer => StudyAudioSessionController.instance.primaryPlayer;

  /// 说意/英拼写面板的滚动控制
  final ScrollController _speakPanelScrollController = ScrollController();

  /// 新手引导：遮罩层自身 / 「正在倾听」语音识别区 的锚点
  final GlobalKey _guideOverlayKey = GlobalKey();
  final GlobalKey _asrListeningKey = GlobalKey();

  /// 掌握动画：顶部掌握小按钮锚点与单词拼写锚点
  final GlobalKey _masteredButtonKey = GlobalKey();
  final GlobalKey _wordSpellKey = GlobalKey();

  /// 掌握动效：题目区向中心坍缩凝聚的控制器与动画
  late final AnimationController _questionCollapseController;
  late final Animation<double> _questionCollapseScaleAnimation;
  late final Animation<double> _questionCollapseOpacityAnimation;

  /// 掌握小按钮受击时的弹跳反馈控制器
  late final AnimationController _masteredButtonScaleController;
  late final Animation<double> _masteredButtonScaleAnimation;
  BdcNotifier? _notifierRef;

  /// 是否正在展示新手引导（首次进入学习页自动展示，也可从设置里再次打开）
  bool _showStudyGuide = false;

  /// 本次进入页面是否已做过新手引导检查（避免重复查库与重复弹出）
  bool _studyGuideChecked = false;

  // 题目区和做题区之间的统一间距
  static const double _questionAnswerGap = 8.0;

  /// 控制做题区、题目区和底部按钮的边框是否显示
  final bool _showBorders = false;

  late AnimationController _soundController;
  late AnimationController _wordSoundController;
  late AnimationController _sentenceSoundController;

  /// Tab控制器，用于管理说/选两个tab
  TabController? _tabController;

  late StreamSubscription _keyboardSubscription;

  @override
  void initState() {
    super.initState();
    
    // 答题期间不打断用户: 段位晋升仪式延迟到本次学习结束时补办
    LevelService().enterStudy();

    // 静默加载并预热手写识别模型，避免进入手写板写完第一笔后产生首次识别延迟
    OcrService.prepareModel();
    
    // 答题卡档数＝这个环节的答题方式（写/说/选），进来时先按"还不知道环节"算一次
    _tabController =
        TabController(length: AnswerModes.forStep(null).length, vsync: this);
    _tabController!.addListener(_onTabControllerChanged);

    // 档位一变，TabController 跟着切到对应那一档
    ref.listenManual(bdcNotifierProvider.select((s) => s.answerMode), (previous, next) {
      final BdcState current = ref.read(bdcNotifierProvider);
      final int target = AnswerModes.indexOf(current.studyStep, next);
      if (_tabController != null &&
          _tabController!.index != target &&
          target < _tabController!.length) {
        _tabController!.animateTo(target);
      }
    });
    
    // 监听答题完成状态，自动收起键盘/手写板，从而退出沉浸式拼写模式。
    // 写档的输入框例外：键盘要留在原地，下一词直接接着打。
    ref.listenManual(bdcNotifierProvider.select((s) => s.hasFinishedAnswering), (previous, next) {
      if (next == true &&
          ref.read(bdcNotifierProvider).answerMode != AnswerMode.write) {
        _meaningFocusNode.unfocus();
      }
    });

    // 监听手写板开启状态，当手写板主动关闭时，也务必收起键盘并退出沉浸式模式
    ref.listenManual(bdcNotifierProvider.select((s) => s.showHandwritingBoard), (previous, next) {
      if (next == false && previous == true) {
        _meaningFocusNode.unfocus();
      }
    });

    // Initialize data and listen for state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(bdcNotifierProvider.notifier).loadData(context);
    });

    // 监听当前学习单词切换：新词入场时立即平滑复原题目区坍缩动画，呈现新题
    ref.listenManual(bdcNotifierProvider.select((s) => s.word?.id), (previous, next) {
      if (previous != null && next != null && previous != next) {
        if (_questionCollapseController.value > 0) {
          _questionCollapseController.reset();
        }
      }
    });

    // 数据就绪后检查新手引导（首次进入学习页自动展示一次）
    ref.listenManual(bdcNotifierProvider.select((s) => s.dataLoaded),
        (previous, next) {
      if (next == true) _checkStudyGuide();
    }, fireImmediately: true);

    // 档数随环节变：单词环节写/说/选三档，例句环节只有说/选。
    // 档数一变就得换一个 TabController，否则 TabBarView 会越界。
    ref.listenManual(
        bdcNotifierProvider
            .select((s) => AnswerModes.forStep(s.studyStep).length),
        (previous, next) {
      if (_tabController?.length == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        updateUI(() => _resetTabController(next), tag: 'tab-recreate');
      });
    });

    // Animation controllers
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _sentenceSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // 监听发音状态，驱动喇叭声波扩散呼吸律动动画
    ref.listenManual(
      bdcNotifierProvider.select((s) => s.playingStates['word'] ?? false),
      (prev, next) {
        if (!mounted) return;
        if (next == true) {
          _wordSoundController.repeat();
        } else {
          _wordSoundController.stop();
          _wordSoundController.reset();
        }
      },
      fireImmediately: true,
    );

    ref.listenManual(
      bdcNotifierProvider.select((s) => s.playingStates['sentence'] ?? false),
      (prev, next) {
        if (!mounted) return;
        if (next == true) {
          _sentenceSoundController.repeat();
        } else {
          _sentenceSoundController.stop();
          _sentenceSoundController.reset();
        }
      },
      fireImmediately: true,
    );

    // Meaning focus listener
    _meaningFocusNode.addListener(() {
      if (!mounted) return;
      final notifier = ref.read(bdcNotifierProvider.notifier);
      if (_meaningFocusNode.hasFocus) {
        Global.logger.d('BDC: 输入框获取焦点，停止 ASR');
        // 用户切到键盘输入：清掉手写板提前回显预览，避免删改后又被手写预览回填
        _handwritingBoardKey.currentState?.clearHandwritingPreview();
        notifier.asr.stopMicrophone();

        final config = StudyConfig.fromCurrentUser();
        if (!config.preferKeyboardInSpelling) {
          config.preferKeyboardInSpelling = true;
          config.saveToCurrentUser();
        }
      } else {
        Global.logger.d('BDC: 输入框失去焦点，尝试恢复 ASR');
        notifier.handleTabChangeForAsr();
      }
      
      // 使用 addPostFrameCallback 延迟 setState，避免在键盘事件处理过程中
      // 立即改变 Widget 树导致 HardwareKeyboard 状态断言错误（如 Enter 键重复触发）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updateUI(() {}, tag: 'focus-change');
      });
    });

    // Keyboard visibility listener
    var keyboardVisibilityController = KeyboardVisibilityController();
    _keyboardSubscription = keyboardVisibilityController.onChange.listen((bool visible) {
      ref.read(bdcNotifierProvider.notifier).updateKeyboardVisibility(visible);
      updateUI(() {}, tag: 'keyboard-vis');
    });

    _soundController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _questionCollapseController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _questionCollapseScaleAnimation = Tween<double>(begin: 1.0, end: 0.02).animate(
      CurvedAnimation(
        parent: _questionCollapseController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _questionCollapseOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _questionCollapseController,
        curve: Curves.easeInQuad,
      ),
    );

    _masteredButtonScaleController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _masteredButtonScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 55,
      ),
    ]).animate(_masteredButtonScaleController);

    // 绑定掌握毕业飞行动画回调
    _notifierRef = ref.read(bdcNotifierProvider.notifier);
    _notifierRef?.onWordMasteredGraduated = playMasteredFlyAnimation;
  }

  @override
  void dispose() {
    _notifierRef?.onWordMasteredGraduated = null;
    _notifierRef = null;
    _keyboardSubscription.cancel();
    _tabController?.dispose();
    _meaningFocusNode.dispose();
    _sentenceAnswerFocusNode.dispose();
    _speakPanelScrollController.dispose();
    _soundController.dispose();
    _wordSoundController.dispose();
    _sentenceSoundController.dispose();
    _questionCollapseController.dispose();
    _masteredButtonScaleController.dispose();

    // 本次学习结束或中途退出, 补办答题期间被延迟的晋升仪式
    LevelService().leaveStudy();

    // 无论是学完退出还是中途返回，发布学习列表进度变化事件，确保计划页刷新最新学习状态
    EventBus.publishTodayStudyListChanged(const TodayStudyListChangedEvent());

    super.dispose();
  }

  /// 播放单词掌握动画：题目区先向中心坍缩凝聚成微核，随后从凝聚中心破茧凝结出掌握胶囊飞向右上角掌握按钮
  Future<void> playMasteredFlyAnimation(String spell) async {
    if (!mounted || spell.isEmpty) return;

    // 第一阶段：题目区向中心深度坍缩凝聚为微核 (200ms)
    await _questionCollapseController.forward(from: 0.0);
    if (!mounted) return;

    // 破茧绽放瞬间：播放泡泡爆破回馈音效 (bubble-pop.wav)，视听 100% 毫秒级同步爆发
    StudyBo.playMasteredBubbleSound();

    // 第二阶段：在凝聚中心破茧生成掌握胶囊，带流光轨迹飞向右上角掌握按钮
    final completer = Completer<void>();
    MasteredFlyAnimation.play(
      context: context,
      spell: spell,
      startKey: _wordSpellKey,
      targetKey: _masteredButtonKey,
      onArrived: () {
        if (!mounted) return;
        _masteredButtonScaleController.forward(from: 0.0);
        if (!completer.isCompleted) completer.complete();
      },
    );

    // 等待飞行动效抵达目标完成吸收（超时安全保护兜底，时长 500ms）
    await completer.future.timeout(const Duration(milliseconds: 500), onTimeout: () {});

    // 兜底保护：若因特殊情况新词未加载或流转中断，在动效彻底结束后平滑复原题目区，避免永久坍缩
    if (mounted && _questionCollapseController.value > 0) {
      _questionCollapseController.reset();
    }
  }

  /// 首次进入学习页时展示新手引导：只讲「你说，我来听」这一件事，
  /// 其余功能留给用户自己探索。
  Future<void> _checkStudyGuide() async {
    if (_studyGuideChecked) return;
    _studyGuideChecked = true;
    // 引导只讲开口说：平台不支持语音识别、或用户这会儿是用「写/选」答题时，弹出来只会误导
    if (!PlatformUtils.isAsrSupported()) return;
    if (ref.read(bdcNotifierProvider).answerMode != AnswerMode.speak) return;
    final cacheKey = 'bdcStudyGuideShown_${Global.currentUserId}';
    try {
      if (Prefs.read<bool>(cacheKey) == true) return;
      final stored = await MyDatabase.instance.localParamsDao.getValue(cacheKey);
      if (stored == 'true') {
        Prefs.write(cacheKey, true);
        return;
      }
      if (!mounted) return;
      // 当前没有在学的单词（学习已完成/无词可学）时不展示：引导没有锚点
      if (ref.read(bdcNotifierProvider).word == null) return;
      startStudyGuide();
    } catch (e) {
      Global.logger.e('新手引导检查失败: $e');
    }
  }

  /// 展示学习引导（首次自动触发；设置弹窗的「学习引导」入口也走这里）
  void startStudyGuide() {
    // 引导遮住页面时先停掉语音识别：此时用户说话不该被识别判分
    ref.read(bdcNotifierProvider.notifier).setGuideShowing(true);
    updateUI(() => _showStudyGuide = true, tag: 'study-guide');
  }

  /// 关闭学习引导并记为已看过（不再自动弹出）
  Future<void> _finishStudyGuide() async {
    updateUI(() => _showStudyGuide = false, tag: 'study-guide-done');
    ref.read(bdcNotifierProvider.notifier).setGuideShowing(false);
    final cacheKey = 'bdcStudyGuideShown_${Global.currentUserId}';
    Prefs.write(cacheKey, true);
    try {
      await MyDatabase.instance.localParamsDao.setValue(cacheKey, 'true');
    } catch (e) {
      Global.logger.e('新手引导标记保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    // 缓存当前主题，子组件直接用缓存值，避免 48 处 context.watch
    _cachedIsDarkMode = context.watch<DarkMode>().isDarkMode;
    // 顶级只监听加载状态，不再监听具体单词细节
    ref.watch(bdcNotifierProvider.select((s) => s.dataLoaded));

    // 极致优化：使用轻量化比对签名对象控制顶层 build 刷新时机，避免昂贵的大集合深比较
    ref.watch(bdcNotifierProvider.select((s) => BdcStateUiSignature(s)));
    final state = ref.read(bdcNotifierProvider);
    _activeState = state;

    {
      final int expectedTabLength = AnswerModes.forStep(state.studyStep).length;
      if (_tabController == null || _tabController!.length != expectedTabLength) {
        _resetTabController(expectedTabLength);
      }
    }

    final isDesktop = PlatformUtils.isDesktop;
    const double maxContentWidth = 600.0;

    Widget pageContent = (!state.dataLoaded) 
        ? _buildLoadingPage() 
        : renderPage(state);

    if (isDesktop) {
      pageContent = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: pageContent,
        ),
      );
    }

    final result = KeyboardDismissOnTap(
      child: AppScaffold(
        body: pageContent,
      ),
    );
    _buildCount++;
    final buildNum = _buildCount;
    debugPrint('⚡ [PERF] BdcPage.build #$buildNum (trigger: $_lastSetStateTag) cost: ${stopwatch.elapsedMilliseconds}ms');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('⚡ [PERF] BdcPage.frame #$buildNum painted');
    });
    return result;
  }

  Widget renderPage(BdcState state) {
    final stopwatch = Stopwatch()..start();

    if (state.loadError != null || state.word == null) {
      final isRedirecting = state.loadError?.contains('跳转') ?? false;

      if (isRedirecting) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                state.loadError!,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      // 通用释义缺失：重试必然再次失败，只能靠补数据或重建本地数据解决
      final cause = state.loadErrorCause;
      if (cause is MissingCommonMeaningException) {
        return Center(
          child: MissingMeaningGuide(
            wordSpell: cause.spell,
            onRetry: () => ref.read(bdcNotifierProvider.notifier).loadData(context),
            onBack: () => Navigator.of(context).pop(),
          ),
        );
      }

      // 轨道里有本版本不支持的环节：重试同样必然失败（配置没变），只给返回这一条出路
      if (cause is UnsupportedStudyStepException) {
        return _buildUnsupportedStepGuide(cause);
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              state.loadError ?? '暂无正在学习的单词',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.read(bdcNotifierProvider.notifier).loadData(context),
              child: const Text('重试'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    // 答题卡内的键盘输入框本身就是答题面：它拿到焦点时必须留在原页面，
    // 不能被"输入框有焦点就进全屏拼写板"的旧判据抢走（那是说面板点输入框时的老路径）。
    final bool typingPanelShown = state.answerMode == AnswerMode.write;
    final isImmersive = state.showHandwritingBoard ||
        (_meaningFocusNode.hasFocus &&
            !state.hasFinishedAnswering &&
            !typingPanelShown);

    final mainContent = Stack(
      children: [
        Column(
          children: [
            // 回看横幅参与正常布局（不再用 Positioned 悬浮覆盖）：横幅多高，下方内容就下移多少，
            // 「返回/掌握/更多」这一行永远落在横幅之下 —— 大字号下横幅变高同样压不到按钮。
            if (state.historyIndex != -1) _buildReviewBanner(),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (details) {},
                onHorizontalDragEnd: (details) {},
                child: RepaintBoundary(
                  child: _buildMainContent(),
                ),
              ),
            ),
            RepaintBoundary(
              child: _buildBottomButtons(),
            ),
          ],
        ),
        // 新手引导：只讲「你说，我来听」（首次进入学习页自动展示，遮罩吸收点击）
        if (_showStudyGuide)
          Positioned.fill(
            child: StudyGuideOverlay(
              overlayKey: _guideOverlayKey,
              targetKey: _asrListeningKey,
              title: '你说，我来听',
              text: studyGuideTextFor(StudyStepExt.fromString(state.studyStep ?? '')),
              onFinish: _finishStudyGuide,
            ),
          ),
      ],
    );

    final res = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isCurrent = child.key ==
            ValueKey(isImmersive ? 'immersive_mode' : 'main_mode');
        return IgnorePointer(
          ignoring: !isCurrent,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: isImmersive
          ? KeyedSubtree(
              key: const ValueKey('immersive_mode'),
              child: _buildFullscreenImmersiveInputMode(),
            )
          : KeyedSubtree(
              key: const ValueKey('main_mode'),
              child: mainContent,
            ),
    );

    debugPrint('⚡ [PERF] BdcPage.renderPage cost: ${stopwatch.elapsedMilliseconds}ms');
    return res;
  }

  /// 轨道里有本版本不支持的环节：说清是哪个环节、给出唯一可行的出路（去升级）
  Widget _buildUnsupportedStepGuide(UnsupportedStudyStepException cause) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.system_update_alt_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '这个学习环节需要升级 App',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              '这个词的轨道里有本版本不支持的环节（${cause.steps.join('、')}）。'
              '升级到最新版本后即可继续学习。',
              style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回今日计划'),
            ),
          ],
        ),
      ),
    );
  }

  /// 回看模式横幅：橙色横条自带状态栏内边距，一直铺到状态栏底下，文字落在状态栏下方。
  /// 它按普通子组件参与 Column 布局，高度由自身内容决定，不再悬浮压住下方内容。
  Widget _buildReviewBanner() {
    return Container(
      key: const Key('review_mode_banner'),
      width: double.infinity,
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          bottom: 2,
          left: 20,
          right: 20),
      color: Colors.orange.withValues(alpha: 0.9),
      child: const Center(
        child: Text(
          '回看模式',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  void _onTabControllerChanged() {
    final TabController? controller = _tabController;
    if (controller == null) return;
    final BdcState current = ref.read(bdcNotifierProvider);
    final List<AnswerMode> modes = AnswerModes.forStep(current.studyStep);
    if (controller.index >= modes.length) return;
    final AnswerMode mode = modes[controller.index];
    if (mode != current.answerMode) {
      ref.read(bdcNotifierProvider.notifier).updateAnswerMode(mode);
    }
  }

  /// 换一个档数不同的 TabController：档数永远是唯一的入口，监听器也只在这里挂一次。
  void _resetTabController(int length) {
    final BdcState current = ref.read(bdcNotifierProvider);
    final int initialIndex = AnswerModes.indexOf(
        current.studyStep, AnswerModes.coerce(current.studyStep, current.answerMode));
    _tabController?.dispose();
    _tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: initialIndex < length ? initialIndex : length - 1);
    _tabController!.addListener(_onTabControllerChanged);
  }
}
