import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/local_embedding_cache.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/models/bdc_page_args.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../util/study_config.dart';
import '../util/subscription_util.dart';
import '../util/utils.dart';
import '../widget/pronunciation_accent_badge.dart';
import '../widget/sound_wave_icon.dart';
import 'bdc/widgets/word_images_widget.dart';
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

  /// 共享的音频会话控制器
  final StudyAudioSessionController? sessionController;

  WordDetailPageArgs(this.word, this.needReQueryWord, this.bottomBtn, this.isThisAnswerWrong,
      {this.priorityDictIds, this.showNextWordButton = false, this.onNextWord, this.sessionController});

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
  StudyAudioSessionController? _sessionController;

  StudyAudioSessionController get sessionController => _sessionController!;
  bool _sessionDisposed = false;
  var sentenceEnglishController = TextEditingController();
  var sentenceChineseController = TextEditingController();
  var isEditMode = false;

  // AI 解释相关 (已升级为 AI 对话)
  late TabController _tabController;
  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final FocusNode _chatInputFocusNode = FocusNode();
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
  bool _showCigenTip = true;
  double _cumulativeScroll = 0.0;
  DateTime? _lastDrawerActionTime;
  int _totalCigenWordsCount = 0;

  // 语境拓展相关状态
  List<WordVo> _semanticSimilarWords = [];
  bool _showSemanticTip = true;
  bool _showSimilarTip = true;
  final Map<String, bool> _wordInDictStatus = {};
  bool _isLoadingSemanticSimilar = false;
  List<String> _semanticSimilarWordIds = [];

  // 生词本收藏状态
  bool _isInRawWordDict = false;
  bool _isTogglingRawWord = false;

  Future<void> _checkRawWordStatus() async {
    final user = Global.getLoggedInUser();
    if (user != null && args.word.id != null) {
      final rawDict = await MyDatabase.instance.dictsDao.findUserRawDict(user.id);
      if (rawDict != null) {
        final dw = await MyDatabase.instance.dictWordsDao.getById(rawDict.id, args.word.id!);
        if (mounted) {
          setState(() {
            _isInRawWordDict = dw != null;
          });
        }
      }
    }
  }

  Future<void> _toggleRawWord() async {
    if (_isTogglingRawWord) return;
    final user = Global.getLoggedInUser();
    if (user == null) {
      ToastUtil.error('请先登录');
      return;
    }
    setState(() {
      _isTogglingRawWord = true;
    });
    try {
      if (_isInRawWordDict) {
        final res = await WordBo().deleteRawWord(args.word.id!);
        if (res.success) {
          ToastUtil.info('已移出生词本');
          if (mounted) {
            setState(() {
              _isInRawWordDict = false;
            });
          }
        } else {
          ToastUtil.error(res.msg ?? '移出生词本失败');
        }
      } else {
        final res = await WordBo().addRawWord(args.word.spell, '详情页收藏');
        if (res.success) {
          ToastUtil.info('已加入生词本');
          if (mounted) {
            setState(() {
              _isInRawWordDict = true;
            });
          }
        } else {
          ToastUtil.error(res.msg ?? '加入生词本失败');
        }
      }
    } catch (e, st) {
      Global.logger.e('切换生词本状态失败', error: e, stackTrace: st);
      ToastUtil.error('操作失败');
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingRawWord = false;
        });
      }
    }
  }

  void _onTabControllerChanged() {
    if (!mounted) return;
    final index = _tabController.index;
    if (index == _lastTabIndex) return;
    _lastTabIndex = index;
    // 切换到 AI 助教 Tab 时自动收起抽屉
    if (_canUseAiAssistant && index == calcTabsCount() - 1 && _isTopDrawerExpanded) {
      _isTopDrawerExpanded = false;
      _cumulativeScroll = 0.0;
      _lastDrawerActionTime = DateTime.now();
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _showCigenTip = Prefs.read<bool>('show_cigen_tip') ?? true;
    _showSemanticTip = Prefs.read<bool>('show_semantic_tip') ?? true;
    _showSimilarTip = Prefs.read<bool>('show_similar_tip') ?? true;
    _wordSoundController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // 初始化 TabController，提供默认长度以免在异常退出 dispose 时报 LateInitializationError
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_onTabControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 同步提取参数以更新 TabController 初始状态
    if (GoRouterState.of(context).extra != null) {
      args = GoRouterState.of(context).extra as WordDetailPageArgs;

      if (_sessionController == null) {
        if (args.sessionController != null) {
          _sessionController = args.sessionController;
        } else {
          _sessionController = StudyAudioSessionController();
          // 进入详情页时，统一将音频状态机转换到 idle 状态，优雅关闭麦克风，平滑物理淡出所有活跃音频流并物理释放硬件资源
          unawaited(_sessionController!.stopSession(forceStopMicrophone: true));
        }
      }

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
    _chatInputFocusNode.dispose();
    _chatScrollController.dispose();

    _sessionDisposed = true;

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

    int totalCount = 0;
    final cigenLinks = args.word.cigenWordLinks;
    if (cigenLinks != null && cigenLinks.isNotEmpty) {
      final cigenIds = cigenLinks.map((l) => l.cigen.id).toList();
      final db = MyDatabase.instance;
      final query = db.selectOnly(db.cigenWordLinks)
        ..addColumns([db.cigenWordLinks.wordId])
        ..where(db.cigenWordLinks.cigenId.isIn(cigenIds));
      final results = await query.get();
      final uniqueWordIds = results.map((r) => r.read(db.cigenWordLinks.wordId)).toSet();
      totalCount = uniqueWordIds.length;
    }
    _totalCigenWordsCount = totalCount;
    await _checkRawWordStatus();

    setState(() {
      final newLength = calcTabsCount();
      if (_tabController.length != newLength) {
        _tabController.dispose();
        _tabController = TabController(length: newLength, vsync: this);
        _tabController.addListener(_onTabControllerChanged);
      }
      dataLoaded = true;
    });

    // 在第一帧秒开渲染后，以非阻塞的异步方式在后台计算相似ID、拉取单词详情及进行词库状态判断
    if (LocalEmbeddingCache.instance.isInitialized) {
      _isLoadingSemanticSimilar = true;
      unawaited(() async {
        try {
          // 1. 异步在 Isolate 中检索相似单词 ID，不阻塞 UI 渲染 tick
          final similarResults = await LocalEmbeddingCache.instance.findSimilarWords(args.word.id!, limit: 9);
          final filteredResults = similarResults.where((res) => res.distance < 500).toList();
          final similarIds = filteredResults.map((res) => res.wordId).toList();
          final distanceMap = {for (var res in filteredResults) res.wordId: res.distance};

          // 2. 批量拉取拓展单词拼写与释义详情
          final tempSemanticWords = await _getSimpleWordsByIds(similarIds);
          
          // 3. 批量查询形近词与拓展词在词书内状态
          final allRelatedIds = <String>[];
          if (args.word.similarWords != null) {
            allRelatedIds.addAll(args.word.similarWords!.map((w) => w.id!));
          }
          allRelatedIds.addAll(similarIds);
          await _checkWordsInDict(allRelatedIds);

          // 按照是否在词书内（正体字排在斜体字前面）和形近程度（原始相似度排序）排序形近词
          _sortSimilarWords();

          // 按照是否在词书内（在的排前面）和汉明距离（小的排前面）排序拓展词
          tempSemanticWords.sort((a, b) {
            final aInDict = _wordInDictStatus[a.id!] ?? true;
            final bInDict = _wordInDictStatus[b.id!] ?? true;
            if (aInDict != bInDict) {
              return aInDict ? -1 : 1;
            }
            final aDist = distanceMap[a.id!] ?? 9999;
            final bDist = distanceMap[b.id!] ?? 9999;
            return aDist.compareTo(bDist);
          });

          final sortedIds = tempSemanticWords.map((w) => w.id!).toList();

          if (mounted) {
            setState(() {
              _semanticSimilarWordIds = sortedIds;
              _semanticSimilarWords = tempSemanticWords;
              _isLoadingSemanticSimilar = false;
            });
          }
        } catch (e, st) {
          Global.logger.e('异步加载拓展单词失败', error: e, stackTrace: st);
          if (mounted) {
            setState(() {
              _isLoadingSemanticSimilar = false;
            });
          }
        }
      }());
    } else {
      // 降级：仅批量查询形近词在词书范围状态
      final allRelatedIds = <String>[];
      if (args.word.similarWords != null) {
        allRelatedIds.addAll(args.word.similarWords!.map((w) => w.id!));
      }
      if (allRelatedIds.isNotEmpty) {
        unawaited(_checkWordsInDict(allRelatedIds).then((_) {
          _sortSimilarWords();
          if (mounted) setState(() {});
        }));
      }
    }

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
        currentWordId: args.word.id,
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

  Future<void> _checkWordsInDict(List<String> wordIds) async {
    if (wordIds.isEmpty) return;
    final userId = Global.getLoggedInUser()?.id;
    final db = MyDatabase.instance;
    final Set<String> inDictWordIds = {};

    try {
      if (userId != null && userId.isNotEmpty) {
        final learningDicts = await (db.select(db.learningDicts)
          ..where((tbl) => tbl.userId.equals(userId))).get();
        final selectedDictIds = learningDicts.map((d) => d.dictId).toList();

        if (selectedDictIds.isNotEmpty) {
          final expandedDictIds = <String>{...selectedDictIds};
          final dbDicts = await (db.select(db.dicts)
            ..where((d) => d.id.isIn(selectedDictIds))).get();
          for (final d in dbDicts) {
            if (d.baseDictId != null && d.baseDictId!.isNotEmpty) {
              expandedDictIds.add(d.baseDictId!);
            }
          }

          final miQuery = db.selectOnly(db.meaningItems)
            ..addColumns([db.meaningItems.wordId])
            ..where(db.meaningItems.wordId.isIn(wordIds))
            ..where(db.meaningItems.dictId.isIn(expandedDictIds));
          final miResults = await miQuery.get();

          inDictWordIds.addAll(miResults.map((r) => r.read(db.meaningItems.wordId)!));
        } else {
          inDictWordIds.addAll(wordIds);
        }

        // 批量检查是否有学习记录
        final learningStatusMap = await WordBo.getWordsLearningStatusBatch(userId, wordIds);
        for (final id in wordIds) {
          final hasRecord = learningStatusMap[id] != null;
          _wordInDictStatus[id] = inDictWordIds.contains(id) || hasRecord;
        }
      } else {
        for (final id in wordIds) {
          _wordInDictStatus[id] = true;
        }
      }
    } catch (e) {
      Global.logger.e('批量检查单词在词书状态失败: $e');
      for (final id in wordIds) {
        _wordInDictStatus[id] = true;
      }
    }
  }

  void _sortSimilarWords() {
    if (args.word.similarWords == null || args.word.similarWords!.isEmpty) return;

    // 记录原始索引以实现稳定排序（保持形近程度/相似度从高到低的次要顺序）
    final originalIndices = <String, int>{};
    for (int i = 0; i < args.word.similarWords!.length; i++) {
      final id = args.word.similarWords![i].id;
      if (id != null) {
        originalIndices[id] = i;
      }
    }

    args.word.similarWords!.sort((a, b) {
      final aInDict = _wordInDictStatus[a.id!] ?? true;
      final bInDict = _wordInDictStatus[b.id!] ?? true;
      if (aInDict != bInDict) {
        return aInDict ? -1 : 1;
      }
      final aIndex = originalIndices[a.id!] ?? 0;
      final bIndex = originalIndices[b.id!] ?? 0;
      return aIndex.compareTo(bIndex);
    });
  }

  Future<List<WordVo>> _getSimpleWordsByIds(List<String> wordIds) async {
    if (wordIds.isEmpty) return [];
    final db = MyDatabase.instance;
    try {
      final wordsQuery = db.select(db.words)..where((w) => w.id.isIn(wordIds));
      final localWords = await wordsQuery.get();
      if (localWords.isEmpty) return [];

      final wordVos = localWords.map((localWord) {
        return WordVo.c2(localWord.spell)
          ..id = localWord.id
          ..shortDesc = localWord.shortDesc
          ..longDesc = localWord.longDesc
          ..pronounce = localWord.pronounce
          ..americaPronounce = localWord.americaPronounce
          ..britishPronounce = localWord.britishPronounce
          ..popularity = localWord.popularity
          ..groupInfo = localWord.groupInfo;
      }).toList();

      final miQuery = db.select(db.meaningItems)..where((mi) => mi.wordId.isIn(wordIds));
      final allMeanings = await miQuery.get();

      final Map<String, List<MeaningItemVo>> meaningMap = {};
      for (final mi in allMeanings) {
        final miVo = MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null);
        meaningMap.putIfAbsent(mi.wordId, () => []).add(miVo);
      }

      for (final vo in wordVos) {
        vo.meaningItems = meaningMap[vo.id] ?? [];
      }

      final Map<String, WordVo> idToVo = {for (var vo in wordVos) vo.id!: vo};
      return wordIds.map((id) => idToVo[id]).whereType<WordVo>().toList();
    } catch (e, st) {
      Global.logger.e('批量精简查词失败', error: e, stackTrace: st);
      return [];
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

    // 先获取/初始化控制器与播放状态
    final controller = audioType == 'word' ? _wordSoundController : _getSentenceController(audioType);
    _playingStates[audioType]!.value = true;
    if (!mounted) return;
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
    final themeConfig = context.themeConfig;
    final isDarkMode = context.isDarkMode;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final cardBg = themeConfig.cardBg;
    final cardBorder = themeConfig.cardBorder;

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部单词概览大卡片（带可收起抽屉效果）
          Container(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom) * 0.45,
            ),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: themeConfig.cardShadows,
              border: Border(
                bottom: BorderSide(
                  color: cardBorder,
                  width: 1.2,
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部导航栏行
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 左侧返回按钮（纯净无底圈）
                              InkResponse(
                                radius: 20,
                                onTap: () => Navigator.of(context).pop(),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 18,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              Text(
                                '单词详情',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                              // 右侧操作区（收藏生词本 + 更多，纯净无底圈）
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 收藏生词本按钮
                                  InkResponse(
                                    radius: 20,
                                    onTap: _toggleRawWord,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        _isInRawWordDict ? Icons.star_rounded : Icons.star_outline_rounded,
                                        size: 23,
                                        color: _isInRawWordDict
                                            ? const Color(0xFFF59E0B)
                                            : textColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 更多按钮
                                  InkResponse(
                                    radius: 20,
                                    onTap: () => _showMoreOptions(context),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.more_horiz_rounded,
                                        size: 23,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 单词核心信息区（左对齐）
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              // 单词拼写大标题
                              Text(
                                args.word.spell,
                                style: TextStyle(
                                  color: isWrongWord
                                      ? Colors.redAccent
                                      : textColor,
                                  fontSize: _isTopDrawerExpanded ? 28 : 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // 音标发音行（轻灵极简无多余胶囊，支持口音切换与声浪动效）
                              ValueListenableBuilder<String>(
                                valueListenable: Prefs.pronunciationAccentNotifier,
                                builder: (context, _, __) {
                                  if (args.word.spell.isEmpty) return const SizedBox.shrink();
                                  final pronInfo = Util.getWordPronounceWithAccent(args.word);
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (pronInfo.$2.isNotEmpty) ...[
                                        PronunciationAccentBadge(
                                          label: pronInfo.$2,
                                          isFallback: pronInfo.$3,
                                          color: accentColor,
                                          onSwitched: (newAccent) async {
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
                                                  Global.logger.d("播放发音失败: $e");
                                                }
                                              }, 'word');
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      if (pronInfo.$1.isNotEmpty) ...[
                                        Text(
                                          '[${pronInfo.$1}]',
                                          style: TextStyle(
                                            color: subtitleColor,
                                            fontSize: 14,
                                            fontFamily: 'NotoSans',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
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
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: AnimatedBuilder(
                                            animation: _playingStates['word']!,
                                            builder: (context, child) {
                                              return ModernSoundWaveIcon(
                                                isPlaying: _playingStates['word']!.value,
                                                animationController: _wordSoundController,
                                                size: 16,
                                                color: subtitleColor,
                                                activeColor: accentColor,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      ValueListenableBuilder<AudioPlaybackStatus>(
                                        valueListenable: StudyAudioSessionController.instance.playbackStatusNotifier,
                                        builder: (context, status, child) {
                                          if (status.hasFallback && status.spell == args.word.spell) {
                                            return Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.amber.withValues(alpha: 0.35), width: 0.5),
                                              ),
                                              child: Text(
                                                status.fallbackType == AudioFallbackType.ttsFallback ? '系统朗读' : '备用发音',
                                                style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              // 释义区域（左对齐常驻清晰展示）
                              _buildMeaningSection(isDarkMode),
                            ],
                          ),
                        ),
                      ],
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
                                final availableWidth = screenWidth - leftPadding - rightPadding;
                                final estimatedWidth = (availableWidth - 10) / 2.0;
                                final imageHeight = (estimatedWidth * 0.58).clamp(88.0, 110.0);
                                final imageBorderColor = isDarkMode
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08);
                                final images = args.word.images!.take(2).toList();

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(leftPadding, 12, rightPadding, 4),
                                  child: Row(
                                    children: [
                                      for (int i = 0; i < images.length; i++) ...[
                                        if (i > 0) const SizedBox(width: 10),
                                        Expanded(
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () {
                                              showImagePreviewWithContext(
                                                context,
                                                images[i],
                                                onDeleted: () => _reloadWordData(),
                                              );
                                            },
                                            child: Container(
                                              height: imageHeight,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: imageBorderColor, width: 0.5),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(11.5),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Builder(
                                                      builder: (context) {
                                                        final imageUrl = Uri.encodeFull('${Config.imgBaseUrl}word/${images[i].imageFile}');
                                                        Global.logger.d('加载单词图片 [详情页]: $imageUrl');
                                                        return Image.network(
                                                          imageUrl,
                                                          height: imageHeight,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            Global.logger.e('图片加载失败 [详情页]: $imageUrl', error: error);
                                                            return Container(
                                                              color: isDarkMode ? const Color(0xFF1E293B) : Colors.grey[100],
                                                              child: Icon(Icons.broken_image_rounded, color: subtitleColor, size: 24),
                                                            );
                                                          },
                                                        );
                                                      },
                                                    ),
                                                    if (images[i].status == 'PENDING')
                                                      Positioned.fill(
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withValues(alpha: 0.55),
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
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (images.length < 2) ...[
                                        if (images.isNotEmpty) const SizedBox(width: 10),
                                        Expanded(
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () {
                                              context.push('/pic_search',
                                                      extra: PicSearchPageArgs(
                                                          args.word.id!,
                                                          args.word.spell))
                                                  .then((value) => _reloadWordData());
                                            },
                                            child: Container(
                                              height: imageHeight,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: imageBorderColor, width: 0.5),
                                                color: isDarkMode ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.grey[50],
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.add_photo_alternate_outlined, size: 22, color: subtitleColor),
                                                  const SizedBox(height: 4),
                                                  Text('添加配图', style: TextStyle(fontSize: 10.5, color: subtitleColor)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ) : const SizedBox(width: double.infinity),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _isTopDrawerExpanded = !_isTopDrawerExpanded;
                          _cumulativeScroll = 0.0;
                          _lastDrawerActionTime = DateTime.now();
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDarkMode
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

          // 详情/形近词等多维 Tab
          Expanded(
            child: Container(
                key: ValueKey('detail_tabs_${calcTabsCount()}_${args.word.id}'),
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cardBorder,
                    width: 1.2,
                  ),
                  boxShadow: themeConfig.cardShadows,
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: cardBorder,
                            width: 1,
                          ),
                        ),
                      ),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        controller: _tabController,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 14.0),
                        labelStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        labelColor: accentColor,
                        unselectedLabelColor: subtitleColor,
                        indicatorSize: TabBarIndicatorSize.label,
                        indicator: UnderlineTabIndicator(
                          borderRadius: BorderRadius.circular(2),
                          borderSide: BorderSide(
                            color: accentColor,
                            width: 2.8,
                          ),
                        ),
                        dividerColor: Colors.transparent,
                        tabs: [
                          const Tab(text: '详情'),
                          if (hasSimilarWords())
                            _buildTabItem('形近', args.word.similarWords!.length),
                          if (hasSynonyms())
                            _buildTabItem('近义', calcSynonymCount()),
                          if (hasCigen())
                            _buildTabItem('同根', _totalCigenWordsCount),
                          if (hasSemanticSimilarWords())
                            _buildTabItem('拓展', _isLoadingSemanticSimilar ? 9 : _semanticSimilarWordIds.length),
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
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          if (notification.metrics.axis == Axis.horizontal) return false;
                          
                          if (_lastDrawerActionTime != null &&
                              DateTime.now().difference(_lastDrawerActionTime!).inMilliseconds < 450) {
                            return false;
                          }
                          
                          if (notification is ScrollUpdateNotification) {
                            final scrollDelta = notification.scrollDelta;
                            if (scrollDelta != null) {
                              if (scrollDelta > 0.0) {
                                _cumulativeScroll = 0.0;
                                if (_isTopDrawerExpanded && notification.metrics.pixels > 10.0) {
                                  setState(() {
                                    _isTopDrawerExpanded = false;
                                    _lastDrawerActionTime = DateTime.now();
                                  });
                                }
                              } else if (scrollDelta < 0.0) {
                                if (notification.metrics.pixels <= 5.0 && !_isTopDrawerExpanded && notification.dragDetails != null) {
                                  _cumulativeScroll += scrollDelta.abs();
                                  if (_cumulativeScroll >= 90.0) {
                                    setState(() {
                                      _isTopDrawerExpanded = true;
                                      _lastDrawerActionTime = DateTime.now();
                                    });
                                    _cumulativeScroll = 0.0;
                                  }
                                } else {
                                  _cumulativeScroll = 0.0;
                                }
                              }
                            }
                          } else if (notification is OverscrollNotification) {
                            if (notification.overscroll < 0.0 && !_isTopDrawerExpanded && notification.dragDetails != null) {
                              _cumulativeScroll += notification.overscroll.abs();
                              if (_cumulativeScroll >= 90.0) {
                                setState(() {
                                  _isTopDrawerExpanded = true;
                                  _lastDrawerActionTime = DateTime.now();
                                });
                                _cumulativeScroll = 0.0;
                              }
                            }
                          } else if (notification is ScrollEndNotification) {
                            _cumulativeScroll = 0.0;
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
                            renderSemanticSimilarWords(),
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
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16.0, 6.0, 16.0, 10.0),
                child: args.bottomBtn!,
              ),
            ),

          // 从背单词页面进入时，显示"下一词"按钮（参考学习页面底部极简流转按钮风格）
          if (args.showNextWordButton && args.bottomBtn == null
              && !(_canUseAiAssistant && _tabController.index == calcTabsCount() - 1))
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                alignment: Alignment.center,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _isLoadingNextWord
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                      child: _isLoadingNextWord
                          ? SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '下一词',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  width: 20.0,
                                  height: 3.2,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: BorderRadius.circular(1.6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withValues(alpha: isDarkMode ? 0.45 : 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final accentColor = context.primaryColor;
    final textColor = isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final subColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.2),
      elevation: 0,
      builder: (BuildContext bottomSheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xC81E293B) // 78% 细腻深邃暗夜磨砂
                    : const Color(0xBFFFFFFF), // 75% 透光乳白高透磨砂
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.85),
                    width: 1.0,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 14),
                        width: 36,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      _buildActionTile(
                        icon: Icons.copy_rounded,
                        title: '复制单词及释义',
                        subtitle: '${args.word.spell} · [${Util.getWordDefaultPronounce(args.word)}]',
                        accentColor: accentColor,
                        textColor: textColor,
                        subColor: subColor,
                        isDarkMode: isDarkMode,
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          final copyText = '${args.word.spell} [${Util.getWordDefaultPronounce(args.word)}]\n${args.word.getMeaningStr()}';
                          Clipboard.setData(ClipboardData(text: copyText));
                          ToastUtil.success('已复制到剪贴板');
                        },
                      ),
                      const SizedBox(height: 6),
                      _buildActionTile(
                        icon: Icons.add_photo_alternate_rounded,
                        title: '添加或更换配图',
                        subtitle: '为该单词挑选生动的助记图片',
                        accentColor: accentColor,
                        textColor: textColor,
                        subColor: subColor,
                        isDarkMode: isDarkMode,
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          context.push('/pic_search',
                                  extra: PicSearchPageArgs(
                                      args.word.id!,
                                      args.word.spell))
                              .then((value) => _reloadWordData());
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDarkMode ? 0.18 : 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: subColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDarkMode ? Colors.white30 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reloadWordData() async {
    try {
      var result = await WordBo().searchWordById(
        args.word.id!,
        Global.getLoggedInUser()?.id,
        priorityDictIds: args.priorityDictIds,
      );
      if (result.word != null && mounted) {
        setState(() {
          args.word = result.word!;
          _isTopDrawerExpanded = true;
        });
      }
    } catch (e, st) {
      ErrorHandler.handleDatabaseError(e, st, operation: '刷新单词配图');
    }
  }

  Widget _buildMeaningSection(bool isDarkMode) {
    final mergedItems = args.word.getMergedMeaningItems();
    if (mergedItems.isNotEmpty) {
      final cixingColor = isDarkMode
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);

      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(),
        },
        children: [
          for (var meaningItem in mergedItems)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 6),
                  child: (meaningItem.ciXing ?? '').trim().isNotEmpty
                      ? Text(
                          (meaningItem.ciXing ?? '').trim(),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: cixingColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                            letterSpacing: 0.2,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      children: _buildTextSpans(meaningItem.meaning ?? ''),
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    // Fallback: 如果结构化释义项为空，直接以高亮解析展示完整释义字符串
    final fallbackMeaning = args.word.getMeaningStr();
    if (fallbackMeaning.isNotEmpty) {
      return Text.rich(
        TextSpan(
          children: _buildTextSpans(fallbackMeaning),
        ),
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTabItem(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
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
    if (hasSemanticSimilarWords()) {
      count++;
    }
    // AI 解释 Tab 仅管理员可见
    if (_canUseAiAssistant) {
      count++;
    }
    return count;
  }

  bool hasSemanticSimilarWords() {
    return LocalEmbeddingCache.instance.isInitialized;
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
      final showTip = _showCigenTip;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: showTip ? links.length + 1 : links.length,
        separatorBuilder: (context, index) {
          if (showTip && index == 0) return const SizedBox(height: 6);
          return Divider(
            height: 24,
            thickness: 0.5,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          );
        },
        itemBuilder: (context, index) {
          if (showTip && index == 0) {
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: isDarkMode ? 0.09 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 14,
                    color: context.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '注：浅灰色单词不在当前词书内，请酌情学习。',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                    onPressed: () async {
                      setState(() {
                        _showCigenTip = false;
                      });
                      await Prefs.write('show_cigen_tip', false);
                    },
                  ),
                ],
              ),
            );
          }

          final link = showTip ? links[index - 1] : links[index];
          final cigen = link.cigen;

          Color tagBgColor;
          Color tagTextColor;
          String categoryName;
          if (cigen.category == 'PREFIX') {
            tagBgColor = isDarkMode ? const Color(0x2638BDF8) : const Color(0xFFE0F2FE);
            tagTextColor = isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
            categoryName = '前缀 PREFIX';
          } else if (cigen.category == 'SUFFIX') {
            tagBgColor = isDarkMode ? const Color(0x26C084FC) : const Color(0xFFF3E8FF);
            tagTextColor = isDarkMode ? const Color(0xFFC084FC) : const Color(0xFF7C3AED);
            categoryName = '后缀 SUFFIX';
          } else if (cigen.category == 'ROOT') {
            tagBgColor = isDarkMode ? const Color(0x26FBBF24) : const Color(0xFFFEF3C7);
            tagTextColor = isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
            categoryName = '词根 ROOT';
          } else {
            tagBgColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
            tagTextColor = context.primaryColor;
            categoryName = '词缀 AFFIX';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagBgColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  categoryName,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tagTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _buildCigenExpandedWords(cigen.id, isDarkMode, tagTextColor),
            ],
          );
        },
      );
    } else {
      return _buildTabEmptyState(
        isDarkMode: isDarkMode,
        icon: Icons.account_tree_outlined,
        title: '暂无词根数据',
        subtitle: '该单词目前没有收录词根词缀内容',
      );
    }
  }

  Widget _buildCigenExpandedWords(String cigenId, bool isDarkMode, Color tagTextColor) {
    final isLoading = _cigenLoadingState[cigenId] ?? false;
    final words = _expandedCigenWords[cigenId];

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(tagTextColor),
            ),
          ),
        ),
      );
    }

    if (words == null || words.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '暂无其他相同词根/词缀的单词',
          style: TextStyle(
            fontSize: 12.5,
            color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in categoriesOrder)
          if (groupedWords.containsKey(cat)) ...[
            Builder(
              builder: (context) {
                final firstItem = groupedWords[cat]!.first;
                final cigenMeaning = firstItem.cigenMeaning;

                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: tagTextColor,
                        ),
                      ),
                      if (cigenMeaning != null && cigenMeaning.isNotEmpty) ...[
                        Text(
                          ' : ',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: tagTextColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            cigenMeaning,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            ...groupedWords[cat]!.take(20).map((item) {
              final spell = item.word.spell;
              final desc = item.word.shortDesc ?? '';
              final lowerSpell = spell.toLowerCase().trim();

              final Color spellColor = item.inDict
                  ? (isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A))
                  : (isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B));
              final Color descColor = item.inDict
                  ? (isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155))
                  : (isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8));

              // 解析释义部分与括号内的助记拆解公式
              String meaningPart = desc;
              String? formulaPart;
              final parenMatch = RegExp(r'[（\(](.*?)[）\)]$').firstMatch(desc.trim());
              if (parenMatch != null) {
                formulaPart = parenMatch.group(1)?.trim();
                meaningPart = desc.trim().substring(0, parenMatch.start).trim();
              }

              final lowerMeaning = meaningPart.toLowerCase();
              if (lowerMeaning.startsWith(lowerSpell)) {
                int cutLen = spell.length;
                while (cutLen < meaningPart.length && ' :：'.contains(meaningPart[cutLen])) {
                  cutLen++;
                }
                meaningPart = meaningPart.substring(cutLen).trim();
              }

              final contentWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          spell,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: spellColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (meaningPart.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            meaningPart,
                            style: TextStyle(
                              fontSize: 13,
                              color: descColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (!item.inDict) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '未选',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (formulaPart != null && formulaPart.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        formulaPart,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              );

              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  context.push(
                    '/word_detail',
                    extra: WordDetailPageArgs(
                      item.word,
                      true,
                      null,
                      false,
                      priorityDictIds: args.priorityDictIds,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(child: contentWidget),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: isDarkMode ? Colors.white24 : Colors.black26,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
      ],
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final msg = _chatMessages[index];
              return _buildChatMessageWidget(msg, isDarkMode);
            },
          ),
        ),

        // 快捷探索提示词（仅当消息较少时展示）
        if (_chatMessages.length <= 1)
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildQuickPromptChip('🎯 常用高频搭配与例句', isDarkMode),
                  const SizedBox(width: 8),
                  _buildQuickPromptChip('📖 趣味助记小故事', isDarkMode),
                  const SizedBox(width: 8),
                  _buildQuickPromptChip('⚠️ 常见易错辨析', isDarkMode),
                ],
              ),
            ),
          ),

        // 错误提示
        if (_aiError != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red[400]?.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: Colors.red[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _aiError!,
                    style: TextStyle(fontSize: 12, color: Colors.red[400]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() => _aiError = null),
                )
              ],
            ),
          ),

        // 底部输入栏（全面屏安全避让 + 极简胶囊）
        SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onFocusChange: (hasFocus) {
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _chatInputFocusNode.hasFocus
                              ? context.primaryColor
                              : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04)),
                          width: _chatInputFocusNode.hasFocus ? 1.2 : 0.6,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        focusNode: _chatInputFocusNode,
                        controller: _chatInputController,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: '向 AI 助教提问关于该词的疑问...',
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          isDense: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _aiLoading
                      ? null
                      : () {
                          if (_chatInputController.text.trim().isNotEmpty) {
                            _sendChatMessage(_chatInputController.text.trim());
                          }
                        },
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(bottom: 1),
                    decoration: BoxDecoration(
                      color: _aiLoading
                          ? (isDarkMode ? Colors.white10 : const Color(0xFFE2E8F0))
                          : context.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: _aiLoading
                        ? Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(context.primaryColor),
                              ),
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPromptChip(String label, bool isDarkMode) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _sendChatMessage(label.replaceAll(RegExp(r'^[^\w\s\u4e00-\u9fa5]+'), '').trim());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
              width: 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessageWidget(ChatMessage msg, bool isDarkMode) {
    final isAssistant = msg.role == MessageRole.assistant;

    // 解析建议追问链接 [xxx](suggest:xxx)
    final suggestRegex = RegExp(r'\[(.*?)\]\(suggest:.*?\)', dotAll: true);
    String mainContent = msg.content;
    final List<String> suggestions = [];
    if (isAssistant && suggestRegex.hasMatch(msg.content)) {
      for (final match in suggestRegex.allMatches(msg.content)) {
        final text = match.group(1)?.trim();
        if (text != null && text.isNotEmpty) {
          suggestions.add(text);
        }
      }
      mainContent = msg.content.replaceAll(suggestRegex, '').trim();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // 思考过程 (仅助教且有内容时显示)
          if (isAssistant && msg.thought != null && msg.thought!.isNotEmpty)
            _buildThoughtWidget(msg, isDarkMode),

          // 消息正文
          Container(
            width: isAssistant ? double.infinity : null,
            constraints: isAssistant
                ? null
                : BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isAssistant
                  ? (isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC))
                  : context.primaryColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isAssistant ? 4 : 16),
                bottomRight: Radius.circular(isAssistant ? 16 : 4),
              ),
              border: isAssistant
                  ? Border.all(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                      width: 0.6,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 助教轻量标识微标
                if (isAssistant)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 13,
                          color: context.primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'AI 助教解析',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.primaryColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (msg.content.isEmpty && isAssistant && _aiLoading && _chatMessages.lastIndexOf(msg) == _chatMessages.length - 1)
                  const Text('正在思考与生成...', style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: Colors.grey))
                else if (isAssistant) ...[
                  MarkdownBody(
                    data: mainContent,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null && href.startsWith('suggest:')) {
                        _sendChatMessage(text);
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        height: 1.6,
                      ),
                      h1: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                      h2: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                      h3: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                      strong: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.primaryColor,
                      ),
                      a: TextStyle(
                        color: context.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                      listBullet: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      tableBody: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                      tableHead: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                      ),
                      tableBorder: TableBorder.all(
                        color: isDarkMode ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                      tableCellsPadding: const EdgeInsets.all(6),
                      code: TextStyle(
                        fontSize: 12.5,
                        backgroundColor: isDarkMode ? Colors.black26 : const Color(0xFFF1F5F9),
                        color: isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                    ),
                  ),

                  // 交互式建议追问药丸
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions.map((suggest) {
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _sendChatMessage(suggest),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.primaryColor.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: context.primaryColor.withValues(alpha: isDarkMode ? 0.3 : 0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 13,
                                    color: context.primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      suggest,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: context.primaryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_outward_rounded,
                                    size: 13,
                                    color: context.primaryColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ] else
                  SelectableText(
                    msg.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
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
        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
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
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (isThinking)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(context.primaryColor),
                      ),
                    )
                  else
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 13,
                      color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isThinking ? 'AI 正在深度思考...' : 'AI 的思考过程',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!isThinking)
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SelectableText(
                thought,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _normalizeEnglishSpacing(String text) {
    if (text.isEmpty) return text;
    // 修复西文标点后紧贴英文字母缺失空格的问题（例如 "feelings.People" -> "feelings. People", "eating,sleeping" -> "eating, sleeping"）
    return text.replaceAllMapped(
      RegExp(r'([,;:?!]|(?<!\.)\.(?!\.))([a-zA-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );
  }

  ListView renderDetail() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 单词深度讲解（如有）
            if (args.word.shortDesc != null && args.word.shortDesc!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 16, color: context.primaryColor),
                        const SizedBox(width: 6),
                        const Text(
                          '深度讲解',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Util.makeEnglishSpanText(
                      _normalizeEnglishSpacing(args.word.shortDesc!),
                      args.word.spell,
                      true,
                      context,
                      false,
                      null,
                      false,
                      FontWeight.w400,
                      fontSize: 14.5,
                      color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      height: 1.55,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 28,
                thickness: 0.5,
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ],

            // 例句标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.format_quote_rounded, size: 17, color: context.primaryColor),
                    const SizedBox(width: 6),
                    const Text(
                      '短语 & 例句',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      isEditMode = !isEditMode;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isEditMode ? Icons.check_circle_outline_rounded : Icons.edit_note_rounded,
                          size: 16,
                          color: isEditMode ? context.primaryColor : subtitleColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isEditMode ? '完成' : '编辑',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isEditMode ? FontWeight.w600 : FontWeight.w500,
                            color: isEditMode ? context.primaryColor : subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 例句内容或空状态
            FutureBuilder<List<SentenceVo>>(
              future: _sentencesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final sentences = snapshot.data ?? [];
                if (sentences.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < sentences.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 20,
                            thickness: 0.5,
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        _buildSentenceItem(sentences[i], isDarkMode, subtitleColor),
                      ],
                    ],
                  );
                } else {
                  // 没有例句时显示空状态提示
                  return _buildTabEmptyState(
                    isDarkMode: isDarkMode,
                    icon: Icons.library_books_rounded,
                    title: '暂无例句',
                    subtitle: '该单词目前没有收录例句内容',
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSentenceItem(SentenceVo sent, bool isDarkMode, Color subtitleColor) {
    return InkWell(
      onTap: () {
        if (!(_playingStates[sent.id]?.value ?? false)) {
          _playWithAnimation(
            () => sessionController.playWordAndSentence(
              args.word,
              sentenceDigest: sent.englishDigest,
              playWord: false,
              playSentence: true,
              isSpeakMode: false,
            ),
            sent.id,
          );
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Util.makeEnglishSpanText(
                    _normalizeEnglishSpacing(sent.english!),
                    args.word.spell,
                    true,
                    context,
                    false,
                    null,
                    false,
                    FontWeight.w400,
                    fontSize: 14.5,
                  ),
                  const SizedBox(height: 5),
                  Util.makeChineseSpanText(
                    sent.chinese!,
                    context,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 13.5,
                      height: 1.45,
                      color: subtitleColor,
                    ),
                  ),
                  if (isEditMode) ...[
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(children: [
                      for (var span in renderSentenceEditSpans(sent)) span,
                    ])),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkResponse(
              radius: 20,
              onTap: () {
                if (!(_playingStates[sent.id]?.value ?? false)) {
                  _playWithAnimation(
                    () => sessionController.playWordAndSentence(
                      args.word,
                      sentenceDigest: sent.englishDigest,
                      playWord: false,
                      playSentence: true,
                      isSpeakMode: false,
                    ),
                    sent.id,
                  );
                }
              },
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: AnimatedBuilder(
                  animation: _getSentenceController(sent.id),
                  builder: (context, child) {
                    return ModernSoundWaveIcon(
                      isPlaying: _playingStates[sent.id]?.value ?? false,
                      animationController: _getSentenceController(sent.id),
                      size: 15,
                      color: subtitleColor,
                      activeColor: context.primaryColor,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget renderSimilarWords() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final similarWords = args.word.similarWords;
    if (similarWords != null && similarWords.isNotEmpty) {
      final showTip = _showSimilarTip;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: showTip ? similarWords.length + 1 : similarWords.length,
        separatorBuilder: (context, index) {
          if (showTip && index == 0) return const SizedBox(height: 6);
          return Divider(
            height: 1,
            thickness: 0.5,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          );
        },
        itemBuilder: (context, index) {
          if (showTip && index == 0) {
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: isDarkMode ? 0.09 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: context.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '注：推荐了拼写相近的单词。浅灰色单词不在当前词书内。',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                    onPressed: () async {
                      setState(() {
                        _showSimilarTip = false;
                      });
                      await Prefs.write('show_similar_tip', false);
                    },
                  ),
                ],
              ),
            );
          }

          final word = showTip ? similarWords[index - 1] : similarWords[index];
          final inDict = _wordInDictStatus[word.id!] ?? true;

          final Color spellColor = inDict
              ? (isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A))
              : (isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B));
          final Color descColor = inDict
              ? (isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155))
              : (isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8));

          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              context.push(
                '/word_detail',
                extra: WordDetailPageArgs(word, true, null, false, priorityDictIds: args.priorityDictIds),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                word.spell,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5,
                                  color: spellColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (Util.getWordDefaultPronounce(word).isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '[${Util.getWordDefaultPronounce(word)}]',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontFamily: 'Roboto',
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (!inDict) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '未选',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          word.getMeaningStr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: descColor,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: isDarkMode ? Colors.white24 : Colors.black26,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      return _buildTabEmptyState(
        isDarkMode: isDarkMode,
        icon: Icons.text_fields_rounded,
        title: '暂无形近词',
        subtitle: '该单词目前没有收录形近词内容',
      );
    }
  }

  Widget renderSemanticSimilarWords() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    if (_isLoadingSemanticSimilar && _semanticSimilarWords.isEmpty) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(context.primaryColor),
          ),
        ),
      );
    }
    if (_semanticSimilarWords.isNotEmpty) {
      final showTip = _showSemanticTip;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: showTip ? _semanticSimilarWords.length + 1 : _semanticSimilarWords.length,
        separatorBuilder: (context, index) {
          if (showTip && index == 0) return const SizedBox(height: 6);
          return Divider(
            height: 1,
            thickness: 0.5,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          );
        },
        itemBuilder: (context, index) {
          if (showTip && index == 0) {
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: isDarkMode ? 0.09 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 14,
                    color: context.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '注：系统推荐了在相似语境中常出现的单词。浅灰色单词不在当前词书内。',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                    onPressed: () async {
                      setState(() {
                        _showSemanticTip = false;
                      });
                      await Prefs.write('show_semantic_tip', false);
                    },
                  ),
                ],
              ),
            );
          }

          final word = showTip ? _semanticSimilarWords[index - 1] : _semanticSimilarWords[index];
          final inDict = _wordInDictStatus[word.id!] ?? true;

          final Color spellColor = inDict
              ? (isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A))
              : (isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B));
          final Color descColor = inDict
              ? (isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155))
              : (isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8));

          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              context.push(
                '/word_detail',
                extra: WordDetailPageArgs(word, true, null, false, priorityDictIds: args.priorityDictIds),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                word.spell,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5,
                                  color: spellColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (Util.getWordDefaultPronounce(word).isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '[${Util.getWordDefaultPronounce(word)}]',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontFamily: 'Roboto',
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (!inDict) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '未选',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          word.getMeaningStr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: descColor,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: isDarkMode ? Colors.white24 : Colors.black26,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      return _buildTabEmptyState(
        isDarkMode: isDarkMode,
        icon: Icons.explore_off_rounded,
        title: '暂无语境拓展词',
        subtitle: '未找到与该单词语义相关的拓展词',
      );
    }
  }

  Widget renderSynonyms() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    // 仅显示有同义词的释义项
    final itemsWithSynonyms = [
      for (var mi in args.word.meaningItems ?? [])
        if (mi.synonyms != null && mi.synonyms!.isNotEmpty) mi
    ];

    if (itemsWithSynonyms.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: itemsWithSynonyms.length,
        separatorBuilder: (context, index) => Divider(
          height: 24,
          thickness: 0.5,
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        itemBuilder: (context, index) {
          final meaningItem = itemsWithSynonyms[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((meaningItem.meaning ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 3.5,
                        height: 13,
                        decoration: BoxDecoration(
                          color: context.primaryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          meaningItem.meaning!,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var synonym in meaningItem.synonyms!)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        StudyAudioSessionController().playWordSoundBySpell(synonym.spell);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              synonym.spell,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 5),
                            ModernSoundWaveIcon(
                              size: 13,
                              color: context.primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      );
    } else {
      return _buildTabEmptyState(
        isDarkMode: isDarkMode,
        icon: Icons.group_work_outlined,
        title: '暂无同义词',
        subtitle: '该单词目前没有收录同义词内容',
      );
    }
  }

  Widget _buildTabEmptyState({
    required bool isDarkMode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: context.subtleBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.cardBorder,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 48,
                color: context.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
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

    return AppScaffold(
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
