import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:math';

import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:flutter/material.dart';
import 'package:nnbdc/page/index.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:image_network/image_network.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_list/stage_words.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
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
import '../util/utils.dart';
import '../db/user_extensions.dart';
import '../theme/app_theme.dart';
import '../util/error_handler.dart';
import '../util/client_type.dart';

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

  const WordImagesWidget({
    super.key,
    required this.images,
    required this.isEditMode,
    required this.onImageTap,
    this.highlightedWordImg,
  });

  @override
  State<WordImagesWidget> createState() => _WordImagesWidgetState();
}

class _WordImagesWidgetState extends State<WordImagesWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      width: MediaQuery.of(context).size.width,
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: (MediaQuery.of(context).size.width - (PlatformUtils.isWeb ? 160 * 4 : 80 * 4) - 16 - 16) / 3,
        runSpacing: 4,
        children: [
          for (var image in widget.images.take(8))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Global.logger.d('GestureDetector onTap image: ${image.imageFile}');
                widget.onImageTap(image);
              },
              child: SizedBox(
                width: PlatformUtils.isWeb ? 160 : 80,
                child: IgnorePointer(
                  ignoring: true,
                  child: ImageNetwork(
                    image: '${Config.wordImageBaseUrl}${image.imageFile}',
                    width: PlatformUtils.isWeb ? 160 : 80,
                    height: PlatformUtils.isWeb ? 120 : 60,
                    duration: 1500,
                    curve: Curves.easeIn,
                    onPointer: true,
                    debugPrint: true, // 启用调试打印
                    onLoading: const LinearProgressIndicator(
                      color: Colors.indigoAccent,
                    ),
                    onError: const Icon(
                      Icons.error,
                      color: Colors.red,
                    ),
                    fitAndroidIos: BoxFit.contain,
                    fitWeb: BoxFitWeb.cover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 预览单词配图的大图弹窗（使用当前上下文）
void _showImagePreviewWithContext(BuildContext context, WordImageVo image, {VoidCallback? onDeleted}) {
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
                      padding: const EdgeInsets.only(left: 8, right: 40, bottom: 8),
                      child: Text(
                        '上传: ${Util.getNickNameOfUser(image.author)}',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    // 大图
                    ImageNetwork(
                      image: '${Config.wordImageBaseUrl}${image.imageFile}',
                      width: PlatformUtils.isWeb ? 720.0 : double.infinity,
                      height: PlatformUtils.isWeb ? 480.0 : 360.0,
                      duration: 800,
                      curve: Curves.easeInOut,
                      onPointer: true,
                      debugPrint: false,
                      onLoading: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      onError: const Icon(Icons.error, color: Colors.red),
                      fitAndroidIos: BoxFit.contain,
                      fitWeb: BoxFitWeb.contain,
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
                (Global.getLoggedInUser()?.isSuper ?? false))
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
                      ToastUtil.info('正在删除...');
                      final result = await Api.client.deleteWordImage(image.id, Global.getLoggedInUser()!.id);
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

class AsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;

  const AsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
  });

  @override
  State<AsrInputWidget> createState() => _AsrInputWidgetState();
}

class _AsrInputWidgetState extends State<AsrInputWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextField(
          textAlign: TextAlign.center,
          controller: widget.controller,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: widget.asrState == AsrState.started
                ? "请说出或输入释义"
                : widget.isKeyboardVisible
                    ? "请输入释义"
                    : "请等待播音结束......",
          ),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          onChanged: (value) {},
        ),
      ],
    );
  }
}

class EnglishAsrInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final AsrState asrState;
  final Function(AsrLanguage) onStartAsr;
  final bool isKeyboardVisible;

  const EnglishAsrInputWidget({
    super.key,
    required this.controller,
    required this.asrState,
    required this.onStartAsr,
    required this.isKeyboardVisible,
  });

  @override
  State<EnglishAsrInputWidget> createState() => _EnglishAsrInputWidgetState();
}

class _EnglishAsrInputWidgetState extends State<EnglishAsrInputWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextField(
          textAlign: TextAlign.center,
          controller: widget.controller,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: widget.asrState == AsrState.started
                ? "请说出或输入英文单词"
                : widget.isKeyboardVisible
                    ? "请输入英文单词"
                    : "请等待播音结束...",
          ),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          onChanged: (value) {},
        ),
      ],
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
  bool dataLoaded = false;
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  late List<UserStudyStepVo> activeUserStudySteps;
  var errorReportController = TextEditingController();
  late Asr asr;

  /// 释义输入框
  TextEditingController meaningController = TextEditingController();

  AudioPlayer audioPlayer = AudioPlayer();

  /// AudioPlayer 是否已被释放的标志
  bool _audioPlayerDisposed = false;

  late BdcPageArgs args;

  /// 是否可以离开当前单词（用户完成了选择题，或者用户asr回答正确的释义数量达到要求）
  bool canLeaveCurrWord = false;

  /// 正在进行匹配的asr输入，防止重复处理，影响性能
  var handlingChinese = "";

  /// 是否正在获取下一个单词
  bool gettingNextWord = false;

  /// 当前正在学习的单词
  GetWordResult? currentGetWordResult;

  /// 正确答案的索引号
  int correctAnswerIndex = 0;

  /// 上一个单词
  WordVo? prevWrod;

  /// 当前单词是否回答正确
  bool isAnswerCorrect = false;

  /// 当前单词是否回答正确
  bool isShowingWordDetail = false;

  /// 当前单词是否已经掌握
  bool isWordMastered = false;

  /// 当前正在学习的单词的第一个例句
  String? englishDigestOfFirstSentence;

  /// 是否正在显示一个单词的内容？
  var isShowingAWord = false;

  String? studyStep;

  /// 当前单词
  WordVo? word;

  /// 当前单词的Wrapper，供recite模式使用
  WordWrapper? wordWrapper;

  /// 当前单词及其他备选单词
  List<WordVo>? words;

  late bool showAnswerButtons;

  late StreamSubscription keyboardSubscription;

  late bool isKeyboardVisible;

  // 底部按钮实际高度，用于为做题区内容预留空间，避免被遮挡
  final GlobalKey _bottomButtonsKey = GlobalKey();

  // 题目区和做题区之间的统一间距
  static const double _questionAnswerGap = 8.0;

  /// 控制做题区、题目区和底部按钮的边框是否显示
  bool showBorders = false;

  var isDarkMode = false;

  var isEditMode = false;

  String? highlightedWordImg;

  bool wordImageEdited = false;

  late AnimationController _soundController;
  late AnimationController _wordSoundController;
  late AnimationController _sentenceSoundController;
  final Map<String, bool> _playingStates = {
    'word': false, // 单词发音
    'sentence': false, // 例句发音
  };

  Timer? _debounceTimer;

  /// Tab控制器，用于管理说/选两个tab
  TabController? _tabController;

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
    if (studyStep == StudyStep.meaning.json) {
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
      children.add(SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildSpeakPanel(),
          ],
        ),
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
    _tabController?.dispose();
    _tabController = TabController(length: _dynamicTabs.length, vsync: this);

    // 重新添加监听器
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        // Tab正在切换中
        return;
      }

      if (_isInSpeakTab) {
        // 切换到"说"tab，启动ASR
        Global.logger.d('===== BDC: 切换到"说"tab，启动ASR');
        if (!isKeyboardVisible) {
          // 设置上下文短语
          _setAsrContextualPhrases();
          asr.startAsr(decideAsrLanguage());
        }
      } else {
        // 切换到"选"tab，停止ASR
        Global.logger.d('===== BDC: 切换到"选"tab，停止ASR');
        asr.stopAsr();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    args = BdcPageArgs.fromJson(GetStorage().read<String>("BdcPageArgs")!);

    // 初始化Tab控制器 - 延迟到studyStep设置后
    // _tabController = TabController(length: 2, vsync: this);

    // // 监听Tab切换，控制ASR的启动和停止
    // _tabController.addListener(() {
    //   if (_tabController.indexIsChanging) {
    //     // Tab正在切换中
    //     return;
    //   }

    //   if (_isInSpeakTab) {
    //     // 切换到"说"tab，启动ASR
    //     Global.logger.d('===== BDC: 切换到"说"tab，启动ASR');
    //     if (!isKeyboardVisible) {
    //       // 设置上下文短语
    //       _setAsrContextualPhrases();
    //       asr.startAsr(decideAsrLanguage());
    //     }
    //   } else {
    //     // 切换到"选"tab，停止ASR
    //     Global.logger.d('===== BDC: 切换到"选"tab，停止ASR');
    //     asr.stopAsr();
    //   }
    // });

    // 初始化两个动画控制器
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _sentenceSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // Listen to player state changes.
    audioPlayer.onPlayerStateChanged.listen((state) {
      Global.logger.d('Player state changed: $state');
    });

    meaningController.addListener(() {
      checkAsrResult();
    });

    // 监听输入法键盘弹出和隐藏
    var keyboardVisibilityController = KeyboardVisibilityController();
    isKeyboardVisible = keyboardVisibilityController.isVisible;
    keyboardSubscription = keyboardVisibilityController.onChange.listen((bool visible) {
      isKeyboardVisible = visible;
      if (isKeyboardVisible) {
        asr.stopAsr();
      } else {
        // 键盘隐藏时，只有在"说"tab激活时才启动ASR
        if (_isInSpeakTab) {
          AsrLanguage language = decideAsrLanguage();
          // 设置上下文短语
          _setAsrContextualPhrases();
          if (studyStep == StudyStep.word.json) {
            asr.startAsr(language);
          } else if (studyStep == StudyStep.meaning.json && Platform.isIOS) {
            asr.startAsr(language);
          }
          if (language != AsrLanguage.english || Platform.isIOS) {
            asr.startAsr(language);
          }
        } else {
          Global.logger.d('===== BDC: 键盘隐藏，但当前在"选"tab，不启动ASR');
        }
      }
      setState(() {});
    });

    asr = Asr();
    asr.initAsr(onAsrResult);
    asr.addStateListener((state) {
      if (mounted) {
        setState(() {});
      }
    });

    _soundController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    loadData();
  }

  AsrLanguage decideAsrLanguage() {
    if (studyStep == StudyStep.meaning.json) {
      return AsrLanguage.english;
    }
    return AsrLanguage.chinese;
  }

  /// 设置ASR上下文短语（当前单词的释义子项(说中文)或当前单词的拼写(说英文)）
  void _setAsrContextualPhrases() {
    try {
      WordVo? word = currentGetWordResult?.learningWord?.word;
      if (word != null) {
        List<String> allowPhrases = [];
        if (studyStep == StudyStep.meaning.json) {
          allowPhrases = [word.spell];
        } else if (studyStep == StudyStep.word.json) {
          allowPhrases = AsrUtil.extractContextualPhrases(
            currentGetWordResult!.learningWord!.word.getMergedMeaningItems(),
          );
        }

        if (allowPhrases.isNotEmpty) {
          AsrUtil.setContextualStrings(
            allowPhrases,
            asr.asrMethodChannel,
            asr.permissionGranted,
          );
        }
      }
    } catch (e) {
      Global.logger.d('设置ASR上下文短语失败: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    asr.removeStateListener((state) {
      if (mounted) {
        setState(() {});
      }
    });
    asr.dispose();
    asr.stopAsr();
    keyboardSubscription.cancel();
    _tabController?.dispose();
    _soundController.dispose();
    _wordSoundController.dispose();
    _sentenceSoundController.dispose();
    GetStorage().remove("BdcPageArgs");

    // 标记 AudioPlayer 为已释放
    _audioPlayerDisposed = true;

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        audioPlayer.dispose();
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace, logPrefix: '释放 AudioPlayer 时出错', showToast: false);
      }
    });

    super.dispose();
  }

  onAsrResult(event) async {
    // 预处理ASR结果，然后更新 meaningController
    String processedResult;

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
        List<String> candidateStrings = candidates.map((e) => e.toString()).toList();
        String bestCandidate = resultData['best'] ?? candidateStrings.first;

        Global.logger.d('===== ASR: Multiple candidates received: $candidateStrings');
        Global.logger.d('===== ASR: Best candidate: $bestCandidate');

        if (studyStep == StudyStep.meaning.json && word != null) {
          // 中→英模式：结合拼写相似度和音素相似度的智能选择
          processedResult = await AsrUtil.selectBestCandidateWithPhoneme(candidateStrings, word!.spell);
          Global.logger.d('===== ASR: Selected result: "$processedResult" (target: ${word!.spell})');
        } else {
          // 其他模式：直接使用最佳候选结果，然后进行相应预处理
          processedResult = bestCandidate;
          if (studyStep == StudyStep.word.json) {
            // 英→中模式：使用中文预处理
            processedResult = AsrUtil.preprocess(processedResult);
            Global.logger.d('===== ASR: Chinese processed result: $processedResult');
          } else {
            Global.logger.d('===== ASR: Using best candidate: $processedResult');
          }
        }
      } else {
        // 单个结果处理
        if (studyStep == StudyStep.meaning.json && word != null) {
          // 中→英模式：英文预处理（单个结果场景下也尝试音素匹配）
          final pre = AsrUtil.preprocessEnglish(event, word!.spell);
          final best = await AsrUtil.selectBestCandidateWithPhoneme([pre], word!.spell);
          processedResult = best;
          Global.logger.d('===== ASR: Single result processed: "$event" -> "$processedResult" (target: ${word!.spell})');
        } else {
          // 其他模式：中文预处理
          processedResult = AsrUtil.preprocess(event);
          Global.logger.d('===== ASR: Chinese processed result: $processedResult');
        }
      }
    } catch (e) {
      Global.logger.e('===== ASR: Error processing result: $e');
      // 出错时使用原始结果进行基本预处理
      if (studyStep == StudyStep.meaning.json && word != null) {
        processedResult = AsrUtil.preprocessEnglish(event, word!.spell);
      } else {
        processedResult = AsrUtil.preprocess(event);
      }
    }

    if (mounted) {
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          if (isShowingWordDetail) {
            Global.logger.d('===== ASR: Skipping result because showing word detail');
            return;
          }
          meaningController.text = processedResult;
        }
      });
    }
  }

  checkAsrResult() async {
    if (meaningController.text != handlingChinese) {
      handlingChinese = meaningController.text;
    } else {
      return;
    }

    Global.logger.d('checkAsrResult: handlingChinese=$handlingChinese');

    bool isPass = false;

    if (studyStep == StudyStep.word.json) {
      // 英→中：验证中文释义
      late Triple<int, int, int> result;
      result = matchInputChineseWithMeaningItems(
        wordWrapper!,
        handlingChinese,
      );

      Global.logger.d('checkAsrResult: result=$result');

      // 检查是否满足通过条件
      final total = result.first;
      final matched = result.second;
      isPass = await _isAsrPass(total, matched);
      Global.logger.d('checkAsrResult: isPass=$isPass');

      // 如果本次有新增匹配，播放音效并设置状态
      if (result.third > 0) {
        setState(() {
          isAnswerCorrect = true;
          canLeaveCurrWord = true;
        });

        // 播放提示音
        await SoundUtil.playAssetSound('ding5.mp3', 1.5, 0.2);
      }
    } else if (studyStep == StudyStep.meaning.json) {
      // 中→英：验证英文单词拼写
      String inputText = handlingChinese.trim().toLowerCase();
      String correctSpell = word!.spell.toLowerCase();

      Global.logger.d('checkAsrResult: inputText=$inputText, correctSpell=$correctSpell');

      if (inputText == correctSpell) {
        isPass = true;
        setState(() {
          isAnswerCorrect = true;
          canLeaveCurrWord = true;
        });

        // 播放提示音
        await SoundUtil.playAssetSound('ding5.mp3', 1.5, 0.2);
        Global.logger.d('checkAsrResult: English spelling match!');
      }
    }

    // 改进的跳转逻辑：使用更宽松的条件
    if (isPass && canLeaveCurrWord) {
      // 检查是否正在获取下一个单词，避免重复调用
      if (!gettingNextWord) {
        Global.logger
            .d('checkAsrResult: pass handling - step=$studyStep, isPass=$isPass, canLeaveCurrWord=$canLeaveCurrWord');
        try {
          // 中→英：回答正确后，先播放一次标准发音再跳转
          if (studyStep == StudyStep.meaning.json) {
            if (!_audioPlayerDisposed && word != null) {
              await SoundUtil.playPronounceSound2(word!, audioPlayer);
            }
          }
          // 英→中：回答正确后直接跳转（不播放单词发音）
        } catch (e, stackTrace) {
          ErrorHandler.handleError(e, stackTrace, logPrefix: '播放发音失败', showToast: false);
        }
        // 在切换到下一个单词前先清空输入框
        meaningController.text = '';
        handlingChinese = '';
        getNextWord(true);
      } else {
        Global.logger.d('checkAsrResult: skipping getNextWord because already getting next word');
      }
    } else {
      Global.logger.d('checkAsrResult: not calling getNextWord - isPass=$isPass, canLeaveCurrWord=$canLeaveCurrWord');
    }
  }

  Future<bool> _isAsrPass(int totalParts, int matchedParts) async {
    final asrPassRule = await MyDatabase.instance.localParamsDao.getAsrPassRule();
    Global.logger.d('_isAsrPass: asrPassRule=$asrPassRule, totalParts=$totalParts, matchedParts=$matchedParts');

    bool result;
    switch (asrPassRule) {
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
    Global.logger.d('_isAsrPass result: $result');
    return result;
  }

  Future<void> loadData() async {
    isDarkMode = await MyDatabase.instance.localParamsDao.getIsDarkMode();

    // 获取用户的学习步骤配置（已激活的学习步骤)
    var stepsResult = await StudyBo().getActiveUserStudySteps();
    if (!stepsResult.success || stepsResult.data == null) {
      ToastUtil.error(stepsResult.msg ?? '获取学习步骤失败');
      return;
    }
    activeUserStudySteps = stepsResult.data!;

    await getNextWord(false);
    if (currentGetWordResult == null) {
      ToastUtil.error('获取单词失败');
      return;
    }
    if (currentGetWordResult!.finished || currentGetWordResult!.noWord || currentGetWordResult!.shouldEnterReviewMode) {
      return;
    }
  }

  /// 播放句子发音按钮处理函数
  Future<void> playFirstSentence() async {
    if (englishDigestOfFirstSentence != null && !_audioPlayerDisposed) {
      try {
        await SoundUtil.playSentenceSound2(englishDigestOfFirstSentence!, audioPlayer);
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace, logPrefix: '播放例句失败', showToast: false);
      }
    }
  }

  getNextWord(bool gotoNext) async {
    if (gettingNextWord) {
      return;
    }
    gettingNextWord = true;
    asr.stopAsr();
    asr.reset();
    // 取消所有待处理的ASR结果防抖定时器，避免旧的识别结果写入新单词的输入框 
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    meaningController.text = '';
    handlingChinese = '';
    // 重置通过状态，避免暴露下一个单词的拼写
    isAnswerCorrect = false;
    canLeaveCurrWord = false;
    highlightedWordImg = null;
    wordImageEdited = false;
    if (currentGetWordResult != null && currentGetWordResult!.learningWord != null) {
      prevWrod = currentGetWordResult!.learningWord!.word;
    }

    //如果是从阶段复习跳转来的，则第一次从服务端取单词时，通知服务端进入下一个学习阶段
    var shouldEnterNextStage = false;
    if (args.fromPage != null && args.fromPage == 'stage_review') {
      shouldEnterNextStage = true;
      args.fromPage = null;
    }

    // 循环调用直到获取到有效单词或遇到其他状态
    int triedCount = 0;
    while (true) {
      var resp = await StudyBo().getNextWord(
          isAnswerCorrect,
          isWordMastered,
          shouldEnterNextStage,
          triedCount == 0 ? gotoNext : true);
      triedCount++;
      if (!resp.success) {
        gettingNextWord = false;
        if (resp.code == 'NEW_DAY') {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('新的一天'),
              content: const Text('已进入新的一天，今天的学习请从“我”页面开始。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          Get.offAllNamed('/index', arguments: IndexPageArgs(4));
          return;
        }
        ToastUtil.error(resp.msg!);
        Get.toNamed("/email_login");
        return;
      }

      currentGetWordResult = resp.data;

      // 如果单词已掌握，重置状态并继续获取下一个单词
      if (currentGetWordResult!.wordMastered) {
        // 重置状态，准备获取下一个单词
        isAnswerCorrect = true; // 设置为true以便前进到下一个单词
        isWordMastered = false; // 重置掌握状态
        shouldEnterNextStage = false; // 后续调用不需要进入下一阶段
        continue; // 继续循环获取下一个单词
      }

      // 获取到有效单词，跳出循环
      break;
    }

    handleWord(currentGetWordResult);

    gettingNextWord = false;
  }

  Future<void> playWordAndFirstSentence(UserVo user, bool forcePlayWord, bool startAsrWhenFinish) async {
    // 播音开始时停止ASR
    asr.stopAsr();

    try {
      // 在中→英模式下，不播放单词发音，避免暴露答案
      if (studyStep != StudyStep.meaning.json && (user.autoPlayWord! || forcePlayWord)) {
        await SoundUtil.playPronounceSound2(word!, audioPlayer);
      }
      // 在中→英模式下，不播放例句发音，避免暴露答案
      if (studyStep != StudyStep.meaning.json && user.autoPlaySentence!) {
        await playFirstSentence();
      }
    } finally {
      // 播音结束后，如果之前在"说"tab且ASR是活跃的，则启动ASR
      if (!PlatformUtils.isWeb && _isInSpeakTab /* "说"tab激活 */) {
        // 设置语音识别的语言
        AsrLanguage language = studyStep == StudyStep.meaning.json ? AsrLanguage.english : AsrLanguage.chinese;
        if (language != AsrLanguage.english || Platform.isIOS) {
          // 启动前设置上下文短语，提升识别效果
          _setAsrContextualPhrases();
          asr.startAsr(language);
        }
      }
    }
  }

  void handleWord(final GetWordResult? getWordResult) async {
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
      } else if (getWordResult.shouldEnterReviewMode) {
        var nextWordBtn = ElevatedButton.icon(
          icon: const Icon(Icons.navigate_next, size: 24.0, color: Colors.white),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          label: const Text('下一组'),
          onPressed: () async {
            Get.back();
            await GetStorage().write("BdcPageArgs", BdcPageArgs('stage_review').toJson());
            // 使用offAndToNamed强制创建新的BDC页面实例
            Get.offAndToNamed('/bdc');
          },
        );
        // 进入阶段复习列表，返回后刷新并确保ASR恢复
        toStageWordsListPage(true, nextWordBtn, context)?.then((_) async {
          if (!mounted) return;
          // 刷新学习内容
          await getNextWord(false);
          // UI稳定后，确保在“说”tab下重启ASR
          Future.delayed(const Duration(milliseconds: 80), () {
            if (!mounted) return;
            if (_isInSpeakTab && !isKeyboardVisible) {
              try {
                // 返回后重新绑定ASR事件监听，避免事件通道在子页面中被覆盖
                asr.stopAsr();
                asr.reset();
                asr.initAsr(onAsrResult);
                _setAsrContextualPhrases();
              } catch (e, stackTrace) {
                // ASR初始化失败需要记录，但不影响后续流程
                Global.logger.w('ASR初始化失败', error: e, stackTrace: stackTrace);
              }
              asr.startAsr(decideAsrLanguage());
            }
          });
        });
        return;
      }

      isWordMastered = false;

      //单词掌握度及当前学习步骤
      if (getWordResult.learningMode >= activeUserStudySteps.length) {
        Global.logger.d('无效的学习模式: ${getWordResult.learningMode}');
        ToastUtil.error('学习模式配置错误');
        return;
      }
      studyStep = activeUserStudySteps[getWordResult.learningMode].studyStep;

      // 重新初始化TabController以适应动态tabs
      _reinitializeTabController();

      isShowingAWord = true;

      if (getWordResult.learningWord?.word == null) {
        Global.logger.d('学习单词为空');
        ToastUtil.error('单词数据错误');
        return;
      }
      word = getWordResult.learningWord!.word;
      wordWrapper = WordWrapper(word!, null);

      // 渲染第一个例句
      englishDigestOfFirstSentence = null; // 先设置为 null
      if (word!.sentences != null && word!.sentences!.isNotEmpty) {
        englishDigestOfFirstSentence = word!.sentences![0].englishDigest;
      }

      var user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.d('用户未登录');
        ToastUtil.error('请先登录');
        return;
      }

      if (studyStep == StudyStep.word.json) {
        //根据拼写
        playWordAndFirstSentence(await user.toUserVo(), false, false);
        //根据发音
        playWordAndFirstSentence(await user.toUserVo(), true, false);
      } else if (studyStep == StudyStep.meaning.json) {
        // 中→英：根据发音
        playWordAndFirstSentence(await user.toUserVo(), true, false);
      }
      _initChoiceData(getWordResult, user);
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '处理单词');
      ToastUtil.error('处理单词时出错');
      return;
    }

    showAnswerButtons = Global.getLoggedInUser()!.showAnswersDirectly;

    setState(() {
      dataLoaded = true;
    });
  }

  /// 初始化选择题数据
  void _initChoiceData(GetWordResult getWordResult, User user) {
    {
      if (studyStep == StudyStep.word.json || studyStep == StudyStep.meaning.json) {
        // 把当前单词及混淆单词放入数组，并随机打乱
        if (getWordResult.otherWords == null || getWordResult.otherWords!.length < 2) {
          Global.logger.d('混淆单词数量（${getWordResult.otherWords!.length}）不足');
          ToastUtil.error('混淆单词数量（${getWordResult.otherWords!.length}）不足');
          return;
        }

        words = <WordVo>[];
        words!.add(word!);
        words!.add(getWordResult.otherWords![0]);
        words!.add(getWordResult.otherWords![1]);
        words!.shuffle();

        // 在打乱的单词数组中找到正确的（当前学习的）
        for (var i = 0; i < words!.length; i++) {
          if (words![i] == word) {
            correctAnswerIndex = i + 1;
            break;
          }
        }

        if (user.enableAllWrong) {
          // 备选答案中含[都不对]
          // 随机选择一个单词索引号（1～3），从数组中删除该单词
          var rnd = Random();
          var indexToDelete = 1 + rnd.nextInt(3 - 1);
          words!.removeAt(indexToDelete - 1);

          // 添加[都不对]选项
          var mockWord = WordVo.c2("[ 都不对 ]");
          mockWord.setMeaningStr("[ 都不对 ]");
          words!.add(mockWord);

          if (indexToDelete == correctAnswerIndex) {
            // 恰好删除了正确的单词，此时[都不对]应成为正确答案
            correctAnswerIndex = 3;
          } else {
            // 在调整过的单词数组中重新找到正确的（当前学习的）
            for (var i = 0; i < words!.length; i++) {
              if (words![i] == word) {
                correctAnswerIndex = i + 1;
                break;
              }
            }
          }
        }
      }
    }
  }

  final email = TextEditingController();

  Widget _buildSettingItem(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
      title: Text(
        title,
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: Global.highlight,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildAsrPassRuleSelector(String currentValue, Function(String) onChanged) {
    const Map<String, String> options = {
      'ONE': '说出一个意思即可',
      'HALF': '说出半数意思',
      'ALL': '说出全部意思',
    };

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
      title: Text(
        '语音识别通过规则',
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        options[currentValue] ?? '说出一个意思即可',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 11,
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(
          Icons.arrow_drop_down,
          color: Global.highlight,
        ),
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
      ),
    );
  }

  Future<void> showSettingDlg() async {
    // 在StatefulBuilder外部初始化本地状态
    var currentUser = Global.getLoggedInUser();
    var localAutoPlayWord = currentUser?.autoPlayWord ?? false;
    var localAutoPlaySentence = currentUser?.autoPlaySentence ?? false;
    var localShowAnswersDirectly = currentUser?.showAnswersDirectly ?? false;
    var localEnableAllWrong = currentUser?.enableAllWrong ?? false;
    var localAsrPassRule = await MyDatabase.instance.localParamsDao.getAsrPassRule();

    if (!mounted) return;

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Container(
                padding: const EdgeInsets.all(10),
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
                      Icons.settings,
                      color: Global.highlight,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '学习设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Global.highlight,
                        fontFamily: "NotoSansSC",
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: min(MediaQuery.of(context).size.width * 0.86, 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    DayNightSwitcherIcon(
                      isDarkModeEnabled: isDarkMode,
                      onStateChanged: (isDarkModeEnabled) {
                        setState(() {
                          isDarkMode = isDarkModeEnabled;
                        });
                        MyDatabase.instance.localParamsDao.saveIsDarkMode(isDarkModeEnabled);
                        context.read<DarkMode>().setIsDarkMode(isDarkModeEnabled);
                      },
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                              width: 0.6,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final bool useTwoColumns = constraints.maxWidth > 360;
                              final List<Widget> items = [
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
                                _buildAsrPassRuleSelector(
                                  localAsrPassRule,
                                  (value) {
                                    setState(() {
                                      localAsrPassRule = value;
                                    });
                                  },
                                ),
                              ];

                              if (!useTwoColumns) {
                                return Column(
                                  children: [
                                    for (int i = 0; i < items.length; i++) ...[
                                      if (i > 0) const SizedBox(height: 2),
                                      items[i],
                                    ]
                                  ],
                                );
                              }

                              return Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: items
                                    .map((w) => SizedBox(
                                          width: (constraints.maxWidth - 8) / 2,
                                          child: w,
                                        ))
                                    .toList(),
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
                          foregroundColor: Colors.white,
                          backgroundColor: Global.highlight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          // 保存所有设置
                          if (currentUser != null) {
                            var updatedUser = currentUser.copyWith(
                              autoPlayWord: localAutoPlayWord,
                              autoPlaySentence: localAutoPlaySentence,
                              showAnswersDirectly: localShowAnswersDirectly,
                              enableAllWrong: localEnableAllWrong,
                            );
                            await MyDatabase.instance.usersDao.saveUser(updatedUser, true);
                            // 更新Global中的用户缓存
                            Global.updateUserCache(updatedUser);
                          }
                          // 保存asrPassRule设置
                          await MyDatabase.instance.localParamsDao.setAsrPassRule(localAsrPassRule);
                          // 在异步操作后检查context是否仍然有效
                          if (context.mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                        child: const Text('确定', style: TextStyle(fontSize: 13, fontFamily: "NotoSansSC")),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[700],
                          backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: const Text('取消', style: TextStyle(fontSize: 13, fontFamily: "NotoSansSC")),
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
        asr.stopAsr();
        handleWord(currentGetWordResult);
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
                    Icon(Icons.report_problem_outlined, color: Global.highlight, size: 20),
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
                        '请输入单词(${word!.spell})的报错内容',
                        textScaler: const TextScaler.linear(1.0),
                        style: const TextStyle(
                          fontFamily: "NotoSansSC",
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1F2430) : const Color(0xFFF7FAFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
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
      var result = await Api.client.saveErrorReport(word!.spell, errorReportController.text, getClientType().name);
      if (result.success) {
        ToastUtil.info('报错成功！感谢你付出宝贵时间');
      } else {
        ToastUtil.error((result.msg!));
      }
    }
  }

  Widget renderPage() {
    if (word == null) {
      return Container();
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
        border: showBorders
            ? Border.all(
                color: const Color.fromARGB(255, 11, 118, 3),
                width: 10,
              )
            : null,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, max(kTextTabBarHeight + 6.0, MediaQuery.of(context).viewPadding.bottom + kTextTabBarHeight)), // 预留底部TabBar空间，避免遮挡
        child: Column(
          children: [
            // 英→中模式整合卡片
            if (studyStep == StudyStep.word.json && currentGetWordResult?.learningWord?.word != null) _buildWordStepCard(),
            // 中→英模式整合卡片
            if (studyStep == StudyStep.meaning.json && currentGetWordResult?.learningWord?.word != null) _buildMeaningStepCard(),

            _buildPhoneticRow(),
            _buildFirstSentenceRow(),
          ],
        ),
      ),
    );
  }

  /// 构建浮动的TabBar
  Widget _buildFloatingTabBar() {
    return Positioned(
      bottom: 0,
      left: leftPadding,
      right: rightPadding,
      child: Container(
        decoration: BoxDecoration(
          color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          dividerColor: Colors.transparent,
          dividerHeight: 0,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: context.watch<DarkMode>().isDarkMode ? Colors.white70 : Colors.grey[600],
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
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
        Container(
          margin: EdgeInsets.fromLTRB(0, MediaQuery.of(context).padding.top + 8, 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : const Color(0xFFE8F1FF),
            ),
            child: currentGetWordResult?.progress != null
                ? FAProgressBar(
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                    currentValue: currentGetWordResult!.progress![0].toDouble(),
                    maxValue: currentGetWordResult!.progress![1].toDouble(),
                    displayText: '',
                    direction: Axis.horizontal,
                    displayTextStyle: const TextStyle(color: Color(0x00000000)),
                    backgroundColor: Colors.transparent,
                    progressColor: AppTheme.primaryColor,
                    animatedDuration: const Duration(milliseconds: 300),
                  )
                : const SizedBox.shrink(),
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
              border: showBorders
                  ? Border.all(
                      color: Colors.blue,
                      width: 10,
                    )
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, 0),
            child: (showAnswerButtons || studyStep == StudyStep.word.json || studyStep == StudyStep.meaning.json)
                ? Column(
                    children: [
                      Expanded(
                        child: (studyStep == StudyStep.word.json || studyStep == StudyStep.meaning.json)
                            ? TabBarView(
                                controller: _tabController,
                                children: _dynamicTabBarViewChildren,
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    _buildChoiceList(),
                                    _buildSpeakPanel(),
                                  ],
                                ),
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
                        showAnswerButtons = true;
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
      child: Container(
        // 底部按钮区背景色 - 紫色调
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: showBorders
              ? Border.all(
                  color: context.watch<DarkMode>().isDarkMode
                      ? const Color(0xFF9C27B0) // 深色模式：紫色边框
                      : const Color(0xFF7B1FA2), // 浅色模式：深紫色边框
                  width: 2,
                )
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (showAnswerButtons || studyStep == StudyStep.word.json)
              ElevatedButton.icon(
                key: const Key('bdc_not_know_btn'),
                icon: const Icon(Icons.close, size: 20.0, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                label: const Text('不认识'),
                onPressed: () => showWordDetail(word, true),
              ),
            if (showAnswerButtons || studyStep == StudyStep.word.json)
              ElevatedButton.icon(
                key: const Key('bdc_study_again'),
                icon: const Icon(Icons.refresh, size: 20.0, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                label: const Text('再学学'),
                onPressed: () => showWordDetail(word, false),
              ),
            if (canLeaveCurrWord)
              ElevatedButton.icon(
                key: const Key('bdc_next_word_btn'),
                icon: const Icon(Icons.navigate_next, size: 20.0, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                label: const Text('下一词'),
                onPressed: () {
                  // 在切换到下一个单词前先清空输入框
                  meaningController.text = '';
                  handlingChinese = '';
                  getNextWord(true);
                },
              ),
          ],
        ),
      ),
    );
  }

  SizedBox spellExerciseTextField(String wordSpell) {
    TextStyle textStyle = TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Util.equalsIgnoreCase(word!.spell, wordWrapper!.spellController.text)
            ? wordWrapper!.isAnswerProvidedBySystem
                ? Colors.blue
                : Colors.green
            : Colors.red);
    double width = Util.getTextWidth(wordSpell, textStyle);
    return SizedBox(
      width: width * 1.3,
      height: 26,
      child: TextField(
        textAlign: TextAlign.center,
        controller: wordWrapper!.spellController,
        focusNode: wordWrapper!.focusNode,
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
          if (Util.equalsIgnoreCase(word!.spell, value)) {
            SoundUtil.playPronounceSound(word!);
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
      highlightedWordImg = null;
    });
  }

  Future<bool> wordImageHasBeenVoted(var wordImage) async {
    return (await MyDatabase.instance.votedWordImagesDao.getVotedWordImageById(Global.getLoggedInUser()!.id, wordImage.id)) != null;
  }

  /// 放大单词配图对话框
  Future<void> showEditPicDlg(BuildContext context, WordImageVo wordImage) async {
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
          return StatefulBuilder(builder: (context, setState) {
            return Align(
              alignment: const Alignment(0, 0),
              child: Container(
                width: PlatformUtils.isWeb ? 600 : MediaQuery.of(context).size.width,
                height: PlatformUtils.isWeb ? 480 : 320,
                margin: MediaQuery.of(context).viewInsets,
                // 当软键盘弹出时，对话框自动上移
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                color: context.read<DarkMode>().isDarkMode ? const Color(0xff333333) : Colors.white,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            child: ImageNetwork(
                                image: '${Config.wordImageBaseUrl}${wordImage.imageFile}',
                                width: PlatformUtils.isWeb ? 400 : 200,
                                height: PlatformUtils.isWeb ? 300 : 150,
                                onLoading: const CircularProgressIndicator(
                                  color: Colors.indigoAccent,
                                ),
                                onError: const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                ),
                                fitAndroidIos: BoxFit.contain,
                                fitWeb: BoxFitWeb.cover),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('by：${Util.getNickNameOfUser(wordImage.author)}'),
                          ],
                        ),
                      ),
                      FutureBuilder<bool>(
                          future: wordImageHasBeenVoted(wordImage),
                          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                            if (snapshot.connectionState == ConnectionState.done) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.favorite_outline,
                                            size: 24,
                                            color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context),
                                          ),
                                          Text(' ${wordImage.hand}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context))),
                                        ],
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client.handWordImage(wordImage.id);
                                        if (result.success) {
                                          MyDatabase.instance.votedWordImagesDao.createEntity(
                                              VotedWordImage(userId: Global.getLoggedInUser()!.id, imageId: wordImage.id, vote: 'HAND'));
                                          wordImage.hand += 1;
                                          wordImageEdited = true;
                                          if (mounted) {
                                            setState(() {});
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
                                              color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context),
                                            ),
                                            Text(' ${wordImage.foot}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context))),
                                          ],
                                        ),
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client.footWordImage(wordImage.id);
                                        if (result.success) {
                                          MyDatabase.instance.votedWordImagesDao.createEntity(
                                              VotedWordImage(userId: Global.getLoggedInUser()!.id, imageId: wordImage.id, vote: 'FOOT'));
                                          wordImage.foot += 1;
                                          wordImageEdited = true;
                                          if (mounted) {
                                            setState(() {});
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
                            if (wordImage.author.id == Global.getLoggedInUser()!.id ||
                                Global.getLoggedInUser()!.isAdmin ||
                                Global.getLoggedInUser()!.isSuper)
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
                                  Api.client.deleteWordImage(wordImage.id, Global.getLoggedInUser()!.id).then((result) {
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
                                if (wordImageEdited) {
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
      word.hintLetterCount++;
    });
  }

  void clearHint(WordWrapper word) {
    setState(() {
      word.hintLetterCount = 0;
    });
  }

  /// 构建单词拼写提示（用于"说出单词发音"模式）
  Widget _buildWordSpellingHint(WordWrapper wordWrapper, bool isAnswerCorrect) {
    if (isAnswerCorrect) {
      // 答对后显示完整单词
      return Text(
        word!.spell,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryColor,
          fontFamily: 'Roboto',
          letterSpacing: 1.2,
        ),
      );
    }

    // 答题中，根据hintLetterCount显示提示
    if (wordWrapper.hintLetterCount == 0) {
      return const SizedBox.shrink();
    }

    String spell = word!.spell;
    int hintCount = wordWrapper.hintLetterCount;
    List<Widget> letterWidgets = [];

    for (int i = 0; i < spell.length; i++) {
      Widget letter;
      if (i < hintCount) {
        // 显示提示字母
        letter = Text(
          spell[i],
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4A90E2),
            fontFamily: 'Roboto',
          ),
        );
      } else {
        // 显示下划线占位符
        letter = Text(
          '_',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.watch<DarkMode>().isDarkMode ? Colors.white30 : Colors.grey[400],
            fontFamily: 'Roboto',
          ),
        );
      }
      
      // 将字母包装在容器中以添加右边距
      letterWidgets.add(Container(
        margin: const EdgeInsets.only(right: 3),
        child: letter,
      ));
    }

    return Wrap(
      spacing: 2,
      runSpacing: 4,
      children: letterWidgets,
    );
  }

  onAnswerClicked(var selectedAnswerIndex) {
    isAnswerCorrect = selectedAnswerIndex == correctAnswerIndex;
    if (isAnswerCorrect) {
      SoundUtil.playAssetSound('ding5.mp3', 1.5, 0.2);
      // 在切换到下一个单词前先清空输入框
      meaningController.text = '';
      handlingChinese = '';
      getNextWord(true);
    } else {
      //不认识或答案错误
      SoundUtil.playAssetSound('cow2.mp3', 1.5, 0.2);
      showWordDetail(word!, true); // 传递true表示本次回答错误
    }
  }

  showWordDetail(var word, bool isAnswerWrong) {
    isShowingWordDetail = true;
    var bottomBtn = Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          // 在切换到下一个单词前先清空输入框
          meaningController.text = '';
          handlingChinese = '';
          getNextWord(true);
        },
        borderRadius: BorderRadius.circular(8),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '下一词 ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(Icons.arrow_forward, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
    Get.toNamed('/word_detail', arguments: WordDetailPageArgs(word, false, bottomBtn, isAnswerWrong))?.then((value) => isShowingWordDetail = false);
  }

  reloadWord() async {
    await StudyBo().prepareForStudy(false);
    getNextWord(false);
  }

  Future<void> _playWithAnimation(Future<void> Function() playSound, String audioType) async {
    setState(() {
      _playingStates[audioType] = true;
    });

    final controller = audioType == 'word' ? _wordSoundController : _sentenceSoundController;
    controller.repeat();

    // 播音开始时停止ASR
    asr.stopAsr();

    try {
      await playSound();
    } finally {
      if (mounted) {
        setState(() {
          _playingStates[audioType] = false;
        });
        controller.stop();
        controller.reset();

        // 播音结束后，如果之前在"说"tab且ASR是活跃的，则启动ASR
        if (_isInSpeakTab && !isKeyboardVisible) {
          Global.logger.d('===== BDC: 播音结束，启动ASR ($audioType)');
          // 设置上下文短语
          _setAsrContextualPhrases();
          asr.startAsr(decideAsrLanguage());
        }
      }
    }
  }

  Widget buildWordSoundButton(WordVo word, AudioPlayer audioPlayer) {
    // 在拼写和音标显示的情况下使用小按钮
    if (studyStep == StudyStep.word.json) {
      return Transform.translate(
          offset: Offset(6.0, 1.0),
          child: InkWell(
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _wordSoundController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_wordSoundController.value < 0.5 ? 0 : -2, 0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
                      child: Icon(
                        _playingStates['word']! ? (_wordSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down) : Icons.volume_up,
                        color: _playingStates['word']! ? Colors.teal[300] : Colors.grey[500],
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              if (!_playingStates['word']!) {
                _playWithAnimation(() => SoundUtil.playPronounceSound2(word, audioPlayer), 'word');
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
        color: _playingStates['word']! ? Colors.teal[300] : Colors.grey[200],
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
              _playWithAnimation(() => SoundUtil.playPronounceSound2(word, audioPlayer), 'word');
            }
          },
          child: Center(
            child: AnimatedBuilder(
              animation: _wordSoundController,
              builder: (context, child) {
                return Icon(
                  _playingStates['word']! ? (_wordSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down) : Icons.volume_up,
                  color: _playingStates['word']! ? Colors.white : Colors.grey[600],
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
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.5) : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        child: AnimatedBuilder(
          animation: _sentenceSoundController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2, 0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
              child: Icon(
                _playingStates['sentence']! ? (_sentenceSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down) : Icons.volume_up,
                color: _playingStates['sentence']! ? Colors.teal[300] : Colors.grey[500],
                size: 18,
              ),
            );
          },
        ),
        onTap: () {
          if (!_playingStates['sentence']! && englishDigestOfFirstSentence != null) {
            _playWithAnimation(() => SoundUtil.playSentenceSound2(englishDigestOfFirstSentence!, audioPlayer), 'sentence');
          }
        },
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    String? label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final buttonColor = color ?? (isDarkMode ? Colors.white : const Color(0xFF4A90E2));

    return Container(
      height: 32, // 恢复原高度
      width: label != null ? null : 32, // 对于无标签的按钮，设置固定宽度形成圆形
      padding: EdgeInsets.symmetric(
        horizontal: label != null ? 8 : 4, // 调整无标签按钮的水平内边距
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
        borderRadius: BorderRadius.circular(label != null ? 16 : 16), // 对于无标签按钮使用圆形
        border: Border.all(
          color: buttonColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
                color: buttonColor,
                size: 14, // 恢复原大小
              ),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label,
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    fontSize: 10, // 恢复原字号
                    fontWeight: FontWeight.w400, // 减轻权重，避免小字号模糊
                    color: buttonColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditToggle() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          isEditMode = !isEditMode;
        });
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDarkMode ? Colors.white : const Color(0xFF4A90E2)).withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Icon(
              Icons.edit,
              size: 12,
              color: isDarkMode ? Colors.white : const Color(0xFF4A90E2),
            ),
            // Switch - 禁用点击，只用作视觉指示器
            SizedBox(
              width: 28,
              child: Transform.scale(
                scale: 0.5,
                child: IgnorePointer(
                  child: Switch(
                    value: isEditMode,
                    onChanged: (_) {}, // 空回调而不是null，保持Switch启用状态
                    activeColor: const Color(0xFF4A90E2),
                    inactiveThumbColor: Colors.grey[400],
                    inactiveTrackColor: Colors.grey[300],
                    activeTrackColor: const Color(0xFF4A90E2).withValues(alpha: 0.5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopButtonsRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 返回按钮
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: context.watch<DarkMode>().isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: context.watch<DarkMode>().isDarkMode ? Colors.white : AppTheme.primaryColor,
                  size: 20,
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
                  color: const Color(0xFF10B981),
                  onTap: () {
                    isAnswerCorrect = true;
                    isWordMastered = true;
                    ToastUtil.info("不再学习 ${word!.spell}");
                    // 在切换到下一个单词前先清空输入框
                    meaningController.text = '';
                    handlingChinese = '';
                    getNextWord(true);
                  },
                ),

                // 编辑开关 - 仅在meaning模式下且非Web平台显示
                if (studyStep == StudyStep.meaning.json && !PlatformUtils.isWeb) _buildEditToggle(),

                // 报错按钮
                _buildTopActionButton(
                  icon: Icons.report_problem_outlined,
                  label: '报错',
                  color: const Color(0xFFF59E0B),
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
          IntrinsicHeight(
            // 让所有子组件具有相同的高度
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 词性部分 - 带背景的容器
                Container(
                  width: 45, // 固定宽度，确保所有词性对齐
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 4), // 减少上下内边距
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF4A4A5E).withValues(alpha: 0.3) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      ciXing,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
                // 释义部分
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 2), // 与词性容器相同的垂直内边距
                    child: Text(
                      _hideAnswerLeakContent(meaning),
                      style: TextStyle(
                        fontFamily: "NotoSansSC",
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // 如果不是以词性开头，直接添加整行
        widgets.add(
          Text(
            line,
            style: TextStyle(
              fontFamily: "NotoSansSC",
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
            ),
          ),
        );
      }

      // 添加行间距（除了最后一行）
      if (i < lines.length - 1) {
        widgets.add(const SizedBox(height: 4));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildChoiceList() {
    if (!(studyStep == StudyStep.word.json || studyStep == StudyStep.meaning.json)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (var index = 0; index < (words?.length ?? 0); index++)
          Padding(
            padding: studyStep == StudyStep.meaning.json ? const EdgeInsets.symmetric(vertical: 3) : const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: context.watch<DarkMode>().isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onAnswerClicked(index + 1),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: _buildAnswerContent(
                        studyStep == StudyStep.meaning.json ? (words?[index].spell ?? '') : (words?[index].getMeaningStr() ?? ''),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpeakPanel() {
    if (!((studyStep == StudyStep.word.json || studyStep == StudyStep.meaning.json) && word != null)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.watch<DarkMode>().isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (isKeyboardVisible)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A90E2), Color(0xFF6BA3E8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                studyStep == StudyStep.word.json ? word!.spell : word!.getMergedMeaningItems().map((e) => e.meaning).join('; '),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: studyStep == StudyStep.word.json
                        ? renderAsrMeaningItems(wordWrapper!)
                        : [
                            Text(
                              '请说出单词发音：',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: context.watch<DarkMode>().isDarkMode ? Colors.white70 : Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildWordSpellingHint(wordWrapper!, isAnswerCorrect),
                          ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => giveALittleHint(wordWrapper!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.emoji_objects_rounded, color: const Color(0xFF4A90E2), size: 14),
                                const SizedBox(width: 3),
                                const Text('提示', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF4A90E2))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => clearHint(wordWrapper!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, color: Colors.grey[600], size: 14),
                                const SizedBox(width: 3),
                                Text('清除', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          studyStep == StudyStep.word.json
              ? AsrInputWidget(
                  controller: meaningController,
                  asrState: asr.state,
                  onStartAsr: (language) => asr.startAsr(language),
                  isKeyboardVisible: isKeyboardVisible,
                )
              : EnglishAsrInputWidget(
                  controller: meaningController,
                  asrState: asr.state,
                  onStartAsr: (language) => asr.startAsr(language),
                  isKeyboardVisible: isKeyboardVisible,
                ),
        ],
      ),
    );
  }

  /// 音标行
  Widget _buildPhoneticRow() {
    if (!(currentGetWordResult?.learningWord?.word != null && studyStep != StudyStep.word.json)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.5) : const Color(0xFFF0F8FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (studyStep != StudyStep.meaning.json)
            Text(
              Util.getWordDefaultPronounce(currentGetWordResult!.learningWord!.word).isEmpty
                  ? ''
                  : '[${Util.getWordDefaultPronounce(currentGetWordResult!.learningWord!.word)}]',
              style: TextStyle(
                color: context.watch<DarkMode>().isDarkMode ? Colors.white70 : Colors.grey[600],
                fontFamily: "NotoSans",
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (studyStep != StudyStep.meaning.json) buildWordSoundButton(currentGetWordResult!.learningWord!.word, audioPlayer),
        ],
      ),
    );
  }

  /// 题目区的例句行(单词的第一个例句)
  Widget _buildFirstSentenceRow() {
    if (!(word?.sentences != null && word!.sentences!.isNotEmpty && studyStep != StudyStep.meaning.json && studyStep != StudyStep.word.json)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.3) : const Color(0xFFF8FAFF),
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
                  ? const Color(0xFF2A2A3E).withValues(alpha: 0.5)
                  : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              child: AnimatedBuilder(
                animation: _sentenceSoundController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2, 0),
                    child: Icon(
                      _playingStates['sentence']! ? (_sentenceSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down) : Icons.volume_up,
                      color: _playingStates['sentence']! ? Colors.teal[300] : Colors.grey[500],
                      size: 24,
                    ),
                  );
                },
              ),
              onTap: () {
                if (!_playingStates['sentence']! && englishDigestOfFirstSentence != null) {
                  _playWithAnimation(() => SoundUtil.playSentenceSound2(englishDigestOfFirstSentence!, audioPlayer), 'sentence');
                }
              },
            ),
          ),
          Expanded(
            child: Util.makeEnglishSpanText(word!.sentences![0].english!, word!.spell, true, context, false, null, true, FontWeight.w300),
          ),
        ],
      ),
    );
  }

  Widget _buildWordStepCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.watch<DarkMode>().isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode
                  ? const Color(0xFF2A2A3E).withValues(alpha: 0.8)
                  : const Color(0xFFF8FAFF).withValues(alpha: 0.9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getStepIcon(studyStep!), color: AppTheme.primaryColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  key: const Key('learning_mode_text'),
                  '英→中',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.primaryColor),
                ),
              ],
            ),
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
                    currentGetWordResult!.learningWord!.word.spell,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 36,
                      color: AppTheme.primaryColor,
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
                    Text(
                      Util.getWordDefaultPronounce(currentGetWordResult!.learningWord!.word).isEmpty
                          ? ''
                          : '[${Util.getWordDefaultPronounce(currentGetWordResult!.learningWord!.word)}]',
                      style: TextStyle(
                        color: context.watch<DarkMode>().isDarkMode ? Colors.white70 : Colors.grey[600],
                        fontFamily: "NotoSans",
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    buildWordSoundButton(currentGetWordResult!.learningWord!.word, audioPlayer),
                  ],
                ),
                if (word?.sentences != null && word!.sentences!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Util.makeEnglishSpanText(word!.sentences![0].english!, word!.spell, true, context, false, null, true, FontWeight.w300),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(left: 8, top: 2),
                        decoration: BoxDecoration(
                          color: context.watch<DarkMode>().isDarkMode
                              ? const Color(0xFF2A2A3E).withValues(alpha: 0.5)
                              : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedBuilder(
                            animation: _sentenceSoundController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2, 0),
                                child: Icon(
                                  _playingStates['sentence']!
                                      ? (_sentenceSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down)
                                      : Icons.volume_up,
                                  color: _playingStates['sentence']! ? Colors.teal[300] : Colors.grey[500],
                                  size: 24,
                                ),
                              );
                            },
                          ),
                          onTap: () {
                            if (!_playingStates['sentence']! && englishDigestOfFirstSentence != null) {
                              _playWithAnimation(() => SoundUtil.playSentenceSound2(englishDigestOfFirstSentence!, audioPlayer), 'sentence');
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
        color: context.watch<DarkMode>().isDarkMode ? const Color(0xFF2A2A3E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.watch<DarkMode>().isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 学习模式标题
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            decoration: BoxDecoration(
              color: context.watch<DarkMode>().isDarkMode
                  ? const Color(0xFF2A2A3E).withValues(alpha: 0.8)
                  : const Color(0xFFF8FAFF).withValues(alpha: 0.9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getStepIcon(studyStep!), color: const Color(0xFF4A90E2), size: 16),
                const SizedBox(width: 6),
                const Text(key: Key('learning_mode_text'), '中→英', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF4A90E2))),
              ],
            ),
          ),
          // 释义/图片/配图按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 释义
                for (var i = 0; i < currentGetWordResult!.learningWord!.word.getMergedMeaningItems().length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == currentGetWordResult!.learningWord!.word.getMergedMeaningItems().length - 1 ? 4.0 : 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentGetWordResult!.learningWord!.word.getMergedMeaningItems()[i].ciXing ?? '',
                            style: const TextStyle(color: Color(0xFF4A90E2), fontSize: 12, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _hideParenthesesContent(currentGetWordResult!.learningWord!.word.getMergedMeaningItems()[i].meaning ?? ''),
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: context.watch<DarkMode>().isDarkMode ? Colors.white : const Color(0xFF2D3748),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 图片
                if (currentGetWordResult?.images != null)
                  Column(
                    children: [
                      if (currentGetWordResult!.images!.isNotEmpty && studyStep != StudyStep.meaning.json)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('图片数量: ${currentGetWordResult!.images!.length}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        ),
                      WordImagesWidget(
                        images: currentGetWordResult!.images!,
                        isEditMode: isEditMode,
                        highlightedWordImg: highlightedWordImg,
                        onImageTap: (image) {
                          Global.logger.d('show dialog for image: ${image.imageFile}');
                          _showImagePreviewWithContext(context, image, onDeleted: () {
                            currentGetWordResult?.images?.removeWhere((e) => e.id == image.id);
                            setState(() {});
                          });
                        },
                      ),
                    ],
                  ),
                // 配图按钮
                if (isEditMode)
                  InkWell(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 24.0),
                        style: ElevatedButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.teal[300]),
                        label: const Text('配图'),
                        onPressed: () {
                          if (currentGetWordResult?.learningWord?.word.id != null) {
                            Get.toNamed('/pic_search',
                                    arguments: PicSearchPageArgs(
                                        currentGetWordResult!.learningWord!.word.id!, currentGetWordResult!.learningWord!.word.spell))!
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

  IconData _getStepIcon(String studyStep) {
    switch (studyStep) {
      case 'Word':
        return Icons.auto_stories;
      case 'Meaning':
        return Icons.school;
      default:
        return Icons.school;
    }
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

  @override
  Widget build(BuildContext context) {
    return KeyboardDismissOnTap(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: null,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: context.watch<DarkMode>().isDarkMode
                  ? [
                      const Color(0xFF1A1A2E),
                      const Color(0xFF16213E),
                      const Color(0xFF0F3460),
                    ]
                  : [
                      const Color(0xFFF8FAFF),
                      const Color(0xFFE8F4FD),
                      const Color(0xFFF0F8FF),
                    ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
        ),
      ),
    );
  }
}
