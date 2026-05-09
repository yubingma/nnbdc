import 'dart:async';
import 'dart:core';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';

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
  void updateUI(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  static const double leftPadding = 16;
  static const double rightPadding = 16;
  static const int batchSize = 10;
  
  var errorReportController = TextEditingController();
  
  /// 释义输入框焦点控制
  final FocusNode _meaningFocusNode = FocusNode();

  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();

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
    
    // Initialize TabController with a default length
    _tabController = TabController(length: 2, vsync: this);

    // Initialize data and listen for state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bdcNotifierProvider.notifier).loadData(context);
    });

    // Listen for studyStep changes to update TabController length safely
    ref.listenManual(bdcNotifierProvider.select((s) => _getShouldShowSpeakTab(s)), (previous, next) {
      final newLength = next ? 2 : 1;
      if (_tabController?.length != newLength) {
        setState(() {
          _tabController?.dispose();
          _tabController = TabController(length: newLength, vsync: this);
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
      final notifier = ref.read(bdcNotifierProvider.notifier);
      if (_meaningFocusNode.hasFocus) {
        Global.logger.d('BDC: 输入框获取焦点，停止 ASR');
        notifier.asr.stopMicrophone();

        final config = StudyConfig.fromCurrentUser();
        if (!config.preferKeyboardInSpelling) {
          config.preferKeyboardInSpelling = true;
          config.saveToCurrentUser();
        }
      }
      setState(() {});
    });

    // Keyboard visibility listener
    var keyboardVisibilityController = KeyboardVisibilityController();
    _keyboardSubscription = keyboardVisibilityController.onChange.listen((bool visible) {
      ref.read(bdcNotifierProvider.notifier).updateKeyboardVisibility(visible);
      setState(() {});
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
    
    _audioPlayer.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bdcNotifierProvider);
    
    if (_tabController == null) {
      int expectedTabLength = _getShouldShowSpeakTab(state) ? 2 : 1;
      _tabController = TabController(length: expectedTabLength, vsync: this);
    }

    final isDesktop = PlatformUtils.isWindows || PlatformUtils.isLinux || PlatformUtils.isMacOS;
    const double maxContentWidth = 600.0;

    Widget pageContent = (!state.dataLoaded) 
        ? const Center(child: CircularProgressIndicator()) 
        : renderPage();

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

  Widget renderPage() {
    final state = ref.watch(bdcNotifierProvider);
    if (state.word == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('暂无正在学习的单词', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.read(bdcNotifierProvider.notifier).loadData(context),
              child: const Text('重试'),
            ),
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    if (state.showHandwritingBoard || _meaningFocusNode.hasFocus) {
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
  }

  bool _getShouldShowSpeakTab(BdcState state) {
    if (!PlatformUtils.isAsrSupported()) return false;
    if (state.studyStep == StudyStep.ch2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    return true;
  }
}
