import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/models/bdc_page_args.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../util/study_config.dart';
import '../util/subscription_util.dart';
import '../util/utils.dart';
import 'pic_search.dart';


class WordDetailPageArgs {
  late WordVo word;

  /// 是否需要重新查询word （word对象可能来自本地，信息并不完整）
  late bool needReQueryWord;

  Widget? bottomBtn;

  /// 本次是否回答错误
  late bool isThisAnswerWrong;

  /// 优先展示这些词库的资源
  List<String>? priorityDictIds;

  /// 是否在底部显示"下一词"按钮（从背单词页面进入时设置为 true）
  bool showNextWordButton;

  /// "下一词"按钮点击时的预拉取回调：在详情页 Pop 之前静默执行切词，
  /// 消除 Pop 后主页的旧词停留和二次卡片淡入。
  final Future<void> Function()? onNextWord;

  WordDetailPageArgs(this.word, this.needReQueryWord, this.bottomBtn, this.isThisAnswerWrong,
      {this.priorityDictIds, this.showNextWordButton = false, this.onNextWord});

  @override
  String toString() {
    return 'WordDetailPageParams{word: $word, needReQueryWord: $needReQueryWord, isThisAnswerWrong: $isThisAnswerWrong, priorityDictIds: $priorityDictIds, showNextWordButton: $showNextWordButton}';
  }
}

enum MessageRole { user, assistant }

class ChatMessage {
  final MessageRole role;
  String content;
  String? thought;
  bool isThoughtExpanded;

  ChatMessage({
    required this.role,
    required this.content,
    this.thought,
    this.isThoughtExpanded = false,
  });
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
  bool _isLoadingData = false;
  bool _isLoadingNextWord = false;
  bool hasError = false;
  String? errorMessage;
  final Map<String, Future<bool>> _voteFutures = {};

  Future<bool> _getVoteFuture(SentenceVo sentence) {
    return _voteFutures.putIfAbsent(sentence.id, () => sentenceHasBeenVoted(sentence));
  }

  bool isWrongWord = false; // 是否是错词
  bool _isTopDrawerExpanded = true;
  static const double leftPadding = 16;
  static const double rightPadding = 16;
  late final StudyAudioSessionController sessionController;
  bool _sessionDisposed = false;
  var sentenceEnglishController = TextEditingController();
  var sentenceChineseController = TextEditingController();
  var isEditMode = false;

  // AI 解释相关 (已升级为 AI 对话)
  late TabController _tabController;
  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  bool _aiLoading = false;
  String? _aiError;
  String _aiRawAccum = '';
  StreamSubscription<String>? _aiPartialSub;
  bool _aiThoughtComplete = false; // 思考内容是否生成完成
  bool _canUseAiAssistant = false;

  // Animation controllers
  late final AnimationController _wordSoundController;
  final Map<String, AnimationController> _sentenceSoundControllers = {};

  // Track playing states
  final Map<String, ValueNotifier<bool>> _playingStates = {
    'word': ValueNotifier(false),
  };

  late WordDetailPageArgs args;
  Future<List<SentenceVo>>? _sentencesFuture;

  int _lastTabIndex = 0;

  // 词根/词缀拓展单词相关状态
  final Map<String, List<CigenExpandedWord>?> _expandedCigenWords = {};
  final Map<String, bool> _cigenExpandedState = {};
  final Map<String, bool> _cigenLoadingState = {};

  void _onTabControllerChanged() {
    if (!mounted) return;
    final index = _tabController.index;
    if (index == _lastTabIndex) return;
    _lastTabIndex = index;
    // 切换到 AI 助教 Tab 时自动收起抽屉
    if (_canUseAiAssistant && index == calcTabsCount() - 1 && _isTopDrawerExpanded) {
      _isTopDrawerExpanded = false;
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    sessionController = StudyAudioSessionController();
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // 初始化 TabController，提供默认长度以免在异常退出 dispose 时报 LateInitializationError
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_onTabControllerChanged);

    // 进入详情页时，统一将音频状态机转换到 idle 状态，优雅关闭麦克风，平滑物理淡出所有活跃音频流并物理释放硬件资源
    unawaited(sessionController.stopSession(forceStopMicrophone: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 同步提取参数以更新 TabController 初始状态
    if (GoRouterState.of(context).extra != null) {
      args = GoRouterState.of(context).extra as WordDetailPageArgs;
      _canUseAiAssistant = Global.getLoggedInUser()?.isAdmin == true || SubscriptionUtil.isPremium();
      final count = calcTabsCount();
      if (count != _tabController.length) {
        _tabController.dispose();
        _tabController = TabController(length: count, vsync: this);
        _tabController.addListener(_onTabControllerChanged);
      }
    }

    // 只有在数据未加载时才加载
    if (!dataLoaded) {
      loadData();
    }
  }

  @override
  void dispose() {
    _wordSoundController.dispose();
    for (var controller in _sentenceSoundControllers.values) {
      controller.dispose();
    }
    _tabController.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();

    _sessionDisposed = true;
    sessionController.dispose();

    super.dispose();
  }

  Future<bool> checkArgs() async {
    if (GoRouterState.of(context).extra == null) {
      Future.delayed(Duration.zero, () async {
        // 延迟到下一个tick执行，避免导航冲突
        await Prefs.write("BdcPageArgs", BdcPageArgs('word_detail').toJson());
        if (!mounted) return;
        context.push('/bdc');
      });
      return false;
    }
    args = GoRouterState.of(context).extra as WordDetailPageArgs;
    return true;
  }

  Future<void> loadData() async {
    if (_isLoadingData || dataLoaded) {
      return;
    }
    _isLoadingData = true;

    if (!await checkArgs()) {
      _isLoadingData = false;
      return;
    }
    try {
    if (args.needReQueryWord) {
      try {
        // 使用新的根据ID查词方法，传入用户ID进行词书过滤，并支持优先词书
        var result = await WordBo().searchWordById(args.word.id!, Global.getLoggedInUser()?.id, priorityDictIds: args.priorityDictIds);
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
          // 使用新的根据ID查词方法，传入用户ID进行词书过滤，并支持优先词书
          var result = await WordBo().searchWordById(args.word.id!, Global.getLoggedInUser()?.id, priorityDictIds: args.priorityDictIds);
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

    _sentencesFuture = args.word.getSentences();

    setState(() {
      final newLength = calcTabsCount();
      if (_tabController.length != newLength) {
        _tabController.dispose();
        _tabController = TabController(length: newLength, vsync: this);
        _tabController.addListener(_onTabControllerChanged);
      }
      dataLoaded = true;
    });

    final links = args.word.cigenWordLinks;
    if (links != null) {
      for (final link in links) {
        final cigen = link.cigen;
        _cigenExpandedState[cigen.id] = true;
        _loadCigenExpandedWords(cigen.id);
      }
    }


    if (_canUseAiAssistant) {
      _prefetchAiExplanation();
    }

    // 自动播放单词发音
    if (!_sessionDisposed) {
      _playWithAnimation(() async {
        try {
          await sessionController.playWordAndSentence(
            args.word,
            sentenceDigest: null,
            playWord: true,
            playSentence: false,
            isSpeakMode: false,
          );
        } catch (e) {
          Global.logger.d("自动播放发音失败: $e");
        }
      }, 'word');
    }
    } finally {
      _isLoadingData = false;
    }
  }

  String _cleanAiText(String rawText) {
    String cleaned = rawText;

    // _validateAndSetImageUrl();

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

    // 处理大模型顽固的中英文标点混用（修复类似 "I’ m", "don’ t", "cat’ s" 的全角加空格问题）
    cleaned = cleaned.replaceAllMapped(
      RegExp(r"[’‘”`]\s*(s|m|t|ve|re|ll|d)\b", caseSensitive: false),
      (match) => "'${match.group(1)}"
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r"([a-zA-Z])\s*[’‘”`]\s*([a-zA-Z])"),
      (match) => "${match.group(1)}'${match.group(2)}"
    );

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
    FocusScope.of(context).unfocus();


    try {
      final runtime = AiService().runtime;
      // 统一监听所有平台的增量流 (Android/iOS/macOS)
      await _aiPartialSub?.cancel();
      _aiPartialSub = runtime.partialStream.listen((delta) {
        if (!mounted) return;
        _aiRawAccum += delta;
        _parseAiOutput(_aiRawAccum);
      });

      // 准备完整的待选历史 (最多 10 条)
      final allValidMessages = _chatMessages.where((m) => m.content.isNotEmpty || (m.thought != null && m.thought!.isNotEmpty)).toList();

      var historyPayload = allValidMessages
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      if (historyPayload.length > 10) {
        historyPayload = historyPayload.sublist(historyPayload.length - 10);
      }

      // 执行推理任务
      final response = await AiService().runTask(AiRequest(
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
    } catch (e, st) {
      Global.logger.e('Chat error', error: e, stackTrace: st);
      setState(() {
        _aiError = e.toString();
        _aiLoading = false;
      });
    }
  }

  Future<void> _loadCigenExpandedWords(String cigenId) async {
    if (_expandedCigenWords.containsKey(cigenId)) return;
    _cigenLoadingState[cigenId] = true;
    setState(() {});
    try {
      final userId = Global.getLoggedInUser()?.id;
      final words = await WordBo().getCigenExpandedWords(
        cigenId, userId,
        excludeWordId: args.word.id,
      );
      _expandedCigenWords[cigenId] = words;
    } catch (e) {
      Global.logger.e('加载词根拓展词失败: $e');
      _expandedCigenWords[cigenId] = [];
    } finally {
      _cigenLoadingState[cigenId] = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _prefetchAiExplanation() async {
    if (!_canUseAiAssistant) return;
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

      // 统一监听流式输出
      await _aiPartialSub?.cancel();
      _aiPartialSub = runtime.partialStream.listen((delta) {
        if (!mounted) return;
        _aiRawAccum += delta;
        _parseAiOutput(_aiRawAccum);
      });

      // 为小模型提供更多上下文：把本地词典释义和例句传给 Prompt 构建器
      final mergedMeaningItems = args.word.getMergedMeaningItems();
      final meaningPayload = mergedMeaningItems
          .map((mi) => {
                'cn': ((mi.ciXing ?? '').trim().isEmpty ? '' : '${mi.ciXing} ') + (mi.meaning ?? ''),
              })
          .toList();

      // 获取至少3个例句作为上下文
      final allSentences = await args.word.getSentences();
      final sentencePayload = allSentences
          .take(3)
          .map((s) => {
                'en': s.english,
                'cn': s.chinese,
              })
          .toList();

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
            _aiError = response.errorMessage;
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
          _aiError = e.toString();
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
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom) * 0.45,
            ),
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
            child: SingleChildScrollView(
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
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.grey[200] : Colors.grey[700]),
                              ),
                              Container(),
                            ],
                          ),
                        ),
                        Text(args.word.spell,
                            style: TextStyle(
                                color: isWrongWord ? Colors.red : Global.highlight, 
                                fontSize: _isTopDrawerExpanded ? 36 : 24, 
                                fontWeight: FontWeight.w500, 
                                letterSpacing: 0.5)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (Util.getWordDefaultPronounce(args.word).isNotEmpty)
                              Text('[${Util.getWordDefaultPronounce(args.word)}]',
                                  style: TextStyle(color: isDarkMode ? Colors.grey[200] : Colors.grey[700], fontSize: 16, fontFamily: 'NotoSans')),
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
                                  if (!_playingStates['word']!.value && !_sessionDisposed) {
                                    _playWithAnimation(() async {
                                      try {
                                        await sessionController.playWordAndSentence(
                                          args.word,
                                          sentenceDigest: null,
                                          playWord: true,
                                          playSentence: false,
                                          isSpeakMode: false,
                                        );
                                      } catch (e) {
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
                  
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: (_isTopDrawerExpanded && MediaQuery.of(context).viewInsets.bottom <= 0) ? Column(
                      children: [
                    // 配图展示
                    if (StudyConfig.fromCurrentUser().enableWordImage && args.word.images != null && args.word.images!.isNotEmpty)
                      Builder(
                        builder: (BuildContext context) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          double imageWidth = (screenWidth - leftPadding - rightPadding - 8) / 2.0; // 横排两张的合适宽度
                          if (imageWidth > 120.0) {
                            imageWidth = 120.0; // 限制最大宽度，避免图片过大占用太多纵向空间
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(leftPadding, 16, rightPadding, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8, 
                                  runSpacing: 8,
                                  children: [
                                    ...args.word.images!.take(2).map((image) => Stack(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                                          ),
                                          child: Builder(
                                            builder: (context) {
                                              final imageUrl = Uri.encodeFull('${Config.imgBaseUrl}word/${image.imageFile}');
                                              Global.logger.d('加载单词图片 [详情页]: $imageUrl');
                                              return Image.network(
                                                imageUrl,
                                                width: imageWidth,
                                                height: imageWidth * 0.75, // 比例 4:3
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  Global.logger.e('图片加载失败 [详情页]: $imageUrl', error: error);
                                                  return Container(
                                                    width: imageWidth,
                                                    height: imageWidth * 0.75,
                                                    color: Colors.grey[200],
                                                    child: const Icon(Icons.broken_image, color: Colors.red),
                                                  );
                                                },
                                              );
                                            }
                                          ),
                                        ),
                                        if (image.status == 'PENDING')
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                      ),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text('AI审核中', style: TextStyle(color: Colors.white, fontSize: 10)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    )),
                                    if (args.word.images!.length < 2)
                                      InkWell(
                                        onTap: () {
                                          context.push('/pic_search',
                                                  extra: PicSearchPageArgs(
                                                      args.word.id!,
                                                      args.word.spell))
                                              .then((value) => loadData());
                                        },
                                        child: Container(
                                          width: imageWidth,
                                          height: imageWidth * 0.75,
                                          decoration: BoxDecoration(
                                            color: isDarkMode ? Colors.white10 : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.withValues(alpha: 0.2), style: BorderStyle.none),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.add_a_photo_outlined, color: Colors.grey[500], size: 28),
                                              const SizedBox(height: 4),
                                              Text('添加配图', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              ],
                            ),
                          );
                        }
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
                                        color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
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
                    ) : const SizedBox(width: double.infinity),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _isTopDrawerExpanded = !_isTopDrawerExpanded;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white24
                                : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ), 
            ),
            ),
          ),

          // 详情/形近词
          Expanded(
            child: Container(
                key: ValueKey('detail_tabs_${calcTabsCount()}_${args.word.id}'),
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
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        controller: _tabController,
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
                        unselectedLabelColor: isDarkMode ? Colors.grey[300] : const Color(0xFF4B5563),
                        indicatorColor: AppTheme.primaryColor,
                        indicatorWeight: 2,
                        tabs: [
                          const Tab(text: '详情'),
                          if (hasSimilarWords()) Tab(text: '形近词(${args.word.similarWords!.length})'),
                          if (hasSynonyms()) Tab(text: "近义词(${calcSynonymCount()})"),
                          if (hasCigen()) Tab(text: '词根词缀(${args.word.cigenWordLinks!.length})'),
                          if (_canUseAiAssistant)
                            const Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_awesome, size: 14),
                                  SizedBox(width: 4),
                                  Text('AI 助教'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded( 
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (ScrollUpdateNotification notification) {
                          if (notification.metrics.axis == Axis.horizontal) return false;
                          
                          // 只有当用户往下看内容（上滑手指）时，收起抽屉
                          if (notification.dragDetails != null && notification.scrollDelta != null) {
                            if (notification.scrollDelta! > 0.0 && _isTopDrawerExpanded) {
                              setState(() { _isTopDrawerExpanded = false; });
                            }
                          }
                          
                          // 当用户往上回看内容（下滑手指），且接近最顶部时，展开启抽屉
                          if (notification.scrollDelta != null && notification.scrollDelta! < -1.0 && notification.metrics.pixels <= 5.0 && !_isTopDrawerExpanded) {
                            setState(() { _isTopDrawerExpanded = true; });
                          }
                          
                          return false;
                        },
                        child: TabBarView( 
                          controller: _tabController,
                          physics: const NeverScrollableScrollPhysics(),
                          dragStartBehavior: DragStartBehavior.down,
                          children: [
                            renderDetail(),
                            if (hasSimilarWords()) renderSimilarWords(),
                            if (hasSynonyms()) renderSynonyms(),
                            if (hasCigen()) renderCigenAffix(),
                            if (_canUseAiAssistant) renderAiExplanation(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 底部下一词按钮 (在 AI 抽屉激活时隐藏，以免挤占空间)
          if (args.bottomBtn != null && !(_canUseAiAssistant && _tabController.index == calcTabsCount() - 1))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 24.0),
              child: args.bottomBtn!,
            ),

          // 从背单词页面进入时，显示"下一词"按钮
          if (args.showNextWordButton && args.bottomBtn == null
              && !(_canUseAiAssistant && _tabController.index == calcTabsCount() - 1))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 24.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.watch<DarkMode>().isDarkMode
                      ? Colors.white
                      : AppTheme.primaryColor,
                  foregroundColor: context.watch<DarkMode>().isDarkMode
                      ? Colors.black
                      : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoadingNextWord
                    ? null
                    : () async {
                        if (args.onNextWord != null) {
                          setState(() => _isLoadingNextWord = true);
                          try {
                            await args.onNextWord!();
                          } finally {
                            if (mounted) {
                              setState(() => _isLoadingNextWord = false);
                              context.pop(true);
                            }
                          }
                        } else {
                          context.pop(true);
                        }
                      },
                child: _isLoadingNextWord
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.watch<DarkMode>().isDarkMode
                              ? AppTheme.primaryColor
                              : Colors.white,
                        ),
                      )
                    : const Text('下一词',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    if (hasCigen()) {
      count++;
    }
    // AI 解释 Tab 仅管理员可见
    if (_canUseAiAssistant) {
      count++;
    }
    return count;
  }

  bool hasCigen() {
    return args.word.cigenWordLinks != null && args.word.cigenWordLinks!.isNotEmpty;
  }

  int getCigenTabIndex() {
    int index = 1; // 详情 Tab 是 0
    if (hasSimilarWords()) {
      index++;
    }
    if (hasSynonyms()) {
      index++;
    }
    return index;
  }

  bool hasSimilarWords() {
    return args.word.similarWords != null && args.word.similarWords!.isNotEmpty;
  }

  int calcSynonymCount() {
    var count = 0;
    if (args.word.meaningItems == null) {
      return 0;
    }
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

  Widget renderCigenAffix() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final links = args.word.cigenWordLinks;
    if (links != null && links.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final link = links[index];
          final cigen = link.cigen;

          String categoryText = '关联';
          Color tagBgColor;
          Color tagTextColor;
          if (cigen.category == 'PREFIX') {
            categoryText = '前缀';
            tagBgColor = isDarkMode ? const Color(0xFF0C4A6E) : const Color(0xFFE0F2FE);
            tagTextColor = isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
          } else if (cigen.category == 'SUFFIX') {
            categoryText = '后缀';
            tagBgColor = isDarkMode ? const Color(0xFF581C87) : const Color(0xFFF3E8FF);
            tagTextColor = isDarkMode ? const Color(0xFFC084FC) : const Color(0xFF6B21A8);
          } else if (cigen.category == 'ROOT') {
            categoryText = '词根';
            tagBgColor = isDarkMode ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
            tagTextColor = isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
          } else {
            tagBgColor = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
            tagTextColor = isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
          }

          final String mainSpell = cigen.spell ?? cigen.description;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode 
                  ? const Color(0xFF1E1E2D).withValues(alpha: 0.95) 
                  : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 词根/词缀 头部栏 (拼写 + 词性Chip + 释义) - 已做防溢出包裹升级
                Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              mainSpell,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagBgColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: tagTextColor.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              categoryText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tagTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (cigen.meaningCn != null && cigen.meaningCn!.isNotEmpty)
                      Flexible(
                        child: Text(
                          '含义: ${cigen.meaningCn}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: tagTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // 拆解详细卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? Colors.black.withValues(alpha: 0.15) 
                        : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 16,
                          color: tagTextColor.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          link.theExplain,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 相同词根/词缀的单词拓展区域
                const SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    final expanded = _cigenExpandedState[cigen.id] ?? false;
                    setState(() {
                      _cigenExpandedState[cigen.id] = !expanded;
                    });
                    if (!expanded) {
                      _loadCigenExpandedWords(cigen.id);
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        (_cigenExpandedState[cigen.id] ?? false)
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: tagTextColor,
                      ),
                      const SizedBox(width: 4),
                      Builder(
                        builder: (context) {
                          final expandedWords = _expandedCigenWords[cigen.id];
                          final countSuffix = expandedWords != null && expandedWords.isNotEmpty
                              ? ' (共 ${expandedWords.length} 个)'
                              : '';
                          return Text(
                            '相同$categoryText的单词$countSuffix',
                            style: TextStyle(
                              fontSize: 13,
                              color: tagTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (_cigenExpandedState[cigen.id] == true)
                  _buildCigenExpandedWords(cigen.id, isDarkMode, tagTextColor),
              ],
            ),
          );
        },
      );
    } else {
      // 备用空状态渲染
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  Icons.account_tree_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无词根数据',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildCigenExpandedWords(String cigenId, bool isDarkMode, Color tagTextColor) {
    final isLoading = _cigenLoadingState[cigenId] ?? false;
    final words = _expandedCigenWords[cigenId];

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (words == null || words.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '暂无其他相同词根/词缀的单词',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      );
    }

    // 按具体的词根/词缀拼写分组
    final Map<String, List<CigenExpandedWord>> groupedWords = {};
    for (final item in words) {
      final cat = item.category;
      groupedWords.putIfAbsent(cat, () => []).add(item);
    }
    final categoriesOrder = groupedWords.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 4),
          for (final cat in categoriesOrder)
            if (groupedWords.containsKey(cat)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tagTextColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: tagTextColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              ...groupedWords[cat]!.take(20).map((item) {
                final status = item.learningStatus;

                Color? chipColor;
                String? chipText;
                if (status == true) {
                  chipColor = Colors.green;
                  chipText = '已掌握';
                } else if (status == false) {
                  chipColor = Colors.orange;
                  chipText = '学习中';
                }

                final spell = item.word.spell;
                final desc = item.word.shortDesc ?? '';
                final lowerDesc = desc.toLowerCase().trim();
                final lowerSpell = spell.toLowerCase().trim();

                Widget contentWidget;
                if (desc.isNotEmpty && lowerDesc.startsWith(lowerSpell)) {
                  int matchLength = spell.length;
                  while (matchLength < desc.length && (desc[matchLength] == ' ' || desc[matchLength] == ':' || desc[matchLength] == '：')) {
                    matchLength++;
                  }
                  final matchedSpell = desc.substring(0, matchLength);
                  final remaining = desc.substring(matchLength);

                  contentWidget = RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
                        height: 1.45,
                      ),
                      children: [
                        TextSpan(
                          text: matchedSpell,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontStyle: item.inDict ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                        TextSpan(
                          text: remaining,
                          style: TextStyle(
                            fontStyle: item.inDict ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  contentWidget = RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
                        height: 1.45,
                      ),
                      children: [
                        TextSpan(
                          text: '$spell ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontStyle: item.inDict ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                        TextSpan(
                          text: desc,
                          style: TextStyle(
                            fontStyle: item.inDict ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                        ? Colors.white.withValues(alpha: 0.03) 
                        : Colors.black.withValues(alpha: 0.015),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode 
                          ? Colors.white.withValues(alpha: 0.06) 
                          : Colors.black.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context.push('/word_detail',
                        extra: WordDetailPageArgs(
                          item.word, true, null, false,
                          priorityDictIds: args.priorityDictIds,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: contentWidget,
                          ),
                          if (chipText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: chipColor!.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: chipColor.withValues(alpha: 0.3), width: 0.5),
                              ),
                              child: Text(
                                chipText,
                                style: TextStyle(fontSize: 9, color: chipColor, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
        ],
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
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _aiError = null),
                )
              ],
            ),
          ),

        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 12, (MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 8)),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF16213E) : Colors.white,
            border: Border(top: BorderSide(color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.03))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _chatInputController,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '向助教提问...',
                    hintStyle: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  ),
                  style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white : Colors.black87),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _aiLoading ? null : () {
                  if (_chatInputController.text.trim().isNotEmpty) {
                    _sendChatMessage(_chatInputController.text.trim());
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: _aiLoading ? Colors.transparent : AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: _aiLoading 
                    ? Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)))
                    : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [

          // 思考过程 (仅助教且有内容时显示)
          if (isAssistant && msg.thought != null && msg.thought!.isNotEmpty) _buildThoughtWidget(msg, isDarkMode),

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
                // 已遗弃旧版_aiImageUrl展示机制的残留，这里不再显示旧图
                if (msg.content.isEmpty && isAssistant && _aiLoading && _chatMessages.lastIndexOf(msg) == _chatMessages.length - 1)
                  const Text('...', style: TextStyle(fontStyle: FontStyle.italic))
                else if (isAssistant)
                  MarkdownBody(
                    data: msg.content,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null && href.startsWith('suggest:')) {
                        _sendChatMessage(text);
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[300] : Colors.grey[800], height: 1.5),
                      h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black),
                      h2: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black),
                      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black),
                      listBullet: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[300] : Colors.grey[800]),
                      tableBody: TextStyle(fontSize: 13, color: isDarkMode ? Colors.grey[300] : Colors.grey[800]),
                      tableHead: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black),
                      tableBorder: TableBorder.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!, width: 0.5),
                      tableCellsPadding: const EdgeInsets.all(8),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        backgroundColor: isDarkMode ? Colors.grey[800]?.withValues(alpha: 0.5) : Colors.grey[200]?.withValues(alpha: 0.8),
                        color: isDarkMode ? Colors.purple[300] : Colors.purple[700],
                      ),
                    ),
                  )
                else
                  SelectableText(
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

  Widget _buildThoughtWidget(ChatMessage msg, bool isDarkMode) {
    final thought = msg.thought!;
    final isCurrentMsg = _chatMessages.isNotEmpty && _chatMessages.last == msg;
    final isThinking = isCurrentMsg && _aiLoading && !_aiThoughtComplete;

    // 如果正在思考，则强制展开；否则遵循用户的折叠状态
    final isExpanded = isThinking || msg.isThoughtExpanded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: isThinking
                ? null
                : () {
                    setState(() {
                      msg.isThoughtExpanded = !msg.isThoughtExpanded;
                    });
                  },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  if (isThinking)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Icon(Icons.lightbulb_outline, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isThinking ? '正在思考中...' : 'AI 的思考过程',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isThinking)
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectableText(
                thought,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
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
                // 词根解析 (已精简为精美跳转条，点击一键平滑跳转到专属 Tab)
                if (args.word.cigenWordLinks != null && args.word.cigenWordLinks!.isNotEmpty)
                  InkWell(
                    onTap: () {
                      _tabController.animateTo(getCigenTabIndex());
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDarkMode 
                            ? const Color(0xFF1E1E2D).withValues(alpha: 0.8) 
                            : const Color(0xFFF3F4F6).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 15,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '词根助记: ',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              args.word.cigenWordLinks!.first.theExplain,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '查看',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

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
                      FutureBuilder<List<SentenceVo>>(
                        future: _sentencesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final sentences = snapshot.data ?? [];
                          if (sentences.isNotEmpty) {
                            return Column(
                              children: [
                                // 有例句时显示例句列表
                                for (var sent in sentences)
                                  InkWell(
                                    onTap: () {
                                      if (!(_playingStates[sent.id]!.value)) {
                                        _playWithAnimation(() => sessionController.playWordAndSentence(
                                          args.word,
                                          sentenceDigest: sent.englishDigest,
                                          playWord: false,
                                          playSentence: true,
                                          isSpeakMode: false,
                                        ), sent.id);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? const Color(0xFF1E1E2D).withValues(alpha: 0.95)
                                            : const Color(0xFFFAFAFA).withValues(alpha: 0.95),
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
                                  ),
                              ],
                            );
                          } else {
                            // 没有例句时显示空状态提示
                            return Container(
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
                            );
                          }
                        },
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


  Widget renderSimilarWords() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final similarWords = args.word.similarWords;
    if (similarWords != null && similarWords.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: similarWords.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final word = similarWords[index];
          return InkWell(
            onTap: () {
              // 直接跳转到详情页，不需要中间的抽屉过渡
              context.push('/word_detail', 
                extra: WordDetailPageArgs(word, true, null, false, priorityDictIds: args.priorityDictIds),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? const Color(0xFF1E1E2D).withValues(alpha: 0.8) 
                    : const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Text(
                    word.spell,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      word.getMeaningStr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 10,
                    color: isDarkMode ? Colors.white24 : Colors.black12,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // 没有形近词时显示空状态提示
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          future: _getVoteFuture(sentence),
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
                    final now = AppClock.now();
                    await MyDatabase.instance.votedSentencesDao.createEntity(VotedSentence(
                        userId: Global.getLoggedInUser()!.id,
                        sentenceId: sentence.id,
                        vote: 'HAND',
                        createTime: now,
                        updateTime: now));
                    sentence.handCount += 1;
                    await MyDatabase.instance.sentencesDao.updateHandCount(sentence.id, sentence.handCount);
                    _voteFutures[sentence.id] = Future.value(true);
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
          future: _getVoteFuture(sentence),
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
                    final now = AppClock.now();
                    await MyDatabase.instance.votedSentencesDao.createEntity(VotedSentence(
                        userId: Global.getLoggedInUser()!.id,
                        sentenceId: sentence.id,
                        vote: 'FOOT',
                        createTime: now,
                        updateTime: now));
                    sentence.footCount += 1;
                    await MyDatabase.instance.sentencesDao.updateFootCount(sentence.id, sentence.footCount);
                    _voteFutures[sentence.id] = Future.value(true);
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
            onPressed: () => Navigator.of(context).pop(),
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
                    onPressed: () => Navigator.of(context).pop(),
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
      body: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: (!dataLoaded) ? const Center(child: CircularProgressIndicator()) : renderPage(),
        ),
      ),
    );
  }
}
