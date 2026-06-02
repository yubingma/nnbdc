import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/util/asr.dart';
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
import '../../theme/app_theme.dart';
import '../../util/analytics_util.dart';
import '../../util/app_clock.dart';
import '../../util/learning_service.dart';
import '../../util/study_config.dart';
import '../../util/performance_watchdog.dart';
import '../../util/utils.dart';
import '../../widget/handwriting_board.dart';
import 'providers/bdc_notifier.dart';
import 'providers/bdc_state.dart';
import "widgets/chinese_asr_input_widget.dart";
import "widgets/english_asr_input_widget.dart";
import "widgets/word_images_widget.dart";

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
  static const int batchSize = 10;
  
  var errorReportController = TextEditingController();
  
  /// 释义输入框焦点控制
  final FocusNode _meaningFocusNode = FocusNode();

  /// 顶级音频播放器，委托给全局控制器维护的单例实例
  ja.AudioPlayer get _audioPlayer => StudyAudioSessionController.instance.primaryPlayer;

  /// 说意/英拼写面板的滚动控制
  final ScrollController _speakPanelScrollController = ScrollController();

  // 底部按钮实际高度，用于为做题区内容预留空间，避免被遮挡
  final GlobalKey _bottomButtonsKey = GlobalKey();

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
    
    // 静默加载并预热手写识别模型，避免进入手写板写完第一笔后产生首次识别延迟
    OcrService.prepareModel();
    
    // Initialize TabController with a default length
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
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
              if (!_tabController!.indexIsChanging) {
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

    // Meaning focus listener
    _meaningFocusNode.addListener(() {
      if (!mounted) return;
      final notifier = ref.read(bdcNotifierProvider.notifier);
      if (_meaningFocusNode.hasFocus) {
        Global.logger.d('BDC: 输入框获取焦点，停止 ASR');
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
  }

  @override
  void dispose() {
    _keyboardSubscription.cancel();
    _tabController?.dispose();
    _meaningFocusNode.dispose();
    _speakPanelScrollController.dispose();
    _soundController.dispose();
    _wordSoundController.dispose();
    _sentenceSoundController.dispose();

    super.dispose();
    }
  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    // 缓存当前主题，子组件直接用缓存值，避免 48 处 context.watch
    _cachedIsDarkMode = context.watch<DarkMode>().isDarkMode;
    // 顶级只监听加载状态，不再监听具体单词细节
    ref.watch(bdcNotifierProvider.select((s) => s.dataLoaded));

    // 获取一份不含高频更新字段的稳定状态供主框架结构使用
    final state = ref.watch(bdcNotifierProvider.select((s) => s.copyWith(
      asrResult: '',
      asrState: AsrState.unknown,
      currentAsrCandidates: const [],
      asrPassRuleCache: '',
      playingStates: const {'word': false, 'sentence': false},
      currentScore: 0,
      meaningText: '',
      hintTapCount: 0,
    )));

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
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: null,
        body: Container(
          color: _cachedIsDarkMode
              ? const Color(0xFF121212)
              : Colors.white,
          child: pageContent,
        ),
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

    if (state.showHandwritingBoard || (_meaningFocusNode.hasFocus && !state.hasFinishedAnswering)) {
      final res = _buildFullscreenImmersiveInputMode();
      debugPrint('⚡ [PERF] BdcPage.renderPage (immersive) cost: ${stopwatch.elapsedMilliseconds}ms');
      return res;
    }

    final res = Stack(
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
      ],
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
