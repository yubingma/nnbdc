part of '../../bdc.dart';

extension BdcPageStateLogic on BdcPageState {
  void _saveCurrentWordState() {
    if (_word?.id != null) {
      _wordUIStates[_word!.id!] = WordUIState(
        studyStep: _studyStep,
        hasFinishedAnswering: _hasFinishedAnswering,
        canLeaveCurrWord: _canLeaveCurrWord,
        showSentenceTranslation: _showSentenceTranslation,
        selectedAnswerIndex: _selectedAnswerIndex,
        flippedAnswerIndices: Set<int>.from(_flippedAnswerIndices),
        tabIndex: _tabController?.index ?? _currentTabIndex,
        currentScore: _currentScore,
        meaningText: _meaningController.text,
        words: _words != null ? List<WordVo>.from(_words!) : null,
        correctAnswerIndex: _correctAnswerIndex,
        fsrsItem: _fsrsItem,
        daysSinceLastReview: _daysSinceLastReview,
        lastFsrsRating: _lastFsrsRating,
        asrMatchedMeaningItemParts: _wordWrapper != null 
          ? List<Pair<int, int>>.from(_wordWrapper!.asrMatchedMeaningItemParts) 
          : null,
        asrRevealedMeaningItemParts: _wordWrapper != null 
          ? List<Pair<int, int>>.from(_wordWrapper!.asrRevealedMeaningItemParts) 
          : null,
        currentAsrCandidates: List<String>.from(_currentAsrCandidates),
      );
    }
  }


  void _persistLastWordHistoryItem() {
    try {
      final state = _word?.id != null ? _wordUIStates[_word!.id!] : null;
      if (state != null) {
        final targetWord = _currentGetWordResult!.learningWord?.word;
        final others = _currentGetWordResult!.otherWords;
        
        final lastWordData = {
          'wordResult': _currentGetWordResult!.toJson(),
          'state': {
            'hasFinishedAnswering': state.hasFinishedAnswering,
            'canLeaveCurrWord': state.canLeaveCurrWord,
            'showSentenceTranslation': state.showSentenceTranslation,
            'selectedAnswerIndex': state.selectedAnswerIndex,
            'flippedAnswerIndices': state.flippedAnswerIndices.toList(),
            'tabIndex': state.tabIndex,
            'currentScore': state.currentScore,
            'meaningText': state.meaningText,
            'correctAnswerIndex': state.correctAnswerIndex,
            'fsrsItem': state.fsrsItem != null ? {
              'stability': state.fsrsItem!.stability,
              'difficulty': state.fsrsItem!.difficulty,
              'elapsedDays': state.fsrsItem!.elapsedDays,
              'scheduledDays': state.fsrsItem!.scheduledDays,
              'reps': state.fsrsItem!.reps,
              'lapses': state.fsrsItem!.lapses,
              'state': state.fsrsItem!.state.index,
            } : null,
            'daysSinceLastReview': state.daysSinceLastReview,
            'lastFsrsRating': state.lastFsrsRating?.index,
            'asrMatchedMeaningItemParts': state.asrMatchedMeaningItemParts?.map((p) => [p.first, p.second]).toList(),
            'asrRevealedMeaningItemParts': state.asrRevealedMeaningItemParts?.map((p) => [p.first, p.second]).toList(),
            'currentAsrCandidates': state.currentAsrCandidates,
            'wordsIndices': state.words?.map((w) {
              if (w.spell == "[ 都不对 ]") return 3;
              if (targetWord != null && w.id == targetWord.id) return 0;
              if (others != null && others.isNotEmpty && w.id == others[0].id) return 1;
              if (others != null && others.length > 1 && w.id == others[1].id) return 2;
              return -1;
            }).toList(),
          }
        };
        GetStorage().write('last_word_history_item', json.encode(lastWordData));
      }
    } catch (e, s) {
      Global.logger.e('持久化上一个单词失败', error: e, stackTrace: s);
    }
  }


  void _restoreWordState(GetWordResult result) {
    final state = _word?.id != null ? _wordUIStates[_word!.id!] : null;
    if (state != null) {
      _hasFinishedAnswering = state.hasFinishedAnswering;
      _canLeaveCurrWord = state.canLeaveCurrWord;
      _meaningController.text = state.meaningText;
      _showSentenceTranslation = state.showSentenceTranslation;
      _selectedAnswerIndex = state.selectedAnswerIndex;
      _flippedAnswerIndices.clear();
      _flippedAnswerIndices.addAll(state.flippedAnswerIndices);
      _currentTabIndex = state.tabIndex;
      _currentScore = state.currentScore;
      _words = state.words != null ? List<WordVo>.from(state.words!) : null;
      _correctAnswerIndex = state.correctAnswerIndex;
      _fsrsItem = state.fsrsItem;
      _daysSinceLastReview = state.daysSinceLastReview;
      _lastFsrsRating = state.lastFsrsRating;
      _currentAsrCandidates = state.currentAsrCandidates != null 
        ? List<String>.from(state.currentAsrCandidates!) 
        : [];
    }
  }


  void _reinitializeTabController({bool preserveCurrentIndex = false}) {
    // 记住当前tab索引
    if (!preserveCurrentIndex && _tabController != null) {
      _currentTabIndex = _tabController!.index;
    }

    // 注意：不在这里 dispose 旧的 TabController，避免在手势处理中
    // 仍然引用旧 controller 时触发 "used after being disposed" 异常。
    // 旧的 controller 会在页面整体 dispose 时统一释放。
    _tabController = TabController(length: _dynamicTabs.length, vsync: this);

    // 确保索引在有效范围内
    if (_currentTabIndex >= _dynamicTabs.length) {
      _currentTabIndex = _dynamicTabs.length - 1; // 选择最后一个tab
    }

    // 设置到之前选中的tab
    _tabController!.index = _currentTabIndex;

    // 重新添加监听器
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        // Tab正在切换中
        return;
      }

      // 更新当前tab索引
      _currentTabIndex = _tabController!.index;

      _handleTabChangeForAsr();
    });
  }


  void _handleTabChangeForAsr() {
    _doHandleTabChangeForAsr();
  }


  void _doHandleTabChangeForAsr() {
    if (_isInSpeakTab) {
      // 当前在"说"tab
      _firstMatchTime = null;

      // 如果已经做完题、正在手写/拼写沉浸模式，或者正在获取下一词，或者当前页面不是顶层路由（如已进入详情页），则严禁启动语音识别提示
      if (_hasFinishedAnswering || _showHandwritingBoard || _isGettingNextWord || !(ModalRoute.of(context)?.isCurrent ?? true)) {
        Global.logger.d('BDC: 由于正处于答题完毕状态、拼写模式、正在加载下一词或页面不在顶层，严禁自动启动 ASR (hasFinishedAnswering=$_hasFinishedAnswering, showHandwriting=$_showHandwritingBoard, isGettingNext=$_isGettingNextWord, isCurrent=${ModalRoute.of(context)?.isCurrent})');
        if (asr.state != AsrState.stopped && asr.state != AsrState.initialized) {
          asr.stopAsr();
        }
        return;
      }

      // 如果ASR已经启动且状态正确，计时器已经开始或将在_startAsrWithHint中重置
      if (asr.state == AsrState.started && !_isKeyboardVisible) {
        Global.logger.d('BDC: 当前在"说"tab，ASR已启动，保持计时');
        return;
      }
      // 将在此处设置初始计时，防止_startAsrWithHint被跳过或延迟太久
      _wordStartTime = AppClock.now();

      // 启动ASR
      Global.logger.d('BDC: 当前在"说"tab，启动ASR (studyStep=$_studyStep)');
      if (!_isKeyboardVisible) {
        // 设置上下文短语
        _setAsrContextualPhrases();
        final language = decideAsrLanguage();
        Global.logger.d('BDC: 准备启动ASR，语言=${language.locale}');
        // 启动ASR并播放提示音
        _startAsrWithHint(language);
      }
    } else {
      // 当前在"选"tab，从切换这一刻重新开始计时（之前的播放时间或 ASR 等待时间不计入）
      _wordStartTime = AppClock.now();
      _firstMatchTime = null;

      // 如果当前在"选"tab，如果ASR已经停止，不需要再次停止

      // 如果当前在"选"tab，如果ASR已经停止，不需要再次停止
      if (asr.state == AsrState.stopped || asr.state == AsrState.initialized) {
        Global.logger.d('BDC: 当前在"选"tab，ASR已停止，跳过重复停止');
        return;
      }
      // 当前在"选"tab，停止ASR
      Global.logger.d('BDC: 当前在"选"tab，停止ASR');
      asr.stopAsr();
    }
  }


  void _startLearningTimer() {
    _learningTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _accumulatedSeconds++;
      if (_accumulatedSeconds % 10 == 0) {
        _syncLearningTimeToDb();
      }
    });
  }


  Future<void> _syncLearningTimeToDb() async {
    if (_accumulatedSeconds <= 0) return;
    int secsToSync = _accumulatedSeconds;
    _accumulatedSeconds = 0;

    try {
      final user = Global.getLoggedInUser();
      if (user == null) return;
      final dao = MyDatabase.instance.usersDao;
      final dbUser = await dao.getUserById(user.id);
      if (dbUser != null) {
        // 重置今日学习时长（如果不是今天）
        int todaySecs = dbUser.todayLearningSeconds ?? 0;
        if (dbUser.lastLearningDate != null) {
          final now = AppClock.now();
          if (dbUser.lastLearningDate!.year != now.year ||
              dbUser.lastLearningDate!.month != now.month ||
              dbUser.lastLearningDate!.day != now.day) {
            todaySecs = 0;
          }
        }

        final newTotal = (dbUser.totalLearningSeconds ?? 0) + secsToSync;
        final newToday = todaySecs + secsToSync;

        final updatedDbUser = dbUser.copyWith(
          totalLearningSeconds: drift.Value(newTotal),
          todayLearningSeconds: drift.Value(newToday),
          lastLearningDate: drift.Value(AppClock.now()),
        );

        await dao.saveUser(updatedDbUser, true);
        Global.updateUserCache(updatedDbUser);
        
        // 更新历史每日统计
        await MyDatabase.instance.userStudyDailyStatsDao.incrementSeconds(user.id, AppClock.now(), secsToSync);
      }
    } catch (e) {
      Global.logger.e("同步学习时长失败", error: e);
      // 如果失败把时间加回去
      _accumulatedSeconds += secsToSync;
    }
  }


  AsrLanguage decideAsrLanguage() {
    Global.logger.d(
        'BDC: decideAsrLanguage() - studyStep=$_studyStep, meaning.json=${StudyStep.ch2En.json}, word.json=${StudyStep.en2Ch.json}');
    if (_studyStep == StudyStep.ch2En.json) {
      Global.logger.d('BDC: 决定使用英文ASR (中→英模式)');
      return AsrLanguage.english;
    }
    Global.logger.d('BDC: 决定使用中文ASR (英→中模式)');
    return AsrLanguage.chinese;
  }


  void _setAsrContextualPhrases() {
    try {
      WordVo? word = _word;
      if (word != null) {
        List<String> phrases = [];
        if (_studyStep == StudyStep.ch2En.json) {
          // 中→英模式：热词设为英文拼写，这能极大提高 ASR 识别当前单词的准确率
          phrases.add(word.spell);
        } else if (_studyStep == StudyStep.en2Ch.json) {
          // 英→中模式：热词设为该词的所有可能释义项，由于 ASR 模型较小，这能显著矫正发音相近的中文词汇
          phrases.addAll(AsrUtil.extractContextualPhrases(word.meaningItems ?? []));
        }

        if (phrases.isNotEmpty) {
          Global.logger.d('~~~~~BDC: 设置 ASR 上下文热词: $phrases');
          asr.setContextualStrings(phrases);
        } else {
          // 如果没有有效热词（如单词对象为空），则清空之前的热词状态
          asr.setContextualStrings([]);
        }
      } else {
        asr.setContextualStrings([]);
      }
    } catch (e) {
      Global.logger.d('BDC: 设置 ASR 上下文短语失败: $e');
    }
  }


  Future<void> _startAsrWithHint(AsrLanguage language) async {
    // 严禁正在手写/沉浸拼写模式，或者正在加载下一词时开启 ASR 会话。
    // 这防止了由键盘监听器或其他侧边回调引起的意外 ASR 提示音爆发。
    if (_showHandwritingBoard || _isGettingNextWord) {
      Global.logger.d('BDC: 由于正处于拼写沉浸模式或正在切换单词，取消 ASR 启动请求 (showHandwriting=$_showHandwritingBoard, isGettingNext=$_isGettingNextWord)');
      return;
    }

    // 如果ASR已经在运行中，不需要重复启动
    if (asr.state == AsrState.started) {
      Global.logger.d('BDC: ASR已经在运行中，跳过重复启动');
      return;
    }

    try {
      await asr.startAsr(language);
      Global.logger.d('BDC: ASR启动成功，播放提示音并计时');
      // startAsr 后立即播放提示音：mixWithOthers 保证录音和播放可共存
      // 注意：不在此处先 stopAsr 再播再 startAsr，那样会多两次音频会话切换产生额外噪音
      if (PlatformUtils.isIOS) {
        // iOS上AVAudioEngine启动后需要一小段缓冲时间，否则紧接着播放音频会产生发颤或杂音
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await SoundUtil.playAsrReadyHintSound();
      _wordStartTime = AppClock.now();
    } catch (e, stackTrace) {
      Global.logger.e('BDC: ASR启动失败', error: e, stackTrace: stackTrace);
      // 即使启动抛出异常，如果 ASR 状态已经是 started（iOS 上会抛异常但实际已启动），
      // 仍然需要播放提示音，提示用户可以开始说话
      if (asr.state == AsrState.started) {
        Global.logger.d('BDC: ASR状态为started，播放提示音并计时');
        if (PlatformUtils.isIOS) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
        await SoundUtil.playAsrReadyHintSound();
        _wordStartTime = AppClock.now();
      }
    } finally {}
  }


  void _onAnswerCorrect(FsrsRating rating) async {
    final answerCorrectStart = DateTime.now();
    // 巩固环节自动评分只允许降低，不允许拔高（除非是用户手工设置评分，那里走的是 _updateFsrsRating）
    if (_currentGetWordResult != null &&
        _currentGetWordResult!.stepIndex > 0 &&
        _assessmentRating != null) {
      if (rating.index > _assessmentRating!.index) {
        Global.logger.d('BDC: 巩固环节中不允许将评分从 ${_assessmentRating!.label} 拔高至 ${rating.label}，自动调整为限高评分。');
        rating = _assessmentRating!;
      }
    }

    _hasFinishedAnswering = true;
    _canLeaveCurrWord = true;

    if (!_autoJumpAfterCorrect || _historyIndex != -1) {
      Global.logger.d(
          'BDC: 非极速模式，拼写正确，准备关闭沉浸式输入界面. _showHandwritingBoard=false, unfocusing');
      _meaningFocusNode.unfocus();
      updateUI(() {
        _showHandwritingBoard = false; // 立即关闭且回到主界面
      });
      _doHandleTabChangeForAsr();
    }

    // 计算 FSRS 预览结果
    final lw = _currentGetWordResult?.learningWord;
    if (lw != null) {
      final fsrs = FSRS();

      // 计算距离上次复习的天数
      _daysSinceLastReview = 0;
      if (lw.lastLearningDate != null) {
        final lastDate = DateTime(lw.lastLearningDate!.year,
            lw.lastLearningDate!.month, lw.lastLearningDate!.day);
        final now = AppClock.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        _daysSinceLastReview = todayDate.difference(lastDate).inDays;
      }

      if (lw.stability == null || lw.stability == 0.0) {
        _fsrsItem = fsrs.init(rating);
      } else {
        final prevItem = FSRSItem(
          stability: lw.stability!,
          difficulty: lw.difficulty!,
          elapsedDays: _daysSinceLastReview ?? 0,
          scheduledDays: lw.scheduledDays ?? 0,
          reps: lw.reps ?? 0,
          lapses: lw.lapses ?? 0,
          state: FsrsStateExt.fromInt(lw.state),
        );
        _fsrsItem = fsrs.next(prevItem, rating, _daysSinceLastReview ?? 0);
      }
    }

    _lastFsrsRating = rating;

    if (!_autoJumpAfterCorrect && _wordWrapper != null) {
      final meaningItems = _wordWrapper!.word.getMergedMeaningItems();
      for (var i = 0; i < meaningItems.length; i++) {
        var parts = splitMeaning2Parts(meaningItems[i].meaning!);
        for (var j = 0; j < parts.length; j++) {
          if (!_wordWrapper!.asrMatchedMeaningItemParts.contains(Pair(i, j)) &&
              !_wordWrapper!.asrRevealedMeaningItemParts.contains(Pair(i, j))) {
            _wordWrapper!.asrRevealedMeaningItemParts.add(Pair(i, j));
          }
        }
      }
    }

    if (mounted) {
      updateUI(() {}); // 立即显示 FSRS 和完整释义
    }

    // 中英模式下，在等待 iOS 音频引擎缓冲期间就开始预缓存单词发音文件，
    // 与 correct.mp3 播放并行，这样 correct.mp3 播完后发音可立即开始而无需等网络下载。
    if (_studyStep == StudyStep.ch2En.json && _word != null && !PlatformUtils.isWeb) {
      final soundUrl = Util.getWordSoundUrl(_word!.spell, word: _word);
      SoundUtil.prefetchSounds([soundUrl]);
    }

    // 核心修复：无论是 Android 还是 iOS，硬件从录音切回播音都需要时间（呼吸窗口）。
    // 100ms 的延迟足以让 ASR 占用的底层音频轨道彻底关闭，确保后续播放能顺利获得硬件访问权。
    await Future.delayed(const Duration(milliseconds: 100));

    // 播放正确提示音（尝试播放，失败不阻塞发音）
    final currentWordId = _word?.id;
    if (_studyStep != StudyStep.ch2En.json) {
      try {
        SoundUtil.playAssetSoundConcurrent('correct.mp3', 1.0, 1.0);
      } catch (e) {
        Global.logger.w('播放 correct.mp3 失败: $e');
      }
    }

    if (!mounted) return;
    // 播放一遍单词的标准发音（中英模式下需要朗读）
    if (_studyStep == StudyStep.ch2En.json) {
      // 核心优化：立即启动发音播放。
      // 注意：playPronounceSound2 内部已优化为优先查找本地缓存，实现零延迟起播。
      unawaited(SoundUtil.playPronounceSound2(_word!, _audioPlayer).then((_) {
        Global.logger.d('[PERF] playPronounceSound2 异步播放完成');
      }));
    }

    Global.logger.d('[PERF] _onAnswerCorrect 反馈启动耗时: ${DateTime.now().difference(answerCorrectStart).inMilliseconds}ms');
    if (_autoJumpAfterCorrect && _historyIndex == -1 && mounted && _word?.id == currentWordId) {
      // 核心优化：延迟 800ms 再跳词。
      // 500ms 有时仍显局促，800ms 能更好地保障发音完整性和视觉停留感。
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _word?.id == currentWordId) {
          getNextWord(true, fsrsRating: rating);
        }
      });
    }
  }


  bool _isAsrPassSync(int totalParts, int matchedParts) {
    Global.logger.d(
        '_isAsrPass: asrPassRule=$_asrPassRuleCache, totalParts=$totalParts, matchedParts=$matchedParts');

    bool result;
    switch (_asrPassRuleCache) {
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
    Global.logger.d('_isAsrPassSync result: $result');
    return result;
  }


  Future<void> loadData() async {
    Api.setLoadingDisabled(true);
    try {
      // 获取5个展示单词
      List<String> displayWords = [];
      try {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getLastLoggedInUser();
        if (user != null) {
          final query = db.select(db.learningWords)
            ..where((tbl) => tbl.userId.equals(user.id) & tbl.batchId.isBiggerThanValue(0));
          final todayWords = await query.get();
          
          var newWords = todayWords.where((w) => w.state == 0).toList();
          var reviewWords = todayWords.where((w) => w.state != 0).toList();
          
          newWords.shuffle();
          reviewWords.shuffle();
          
          var selectedWords = [];
          selectedWords.addAll(newWords.take(5));
          if (selectedWords.length < 5) {
            selectedWords.addAll(reviewWords.take(5 - selectedWords.length));
          }
          
          for (var w in selectedWords) {
            final wordItem = await db.wordsDao.getWordById(w.wordId);
            if (wordItem != null && wordItem.spell.isNotEmpty) {
              displayWords.add(wordItem.spell);
            }
          }
        }
      } catch (e) {
        Global.logger.e('获取展示单词失败: $e');
      }

      // 在下一帧显示初始化反馈的提示框
      BuildContext? dialogContext;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.1),
          builder: (ctx) {
            dialogContext = ctx;
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : Colors.black87;
            
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(horizontal: 40),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark 
                        ? const Color(0xFF1E1E1E).withValues(alpha: 0.75) 
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 专属加载图标
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "语音识别引擎",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "正在准备离线识别模型...",
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      
                      if (displayWords.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: displayWords.asMap().entries.map((entry) {
                            int idx = entry.key;
                            String word = entry.value;
                            
                            return TweenAnimationBuilder<double>(
                              duration: Duration(milliseconds: 600 + (idx * 100)),
                              curve: Curves.easeOutQuart,
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 15 * (1 - value)),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      child: Text(
                                        word,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      });

      // 预加载语音识别模型（耗时操作）
      await asr.preloadModels();

      // 如果模型加载完成且弹窗还在，或者 dialogContext 已赋值，将其关闭
      // 等待一个极短的时间，确保 postFrameCallback 执行并且 dialog 已经弹出
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      if (dialogContext != null) {
        // ignore: use_build_context_synchronously
        Navigator.of(dialogContext!).pop();
      } else {
        // 若上面因为某些原因 dialogContext 还未赋值但 dialog 被弹出了
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (dialogContext != null) {
            Navigator.of(dialogContext!).pop();
          } else if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
      }

      // 保证音频会话配置已完成
      await SoundUtil.configureAudioSession();

      MyDatabase.instance.localParamsDao.getIsDarkMode().then((value) {
        if (mounted) {
          updateUI(() {
            _isDarkMode = value;
          });
        }
      });

      final studyConfig = StudyConfig.fromCurrentUser();
      // _asrPassRuleCache = studyConfig.asrPassRule; // This will be an int (0-100)
      if (mounted) {
        _asrPassRuleCache = studyConfig.asrPassRule;
      }
      updateUI(() {
        // _isDarkMode = isDarkMode; // This line is now handled by the .then() block above
        // final studyConfig = StudyConfig.fromCurrentUser(); // Already defined above
        _autoJumpAfterCorrectCh2En = studyConfig.autoJumpAfterCorrectCh2En;
        _autoJumpAfterCorrectEn2Ch = studyConfig.autoJumpAfterCorrectEn2Ch;
      });

      // 获取用户的学习步骤配置（已激活的学习步骤)
      var stepsResult = await StudyBo().getActiveUserStudySteps();
      if (!stepsResult.success || stepsResult.data == null) {
        Global.logger.e(
            'loadData: 获取激活学习步骤失败: code=${stepsResult.code}, msg=${stepsResult.msg}');
        ToastUtil.error(stepsResult.msg ?? '获取学习步骤失败');
        return;
      }
      activeUserStudySteps = stepsResult.data!;

      Global.logger.d('开始加载单词数据...');
      await getNextWord(false);
      
      // 恢复持久化的上一个单词
      try {
        final lastWordDataStr = GetStorage().read<String>('last_word_history_item');
        if (lastWordDataStr != null) {
          final lastWordData = json.decode(lastWordDataStr);
          final wordResult = GetWordResult.fromJson(lastWordData['wordResult']);
          final stateJson = lastWordData['state'];
          final state = WordUIState(
            hasFinishedAnswering: stateJson['hasFinishedAnswering'] ?? false,
            canLeaveCurrWord: stateJson['canLeaveCurrWord'] ?? false,
            showSentenceTranslation: stateJson['showSentenceTranslation'] ?? false,
            selectedAnswerIndex: stateJson['selectedAnswerIndex'],
            flippedAnswerIndices: Set<int>.from(stateJson['flippedAnswerIndices'] ?? []),
            tabIndex: stateJson['tabIndex'] ?? 0,
            currentScore: stateJson['currentScore'],
            meaningText: stateJson['meaningText'] ?? '',
            correctAnswerIndex: stateJson['correctAnswerIndex'] ?? 0,
            fsrsItem: stateJson['fsrsItem'] != null ? FSRSItem(
              stability: (stateJson['fsrsItem']['stability'] as num).toDouble(),
              difficulty: (stateJson['fsrsItem']['difficulty'] as num).toDouble(),
              elapsedDays: stateJson['fsrsItem']['elapsedDays'] as int,
              scheduledDays: stateJson['fsrsItem']['scheduledDays'] as int,
              reps: stateJson['fsrsItem']['reps'] as int,
              lapses: stateJson['fsrsItem']['lapses'] as int,
              state: FsrsState.values[stateJson['fsrsItem']['state'] as int],
            ) : null,
            daysSinceLastReview: stateJson['daysSinceLastReview'],
            lastFsrsRating: stateJson['lastFsrsRating'] != null ? FsrsRating.values[stateJson['lastFsrsRating'] as int] : null,
            asrMatchedMeaningItemParts: stateJson['asrMatchedMeaningItemParts'] != null 
              ? (stateJson['asrMatchedMeaningItemParts'] as List).map((p) => Pair<int, int>((p as List)[0], (p)[1])).toList() 
              : null,
            asrRevealedMeaningItemParts: stateJson['asrRevealedMeaningItemParts'] != null 
              ? (stateJson['asrRevealedMeaningItemParts'] as List).map((p) => Pair<int, int>((p as List)[0], (p)[1])).toList() 
              : null,
            currentAsrCandidates: stateJson['currentAsrCandidates'] != null 
              ? List<String>.from(stateJson['currentAsrCandidates']) 
              : null,
            words: stateJson['wordsIndices'] != null ? (stateJson['wordsIndices'] as List).map((idx) {
              if (idx == 0) return wordResult.learningWord?.word;
              if (idx == 1 && wordResult.otherWords != null && wordResult.otherWords!.isNotEmpty) return wordResult.otherWords![0];
              if (idx == 2 && wordResult.otherWords != null && wordResult.otherWords!.length > 1) return wordResult.otherWords![1];
              if (idx == 3) {
                var mockWord = WordVo.c2("[ 都不对 ]");
                mockWord.setMeaningStr("[ 都不对 ]");
                return mockWord;
              }
              return null;
            }).whereType<WordVo>().toList() : null,
          );
          
          _history.add(wordResult);
          final wordId = wordResult.learningWord?.word.id;
          if (wordId != null) {
            _wordUIStates[wordId] = state;
          }
        }
      } catch (e, stackTrace) {
        Global.logger.e('恢复上一个单词的历史状态失败', error: e, stackTrace: stackTrace);
      }

      if (_currentGetWordResult == null) {
        Global.logger
            .e('loadData: _currentGetWordResult is null after getNextWord');
        ToastUtil.error('获取单词失败');
        return;
      }
      if (_currentGetWordResult!.finished || _currentGetWordResult!.noWord) {
        return;
      }
    } catch (e, stackTrace) {
      Global.logger.e('loadData: 发生未捕获异常', error: e, stackTrace: stackTrace);
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'loadData');
    } finally {
      Api.setLoadingDisabled(false);
    }
  }


  Future<void> playFirstSentence() async {
    if (_englishDigestOfFirstSentence != null && !_audioPlayerDisposed) {
      try {
        await SoundUtil.playSentenceSound2(
            _englishDigestOfFirstSentence!, _audioPlayer);
      } catch (e, stackTrace) {
        ErrorHandler.handleError(e, stackTrace,
            logPrefix: '播放例句失败', showToast: false);
      }
    }
  }


  void _showErrorWidget(String errorMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400]),
            const SizedBox(width: 8),
            const Text('出错了'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMessage),
              const SizedBox(height: 8),
              const Text(
                '您可以尝试重新加载或返回上一页。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('返回'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HealthCheckPage(autoStart: true),
                ),
              );
            },
            child: const Text('尝试修复'),
          ),
        ],
      ),
    );
  }


  Future<void> playWordAndFirstSentence(
      UserVo user, bool forcePlayWord, bool startAsrWhenFinish) async {
    // 等待所有提示音播放完成，避免与单词发音重叠
    // 使用列表快照，避免在等待过程中列表被修改
    final soundsToWait = List<Future<void>>.from(_playingCorrectSounds);
    if (soundsToWait.isNotEmpty) {
      await Future.wait(soundsToWait);
    }

    // 保存当前的 studyStep 和 word，用于在 finally 块中检查是否已经改变
    final savedStudyStep = _studyStep;
    final savedWordId = _word?.id;

    // 判断是否真的有音频要播，如果什么都不播（比如中英模式），需要给 finally 知道直接启动 ASR
    final studyConfig = StudyConfig.fromCurrentUser();
    bool willPlayWord = _studyStep == StudyStep.en2Ch.json &&
        (studyConfig.autoPlayWord || forcePlayWord);
    bool willPlaySentence =
        _studyStep == StudyStep.en2Ch.json && studyConfig.autoPlaySentence;

    // 如果不需要播放音频，为了保证流程顺畅且不受到 await ASR.stopAsr() 的延迟影响
    // 直接进入 finally 块的判断，快速拉起 ASR
    if (!willPlayWord && !willPlaySentence) {
      Global.logger.d('BDC: 由于无需播放音频，继续走到 finally 快速启动 ASR');
    } else {
      // 需要播放的话，确保停止 ASR 任务（Hot Stop）
      await asr.stopAsr();
    }

    try {
      // 在英→中模式下，播放单词发音
      if (willPlayWord) {
        await SoundUtil.playPronounceSound2(_word!, _audioPlayer);
      }
      // 在英→中模式下，播放例句发音
      if (willPlaySentence) {
        await playFirstSentence();
      }
    } finally {
      // 播音结束后，如果当前在"说"tab且键盘未弹出，则统一交给 _handleTabChangeForAsr 控制ASR启动
      // 注意：检查 studyStep 和 word 是否已经改变，如果改变了说明有新的单词加载，就不应该启动ASR
      if (!PlatformUtils.isWeb && _isInSpeakTab && !_isKeyboardVisible) {
        // 检查 studyStep 和 word 是否还是原来的值
        if (savedStudyStep == _studyStep && savedWordId == _word?.id) {
          Global.logger.d(
              'BDC: playWordAndFirstSentence 播放完成，准备启动ASR (studyStep=$_studyStep, wordId=${_word?.id})');
          _handleTabChangeForAsr();
        } else {
          Global.logger.d(
              'BDC: playWordAndFirstSentence 播放完成，但单词已改变，跳过ASR启动 (savedStudyStep=$savedStudyStep => studyStep=$_studyStep, savedWordId=$savedWordId => wordId=${_word?.id})');
        }
      } else {
        Global.logger.d(
            'BDC: playWordAndFirstSentence 播放完成，但跳过ASR启动 (isInSpeakTab=$_isInSpeakTab, isKeyboardVisible=$_isKeyboardVisible)');
      }
    }
  }


  void handleWord(final GetWordResult? getWordResult,
      {bool isFromBatchWordList = false}) async {
    final handleWordStartTime = DateTime.now();
    Global.logger.d('[BDC Performance] === handleWord 开始 ===');
    // 异步拉取最新 ASR 规则并缓存，避免后续同步处理挂起
    final config = StudyConfig.fromCurrentUser();
    _asrPassRuleCache = config.asrPassRule;

    // 进入新单词时禁用不认识/再学学按钮，500ms 延时后重新开启（防止闪电模式下点击再学学/不认识后按钮消失导致误触）
    _buttonsEnabled = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        updateUI(() {
          _buttonsEnabled = true;
        });
      }
    });

    updateUI(() {
      _fsrsItem = null;
      _lastFsrsRating = null;
    });

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
      }

      // 检查当前学习模式是否超出范围
      if (getWordResult.stepIndex >= activeUserStudySteps.length) {
        Global.logger.d('无效的学习模式: ${getWordResult.stepIndex}');
        ToastUtil.error('学习模式配置错误');
        return;
      }

      // 获取当前学习步骤
      final currentStep =
          activeUserStudySteps[getWordResult.stepIndex].studyStep;

      // 如果当前学习步骤是列表模式，显示单词列表
      if (currentStep == 'List') {
        var nextWordBtn = ElevatedButton(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () async {
            Get.back(result: true);
            // 给 UI 一个缓冲时间，确保列表页面完全关闭并清理 ASR 状态后再进入下一步
            await Future.delayed(const Duration(milliseconds: 100));
 
            // 完成当前批次列表学习
            await StudyBo().completeListStepForCurrentBatch();
            _args.fromPage = 'batch_word_list';
            await GetStorage().write("BdcPageArgs", _args.toJson());
            await getNextWord(false);
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0,
                child: Icon(Icons.navigate_next, size: 24.0),
              ),
              Expanded(
                child: Text(
                  '继续',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Icon(Icons.navigate_next, size: 24.0),
            ],
          ),
        );
        // 在获取下一个单词前，停止 ASR 任务（Hot Stop）
        await asr.stopAsr();
        await asr.reset();
        if (!mounted) return;
        final wasMounted = mounted;
        if (!wasMounted) return;
        toBatchWordsListPage('单词列表', true, nextWordBtn, context)
            ?.then((result) async {
          if (!mounted) return;
          if (result == null) {
            Navigator.pop(context);
          }
        });
        return;
      }

      _isWordMastered = false;

      String? oldStudyStep = _studyStep;
      _studyStep = activeUserStudySteps[getWordResult.stepIndex].studyStep;

      // 极端防御：如果在渲染新单词时 ASR 状态依然是 started（通常是异步时序导致），强制同步一次状态
      // 确保 _handleTabChangeForAsr 能够触发新的 _startAsr() 而不是认为已经启动
      if (asr.state == AsrState.started) {
        Global.logger.w('BDC: 检测到 ASR 残留状态，准备通过 stopAsr 确保下一环节能正常启动');
        await asr.stopAsr();
      }

      // 只有在模式真正改变时，才重新初始化 ASR（防止在相同模式下刷新导致 ASR 意外停止）
      // 注意：getNextWord 已经执行过 stopAsr + reset，此处无需重复，否则会触发额外的
      // iOS Audio Engine tear-down，产生听感噪音。
      if (oldStudyStep == null ||
          oldStudyStep != _studyStep ||
          isFromBatchWordList) {
        Global.logger.i(
            'BDC: 学习模式改变或从列表返回 (oldStudyStep: $oldStudyStep, currentStep: $_studyStep, fromBatchList: $isFromBatchWordList)，初始化 ASR 监听');
        await asr.initAsr(onAsrResult);

        // 临时禁用侵入式的 microphone pre-warm，因为它会与后续即时的 startAsr 产生竞争并打断音频流程
        // if (_shouldShowSpeakTab) {
        //   unawaited(asr.startMicrophone());
        // }
      }


      if (_word?.id != getWordResult.learningWord!.word.id) {
        _lowestRatingForCurrentWord = null;
      }

      if (getWordResult.learningWord?.word == null) {
        Global.logger.e(
            '处理单词失败：获取到的单词数据中 learningWord.word 为空。 stepIndex=${getWordResult.stepIndex}, finished=${getWordResult.finished}');
        ToastUtil.error('单词数据加载错误');
        return;
      }
      _word = getWordResult.learningWord!.word;
      _canLeaveCurrWord = false;
      _hasFinishedAnswering = false;
      _selectedAnswerIndex = null;
      _flippedAnswerIndices.clear();
      _showSentenceTranslation = false;
      _isUpdatingByHint = false;
      _currentScore = null; // 重置发音评分，防止携带上一个单词的分数

      if (_historyIndex != -1) {
        _restoreWordState(getWordResult);
      } else {
        _meaningController.text = "";
      }

      // 重新初始化TabController以适应动态tabs，此时已恢复了之前的 _currentTabIndex
      _reinitializeTabController(preserveCurrentIndex: true);

      // 如果仅返回了ID，则本地补全单词详情与释义
      if (_word != null && (_word!.spell.isEmpty)) {
        final dbStartTime = DateTime.now();
        try {
          final db = MyDatabase.instance;
          final local = await db.wordsDao.getWordById(_word!.id!);
          if (local != null) {
            _word!
              ..spell = local.spell
              ..shortDesc = local.shortDesc
              ..longDesc = local.longDesc
              ..pronounce = local.pronounce
              ..americaPronounce = local.americaPronounce
              ..britishPronounce = local.britishPronounce
              ..popularity = local.popularity;
          }
          final user = Global.getLoggedInUser();
          if (user != null) {
            final mis =
                await WordBo().getMeaningItemsForWord(_word!.id!, user.id);
            _word!.meaningItems = mis;

            // 本地加载单词配图，填充到 currentGetWordResult.images
            try {
              final imgsQuery = db.select(db.wordImages)
                ..where((tbl) =>
                    tbl.wordId.equals(_word!.id!) &
                    (tbl.status.equals('APPROVED') |
                        tbl.status.isNull() |
                        (tbl.status.equals('PENDING') &
                            tbl.authorId.equals(user.id))));
              final imgs = await imgsQuery.get();
              final imageVos = <WordImageVo>[];
              for (final img in imgs) {
                final author = await db.usersDao.getUserById(img.authorId);
                // WordImageVo 需要非空作者，这里用占位作者避免空指针
                UserVo authorVo = UserVo.c2(author?.id ?? '0')
                  ..nickName = (author?.nickName ?? '');
                imageVos.add(WordImageVo(
                  img.id,
                  img.imageFile,
                  img.hand,
                  img.foot,
                  authorVo,
                ));
              }
              _currentGetWordResult?.images = imageVos;
              _word!.images = imageVos;
            } catch (e) {
              Global.logger.w('本地加载单词图片失败', error: e);
            }
          }
        } catch (e) {
          Global.logger.w('本地补全单词失败', error: e);
        }
        Global.logger.d('[BDC Performance] 本地数据库补全单词详情耗时: ${DateTime.now().difference(dbStartTime).inMilliseconds} ms');
      }
      _wordWrapper = WordWrapper(_word!, null);

      final state = _word?.id != null ? _wordUIStates[_word!.id!] : null;
      if (state != null) {
        if (state.asrMatchedMeaningItemParts != null) {
          _wordWrapper!.asrMatchedMeaningItemParts.addAll(state.asrMatchedMeaningItemParts!);
        }
        if (state.asrRevealedMeaningItemParts != null) {
          _wordWrapper!.asrRevealedMeaningItemParts.addAll(state.asrRevealedMeaningItemParts!);
        }
      }

      // 渲染第一个例句
      final sentenceStartTime = DateTime.now();
      _englishDigestOfFirstSentence = null; // 先设置为 null
      final allSentences = await _word!.getSentences();
      if (allSentences.isNotEmpty) {
        _englishDigestOfFirstSentence = allSentences[0].englishDigest;
      }
      Global.logger.d('[BDC Performance] 获取例句耗时: ${DateTime.now().difference(sentenceStartTime).inMilliseconds} ms');

      var user = Global.getLoggedInUserNotNull();

      final playStartTime = DateTime.now();
      if (_studyStep == StudyStep.en2Ch.json) {
        playWordAndFirstSentence(await user.toUserVo(), false, false);
      } else if (_studyStep == StudyStep.ch2En.json) {
        playWordAndFirstSentence(await user.toUserVo(), true, false);
      }
      Global.logger.d('[BDC Performance] 播放音频(异步/开始)耗时: ${DateTime.now().difference(playStartTime).inMilliseconds} ms');

      bool needInitChoice = true;
      if (_historyIndex != -1 && _word?.id != null && _wordUIStates.containsKey(_word!.id!)) {
        final state = _wordUIStates[_word!.id!];
        if (state != null && state.words != null && state.words!.isNotEmpty) {
          needInitChoice = false;
        }
      }

      if (needInitChoice) {
        _initChoiceData(getWordResult, user);
      }


      if (_word?.id != null) {
        _learningHistoryFuture = MyDatabase.instance.learningLogsDao
            .getHistory(Global.getLoggedInUserNotNull().id, _word!.id!);
        if (_currentGetWordResult != null && _currentGetWordResult!.stepIndex > 0) {
          final logs = await MyDatabase.instance.learningLogsDao
              .getHistory(Global.getLoggedInUserNotNull().id, _word!.id!);
          if (logs.isNotEmpty) {
            _assessmentRating = FsrsRatingExt.fromInt(logs.first.rating);
          } else {
            _assessmentRating = null;
          }
        } else {
          _assessmentRating = null;
        }
      } else {
        _learningHistoryFuture = null;
        _assessmentRating = null;
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '处理单词');
      ToastUtil.error('处理单词时出错');
      // 异常时也要设置 dataLoaded，避免白屏
      if (mounted) {
        updateUI(() {
          dataLoaded = true;
        });
        // 显示错误提示，让用户可以选择重试或返回
        _showErrorWidget('处理单词时出错: ${e.toString()}');
      }
      return;
    }

    _showAnswerButtons = StudyConfig.fromCurrentUser().showAnswersDirectly;

    updateUI(() {
      dataLoaded = true;
      // 只有在不在"说"tab时才直接启动计时（"说"tab会等 ASR 准备好以后再启动计时）
      if (!_isInSpeakTab) {
        _wordStartTime = AppClock.now();
      }
    });

    // 自动获取焦点，提升输入效率 (仅在用户偏好键盘模式时自动触发)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasFinishedAnswering) {
        final preferKeyboard = StudyConfig.fromCurrentUser().preferKeyboardInSpelling;
        Global.logger.d('BDC: handleWord postFrameCallback, preferKeyboard=$preferKeyboard');
        if (preferKeyboard) {
          _meaningFocusNode.requestFocus();
        }
      }
    });

    // 如果在数据加载期间（如等待数据库查询）已经有语音结果提前到达，手动触发一次校验
    if (_meaningController.text.isNotEmpty && _handlingChinese.isEmpty) {
      Global.logger.i('BDC: 单词加载完成，发现加载期间缓存的语音结果，主动触发校验');
      checkAsrResult();
    }
    Global.logger.d('[BDC Performance] === handleWord 结束，总耗时: ${DateTime.now().difference(handleWordStartTime).inMilliseconds} ms ===');
  }


  void _initChoiceData(GetWordResult getWordResult, User user) {
    try {
      if (_studyStep == StudyStep.en2Ch.json ||
          _studyStep == StudyStep.ch2En.json) {
        // 把当前单词及混淆单词放入数组，并随机打乱
        if (getWordResult.otherWords == null ||
            getWordResult.otherWords!.length < 2) {
          final actualLength = getWordResult.otherWords?.length ?? 0;
          Global.logger.e('混淆单词数量（$actualLength）不足');
          ToastUtil.error('混淆单词数量（$actualLength）不足，请稍后重试');
          return;
        }

        _words = <WordVo>[];
        _words!.add(_word!);
        _words!.add(getWordResult.otherWords![0]);
        _words!.add(getWordResult.otherWords![1]);
        _words!.shuffle();

        // 在打乱的单词数组中找到正确的（当前学习的）
        for (var i = 0; i < _words!.length; i++) {
          if (_words![i] == _word) {
            _correctAnswerIndex = i + 1;
            break;
          }
        }

        if (StudyConfig.fromCurrentUser().enableAllWrong) {
          // 备选答案中含[都不对]
          // 随机选择一个单词索引号（1～3），从数组中删除该单词
          var rnd = Random();
          var indexToDelete = 1 + rnd.nextInt(3);
          _words!.removeAt(indexToDelete - 1);

          // 添加[都不对]选项
          var mockWord = WordVo.c2("[ 都不对 ]");
          mockWord.setMeaningStr("[ 都不对 ]");
          _words!.add(mockWord);

          if (indexToDelete == _correctAnswerIndex) {
            // 恰好删除了正确的单词，此时[都不对]应成为正确答案
            _correctAnswerIndex = 3;
          } else {
            // 在调整过的单词数组中重新找到正确的（当前学习的）
            for (var i = 0; i < _words!.length; i++) {
              if (_words![i] == _word) {
                _correctAnswerIndex = i + 1;
                break;
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      Global.logger.e('初始化选择题数据时发生异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('初始化选择题失败，请稍后重试');
    }
  }


  SizedBox spellExerciseTextField(String wordSpell) {
    TextStyle textStyle =
        const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    double width = Util.getTextWidth(wordSpell, textStyle);
    return SizedBox(
      width: width * 1.3,
      height: 26,
      child: TextField(
        textAlign: TextAlign.center,
        controller: _wordWrapper!.spellController,
        focusNode: _wordWrapper!.focusNode,
        autofocus: true,
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
          if (Util.equalsIgnoreCase(_word!.spell, value)) {
            SoundUtil.playPronounceSound(_word!);
            Util.closeIme();
          }
          updateUI(() {});
        },
        style: textStyle,
      ),
    );
  }


  Future<bool> wordImageHasBeenVoted(var wordImage) async {
    return (await MyDatabase.instance.votedWordImagesDao.getVotedWordImageById(
            Global.getLoggedInUser()!.id, wordImage.id)) !=
        null;
  }


  void giveALittleHint(WordWrapper word) {
    updateUI(() {
      _hintTapCount++;
      word.hintLetterCount++;
      // 中英模式 或 正在进行拼写练习：提供英文拼写提示
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        final spell = word.word.spell;
        if (word.hintLetterCount > spell.length) {
          word.hintLetterCount = spell.length;
        }
        _isUpdatingByHint = true;
        _meaningController.text = spell.substring(0, word.hintLetterCount);
      }
    });
  }


  void giveFullHint(WordWrapper word) {
    updateUI(() {
      _hintTapCount = 2; // 长按直接视为严重提示
      word.hintLetterCount = word.word.spell.length;
      // 中英模式 或 正在进行拼写练习：拼写提示
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        _isUpdatingByHint = true;
        _meaningController.text = word.word.spell;
      }
    });
  }


  void clearHint(WordWrapper word) {
    updateUI(() {
      word.hintLetterCount = 0;
      if (_studyStep == StudyStep.ch2En.json || _showHandwritingBoard) {
        _isUpdatingByHint = true;
        _meaningController.text = '';
      }
    });
  }


  Future<void> _playWithAnimation(
      Future<void> Function() playSound, String audioType) async {
    updateUI(() {
      _playingStates[audioType] = true;
    });

    final controller =
        audioType == 'word' ? _wordSoundController : _sentenceSoundController;
    controller.repeat();

    // 播音开始前停止 ASR 任务（Hot Stop），消除硬件切换产生的杂音
    await asr.stopAsr();

    try {
      await playSound();
    } finally {
      if (mounted) {
        updateUI(() {
          _playingStates[audioType] = false;
        });
        controller.stop();
        controller.reset();

        // 播音结束后，如果当前在"说"tab且键盘未弹出，则统一交给 _handleTabChangeForAsr 控制ASR启动
        if (_isInSpeakTab && !_isKeyboardVisible) {
          Global.logger.d('BDC: 播音结束，准备根据当前状态决定是否启动ASR ($audioType)');
          _handleTabChangeForAsr();
        }
      }
    }
  }


  Widget buildWordSoundButton(WordVo word, AudioPlayer audioPlayer) {
    // 在拼写和音标显示的情况下使用小按钮
    if (_studyStep == StudyStep.en2Ch.json) {
      return Transform.translate(
          offset: Offset(6.0, 1.0),
          child: InkWell(
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _wordSoundController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_wordSoundController.value < 0.5 ? 0 : -2,
                          0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
                      child: Icon(
                        _playingStates['word']!
                            ? (_wordSoundController.value < 0.5
                                ? Icons.volume_up
                                : Icons.volume_down)
                            : Icons.volume_up,
                        color: _playingStates['word']!
                            ? Colors.teal[300]
                            : Colors.grey[500],
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              if (!_playingStates['word']!) {
                _playWithAnimation(
                    () => SoundUtil.playPronounceSound2(word, audioPlayer),
                    'word');
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
        color: _playingStates['word']!
            ? const Color(0xFF1A1A1A)
            : Colors.grey[200],
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
              _playWithAnimation(
                  () => SoundUtil.playPronounceSound2(word, audioPlayer),
                  'word');
            }
          },
          child: Center(
            child: AnimatedBuilder(
              animation: _wordSoundController,
              builder: (context, child) {
                return Icon(
                  _playingStates['word']!
                      ? (_wordSoundController.value < 0.5
                          ? Icons.volume_up
                          : Icons.volume_down)
                      : Icons.volume_up,
                  color:
                      _playingStates['word']! ? Colors.white : Colors.grey[600],
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
        color: context.watch<DarkMode>().isDarkMode
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFF0F0F0).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        child: AnimatedBuilder(
          animation: _sentenceSoundController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2,
                  0), // 位移, 因为一个波纹的图标较小，所以需要通过位移，消除轮播的左右晃动
              child: Icon(
                _playingStates['sentence']!
                    ? (_sentenceSoundController.value < 0.5
                        ? Icons.volume_up
                        : Icons.volume_down)
                    : Icons.volume_up,
                color: _playingStates['sentence']!
                    ? Colors.teal[300]
                    : Colors.grey[500],
                size: 18,
              ),
            );
          },
        ),
        onTap: () {
          if (!_playingStates['sentence']! &&
              _englishDigestOfFirstSentence != null) {
            _playWithAnimation(
                () => SoundUtil.playSentenceSound2(
                    _englishDigestOfFirstSentence!, _audioPlayer),
                'sentence');
          }
        },
      ),
    );
  }


  void _updateFsrsRating(FsrsRating newRating) {
    updateUI(() {
      _lastFsrsRating = newRating;

      // 重新计算 FSRS 预览结果
      final lw = _currentGetWordResult?.learningWord;
      if (lw != null) {
        final fsrs = FSRS();
        _daysSinceLastReview = 0;
        if (lw.lastLearningDate != null) {
          final lastDate = DateTime(lw.lastLearningDate!.year,
              lw.lastLearningDate!.month, lw.lastLearningDate!.day);
          final now = AppClock.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          _daysSinceLastReview = todayDate.difference(lastDate).inDays;
        }
        if (lw.stability == null || lw.stability == 0.0) {
          _fsrsItem = fsrs.init(newRating);
        } else {
          final prevItem = FSRSItem(
            stability: lw.stability!,
            difficulty: lw.difficulty!,
            elapsedDays: _daysSinceLastReview ?? 0,
            scheduledDays: lw.scheduledDays ?? 0,
            reps: lw.reps ?? 0,
            lapses: lw.lapses ?? 0,
            state: FsrsStateExt.fromInt(lw.state),
          );
          _fsrsItem = fsrs.next(prevItem, newRating, _daysSinceLastReview ?? 0);
        }
      }
    });
  }


  void _showLearningHistoryDialog() async {
    final wordId = _wordWrapper?.word.id;
    if (wordId == null) return;

    final history = await MyDatabase.instance.learningLogsDao
        .getHistory(Global.getLoggedInUser()!.id, wordId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final isDarkMode = context.watch<DarkMode>().isDarkMode;
        final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDarkMode ? Colors.white70 : Colors.black87;

        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('记忆历史',
              style: TextStyle(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          content: history.isEmpty
              ? Text('暂无记忆历史',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6)))
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final log = history[index];
                      final rating = FsrsRatingExt.fromInt(log.rating);
                      final timeStr =
                          '${log.createTime.year}-${log.createTime.month.toString().padLeft(2, '0')}-${log.createTime.day.toString().padLeft(2, '0')} ${log.createTime.hour.toString().padLeft(2, '0')}:${log.createTime.minute.toString().padLeft(2, '0')}';

                      Color ratingColor;
                      switch (rating) {
                        case FsrsRating.again:
                          ratingColor = Colors.redAccent;
                          break;
                        case FsrsRating.hard:
                          ratingColor = Colors.orangeAccent;
                          break;
                        case FsrsRating.good:
                          ratingColor = AppTheme.primaryColor;
                          break;
                        case FsrsRating.easy:
                          ratingColor = Colors.greenAccent;
                          break;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ratingColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: ratingColor.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                rating.label,
                                style: TextStyle(
                                    color: ratingColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                            text: '下次复习: ',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        TextSpan(
                                          text: '${log.scheduledDays}',
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                            text: '天后',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: textColor.withValues(alpha: 0.3)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      },
    );
  }


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


  void _showDebugOverlay() async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    // 获取今日所有学习单词及其状态
    final words = await LearningService.getTodayLearningWordsFromDb(user.id);
    final activeSteps = activeUserStudySteps;

    // 获取用户已掌握的单词 ID 集，用于准确反映调度状态
    final masteredWords = await MyDatabase.instance.masteredWordsDao
        .getMasteredWordsForUser(user.id);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toSet();

    // 助手函数：判断单词是否已掌握 (调度层的一致性逻辑)
    bool isEffectivelyMastered(dynamic word) {
      if (masteredWordIds.contains(word.wordId)) {
        return true;
      }
      if (word.stability != null &&
          (word.stability ?? 0.0) >= Constants.graduationStability) {
        return true;
      }
      return false;
    }

    // 获取单词的拼写
    final Map<String, String> spellings = {};
    for (var w in words) {
      if (!spellings.containsKey(w.wordId)) {
        final wordData =
            await MyDatabase.instance.wordsDao.getWordById(w.wordId);
        spellings[w.wordId] = wordData?.spell ?? w.wordId;
      }
    }

    if (!mounted) return;

    // 分批次并按照学习序号排序
    words.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (a.batchId ?? 0).compareTo(b.batchId ?? 0);
      }
      return a.learningOrder.compareTo(b.learningOrder);
    });

    // 分组：底层调度系统固定是 10 个词为一个学习循环（也就是一个 Batch）
    const int batchSize = 10;
    final Map<int, List<dynamic>> batches = {};
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      // 计算其实际属于第几个调度轮次 (从 1 开始)
      final chunkId = (i ~/ batchSize) + 1;
      batches.putIfAbsent(chunkId, () => []).add(w);
    }

    // 计算即将到来的待办单元格 sequence
    List<Map<String, dynamic>> pendingCells = [];
    for (var batchId in batches.keys) {
      final batchWords = batches[batchId]!;
      for (int sIndex = 0; sIndex < activeSteps.length; sIndex++) {
        for (var w in batchWords) {
          if (w.todayLearnedTimes == sIndex) {
            pendingCells.add({'wordId': w.wordId, 'sIndex': sIndex});
          }
        }
      }
    }

    String? nextWordId;
    int? nextStepIndex;
    String? currentWordId = _currentGetWordResult?.learningWord?.word.id;

    if (pendingCells.isNotEmpty) {
      int currentIndex = -1;
      if (currentWordId != null) {
        currentIndex =
            pendingCells.indexWhere((cell) => cell['wordId'] == currentWordId);
      }

      if (currentIndex != -1 && currentIndex + 1 < pendingCells.length) {
        nextWordId = pendingCells[currentIndex + 1]['wordId'];
        nextStepIndex = pendingCells[currentIndex + 1]['sIndex'];
      } else if (currentIndex == -1) {
        nextWordId = pendingCells[0]['wordId'];
        nextStepIndex = pendingCells[0]['sIndex'];
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Debug",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final bool isDark = context.watch<DarkMode>().isDarkMode;
        final Color textColor = isDark ? Colors.white : Colors.black87;
        final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

        Widget buildLegendItem(bool done, bool mastered, String label) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green
                      : (isDark
                          ? Colors.white24
                          : Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: mastered
                      ? BorderRadius.circular(2)
                      : BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: subTextColor)),
            ],
          );
        }

        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 5 * anim1.value, sigmaY: 5 * anim1.value),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
              child: AlertDialog(
                backgroundColor: isDark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.9),
                elevation: 24,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.analytics_outlined,
                              color: Colors.blueAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日取词流水线',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '实时调度状态可视化',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: subTextColor,
                                  fontWeight: FontWeight.normal),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        buildLegendItem(true, false, '学过'),
                        buildLegendItem(false, false, '未学'),
                        buildLegendItem(true, true, '已掌握'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.blueAccent, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('当前',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('下一个',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 0.5),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                content: SizedBox(
                  width: 400,
                  height: 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: words.isEmpty
                        ? Center(
                            child: Text(
                              '今日还没有学习单词',
                              style: TextStyle(color: subTextColor),
                            ),
                          )
                        : ListView.builder(
                            itemCount: batches.keys.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (ctx, index) {
                              // 确保批次 ID 按顺序排列
                              final sortedBatchIds = batches.keys.toList()
                                ..sort();
                              int batchId = sortedBatchIds[index];
                              final batchWords = batches[batchId]!;

                              // 判断是否为当前批次
                              final bool isCurrentBatch = batchWords
                                  .any((w) => w.wordId == currentWordId);

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrentBatch
                                        ? Colors.blueAccent
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                    width: isCurrentBatch ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Batch $batchId',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: textColor),
                                    ),
                                    const SizedBox(height: 12),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Word Headers
                                          Row(
                                            children: [
                                              const SizedBox(
                                                  width:
                                                      60), // Space for step names
                                              ...batchWords.map((w) {
                                                final isCurrentWord =
                                                    _currentGetWordResult
                                                            ?.learningWord
                                                            ?.word
                                                            .id ==
                                                        w.wordId;
                                                return Tooltip(
                                                  message:
                                                      spellings[w.wordId] ??
                                                          w.wordId,
                                                  child: Container(
                                                    width: 30,
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    height:
                                                        70, // Room for rotated text
                                                    child: RotatedBox(
                                                      quarterTurns:
                                                          3, // text going up
                                                      child: Text(
                                                        spellings[w.wordId] ??
                                                            w.wordId,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isCurrentWord
                                                              ? Colors
                                                                  .blueAccent
                                                              : textColor,
                                                          fontWeight:
                                                              isCurrentWord
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                              const SizedBox(
                                                  width:
                                                      16), // Padding right for scrolling
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          // Data Rows (Steps)
                                          ...List.generate(activeSteps.length,
                                              (sIndex) {
                                            final stepInfo =
                                                activeSteps[sIndex];
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: [
                                                  SizedBox(
                                                    width: 60,
                                                    child: Text(
                                                      '${sIndex + 1}: ${stepInfo.studyStep}',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: subTextColor),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  ...batchWords.map((w) {
                                                    // Is the user learning this exact word in this exact step right now?
                                                    final isCurrentStep =
                                                        _currentGetWordResult
                                                                    ?.learningWord
                                                                    ?.word
                                                                    .id ==
                                                                w.wordId &&
                                                            w.todayLearnedTimes ==
                                                                sIndex;
                                                    final isNextStep =
                                                        nextWordId ==
                                                                w.wordId &&
                                                            nextStepIndex ==
                                                                sIndex;
                                                    // 已掌握的唯一标准：稳定度大于等于毕业阈值，或者在已掌握表中
                                                    final isWordFinished =
                                                        isEffectivelyMastered(
                                                            w);

                                                    // 从用户视角看：如果我处于这个环节，或者处于之后的环节，或者单词已掌握，则该格显绿
                                                    final isStepCompleted =
                                                        isWordFinished ||
                                                            w.todayLearnedTimes >
                                                                sIndex ||
                                                            isCurrentStep;

                                                    return Container(
                                                      width: 30,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Container(
                                                        width: 14,
                                                        height: 14,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isStepCompleted
                                                              ? Colors.green
                                                              : (isDark
                                                                  ? Colors
                                                                      .white24
                                                                  : Colors.grey
                                                                      .withValues(
                                                                          alpha:
                                                                              0.3)),
                                                          borderRadius:
                                                              isWordFinished
                                                                  ? BorderRadius
                                                                      .circular(
                                                                          3)
                                                                  : BorderRadius
                                                                      .circular(
                                                                          7), // 矩形(圆角3)/圆形(圆角7)
                                                          border: isCurrentStep
                                                              ? Border.all(
                                                                  color: Colors
                                                                      .blueAccent,
                                                                  width: 2)
                                                              : (isNextStep
                                                                  ? Border.all(
                                                                      color: Colors
                                                                          .orange,
                                                                      width: 2)
                                                                  : null),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                  const SizedBox(
                                                      width:
                                                          16), // Padding right for scrolling
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                actions: [
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('我知道了',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


}
