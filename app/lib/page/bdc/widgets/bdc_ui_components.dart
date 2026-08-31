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
      decoration: const BoxDecoration(
        color: Colors.transparent,
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
          ],
        ),
      ),
    );
  }


  Widget _buildTabBar() {
    if (_tabController == null || _tabController!.length <= 1) {
      return const SizedBox.shrink();
    }
    final isDarkMode = _cachedIsDarkMode;

    return Center(
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
            width: 1,
          ),
        ),
        child: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.06),
                blurRadius: 6,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          dividerColor: Colors.transparent,
          dividerHeight: 0,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          labelColor: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
          unselectedLabelColor: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5B7A75),
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          tabs: notifier.dynamicTabs,
          onTap: (index) {
            ref.read(bdcNotifierProvider.notifier).updateTabIndex(index);
          },
        ),
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

                        // 计算批次数量（基于单词数量，每批次10个单词）。
                        // 三组结构下学习轨道默认 5 个环节（测评+3巩固+List），用于近似单词数换算。
                        const int modeCount = 5;

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
                                final startWordIndex = index * batchWordCount;
                                final endWordIndex = min(
                                    (index + 1) * batchWordCount, wordCount);
                                final batchWords =
                                    max(1, endWordIndex - startWordIndex);
                                return Expanded(
                                  flex: batchWords,
                                  child: Container(
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
        // 题目区 - 保持固定匀称比例（4:5）
        Expanded(
          flex: 4,
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
        // 做题区 - 答题后适度分配更多空间（flex=5）
        Expanded(
          flex: 5,
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
    final isDarkMode = _cachedIsDarkMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
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
                backgroundColor: isDarkMode
                    ? const Color(0xFF192C27)
                    : const Color(0xFFEDF5F2),
                foregroundColor: isDarkMode
                    ? const Color(0xFFEAF7F4)
                    : const Color(0xFF425B57),
                side: BorderSide(
                  color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
                  width: 1,
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => notifier.showWordDetail(state.word!, true, context,
                  fsrsRating: FsrsRating.again, reason: "主动点击了不再认识，评分: 忘记"),
              child: const Text(
                '不认识',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
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
                backgroundColor: isDarkMode
                    ? const Color(0xFF192C27)
                    : const Color(0xFFEDF5F2),
                foregroundColor: isDarkMode
                    ? const Color(0xFFEAF7F4)
                    : const Color(0xFF425B57),
                side: BorderSide(
                  color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
                  width: 1,
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => notifier.showWordDetail(state.word!, false, context,
                  fsrsRating: FsrsRating.good, reason: "主动点击了再学学，评分: 良好"),
              child: const Text(
                '再学学',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ),
          ),
        ],
        if (state.canLeaveCurrWord) ...[
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              shadowColor: AppTheme.primaryColor.withValues(alpha: 0.35),
            ),
            onPressed: state.isGettingNextWord
                ? null
                : () =>
                    notifier.getNextWord(true, fsrsRating: state.lastFsrsRating),
            child: const Text(
              '下一词',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
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
      height: 32,
      width: label != null ? null : 32,
      padding: EdgeInsets.symmetric(
        horizontal: label != null ? 9 : 0,
        vertical: 0,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode
              ? Colors.white12
              : const Color(0xFFD1EADE),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C),
                size: 14.5,
              ),
              if (label != null) ...[
                const SizedBox(width: 3.5),
                Text(
                  label,
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 圆形返回按钮
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (state.currentGetWordResult != null && state.currentGetWordResult!.progress != null && state.currentGetWordResult!.progress!.length >= 2) {
                  final completed = state.currentGetWordResult!.progress![0];
                  final total = state.currentGetWordResult!.progress![1];
                  AnalyticsUtil.trackStudyQuitEarly(completed, total - completed);
                }
                Navigator.pop(context);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cachedIsDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2),
                  border: Border.all(
                    color: _cachedIsDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _cachedIsDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                    size: 14,
                  ),
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
                    icon: Icons.keyboard_return_rounded,
                    label: '返回',
                    onTap: () => notifier.exitReviewMode(),
                  )
                else if (state.history.isNotEmpty)
                  _buildTopActionButton(
                    icon: Icons.skip_previous_rounded,
                    label: '回看',
                    onTap: () => notifier.goToPreviousWord(),
                  ),

                // 已掌握按钮
                _buildTopActionButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: '掌握',
                  onTap: () {
                    notifier.updateHasFinishedAnswering(true);
                    notifier.updateIsWordMastered(true);
                    ToastUtil.info("不再学习 ${state.word!.spell}");
                    notifier.getNextWord(true);
                  },
                ),

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


  Widget _buildSecondaryAnswerContent(WordVo? word, bool isCh2En) {
    if (word == null || word.spell == "[ 都不对 ]") return const SizedBox.shrink();
    final isDarkMode = _cachedIsDarkMode;

    if (isCh2En) {
      final text = word.getMeaningStr();
      if (text.isEmpty) return const SizedBox.shrink();
      final lines = text.split("\n");
      List<Widget> widgets = [];
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty) continue;
        final ciXingRegex = RegExp(r"^([a-z]+\.)");
        final match = ciXingRegex.firstMatch(line);
        if (match != null) {
          String ciXing = match.group(1)!;
          String meaning = line.substring(match.end);
          widgets.add(
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "$ciXing ",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                  TextSpan(
                    text: meaning,
                    style: TextStyle(
                      fontFamily: "NotoSansSC",
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode ? Colors.white70 : const Color(0xFF4A5568),
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
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4A5568),
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
    } else {
      final spell = word.spell;
      if (spell.isEmpty) return const SizedBox.shrink();
      final pronounce = word.pronounce;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            spell,
            style: TextStyle(
              fontFamily: "NotoSansSC",
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white70 : const Color(0xFF4A5568),
            ),
          ),
          if (pronounce != null && pronounce.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '/$pronounce/',
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.white38 : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      );
    }
  }

  Widget _buildChoiceList() {
    if (!(state.studyStep == StudyStep.en2Ch.json ||
        state.studyStep == StudyStep.ch2En.json)) {
      return const SizedBox.shrink();
    }

    final isAnswered = state.selectedAnswerIndex != null || state.hasFinishedAnswering;
    final isCh2En = state.studyStep == StudyStep.ch2En.json;

    return Column(
      children: [
        for (var index = 0; index < (state.words?.length ?? 0); index++)
          Builder(
            builder: (context) {
              Color bgColor;
              Color borderColor;
              double borderWidth = 1.0;
              final isDarkMode = _cachedIsDarkMode;
              final word = state.words?[index];
              final isNoneOfAbove = word?.spell == "[ 都不对 ]";

              if (state.selectedAnswerIndex != null) {
                if ((index + 1) == state.correctAnswerIndex) {
                  bgColor = isDarkMode ? const Color(0xFF152B24) : const Color(0xFFE8F8F1);
                  borderColor = isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C);
                  borderWidth = 1.5;
                } else if ((index + 1) == state.selectedAnswerIndex) {
                  bgColor = isDarkMode ? const Color(0xFF2A1614) : const Color(0xFFFEF2F0);
                  borderColor = isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFFA6E59);
                  borderWidth = 1.5;
                } else {
                  bgColor = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
                  borderColor = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
                }
              } else {
                bgColor = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
                borderColor = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => notifier.onAnswerClicked(index + 1, context),
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isAnswered && !isNoneOfAbove ? 10 : 13.5,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildAnswerContent(
                                    isCh2En
                                        ? (word?.spell.isNotEmpty == true ? word!.spell : "无对应英文")
                                        : (word?.getMeaningStr().isNotEmpty == true ? word!.getMeaningStr() : "无对应释义"),
                                  ),
                                  if (isAnswered && !isNoneOfAbove) ...[
                                    const SizedBox(height: 4),
                                    _buildSecondaryAnswerContent(word, isCh2En),
                                  ],
                                ],
                              ),
                            ),
                            if (isAnswered && !isNoneOfAbove)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDarkMode ? Colors.white10 : const Color(0xFFEDF5F2),
                                  ),
                                  child: Icon(
                                    Icons.volume_up_rounded,
                                    size: 13,
                                    color: isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C),
                                  ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA),
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
                    final isScorePassed = ref.watch(bdcNotifierProvider.select((s) => s.isScorePassed || s.hasFinishedAnswering));
                    final isAiEvaluating = ref.watch(bdcNotifierProvider.select((s) => s.isAiEvaluating));
                    
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
            ],
          ),
        ),

        // 2. 滚动区域：中文释义 / 拼写提示
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              border: Border(
                left: BorderSide(
                    color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA)),
                right: BorderSide(
                    color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA)),
                bottom: BorderSide(
                    color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
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
                  return _buildSentenceAnswerArea();
                } else if (step == StudyStep.chSentence2En.json) {
                  return _buildSentenceAnswerArea();
                } else if (step == StudyStep.en2Ch.json) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.record_voice_over_outlined,
                            size: 15,
                            color: _cachedIsDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '请说出中文释义：',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _cachedIsDarkMode
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFF4B5563),
                            ),
                          ),
                          if (state.isAiEvaluating) ...[
                            const SizedBox(width: 8),
                            _buildAiJudgingBadge(_cachedIsDarkMode),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
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
                      Row(
                        children: [
                          Icon(
                            Icons.record_voice_over_outlined,
                            size: 15,
                            color: _cachedIsDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '请说出单词发音 或 直接拼写：',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _cachedIsDarkMode
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFF4B5563),
                            ),
                          ),
                        ],
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

        // 3. 例句环节底部固定"按住说话"按钮：独立于滚动区，位置不随识别文本/反馈变化
        if (isSentence && !state.hasFinishedAnswering)
          _buildPttSpeakButton(),
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

  Widget _buildAiJudgingBadge(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
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
              color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            'AI判定中...',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpellingExerciseButton(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            notifier.updateIsUpdatingByHint(true);
            notifier.meaningController.clear();
            notifier.updateIsUpdatingByHint(false);
            updateUI(() {
              notifier.updateShowHandwritingBoard(true);
            }, tag: 'hw-open');
            notifier.asr.stopMicrophone();
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF0F6F3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 17,
                  color: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: notifier.meaningController,
                    builder: (context, value, child) {
                      final text = value.text;
                      return text.isEmpty
                          ? Text(
                              '点击在此手写或拼写练习',
                              style: TextStyle(
                                fontSize: 14.5,
                                color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
                                fontWeight: FontWeight.w500,
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
                                        ? const Color(0xFFFA6E59)
                                        : (isDarkMode ? Colors.white : const Color(0xFF152724)),
                                    const TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  if (text.length < (state.word?.spell.length ?? 0))
                                    TextSpan(
                                      text:
                                          ' ${_buildUnderlines(state.word?.spell ?? "", text.length)}',
                                      style: TextStyle(
                                        fontSize: 17,
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
        const SizedBox(height: 12),
      ],
    );
  }

  /// 例句环节可编辑答案输入框：识别结果写入其中，支持光标定位与语音插入补充。
  /// 不弹系统输入法(readOnly + showCursor)：点击仅显示光标位置作为语音插入点，
  /// 编辑区固定在可视高度内占满答案区，内容多时可内部滚动。
  Widget _buildSentenceAnswerArea() {
    final isDarkMode = _cachedIsDarkMode;
    final hintText = state.studyStep == StudyStep.enSentence2Ch.json
        ? '请按住下方按钮，说出中文翻译'
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
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
    // 用 Consumer 细粒度监听 isPttPressed，避免依赖顶层 _activeState 缓存（顶层按 BdcStateUiSignature 重建，不含该字段）
    return Consumer(
      builder: (context, ref, _) {
        final isPressed = ref.watch(bdcNotifierProvider.select((s) => s.isPttPressed));
        final bgColor = isPressed
            ? (isDarkMode ? Colors.white24 : Colors.black.withValues(alpha: 0.08))
            : AppTheme.primaryColor;
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
                    isPressed ? '松开结束并判定' : '按住说话',
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

    // 当前环节阶段名：测评（stepIndex 0）/ 重测（复习轨道测评答错后的加测环节，由 handleWord 计算）/ 巩固（其余后续环节）
    final gwr = state.currentGetWordResult;
    final String stageText = gwr == null || gwr.stepIndex == 0
        ? '[测评] '
        : (state.isRestoreStep ? '[重测] ' : '[巩固] ');

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
                            '$stageText今日测评: $assLabel',
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
                  padding: const EdgeInsets.only(bottom: 8),
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
                                    '$stageText今日测评: $fallbackLabel',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: hasRating
                                          ? AppTheme.primaryColor
                                          : textColor,
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                '$stageText今日测评: 测评中',
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

      // 兜底:测评环节(stepIndex 0)或未答完时。
      // 若已有评分(如点击"看答案"后 lastFsrsRating=again)则显示评分,
      // 否则显示"测评中"。
      final String fallbackLabel = state.lastFsrsRating?.label ?? '测评中';
      final bool hasRating = state.lastFsrsRating != null;
      return Container(
        padding: const EdgeInsets.only(bottom: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (stageText.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2C2416) : const Color(0xFFFFF8E6),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isDarkMode ? const Color(0xFF6B5320) : const Color(0xFFFDE68A),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    stageText.replaceAll('[', '').replaceAll(']', ''),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // 有评分时才可点击弹"修改今日评分"对话框;测评中不可点击
              hasRating
                  ? InkWell(
                      onTap: _showRatingModifyDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '今日测评: $fallbackLabel',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: hasRating
                                ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                                : textColor,
                          ),
                        ),
                      )
                    )
                  : Text(
                      '今日测评: 测评中',
                      style: TextStyle(fontSize: 11.5, color: textColor),
                    ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('·',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
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
    Color ratingColor;

    switch (state.lastFsrsRating) {
      case FsrsRating.again:
        ratingColor =
            isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFFA6E59); // 珊瑚红
        break;
      case FsrsRating.hard:
        ratingColor =
            isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706); // 琥珀黄
        break;
      case FsrsRating.easy:
        ratingColor =
            isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C); // 翡翠绿
        break;
      case FsrsRating.good:
      default:
        ratingColor =
            isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C);
        break;
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (stageText.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2C2416) : const Color(0xFFFFF8E6),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF6B5320) : const Color(0xFFFDE68A),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  stageText.replaceAll('[', '').replaceAll(']', ''),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            InkWell(
              onTap: _showRatingModifyDialog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '今日测评: $ratingLabel',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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
                      fontWeight: FontWeight.bold,
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
                      color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                      fontWeight: FontWeight.bold,
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
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2),
        border: Border.all(
          color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                  size: 13.5,
                ),
                const SizedBox(width: 3.5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
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
      child: Row(
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
            ),
          ),
          const SizedBox(width: 6),
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
          // 小喇叭 + 看答案/隐藏答案 同行,根据作答状态切换按钮,避免按钮被滚动区遮挡
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
              if (!state.hasFinishedAnswering)
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text("看答案",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
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
          // 小喇叭 + 看答案/隐藏答案 同行,根据作答状态切换按钮,避免按钮被滚动区遮挡
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
              if (!state.hasFinishedAnswering)
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text("看答案",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
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
    final isDarkMode = _cachedIsDarkMode;
    final primaryTextColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final secondaryTextColor = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5B7A75);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                      fontWeight: FontWeight.w900,
                      fontSize: 38,
                      color: primaryTextColor,
                      fontFamily: 'Roboto',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 音标与播音小胶囊
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
                          color: secondaryTextColor,
                          fontFamily: "NotoSans",
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 6),
                    buildWordSoundButton(
                        state.currentGetWordResult!.learningWord!.word,
                        _audioPlayer,
                        state),
                  ],
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
                if (state.word?.sentences != null &&
                    state.word!.sentences!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧极简播放前缀按钮
                        buildSentenceSoundButton(state),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text(
                                        '显示翻译',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                      ],
                    ),
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
    final isDarkMode = _cachedIsDarkMode;
    final allItems = state.currentGetWordResult!.learningWord!.word.getMergedMeaningItems();
    final hasCixingItems = allItems.any((item) => (item.ciXing ?? '').trim().isNotEmpty);
    final displayItems = hasCixingItems
        ? allItems.where((item) => (item.ciXing ?? '').trim().isNotEmpty).toList()
        : allItems;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // 释义温润微卡片
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in displayItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((item.ciXing ?? '').isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF192C27)
                                  : const Color(0xFFEDF5F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white12
                                    : const Color(0xFFD1EADE),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              item.ciXing!,
                              style: TextStyle(
                                color: isDarkMode
                                    ? const Color(0xFF2CD88F)
                                    : const Color(0xFF18BA7C),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            notifier.hideParenthesesContent(item.meaning ?? ''),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? const Color(0xFFEAF7F4)
                                  : const Color(0xFF152724),
                              height: 1.45,
                            ),
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
              state.currentGetWordResult!.images!.isNotEmpty) ...[
            const SizedBox(height: 10),
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
          ],

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
    final isDarkMode = _cachedIsDarkMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!wordPlaying) {
            notifier.playWithAnimation(
                () => StudyAudioSessionController.instance.playWordSound(word),
                'word');
          }
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: wordPlaying
                ? (isDarkMode ? const Color(0xFF152B24) : const Color(0xFFE8F8F1))
                : (isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2)),
            border: Border.all(
              color: wordPlaying
                  ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                  : (isDarkMode ? Colors.white12 : const Color(0xFFD1EADE)),
              width: 1,
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _wordSoundController,
              builder: (context, child) {
                return Icon(
                  wordPlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                  size: 13,
                  color: wordPlaying
                      ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                      : (isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF425B57)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSentenceSoundButton(BdcState state) {
    final sentencePlaying = state.playingStates['sentence'] ?? false;
    final isDarkMode = _cachedIsDarkMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!sentencePlaying &&
              state.englishDigestOfFirstSentence != null) {
            notifier.playWithAnimation(
                () => StudyAudioSessionController.instance.playSentenceSound(
                    state.englishDigestOfFirstSentence!),
                'sentence');
          }
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sentencePlaying
                ? (isDarkMode ? const Color(0xFF152B24) : const Color(0xFFE8F8F1))
                : (isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2)),
            border: Border.all(
              color: sentencePlaying
                  ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                  : (isDarkMode ? Colors.white12 : const Color(0xFFD1EADE)),
              width: 1,
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _sentenceSoundController,
              builder: (context, child) {
                return Icon(
                  sentencePlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                  size: 13.5,
                  color: sentencePlaying
                      ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                      : (isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF425B57)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
