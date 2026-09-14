import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column, Table;
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
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/util/ocr_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart' hide Consumer;

import '../../api/enum.dart';
import '../../api/vo.dart';
import '../../config.dart';
import '../../constants.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../state.dart';
import '../../event/events.dart';
import '../../services/level_service.dart';
import '../../theme/app_theme.dart';
import '../../util/analytics_util.dart';
import '../../util/app_clock.dart';
import '../../util/learning_service.dart';
import '../../util/study_config.dart';
import '../../util/study_steps_service.dart';
import '../../util/study_track.dart';
import '../../util/performance_watchdog.dart';
import '../../util/prefs.dart';
import '../../util/utils.dart';
import '../../widget/handwriting_board.dart';
import '../../widget/learning_history_dialog.dart';
import '../../widget/pronunciation_accent_badge.dart';
import '../../widget/sound_wave_icon.dart';
import '../../widget/pronunciation_accent_dialog.dart';
import '../../widget/minimal_flow_button.dart';
import '../../widget/theme_select_dialog.dart';
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
    
    // Initialize TabController with a default length
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      if (_tabController!.index != ref.read(bdcNotifierProvider).tabIndex) {
        ref.read(bdcNotifierProvider.notifier).updateTabIndex(_tabController!.index);
      }
    });

    // Sync state tabIndex to controller
    ref.listenManual(bdcNotifierProvider.select((s) => s.tabIndex), (previous, next) {
      if (_tabController != null && _tabController!.index != next && next < _tabController!.length) {
        _tabController!.animateTo(next);
      }
    });
    
    // 监听答题完成状态，自动收起键盘/手写板，从而退出沉浸式拼写模式
    ref.listenManual(bdcNotifierProvider.select((s) => s.hasFinishedAnswering), (previous, next) {
      if (next == true) {
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
      ref.read(bdcNotifierProvider.notifier).loadData(context);
    });

    // 数据就绪后检查新手引导（首次进入学习页自动展示一次）
    ref.listenManual(bdcNotifierProvider.select((s) => s.dataLoaded),
        (previous, next) {
      if (next == true) _checkStudyGuide();
    }, fireImmediately: true);

    // Listen for studyStep changes to update TabController length safely
    ref.listenManual(bdcNotifierProvider.select((s) => _getShouldShowSpeakTab(s)), (previous, next) {
      final newLength = next ? 2 : 1;
      if (_tabController?.length != newLength) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          updateUI(() {
            _tabController?.dispose();
            _tabController = TabController(length: newLength, vsync: this);
            _tabController!.addListener(() {
              if (_tabController!.index != ref.read(bdcNotifierProvider).tabIndex) {
                ref.read(bdcNotifierProvider.notifier).updateTabIndex(_tabController!.index);
              }
            });
            // Re-sync after recreation
            final currentTabIndex = ref.read(bdcNotifierProvider).tabIndex;
            if (currentTabIndex < newLength) {
              _tabController!.index = currentTabIndex;
            }
          }, tag: 'tab-recreate');
        });
      }
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
      duration: const Duration(milliseconds: 200),
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
      duration: const Duration(milliseconds: 260),
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
  void playMasteredFlyAnimation(String spell) async {
    if (!mounted || spell.isEmpty) return;

    // 第一阶段：题目区向中心深度坍缩凝聚为微核 (200ms)
    await _questionCollapseController.forward(from: 0.0);
    if (!mounted) return;

    // 第二阶段：在凝聚中心破茧生成掌握胶囊，带流光轨迹飞向右上角掌握按钮
    MasteredFlyAnimation.play(
      context: context,
      spell: spell,
      startKey: _wordSpellKey,
      targetKey: _masteredButtonKey,
      onArrived: () {
        if (!mounted) return;
        _masteredButtonScaleController.forward(from: 0.0);
      },
    );

    // 第三阶段：等待胶囊飞离中心一段距离后（260ms），平滑复原题目区以迎接新内容
    await Future.delayed(const Duration(milliseconds: 260));
    if (mounted) {
      _questionCollapseController.reset();
    }
  }

  /// 首次进入学习页时展示新手引导：只讲「你说，我来听」这一件事，
  /// 其余功能留给用户自己探索。
  Future<void> _checkStudyGuide() async {
    if (_studyGuideChecked) return;
    _studyGuideChecked = true;
    // 引导只讲开口说，平台不支持语音识别时弹出来只会误导
    if (!PlatformUtils.isAsrSupported()) return;
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
      int expectedTabLength = _getShouldShowSpeakTab(state) ? 2 : 1;
      if (_tabController == null || _tabController!.length != expectedTabLength) {
        _tabController?.dispose();
        _tabController = TabController(length: expectedTabLength, vsync: this);
      }
    }

    final isDesktop = PlatformUtils.isWindows || PlatformUtils.isLinux || PlatformUtils.isMacOS;
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

    final isImmersive = state.showHandwritingBoard ||
        (_meaningFocusNode.hasFocus && !state.hasFinishedAnswering);

    final mainContent = Stack(
      children: [
        Column(
          children: [
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
        if (state.historyIndex != -1)
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
                        '-${state.history.length - state.historyIndex}',
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

  bool _getShouldShowSpeakTab(BdcState state) {
    if (!PlatformUtils.isAsrSupported()) return false;
    if (state.studyStep == StudyStep.ch2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    return true;
  }
}
