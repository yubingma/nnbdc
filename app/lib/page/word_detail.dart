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
        var result = await Api.client.searchWord(args.word.spell, Global.getLoggedInUser()?.id ?? '');
        if (result.word == null) {
          ToastUtil.error("单词 ${args.word.spell} 不存在");
        } else {
          args.word = result.word!;
        }
      } catch (e, st) {
        ErrorHandler.handleNetworkError(e, st, api: '/searchWord.do');
        if (mounted) {
          setState(() {
            hasError = true;
            errorMessage = '加载单词详情失败';
          });
        }
        return;
      }
    }

    // 使用传入的参数判断本次是否回答错误
    isWrongWord = args.isThisAnswerWrong;

    setState(() {
      dataLoaded = true;
    });
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
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: const BouncingScrollPhysics(),
                        dragStartBehavior: DragStartBehavior.down,
                        children: [renderDetail(), if (hasSimilarWords()) renderSimilarWords(), if (hasSynonyms()) renderSynonyms()],
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
                                  activeColor: const Color(0xFF4A90E2),
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

  Future<bool> sentenceChineseHasBeenVoted(var sentenceChinese) async {
    return (await MyDatabase.instance.votedChinesesDao.getVotedChineseById(Global.getLoggedInUser()!.id, sentenceChinese.id)) != null;
  }

  Future<bool> sentenceHasBeenVoted(var sentence) async {
    return (await MyDatabase.instance.votedSentencesDao.getVotedSentenceById(Global.getLoggedInUser()!.id, sentence.id)) != null;
  }

  Widget renderSentenceChinese(String sentenceChinese, String sentenceId) {
    return FutureBuilder<bool>(
        future: sentenceChineseHasBeenVoted(sentenceChinese),
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
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
          } else {
            return Container();
          }
        });
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
