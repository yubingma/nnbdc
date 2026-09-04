import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/local_word_cache.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme/app_theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  static void show(BuildContext context) {
    Util.showFullScreenDialog(context, const SearchPage());
  }

  @override
  State<StatefulWidget> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  bool dataLoaded = false;
  List<WordVo> matchedWords = [];
  final spell = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // 性能优化相关
  bool _isSearching = false;
  String _lastSearchQuery = '';
  final Map<String, List<WordVo>> _searchCache = {};

  // 动画控制器
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // 进入查词页时强制关停 ASR
    Asr().stopMicrophone();
    loadData();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });

    // 初始化动画控制器
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // 启动动画
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    spell.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _searchCache.clear();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() {
      dataLoaded = true;
    });
  }

  void onSearchTextChanged(String value) async {
    final query = value.trim();

    // 避免重复搜索相同内容
    if (query == _lastSearchQuery) {
      return;
    }

    // 如果正在搜索中，跳过这次请求
    if (_isSearching) {
      return;
    }

    _lastSearchQuery = query;

    // 检查缓存
    if (_searchCache.containsKey(query)) {
      setState(() {
        matchedWords = _searchCache[query]!;
      });
      _scrollToTop();
      return;
    }

    // 空查询直接清空结果
    if (query.isEmpty) {
      setState(() {
        matchedWords = [];
      });
      return;
    }

    _isSearching = true;

    try {
      final words = await LocalWordCache.instance.fuzzySearchWord(query);

      // 缓存结果（限制缓存大小）
      if (_searchCache.length > 100) {
        _searchCache.clear();
      }
      _searchCache[query] = words;

      // 只有当查询内容仍然匹配时才更新UI
      if (query == _lastSearchQuery && mounted) {
        setState(() {
          matchedWords = words;
        });
        _scrollToTop();
      }
    } catch (e) {
      Global.logger.d('搜索出错: $e');
    } finally {
      _isSearching = false;
    }
  }

  /// 滚动到列表顶部
  void _scrollToTop() {
    if (_scrollController.hasClients && matchedWords.isNotEmpty) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _performExactSearch() async {
    final query = spell.text.trim();
    if (query.isEmpty) return;
    try {
      var result = await WordBo().searchWordLocalOnly(query);
      if (result.word == null) {
        ToastUtil.error("单词 $query 不存在");
      } else {
        var fullResult = await WordBo().searchWordById(result.word!.id!, null);
        if (!mounted) return;
        if (fullResult.word != null) {
          context.push('/word_detail', extra: WordDetailPageArgs(fullResult.word!, false, null, false));
        } else {
          context.push('/word_detail', extra: WordDetailPageArgs(result.word!, false, null, false));
        }
      }
    } catch (e, st) {
      ErrorHandler.handleDatabaseError(e, st, operation: '本地查词');
    }
  }

  Widget _buildHighlightedSpell(String wordSpell, String query, AppThemeConfig themeConfig) {
    final accentColor = themeConfig.primaryColor;
    final textMain = themeConfig.textPrimary;

    if (query.isNotEmpty && wordSpell.toLowerCase().startsWith(query.toLowerCase())) {
      final matchPart = wordSpell.substring(0, query.length);
      final restPart = wordSpell.substring(query.length);
      return RichText(
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        text: TextSpan(
          children: [
            TextSpan(
              text: matchPart,
              style: TextStyle(
                color: accentColor,
                fontSize: 17.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'NotoSansSC',
              ),
            ),
            TextSpan(
              text: restPart,
              style: TextStyle(
                color: textMain,
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      wordSpell,
      style: TextStyle(
        color: textMain,
        fontSize: 17.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'NotoSansSC',
        height: 1.2,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textScaler: const TextScaler.linear(1.0),
    );
  }

  Widget _buildMeaningWithTags(String meaningStr, AppThemeConfig themeConfig) {
    final textPrimary = themeConfig.textPrimary;
    final posColor = themeConfig.textMuted.withValues(alpha: 0.85);

    // 解析词性标签如 "n. ", "v. ", "adj. ", "adv. ", "vt. ", "vi. "
    final posRegex = RegExp(r'(n\.|v\.|adj\.|adv\.|vt\.|vi\.|prep\.|conj\.|pron\.|art\.|num\.|int\.)\s*');
    final matches = posRegex.allMatches(meaningStr);

    if (matches.isEmpty) {
      return Text(
        meaningStr.isNotEmpty ? meaningStr : "（暂无释义）",
        style: TextStyle(
          color: textPrimary,
          fontSize: 13.5,
          height: 1.45,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textScaler: const TextScaler.linear(1.0),
      );
    }

    final List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: meaningStr.substring(lastEnd, match.start),
          style: TextStyle(color: textPrimary, fontSize: 13.5, height: 1.45),
        ));
      }
      final posText = match.group(1)!;
      spans.add(TextSpan(
        text: '$posText ',
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'NotoSans',
          fontWeight: FontWeight.w500,
          color: posColor,
          letterSpacing: 0.1,
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < meaningStr.length) {
      spans.add(TextSpan(
        text: meaningStr.substring(lastEnd),
        style: TextStyle(color: textPrimary, fontSize: 13.5, height: 1.45),
      ));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget renderWord(final int i) {
    var word = matchedWords[i];
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final cardBg = themeConfig.cardBg;
    final cardBorder = themeConfig.cardBorder;
    final cardSubtle = themeConfig.subtleBg;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 16 * (1 - _fadeAnimation.value)),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4.5),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: themeConfig.cardShadows,
                border: Border.all(
                  color: cardBorder,
                  width: 1.2,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    try {
                      var result = await WordBo().searchWordById(word.id!, null);
                      if (!context.mounted) return;
                      if (result.word != null) {
                        context.push('/word_detail', extra: WordDetailPageArgs(result.word!, false, null, false));
                      } else {
                        context.push('/word_detail', extra: WordDetailPageArgs(word, true, null, false));
                      }
                    } catch (e, st) {
                      ErrorHandler.handleDatabaseError(e, st, operation: '根据ID查词');
                      if (!context.mounted) return;
                      context.push('/word_detail', extra: WordDetailPageArgs(word, true, null, false));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: _buildHighlightedSpell(word.spell, spell.text.trim(), themeConfig),
                                  ),
                                  if (word.mergedPronounce.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cardSubtle,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '[${word.mergedPronounce}]',
                                          style: TextStyle(
                                            color: textSub,
                                            fontSize: 12,
                                            fontFamily: 'NotoSans',
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          textScaler: const TextScaler.linear(1.0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 发音小喇叭按钮
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                StudyAudioSessionController().playWordSound(word);
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: cardSubtle,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.volume_up_rounded,
                                  size: 16,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: themeStyle.isDark ? Colors.white24 : Colors.black26,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildMeaningWithTags(word.getMeaningStr(), themeConfig),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    final searchBoxBg = themeConfig.cardBg;
    final searchBoxBorder = _focusNode.hasFocus ? themeConfig.primaryColor : themeConfig.cardBorder;
    final accentColor = themeConfig.primaryColor;
    final textMain = themeConfig.textPrimary;

    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: searchBoxBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: searchBoxBorder,
              width: _focusNode.hasFocus ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _focusNode.hasFocus
                    ? accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.15)
                    : Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.03),
                blurRadius: _focusNode.hasFocus ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                color: accentColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: spell,
                  focusNode: _focusNode,
                  onChanged: onSearchTextChanged,
                  onSubmitted: (_) => _performExactSearch(),
                  style: TextStyle(
                    color: textMain,
                    fontSize: 15,
                    fontFamily: 'NotoSansSC',
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入单词或中文释义...',
                    hintStyle: TextStyle(
                      color: themeConfig.textMuted.withValues(alpha: 0.8),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (spell.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    spell.clear();
                    onSearchTextChanged('');
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _performExactSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    '查词',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: matchedWords.isEmpty
            ? _buildEmptyState(themeConfig)
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 6, bottom: 20),
                itemCount: matchedWords.length,
                itemBuilder: (context, index) => renderWord(index),
                // ignore: deprecated_member_use
                cacheExtent: 1000.0,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
      ),
    );
  }

  Widget _buildEmptyState(AppThemeConfig themeConfig) {
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    if (spell.text.trim().isNotEmpty) {
      // 搜索无结果态
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: themeConfig.subtleBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 32,
                color: textSub,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '未找到相关单词',
              style: TextStyle(
                color: textMain,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '可尝试输入完整单词拼写或核心释义',
              style: TextStyle(
                color: textSub,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // 默认空状态：插画 + 高频词推荐 + 词根探索
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 顶部插画展台
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: themeConfig.subtleBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: themeConfig.cardBorder,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.15),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.manage_search_rounded,
                        size: 36,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '查单词 · 找例句',
                      style: TextStyle(
                        color: textMain,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '支持输入英文拼写、中文释义或模糊前缀',
                      style: TextStyle(
                        color: textSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
