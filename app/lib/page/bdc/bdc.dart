import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/config.dart';
import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
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

import 'controllers/bdc_controller.dart';
import 'models/pic_search_page_args.dart';

part 'dialogs/bdc_dialogs.dart';
part 'widgets/bdc_ui_components.dart';

class BdcPage extends GetView<BdcController> {
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  static const double questionAnswerGap = 8.0;

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
        body: Obx(() {
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
        }),
      ),
    );
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
