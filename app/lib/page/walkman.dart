import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:provider/provider.dart';

import '../db/db.dart';
import '../global.dart';
import '../state.dart';
import '../util/sound.dart';
import '../util/tts.dart';
import 'index.dart';

class WalkmanParams {
  WordsProvider wordsProvider;

  WalkmanParams(this.wordsProvider);

  @override
  String toString() {
    return 'WalkmanParams{wordsProvider: $wordsProvider}';
  }
}

class WalkmanPage extends StatefulWidget {
  const WalkmanPage({super.key});

  @override
  WalkmanPageState createState() {
    return WalkmanPageState();
  }
}

class WalkmanPageState extends State<WalkmanPage> {
  static const double leftPadding = 0;
  static const double rightPadding = 0;
  Color selectedTextColor = Colors.white;
  Color normalTextColor = const Color(0xffaaaaaa);
  AudioPlayer audioPlayer = AudioPlayer();
  bool _audioPlayerDisposed = false;
  Timer? loadWordTimer; // 改为可空类型，避免late风险
  Timer? playWordTimer;
  bool dataLoaded = false;
  WalkmanParams? params; // 改为可空类型，在checkArgs中验证
  List<WordWrapper> allWords = [];
  int totalWordCount = -1;
  bool shouldStop = false;
  int currWordIndex = 0;
  int nextWordIndex = 0;
  bool isShowingSettingPanel = false;
  Tts? tts; // 改为可空类型，在init中初始化
  var showSpell = true;
  var showPronounce = false;
  var showMeaning = false;
  var showSentence = false;
  var showChinese = false;
  var playPronounce = true;
  var playMeaning = false;
  var playSentence = false;
  var playChinese = false;
  var repeatCount = 1;
  var playInterval = 0; // 每个单词之间的播放时间间隔（毫秒）
  var currentPlayStep = ''; // 当前单词正在的播放的步骤（英文、音标、释义...）
  var currentWordPlayShouldStop = false;
  var currentWordPlayingStopped = true;
  var playEvenIfSettingPanelIsShowing = false;
  static const maxIntValue = 0x7fffffff;
  int waitedTime = maxIntValue;
  bool inited = false;
  bool isLandscape = false;

  Future<bool> checkArgs() async {
    if (Get.arguments == null) {
      Future.delayed(Duration.zero, () {
        // 延迟到下一个tick执行，避免导航冲突
        Get.toNamed('/index', arguments: IndexPageArgs(4));
      });
      return false;
    }
    params = Get.arguments;
    return true;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    tts = Tts();
    tts?.init();

    loadData();

    // 周期性加载单词
    loadWordTimer = Timer.periodic(const Duration(milliseconds: 1000), (Timer timer) {
      if (currWordIndex > allWords.length - 10 && !isAllWordsLoaded()) {
        // 缓冲区中剩下待浏览的词不多了，从服务端加载一批
        try {
          loadAPageOfRawWords();
        } catch (e) {
          timer.cancel(); // 直接使用参数timer而不是loadWordTimer
          ErrorHandler.handleError(e, null, userMessage: '加载单词失败，请稍后重试', logPrefix: 'Walkman加载单词');
        }
      }
    });

    // 开始播放单词
    playWordTick();
  }

  Future<void> loadData() async {
    if (!await checkArgs()) {
      return;
    }
    // 确保params已初始化
    if (params == null) {
      Global.logger.e('Walkman: params为空，无法加载数据');
      return;
    }
    setState(() {
      inited = true;
    });
  }

  @override
  void dispose() {
    // 设置停止标志
    currentWordPlayShouldStop = true;
    _audioPlayerDisposed = true; // 立即标记为已释放，防止后续使用

    // 取消所有计时器
    loadWordTimer?.cancel();
    playWordTimer?.cancel();

    // 延迟释放 AudioPlayer，确保所有操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        audioPlayer.dispose();
      } catch (e) {
        // 忽略释放时的错误
        Global.logger.d("释放 AudioPlayer 时出错: $e");
      }
    });

    // 退出全屏并恢复默认方向设置
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([]);

    super.dispose();
  }

  Future<void> forceFinishCurrentWord() async {
    // 如果 AudioPlayer 已经被释放，直接返回
    if (_audioPlayerDisposed) {
      currentWordPlayShouldStop = true;
      currentWordPlayingStopped = true;
      return;
    }

    currentWordPlayShouldStop = true;

    // 强制停止所有可能的播放
    try {
      if (currentPlayStep == 'meaning') {
        await tts?.stop();
      } else if (currentPlayStep == 'chinese') {
        await tts?.stop();
      }
      // 移除 AudioPlayer 的 stop 调用，因为可能导致 disposed 错误
    } catch (e) {
      // 忽略停止播放时的错误
      Global.logger.d("强制停止播放时出错: $e");
    }

    await waitCurrentWordPlayingToStop();
  }

  Future<void> waitCurrentWordPlayingToStop() async {
    // 最多等待2秒，防止无限等待
    int attempts = 0;
    final maxAttempts = 100; // 100 × 20ms = 2s

    while (!currentWordPlayingStopped && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 20), () {});
      attempts++;
    }

    // 如果等待超时，强制设置状态为已停止
    if (!currentWordPlayingStopped) {
      currentWordPlayingStopped = true;
    }
  }

  playWordTick() async {
    if (isShowingSettingPanel && !playEvenIfSettingPanelIsShowing) {
      // 设置面板显示且不播放时，只更新计时器
      playWordTimer = Timer(const Duration(milliseconds: 100), () {
        playWordTick();
      });
    } else if (waitedTime >= playInterval && currentWordPlayingStopped) {
      // 重置等待时间
      waitedTime = 0;

      // 开始播放
      await doPlayWord();

      // 设置下一个计时器
      playWordTimer = Timer(const Duration(milliseconds: 100), () {
        if (waitedTime <= maxIntValue - 100) {
          waitedTime += 100;
        }
        playWordTick();
      });
    } else {
      // 更新等待时间并继续计时
      playWordTimer = Timer(const Duration(milliseconds: 100), () {
        if (waitedTime <= maxIntValue - 100) {
          waitedTime += 100;
        }
        playWordTick();
      });
    }
  }

  Future<void> doPlayWord() async {
    try {
      currentWordPlayShouldStop = false;
      currentWordPlayingStopped = false;

      // 播放当前单词
      if (allWords.isNotEmpty && mounted) {
        setState(() {
          currWordIndex = nextWordIndex;
        });
        final word = allWords[currWordIndex];

        // 提前获取例句，确保例句与当前单词匹配
        List<SentenceVo> sentences = [];
        try {
          sentences = await word.word.getSentences();
        } catch (e) {
          Global.logger.d("获取例句失败: $e");
          sentences = [];
        }

        // 检查是否被停止，避免获取例句期间状态变化
        if (currentWordPlayShouldStop) {
          currentWordPlayingStopped = true;
          return;
        }

        for (var i = 0; i < repeatCount && !currentWordPlayShouldStop; i++) {
          // 检查停止信号
          if (currentWordPlayShouldStop) break;

          if (playPronounce && !_audioPlayerDisposed) {
            currentPlayStep = 'pronounce';
            try {
              await SoundUtil.playPronounceSoundBySpell2(word.word.spell, audioPlayer);
            } catch (e) {
              // 忽略 AudioPlayer 错误
              Global.logger.d("播放发音失败: $e");
            }
            currentPlayStep = '';
          }

          // 检查停止信号
          if (currentWordPlayShouldStop) break;

          if (playMeaning && PlatformUtils.isTtsSupported()) {
            // 播放释义前，休眠一会儿，以便用户可以回想一下
            var sleepTime = 0;
            while (!currentWordPlayShouldStop && sleepTime < playInterval * 0.5) {
              await Future.delayed(const Duration(milliseconds: 10), () {}); // 减少检查间隔
              sleepTime += 10;
            }

            if (!currentWordPlayShouldStop) {
              currentPlayStep = 'meaning';
              if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
                await tts?.speak(Util.pureMeaningStr(word.word));
              }
              currentPlayStep = '';
            }
          }

          // 检查停止信号
          if (currentWordPlayShouldStop) break;

          // 播放已预先获取的例句
          if (sentences.isNotEmpty) {
            if (playSentence && !currentWordPlayShouldStop && !_audioPlayerDisposed) {
              currentPlayStep = 'sentence';
              try {
                await SoundUtil.playSentenceSound2(sentences[0].englishDigest!, audioPlayer);
              } catch (e) {
                // 忽略 AudioPlayer 错误
                Global.logger.d("播放例句失败: $e");
              }
              currentPlayStep = '';
            }

            // 检查停止信号
            if (currentWordPlayShouldStop) break;

            if (playChinese && !currentWordPlayShouldStop) {
              currentPlayStep = 'chinese';
              await tts?.speak(Util.pureSentenceChinese(sentences[0].chinese!));
              currentPlayStep = '';
            }
          }

          // 重复播放下一个单词前，等待一段时间
          if (i < repeatCount - 1) {
            var sleepTime = 0;
            while (!currentWordPlayShouldStop && sleepTime < playInterval) {
              await Future.delayed(const Duration(milliseconds: 10), () {}); // 减少检查间隔
              sleepTime += 10;
            }
          }
        }

        nextWordIndex = currWordIndex + 1 < allWords.length ? currWordIndex + 1 : 0;
      }
      currentWordPlayingStopped = true;
    } catch (e) {
      // 即使出错也要更新nextWordIndex和播放状态，确保播放能继续到下一个单词
      if (mounted && allWords.isNotEmpty) {
        nextWordIndex = currWordIndex + 1 < allWords.length ? currWordIndex + 1 : 0;
      }
      currentWordPlayingStopped = true;
      ToastUtil.error("播放异常");
    }
  }

  loadAPageOfRawWords() async {
    if (!inited) {
      return;
    }
    var result = await params?.wordsProvider.getAPageOfWords(allWords.length, 10);
    totalWordCount = result?.total ?? -1;
    allWords.addAll(result?.rows ?? []);
    dataLoaded = true;
    Global.logger.d('加载了${result?.rows.length ?? 0}个单词，缓冲区中共${allWords.length}个单词');
  }

  bool isAllWordsLoaded() {
    return totalWordCount != -1 && totalWordCount <= allWords.length;
  }

  Widget renderWord(WordWrapper word) {
    // 横屏模式下文字大小调整
    final spellFontSize = isLandscape ? 32.0 : 24.0;
    final meaningFontSize = isLandscape ? 16.0 : 14.0;

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      // 单词英文
      showSpell
          ? Text(
              word.word.spell,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: spellFontSize),
            )
          : Container(),

      // 音标
      showPronounce
          ? Text(
              word.word.mergedPronounce.isNotEmpty ? '[${word.word.mergedPronounce}]' : '',
              style: const TextStyle(fontFamily: 'NotoSans'),
            )
          : Container(),

      // 释义
      showMeaning ? renderWordMeaning(word, meaningFontSize) : Container(),

      // 播放/暂停按钮
      isShowingSettingPanel
          ? InkWell(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Icon(
                  playEvenIfSettingPanelIsShowing ? Icons.pause_circle_outline_outlined : Icons.play_circle_outline_outlined,
                  // 横屏模式下图标增大
                  size: isLandscape ? 36.0 : 24.0,
                ),
              ),
              onTap: () {
                setState(() {
                  playEvenIfSettingPanelIsShowing = !playEvenIfSettingPanelIsShowing;

                  if (playEvenIfSettingPanelIsShowing) {
                    // 开始播放：立即设置停止标志，然后重置播放状态
                    currentWordPlayShouldStop = true;
                    // 延迟重置播放状态，确保当前播放停止
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) {
                        resetPlayState();
                      }
                    });
                  } else {
                    // 暂停播放：只设置停止标志
                    currentWordPlayShouldStop = true;
                  }
                });
              },
            )
          : Container(),
    ]);
  }

  Widget renderWordMeaning(WordWrapper word, [double fontSize = 14.0]) {
    return Column(
      children: [
        for (var meaningItem in word.word.getMergedMeaningItems())
          Text(
            '${meaningItem.ciXing} ${meaningItem.meaning!}',
            style: TextStyle(fontSize: fontSize),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget renderPage() {
    final word = allWords[currWordIndex];
    // 横屏模式下调整外边距
    final horizontalPadding = isLandscape ? 40.0 : 0.0;

    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              // 切换设置面板显示状态
              isShowingSettingPanel = !isShowingSettingPanel;

              if (isShowingSettingPanel) {
                // 显示设置面板时，停止当前单词播放
                forceFinishCurrentWord();
                // 默认不在设置面板显示时播放
                playEvenIfSettingPanelIsShowing = false;
              } else {
                // 关闭设置面板时，确保立即开始播放当前单词
                nextWordIndex = currWordIndex; // 重播当前单词

                // 使用新方法完全重置播放状态
                resetPlayState();
              }
            });
          },
          onHorizontalDragEnd: (DragEndDetails details) async {
            // 向左滑动, 播放下一个单词
            if (details.velocity.pixelsPerSecond.dx <= -500) {
              await forceFinishCurrentWord();
              setState(() {
                if (currWordIndex + 1 < allWords.length) {
                  currWordIndex += 1;
                } else {
                  currWordIndex = 0;
                }
                nextWordIndex = currWordIndex;
              });
              // 使用新方法重置播放状态
              resetPlayState();
            }

            // 向右滑动, 播放上一个单词
            else if (details.velocity.pixelsPerSecond.dx >= 500) {
              await forceFinishCurrentWord();
              setState(() {
                if (currWordIndex >= 1) {
                  currWordIndex -= 1;
                } else {
                  currWordIndex = allWords.length - 1;
                }
                nextWordIndex = currWordIndex;
              });
              // 使用新方法重置播放状态
              resetPlayState();
            }
          },
          child: Container(
            decoration: const BoxDecoration(color: Colors.transparent),
            // 横屏模式下调整内边距
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${currWordIndex + 1} / $totalWordCount',
                      style: TextStyle(fontSize: isLandscape ? 12.0 : 9.0),
                    ),
                  ],
                ),
                Center(child: renderWord(word)),
              ],
            ),
          ),
        ),
        isShowingSettingPanel
            ? Positioned(
                bottom: 0,
                left: 0,
                width: MediaQuery.of(context).size.width,
                child: renderSettingPanel(),
              )
            : Container(),
      ],
    );
  }

  Widget renderSettingPanel() {
    return Container(
      color: Global.highlight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: DefaultTextStyle.merge(
          // 统一缩小设置面板文字尺寸
          style: const TextStyle(fontSize: 12.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '显示',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.0),
                    ),
                    InkWell(
                      child: Text(
                        '英文',
                        style: TextStyle(color: showSpell ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          showSpell = !showSpell;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '音标',
                        style: TextStyle(color: showPronounce ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          showPronounce = !showPronounce;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '释义',
                        style: TextStyle(color: showMeaning ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          showMeaning = !showMeaning;
                        });
                      },
                    ),
                    const Text('　　'),
                    const Text('　　'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '发音',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.0),
                    ),
                    InkWell(
                      child: Text(
                        '英文',
                        style: TextStyle(color: playPronounce ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playPronounce = !playPronounce;
                        });
                      },
                    ),
                    if (PlatformUtils.isTtsSupported())
                      InkWell(
                        child: Text(
                          '释义',
                          style: TextStyle(color: playMeaning ? selectedTextColor : normalTextColor),
                        ),
                        onTap: () {
                          setState(() {
                            playMeaning = !playMeaning;
                          });
                        },
                      ),
                    InkWell(
                      child: Text(
                        '例句',
                        style: TextStyle(color: playSentence ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playSentence = !playSentence;
                        });
                      },
                    ),
                    if (PlatformUtils.isTtsSupported())
                      InkWell(
                        child: Text(
                          '翻译',
                          style: TextStyle(color: playChinese ? selectedTextColor : normalTextColor),
                        ),
                        onTap: () {
                          setState(() {
                            playChinese = !playChinese;
                          });
                        },
                      ),
                    const Text('　　'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '重复',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.0),
                    ),
                    InkWell(
                      child: Text(
                        '1次',
                        style: TextStyle(color: repeatCount == 1 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          repeatCount = 1;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '2次',
                        style: TextStyle(color: repeatCount == 2 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          repeatCount = 2;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '3次',
                        style: TextStyle(color: repeatCount == 3 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          repeatCount = 3;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '4次',
                        style: TextStyle(color: repeatCount == 4 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          repeatCount = 4;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '5次',
                        style: TextStyle(color: repeatCount == 5 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          repeatCount = 5;
                        });
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '间隔',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.0),
                    ),
                    InkWell(
                      child: Text(
                        '0秒',
                        style: TextStyle(color: playInterval == 0 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playInterval = 0;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '1秒',
                        style: TextStyle(color: playInterval == 1000 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playInterval = 1000;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '2秒',
                        style: TextStyle(color: playInterval == 2000 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playInterval = 2000;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '3秒',
                        style: TextStyle(color: playInterval == 3000 ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playInterval = 3000;
                        });
                      },
                    ),
                    InkWell(
                      child: Text(
                        '手动',
                        style: TextStyle(color: playInterval == maxIntValue ? selectedTextColor : normalTextColor),
                      ),
                      onTap: () {
                        setState(() {
                          playInterval = maxIntValue;
                        });
                        ToastUtil.info('手指向左滑动，播放下一单词');
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '其他',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.0),
                    ),
                    InkWell(
                        onTap: () {
                          setState(() {
                            var isDarkMode = !context.read<DarkMode>().isDarkMode;
                            MyDatabase.instance.localParamsDao.saveIsDarkMode(isDarkMode);
                            context.read<DarkMode>().setIsDarkMode(isDarkMode);
                          });
                        },
                        child: Text(context.read<DarkMode>().isDarkMode ? '白天' : '夜间', style: TextStyle(color: selectedTextColor))),
                    InkWell(
                      child: Text(
                        isLandscape ? '竖屏' : '横屏',
                        style: TextStyle(color: selectedTextColor),
                      ),
                      onTap: () {
                        toggleOrientation();
                      },
                    ),
                    InkWell(
                      child: Text('离开', style: TextStyle(color: selectedTextColor)),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                    const Text('　　'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    // 根据主题模式设置背景色
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor, // 根据主题模式设置背景色
      body: Container(
        // 横屏模式下调整内边距
        padding: EdgeInsets.fromLTRB(leftPadding, isLandscape ? 8.0 : 16.0, rightPadding, 0),
        child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
      ),
    );
  }

  // 完全重置播放状态，确保可以重新开始播放
  void resetPlayState() {
    // 重置状态标志
    currentWordPlayingStopped = true;
    currentWordPlayShouldStop = false;
    currentPlayStep = '';

    // 重置等待时间为0，确保能立即开始新的播放
    waitedTime = 0;

    // 取消并重建计时器
    if (playWordTimer != null) {
      playWordTimer!.cancel();
    }

    // 重新启动播放循环
    playWordTimer = Timer(const Duration(milliseconds: 100), () {
      playWordTick();
    });
  }

  // 切换屏幕方向
  void toggleOrientation() {
    setState(() {
      isLandscape = !isLandscape;
      if (isLandscape) {
        // 切换到横屏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        ToastUtil.info('已切换到横屏模式');
      } else {
        // 切换到竖屏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        ToastUtil.info('已切换到竖屏模式');
      }
    });
  }
}
