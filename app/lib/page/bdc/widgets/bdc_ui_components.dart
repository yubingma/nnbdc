part of '../bdc.dart';

extension BdcPageStateUIComponents on BdcPageState {
  // 终极性能优化：UI组件库在读取全局 state 时屏蔽所有高频字段，防止题目区闪烁，并在回调中安全读取
  BdcState get state => _activeState ?? ref.read(bdcNotifierProvider);
  BdcNotifier get notifier => ref.read(bdcNotifierProvider.notifier);

  Widget _buildLoadingPage() {
    final isDarkMode = _cachedIsDarkMode;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
              : [Colors.white, const Color(0xFFF8F9FA)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(context.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              "正在准备学习内容...",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (isDarkMode ? Colors.white : Colors.black)
                    .withValues(alpha: 0.3),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenImmersiveInputMode() {
    final isDarkMode = _cachedIsDarkMode;

    // 「键盘 vs 手写」的接管判据（「提交」「回退」共用）：
    // 只有键盘没在用、且画布上有笔迹时，才把手势交给手写板处理；否则都作用于输入框文本。
    // 不能只看键盘焦点——点一下画布就会让输入框失焦，只看焦点会让键盘已打好的内容被判空/被覆盖。
    // 用闭包而非局部变量：焦点与笔迹在 build 之后仍会变化，必须在点击当刻读取。
    bool handwritingTakesOver() =>
        !_meaningFocusNode.hasFocus &&
        (_handwritingBoardKey.currentState?.hasInk ?? false);

    // 获取合并后的所有释义项
    final meaningItems = state.word?.getMergedMeaningItems() ?? [];
    final combinedMeaning = meaningItems
        .map((m) => "${m.ciXing ?? ''} ${m.meaning ?? ''}")
        .join("; ");

    return Container(
      color: isDarkMode ? const Color(0xFF121212) : Colors.white,
      child: Column(
        children: [
          // 1. 顶部手写与释义区 (使用 Stack 实现手写板全屏覆盖且释义浮动)
          Expanded(
            child: Stack(
              children: [
                // 底层：手写板 (去除边框和内部标题，最大化感应面积)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: state.isSpellingSuccess,
                    child: HandwritingBoard(
                      key: _handwritingBoardKey,
                      showCloseButton: false,
                      showHeader: false, // 隐藏内部自带的标题栏
                      useBoxDecoration: false, // 隐藏内部背景和圆角，直接使用外层背景
                      // 中文默写（英译汉）时识别中文汉字；否则识别英文拼写
                      // ML Kit 数字墨迹识别的中文标签是 "zh-Hani"（Han 手写体），不是 BCP-47 的 "zh-Hans"，
                      // 传错会导致 native 侧 DigitalInkRecognitionModelIdentifier(forLanguageTag:) 返回 nil。
                      language: state.isChineseDictation ? 'zh-Hani' : 'en-US',
                      // 中文默写采用手动提交：停笔不自动判题，仅点击「提交」后才识别+匹配，规避过早识别
                      manualSubmit: state.isChineseDictation,
                      // 中文默写分 2 格书写，一格一个字（竖屏上下两格、横屏左右两格）；
                      // 新一笔起点换格即识别上一格，显著提升单字识别率
                      cellCount: state.isChineseDictation ? 2 : 1,
                      onStartWriting: () {
                        // 一旦用户开始手写，立即收起键盘
                        if (_meaningFocusNode.hasFocus) {
                          _meaningFocusNode.unfocus();
                          // 同时记录偏好：既然开始了手写，下次默认就不弹出键盘了
                          final config = StudyConfig.fromCurrentUser();
                          if (config.preferKeyboardInSpelling) {
                            config.preferKeyboardInSpelling = false;
                            config.saveToCurrentUser();
                          }
                        }
                      },
                      onRecognized: (text) async {
                        notifier.updateIsUpdatingByHint(false);

                        // 记录用户偏好：使用手写输入
                        final config = StudyConfig.fromCurrentUser();
                        if (config.preferKeyboardInSpelling) {
                          config.preferKeyboardInSpelling = false;
                          config.saveToCurrentUser();
                        }

                        // 设置文本时抑制自动判题监听；判题显式在下面调用（避免 150ms 防抖重复判题）
                        notifier.updateMeaningTextWithoutCheck(text);
                        await notifier.checkAsrResult(
                            asrInput: text, isVoice: false);
                      },
                      // 分格模式提前回显：每识别完一格就把"已识别前缀"同步到输入框供用户反馈，不判题
                      onRecognizedPreview: (text) {
                        notifier.updateMeaningTextWithoutCheck(text);
                      },
                      // 点「提交」：键盘在用或画布没有笔迹 → 直接判输入框文本；否则交回手写板识别判题。
                      onSubmit: () {
                        if (handwritingTakesOver()) return false;
                        notifier.checkAsrResult();
                        return true;
                      },
                      // 手写识别失败/超时：与"答案不对"区分开提示，避免用户把识别失败
                      // 误当成自己写错（历史问题：超时返回空串被当成"答案不正确或未写完整"）
                      onRecognizeFailed: () {
                        ToastUtil.error('手写识别失败，请重写');
                      },
                      // 落笔接管的当刻读取输入框文本，作为本次手写答案的前缀（"打字→手写"不丢键盘内容）
                      onReadCurrentText: () => notifier.meaningController.text,
                      // 点「回退」：键盘在用或画布没有笔迹 → 删除输入框最后一个字符；
                      // 否则交回手写板（清当前格 / 删已定稿的最后一个字）。
                      onUndoRequest: () {
                        if (handwritingTakesOver()) return false;
                        final text = notifier.meaningController.text;
                        if (text.isNotEmpty) {
                          notifier.updateMeaningTextWithoutCheck(
                              text.substring(0, text.length - 1));
                        }
                        // 键盘已接管输入框：同步清掉手写板状态，避免下次落笔时把被删掉的内容又带回来
                        _handwritingBoardKey.currentState?.clearHandwritingPreview();
                        return true;
                      },
                      onCancel: () {
                        _meaningFocusNode.unfocus();
                        // 中文默写用 closeChineseDictation 一并重置中文默写标记
                        if (state.isChineseDictation) {
                          notifier.closeChineseDictation();
                        } else {
                          updateUI(() {
                            notifier.updateShowHandwritingBoard(false);
                          }, tag: 'hw-cancel');
                          notifier.handleTabChangeForAsr();
                        }
                      },
                    ),
                  ),
                ),

                // 顶层：浮动释义头部（整层 IgnorePointer，确保顶部起笔也能正常书写；
                // 关闭按钮单独放在上层，保持可点击）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                          16, MediaQuery.of(context).padding.top + 4, 48, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (isDarkMode ? const Color(0xFF121212) : Colors.white)
                                .withValues(alpha: 0.16),
                            (isDarkMode ? const Color(0xFF121212) : Colors.white)
                                .withValues(alpha: 0.0),
                          ],
                          stops: const [0.35, 1.0],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.isChineseDictation
                                ? '请写出中文释义：'
                                : '请拼写单词：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              color: context.textSecondary.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 3),
                          // 中文默写（英译汉）时，顶部展示英文原词作为题目，而非中文释义，否则会直接泄题
                          Text(
                            state.isChineseDictation
                                ? (state.word?.spell ?? combinedMeaning)
                                : combinedMeaning,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 关闭按钮（独立于顶部提示层，保持可点击）
                Positioned(
                  top: MediaQuery.of(context).padding.top,
                  right: 4,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 22,
                      color: context.textSecondary,
                    ),
                    onPressed: () {
                      _meaningFocusNode.unfocus();
                      // 中文默写关闭时一并重置中文默写标记
                      if (state.isChineseDictation) {
                        notifier.closeChineseDictation();
                      } else {
                        updateUI(() {
                          notifier.updateShowHandwritingBoard(false);
                        }, tag: 'hw-close');
                        notifier.handleTabChangeForAsr();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // 2. 底部输入与提示区
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, MediaQuery.of(context).padding.bottom + 18),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xB8161E2A) : context.cardBg,
              boxShadow: [context.cardShadow],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: notifier.meaningController,
                        focusNode: _meaningFocusNode,
                        autofocus: StudyConfig.fromCurrentUser()
                            .preferKeyboardInSpelling,
                        // 中文默写：要用键盘输入汉字，需用 text 键盘以调出中文输入法（拼音候选）；
                        // 英文拼写：用 visiblePassword 键盘避免自动纠错/候选污染拼写。
                        keyboardType: state.isChineseDictation
                            ? TextInputType.text
                            : TextInputType.visiblePassword,
                        autocorrect: false,
                        // 中文默写允许输入法候选（拼音→汉字），英文拼写关闭候选
                        enableSuggestions: state.isChineseDictation,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: state.isSpellingSuccess
                              ? const Color(0xFF10B981)
                              : context.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: state.isChineseDictation
                              ? '在此键入中文释义...'
                              : '在此键入单词...',
                          hintStyle: TextStyle(
                            fontSize: 30,
                            color: context.textMuted.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (value) {
                          // 用户用键盘手动编辑输入框：清掉手写板的提前回显预览，
                          // 避免删改后又被手写预览回填（键盘输入以输入框为准）。
                          _handwritingBoardKey.currentState
                              ?.clearHandwritingPreview();
                          notifier.updateIsUpdatingByHint(false);
                          if (value.isNotEmpty && state.word?.spell != null) {
                            if (Util.equalsIgnoreCase(
                                value, state.word!.spell)) {
                              // 提示已经显示了全部字母时不应自动提交，用户应继续手动答题
                              final allRevealedByHint =
                                  (state.wordWrapper?.hintLetterCount ?? 0) >=
                                      state.word!.spell.length;
                              if (!allRevealedByHint) {
                                notifier.checkAsrResult();
                              }
                            }
                          }
                        },
                        onSubmitted: (value) {
                          notifier.checkAsrResult();
                        },
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: state.isSpellingSuccess
                          ? const Padding(
                              key: ValueKey('spelling_success_icon'),
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 24,
                                color: Color(0xFF10B981),
                              ),
                            )
                          : IconButton(
                              key: const ValueKey('spelling_hint_btn'),
                              icon: Icon(Icons.lightbulb_outline, size: 24,
                                  color: context.primaryColor),
                              onPressed: () {
                                notifier.giveFullHint();
                                // 不自动提交，用户应继续手动拼写答题
                              },
                            ),
                    ),
                  ],
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 1.5,
                  color: state.isSpellingSuccess
                      ? const Color(0xFF10B981)
                      : context.primaryColor.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 10),
                // 中文默写：只读展示"距离通过还差几个释义"。
                // 判题时机仍由「提交」触发，进度仅作展示，不接管任何手势或输入行为。
                if (state.dictationRequiredCount > 0)
                  _buildDictationProgressText(state)
                else
                  Text(
                    '支持键盘输入与手写混合使用',
                    style: TextStyle(
                      color: context.textMuted.withValues(alpha: 0.8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中文默写的通过进度（只读）：尚未命中任何释义时提示通过门槛，已有命中时提示还差几个。
  /// 与静态提示保持同字号同字距，仅数字改用主色 + 半粗，确保出现进度时底部面板不跳动。
  Widget _buildDictationProgressText(BdcState state) {
    final int matched = state.dictationMatchedCount;
    final int required = state.dictationRequiredCount;
    final int remaining = required - matched > 0 ? required - matched : 0;
    final TextStyle baseStyle = TextStyle(
      color: context.textMuted.withValues(alpha: 0.8),
      fontSize: 11.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.3,
    );
    final TextStyle numberStyle = baseStyle.copyWith(
      color: context.textPrimary,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        children: matched == 0
            ? [
                const TextSpan(text: '写对 '),
                TextSpan(text: '$required', style: numberStyle),
                const TextSpan(text: ' 个释义即可通过'),
              ]
            : [
                const TextSpan(text: '已答对 '),
                TextSpan(text: '$matched/$required', style: numberStyle),
                const TextSpan(text: ' · 还差 '),
                TextSpan(text: '$remaining', style: numberStyle),
                const TextSpan(text: ' 个即可通过'),
              ],
      ),
      style: baseStyle,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildQuestionContent(BdcState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const ValueKey('bdc_question_content_scroll_view'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: max(0.0, constraints.maxHeight - 16),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 英→中模式 或 列表模式 整合卡片
                  if ((state.studyStep == StudyStep.en2Ch.json ||
                          state.studyStep == StudyStep.list.json) &&
                      state.currentGetWordResult?.learningWord?.word != null)
                    _buildWordStepCard(state),
                  // 中→英模式整合卡片
                  if (state.studyStep == StudyStep.ch2En.json &&
                      state.currentGetWordResult?.learningWord?.word != null)
                    _buildMeaningStepCard(state),
                  // 例句英→中模式整合卡片
                  if (state.studyStep == StudyStep.enSentence2Ch.json &&
                      state.currentGetWordResult?.learningWord?.word != null)
                    _buildEnSentenceStepCard(state),
                  // 例句中→英模式整合卡片
                  if (state.studyStep == StudyStep.chSentence2En.json &&
                      state.currentGetWordResult?.learningWord?.word != null)
                    _buildChSentenceStepCard(state),

                  // 音标和例句辅助行，仅在单词/浏览模式下显示，例句模式本身不需要它们
                  if (state.studyStep == StudyStep.en2Ch.json ||
                      state.studyStep == StudyStep.ch2En.json ||
                      state.studyStep == StudyStep.list.json) ...[
                    _buildPhoneticRow(state),
                    _buildFirstSentenceRow(state),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeSwitchButton() {
    if (_tabController == null || _tabController!.length <= 1) {
      return const SizedBox.shrink();
    }
    final isDarkMode = _cachedIsDarkMode;
    final bool isSpeakMode = state.tabIndex == 0;
    final String targetLabel;
    if (isSpeakMode) {
      targetLabel = '选择题';
    } else if (state.studyStep == StudyStep.enSentence2Ch.json) {
      targetLabel = '说中文';
    } else if (state.studyStep == StudyStep.chSentence2En.json) {
      targetLabel = '说英文';
    } else if (state.studyStep == StudyStep.en2Ch.json) {
      targetLabel = '说释义';
    } else {
      targetLabel = '说发音';
    }
    final IconData targetIcon =
        isSpeakMode ? Icons.fact_check_outlined : Icons.mic_none_rounded;

    final Color actionColor =
        isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF5A716E);

    return GestureDetector(
      key: const Key('bdc_mode_switch_btn'),
      onTap: () {
        final targetIndex = isSpeakMode ? 1 : 0;
        ref.read(bdcNotifierProvider.notifier).updateTabIndex(targetIndex);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              targetIcon,
              size: 13.5,
              color: actionColor,
            ),
            const SizedBox(width: 3.5),
            Text(
              targetLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: actionColor,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final sw = Stopwatch()..start();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final bool isLargeFont = textScale > 1.05;

    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部极细无缝流光进度条（紧贴状态栏底边，通栏一体化呈现，零额外空间消耗）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final notifierInstance = ref.read(bdcNotifierProvider.notifier);
            final currentCount = state.progressBarTapCount + 1;

            HapticFeedback.lightImpact();
            notifierInstance.progressBarTapTimer?.cancel();

            if (currentCount >= 5) {
              notifier.updateProgressBarTapCount(0);
              _showDebugOverlay();
            } else {
              notifier.updateProgressBarTapCount(currentCount);
              notifierInstance.progressBarTapTimer =
                  Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                if (ref.read(bdcNotifierProvider).progressBarTapCount == 2) {
                  PerformanceWatchdog.toggleFpsOverlay();
                  HapticFeedback.mediumImpact();
                }
                notifier.updateProgressBarTapCount(0);
              });
            }
          },
          child: Container(
            height: MediaQuery.of(context).padding.top + 2.5,
            width: double.infinity,
            alignment: Alignment.bottomCenter,
            child: state.currentGetWordResult?.progress != null
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final maxValue =
                          state.currentGetWordResult!.progress![1].toDouble();
                      if (maxValue <= 0) return const SizedBox.shrink();
                      final currentProgress =
                          state.currentGetWordResult!.progress![0].toDouble();
                      final progressRatio =
                          (currentProgress / maxValue).clamp(0.0, 1.0);

                      return SizedBox(
                        height: 2.5,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            // 极淡一体化柔光微底轨（通栏无缝贯穿状态栏底边）
                            Container(
                              width: double.infinity,
                              height: 2.5,
                              color: _cachedIsDarkMode
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.04),
                            ),
                            // 连续平滑无缝流光光带
                            FractionallySizedBox(
                              widthFactor: progressRatio,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 2.5,
                                color: context.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),

        // 实时 FPS 指示气泡：当双击进度条激活彩蛋时渲染
        ValueListenableBuilder<bool>(
          valueListenable: PerformanceWatchdog.showFpsOverlay,
          builder: (context, show, child) {
            if (!show) return const SizedBox.shrink();
            return ValueListenableBuilder<double>(
              valueListenable: PerformanceWatchdog.currentFps,
              builder: (context, fps, child) {
                final isLowFps = fps < 45.0;
                final themeColor = isLowFps
                    ? Colors.red.withValues(alpha: 0.85)
                    : (_cachedIsDarkMode
                        ? Colors.white12
                        : Colors.black.withValues(alpha: 0.08));
                final textColor = isLowFps
                    ? Colors.white
                    : (_cachedIsDarkMode ? Colors.white60 : Colors.black54);
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: themeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'FPS: ${fps.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            );
          },
        ),

        // 顶部按钮
        _buildTopButtonsRow(),
        // 本组环节进度（让"整组先英译汉、再整组汉译英"的顺序可见）
        _buildGroupStepIndicator(),
        // 顶部按钮和题目区之间的间距
        const SizedBox(height: 8),
        // 题目区 - 保持固定匀称比例（4:5）
        Expanded(
          flex: 4,
          child: ScaleTransition(
            scale: _questionCollapseScaleAnimation,
            child: FadeTransition(
              opacity: _questionCollapseOpacityAnimation,
              child: Container(
                key: _wordSpellKey,
                child: Consumer(
                  builder: (context, ref, child) {
                    // 物理隔离：只监听会影响卡片渲染的核心状态
                    final wordId =
                        ref.watch(bdcNotifierProvider.select((s) => s.word?.id));
                    final historyIndex =
                        ref.watch(bdcNotifierProvider.select((s) => s.historyIndex));
                    final showSentenceTranslation = ref.watch(
                        bdcNotifierProvider.select((s) => s.showSentenceTranslation));
                    final isEditMode =
                        ref.watch(bdcNotifierProvider.select((s) => s.isEditMode));
                    final wordPlaying = ref.watch(bdcNotifierProvider
                        .select((s) => s.playingStates['word'] ?? false));
                    final sentencePlaying = ref.watch(bdcNotifierProvider
                        .select((s) => s.playingStates['sentence'] ?? false));
                    final imagesLength = ref.watch(bdcNotifierProvider
                        .select((s) => s.currentGetWordResult?.images?.length ?? 0));
                    final highlightedWordImg = ref.watch(
                        bdcNotifierProvider.select((s) => s.highlightedWordImg));

                    // 获取当前最新脱敏 state 传给卡片渲染，以确保 state 中的其他字段也是最新的，但不会被其改变触发不必要的 rebuild
                    final currentState = ref.read(bdcNotifierProvider);

                    // 确保 imagesLength 被显式使用以消除编译器警告并保持监听状态
                    if (imagesLength < 0) {
                      Global.logger.d('imagesLength: $imagesLength');
                    }

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder:
                          (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: SizedBox(
                        key: ValueKey('word_card_${wordId}_$historyIndex'),
                        width: double.infinity,
                        height: double.infinity,
                        child: _buildQuestionContent(currentState.copyWith(
                          showSentenceTranslation: showSentenceTranslation,
                          isEditMode: isEditMode,
                          playingStates: {
                            'word': wordPlaying,
                            'sentence': sentencePlaying
                          },
                          highlightedWordImg: highlightedWordImg,
                        )),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // 题目区和做题区之间的统一间距
        SizedBox(height: BdcPageState._questionAnswerGap),
        // 做题区 - 保持固定匀称比例（4:5）
        Expanded(
          flex: 5,
          child: Consumer(
            builder: (context, ref, child) {
              final wordId =
                  ref.watch(bdcNotifierProvider.select((s) => s.word?.id));
              final historyIndex =
                  ref.watch(bdcNotifierProvider.select((s) => s.historyIndex));

              return Container(
                key: ValueKey('bdc_choice_area_${wordId}_$historyIndex'),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: (state.showAnswerButtons ||
                        state.studyStep == StudyStep.en2Ch.json ||
                        state.studyStep == StudyStep.ch2En.json ||
                        state.studyStep == StudyStep.enSentence2Ch.json ||
                        state.studyStep == StudyStep.chSentence2En.json ||
                        state.studyStep == StudyStep.list.json)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _cachedIsDarkMode
                                  ? const Color(0xB8161E2A)
                                  : context.cardBg,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                // 极淡中性描边，仅一丝定义；边界主要靠"卡更白 + 柔和阴影"，避免生硬灰线
                                color: _cachedIsDarkMode
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : context.cardBorder,
                                width: 1.0,
                              ),
                              boxShadow: [context.cardShadow],
                            ),
                            padding: EdgeInsets.fromLTRB(
                              12,
                              isLargeFont ? 7.0 : 10.0,
                              12,
                              isLargeFont ? 7.0 : 10.0,
                            ),
                            child: Column(
                              children: [
                                if ((state.studyStep == StudyStep.en2Ch.json ||
                                        state.studyStep ==
                                            StudyStep.ch2En.json ||
                                        state.studyStep ==
                                            StudyStep.enSentence2Ch.json ||
                                        state.studyStep ==
                                            StudyStep.chSentence2En.json) &&
                                    _tabController != null &&
                                    _tabController!.length > 1) ...[
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (state.tabIndex == 0)
                                        Expanded(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons
                                                    .record_voice_over_outlined,
                                                size: 13.5,
                                                color: _cachedIsDarkMode
                                                    ? const Color(0xFF94A3B8)
                                                    : const Color(0xFF5A716E),
                                              ),
                                              const SizedBox(width: 4.5),
                                              Flexible(
                                                child: Text(
                                                  (state.studyStep ==
                                                          StudyStep
                                                              .enSentence2Ch
                                                              .json)
                                                      ? '请说出例句翻译：'
                                                      : (state.studyStep ==
                                                              StudyStep
                                                                  .chSentence2En
                                                                  .json)
                                                          ? '请朗读英文例句：'
                                                          : (state.studyStep ==
                                                                  StudyStep
                                                                      .en2Ch
                                                                      .json)
                                                              ? '请说出中文释义：'
                                                              : '请说出单词发音：',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    color: _cachedIsDarkMode
                                                        ? const Color(0xFFCBD5E1)
                                                        : const Color(0xFF475569),
                                                    letterSpacing: -0.1,
                                                  ),
                                                ),
                                              ),
                                              if (state.isAiEvaluating) ...[
                                                const SizedBox(width: 6),
                                                _buildAiJudgingBadge(
                                                    _cachedIsDarkMode),
                                              ],
                                            ],
                                          ),
                                        )
                                      else
                                        const Spacer(),
                                      // 英译汉：中文「默写」入口（手写中文释义；不适用语音时替代）
                                      if (state.studyStep ==
                                              StudyStep.en2Ch.json &&
                                          !state.isChineseDictation)
                                        GestureDetector(
                                          key: const Key(
                                              'bdc_chinese_dictation_btn'),
                                          onTap: () {
                                            _meaningFocusNode.unfocus();
                                            notifier.openChineseDictation();
                                          },
                                          behavior: HitTestBehavior.opaque,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 3),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.edit_outlined,
                                                  size: 13.5,
                                                  color:
                                                      _cachedIsDarkMode
                                                          ? const Color(
                                                              0xFF94A3B8)
                                                          : const Color(
                                                              0xFF5A716E),
                                                ),
                                                const SizedBox(width: 3.5),
                                                Text(
                                                  '默写',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                    color: _cachedIsDarkMode
                                                        ? const Color(
                                                            0xFF94A3B8)
                                                        : const Color(
                                                            0xFF5A716E),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      _buildModeSwitchButton(),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Expanded(
                                  child: (state.studyStep ==
                                              StudyStep.en2Ch.json ||
                                          state.studyStep ==
                                              StudyStep.ch2En.json ||
                                          state.studyStep ==
                                              StudyStep.enSentence2Ch.json ||
                                          state.studyStep ==
                                              StudyStep.chSentence2En.json)
                                      ? TabBarView(
                                          key: ValueKey(
                                              'bdc_tab_bar_view_${_tabController?.length}'),
                                          controller: _tabController,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          children: [
                                            // 始终保持 Tab 数量一致性，避免抖动
                                            if (_tabController?.length == 2)
                                              _buildSpeakPanel(),
                                            _buildChoiceListScrollView(),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Flexible(
                                              child:
                                                  _buildChoiceListScrollView(),
                                            ),
                                            Expanded(
                                                child: _buildSpeakPanel()),
                                          ],
                                        ),
                                ),
                                SizedBox(height: isLargeFont ? 4.0 : 8.0),
                                _buildFsrsResultPanel(),
                              ],
                            ),
                          ),
                        ),
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
                          updateUI(() {
                            notifier.updateShowAnswerButtons(true);
                          }, tag: 'show-answer');
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
    debugPrint('⚡ [PERF] _buildMainContent cost: ${sw.elapsedMilliseconds}ms');
    return result;
  }

  Widget _buildBottomButtons() {
    final sw = Stopwatch()..start();
    final bool isCardShowing = (state.showAnswerButtons ||
        state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json ||
        state.studyStep == StudyStep.enSentence2Ch.json ||
        state.studyStep == StudyStep.chSentence2En.json ||
        state.studyStep == StudyStep.list.json);

    final result = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 仅在磨砂卡片未显示时才在外部托底展示测评面板，避免重复
          if (!isCardShowing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildFsrsResultPanel(),
            ),
          Container(
            // 底部按钮区背景色 - 紫色调
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _showBorders
                  ? Border.all(
                      color: _cachedIsDarkMode
                          ? const Color(0xFF9C27B0) // 深色模式：紫色边框
                          : const Color(0xFF7B1FA2), // 浅色模式：深紫色边框
                      width: 2,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: _buildRatingButtonsRow(),
            ),
          ),
        ],
      ),
    );
    debugPrint(
        '⚡ [PERF] _buildBottomButtons cost: ${sw.elapsedMilliseconds}ms');
    return result;
  }

  Widget _buildMinimalPillButton({
    required Key key,
    required String label,
    required Color textColor,
    required Color indicatorColor,
    required VoidCallback? onTap,
    bool isEnabled = true,
    double indicatorWidth = 16.0,
    double fontSize = 15.5,
  }) {
    // 复用共享极简流转按钮，保证「下一词 / 不认识 / 再学学」与阶段复习「下一组」视觉一致
    return MinimalFlowButton(
      tapKey: key,
      label: label,
      textColor: textColor,
      indicatorColor: indicatorColor,
      onTap: onTap,
      isEnabled: isEnabled,
      indicatorWidth: indicatorWidth,
      fontSize: fontSize,
    );
  }

  Widget _buildRatingButtonsRow() {
    final showStudyActions = state.showAnswerButtons ||
        state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json ||
        state.studyStep == StudyStep.enSentence2Ch.json ||
        state.studyStep == StudyStep.chSentence2En.json ||
        state.studyStep == StudyStep.list.json;

    final isDark = _cachedIsDarkMode;
    // FSRS 评分严格使用记忆科学与行业通行的语义色（红/绿），通用流转导航动作「下一词」使用应用当前主题色
    final againIndicator = FsrsRating.again.colorWithDark(isDark);
    final studyAgainIndicator = FsrsRating.good.colorWithDark(isDark);
    final nextWordIndicator = context.primaryColor;

    final normalTextColor = context.textPrimary;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showStudyActions) ...[
            _buildMinimalPillButton(
              key: const Key('bdc_not_know_btn'),
              label: '不认识',
              textColor: normalTextColor,
              indicatorColor: againIndicator,
              isEnabled: state.buttonsEnabled,
              indicatorWidth: 16.0,
              onTap: () => notifier.showWordDetail(
                state.word!,
                true,
                context,
                fsrsRating: FsrsRating.again,
                reason: "主动点击了不再认识，评分: 忘记",
              ),
            ),
            const SizedBox(width: 20),
            _buildMinimalPillButton(
              key: const Key('bdc_study_again'),
              label: '再学学',
              textColor: normalTextColor,
              indicatorColor: studyAgainIndicator,
              isEnabled: state.buttonsEnabled,
              indicatorWidth: 16.0,
              onTap: () => notifier.showWordDetail(
                state.word!,
                false,
                context,
                fsrsRating: FsrsRating.good,
                reason: "主动点击了再学学，评分: 良好",
              ),
            ),
          ],
          // 答案未看过(仅答对部分释义、未达通过线)时不渲染流转按钮：此时唯一出口是「不认识/再学学」，
          // 两者都会进入单词详情页看答案并留下评分。这样"没看答案就跳到下一词"在结构上不可能发生。
          if (state.canLeaveCurrWord && notifier.hasSeenAnswer) ...[
            if (showStudyActions) const SizedBox(width: 20),
            _buildMinimalPillButton(
              key: const Key('bdc_next_word_btn'),
              label: '下一词',
              textColor: normalTextColor,
              indicatorColor: nextWordIndicator,
              isEnabled: !state.isGettingNextWord,
              indicatorWidth: 20.0,
              fontSize: 16.0,
              onTap: state.isGettingNextWord
                  ? null
                  : () => notifier.getNextWord(true,
                      fsrsRating: state.lastFsrsRating),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopActionButton({
    Key? key,
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    final isDark = _cachedIsDarkMode;
    // 极简排布：裸图标 + 轻文字，不包裹药丸/描边/阴影容器，靠字阶与色彩建立层级。
    final Color fg = isDark ? const Color(0xFFCBD5E1) : context.textSecondary;
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label != null ? 8 : 9,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: fg,
                size: 15,
              ),
              if (label != null) ...[
                const SizedBox(width: 3.5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color:
                        isDark ? const Color(0xFFE2E8F0) : context.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 本组环节进度：本组（每组单词数可配置）的序号、当前词的轨道名、该轨道在本环节的排队位置
  /// （见 StudyBo.getBatchPhaseProgress）。
  /// 极简裸排版、无容器 —— 只为让"整组先英译汉、再整组汉译英"的顺序变得可见可预期。
  Widget _buildGroupStepIndicator() {
    final groupNo = state.groupStepNo;
    final trackName = state.groupStepTrackName;
    final position = state.groupStepPosition;
    final total = state.groupStepTotal;
    final hint = state.groupStepHint;
    final stepDesc = StudyStepExt.fromString(state.studyStep ?? '').description;
    return SizedBox(
      width: double.infinity,
      child: (position <= 0 || total <= 0)
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: context.textSecondary,
                      ),
                      children: [
                        TextSpan(
                          text: '第 $groupNo 组 · $trackName · $stepDesc ',
                        ),
                        TextSpan(
                          text: '$position/$total',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 环节切换的一次性轻提示（只在切换后第一个词上出现，点 × 永久关闭）
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              hint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                color: context.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: notifier.dismissGroupStepHint,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: context.textSecondary
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildTopButtonsRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 圆形返回按钮（微透亚克力晶莹小圆钮）
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (state.currentGetWordResult != null &&
                    state.currentGetWordResult!.progress != null &&
                    state.currentGetWordResult!.progress!.length >= 2) {
                  final completed = state.currentGetWordResult!.progress![0];
                  final total = state.currentGetWordResult!.progress![1];
                  AnalyticsUtil.trackStudyQuitEarly(
                      completed, total - completed);
                }
                Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.textPrimary,
                  size: 17,
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
                // 上一个按钮
                if (state.historyIndex != -1)
                  _buildTopActionButton(
                    icon: Icons.redo_rounded,
                    label: '返回',
                    onTap: () => notifier.exitReviewMode(),
                  )
                else if (state.history.isNotEmpty)
                  _buildTopActionButton(
                    icon: Icons.undo_rounded,
                    label: '回看',
                    onTap: () => notifier.goToPreviousWord(),
                  ),

                // 已掌握按钮
                ScaleTransition(
                  scale: _masteredButtonScaleAnimation,
                  child: _buildTopActionButton(
                    key: _masteredButtonKey,
                    icon: Icons.check_circle_outline_rounded,
                    label: '掌握',
                    onTap: () {
                      final spell = state.word?.spell ?? '';
                      playMasteredFlyAnimation(spell);
                      notifier.updateHasFinishedAnswering(true);
                      notifier.updateIsWordMastered(true);
                      notifier.getNextWord(true);
                    },
                  ),
                ),

                // 报错按钮
                _buildTopActionButton(
                  icon: Icons.feedback_outlined,
                  label: '报错',
                  onTap: () => showErrorReportDlg(),
                ),

                // 查词按钮
                _buildTopActionButton(
                  icon: Icons.search_rounded,
                  onTap: () => context.push('/search'),
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

  Widget _buildChoiceItemContent(WordVo? word, bool isAnswered, bool isCh2En) {
    if (word == null) return const SizedBox.shrink();
    final isNoneOfAbove = word.spell == "[ 都不对 ]";

    if (isNoneOfAbove) {
      return Text(
        "[ 都不对 ]",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      );
    }

    // 答题后：第一行固定为英文，第二行固定为释义（紧凑排布在预留高度内，彻底防止高度跳变）
    if (isAnswered) {
      final pronounce = Util.getWordDefaultPronounce(word);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：英文单词拼写 + 音标
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: word.spell,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    height: 1.2,
                    letterSpacing: 0.2,
                  ),
                ),
                if (pronounce.isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '[$pronounce]',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: context.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          // 第二行：中文释义
          _buildMeaningInline(
              word.getMeaningStr(), 13.0, context.textSecondary),
        ],
      );
    }

    // 答题前：垂直居中展示单行选项待辨识内容
    if (isCh2En) {
      // 中选英：选项是英文单词
      return Text(
        word.spell,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
          letterSpacing: 0.2,
        ),
      );
    } else {
      // 英选中：选项是中文释义
      return _buildMeaningInline(
          word.getMeaningStr(), 15.5, context.textPrimary);
    }
  }

  Widget _buildMeaningInline(String text, double fontSize, Color defaultColor) {
    if (text.isEmpty) return const SizedBox.shrink();
    final isDark = _cachedIsDarkMode;
    final cixingColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final lines = text.split('\n');
    List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final ciXingRegex = RegExp(r'^([a-z\.\s]+)\s*(.*)$');
      final match = ciXingRegex.firstMatch(line);

      String ciXing = '';
      String meaning = line;
      if (match != null && match.group(1)!.contains('.')) {
        ciXing = match.group(1)!.trim();
        meaning = match.group(2)!.trim();
      }

      meaning = notifier.hideAnswerLeakContent(meaning);
      while (meaning.endsWith(';') ||
          meaning.endsWith('；') ||
          meaning.endsWith(',') ||
          meaning.endsWith('，') ||
          meaning.endsWith('。')) {
        meaning = meaning.substring(0, meaning.length - 1).trim();
      }

      if (ciXing.isNotEmpty) {
        widgets.add(
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$ciXing ',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: fontSize - 1,
                    fontWeight: FontWeight.w500,
                    color: cixingColor,
                    letterSpacing: 0.2,
                  ),
                ),
                TextSpan(
                  text: meaning,
                  style: TextStyle(
                    fontFamily: "NotoSansSC",
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    color: defaultColor,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Text(
            meaning,
            style: TextStyle(
              fontFamily: "NotoSansSC",
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: defaultColor,
            ),
          ),
        );
      }

      if (i < lines.length - 1) {
        widgets.add(const SizedBox(width: 8));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widgets,
      ),
    );
  }

  Widget _buildChoiceListScrollView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: const ValueKey('bdc_choice_list_scroll_view'),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Center(
              child: _buildChoiceList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoiceList() {
    if (!(state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json ||
        state.studyStep == StudyStep.enSentence2Ch.json ||
        state.studyStep == StudyStep.chSentence2En.json)) {
      return const SizedBox.shrink();
    }

    final isAnswered =
        state.selectedAnswerIndex != null || state.hasFinishedAnswering;
    final isCh2En = state.studyStep == StudyStep.ch2En.json ||
        state.studyStep == StudyStep.chSentence2En.json;
    final isDarkMode = _cachedIsDarkMode;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final bool isLargeFont = textScale > 1.05;

    return Column(
      children: [
        for (var index = 0; index < (state.words?.length ?? 0); index++) ...[
          // 极简分组：仅用发丝分隔线区隔选项，不再为每个选项塞独立卡片
          if (index > 0)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.055),
              ),
            ),
          Builder(
            builder: (context) {
              Color bgColor;
              Color borderColor;
              double borderWidth = 1.0;
              final word = state.words?[index];

              if (state.selectedAnswerIndex != null) {
                if ((index + 1) == state.correctAnswerIndex) {
                  // 仅保留主题色描边，不填充内部、不带阴影光晕，保证文字清晰
                  bgColor = Colors.transparent;
                  borderColor = context.primaryColor;
                  borderWidth = 1.2;
                } else if ((index + 1) == state.selectedAnswerIndex) {
                  // 选错：仅保留暖珊瑚描边，不填充内部、不带阴影光晕
                  bgColor = Colors.transparent;
                  borderColor = isDarkMode
                      ? const Color(0xFFFF7E6C)
                      : const Color(0xFFFA6E59);
                  borderWidth = 1.2;
                } else {
                  // 未作答 / 未命中的选项：融入面板，不铺底色
                  bgColor = Colors.transparent;
                  borderColor = Colors.transparent;
                }
              } else if (state.hasFinishedAnswering) {
                // 未点选选项但已进入看答案状态时，高亮正确选项
                if ((index + 1) == state.correctAnswerIndex) {
                  bgColor = Colors.transparent;
                  borderColor = context.primaryColor;
                  borderWidth = 1.2;
                } else {
                  bgColor = Colors.transparent;
                  borderColor = Colors.transparent;
                }
              } else {
                bgColor = Colors.transparent;
                borderColor = Colors.transparent;
              }

              return Padding(
                padding: EdgeInsets.symmetric(vertical: isLargeFont ? 1.5 : 2.5),
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: borderColor == Colors.transparent
                          ? null
                          : Border.all(
                              color: borderColor,
                              width: borderWidth,
                            ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () =>
                            notifier.onAnswerClicked(index + 1, context),
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(minHeight: isLargeFont ? 50 : 56),
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: isLargeFont ? 5.5 : 8,
                          ),
                          child: _buildChoiceItemContent(
                              word, isAnswered, isCh2En),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSpeakPanel() {
    final String? step = state.studyStep;
    if (!((step == StudyStep.en2Ch.json ||
            step == StudyStep.ch2En.json ||
            step == StudyStep.enSentence2Ch.json ||
            step == StudyStep.chSentence2En.json) &&
        state.word != null)) {
      return const SizedBox.shrink();
    }
    final isDarkMode = _cachedIsDarkMode;
    final bool isSentence = step == StudyStep.enSentence2Ch.json ||
        step == StudyStep.chSentence2En.json;

    final cardWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶栏：音频波纹 + 提示/清除按钮 (固定浮动在上方)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 语音波形反馈（新手引导高亮此处：用户要做的就是说，不是点）
              Expanded(
                key: _asrListeningKey,
                child: Consumer(
                  builder: (context, ref, child) {
                    final currentAsrState = ref
                        .watch(bdcNotifierProvider.select((s) => s.asrState));
                    final currentScore = ref.watch(
                        bdcNotifierProvider.select((s) => s.currentScore));
                    final isScorePassed = ref.watch(bdcNotifierProvider.select(
                        (s) => s.isScorePassed || s.hasFinishedAnswering));
                    final isAiEvaluating = ref.watch(
                        bdcNotifierProvider.select((s) => s.isAiEvaluating));

                    final bool isChineseInput =
                        state.studyStep == StudyStep.en2Ch.json ||
                            state.studyStep == StudyStep.enSentence2Ch.json;
                    final bool isSentence =
                        state.studyStep == StudyStep.enSentence2Ch.json ||
                            state.studyStep == StudyStep.chSentence2En.json;
                    return isChineseInput
                        ? ChineseAsrInputWidget(
                            controller: notifier.meaningController,
                            asrState: currentAsrState,
                            onStartAsr: (language) =>
                                notifier.asr.startAsr(language),
                            isKeyboardVisible: state.isKeyboardVisible,
                            focusNode: _meaningFocusNode,
                            score: currentScore,
                            isScorePassed: isScorePassed,
                            isSentenceStep: isSentence,
                            isAiEvaluating: isAiEvaluating,
                          )
                        : EnglishAsrInputWidget(
                            controller: notifier.meaningController,
                            asrState: currentAsrState,
                            onStartAsr: (language) =>
                                notifier.asr.startAsr(language),
                            isKeyboardVisible: state.isKeyboardVisible,
                            focusNode: _meaningFocusNode,
                            score: currentScore,
                            isScorePassed: isScorePassed,
                            isSentenceStep: isSentence,
                            isAiEvaluating: isAiEvaluating,
                          );
                  },
                ),
              ),

              const SizedBox(width: 8),
              if (isSentence)
                _buildPanelButton(
                  icon: Icons.refresh_rounded,
                  label: '清空',
                  onTap: () => notifier.clearHint(),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPanelButton(
                        icon: Icons.edit_note_rounded,
                        label: '拼写',
                        onTap: () {
                          // 输入框空白由 updateShowHandwritingBoard(true) 统一保证，这里不再单独清
                          updateUI(() {
                            notifier.updateShowHandwritingBoard(true);
                          }, tag: 'hw-open');
                          notifier.asr.stopMicrophone();
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPanelButton(
                        icon: Icons.lightbulb_outline_rounded,
                        label: '提示',
                        onTap: () => notifier.giveALittleHint(),
                        onLongPress: () => notifier.giveFullHint(),
                      ),
                      const SizedBox(width: 6),
                      _buildPanelButton(
                        icon: Icons.refresh_rounded,
                        label: '清除',
                        onTap: () => notifier.clearHint(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // 微柔光分割线
        Container(
          height: 0.6,
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),

        // 2. 滚动区域：中文释义 / 拼写提示与手写结果
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _speakPanelScrollController,
                  physics: state.showHandwritingBoard
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: () {
                      final step = state.studyStep;
                      if (step == StudyStep.enSentence2Ch.json) {
                        return _buildSentenceAnswerArea();
                      } else if (step == StudyStep.chSentence2En.json) {
                        return _buildSentenceAnswerArea();
                      } else if (step == StudyStep.en2Ch.json) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...renderAsrMeaningItems(state.wordWrapper!,
                                isDarkMode:
                                    context.read<DarkMode>().isDarkMode),
                          ],
                        );
                      } else {
                        return Center(
                          child: _buildCenteredSpellingHint(isDarkMode),
                        );
                      }
                    }(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: cardWidget),
        // 3. 例句环节底部固定"按住说话/练习"按钮：独立于滚动区，位置不随识别文本/反馈变化
        if (isSentence) _buildPttSpeakButton(),
      ],
    );
  }

  Widget _buildCenteredSpellingHint(bool isDarkMode) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: notifier.meaningController,
      builder: (context, value, child) {
        final text = value.text;
        if (text.isEmpty) {
          return const SizedBox.shrink();
        }

        final targetSpell = state.word?.spell ?? '';
        final isMatched =
            text.trim().toLowerCase() == targetSpell.trim().toLowerCase();
        final textPrimaryColor =
            isDarkMode ? Colors.white : const Color(0xFF1D1D1F);
        final textColor = isMatched ? textPrimaryColor : context.primaryColor;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  SpellingTextEditingController.buildSpellingTextSpan(
                    text,
                    targetSpell,
                    text.trim().toLowerCase() !=
                                targetSpell.trim().toLowerCase() &&
                            !targetSpell
                                .toLowerCase()
                                .startsWith(text.trim().toLowerCase())
                        ? const Color(0xFFFA6E59)
                        : textColor,
                    TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      letterSpacing: isMatched ? 1.2 : 3.5,
                      color: textColor,
                    ),
                  ),
                  if (text.length < targetSpell.length)
                    TextSpan(
                      text: _buildUnderlines(targetSpell, text.length),
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.28)
                            : Colors.black.withValues(alpha: 0.22),
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

  String _buildUnderlines(String targetWord, int inputLength) {
    final buffer = StringBuffer();
    for (int i = inputLength; i < targetWord.length; i++) {
      final char = targetWord[i];
      if (RegExp(r'[a-zA-Z]').hasMatch(char)) {
        buffer.write('_');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  Widget _buildAiJudgingBadge(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: context.primaryColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 8.5,
            height: 8.5,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: context.primaryColor,
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            'AI判定中...',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: context.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 例句环节可编辑答案输入框：识别结果写入其中，支持光标定位与语音插入补充。
  /// 不弹系统输入法(readOnly + showCursor)：点击仅显示光标位置作为语音插入点，
  /// 编辑区固定在可视高度内占满答案区，内容多时可内部滚动。
  Widget _buildSentenceAnswerArea() {
    final isDarkMode = _cachedIsDarkMode;
    final hintText = state.studyStep == StudyStep.enSentence2Ch.json
        ? '请按住下方按钮，说出例句翻译'
        : (state.studyStep == StudyStep.chSentence2En.json
            ? '请按住下方按钮，朗读英文例句'
            : '请按住下方按钮说话');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: notifier.sentenceAnswerController,
          focusNode: _sentenceAnswerFocusNode,
          // readOnly:不弹系统输入法,点击仅聚焦以显示光标位置(语音插入点)。
          // 光标位置由 onAsrResult 读取,用于 PTT 补充说话时定位插入点。
          readOnly: true,
          showCursor: true,
          enabled: !state.hasFinishedAnswering,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
          minLines: 2,
          maxLines: 5,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDarkMode ? Colors.white30 : Colors.black38,
            ),
            isDense: true,
            filled: false,
            fillColor: Colors.transparent,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        if (state.isAiEvaluating) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _buildAiJudgingBadge(_cachedIsDarkMode),
          ),
        ],
        if (state.hasFinishedAnswering &&
            (state.lastFsrsRatingReason?.contains("AI裁判") ?? false)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gavel_rounded, color: Colors.green, size: 12),
                  SizedBox(width: 4),
                  Text(
                    "AI判定正确",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 例句环节"按住说话"PTT 大按钮：按下并保持开始识别，松开停止并立即判定。
  /// 仅例句步骤 (EnSentence2Ch / ChSentence2En) 且未答完时展示。
  /// 用 [Listener] 监听原始指针事件而非 GestureDetector：
  /// 按钮处于 SingleChildScrollView 内，GestureDetector 的 Tap 会因手指轻微移动
  /// 触发的滚动手势竞争而被 cancel，导致说话被打断；Listener 不参与手势竞技场，
  /// 按下即开始、任何抬起即停止，手指抖动不会中断识别。
  Widget _buildPttSpeakButton() {
    final isDarkMode = _cachedIsDarkMode;
    final isFinished = state.hasFinishedAnswering;
    final idleLabel = isFinished ? '按住练习' : '按住说话';
    // 用 Consumer 细粒度监听 isPttPressed，避免依赖顶层 _activeState 缓存（顶层按 BdcStateUiSignature 重建，不含该字段）
    return Consumer(
      builder: (context, ref, _) {
        final isPressed =
            ref.watch(bdcNotifierProvider.select((s) => s.isPttPressed));
        final bgColor = isPressed
            ? (isDarkMode
                ? Colors.white24
                : Colors.black.withValues(alpha: 0.08))
            : context.primaryColor;
        final fgColor = isPressed
            ? (isDarkMode ? Colors.white : Colors.black87)
            : Colors.white;

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Listener(
            onPointerDown: (_) {
              // 按住说话时收起答案区键盘，避免键盘与说话手势冲突
              if (_sentenceAnswerFocusNode.hasFocus) {
                _sentenceAnswerFocusNode.unfocus();
              }
              if (state.hasFinishedAnswering) {
                notifier.hideAnswer();
              }
              notifier.startPttAsr();
            },
            onPointerUp: (_) => notifier.stopPttAsr(),
            onPointerCancel: (_) => notifier.stopPttAsr(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPressed
                      ? (isDarkMode ? Colors.white54 : Colors.black26)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPressed ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: fgColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPressed ? '松开结束并判定' : idleLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
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

  Widget _buildFsrsResultPanel() {
    final isDarkMode = _cachedIsDarkMode;
    final textColor = isDarkMode ? Colors.white38 : Colors.black38;

    final bool hasFinishedOrPractice =
        state.hasFinishedAnswering || (state.isPracticeMode && state.lastFsrsRating != null);
    if (!hasFinishedOrPractice || state.fsrsItem == null) {
      if (state.currentGetWordResult != null &&
          state.currentGetWordResult!.stepIndex > 0 &&
          state.wordWrapper?.word.id != null) {
        return FutureBuilder<List<LearningLog>>(
          future: notifier.learningHistoryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              // 巩固阶段：如果当前词已有本场测评结果，直接展示测评数据
              if (state.assessmentRating != null) {
                final assRating = state.assessmentRating!;
                String assLabel = assRating.label;
                Color assColor = assRating.colorWithDark(isDarkMode);
                return Container(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '测评结果: $assLabel',
                          style: TextStyle(fontSize: 11, color: assColor),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('|',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: textColor.withValues(alpha: 0.3))),
                        ),
                        Text(
                          '下次复习: ${state.assessmentScheduledDays ?? "--"}天后',
                          style: TextStyle(fontSize: 11, color: textColor),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // 巩固阶段兜底:LearningLog 无测评记录且 assessmentRating 未恢复。
              // 若已作答(如点击"看答案"后 lastFsrsRating=again)则显示评分,
              // 否则显示"测评中"。
              final String fallbackLabel = state.lastFsrsRating?.label ?? '测评中';
              final bool hasRating = state.lastFsrsRating != null;
              return Container(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 有评分时才可点击弹"修改今日评分"对话框;测评中不可点击
                      hasRating
                          ? InkWell(
                              onTap: _showRatingModifyDialog,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Text(
                                  '测评结果: $fallbackLabel',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hasRating
                                        ? (state.lastFsrsRating
                                                ?.colorWithDark(isDarkMode) ??
                                            textColor)
                                        : textColor,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              '测评中',
                              style: TextStyle(fontSize: 11, color: textColor),
                            ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('|',
                            style: TextStyle(
                                fontSize: 10,
                                color: textColor.withValues(alpha: 0.3))),
                      ),
                      Text(
                        '下次复习: --天后',
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ],
                  ),
                ),
              );
            }

            final latestLog = snapshot.data!.first;
            final rating = FsrsRatingExt.fromInt(latestLog.rating);
            final scheduledDays = latestLog.scheduledDays;

            String ratingLabel = rating.label;
            Color ratingColor = rating.colorWithDark(isDarkMode);

            return Container(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: _showRatingModifyDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '测评结果: $ratingLabel',
                              style: TextStyle(
                                fontSize: 11,
                                color: ratingColor,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dashed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('|',
                          style: TextStyle(
                              fontSize: 10,
                              color: textColor.withValues(alpha: 0.3))),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text: '下次复习: ',
                              style: TextStyle(fontSize: 11, color: textColor)),
                          TextSpan(
                            text: '$scheduledDays',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          TextSpan(
                              text: '天后',
                              style: TextStyle(fontSize: 11, color: textColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _showLearningHistoryDialog,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 14,
                              color: textColor.withValues(alpha: 0.75)),
                          const SizedBox(width: 2),
                          Text(
                            '${snapshot.data!.length}',
                            style: TextStyle(
                                fontSize: 11,
                                color: textColor.withValues(alpha: 0.8),
                                height: 1.1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
      // 测评环节未作答且未进入练习模式：直接返回占位
      if (!hasFinishedOrPractice) {
        return const SizedBox(height: 24);
      }
    }

    // 测评环节且已完成做题：展示测评结果
    // 巩固阶段直接进入或复习无测评记录兜底
    if (state.fsrsItem == null &&
        (state.assessmentScheduledDays == null ||
            state.assessmentScheduledDays! <= 0)) {
      final String fallbackLabel = state.lastFsrsRating?.label ?? '测评中';
      final bool hasRating = state.lastFsrsRating != null;
      return Container(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              hasRating
                  ? InkWell(
                      onTap: _showRatingModifyDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          '测评结果: $fallbackLabel',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: hasRating
                                ? (state.lastFsrsRating
                                        ?.colorWithDark(isDarkMode) ??
                                    textColor)
                                : textColor,
                          ),
                        ),
                      ))
                  : Text(
                      '测评中',
                      style: TextStyle(fontSize: 11.5, color: textColor),
                    ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('·',
                    style: TextStyle(
                        fontSize: 13,
                        color: textColor.withValues(alpha: 0.4))),
              ),
              Text(
                '下次复习: --天后',
                style: TextStyle(fontSize: 11.5, color: textColor),
              ),
            ],
          ),
        ),
      );
    }

    // 获取本次操作的评估标签和颜色
    String ratingLabel = state.lastFsrsRating?.label ?? '未知';
    Color ratingColor = state.lastFsrsRating?.colorWithDark(isDarkMode) ??
        (isDarkMode ? Colors.white70 : Colors.black87);

    return Container(
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: _showRatingModifyDialog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '测评结果: $ratingLabel',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ratingColor,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·',
                  style: TextStyle(
                      fontSize: 13,
                      color: textColor.withValues(alpha: 0.4))),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: '下次复习: ',
                      style: TextStyle(fontSize: 11.5, color: textColor)),
                  TextSpan(
                    text: '${state.fsrsItem!.scheduledDays}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDarkMode
                          ? const Color(0xFFEAF7F4)
                          : const Color(0xFF152724),
                    ),
                  ),
                  TextSpan(
                      text: '天后',
                      style: TextStyle(fontSize: 11.5, color: textColor)),
                ],
              ),
            ),
            if (state.wordWrapper?.word.id != null)
              FutureBuilder(
                future: notifier.learningHistoryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox();
                  }
                  final historyCount = (snapshot.data as List?)?.length ?? 0;
                  if (historyCount == 0) {
                    return const SizedBox();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _showLearningHistoryDialog,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 14,
                                color: textColor.withValues(alpha: 0.75)),
                            const SizedBox(width: 2),
                            Text(
                              '$historyCount',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: textColor.withValues(alpha: 0.8),
                                  height: 1.1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final isDarkMode = _cachedIsDarkMode;
    final Color actionColor =
        isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF5A716E);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: actionColor,
                size: 13.5,
              ),
              const SizedBox(width: 3.5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: actionColor,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneticRow(BdcState state) {
    if (state.currentGetWordResult?.learningWord?.word == null ||
        state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: ValueListenableBuilder<String>(
        valueListenable: Prefs.pronunciationAccentNotifier,
        builder: (context, _, __) {
          final currentWord = state.currentGetWordResult?.learningWord?.word;
          if (currentWord == null) return const SizedBox.shrink();
          final pronInfo = Util.getWordPronounceWithAccent(currentWord);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (pronInfo.$2.isNotEmpty) ...[
                PronunciationAccentBadge(
                  label: pronInfo.$2,
                  isFallback: pronInfo.$3,
                  color: context.textSecondary,
                  fontSize: 10.5,
                  margin: const EdgeInsets.only(right: 6),
                  onSwitched: (newAccent) async {
                    StudyAudioSessionController.instance
                        .playWordSound(currentWord);
                  },
                ),
              ],
              if (pronInfo.$1.isNotEmpty)
                Flexible(
                  child: Text(
                    '[${pronInfo.$1}]',
                    style: TextStyle(
                      color: _cachedIsDarkMode
                          ? const Color(0xFFD1D5DB)
                          : const Color(0xFF4B5563),
                      fontFamily: "NotoSans",
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              buildWordSoundButton(currentWord, _audioPlayer, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFirstSentenceRow(BdcState state) {
    if (!(state.word?.sentences != null &&
        state.word!.sentences!.isNotEmpty &&
        state.studyStep != StudyStep.ch2En.json &&
        state.studyStep != StudyStep.en2Ch.json)) {
      return const SizedBox.shrink();
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        final sentencePlaying = state.playingStates['sentence'] ?? false;
        if (!sentencePlaying && state.englishDigestOfFirstSentence != null) {
          notifier.playWithAnimation(
              () => StudyAudioSessionController.instance
                  .playSentenceSound(state.englishDigestOfFirstSentence!),
              'sentence');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Util.makeEnglishSpanText(
                    state.word!.sentences![0].english!,
                    state.word!.spell,
                    true,
                    context,
                    false,
                    null,
                    true,
                    FontWeight.w400),
              ),
            ),
            const SizedBox(width: 8),
            buildSentenceSoundButton(state),
          ],
        ),
      ),
    );
  }

  Widget _buildEnSentenceStepCard(BdcState state) {
    final isDarkMode = _cachedIsDarkMode;
    final sentence =
        (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
            ? state.word!.sentences!.first
            : null;
    final sentenceText = sentence?.english ?? "No sentence available";
    final spell = state.word?.spell ?? '';
    final bool isChoiceTab = state.tabIndex == 1;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 选择题 Tab：显示单词英文拼写，不显示例句
          if (isChoiceTab && spell.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                spell,
                key: const Key('en_sentence_word_spell'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  fontFamily: 'Roboto',
                  letterSpacing: -0.4,
                  color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ),
          ],
          // 2. 说中文 Tab：只显示英文例句，不显示单词
          if (!isChoiceTab) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Util.makeEnglishSpanText(
                sentenceText,
                spell,
                true,
                context,
                false,
                null,
                false,
                FontWeight.normal,
                fontSize: 20,
                textAlign: TextAlign.center,
                color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // 小喇叭 + 看答案/隐藏答案 同行,根据作答状态切换按钮,避免按钮被滚动区遮挡
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkResponse(
                  radius: 22,
                  highlightShape: BoxShape.circle,
                  onTap: () {
                    final sentencePlaying =
                        state.playingStates['sentence'] ?? false;
                    if (!sentencePlaying) {
                      notifier.playWordAndFirstSentence(false, false,
                          forcePlaySentence: true);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ModernSoundWaveIcon(
                      isPlaying: state.playingStates['sentence'] ?? false,
                      animationController: _sentenceSoundController,
                      size: 22.0,
                    ),
                  ),
                ),
              ),
              if (!state.hasFinishedAnswering)
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text("看答案",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                  ),
                  onPressed: () {
                    notifier.revealAnswerAndMarkWrong(context);
                  },
                )
              else
                TextButton.icon(
                  onPressed: () => notifier.hideAnswer(),
                  icon: const Icon(Icons.visibility_off_outlined, size: 16),
                  label: const Text('隐藏答案继续练习',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                  ),
                ),
            ],
          ),
          // 仅在说模式 Tab 且看答案状态下展示中文例句；选择题 Tab 不显示例句
          if (!isChoiceTab && state.hasFinishedAnswering && sentence != null) ...[
            const SizedBox(height: 12),
            Util.makeChineseSpanText(
              sentence.chinese ?? '',
              context,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// 单词释义多行展示组件：在例句汉译英选择题模式下展示，
  /// 允许多行展示，词性列与释义列严格左对齐，视觉工整高级且易读。
  Widget _buildChoiceMeanings(BdcState state) {
    final allItems = state.word?.getMergedMeaningItems() ?? [];
    final hasCixingItems =
        allItems.any((item) => (item.ciXing ?? '').trim().isNotEmpty);
    final displayItems = hasCixingItems
        ? allItems
            .where((item) => (item.ciXing ?? '').trim().isNotEmpty)
            .toList()
        : allItems;

    String cleanMeaning(String? raw) {
      if (raw == null) return '';
      var text = notifier.hideParenthesesContent(raw).trim();
      while (text.endsWith(';') ||
          text.endsWith('；') ||
          text.endsWith(',') ||
          text.endsWith('，') ||
          text.endsWith('。')) {
        text = text.substring(0, text.length - 1).trim();
      }
      return text;
    }

    final isDark = _cachedIsDarkMode;
    final cixingColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final count = displayItems.length;
    final double meaningFontSize = count <= 1 ? 22.0 : 18.0;
    final double cixingFontSize = count <= 1 ? 15.0 : 13.5;
    final double itemVerticalGap = count <= 1 ? 4.0 : 5.0;

    if (displayItems.isEmpty) {
      final rawMeaning = state.word?.getMeaningStr() ?? '';
      final cleaned = cleanMeaning(rawMeaning);
      if (cleaned.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            cleaned,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: meaningFontSize,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              height: 1.4,
              letterSpacing: -0.2,
            ),
          ),
        ),
      );
    }

    final anyHasCixing = displayItems.any((i) => (i.ciXing ?? '').trim().isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: anyHasCixing
            ? Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                },
                children: [
                  for (final item in displayItems)
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            right: 10,
                            top: itemVerticalGap,
                            bottom: itemVerticalGap,
                          ),
                          child: Text(
                            (item.ciXing ?? '').trim(),
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: cixingColor,
                              fontSize: cixingFontSize,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: itemVerticalGap),
                          child: Text(
                            cleanMeaning(item.meaning),
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: meaningFontSize,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                              height: 1.4,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in displayItems)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: itemVerticalGap),
                      child: Text(
                        cleanMeaning(item.meaning),
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: meaningFontSize,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                          height: 1.4,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildChSentenceStepCard(BdcState state) {
    final sentence =
        (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
            ? state.word!.sentences!.first
            : null;
    final translationText = sentence?.chinese ?? "暂无例句翻译";
    final bool isChoiceTab = state.tabIndex == 1;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 说英文 Tab：只显示中文例句，不显示中文释义
          if (!isChoiceTab) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Util.makeChineseSpanText(
                translationText,
                context,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: context.textPrimary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          // 2. 选择题 Tab：只显示中文释义，不显示例句
          if (isChoiceTab) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildChoiceMeanings(state),
            ),
          ],
          const SizedBox(height: 8),
          // 小喇叭 + 看答案/隐藏答案 同行,根据作答状态切换按钮,避免按钮被滚动区遮挡
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkResponse(
                  radius: 22,
                  highlightShape: BoxShape.circle,
                  onTap: () {
                    final sentencePlaying =
                        state.playingStates['sentence'] ?? false;
                    if (!sentencePlaying) {
                      notifier.playWordAndFirstSentence(false, false,
                          forcePlaySentence: true);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ModernSoundWaveIcon(
                      isPlaying: state.playingStates['sentence'] ?? false,
                      animationController: _sentenceSoundController,
                      size: 22.0,
                    ),
                  ),
                ),
              ),
              if (!state.hasFinishedAnswering)
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text("看答案",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                  ),
                  onPressed: () {
                    notifier.revealAnswerAndMarkWrong(context);
                  },
                )
              else
                TextButton.icon(
                  onPressed: () => notifier.hideAnswer(),
                  icon: const Icon(Icons.visibility_off_outlined, size: 16),
                  label: const Text('隐藏答案继续练习',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                  ),
                ),
            ],
          ),
          // 仅在说模式 Tab 且看答案状态下展示英文例句；选择题 Tab 不显示例句
          if (!isChoiceTab && state.hasFinishedAnswering && sentence != null) ...[
            const SizedBox(height: 12),
            Util.makeEnglishSpanText(
              sentence.english ?? '',
              state.word?.spell ?? '',
              true,
              context,
              false,
              null,
              false,
              FontWeight.w500,
              fontSize: 16,
              textAlign: TextAlign.center,
              color: context.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWordStepCard(BdcState state) {
    final primaryTextColor = context.textPrimary;
    final secondaryTextColor = context.textSecondary;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 核心单词拼写
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    key: const Key('currentstate.word_spell'),
                    state.currentGetWordResult!.learningWord!.word.spell,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 44,
                      color: primaryTextColor,
                      fontFamily: 'Roboto',
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 音标与播音小胶囊（支持点击小按钮快速切换英美音）
                ValueListenableBuilder<String>(
                  valueListenable: Prefs.pronunciationAccentNotifier,
                  builder: (context, _, __) {
                    final currentWord =
                        state.currentGetWordResult?.learningWord?.word;
                    if (currentWord == null) return const SizedBox.shrink();
                    final pronInfo =
                        Util.getWordPronounceWithAccent(currentWord);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (pronInfo.$2.isNotEmpty) ...[
                          PronunciationAccentBadge(
                            label: pronInfo.$2,
                            isFallback: pronInfo.$3,
                            color: context.textSecondary,
                            fontSize: 11,
                            margin: const EdgeInsets.only(right: 5),
                            onSwitched: (newAccent) async {
                              StudyAudioSessionController.instance
                                  .playWordSound(currentWord);
                            },
                          ),
                        ],
                        if (pronInfo.$1.isNotEmpty)
                          Flexible(
                            child: Text(
                              '[${pronInfo.$1}]',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontFamily: "NotoSans",
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              softWrap: true,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(width: 6),
                        buildWordSoundButton(currentWord, _audioPlayer, state),
                      ],
                    );
                  },
                ),
                if (state.studyStep == StudyStep.list.json) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.word?.getMeaningStr() ?? '',
                    style: TextStyle(
                      fontSize: 16,
                      color: primaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          if (state.word?.sentences != null &&
              state.word!.sentences!.isNotEmpty) ...[
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                final sentencePlaying =
                    state.playingStates['sentence'] ?? false;
                if (!sentencePlaying &&
                    state.englishDigestOfFirstSentence != null) {
                  notifier.playWithAnimation(
                      () => StudyAudioSessionController.instance
                          .playSentenceSound(
                              state.englishDigestOfFirstSentence!),
                      'sentence');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 英文例句（顶格起排，重点单词高亮）
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Util.makeEnglishSpanText(
                                state.word!.sentences![0].english!,
                                state.word!.spell,
                                true,
                                context,
                                false,
                                null,
                                true,
                                FontWeight.w400),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 极简现代声波发音图标（置于右侧，极大方便右手单手大拇指触达）
                        buildSentenceSoundButton(state),
                      ],
                    ),
                    if (!state.showSentenceTranslation)
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () {
                            updateUI(() {
                              notifier.updateShowSentenceTranslation(true);
                            }, tag: 'sentence-trans');
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.only(
                                top: 6, left: 6, bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '显示翻译',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: _cachedIsDarkMode
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 13.5,
                                  color: _cachedIsDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Util.makeChineseSpanText(
                          state.word!.sentences![0].chinese ?? '',
                          context,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeaningStepCard(BdcState state) {
    final allItems =
        state.currentGetWordResult!.learningWord!.word.getMergedMeaningItems();
    final hasCixingItems =
        allItems.any((item) => (item.ciXing ?? '').trim().isNotEmpty);
    final displayItems = hasCixingItems
        ? allItems
            .where((item) => (item.ciXing ?? '').trim().isNotEmpty)
            .toList()
        : allItems;

    // 自适应字阶与排版参数
    final count = displayItems.length;

    final double meaningFontSize;
    final double cixingFontSize;
    final double itemVerticalGap;

    if (count <= 1) {
      meaningFontSize = 26.0;
      cixingFontSize = 17.0;
      itemVerticalGap = 6.0;
    } else if (count == 2) {
      meaningFontSize = 20.0;
      cixingFontSize = 14.5;
      itemVerticalGap = 6.0;
    } else {
      meaningFontSize = 17.0;
      cixingFontSize = 13.0;
      itemVerticalGap = 5.0;
    }

    String cleanMeaning(String? raw) {
      if (raw == null) return '';
      var text = notifier.hideParenthesesContent(raw).trim();
      while (text.endsWith(';') ||
          text.endsWith('；') ||
          text.endsWith(',') ||
          text.endsWith('，') ||
          text.endsWith('。')) {
        text = text.substring(0, text.length - 1).trim();
      }
      return text;
    }

    final isDark = _cachedIsDarkMode;
    final cixingColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (count <= 1)
            for (final item in displayItems)
              Padding(
                padding: EdgeInsets.symmetric(vertical: itemVerticalGap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if ((item.ciXing ?? '').trim().isNotEmpty) ...[
                      Text(
                        (item.ciXing ?? '').trim(),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: cixingColor,
                          fontSize: cixingFontSize,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Roboto',
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        cleanMeaning(item.meaning),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: meaningFontSize,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                          height: 1.35,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            // 多项时：整组居中，使用 Table 原生弹性列自动匹配最宽词性，天然垂直对齐成列，彻底根除换行与魔数宽度
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                },
                children: [
                  for (final item in displayItems)
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            right: 8,
                            top: itemVerticalGap,
                            bottom: itemVerticalGap,
                          ),
                          child: Text(
                            (item.ciXing ?? '').trim(),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: cixingColor,
                              fontSize: cixingFontSize,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Roboto',
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: itemVerticalGap),
                          child: Text(
                            cleanMeaning(item.meaning),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: meaningFontSize,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                              height: 1.4,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

          // 图片 (仅对管理员开放)
          if (StudyConfig.fromCurrentUser().enableWordImage &&
              (Global.getLoggedInUser()?.isAdmin == true) &&
              state.currentGetWordResult?.images != null &&
              state.currentGetWordResult!.images!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Column(
              children: [
                if (state.currentGetWordResult!.images!.isNotEmpty &&
                    state.studyStep != StudyStep.ch2En.json)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        '图片: ${state.currentGetWordResult!.images!.length}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400)),
                  ),
                WordImagesWidget(
                  images: state.currentGetWordResult!.images!,
                  isEditMode: state.isEditMode,
                  highlightedWordImg: state.highlightedWordImg?.imageFile,
                  maxImages: 2,
                  onImageTap: (image) {
                    showImagePreviewWithContext(context, image, onDeleted: () {
                      state.currentGetWordResult?.images
                          ?.removeWhere((e) => e.id == image.id);
                      updateUI(() {}, tag: 'img-delete');
                    });
                  },
                ),
              ],
            ),
          ],

          // 配图按钮
          if (StudyConfig.fromCurrentUser().enableWordImage &&
              state.isEditMode &&
              (state.currentGetWordResult?.learningWord?.word.images?.length ??
                      0) <
                  2)
            InkWell(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 24.0),
                  style: ElevatedButton.styleFrom(
                    foregroundColor:
                        _cachedIsDarkMode ? Colors.black : Colors.white,
                    backgroundColor:
                        _cachedIsDarkMode ? Colors.white : context.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  label: const Text('添加配图'),
                  onPressed: () {
                    if (state.currentGetWordResult?.learningWord?.word.id !=
                        null) {
                      context
                          .push('/pic_search',
                              extra: PicSearchPageArgs(
                                  state.currentGetWordResult!.learningWord!.word
                                      .id!,
                                  state.currentGetWordResult!.learningWord!.word
                                      .spell))
                          .then((value) => notifier.reloadWord());
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
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
        controller: state.wordWrapper!.spellController,
        focusNode: state.wordWrapper!.focusNode,
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
          if (Util.equalsIgnoreCase(state.word!.spell, value)) {
            StudyAudioSessionController.instance.playWordSound(state.word!);
            Util.closeIme();
          }
          updateUI(() {}, tag: 'spell-submit');
        },
        style: textStyle,
      ),
    );
  }

  Widget buildWordSoundButton(
      WordVo word, dynamic audioPlayer, BdcState state) {
    final wordPlaying = state.playingStates['word'] ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          child: InkResponse(
            radius: 18,
            highlightShape: BoxShape.circle,
            onTap: () {
              if (!wordPlaying) {
                notifier.playWithAnimation(
                    () => StudyAudioSessionController.instance
                        .playWordSound(word),
                    'word');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              child: ModernSoundWaveIcon(
                isPlaying: wordPlaying,
                animationController: _wordSoundController,
                size: 18.5,
              ),
            ),
          ),
        ),
        ValueListenableBuilder<AudioPlaybackStatus>(
          valueListenable:
              StudyAudioSessionController.instance.playbackStatusNotifier,
          builder: (context, status, child) {
            if (status.hasFallback && status.spell == word.spell) {
              return Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.35), width: 0.5),
                ),
                child: Text(
                  status.fallbackType == AudioFallbackType.ttsFallback
                      ? '系统朗读'
                      : '备用发音',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget buildSentenceSoundButton(BdcState state) {
    final sentencePlaying = state.playingStates['sentence'] ?? false;

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        radius: 18,
        highlightShape: BoxShape.circle,
        onTap: () {
          if (!sentencePlaying && state.englishDigestOfFirstSentence != null) {
            notifier.playWithAnimation(
                () => StudyAudioSessionController.instance
                    .playSentenceSound(state.englishDigestOfFirstSentence!),
                'sentence');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: ModernSoundWaveIcon(
            isPlaying: sentencePlaying,
            animationController: _sentenceSoundController,
            size: 19.0,
          ),
        ),
      ),
    );
  }
}
