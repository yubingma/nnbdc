import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' as drift;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../db/db.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';
import '../util/study_audio_session_controller.dart';
import '../util/tts.dart';
import '../util/prefs.dart';
import '../widget/app_scaffold.dart';
import '../widget/theme_select_dialog.dart';
import 'index.dart';

/// 随身听自然沉浸场景（动态微动态背景 + 原版高保真环境白噪音）
enum WalkmanScene {
  none('极简', null, null),
  rain('闲时听雨', 'assets/video/scenes/rain.mp4', 'assets/audio/scenes/rain.mp3'),
  night('夏夜虫鸣', 'assets/video/scenes/night.mp4', 'assets/audio/scenes/night.mp3');

  final String title;
  final String? videoAsset;
  final String? audioAsset;
  const WalkmanScene(this.title, this.videoAsset, this.audioAsset);

  bool get hasVideo => videoAsset != null;
  bool get hasAudio => audioAsset != null;
}

class WalkmanConfig {
  bool showSpell = true;
  bool showPronounce = false;
  bool showMeaning = false;
  bool showSentence = false;
  bool showChinese = false;
  bool playPronounce = true;
  bool playMeaning = false;
  bool playSentence = false;
  bool playChinese = false;
  int repeatCount = 1;
  int playInterval = 0;
  double sentencePlaySpeed = 1.0;
  int playSentenceCount = 1; // 1, 2, 3, 4, -1 (全部)
  String scene = 'none';
  double ambientVolume = 0.35;
  bool ambientMuted = false;

  WalkmanConfig();

  factory WalkmanConfig.fromJson(Map<String, dynamic> json) {
    var config = WalkmanConfig();
    config.showSpell = json['showSpell'] ?? true;
    config.showPronounce = json['showPronounce'] ?? false;
    config.showMeaning = json['showMeaning'] ?? false;
    config.showSentence = json['showSentence'] ?? false;
    config.showChinese = json['showChinese'] ?? false;
    config.playPronounce = json['playPronounce'] ?? true;
    config.playMeaning = json['playMeaning'] ?? false;
    config.playSentence = json['playSentence'] ?? false;
    config.playChinese = json['playChinese'] ?? false;
    config.repeatCount = json['repeatCount'] ?? 1;
    config.playInterval = json['playInterval'] ?? 0;
    config.sentencePlaySpeed = (json['sentencePlaySpeed'] ?? 1.0).toDouble();
    config.playSentenceCount = json['playSentenceCount'] ?? 1;
    config.scene = json['scene'] ?? 'none';
    config.ambientVolume = (json['ambientVolume'] ?? 0.35).toDouble();
    config.ambientMuted = json['ambientMuted'] ?? false;
    return config;
  }

  Map<String, dynamic> toJson() => {
        'showSpell': showSpell,
        'showPronounce': showPronounce,
        'showMeaning': showMeaning,
        'showSentence': showSentence,
        'showChinese': showChinese,
        'playPronounce': playPronounce,
        'playMeaning': playMeaning,
        'playSentence': playSentence,
        'playChinese': playChinese,
        'repeatCount': repeatCount,
        'playInterval': playInterval,
        'sentencePlaySpeed': sentencePlaySpeed,
        'playSentenceCount': playSentenceCount,
        'scene': scene,
        'ambientVolume': ambientVolume,
        'ambientMuted': ambientMuted,
      };
}

class WalkmanParams {
  WordsProvider wordsProvider;
  BookMarkProvider? bookMarkProvider;
  int? initialWordIndex;

  WalkmanParams(this.wordsProvider, {this.bookMarkProvider, this.initialWordIndex});

  @override
  String toString() {
    return 'WalkmanParams{wordsProvider: $wordsProvider, bookMarkProvider: $bookMarkProvider, initialWordIndex: $initialWordIndex}';
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

  Timer? playWordTimer;
  bool dataLoaded = false;
  WalkmanParams? params; // 改为可空类型，在checkArgs中验证
  final Map<int, WordWrapper> _wordCache = {};
  final Set<int> _loadingPages = {};
  static const int _pageSize = 20;
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
  var sentencePlaySpeed = 1.0;
  var playSentenceCount = 1;
  var currentPlayStep = ''; // 当前单词正在的播放的步骤（英文、音标、释义...）
  var currentWordPlayShouldStop = false;
  var currentWordPlayingStopped = true;
  var playEvenIfSettingPanelIsShowing = false;
  List<SentenceVo> currSentences = [];
  int currSentenceIndex = 0;
  static const maxIntValue = 0x7fffffff;
  int waitedTime = 0; // 修改初始值为0，但在进入时标记为“已等待足够久”
  bool _isFirstWord = true; // 增加标记位，识别是否为第一个单词
  bool _forceNoWaitOnce = false; // 强制跳过单词内部的所有等待时间 (用于手动切换后的第一个词)
  bool inited = false;
  bool isLandscape = false;
  int _playSessionId = 0;

  // 自然沉浸场景与环境音效状态
  WalkmanScene currentScene = WalkmanScene.none;
  VideoPlayerController? _videoController;
  AudioPlayer? _ambientPlayer;
  double ambientVolume = 0.35;
  bool ambientMuted = false;

  Future<bool> checkArgs() async {
    final extra = GoRouterState.of(context).extra;
    if (extra == null) {
      Future.delayed(Duration.zero, () {
        // 延迟到下一个tick执行，避免导航冲突
        if (!mounted) return;
        context.push('/index', extra: IndexPageArgs(4));
      });
      return false;
    }
    params = extra as WalkmanParams?;
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

    // 读取本地保存的场景与白噪音偏好
    final sceneName = Prefs.read<String>('walkman_scene') ?? 'none';
    currentScene = WalkmanScene.values.firstWhere(
      (s) => s.name == sceneName,
      orElse: () => WalkmanScene.none,
    );
    ambientVolume = Prefs.read<double>('walkman_ambient_volume') ?? 0.35;
    ambientMuted = Prefs.read<bool>('walkman_ambient_muted') ?? false;

    if (currentScene != WalkmanScene.none) {
      _applyScene(currentScene, save: false);
    }
  }

  /// 切换沉浸场景（支持动态视频背景 + 高保真环境音效循环）
  Future<void> _applyScene(WalkmanScene scene, {bool save = true}) async {
    if (save) {
      await Prefs.write('walkman_scene', scene.name);
    }
    currentScene = scene;
    if (mounted) setState(() {});

    // 1. 处理微动态视频背景
    final oldVideo = _videoController;
    _videoController = null;
    if (mounted) setState(() {});
    if (oldVideo != null) {
      try {
        await oldVideo.dispose();
      } catch (_) {}
    }

    if (scene.hasVideo) {
      try {
        final vController = VideoPlayerController.asset(scene.videoAsset!);
        await vController.initialize();
        await vController.setLooping(true);
        await vController.setVolume(0.0); // 视频背景本身静音
        await vController.play();
        if (mounted) {
          setState(() {
            _videoController = vController;
          });
        } else {
          await vController.dispose();
        }
      } catch (e) {
        Global.logger.d("初始化随身听场景微动态背景失败: $e");
      }
    }

    // 2. 处理环境白噪音音效
    if (scene.hasAudio) {
      try {
        _ambientPlayer ??= AudioPlayer();
        await _ambientPlayer!.stop();
        await _ambientPlayer!.setAsset(scene.audioAsset!);
        await _ambientPlayer!.setLoopMode(LoopMode.one);
        await _ambientPlayer!.setVolume(ambientMuted ? 0.0 : ambientVolume);
        await _ambientPlayer!.play();
      } catch (e) {
        Global.logger.d("初始化随身听环境音效失败: $e");
      }
    } else {
      try {
        await _ambientPlayer?.stop();
      } catch (_) {}
    }

    if (save) {
      saveConfig();
    }
  }

  /// 切换环境白噪音静音态
  Future<void> _toggleAmbientMute() async {
    setState(() {
      ambientMuted = !ambientMuted;
    });
    await Prefs.write('walkman_ambient_muted', ambientMuted);
    if (_ambientPlayer != null) {
      await _ambientPlayer!.setVolume(ambientMuted ? 0.0 : ambientVolume);
    }
    saveConfig();
  }

  /// 调节环境白噪音音量
  Future<void> _setAmbientVolume(double volume) async {
    setState(() {
      ambientVolume = volume;
      ambientMuted = false;
    });
    await Prefs.write('walkman_ambient_volume', volume);
    await Prefs.write('walkman_ambient_muted', false);
    if (_ambientPlayer != null) {
      await _ambientPlayer!.setVolume(volume);
    }
    saveConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!inited) {
      // 异步加载配置和初始数据，加载成功后立即开始播放循环
      loadData().then((_) {
        if (mounted && totalWordCount > 0) {
          playWordTick();
        }
      });
    }
  }

  Future<void> loadConfig() async {
    User? user = Global.getLoggedInUser();
    if (user != null && user.studyConfig != null) {
      try {
        final studyConfigAll = jsonDecode(user.studyConfig!);
        if (studyConfigAll['walkman'] != null) {
          final config = WalkmanConfig.fromJson(studyConfigAll['walkman']);
          setState(() {
            showSpell = config.showSpell;
            showPronounce = config.showPronounce;
            showMeaning = config.showMeaning;
            showSentence = config.showSentence;
            showChinese = config.showChinese;
            playPronounce = config.playPronounce;
            playMeaning = config.playMeaning;
            playSentence = config.playSentence;
            playChinese = config.playChinese;
            repeatCount = config.repeatCount;
            playInterval = config.playInterval;
            sentencePlaySpeed = config.sentencePlaySpeed;
            playSentenceCount = config.playSentenceCount;
          });
        }
      } catch (e) {
        Global.logger.e('解析随身听配置失败: $e');
      }
    }
  }

  Future<void> saveConfig() async {
    final config = WalkmanConfig()
      ..showSpell = showSpell
      ..showPronounce = showPronounce
      ..showMeaning = showMeaning
      ..showSentence = showSentence
      ..showChinese = showChinese
      ..playPronounce = playPronounce
      ..playMeaning = playMeaning
      ..playSentence = playSentence
      ..playChinese = playChinese
      ..repeatCount = repeatCount
      ..playInterval = playInterval
      ..sentencePlaySpeed = sentencePlaySpeed
      ..playSentenceCount = playSentenceCount
      ..scene = currentScene.name
      ..ambientVolume = ambientVolume
      ..ambientMuted = ambientMuted;

    try {
      User user = Global.getLoggedInUserNotNull();
      // 保留或新建其他 studyConfig 的配置
      Map<String, dynamic> studyConfigAll = {};
      if (user.studyConfig != null) {
        try {
          studyConfigAll = jsonDecode(user.studyConfig!);
        } catch (_) {}
      }
      studyConfigAll['walkman'] = config.toJson();
      
      final updatedUser = user.copyWith(studyConfig: drift.Value<String?>(jsonEncode(studyConfigAll)));
      await MyDatabase.instance.usersDao.saveUser(updatedUser, true);
      Global.updateUserCache(updatedUser);
    } catch (e) {
      Global.logger.e('保存随身听配置失败: $e');
    }
  }

  Future<void> _loadPage(int pageIndex) async {
    if (_loadingPages.contains(pageIndex)) return;
    _loadingPages.add(pageIndex);
    try {
      final fromIndex = pageIndex * _pageSize;
      final result = await params?.wordsProvider.getAPageOfWords(fromIndex, _pageSize);
      if (result != null) {
        if (totalWordCount != result.total) {
          if (mounted) {
            setState(() {
              totalWordCount = result.total;
            });
          } else {
            totalWordCount = result.total;
          }
        }
        for (int i = 0; i < result.rows.length; i++) {
          _wordCache[fromIndex + i] = result.rows[i];
        }
      }
    } catch (e) {
      Global.logger.e('Walkman加载单词失败 (page=$pageIndex): $e');
    } finally {
      _loadingPages.remove(pageIndex);
    }
  }

  Future<WordWrapper?> getWordAt(int index) async {
    if (index < 0) return null;
    if (totalWordCount > 0 && index >= totalWordCount) return null;
    if (_wordCache.containsKey(index)) {
      return _wordCache[index];
    }
    final pageIndex = index ~/ _pageSize;
    await _loadPage(pageIndex);
    return _wordCache[index];
  }

  void prefetchAround(int index) {
    if (totalWordCount <= 0) return;
    // 预加载后一页
    final nextPage = (index + 5) ~/ _pageSize;
    if (!_loadingPages.contains(nextPage)) {
      final nextFrom = nextPage * _pageSize;
      if (nextFrom < totalWordCount && !_wordCache.containsKey(nextFrom)) {
        unawaited(_loadPage(nextPage));
      }
    }
    // 预加载前一页（以便向右滑动上一个词时秒开）
    if (index >= 5) {
      final prevPage = (index - 5) ~/ _pageSize;
      if (!_loadingPages.contains(prevPage)) {
        final prevFrom = prevPage * _pageSize;
        if (prevFrom >= 0 && !_wordCache.containsKey(prevFrom)) {
          unawaited(_loadPage(prevPage));
        }
      }
    }
  }

  Future<void> _saveCurrentPosition(int index, WordWrapper? word) async {
    if (word == null || params?.bookMarkProvider == null) return;
    try {
      await params!.bookMarkProvider!.saveBookMark(BookMarkVo(index, word.word.spell));
    } catch (e) {
      Global.logger.w('保存随身听当前位置失败: $e');
    }
  }

  Future<void> loadData() async {
    if (!await checkArgs()) {
      return;
    }
    await loadConfig();
    // 确保params已初始化
    if (params == null) {
      Global.logger.e('Walkman: params为空，无法加载数据');
      return;
    }

    // 确定起始位置
    int startPos = 0;
    if (params!.initialWordIndex != null && params!.initialWordIndex! >= 0) {
      startPos = params!.initialWordIndex!;
    } else if (params!.bookMarkProvider != null) {
      try {
        final bookmark = await params!.bookMarkProvider!.getBookMark();
        if (bookmark != null && bookmark.position >= 0) {
          startPos = bookmark.position;
        }
      } catch (e) {
        Global.logger.w('获取随身听书签失败: $e');
      }
    }

    final initialPage = startPos ~/ _pageSize;
    await _loadPage(initialPage);

    if (totalWordCount > 0 && startPos >= totalWordCount) {
      startPos = 0;
      if (!_wordCache.containsKey(0)) {
        await _loadPage(0);
      }
    }

    currWordIndex = startPos;
    nextWordIndex = startPos;
    prefetchAround(currWordIndex);

    if (mounted) {
      setState(() {
        dataLoaded = true;
        inited = true;
      });
    }
  }

  @override
  void dispose() {
    // 设置停止标志
    currentWordPlayShouldStop = true;

    // 取消所有计时器
    playWordTimer?.cancel();

    // 释放微动态视频背景与环境音效
    try {
      _videoController?.dispose();
    } catch (_) {}
    try {
      _ambientPlayer?.dispose();
    } catch (_) {}

    // 退出时保存最后播放的位置
    final currentWord = _wordCache[currWordIndex];
    if (currentWord != null) {
      _saveCurrentPosition(currWordIndex, currentWord);
    }

    // 退出全屏并恢复默认方向设置
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
  }

  Future<void> forceFinishCurrentWord() async {
    currentWordPlayShouldStop = true;

    // 强制停止所有可能的播放
    try {
      // 停止 TTS
      if (currentPlayStep == 'meaning' || currentPlayStep == 'chinese') {
        await tts?.stop();
      }
      
      // 停止 Just Audio 播放器
      await StudyAudioSessionController().cancelPlayback();
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
    final int session = _playSessionId;
    if (isShowingSettingPanel && !playEvenIfSettingPanelIsShowing) {
      // 设置面板显示且不播放时，只更新计时器
      playWordTimer = Timer(const Duration(milliseconds: 100), () {
        if (session == _playSessionId) {
          playWordTick();
        }
      });
    } else if ((_isFirstWord || waitedTime >= playInterval) && currentWordPlayingStopped) {
      // 如果是第一个单词，或者等待时间已到，且当前单词已停止播放
      
      // 重置等待时间和标记位
      waitedTime = 0;
      _isFirstWord = false;

      // 开始播放
      await doPlayWord();

      // 如果在此期间 Session 发生了变化，说明已经启动了新的播放循环，当前旧循环应退出
      if (session != _playSessionId) {
        return;
      }

      // 设置下一个计时器
      playWordTimer = Timer(Duration(milliseconds: _isFirstWord ? 0 : 100), () {
        if (session == _playSessionId) {
          if (waitedTime <= maxIntValue - 100) {
            waitedTime += 100;
          }
          playWordTick();
        }
      });
    } else {
      // 更新等待时间并继续计时
      playWordTimer = Timer(Duration(milliseconds: _isFirstWord ? 0 : 100), () {
        if (session == _playSessionId) {
          if (waitedTime <= maxIntValue - 100) {
            waitedTime += 100;
          }
          playWordTick();
        }
      });
    }
  }

  Future<void> doPlayWord() async {
    final int expectedSession = _playSessionId;
    try {
      currentWordPlayShouldStop = false;
      currentWordPlayingStopped = false;

      if (totalWordCount <= 0) {
        currentWordPlayingStopped = true;
        return;
      }

      // 播放当前单词
      if (mounted) {
        setState(() {
          currWordIndex = nextWordIndex;
        });
        if (totalWordCount > 0 && currWordIndex >= totalWordCount) {
          currWordIndex = 0;
        }

        WordWrapper? word = _wordCache[currWordIndex];
        word ??= await getWordAt(currWordIndex);

        if (word == null) {
          if (expectedSession == _playSessionId) {
            nextWordIndex = (totalWordCount > 0) ? ((currWordIndex + 1) % totalWordCount) : 0;
            currentWordPlayingStopped = true;
          }
          return;
        }

        _saveCurrentPosition(currWordIndex, word);
        prefetchAround(currWordIndex);

        // 提前获取例句，确保例句与当前单词匹配
        List<SentenceVo> sentences = [];
        try {
          sentences = await word.word.getBalancedSentences();
        } catch (e) {
          Global.logger.d("获取例句失败: $e");
          sentences = [];
        }

        // 检查是否被停止，避免获取例句期间状态变化
        if (currentWordPlayShouldStop || expectedSession != _playSessionId) {
          if (expectedSession == _playSessionId) currentWordPlayingStopped = true;
          return;
        }

        setState(() {
          currSentences = sentences;
          currSentenceIndex = 0;
        });

        for (var i = 0; i < repeatCount && !currentWordPlayShouldStop && expectedSession == _playSessionId; i++) {
          // 检查停止信号
          if (currentWordPlayShouldStop || expectedSession != _playSessionId) break;

          if (playPronounce && mounted) {
            currentPlayStep = 'pronounce';
            try {
              await StudyAudioSessionController().playWordSoundBySpell(word.word.spell);
            } catch (e) {
              // 忽略 AudioPlayer 错误
              Global.logger.d("播放发音失败: $e");
            }
            currentPlayStep = '';
            // 步骤之间增加微小延迟
            await Future.delayed(const Duration(milliseconds: 100));
          }

          // 检查停止信号
          if (currentWordPlayShouldStop || expectedSession != _playSessionId) break;

          if (playMeaning && PlatformUtils.isTtsSupported()) {
            // 播放释义前，休眠一会儿，以便用户可以回想一下
            // 如果是手动模式 (playInterval == maxIntValue) 或者是手动切换后的第一个词，则不在这里等待
            var sleepTime = 0;
            final effectiveInterval = (playInterval == maxIntValue || _forceNoWaitOnce) ? 0 : playInterval;
            while (!currentWordPlayShouldStop && expectedSession == _playSessionId && sleepTime < effectiveInterval * 0.5) {
              await Future.delayed(const Duration(milliseconds: 10), () {}); // 减少检查间隔
              sleepTime += 10;
            }

            if (!currentWordPlayShouldStop && expectedSession == _playSessionId) {
              currentPlayStep = 'meaning';
              if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
                // 确保 TTS 播放完成才继续
                await tts?.speak(Util.pureMeaningStr(word.word));
              }
              currentPlayStep = '';
              // 步骤之间增加微小延迟，给 TTS 引擎一点缓冲时间
              await Future.delayed(const Duration(milliseconds: 300));
            }
          }

          // 检查停止信号
          if (currentWordPlayShouldStop || expectedSession != _playSessionId) break;

          // 播放已预先获取的例句
          if (sentences.isNotEmpty) {
            final int actualPlaySentenceCount = playSentenceCount == -1 ? sentences.length : (playSentenceCount > sentences.length ? sentences.length : playSentenceCount);
            for (var j = 0; j < actualPlaySentenceCount; j++) {
              if (playSentence && !currentWordPlayShouldStop && expectedSession == _playSessionId && mounted) {
                currentPlayStep = 'sentence';
                setState(() {
                  currSentenceIndex = j;
                });
                try {
                  await StudyAudioSessionController().playSentenceSound(sentences[j].englishDigest!, speed: sentencePlaySpeed);
                } catch (e) {
                  // 忽略 AudioPlayer 错误
                  Global.logger.d("播放例句失败: $e");
                }
                currentPlayStep = '';
                // 步骤之间增加微小延迟
                await Future.delayed(const Duration(milliseconds: 300));
              }

              // 检查停止信号
              if (currentWordPlayShouldStop || expectedSession != _playSessionId) break;

              if (playChinese && !currentWordPlayShouldStop && expectedSession == _playSessionId) {
                currentPlayStep = 'chinese';
                await tts?.speak(Util.pureSentenceChinese(sentences[j].chinese!));
                currentPlayStep = '';
                // 步骤之间增加微小延迟
                await Future.delayed(const Duration(milliseconds: 300));
              }

              // 检查停止信号
              if (currentWordPlayShouldStop || expectedSession != _playSessionId) break;
            }
          }

          // 重复播放下一个单词前，等待一段时间
          if (i < repeatCount - 1) {
            var sleepTime = 0;
            final effectiveInterval = (playInterval == maxIntValue || _forceNoWaitOnce) ? 500 : playInterval; // 手动或强制模式下重复播放给 0.5 秒间隔
            while (!currentWordPlayShouldStop && expectedSession == _playSessionId && sleepTime < effectiveInterval) {
              await Future.delayed(const Duration(milliseconds: 10), () {}); // 减少检查间隔
              sleepTime += 10;
            }
          }
        }

        if (expectedSession == _playSessionId) {
          nextWordIndex = (totalWordCount > 0) ? ((currWordIndex + 1) % totalWordCount) : 0;
          _forceNoWaitOnce = false; // 当前单词播报完毕，重置强制标记
        }
      }
      if (expectedSession == _playSessionId) {
        currentWordPlayingStopped = true;
        _forceNoWaitOnce = false; // 确保即使异常也能重置
      }
    } catch (e) {
      // 即使出错也要更新nextWordIndex和播放状态，确保播放能继续到下一个单词
      if (mounted && expectedSession == _playSessionId) {
        nextWordIndex = (totalWordCount > 0) ? ((currWordIndex + 1) % totalWordCount) : 0;
      }
      if (expectedSession == _playSessionId) {
        currentWordPlayingStopped = true;
        _forceNoWaitOnce = false;
      }
      ToastUtil.error("播放异常");
    }
  }

  Widget renderWord(WordWrapper word) {
    final themeConfig = context.themeConfig;
    final hasScene = currentScene != WalkmanScene.none;
    final primaryTextColor = hasScene ? Colors.white : themeConfig.textPrimary;
    final secondaryTextColor = hasScene ? Colors.white.withValues(alpha: 0.85) : themeConfig.textSecondary;
    final spellFontSize = isLandscape ? 34.0 : 42.0;
    final meaningFontSize = isLandscape ? 15.0 : 15.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 单词英文
        if (showSpell)
          Text(
            word.word.spell,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              fontSize: spellFontSize,
              letterSpacing: -0.5,
              color: primaryTextColor,
              shadows: hasScene
                  ? [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        offset: const Offset(0, 2),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            textAlign: TextAlign.center,
          ),

        // 音标
        if (showPronounce && word.word.mergedPronounce.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              '[${word.word.mergedPronounce}]',
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontSize: isLandscape ? 14.0 : 16.0,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // 释义
        if (showMeaning) renderWordMeaning(word, meaningFontSize, hasScene),

        // 例句
        if (showSentence && currSentences.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20.0, left: 16, right: 16),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: hasScene
                    ? Colors.black.withValues(alpha: 0.38)
                    : context.cardBg.withValues(alpha: context.isDarkMode ? 0.4 : 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasScene
                      ? Colors.white.withValues(alpha: 0.18)
                      : context.cardBorder.withValues(alpha: 0.5),
                  width: 0.8,
                ),
                boxShadow: hasScene
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  renderRichText(
                    playSentence
                        ? (currSentences[currSentenceIndex].english ?? '')
                        : (currSentences[0].english ?? ''),
                    TextStyle(
                      fontSize: meaningFontSize,
                      fontStyle: FontStyle.italic,
                      color: primaryTextColor,
                      height: 1.4,
                    ),
                  ),
                  if (showChinese) ...[
                    const SizedBox(height: 8),
                    renderRichText(
                      playSentence
                          ? (currSentences[currSentenceIndex].chinese ?? '')
                          : (currSentences[0].chinese ?? ''),
                      TextStyle(
                        fontSize: meaningFontSize * 0.9,
                        color: secondaryTextColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // 播放/暂停悬浮控制按钮
        Padding(
          padding: const EdgeInsets.only(top: 28.0),
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (isShowingSettingPanel) {
                  playEvenIfSettingPanelIsShowing = !playEvenIfSettingPanelIsShowing;
                  if (playEvenIfSettingPanelIsShowing) {
                    currentWordPlayShouldStop = true;
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) resetPlayState();
                    });
                  } else {
                    currentWordPlayShouldStop = true;
                  }
                } else {
                  if (currentWordPlayingStopped) {
                    resetPlayState();
                  } else {
                    currentWordPlayShouldStop = true;
                    currentWordPlayingStopped = true;
                  }
                }
              });
            },
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasScene ? const Color(0xDD1E293B) : context.cardBg,
                border: Border.all(
                  color: hasScene
                      ? Colors.white.withValues(alpha: 0.25)
                      : themeConfig.primaryColor.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: themeConfig.primaryColor.withValues(alpha: hasScene ? 0.25 : 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                ((isShowingSettingPanel ? playEvenIfSettingPanelIsShowing : !currentWordPlayingStopped))
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
                color: hasScene ? Colors.white : themeConfig.primaryColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget renderWordMeaning(WordWrapper word, [double fontSize = 15.0, bool hasScene = false]) {
    final themeConfig = context.themeConfig;
    final meanings = word.word.getMergedMeaningItems();
    if (meanings.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var meaningItem in meanings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (meaningItem.ciXing != null && meaningItem.ciXing!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: hasScene
                            ? Colors.white.withValues(alpha: 0.16)
                            : themeConfig.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meaningItem.ciXing!,
                        style: TextStyle(
                          fontSize: fontSize * 0.82,
                          fontWeight: FontWeight.w600,
                          color: hasScene ? Colors.white : themeConfig.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      meaningItem.meaning ?? '',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w400,
                        color: hasScene ? Colors.white.withValues(alpha: 0.95) : themeConfig.textPrimary,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget renderRichText(String text, TextStyle baseStyle) {
    List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r"<b>(.*?)</b>");
    int lastMatchEnd = 0;

    for (var match in regExp.allMatches(text)) {
      // Add text before <b>
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: baseStyle));
      }
      // Add bold text
      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ));
      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: baseStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  void toggleSettingPanel({bool? show}) {
    final targetState = show ?? !isShowingSettingPanel;
    if (targetState == isShowingSettingPanel) return;

    setState(() {
      isShowingSettingPanel = targetState;
      if (isShowingSettingPanel) {
        playEvenIfSettingPanelIsShowing = !currentWordPlayingStopped;
      } else {
        if (playEvenIfSettingPanelIsShowing) {
          if (currentWordPlayingStopped) {
            resetPlayState();
          }
        }
      }
    });
  }

  Widget _renderTopBar() {
    final themeConfig = context.themeConfig;
    final isDark = context.isDarkMode;
    final hasScene = currentScene != WalkmanScene.none;
    final progress = totalWordCount > 0 ? (currWordIndex + 1) / totalWordCount : 0.0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 32.0 : 16.0,
          vertical: 6.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 退出按钮
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasScene
                      ? Colors.black.withValues(alpha: 0.35)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.04)),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: hasScene ? Colors.white : themeConfig.textPrimary,
                ),
              ),
            ),

            // 挺拔修长的当前学习进度
            Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Row(
                   mainAxisSize: MainAxisSize.min,
                   crossAxisAlignment: CrossAxisAlignment.baseline,
                   textBaseline: TextBaseline.alphabetic,
                   children: [
                     Text(
                       '${currWordIndex + 1}',
                       style: TextStyle(
                         fontFamily: 'Roboto',
                         fontSize: 15,
                         fontWeight: FontWeight.w700,
                         color: hasScene ? Colors.white : themeConfig.textPrimary,
                       ),
                     ),
                     Text(
                       ' / $totalWordCount',
                       style: TextStyle(
                         fontFamily: 'Roboto',
                         fontSize: 12.5,
                         fontWeight: FontWeight.w400,
                         color: hasScene
                             ? Colors.white.withValues(alpha: 0.75)
                             : themeConfig.textSecondary.withValues(alpha: 0.65),
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 5),
                 // 极细微进度条
                 ClipRRect(
                   borderRadius: BorderRadius.circular(2),
                   child: SizedBox(
                     width: 108,
                     height: 3,
                     child: Stack(
                       children: [
                         Container(
                           color: hasScene
                               ? Colors.white.withValues(alpha: 0.22)
                               : (isDark
                                   ? Colors.white.withValues(alpha: 0.1)
                                   : Colors.black.withValues(alpha: 0.06)),
                         ),
                         FractionallySizedBox(
                           widthFactor: progress,
                           alignment: Alignment.centerLeft,
                           child: Container(
                             color: themeConfig.primaryColor,
                           ),
                         ),
                       ],
                     ),
                   ),
                 ),
               ],
            ),

            // 设置开关按钮
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => toggleSettingPanel(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isShowingSettingPanel
                      ? themeConfig.primaryColor.withValues(alpha: 0.15)
                      : (hasScene
                          ? Colors.black.withValues(alpha: 0.35)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.04))),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: isShowingSettingPanel
                      ? themeConfig.primaryColor
                      : (hasScene ? Colors.white : themeConfig.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget renderPage() {
    if (totalWordCount == 0) {
      return const Center(
        child: Text(
          '词单暂无单词',
          style: TextStyle(color: Colors.grey, fontSize: 16.0),
        ),
      );
    }
    final word = _wordCache[currWordIndex];
    if (word == null) {
      getWordAt(currWordIndex).then((w) {
        if (mounted && w != null) setState(() {});
      });
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // 0. 动态微动态背景视频层（FittedBox cover充满全屏，静音平滑无缝循环）
        if (currentScene.hasVideo &&
            _videoController != null &&
            _videoController!.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ),

        // 0.1 沉浸式暗色渐变蒙层（保留微动态美感的同时确保文字清晰度）
        if (currentScene != WalkmanScene.none)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.36),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),

        // 1. 主内容与触控手势区
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              toggleSettingPanel();
            },
            onHorizontalDragEnd: (DragEndDetails details) async {
              if (totalWordCount <= 0) return;
              // 向左滑动, 播放下一个单词
              if (details.velocity.pixelsPerSecond.dx <= -500) {
                int nextIdx = (currWordIndex + 1) % totalWordCount;
                _handleWordSwitch(nextIdx);
              }
              // 向右滑动, 播放上一个单词
              else if (details.velocity.pixelsPerSecond.dx >= 500) {
                int prevIdx = currWordIndex >= 1 ? currWordIndex - 1 : totalWordCount - 1;
                _handleWordSwitch(prevIdx);
              }
            },
            child: Column(
              children: [
                _renderTopBar(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 40.0 : 20.0,
                        vertical: 12.0,
                      ),
                      child: renderWord(word),
                    ),
                  ),
                ),
                SizedBox(height: isLandscape ? 12.0 : 24.0),
              ],
            ),
          ),
        ),

        // 面板展开时的轻柔背景遮罩（点击可收起面板）
        if (isShowingSettingPanel)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => toggleSettingPanel(show: false),
              child: Container(
                color: Colors.black.withValues(alpha: context.isDarkMode ? 0.35 : 0.12),
              ),
            ),
          ),

        // 底部毛玻璃控制面板（使用 AnimatedSlide 做平滑位移，避免任何 OpacityLayer 破坏底层渲染）
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            offset: isShowingSettingPanel ? Offset.zero : const Offset(0, 1.15),
            child: renderSettingPanel(),
          ),
        ),
      ],
    );
  }

  Widget renderSettingPanel() {
    final isDark = context.isDarkMode;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xD9171C26)
                  : const Color(0xCCFFFFFF),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 1.0,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部拖拽手柄
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 1. 显示行
                      _buildSettingRow(
                        title: '显示',
                        children: [
                          _buildSettingPill(
                            label: '英文',
                            selected: showSpell,
                            onTap: () {
                              setState(() {
                                showSpell = !showSpell;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '音标',
                            selected: showPronounce,
                            onTap: () {
                              setState(() {
                                showPronounce = !showPronounce;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '释义',
                            selected: showMeaning,
                            onTap: () {
                              setState(() {
                                showMeaning = !showMeaning;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '例句',
                            selected: showSentence,
                            onTap: () {
                              setState(() {
                                showSentence = !showSentence;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '翻译',
                            selected: showChinese,
                            onTap: () {
                              setState(() {
                                showChinese = !showChinese;
                                saveConfig();
                              });
                            },
                          ),
                        ],
                      ),
                      // 2. 发音行
                      _buildSettingRow(
                        title: '发音',
                        children: [
                          _buildSettingPill(
                            label: '英文',
                            selected: playPronounce,
                            onTap: () {
                              setState(() {
                                playPronounce = !playPronounce;
                                saveConfig();
                              });
                            },
                          ),
                          if (PlatformUtils.isTtsSupported())
                            _buildSettingPill(
                              label: '释义',
                              selected: playMeaning,
                              onTap: () {
                                setState(() {
                                  playMeaning = !playMeaning;
                                  saveConfig();
                                });
                              },
                            ),
                          _buildSettingPill(
                            label: '例句',
                            selected: playSentence,
                            onTap: () {
                              setState(() {
                                playSentence = !playSentence;
                                saveConfig();
                              });
                            },
                          ),
                          if (PlatformUtils.isTtsSupported())
                            _buildSettingPill(
                              label: '翻译',
                              selected: playChinese,
                              onTap: () {
                                setState(() {
                                  playChinese = !playChinese;
                                  saveConfig();
                                });
                              },
                            ),
                        ],
                      ),
                      // 3. 句数行
                      _buildSettingRow(
                        title: '句数',
                        titleEnabled: playSentence,
                        children: [
                          for (var count in [1, 2, 3, 4])
                            _buildSettingPill(
                              label: '$count句',
                              selected: playSentence && playSentenceCount == count,
                              enabled: playSentence,
                              onTap: () {
                                setState(() {
                                  playSentenceCount = count;
                                  saveConfig();
                                });
                              },
                            ),
                          _buildSettingPill(
                            label: '全部',
                            selected: playSentence && playSentenceCount == -1,
                            enabled: playSentence,
                            onTap: () {
                              setState(() {
                                playSentenceCount = -1;
                                saveConfig();
                              });
                            },
                          ),
                        ],
                      ),
                      // 4. 重复行
                      _buildSettingRow(
                        title: '重复',
                        children: [
                          for (var count in [1, 2, 3, 4, 5])
                            _buildSettingPill(
                              label: '$count次',
                              selected: repeatCount == count,
                              onTap: () {
                                setState(() {
                                  repeatCount = count;
                                  saveConfig();
                                });
                              },
                            ),
                        ],
                      ),
                      // 5. 间隔行
                      _buildSettingRow(
                        title: '间隔',
                        children: [
                          _buildSettingPill(
                            label: '0秒',
                            selected: playInterval == 0,
                            onTap: () {
                              setState(() {
                                playInterval = 0;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '1秒',
                            selected: playInterval == 1000,
                            onTap: () {
                              setState(() {
                                playInterval = 1000;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '2秒',
                            selected: playInterval == 2000,
                            onTap: () {
                              setState(() {
                                playInterval = 2000;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '3秒',
                            selected: playInterval == 3000,
                            onTap: () {
                              setState(() {
                                playInterval = 3000;
                                saveConfig();
                              });
                            },
                          ),
                          _buildSettingPill(
                            label: '手动',
                            selected: playInterval == maxIntValue,
                            onTap: () {
                              setState(() {
                                playInterval = maxIntValue;
                                saveConfig();
                              });
                              ToastUtil.info('手指向左滑动，播放下一单词');
                            },
                          ),
                        ],
                      ),
                      // 6. 自然沉浸场景行
                      _buildSettingRow(
                        title: '场景',
                        children: [
                          for (var s in WalkmanScene.values)
                            _buildSettingPill(
                              label: s.title,
                              selected: currentScene == s,
                              onTap: () {
                                _applyScene(s);
                              },
                            ),
                        ],
                      ),
                      // 7. 环境白噪音音效行（开启自然场景时展示）
                      if (currentScene.hasAudio)
                        _buildSettingRow(
                          title: '音效',
                          children: [
                            _buildSettingPill(
                              label: ambientMuted ? '已静音' : '静音',
                              selected: ambientMuted,
                              onTap: () {
                                _toggleAmbientMute();
                              },
                            ),
                            for (var vol in [0.35, 0.65, 1.0])
                              _buildSettingPill(
                                label: '${(vol * 100).round()}%',
                                selected: !ambientMuted && (ambientVolume - vol).abs() < 0.08,
                                onTap: () {
                                  _setAmbientVolume(vol);
                                },
                              ),
                          ],
                        ),
                    // 8. 其他行
                    _buildSettingRow(
                      title: '其他',
                      children: [
                        _buildSettingPill(
                          label: context.watch<DarkMode>().themeStyle.label,
                          selected: false,
                          onTap: () {
                            ThemeSelectDialog.show(context);
                          },
                        ),
                        _buildSettingPill(
                          label: isLandscape ? '竖屏' : '横屏',
                          selected: false,
                          onTap: () {
                            toggleOrientation();
                          },
                        ),
                        _buildSettingPill(
                          label: '离开',
                          selected: false,
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildSettingRow({
    required String title,
    required List<Widget> children,
    bool titleEnabled = true,
  }) {
    final isDark = context.isDarkMode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: titleEnabled
                    ? (isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155))
                    : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.25)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final themeConfig = context.themeConfig;
    final isDark = context.isDarkMode;

    Color bgColor;
    Color textColor;
    BoxShadow? shadow;

    if (!enabled) {
      bgColor = Colors.transparent;
      textColor = isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.22);
    } else if (selected) {
      bgColor = themeConfig.primaryColor;
      textColor = Colors.white;
      shadow = BoxShadow(
        color: themeConfig.primaryColor.withValues(alpha: 0.3),
        blurRadius: 6,
        offset: const Offset(0, 2),
      );
    } else {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04);
      textColor = themeConfig.textSecondary;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
          boxShadow: shadow != null ? [shadow] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: textColor,
          ),
        ),
      ),
    );
  }

  // 统一处理单词切换，确保响应迅速
  Future<void> _handleWordSwitch(int newIndex) async {
    // 1. 立即设置停止信号并增加 Session ID，这会瞬间阻断当前正在进行的 doPlayWord 循环
    currentWordPlayShouldStop = true;
    _playSessionId++;

    // 2. 立即尝试停止物理播放器 (TTS 和 Just Audio)
    try {
      unawaited(tts?.stop());
      await StudyAudioSessionController().cancelPlayback();
    } catch (e) {
      Global.logger.d("切换单词时停止播放出错: $e");
    }

    if (totalWordCount > 0) {
      if (newIndex < 0) newIndex = totalWordCount - 1;
      if (newIndex >= totalWordCount) newIndex = 0;
    }

    // 3. 立即更新 UI 和索引
    setState(() {
      currWordIndex = newIndex;
      nextWordIndex = currWordIndex;
    });

    final word = _wordCache[currWordIndex];
    if (word != null) {
      _saveCurrentPosition(currWordIndex, word);
    }
    prefetchAround(currWordIndex);

    // 4. 重置状态并开启新一轮播放
    _forceNoWaitOnce = true;
    resetPlayState();
  }

  @override
  Widget build(BuildContext context) {
    // 全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    return AppScaffold(
      vibrancy: PageVibrancy.walkman,
      body: Container(
        // 横屏模式下调整内边距
        padding: EdgeInsets.fromLTRB(leftPadding, isLandscape ? 8.0 : 16.0, rightPadding, 0),
        child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
      ),
    );
  }

  // 完全重置播放状态，确保可以重新开始播放
  void resetPlayState() {
    _playSessionId++; // 每次重置时递增，强行阻断旧的休眠或播放异步等待
    // 重置状态标志
    currentWordPlayingStopped = true;
    currentWordPlayShouldStop = false;
    currentPlayStep = '';

    // 设置为 maxIntValue，确保在 playWordTick 中能立即通过 (waitedTime >= playInterval) 的检查
    waitedTime = maxIntValue;
    _isFirstWord = true; // 视为新的“第一个”单词，确保立即响应

    // 取消并重建计时器
    if (playWordTimer != null) {
      playWordTimer!.cancel();
    }

    // 重新启动播放循环
    playWordTimer = Timer(const Duration(milliseconds: 10), () {
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
