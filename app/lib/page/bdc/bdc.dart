import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/config.dart';
import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/util/study_config.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/analytics_util.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/learning_service.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/page/bdc/widgets/word_images_widget.dart';
import 'package:nnbdc/page/bdc/widgets/chinese_asr_input_widget.dart';
import 'package:nnbdc/page/bdc/widgets/english_asr_input_widget.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nnbdc/constants.dart';
import 'package:get_storage/get_storage.dart';
import 'controllers/bdc_controller.dart';
import 'models/bdc_page_args.dart';
import 'models/pic_search_page_args.dart';

part 'dialogs/bdc_dialogs.dart';
part 'widgets/bdc_ui_components.dart';

class BdcPage extends GetView<BdcController> {
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  static const double questionAnswerGap = 8.0;

  final bool _isInitializing = false;

  const BdcPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 桌面版本最大内容宽度，自动居中显示
    final isDesktop = PlatformUtils.isWindows || PlatformUtils.isLinux || PlatformUtils.isMacOS;
    const double maxContentWidth = 600.0;

    return KeyboardDismissOnTap(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: null,
        body: FutureBuilder<void>(
          future: _initializeAsr(),
          builder: (context, snapshot) {
            // 显示初始化过渡页面
            if (snapshot.connectionState != ConnectionState.done) {
              final isDarkMode = context.watch<DarkMode>().isDarkMode;
              final todayWordCount = _getTodayWordCount();
              return Container(
                color: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.mic_none_rounded,
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '正在初始化语音识别引擎',
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : const Color(0xFF2C3E50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '请稍候，正在准备语音识别功能...',
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                        ),
                        if (todayWordCount != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            '今日单词数: $todayWordCount',
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }

            // ASR 初始化完成，显示正常学习页面
            return Obx(() {
              if (!controller.dataLoaded.value) {
                return Container(
                  color: controller.isDarkMode.value ? const Color(0xFF121212) : Colors.white,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              Widget pageContent = renderPage(context);

              if (isDesktop) {
                pageContent = Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: maxContentWidth),
                    child: pageContent,
                  ),
                );
              }

              return Container(
                color: controller.isDarkMode.value ? const Color(0xFF121212) : Colors.white,
                child: pageContent,
              );
            });
          },
        ),
      ),
    );
  }

  /// 获取今日单词数（用于过渡页面显示）
  int? _getTodayWordCount() {
    // 尝试从 GetStorage 读取之前保存的单词数
    try {
      final argsJson = GetStorage().read<String>("BdcPageArgs");
      if (argsJson != null) {
        // 这里可以扩展为从存储读取单词数
      }
    } catch (_) {}
    return null;
  }

  /// 初始化 ASR 引擎（只在从 before_bdc 过来时才需要）
  Future<void> _initializeAsr() async {
    try {
      final argsJson = GetStorage().read<String>("BdcPageArgs");
      if (argsJson != null) {
        final args = BdcPageArgs.fromJson(argsJson);
        if (args.fromPage == 'before_bdc') {
          Global.logger.d('BdcPage: Initializing ASR...');
          // 初始化 ASR
          Asr().initAsr((event) {});
          // 等待 ASR 初始化完成（最多 2 秒）
          for (int i = 0; i < 20; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (Asr().state == AsrState.initialized || Asr().state == AsrState.started) {
              Global.logger.d('BdcPage: ASR initialized after waiting');
              break;
            }
          }
          Global.logger.d('BdcPage: ASR initialization done, state=${Asr().state}');
        }
      }
    } catch (e) {
      Global.logger.w('BdcPage: ASR init failed, continuing anyway: $e');
    }
  }

  Widget renderPage(BuildContext context) {
    if (controller.word.value == null) {
      return Container();
    }

    if (controller.showHandwritingBoard.value || controller.meaningFocusNode.hasFocus) {
      return _buildFullscreenImmersiveInputMode(context);
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _buildMainContent(context),
            ),
            _buildBottomButtons(context),
          ],
        ),
        if (controller.historyIndex.value != -1 && controller.historyIndex.value < controller.history.length - 1)
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
                  const Expanded(
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
                        '-${controller.history.length - controller.historyIndex.value}',
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
}
