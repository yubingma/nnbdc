import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/services/ai_runtime_macos.dart';

import '../global.dart';
import '../state.dart';
import '../util/utils.dart';

class WordDetailPageArgs {
  late WordVo word;

  /// 是否需要重新查询word （word对象可能来自本地，信息并不完整）
  late bool needReQueryWord;

  Widget? bottomBtn;

  /// 本次是否回答错误
  late bool isThisAnswerWrong;

  WordDetailPageArgs(this.word, this.needReQueryWord, this.bottomBtn, this.isThisAnswerWrong);

  @override
  String toString() {
    return 'WordDetailPageParams{word: $word, needReQueryWord: $needReQueryWord, isThisAnswerWrong: $isThisAnswerWrong}';
  }
}

enum MessageRole { user, assistant }

class ChatMessage {
  final MessageRole role;
  String content;
  String? thought;

  ChatMessage({required this.role, required this.content, this.thought});
}

class WordDetailPage extends StatefulWidget {
  const WordDetailPage({super.key});

  @override
  WordDetailPageState createState() {
    return WordDetailPageState();
  }
}

class WordDetailPageState extends State<WordDetailPage> with TickerProviderStateMixin {
  bool dataLoaded = false;
  bool hasError = false;
  String? errorMessage;
  bool isWrongWord = false; // 是否是错词
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  late final AudioPlayer audioPlayer;
  bool _audioPlayerDisposed = false;
  var sentenceEnglishController = TextEditingController();
  var sentenceChineseController = TextEditingController();
  var isEditMode = false;
  
  // AI 解释相关 (已升级为 AI 对话)
  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  String? _aiImageUrl;
  bool _aiLoading = false;
  String? _aiError;
  String _aiRawAccum = '';
  StreamSubscription<String>? _aiPartialSub;
  bool _aiThoughtComplete = false; // 思考内容是否生成完成

  // Animation controllers
  late final AnimationController _wordSoundController;
  final Map<String, AnimationController> _sentenceSoundControllers = {};

  // Track playing states
  final Map<String, ValueNotifier<bool>> _playingStates = {
    'word': ValueNotifier(false),
  };

  late WordDetailPageArgs args;

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayer();
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    loadData();
  }

  @override
  void dispose() {
    _wordSoundController.dispose();
    for (var controller in _sentenceSoundControllers.values) {
      controller.dispose();
    }
    _chatInputController.dispose();
    _chatScrollController.dispose();

    // 标记 AudioPlayer 为已释放
    _audioPlayerDisposed = true;

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        audioPlayer.dispose();
      } catch (e) {
        // 忽略释放时的错误
        Global.logger.d("释放 AudioPlayer 时出错: $e");
      }
    });

    super.dispose();
  }

  Future<bool> checkArgs() async {
    if (Get.arguments == null) {
      Future.delayed(Duration.zero, () {
        // 延迟到下一个tick执行，避免导航冲突
        Get.toNamed('/bdc');
      });
      return false;
    }
    args = Get.arguments;
    return true;
  }

  Future<void> loadData() async {
    if (!await checkArgs()) {
      return;
    }
    if (args.needReQueryWord) {
      try {
        // 使用新的根据ID查词方法，传入用户ID进行词书过滤
        var result = await WordBo().searchWordById(args.word.id!, Global.getLoggedInUser()?.id);
        if (result.word == null) {
          ToastUtil.error("单词 ${args.word.spell} 不存在");
        } else {
          args.word = result.word!;
        }
      } catch (e, st) {
        ErrorHandler.handleDatabaseError(e, st, operation: '根据ID查词');
        if (mounted) {
          setState(() {
            hasError = true;
            errorMessage = '加载单词详情失败';
          });
        }
        return;
      }
    }

    // 如果未强制重查，但数据不完整（缺少形近词或例句），则补拉完整数据
    if (!args.needReQueryWord) {
      bool missingSimilar = args.word.similarWords == null;
      bool missingMeaningItems = args.word.meaningItems == null || args.word.meaningItems!.isEmpty;
      bool missingAnySentences = false;
      if (!missingMeaningItems) {
        for (final mi in args.word.meaningItems!) {
          if (mi.sentences == null || mi.sentences!.isEmpty) {
            missingAnySentences = true;
            break;
          }
        }
      }

      if (missingSimilar || missingMeaningItems || missingAnySentences) {
        try {
          // 使用新的根据ID查词方法，传入用户ID进行词书过滤
          var result = await WordBo().searchWordById(args.word.id!, Global.getLoggedInUser()?.id);
          if (result.word != null) {
            args.word = result.word!;
          }
        } catch (e, st) {
          // 静默处理补拉失败，保留已有数据
          ErrorHandler.handleDatabaseError(e, st, operation: '根据ID查词');
        }
      }
    }

    // 使用传入的参数判断本次是否回答错误
    isWrongWord = args.isThisAnswerWrong;

    setState(() {
      dataLoaded = true;
    });

    _prefetchAiExplanation();
  }

  String _cleanAiText(String rawText) {
    String cleaned = rawText;

    // 直接由程序生成图片 URL，不再依赖 AI 输出标签
    _aiImageUrl = '${Config.wordImageBaseUrl}${args.word.spell}';

    // 进一步清理 AI 输出：移除所有特殊 token 和残留的标签
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_start\|>.*?(\n|$)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>.*?(\n|$)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|imgr\|.*?\|(?:imgr\|)+'), ''); // 移除任何残留的完整标签
    cleaned = cleaned.replaceAll(RegExp(r'(?:imgr\|)+'), ''); // 移除孤立的重复 imgr|
    cleaned = cleaned.replaceAll('<|imgr|', '');

    // 移除 "assistant\n" 或 "assistant: " 这种多余的开头/残留
    cleaned = cleaned.replaceAll(RegExp(r'(assistant|user|system)\s*(:|\n)', caseSensitive: false), '');

    // 移除旧 prompt 残留（system/user 指令内容）
    cleaned = cleaned.replaceAll(RegExp(r'你是一个简洁的英语老师.*?解释：', dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'解释单词:.*?词汇数据:.*?\n', dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'You are a helpful.*?Chinese learners\.', dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'You explain words.*?Chinese\.', dotAll: true), '');

    // 移除开头和结尾的空白及多余空行
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n'); // 压缩连续空行

    return cleaned;
  }

  /// 解析 AI 原始输出，分离思考过程 和 最终答案
  void _parseAiOutput(String raw) {
    String? thought;
    String? answer;
    bool thoughtComplete = false;

    final thinkStart = raw.indexOf('<think>');
    if (thinkStart != -1) {
      final thinkEnd = raw.indexOf('</think>', thinkStart);
      if (thinkEnd != -1) {
        // </think> 已生成，思考完成
        thought = raw.substring(thinkStart + 7, thinkEnd).trim();
        answer = raw.substring(thinkEnd + 8).trim();
        thoughtComplete = true;
      } else {
        // </think> 还没生成，整段都是思考
        thought = raw.substring(thinkStart + 7).trim();
        answer = '';
      }
    } else {
      // 没有 <think> 标签
      answer = raw.trim();
    }

    setState(() {
      // 在对话模式下，我们将最新的输出动态更新到最后一条 assistant 消息中
      if (_chatMessages.isNotEmpty && _chatMessages.last.role == MessageRole.assistant) {
        _chatMessages.last.content = _cleanAiText(answer ?? '');
        _chatMessages.last.thought = thought;
      }
      _aiThoughtComplete = thoughtComplete;
    });
    
    // 自动滚动到底部
    _scrollToBottom();
  }

  void _scrollToBottom({bool force = false}) {
    if (_chatScrollController.hasClients) {
      // 检查当前是否在底部（允许 50 像素误差）。
      // 注意：由于 addPostFrameCallback 还没运行，此时的 maxScrollExtent 还是旧内容的。
      // 因此 isAtBottom 表示：在加入新内容之前，用户是否已经处于当时的底部。
      final isAtBottom = _chatScrollController.offset >= _chatScrollController.position.maxScrollExtent - 50;
      
      // 如果用户不再底部，且不是强制滚动（如发送新消息），则不执行自动滚动，让用户停留在当前位置
      if (!isAtBottom && !force) {
        return;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendChatMessage(String userText) async {
    if (userText.trim().isEmpty || _aiLoading) return;

    setState(() {
      _chatMessages.add(ChatMessage(role: MessageRole.user, content: userText));
      _chatMessages.add(ChatMessage(role: MessageRole.assistant, content: '', thought: ''));
      _aiLoading = true;
      _aiError = null;
      _aiRawAccum = '';
      _aiThoughtComplete = false;
    });
    _chatInputController.clear();
    _scrollToBottom(force: true);

    try {
      final service = AiService();
      final runtime = service.runtime;
      if (runtime is MacOsAiRuntime) {
        await _aiPartialSub?.cancel();
        _aiPartialSub = runtime.partialStream.listen((delta) {
          if (!mounted) return;
          _aiRawAccum += delta;
          _parseAiOutput(_aiRawAccum);
        });
      }

      // 构建历史消息 payload
      final historyPayload = _chatMessages
          .where((m) => m.content.isNotEmpty || m.thought != null)
          .take(_chatMessages.length - 1) // 不包含当前正在生成的这一条
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final response = await service.runTask(AiRequest(
        type: AiTaskType.chat,
        payload: {'messages': historyPayload},
      ));

      await _aiPartialSub?.cancel();
      _aiPartialSub = null;

      if (response.success) {
        setState(() {
          _aiLoading = false;
          _parseAiOutput(response.text ?? '');
        });
      } else {
        setState(() {
          _aiError = response.errorMessage;
          _aiLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _aiError = e.toString();
        _aiLoading = false;
      });
    }
  }

  Future<void> _prefetchAiExplanation() async {
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiRawAccum = '';
      _chatMessages.clear();
      // 初始化第一条 assistant 消息用于流式接收
      _chatMessages.add(ChatMessage(role: MessageRole.assistant, content: '', thought: ''));
      _aiThoughtComplete = false;
    });
    
    try {
      final service = AiService();
      final runtime = service.runtime;
      if (runtime is MacOsAiRuntime) {
        await _aiPartialSub?.cancel();
        _aiPartialSub = runtime.partialStream.listen((delta) {
          if (!mounted) return;
          _aiRawAccum += delta;
          _parseAiOutput(_aiRawAccum);
        });
      }

      // 为小模型提供更多上下文：把本地词典释义和例句传给 Prompt 构建器
      final mergedMeaningItems = args.word.getMergedMeaningItems();
      final meaningPayload = mergedMeaningItems
          .map((mi) => {
                'cn': ((mi.ciXing ?? '').trim().isEmpty
                        ? ''
                        : '${mi.ciXing} ')
                    + (mi.meaning ?? ''),
              })
          .toList();

      // 获取至少3个例句作为上下文
      final allSentences = await args.word.getSentences();
      final sentencePayload = allSentences.take(3).map((s) => {
        'en': s.english,
        'cn': s.chinese,
      }).toList();

      final request = AiRequest(
        type: AiTaskType.explainWord,
        payload: {
          'spell': args.word.spell,
          'phonetics': args.word.mergedPronounce ?? '',
          'partOfSpeech': mergedMeaningItems.isNotEmpty ? (mergedMeaningItems.first.ciXing ?? '') : '',
          'meanings': meaningPayload,
          'sentences': sentencePayload,
          'shortDesc': args.word.shortDesc,
        },
      );
      final response = await service.runTask(request);
      
      await _aiPartialSub?.cancel();
      _aiPartialSub = null;
      
      if (response.success) {
        if (mounted) {
          setState(() {
            _parseAiOutput(response.text ?? '');
            if (_chatMessages.last.thought != null && _chatMessages.last.thought!.isNotEmpty && !_aiThoughtComplete) {
              _aiThoughtComplete = true;
            }
            _aiLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _aiError = response.errorMessage ?? 'AI 解释失败';
            _aiLoading = false;
          });
        }
      }
    } catch (e, st) {
      await _aiPartialSub?.cancel();
      _aiPartialSub = null;
      Global.logger.e('AI explainWord exception', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _aiError = 'AI 解释失败: $e';
          _aiLoading = false;
        });
      }
    }
  }

  Future<void> _playWithAnimation(Future<void> Function() playSound, String audioType) async {
    // 启动当前动画前，先停止其他所有正在播放的动画
    _stopAllExcept(audioType);

    _playingStates[audioType]!.value = true;
    if (!mounted) return;

    // 只更新特定的控制器状态
    final controller = audioType == 'word' ? _wordSoundController : _getSentenceController(audioType);
    controller.repeat();

    try {
      await playSound();
    } finally {
      if (mounted) {
        _playingStates[audioType]!.value = false;
        // 停止动画
        controller.stop();
        controller.reset();
      }
    }
  }

  /// 停止除指定 audioType 外的所有动画与播放状态
  void _stopAllExcept(String audioType) {
    for (final entry in _playingStates.entries) {
      final type = entry.key;
      final state = entry.value;
      if (type != audioType && state.value) {
        state.value = false;
        final controller = type == 'word' ? _wordSoundController : _sentenceSoundControllers[type];
        if (controller != null) {
          controller.stop();
          controller.reset();
        }
      }
    }
  }

  Widget renderPage() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDarkMode
              ? [
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E),
                ]
              : [
                  const Color(0xFFF8F9FA),
                  const Color(0xFFF1F3F5),
                ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 单词拼写及释义
          Container(
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: Column(
                children: [
                  Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              ),
                              Container(),
                            ],
                          ),
                        ),
                        Text(args.word.spell,
                            style: TextStyle(
                                color: isWrongWord ? Colors.red : Global.highlight, fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (Util.getWordDefaultPronounce(args.word).isNotEmpty)
                              Text('[${Util.getWordDefaultPronounce(args.word)}]',
                                  style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 16, fontFamily: 'NotoSans')),
                            Transform.translate(
                              offset: const Offset(6.0, 2.0),
                              child: InkWell(
                                child: AnimatedBuilder(
                                  animation: _wordSoundController,
                                  builder: (context, child) {
                                    return Transform.translate(
                                      offset: Offset(_wordSoundController.value < 0.5 ? 0 : -2, 0),
                                      child: Icon(
                                        _playingStates['word']!.value
                                            ? (_wordSoundController.value < 0.5 ? Icons.volume_up : Icons.volume_down)
                                            : Icons.volume_up,
                                        color: _playingStates['word']!.value ? Colors.teal[300] : Colors.grey[500],
                                        size: 24,
                                      ),
                                    );
                                  },
                                ),
                                onTap: () {
                                  if (!_playingStates['word']!.value && !_audioPlayerDisposed) {
                                    _playWithAnimation(() async {
                                      try {
                                        await SoundUtil.playPronounceSound2(args.word, audioPlayer);
                                      } catch (e) {
                                        // 忽略 AudioPlayer 错误
                                        Global.logger.d("播放发音失败: $e");
                                      }
                                    }, 'word');
                                  }
                                },
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(leftPadding, 8, rightPadding, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('释义', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.5, fontFamily: 'NotoSansSC')),
                        const SizedBox(height: 8),
                        for (var meaningItem in args.word.getMergedMeaningItems())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((meaningItem.ciXing ?? '').isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      meaningItem.ciXing!,
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: _buildTextSpans(meaningItem.meaning!),
                                    ),
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 详情/形近词
          Expanded(
            child: DefaultTabController(
              length: calcTabsCount(),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2A2A3E).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.5) : Colors.grey[300]!.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: TabBar(
                        labelStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                        labelColor: isDarkMode ? Colors.white : Colors.black,
                        unselectedLabelColor: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                        indicatorColor: AppTheme.primaryColor,
                        indicatorWeight: 2,
                        tabs: [
                          const Tab(text: '详情'),
                          if (hasSimilarWords()) Tab(text: '形近词(${args.word.similarWords!.length})'),
                          if (hasSynonyms()) Tab(text: "近义词(${calcSynonymCount()})"),
                          const Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_awesome, size: 14),
                                SizedBox(width: 4),
                                Text('AI 解释'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: const BouncingScrollPhysics(),
                        dragStartBehavior: DragStartBehavior.down,
                        children: [
                          renderDetail(), 
                          if (hasSimilarWords()) renderSimilarWords(), 
                          if (hasSynonyms()) renderSynonyms(),
                          renderAiExplanation(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部下一词按钮
          if (args.bottomBtn != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Center(
                child: args.bottomBtn!,
              ),
            ),
        ],
      ),
    );
  }

  int calcTabsCount() {
    int count = 1;
    if (hasSimilarWords()) {
      count++;
    }
    if (hasSynonyms()) {
      count++;
    }
    // AI 解释 Tab 始终存在
    count++;
    return count;
  }

  bool hasSimilarWords() {
    return args.word.similarWords != null && args.word.similarWords!.isNotEmpty;
  }

  int calcSynonymCount() {
    var count = 0;
    for (var meaningItem in args.word.meaningItems!) {
      if (meaningItem.synonyms != null && meaningItem.synonyms!.isNotEmpty) {
        count += meaningItem.synonyms!.length;
      }
    }
    return count;
  }

  bool hasSynonyms() {
    return calcSynonymCount() > 0;
  }

  /// 将 Markdown 文本渲染为 Flutter Widget（支持基本格式）
  Widget _buildMarkdownText(String text, bool isDarkMode) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (var line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // ### 三级标题
      if (line.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              line.substring(4),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey[200] : Colors.grey[900],
              ),
            ),
          ),
        );
        continue;
      }

      // ## 二级标题
      if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Text(
              line.substring(3),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? Colors.grey[100] : Colors.grey[900],
              ),
            ),
          ),
        );
        continue;
      }

      // # 一级标题
      if (line.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 10),
            child: Text(
              line.substring(2),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDarkMode ? Colors.grey[100] : Colors.black,
              ),
            ),
          ),
        );
        continue;
      }

      // - 列表项
      if (line.trim().startsWith('- ')) {
        final content = line.trim().substring(2);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
                Expanded(
                  child: _buildInlineMarkdown(content, isDarkMode),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 普通段落
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildInlineMarkdown(line, isDarkMode),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// 处理行内 Markdown 格式（**粗体**、*斜体*）
  Widget _buildInlineMarkdown(String text, bool isDarkMode) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    var lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // 添加匹配前的普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      // **粗体**
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }
      // *斜体*
      else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      // `代码`
      else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: isDarkMode 
                  ? Colors.grey[800]?.withValues(alpha: 0.5) 
                  : Colors.grey[200]?.withValues(alpha: 0.8),
              color: isDarkMode ? Colors.purple[300] : Colors.purple[700],
            ),
          ),
        );
      }

      lastEnd = match.end;
    }

    // 添加剩余的普通文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: 14,
        height: 1.6,
        color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
      ),
    );
  }

  Widget renderAiExplanation() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Column(
      children: [
        // 对话记录列表
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final msg = _chatMessages[index];
              return _buildChatMessageWidget(msg, isDarkMode);
            },
          ),
        ),
        
        // 错误提示
        if (_aiError != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red[400]?.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _aiError!,
                    style: TextStyle(fontSize: 12, color: Colors.red[400]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: () => _prefetchAiExplanation(),
                )
              ],
            ),
          ),

        // 输入框区域
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF16213E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2A2A3E) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _chatInputController,
                    decoration: const InputDecoration(
                      hintText: '问问 AI 关于这个词...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 14),
                    ),
                    onSubmitted: (val) => _sendChatMessage(val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _aiLoading 
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: Icon(Icons.send, color: AppTheme.primaryColor),
                    onPressed: () => _sendChatMessage(_chatInputController.text),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatMessageWidget(ChatMessage msg, bool isDarkMode) {
    final isAssistant = msg.role == MessageRole.assistant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // 角色标识
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAssistant)
                Icon(Icons.auto_awesome, size: 14, color: Colors.purple[400])
              else
                Icon(Icons.person, size: 14, color: Colors.teal[400]),
              const SizedBox(width: 4),
              Text(
                isAssistant ? 'AI 助手' : '你',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isAssistant ? Colors.purple[400] : Colors.teal[400],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          
          // 思考过程 (仅助手且有内容时显示)
          if (isAssistant && msg.thought != null && msg.thought!.isNotEmpty)
            _buildThoughtWidget(msg.thought!, isDarkMode),

          // 消息正文
          Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            decoration: BoxDecoration(
              color: isAssistant
                  ? (isDarkMode ? const Color(0xFF2A2A3E) : const Color(0xFFF0F4FF))
                  : (isDarkMode ? const Color(0xFF3F3F5A) : AppTheme.primaryColor),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isAssistant ? 0 : 12),
                bottomRight: Radius.circular(isAssistant ? 12 : 0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isAssistant && _chatMessages.indexOf(msg) == 0 && _aiImageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _aiImageUrl!.endsWith('.png') ? _aiImageUrl! : '$_aiImageUrl.png',
                        errorBuilder: (c, e, s) => Container(),
                      ),
                    ),
                  ),
                if (msg.content.isEmpty && isAssistant && _aiLoading && _chatMessages.lastIndexOf(msg) == _chatMessages.length - 1)
                  const Text('...', style: TextStyle(fontStyle: FontStyle.italic))
                else if (isAssistant)
                  _buildMarkdownText(msg.content, isDarkMode)
                else
                  Text(
                    msg.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThoughtWidget(String thought, bool isDarkMode) {
    final showLoading = !_aiThoughtComplete && _aiLoading && _chatMessages.last.thought == thought;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showLoading)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(Icons.lightbulb_outline, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                showLoading ? '正在思考中...' : '已完成思考',
                style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            thought,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  ListView renderDetail() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Column(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 单词讲解
                if (args.word.shortDesc != null && args.word.shortDesc!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Color(0xFF4A90E2)),
                            const SizedBox(width: 8),
                            const Text('讲解',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.5, fontFamily: 'NotoSansSC')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Util.makeEnglishSpanText(args.word.shortDesc!, args.word.spell, true, context, false, null, false, FontWeight.w400)
                      ],
                    ),
                  ),

                // 例句
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.format_quote, size: 16, color: Color(0xFF4A90E2)),
                              const SizedBox(width: 8),
                              const Text('短语 & 例句',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.5, fontFamily: 'NotoSansSC')),
                            ],
                          ),
                          Row(
                            children: [
                              const Text('编辑', style: TextStyle(fontSize: 13, color: Colors.grey)),
                              Transform.scale(
                                scale: 0.7,
                                child: Switch(
                                  value: isEditMode,
                                  onChanged: (value) {
                                    setState(() {
                                      isEditMode = value;
                                    });
                                  },
                                  activeThumbColor: const Color(0xFF4A90E2),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 例句内容或空状态
                      if (args.word.sentences != null && args.word.sentences!.isNotEmpty)
                        // 有例句时显示例句列表
                        for (var sent in args.word.sentences!)
                          InkWell(
                            onTap: () {
                              if (!(_playingStates[sent.id]!.value)) {
                                _playWithAnimation(() => SoundUtil.playSentenceSound2(sent.englishDigest!, audioPlayer), sent.id);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Util.makeEnglishSpanText(
                                                sent.english!, args.word.spell, true, context, false, null, false, FontWeight.w400),
                                            if (isEditMode)
                                              Text.rich(TextSpan(children: [
                                                for (var span in renderSentenceEditSpans(sent)) span,
                                              ])),
                                          ],
                                        ),
                                      ),
                                      AnimatedBuilder(
                                        animation: _getSentenceController(sent.id),
                                        builder: (context, child) {
                                          return Icon(
                                            _playingStates[sent.id]!.value
                                                ? (_getSentenceController(sent.id).value < 0.5 ? Icons.volume_up : Icons.volume_down)
                                                : Icons.volume_up_outlined,
                                            color: _playingStates[sent.id]!.value ? Colors.teal[300] : Colors.grey[400],
                                            size: 16,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  renderSentenceChinese(sent.chinese!, sent.id)
                                ],
                              ),
                            ),
                          )
                      else
                        // 没有例句时显示空状态提示
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.library_books_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '暂无例句',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '该单词目前没有例句内容',
                                style: TextStyle(fontSize: 14, color: Colors.grey[500], fontFamily: 'NotoSansSC'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  ListView renderSimilarWords() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        if (args.word.similarWords != null && args.word.similarWords!.isNotEmpty)
          // 有形近词时显示列表
          for (var similarWord in args.word.similarWords!)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: InkWell(
                onTap: () {
                  SoundUtil.playPronounceSound(similarWord);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      similarWord.spell,
                      style: const TextStyle(fontSize: 18, color: Color(0xFF4A90E2), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (var meaningItem in Util.mergeMeaningItems(similarWord.meaningItems!))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${meaningItem.ciXing} ${meaningItem.meaning!}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
        else
          // 没有形近词时显示空状态提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.text_fields_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无形近词',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '该单词目前没有形近词内容',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  ListView renderSynonyms() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    // 仅显示有同义词的释义项
    final itemsWithSynonyms = [
      for (var mi in args.word.meaningItems!)
        if (mi.synonyms != null && mi.synonyms!.isNotEmpty) mi
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        if (itemsWithSynonyms.isNotEmpty)
          for (var meaningItem in itemsWithSynonyms)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((meaningItem.meaning ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        meaningItem.meaning!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4A90E2),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var synonym in meaningItem.synonyms!)
                        InkWell(
                          onTap: () {
                            SoundUtil.playPronounceSoundBySpell(synonym.spell);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A90E2).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF4A90E2).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              synonym.spell,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF4A90E2),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[300]!.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.group_work_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无同义词',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '该单词目前没有同义词内容',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<InlineSpan> renderSentenceEditSpans(SentenceVo sentence) {
    var spans = <InlineSpan>[];
    spans.add(WidgetSpan(
        child: Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: FutureBuilder<bool>(
          future: sentenceHasBeenVoted(sentence),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return InkWell(
                onTap: () async {
                  if (snapshot.data!) {
                    ToastUtil.error('不能重复投票');
                    return;
                  }
                  var result = await Api.client.handSentence(sentence.id, args.word.spell, Global.getLoggedInUser()?.id ?? '');
                  if (result.success) {
                    MyDatabase.instance.votedSentencesDao
                        .createEntity(VotedSentence(userId: Global.getLoggedInUser()!.id, sentenceId: sentence.id, vote: 'HAND'));
                    sentence.handCount += 1;
                    await MyDatabase.instance.sentencesDao.updateHandCount(sentence.id, sentence.handCount);
                    setState(() {});
                  } else {
                    ToastUtil.error(result.msg!);
                  }
                },
                child: Wrap(
                  children: [
                    Icon(
                      Icons.favorite_outline,
                      size: 14,
                      color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context),
                    ),
                    Text(' ${sentence.handCount}',
                        style: TextStyle(fontSize: 9, color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context))),
                  ],
                ),
              );
            } else {
              return Container();
            }
          }),
    )));

    spans.add(WidgetSpan(
        child: Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 0, 0),
      child: FutureBuilder<bool>(
          future: sentenceHasBeenVoted(sentence),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return InkWell(
                onTap: () async {
                  if (snapshot.data!) {
                    ToastUtil.error('不能重复投票');
                    return;
                  }
                  var result = await Api.client.footSentence(sentence.id, args.word.spell, Global.getLoggedInUser()?.id ?? '');
                  if (result.success) {
                    MyDatabase.instance.votedSentencesDao
                        .createEntity(VotedSentence(userId: Global.getLoggedInUser()!.id, sentenceId: sentence.id, vote: 'FOOT'));
                    sentence.footCount += 1;
                    await MyDatabase.instance.sentencesDao.updateFootCount(sentence.id, sentence.footCount);
                    setState(() {});
                  } else {
                    ToastUtil.error(result.msg!);
                  }
                },
                child: Wrap(
                  children: [
                    Icon(
                      Icons.heart_broken_outlined,
                      size: 14,
                      color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context),
                    ),
                    Text(' ${sentence.footCount}',
                        style: TextStyle(fontSize: 9, color: snapshot.data! ? Util.voteColorDisabled(context) : Util.voteColorEnabled(context)))
                  ],
                ),
              );
            } else {
              return Container();
            }
          }),
    )));

    // 删除例句
    if (sentence.author.id == Global.getLoggedInUser()!.id) {
      spans.add(WidgetSpan(
          child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 0, 0),
        child: InkWell(
          onTap: () async {
            var result = await Api.client.deleteSentence(sentence.id, args.word.spell, Global.getLoggedInUser()?.id ?? '');
            if (result.success) {
              var sentenceIndex = getSentenceIndex(sentence.id);
              if (sentenceIndex != -1) {
                args.word.sentences!.removeAt(sentenceIndex);
              }
              setState(() {});
            } else {
              ToastUtil.error(result.msg!);
            }
          },
          child: Wrap(
            children: [
              Icon(
                Icons.delete_outline,
                size: 14,
                color: Util.voteColorEnabled(context),
              ),
              const Text(' 删除', style: TextStyle(fontSize: 8))
            ],
          ),
        ),
      )));
    }

    return spans;
  }


  Future<bool> sentenceHasBeenVoted(var sentence) async {
    return (await MyDatabase.instance.votedSentencesDao.getVotedSentenceById(Global.getLoggedInUser()!.id, sentence.id)) != null;
  }

  Widget renderSentenceChinese(String sentenceChinese, String sentenceId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
            margin: const EdgeInsets.fromLTRB(0, 6, 0, 0),
            child: Util.makeChineseSpanText(
              sentenceChinese,
              context,
              style: const TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 14,
                height: 1.4,
              ),
            )),
      ],
    );
  }

  addNewSentenceToCache(SentenceVo newSentence) {
    setState(() {
      args.word.sentences!.add(newSentence);
    });
  }

  Future<void> refreshSentence(var sentenceId) async {
    var index = getSentenceIndex(sentenceId);
    if (index != -1) {
      var sentenceFromServer = await WordBo().getSentence(sentenceId);
      args.word.sentences![index] = sentenceFromServer;
      setState(() {});
    }
  }

  int getSentenceIndex(var sentenceId) {
    for (var i = 0; i < args.word.sentences!.length; i++) {
      var sentence = args.word.sentences![i];
      if (sentence.id == sentenceId) {
        return i;
      }
    }
    return -1;
  }

  Future<void> showAddChineseDlg(BuildContext dialogContext, SentenceVo sentence) async {
    var votedSentence = await MyDatabase.instance.votedSentencesDao.getVotedSentenceById(Global.getLoggedInUser()!.id, sentence.id);
    sentence.voted = votedSentence != null;
    sentenceChineseController.text = '';

    // 检查组件是否仍然挂载
    if (!mounted) return;

    // 在底部显示对话框
    showGeneralDialog(
        context: context, // 使用 State 的 context
        barrierDismissible: false,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 100),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FractionalTranslation(
              translation: Offset(0, 1 - animation.value), // 从底部出现
              child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(builder: (context, setState) {
            return Align(
                alignment: const Alignment(0, 1),
                child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: 200,
                    margin: MediaQuery.of(context).viewInsets,
                    // 当软键盘弹出时，对话框自动上移
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    color: context.read<DarkMode>().isDarkMode ? const Color(0xff333333) : Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              Column(
                                children: [
                                  Container(
                                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                      child: Row(
                                        children: [
                                          Flexible(
                                              child: Util.makeEnglishSpanText(
                                                  sentence.english!, args.word.spell, true, context, false, null, false, FontWeight.w400)),
                                        ],
                                      )),
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                    child: TextField(
                                      maxLines: 3,
                                      controller: sentenceChineseController, //or null
                                      decoration: const InputDecoration.collapsed(hintText: "输入翻译内容"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('取消'),
                              onPressed: () {
                                Navigator.pop(context, false);
                              },
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('确定'),
                              onPressed: () async {
                                // 保存当前的context
                                final currentContext = context;
                                var result = await Api.client.saveSentenceChinese(sentence.id, sentenceChineseController.text, args.word.spell);

                                if (result.success) {
                                  refreshSentence(sentence.id);
                                  ToastUtil.info('成功');
                                  if (currentContext.mounted) {
                                    Navigator.pop(currentContext, false);
                                  }
                                } else {
                                  ToastUtil.error(result.msg!);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    )));
          });
        });
  }

  showAddSentenceDlg(BuildContext dialogContext) {
    sentenceEnglishController.text = '';
    sentenceChineseController.text = '';

    // 检查组件是否仍然挂载
    if (!mounted) return;

    // 在底部显示对话框
    showGeneralDialog(
        context: context, // 使用 State 的 context
        barrierDismissible: false,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 100),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FractionalTranslation(
              translation: Offset(0, 1 - animation.value), // 从底部出现
              child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(builder: (context, setState) {
            return Align(
                alignment: const Alignment(0, 1),
                child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: 200,
                    margin: MediaQuery.of(context).viewInsets,
                    // 当软键盘弹出时，对话框自动上移
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    color: context.read<DarkMode>().isDarkMode ? const Color(0xff333333) : Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                    child: TextField(
                                      maxLines: 2,
                                      controller: sentenceEnglishController, //or null
                                      decoration: const InputDecoration.collapsed(hintText: "输入例句英文内容"),
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                    child: TextField(
                                      maxLines: 2,
                                      controller: sentenceChineseController, //or null
                                      decoration: const InputDecoration.collapsed(hintText: "输入翻译内容"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('取消'),
                              onPressed: () {
                                Navigator.pop(context, false);
                              },
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('确定'),
                              onPressed: () async {
                                // 保存当前的context
                                final currentContext = context;
                                var result = await Api.client.saveSentence(sentenceEnglishController.text, sentenceChineseController.text,
                                    args.word.id!, 0, args.word.spell, Global.getLoggedInUser()?.id ?? '');

                                if (result.success) {
                                  addNewSentenceToCache(result.data!);
                                  ToastUtil.info('成功');
                                  if (currentContext.mounted) {
                                    Navigator.pop(currentContext, false);
                                  }
                                } else {
                                  ToastUtil.error(result.msg!);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    )));
          });
        });
  }

  AnimationController _getSentenceController(String sentenceId) {
    if (!_sentenceSoundControllers.containsKey(sentenceId)) {
      _sentenceSoundControllers[sentenceId] = AnimationController(
        duration: const Duration(milliseconds: 700),
        vsync: this,
      );
      _playingStates[sentenceId] = ValueNotifier(false);
    }
    return _sentenceSoundControllers[sentenceId]!;
  }

  List<TextSpan> _buildTextSpans(String text) {
    final List<TextSpan> spans = [];
    // 先处理分号和逗号的组合
    text = text.replaceAll(RegExp(r'[,，]?[;；]'), '；');
    // 删除末尾的分号和逗号
    while (text.endsWith(';') || text.endsWith('；') || text.endsWith(',') || text.endsWith('，')) {
      text = text.substring(0, text.length - 1);
    }
    // 删除连续的分号
    text = text.replaceAll(RegExp(r'[;；]+'), '；');
    // 删除连续的逗号
    text = text.replaceAll(RegExp(r'[,，]+'), '，');

    spans.add(TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: 'NotoSansSC',
        height: 1.4,
      ),
    ));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('加载失败'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(errorMessage ?? '发生错误', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        hasError = false;
                        errorMessage = null;
                        dataLoaded = false;
                      });
                      loadData();
                    },
                    child: const Text('重试'),
                  ),
                ],
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: null,
      body: Container(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: (!dataLoaded) ? const Center(child: CircularProgressIndicator()) : renderPage(),
      ),
    );
  }
}
