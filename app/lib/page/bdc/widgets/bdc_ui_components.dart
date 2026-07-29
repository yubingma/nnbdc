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
            const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              "正在准备学习内容...",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.3),
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
                  child: HandwritingBoard(
                    showCloseButton: false,
                    showHeader: false, // 隐藏内部自带的标题栏
                    useBoxDecoration: false, // 隐藏内部背景和圆角，直接使用外层背景
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

                      notifier.meaningController.text = text;
                      await notifier.checkAsrResult(asrInput: text, isVoice: false);
                    },
                      onCancel: () {
                        _meaningFocusNode.unfocus();
                        updateUI(() {
                          notifier.updateShowHandwritingBoard(false);
                        }, tag: 'hw-cancel');
                        notifier.handleTabChangeForAsr();
                    },
                  ),
                ),

                // 顶层：浮动释义头部 (采用渐变背景确保文字清晰，且支持笔触穿透)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                        16, MediaQuery.of(context).padding.top + 8, 8, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (isDarkMode ? const Color(0xFF121212) : Colors.white)
                              .withValues(alpha: 0.85),
                          (isDarkMode ? const Color(0xFF121212) : Colors.white)
                              .withValues(alpha: 0.0),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: IgnorePointer(
                            // 使用 IgnorePointer 让用户可以在释义文字区域直接起笔书写
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '请拼写单词：',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                                Text(
                                  combinedMeaning,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 功能按钮 (不被 IgnorePointer 包裹，确保可点击)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _meaningFocusNode.unfocus();
                                updateUI(() {
                                  notifier.updateShowHandwritingBoard(false);
                                }, tag: 'hw-close');
                                notifier.handleTabChangeForAsr();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 底部输入与提示区
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
              border: Border(
                top: BorderSide(
                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
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
                        autofocus: StudyConfig.fromCurrentUser().preferKeyboardInSpelling,
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: '在此键入单词...',
                          hintStyle: TextStyle(
                            fontSize: 32,
                            color: (isDarkMode ? Colors.white : Colors.black)
                                .withValues(alpha: 0.2),
                            fontWeight: FontWeight.normal,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (value) {
                          notifier.updateIsUpdatingByHint(false);
                          if (value.isNotEmpty && state.word?.spell != null) {
                            if (Util.equalsIgnoreCase(value, state.word!.spell)) {
                              // 提示已经显示了全部字母时不应自动提交，用户应继续手动答题
                              final allRevealedByHint =
                                  (state.wordWrapper?.hintLetterCount ?? 0) >= state.word!.spell.length;
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
                    IconButton(
                      icon: Icon(Icons.lightbulb_outline, color: AppTheme.primaryColor),
                      onPressed: () {
                        notifier.giveFullHint();
                        // 不自动提交，用户应继续手动拼写答题
                      },
                    ),
                  ],
                ),
                Container(
                  height: 2,
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  '支持键盘输入与手写混合使用',
                  style: TextStyle(
                    color: (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.24),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildQuestionContent(BdcState state) {
    return Container(
      decoration: BoxDecoration(
        color: _cachedIsDarkMode
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF8F9FA),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.zero,
          topRight: Radius.zero,
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: _cachedIsDarkMode
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: _showBorders
            ? Border.all(
                color: const Color.fromARGB(255, 11, 118, 3),
                width: 10,
              )
            : null,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('bdc_question_content_scroll_view'),
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            BdcPageState.leftPadding,
            0,
            BdcPageState.rightPadding,
            max(
                kTextTabBarHeight + 6.0,
                MediaQuery.of(context).viewPadding.bottom +
                    kTextTabBarHeight)), // 预留底部TabBar空间，避免遮挡
        child: Column(
          children: [
            // 英→中模式 或 列表模式 整合卡片
            if ((state.studyStep == StudyStep.en2Ch.json || state.studyStep == StudyStep.list.json) &&
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
                      if (state.aiRefereeFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gavel_rounded, color: Colors.orange.shade600, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  state.aiRefereeFeedback!,
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
        ),
      ),
    );
  }


  Widget _buildTabBar() {
    if (_tabController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: _cachedIsDarkMode
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _cachedIsDarkMode
            ? Colors.white
            : Colors.black,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        labelColor: _cachedIsDarkMode
            ? Colors.white
            : Colors.black,
        unselectedLabelColor: _cachedIsDarkMode
            ? Colors.white54
            : Colors.grey.shade400,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        tabs: notifier.dynamicTabs,
      ),
    );
  }


  Widget _buildMainContent() {
    final sw = Stopwatch()..start();
    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部学习进度条
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final notifierInstance = ref.read(bdcNotifierProvider.notifier);
            final currentCount = state.progressBarTapCount + 1;

            // 每次点击都给予轻微反馈
            HapticFeedback.lightImpact();

            // 取消之前的计时器
            notifierInstance.progressBarTapTimer?.cancel();

            if (currentCount >= 5) {
              // 达到 5 次，立即触发五击事件，不需要等待
              notifier.updateProgressBarTapCount(0);
              _showDebugOverlay();
            } else {
              notifier.updateProgressBarTapCount(currentCount);
              // 开启一个短的计时器（300ms），在没有新点击时触发
              notifierInstance.progressBarTapTimer = Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;

                // 300ms 后如果点击次数刚好为 2，说明是双击，触发双击逻辑
                if (ref.read(bdcNotifierProvider).progressBarTapCount == 2) {
                  PerformanceWatchdog.toggleFpsOverlay();
                  HapticFeedback.mediumImpact();
                }

                // 触发完成后清零计数器
                notifier.updateProgressBarTapCount(0);
              });
            }
          },
          child: Container(
            margin: EdgeInsets.fromLTRB(
                0, MediaQuery.of(context).padding.top + 8, 0, 0),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4), // 进一步减小垂直间距以整体上移下方元素
            child: Container(
              height: 3, // 从 6 改为 3
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1.5), // 从 3 改为 1.5
                color: _cachedIsDarkMode
                    ? const Color(0xFF2C2C2C)
                    : const Color(0xFFF0F2F5),
              ),
              child: state.currentGetWordResult?.progress != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final maxValue =
                            state.currentGetWordResult!.progress![1].toDouble();
                        final width = constraints.maxWidth;

                        // 计算批次颜色：从红色(0) -> 蓝色(0.5) -> 绿色(1.0) 渐变
                        // 根据白天/黑夜模式调整基础透明度
                        final bool isDarkMode =
                            _cachedIsDarkMode;
                        final double baseAlpha =
                            isDarkMode ? 0.25 : 0.15; // 黑夜模式稍明显一点，白天模式更淡

                        // 获取批次的基础颜色（不透明度）
                        // 修改：所有批次都使用最后一个批次的颜色（绿色）
                        Color getBatchBaseColor(
                            int batchIndex, int totalBatches) {
                          return isDarkMode
                              ? Colors.white
                              : const Color(0xFF1A1A1A);
                        }

                        Color getBatchColor(int batchIndex, int totalBatches) {
                          // 所有批次都使用统一的半透明绿色作为背景色
                          return getBatchBaseColor(batchIndex, totalBatches)
                              .withValues(alpha: baseAlpha);
                        }

                        // 计算批次数量（基于单词数量，每批次10个单词）
                        final modeCount = state.activeUserStudySteps.length;

                        // 【根本原因修复】检查 modeCount 和 maxValue 是否有效
                        // 如果学习步骤未配置或进度数据无效，不渲染进度条
                        if (modeCount <= 0 || maxValue <= 0 || width <= 0) {
                          return const SizedBox.shrink();
                        }

                        final wordCount = (maxValue / modeCount).ceil();
                        final batchWordCount = 10;
                        final totalBatches =
                            max(1, (wordCount / batchWordCount).ceil());

                        // 计算当前进度所在的批次索引
                        final currentProgress =
                            state.currentGetWordResult!.progress![0].toDouble();
                        // 当前步进对应的单词索引
                        final currentWordIndex = min(
                            (currentProgress / modeCount).floor(),
                            wordCount - 1);
                        final currentBatchIndex = min(
                            (currentWordIndex / batchWordCount).floor(),
                            totalBatches - 1);
                        // 获取当前批次的鲜艳颜色作为进度条前景色
                        final progressColor =
                            getBatchBaseColor(currentBatchIndex, totalBatches);

                        return Stack(
                          children: [
                            // 批次背景色层（基于单词批次）
                            Row(
                              children: List.generate(totalBatches, (index) {
                                final isLastBatch = index == totalBatches - 1;
                                // 计算该批次包含的单词数
                                final startWordIndex = index * batchWordCount;
                                final endWordIndex = min(
                                    (index + 1) * batchWordCount, wordCount);
                                final batchWords =
                                    endWordIndex - startWordIndex;
                                // 转换为进度条宽度（乘以模式数）
                                final batchSteps = batchWords * modeCount;
                                final batchWidth =
                                    (batchSteps / maxValue) * width;
                                return Container(
                                  width: batchWidth,
                                  decoration: BoxDecoration(
                                    color: getBatchColor(index, totalBatches),
                                    borderRadius: BorderRadius.horizontal(
                                      left: index == 0
                                          ? const Radius.circular(1.5)
                                          : Radius.zero,
                                      right: isLastBatch
                                          ? const Radius.circular(1.5)
                                          : Radius.zero,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            ClipRRect(
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(1.5)),
                              child: ValueListenableBuilder<double>(
                                valueListenable: PerformanceWatchdog.jankHeat,
                                builder: (context, heat, child) {
                                  final actualColor = Color.lerp(progressColor, Colors.red, heat)!;
                                  return FAProgressBar(
                                    borderRadius:
                                        const BorderRadius.all(Radius.circular(1.5)),
                                    currentValue: currentProgress,
                                    maxValue: maxValue,
                                    displayText: '',
                                    direction: Axis.horizontal,
                                    displayTextStyle: const TextStyle(
                                        color: Color(0x00000000), fontSize: 0),
                                    backgroundColor: Colors.transparent,
                                    progressColor: actualColor,
                                    animatedDuration:
                                        const Duration(milliseconds: 300),
                                  );
                                },
                              ),
                            ),
                            // 批次分隔线（只在批次边界处显示）
                            if (totalBatches > 1)
                              ...List.generate(totalBatches - 1, (index) {
                                // 计算批次边界对应的进度位置
                                final boundaryWordIndex =
                                    (index + 1) * batchWordCount;
                                final boundaryStep =
                                    boundaryWordIndex * modeCount;
                                final left = (boundaryStep / maxValue) * width;
                                // 只有当计算出的位置在进度条范围内时才显示
                                if (left <= 0 || left >= width) {
                                  return const SizedBox.shrink();
                                }
                                return Positioned(
                                  left: left,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1.5,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
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
                    : (_cachedIsDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.08));
                final textColor = isLowFps ? Colors.white : (_cachedIsDarkMode ? Colors.white60 : Colors.black54);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        // 顶部按钮和题目区之间的间距
        const SizedBox(height: 8),
        // 题目区 - 使用flex=1
        Expanded(
          flex: 1,
          child: Consumer(
            builder: (context, ref, child) {
              // 物理隔离：只监听会影响卡片渲染的核心状态
              final wordId = ref.watch(bdcNotifierProvider.select((s) => s.word?.id));
              final historyIndex = ref.watch(bdcNotifierProvider.select((s) => s.historyIndex));
              final showSentenceTranslation = ref.watch(bdcNotifierProvider.select((s) => s.showSentenceTranslation));
              final isEditMode = ref.watch(bdcNotifierProvider.select((s) => s.isEditMode));
              final wordPlaying = ref.watch(bdcNotifierProvider.select((s) => s.playingStates['word'] ?? false));
              final sentencePlaying = ref.watch(bdcNotifierProvider.select((s) => s.playingStates['sentence'] ?? false));
              final imagesLength = ref.watch(bdcNotifierProvider.select((s) => s.currentGetWordResult?.images?.length ?? 0));
              final highlightedWordImg = ref.watch(bdcNotifierProvider.select((s) => s.highlightedWordImg));

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
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: Container(
                  key: ValueKey('word_card_${wordId}_$historyIndex'),
                  child: _buildQuestionContent(currentState.copyWith(
                    showSentenceTranslation: showSentenceTranslation,
                    isEditMode: isEditMode,
                    playingStates: {'word': wordPlaying, 'sentence': sentencePlaying},
                    highlightedWordImg: highlightedWordImg,
                  )),
                ),
              );
            },
          ),
        ),
        // 题目区和做题区之间的统一间距
        SizedBox(height: BdcPageState._questionAnswerGap),
        // 做题区 - 使用flex=1
        Expanded(
          flex: 1,
          child: Consumer(
            builder: (context, ref, child) {
              final wordId = ref.watch(bdcNotifierProvider.select((s) => s.word?.id));
              final historyIndex = ref.watch(bdcNotifierProvider.select((s) => s.historyIndex));
              
              return Container(
                key: ValueKey('bdc_choice_area_${wordId}_$historyIndex'),
                // 做题区背景色 - 浅绿色调
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: _showBorders
                      ? Border.all(
                          color: Colors.blue,
                          width: 10,
                        )
                      : null,
                ),
                padding: const EdgeInsets.fromLTRB(BdcPageState.leftPadding, 0, BdcPageState.rightPadding, 0),
                child: (state.showAnswerButtons ||
                        state.studyStep == StudyStep.en2Ch.json ||
                        state.studyStep == StudyStep.ch2En.json ||
                        state.studyStep == StudyStep.enSentence2Ch.json ||
                        state.studyStep == StudyStep.chSentence2En.json ||
                        state.studyStep == StudyStep.list.json)
                    ? Column(
                        children: [
                          if (state.studyStep == StudyStep.en2Ch.json ||
                              state.studyStep == StudyStep.ch2En.json) ...[
                            _buildTabBar(),
                            const SizedBox(height: 8),
                          ],
                          Expanded(
                            child: (state.studyStep == StudyStep.en2Ch.json ||
                                    state.studyStep == StudyStep.ch2En.json)
                                ? TabBarView(
                                    key: ValueKey('bdc_tab_bar_view_${_tabController?.length}'),
                                    controller: _tabController,
                                    physics: const NeverScrollableScrollPhysics(),
                                    children: [
                                      // 始终保持 Tab 数量一致性，避免抖动
                                      if (_tabController?.length == 2) _buildSpeakPanel(),
                                      SingleChildScrollView(
                                        key: const ValueKey('bdc_choice_list_scroll_view'),
                                        physics: const BouncingScrollPhysics(),
                                        child: _buildChoiceList(),
                                      ),
                                    ],
                                  )
                                : (state.studyStep == StudyStep.enSentence2Ch.json ||
                                       state.studyStep == StudyStep.chSentence2En.json)
                                    ? _buildSpeakPanel()
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Flexible(
                                            child: SingleChildScrollView(
                                              physics: const BouncingScrollPhysics(),
                                              child: _buildChoiceList(),
                                            ),
                                          ),
                                          Expanded(child: _buildSpeakPanel()),
                                        ],
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
    final result = Container(
      key: _bottomButtonsKey,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 对测评结果进行展示（即便在极速模式下也展示一下，方便用户看下评分情况）
          _buildFsrsResultPanel(),
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
    debugPrint('⚡ [PERF] _buildBottomButtons cost: ${sw.elapsedMilliseconds}ms');
    return result;
  }

  Widget _buildRatingButtonsRow() {
    final bool isSentence = state.studyStep == StudyStep.enSentence2Ch.json ||
        state.studyStep == StudyStep.chSentence2En.json;
    final recognizedText = state.currentAsrCandidates.isNotEmpty
        ? state.currentAsrCandidates.first
        : '';
    final hasInput = recognizedText.trim().isNotEmpty ||
        notifier.meaningController.text.trim().isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (isSentence && !state.hasFinishedAnswering && hasInput) ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.gavel_rounded, size: 18),
            label: const Text('AI裁判', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => notifier.evaluateWithAiReferee(context),
          ),
          const SizedBox(width: 12),
        ],
        if (state.showAnswerButtons ||
            state.studyStep == StudyStep.en2Ch.json ||
            state.studyStep == StudyStep.ch2En.json ||
            state.studyStep == StudyStep.enSentence2Ch.json ||
            state.studyStep == StudyStep.chSentence2En.json ||
            state.studyStep == StudyStep.list.json)
          AbsorbPointer(
            absorbing: !state.buttonsEnabled,
            child: ElevatedButton(
              key: const Key('bdc_not_know_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cachedIsDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFF5F5F5),
                foregroundColor: _cachedIsDarkMode
                    ? Colors.white70
                    : const Color(0xFF666666),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => notifier.showWordDetail(state.word!, true, context,
                  fsrsRating: FsrsRating.again, reason: "主动点击了不再认识，评分: 忘记"),
              child: const Text('不认识',
                  style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        if (state.showAnswerButtons ||
            state.studyStep == StudyStep.en2Ch.json ||
            state.studyStep == StudyStep.ch2En.json ||
            state.studyStep == StudyStep.enSentence2Ch.json ||
            state.studyStep == StudyStep.chSentence2En.json ||
            state.studyStep == StudyStep.list.json) ...[
          const SizedBox(width: 12),
          AbsorbPointer(
            absorbing: !state.buttonsEnabled,
            child: ElevatedButton(
              key: const Key('bdc_study_again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cachedIsDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFF5F5F5),
                foregroundColor: _cachedIsDarkMode
                    ? Colors.white70
                    : const Color(0xFF666666),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => notifier.showWordDetail(state.word!, false, context,
                  fsrsRating: FsrsRating.good, reason: "主动点击了再学学，评分: 良好"),
              child: const Text('再学学',
                  style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        ],
        if (state.canLeaveCurrWord) ...[
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _cachedIsDarkMode
                  ? Colors.white
                  : AppTheme.primaryColor,
              foregroundColor: _cachedIsDarkMode
                  ? Colors.black
                  : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: state.isGettingNextWord
                ? null
                : () =>
                    notifier.getNextWord(true, fsrsRating: state.lastFsrsRating),
            child: const Text('下一词',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }


  Widget _buildTopActionButton({
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    final isDarkMode = _cachedIsDarkMode;

    return Container(
      height: 32, // 恢复原高度
      width: label != null ? null : 32, // 对于无标签的按钮，设置固定宽度形成圆形
      padding: EdgeInsets.symmetric(
        horizontal: label != null ? 8 : 4, // 调整无标签按钮的水平内边距
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
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
                color: isDarkMode ? Colors.white70 : const Color(0xFF333333),
                size: 14,
              ),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label,
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color:
                        isDarkMode ? Colors.white70 : const Color(0xFF333333),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildTopButtonsRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), // 完全移除顶部向上的 padding，让按钮更加贴着进度条
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 返回按钮
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _cachedIsDarkMode
                  ? const Color(0xFF2C2C2C)
                  : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _cachedIsDarkMode
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (state.currentGetWordResult != null && state.currentGetWordResult!.progress != null && state.currentGetWordResult!.progress!.length >= 2) {
                    final completed = state.currentGetWordResult!.progress![0];
                    final total = state.currentGetWordResult!.progress![1];
                    AnalyticsUtil.trackStudyQuitEarly(completed, total - completed);
                  }
                  Navigator.pop(context);
                },
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: _cachedIsDarkMode
                      ? Colors.white70
                      : const Color(0xFF333333),
                  size: 18,
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
                    icon: Icons.keyboard_return,
                    label: '返回',
                    onTap: () => notifier.exitReviewMode(),
                  )
                else if (state.history.isNotEmpty)
                  _buildTopActionButton(
                    icon: Icons.skip_previous_outlined,
                    label: '回看',
                    onTap: () => notifier.goToPreviousWord(),
                  ),

                // 已掌握按钮
                _buildTopActionButton(
                  icon: Icons.check_circle_outline,
                  label: '掌握',
                  onTap: () {
                    notifier.updateHasFinishedAnswering(true);
                    notifier.updateIsWordMastered(true);
                    ToastUtil.info("不再学习 ${state.word!.spell}");
                    notifier.getNextWord(true);
                  },
                ),

                // 编辑开关 - 仅在meaning模式下且非Web平台显示

                // 报错按钮
                _buildTopActionButton(
                  icon: Icons.report_problem_outlined,
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


  Widget _buildAnswerContent(String text) {
    if (text.isEmpty) return const SizedBox();

    final isDarkMode = _cachedIsDarkMode;
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
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$ciXing ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color:
                        isDarkMode ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
                TextSpan(
                  text: notifier.hideAnswerLeakContent(meaning),
                  style: TextStyle(
                    fontFamily: "NotoSansSC",
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Text(
            line,
            style: TextStyle(
              fontFamily: "NotoSansSC",
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: isDarkMode ? Colors.white : const Color(0xFF2D3748),
            ),
          ),
        );
      }

      // 添加行间距（除了最后一行）
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


  Widget _buildChoiceList() {
    if (!(state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (var index = 0; index < (state.words?.length ?? 0); index++)
          Builder(
            builder: (context) {
              Color bgColor;
              Color borderColor;
              final isDarkMode = _cachedIsDarkMode;

              if (state.selectedAnswerIndex != null) {
                if ((index + 1) == state.correctAnswerIndex) {
                  bgColor = Colors.green.withValues(alpha: isDarkMode ? 0.25 : 0.15);
                  borderColor = Colors.green;
                } else if ((index + 1) == state.selectedAnswerIndex) {
                  bgColor = Colors.red.withValues(alpha: isDarkMode ? 0.25 : 0.15);
                  borderColor = Colors.red;
                } else {
                  bgColor = isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA);
                  borderColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
                }
              } else {
                bgColor = isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFF8F9FA);
                borderColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
              }

              return Padding(
                padding: state.studyStep == StudyStep.ch2En.json
                    ? const EdgeInsets.symmetric(vertical: 3)
                    : const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => notifier.onAnswerClicked(index + 1, context),
                        child: Stack(
                          children: [
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 300),
                          crossFadeState: state.flippedAnswerIndices.contains(index)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: _buildAnswerContent(
                              state.studyStep == StudyStep.ch2En.json
                                  ? (state.words?[index].spell.isNotEmpty == true ? state.words![index].spell : '无对应英文')
                                  : (state.words?[index].getMeaningStr().isNotEmpty == true ? state.words![index].getMeaningStr() : '无对应释义'),
                            ),
                          ),
                          secondChild: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: _buildAnswerContent(
                              state.studyStep == StudyStep.ch2En.json
                                  ? (state.words?[index].getMeaningStr().isNotEmpty == true ? state.words![index].getMeaningStr() : '无对应释义')
                                  : (state.words?[index].spell.isNotEmpty == true ? state.words![index].spell : '无对应英文'),
                            ),
                          ),
                        ),
                            if ((state.hasFinishedAnswering || state.selectedAnswerIndex != null) &&
                                (state.words?[index].spell != "[ 都不对 ]"))
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(
                                  Icons.sync,
                                  size: 16,
                                  color: isDarkMode ? Colors.white30 : Colors.black26,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶栏：音频波纹 + 提示/清除按钮 (固定浮动在上方)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _cachedIsDarkMode
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFF8F9FA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(
              color: _cachedIsDarkMode
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.03),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 语音波形反馈
              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final currentAsrState = ref.watch(bdcNotifierProvider.select((s) => s.asrState));
                    final currentScore = ref.watch(bdcNotifierProvider.select((s) => s.currentScore));
                    
                    final bool isChineseInput = state.studyStep == StudyStep.en2Ch.json ||
                                                state.studyStep == StudyStep.enSentence2Ch.json;
                    final bool isSentence = state.studyStep == StudyStep.enSentence2Ch.json ||
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
                            isSentenceStep: isSentence,
                          )
                        : EnglishAsrInputWidget(
                            controller: notifier.meaningController,
                            asrState: currentAsrState,
                            onStartAsr: (language) =>
                                notifier.asr.startAsr(language),
                            isKeyboardVisible: state.isKeyboardVisible,
                            focusNode: _meaningFocusNode,
                            score: currentScore,
                            isSentenceStep: isSentence,
                          );
                  },
                ),
              ),

              const SizedBox(width: 8),
              if (isSentence)
                _buildPanelButton(
                  icon: Icons.refresh,
                  label: '清空',
                  onTap: () => notifier.clearHint(),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPanelButton(
                      icon: Icons.emoji_objects_rounded,
                      label: '提示',
                      onTap: () => notifier.giveALittleHint(),
                      onLongPress: () => notifier.giveFullHint(),
                    ),
                    const SizedBox(width: 6),
                    _buildPanelButton(
                      icon: Icons.refresh,
                      label: '清除',
                      onTap: () => notifier.clearHint(),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // 2. 滚动区域：中文释义 / 拼写提示
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: _cachedIsDarkMode
                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.8)
                  : const Color(0xFFF8F9FA).withValues(alpha: 0.8),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(
                left: BorderSide(
                    color: _cachedIsDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
                right: BorderSide(
                    color: _cachedIsDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
                bottom: BorderSide(
                    color: _cachedIsDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03)),
              ),
            ),
            child: SingleChildScrollView(
              controller: _speakPanelScrollController,
              physics: state.showHandwritingBoard
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: EdgeInsets.zero,
              child: () {
                final step = state.studyStep;
                if (step == StudyStep.enSentence2Ch.json) {
                  final recognizedText = state.currentAsrCandidates.isNotEmpty ? state.currentAsrCandidates.first : '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请说出对应的中文翻译：',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cachedIsDarkMode
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      if (recognizedText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                recognizedText,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _cachedIsDarkMode ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ),
                            if (state.hasFinishedAnswering &&
                                (state.lastFsrsRatingReason?.contains("AI裁判") ?? false)) ...[
                              const SizedBox(width: 8),
                              Container(
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
                            ],
                          ],
                        ),
                      ],
                      if (state.aiRefereeFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gavel_rounded, color: Colors.orange.shade600, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  state.aiRefereeFeedback!,
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                } else if (step == StudyStep.chSentence2En.json) {
                  final recognizedText = state.currentAsrCandidates.isNotEmpty ? state.currentAsrCandidates.first : '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请读出对应的英文例句：',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cachedIsDarkMode
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      if (recognizedText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Util.makeEnglishSpanText(
                                recognizedText,
                                state.word?.spell ?? '',
                                false,
                                context,
                                false,
                                null,
                                false,
                                FontWeight.w400,
                                fontSize: 14,
                                color: _cachedIsDarkMode ? Colors.white60 : Colors.black54,
                              ),
                            ),
                            if (state.hasFinishedAnswering &&
                                (state.lastFsrsRatingReason?.contains("AI裁判") ?? false)) ...[
                              const SizedBox(width: 8),
                              Container(
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
                            ],
                          ],
                        ),
                      ],
                      if (state.aiRefereeFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gavel_rounded, color: Colors.orange.shade600, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  state.aiRefereeFeedback!,
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                } else if (step == StudyStep.en2Ch.json) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...renderAsrMeaningItems(state.wordWrapper!,
                          isDarkMode: context.read<DarkMode>().isDarkMode),
                      const SizedBox(height: 16),
                      _buildSpellingExerciseButton(isDarkMode),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '说出单词发音 或 直接拼写：',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _cachedIsDarkMode
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSpellingExerciseButton(isDarkMode),
                    ],
                  );
                }
              }(),
            ),
          ),
        ),
      ],
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

  Widget _buildSpellingExerciseButton(bool isDarkMode) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            notifier.updateIsUpdatingByHint(true);
            notifier.meaningController.clear();
            notifier.updateIsUpdatingByHint(false);
            updateUI(() {
              notifier.updateShowHandwritingBoard(true);
            }, tag: 'hw-open');
            // 进入手势拼写模式前，务必强制彻底停止 ASR 会话，避免在手写时后台仍在倾听或产生提示音
            notifier.asr.stopMicrophone();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: _cachedIsDarkMode
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note,
                    color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: notifier.meaningController,
                    builder: (context, value, child) {
                      final text = value.text;
                      return text.isEmpty
                          ? Text(
                              '拼写练习',
                              style: TextStyle(
                                fontSize: 18,
                                color: (isDarkMode ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.2),
                                fontWeight: FontWeight.normal,
                              ),
                            )
                          : RichText(
                              text: TextSpan(
                                children: [
                                  SpellingTextEditingController
                                      .buildSpellingTextSpan(
                                    text,
                                    state.word?.spell ?? "",
                                    text.trim().toLowerCase() !=
                                            (state.word?.spell.toLowerCase() ?? "")
                                        ? Colors.red
                                        : (isDarkMode ? Colors.white : Colors.black),
                                    const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  if (text.length < (state.word?.spell.length ?? 0))
                                    TextSpan(
                                      text:
                                          ' ${_buildUnderlines(state.word?.spell ?? "", text.length)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? Colors.white30
                                            : Colors.black26,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                ],
                              ),
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }


  Widget _buildFsrsResultPanel() {
    final isDarkMode = _cachedIsDarkMode;
    final textColor = isDarkMode ? Colors.white38 : Colors.black38;

    if (!state.hasFinishedAnswering || state.fsrsItem == null) {
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
                  Color assColor;
                  switch (assRating) {
                    case FsrsRating.again:
                      assColor = isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F);
                      break;
                    case FsrsRating.hard:
                      assColor = isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00);
                      break;
                    case FsrsRating.easy:
                      assColor = isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32);
                      break;
                    case FsrsRating.good:
                      assColor = isDarkMode ? AppTheme.primaryColor : AppTheme.primaryColor;
                      break;
                  }
                  return Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '[巩固] 今日测评: $assLabel',
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
                return Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '[巩固] 今日测评: 测评中',
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor,
                          ),
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
            Color ratingColor;
            switch (rating) {
              case FsrsRating.again:
                ratingColor =
                    isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F);
                break;
              case FsrsRating.hard:
                ratingColor =
                    isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00);
                break;
              case FsrsRating.easy:
                ratingColor =
                    isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32);
                break;
              case FsrsRating.good:
                ratingColor =
                    isDarkMode ? AppTheme.primaryColor : AppTheme.primaryColor;
                break;
            }

            return Container(
              padding: const EdgeInsets.only(bottom: 8),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '[巩固] 今日测评: $ratingLabel',
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
                              color: isDarkMode ? Colors.white70 : Colors.black54,
                              fontWeight: FontWeight.bold,
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

      return Container(
        padding: const EdgeInsets.only(bottom: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '[测评] 今日测评: 测评中',
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('|',
                    style: TextStyle(
                        fontSize: 10, color: textColor.withValues(alpha: 0.3))),
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

    // 获取本次操作的评估标签和颜色
    String ratingLabel = state.lastFsrsRating?.label ?? '未知';
    Color ratingColor;

    switch (state.lastFsrsRating) {
      case FsrsRating.again:
        ratingColor =
            isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F); // 深红色
        break;
      case FsrsRating.hard:
        ratingColor =
            isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00); // 橘色
        break;
      case FsrsRating.easy:
        ratingColor =
            isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32); // 深绿色
        break;
      case FsrsRating.good:
      default:
        ratingColor =
            isDarkMode ? AppTheme.primaryColor : AppTheme.primaryColor;
        break;
    }

    String stageText = (state.currentGetWordResult != null && state.currentGetWordResult!.stepIndex > 0) ? '[巩固] ' : '[测评] ';
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
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
                child: Row(
                  children: [
                    Text(
                      '$stageText今日测评: $ratingLabel',
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
                      fontSize: 10, color: textColor.withValues(alpha: 0.3))),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: '下次复习: ',
                      style: TextStyle(fontSize: 11, color: textColor)),
                  TextSpan(
                    text: '${state.fsrsItem!.scheduledDays}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                      text: '天后',
                      style: TextStyle(fontSize: 11, color: textColor)),
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color:
              isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDarkMode
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildPhoneticRow(BdcState state) {
    if (!(state.currentGetWordResult?.learningWord?.word != null &&
        state.studyStep != StudyStep.en2Ch.json)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cachedIsDarkMode
            ? const Color(0xFF2C2C2C)
            : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (state.studyStep != StudyStep.ch2En.json)
            Flexible(
              child: Text(
                Util.getWordDefaultPronounce(
                            state.currentGetWordResult!.learningWord!.word)
                        .isEmpty
                    ? ''
                    : '[${Util.getWordDefaultPronounce(state.currentGetWordResult!.learningWord!.word)}]',
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
          if (state.studyStep != StudyStep.ch2En.json)
            buildWordSoundButton(
                state.currentGetWordResult!.learningWord!.word, _audioPlayer, state),
        ],
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cachedIsDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧极简播放前缀按钮
          buildSentenceSoundButton(state),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3), // 微调使文本与左侧图标对齐
              child: Util.makeEnglishSpanText(
                  state.word!.sentences![0].english!,
                  state.word!.spell,
                  true,
                  context,
                  false,
                  null,
                  true,
                  FontWeight.w300),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildEnSentenceStepCard(BdcState state) {
    final isDarkMode = _cachedIsDarkMode;
    final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
        ? state.word!.sentences!.first
        : null;
    final sentenceText = sentence?.english ?? "No sentence available";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Util.makeEnglishSpanText(
              sentenceText,
              state.word?.spell ?? '',
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.volume_up_rounded,
                  color: isDarkMode ? const Color(0xFF22D3EE) : AppTheme.primaryColor,
                  size: 28,
                ),
                onPressed: () {
                  notifier.playWordAndFirstSentence(false, false, forcePlaySentence: true);
                },
              ),
            ],
          ),
          if (!state.hasFinishedAnswering) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(
                Icons.visibility_outlined,
                size: 16,
                color: isDarkMode ? Colors.black : Colors.white,
              ),
              label: Text(
                "看答案",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.black : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.white : AppTheme.primaryColor,
                foregroundColor: isDarkMode ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                notifier.revealAnswerAndMarkWrong(context);
              },
            ),
          ],
          if (state.hasFinishedAnswering && sentence != null) ...[
            const SizedBox(height: 12),
            Util.makeChineseSpanText(
              sentence.chinese ?? '',
              context,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChSentenceStepCard(BdcState state) {
    final isDarkMode = _cachedIsDarkMode;
    final sentence = (state.word?.sentences != null && state.word!.sentences!.isNotEmpty)
        ? state.word!.sentences!.first
        : null;
    final translationText = sentence?.chinese ?? "暂无例句翻译";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Util.makeChineseSpanText(
              translationText,
              context,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (!state.hasFinishedAnswering) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(
                Icons.visibility_outlined,
                size: 16,
                color: isDarkMode ? Colors.black : Colors.white,
              ),
              label: Text(
                "看答案",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.black : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.white : AppTheme.primaryColor,
                foregroundColor: isDarkMode ? Colors.black : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                notifier.revealAnswerAndMarkWrong(context);
              },
            ),
          ],
          if (state.hasFinishedAnswering && sentence != null) ...[
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
              color: isDarkMode ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildWordStepCard(BdcState state) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    key: const Key('currentstate.word_spell'),
                    state.currentGetWordResult!.learningWord!.word.spell,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 36,
                      color: _cachedIsDarkMode
                          ? Colors.white
                          : const Color(0xFF1A1A1A),
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
                    Flexible(
                      child: Text(
                        Util.getWordDefaultPronounce(
                                    state.currentGetWordResult!.learningWord!.word)
                                .isEmpty
                            ? ''
                            : '[${Util.getWordDefaultPronounce(state.currentGetWordResult!.learningWord!.word)}]',
                        style: TextStyle(
                          color: _cachedIsDarkMode
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFF4B5563),
                          fontFamily: "NotoSans",
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    buildWordSoundButton(
                        state.currentGetWordResult!.learningWord!.word,
                        _audioPlayer,
                        state),
                  ],
                ),
                if (state.studyStep == StudyStep.list.json) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.word?.getMeaningStr() ?? '',
                    style: TextStyle(
                      fontSize: 16,
                      color: _cachedIsDarkMode
                          ? Colors.white70
                          : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (state.word?.sentences != null &&
                    state.word!.sentences!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧极简播放前缀按钮
                      buildSentenceSoundButton(state),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3), // 微调使第一行文本与左侧图标对齐
                              child: Util.makeEnglishSpanText(
                                  state.word!.sentences![0].english!,
                                  state.word!.spell,
                                  true,
                                  context,
                                  false,
                                  null,
                                  true,
                                  FontWeight.w300),
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
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      '显示翻译',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Util.makeChineseSpanText(
                                  state.word!.sentences![0].chinese ?? '',
                                  context,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _cachedIsDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                          ],
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


  Widget _buildMeaningStepCard(BdcState state) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [

          // 释义/图片/配图按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 释义
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0;
                          i <
                              state.currentGetWordResult!.learningWord!.word
                                  .getMergedMeaningItems()
                                  .length;
                          i++)
                        Padding(
                          padding: EdgeInsets.only(
                              right: i ==
                                      state.currentGetWordResult!.learningWord!.word
                                              .getMergedMeaningItems()
                                              .length -
                                          1
                                  ? 0
                                  : 4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                state.currentGetWordResult!.learningWord!.word
                                        .getMergedMeaningItems()[i]
                                        .ciXing ??
                                    '',
                                style: const TextStyle(
                                    color: Color(0xFF999999),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                notifier.hideParenthesesContent(state.currentGetWordResult!
                                        .learningWord!.word
                                        .getMergedMeaningItems()[i]
                                        .meaning ??
                                    ''),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _cachedIsDarkMode
                                      ? Colors.white
                                      : const Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // 图片 (仅对管理员开放)
                if (StudyConfig.fromCurrentUser().enableWordImage &&
                    (Global.getLoggedInUser()?.isAdmin == true) &&
                    state.currentGetWordResult?.images != null &&
                    state.currentGetWordResult!.images!.isNotEmpty)
                  Column(
                    children: [
                      if (state.currentGetWordResult!.images!.isNotEmpty &&
                          state.studyStep != StudyStep.ch2En.json)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                          showImagePreviewWithContext(context, image,
                              onDeleted: () {
                            state.currentGetWordResult?.images
                                ?.removeWhere((e) => e.id == image.id);
                            updateUI(() {}, tag: 'img-delete');
                          });
                        },
                      ),
                    ],
                  ),
                // 配图按钮
                if (StudyConfig.fromCurrentUser().enableWordImage && state.isEditMode && (state.currentGetWordResult?.learningWord?.word.images?.length ?? 0) < 2)
                  InkWell(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 24.0),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: _cachedIsDarkMode
                              ? Colors.black
                              : Colors.white,
                          backgroundColor: _cachedIsDarkMode
                              ? Colors.white
                              : AppTheme.primaryColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        label: const Text('添加配图'),
                        onPressed: () {
                          if (state.currentGetWordResult?.learningWord?.word.id !=
                              null) {
                            context.push('/pic_search',
                                    extra: PicSearchPageArgs(
                                        state.currentGetWordResult!
                                            .learningWord!.word.id!,
                                        state.currentGetWordResult!
                                            .learningWord!.word.spell))
                                .then((value) => notifier.reloadWord());
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


  Widget buildWordSoundButton(WordVo word, dynamic audioPlayer, BdcState state) {
    final wordPlaying = state.playingStates['word'] ?? false;

    // 统一使用极简扁平无边框设计
    return Transform.translate(
      offset: const Offset(2.0, 0.0), // 适度右移微调，优化视觉对齐
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!wordPlaying) {
            notifier.playWithAnimation(
                () => StudyAudioSessionController.instance.playWordSound(word),
                'word');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: AnimatedBuilder(
            animation: _wordSoundController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_wordSoundController.value < 0.5 ? 0 : -2, 0), // 发音波纹微晃动位移
                child: Icon(
                  wordPlaying
                      ? (_wordSoundController.value < 0.5
                          ? Icons.volume_up
                          : Icons.volume_down)
                      : Icons.volume_up,
                  color: wordPlaying
                      ? Colors.teal[300]
                      : Colors.grey[500],
                  size: 22,
                ),
              );
            },
          ),
        ),
      ),
    );
  }


  Widget buildSentenceSoundButton(BdcState state) {
    final sentencePlaying = state.playingStates['sentence'] ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (!sentencePlaying &&
            state.englishDigestOfFirstSentence != null) {
          notifier.playWithAnimation(
              () => StudyAudioSessionController.instance.playSentenceSound(
                  state.englishDigestOfFirstSentence!),
              'sentence');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: AnimatedBuilder(
          animation: _sentenceSoundController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_sentenceSoundController.value < 0.5 ? 0 : -2, 0), // 发音微晃动动画位移
              child: Icon(
                sentencePlaying
                    ? (_sentenceSoundController.value < 0.5
                        ? Icons.volume_up
                        : Icons.volume_down)
                    : Icons.volume_up_outlined, // 默认使用更精致的空心发音图标
                color: sentencePlaying
                    ? Colors.teal[300]
                    : Colors.grey[500],
                size: 20,
              ),
            );
          },
        ),
      ),
    );
  }
}
