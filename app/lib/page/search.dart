import 'dart:async';
import 'package:nnbdc/global.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/local_word_cache.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:provider/provider.dart';

import '../util/utils.dart';
import '../state.dart';

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
      begin: const Offset(0, 0.3),
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
    _searchCache.clear(); // 清理缓存
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() {
      dataLoaded = true;
    });
  }

  Widget renderWord(final int i) {
    var word = matchedWords[i];
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - _fadeAnimation.value)),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode ? Colors.black.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                ],
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[200]!.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Get.toNamed('/word_detail', arguments: WordDetailPageArgs(word, true, null, false), preventDuplicates: false);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// 单词英文和音标
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                word.spell,
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'NotoSansSC',
                                  height: 1.3,
                                  letterSpacing: 0.5,
                                ),
                                textScaler: const TextScaler.linear(1.0),
                              ),
                            ),
                            if (word.mergedPronounce.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isDarkMode ? [Colors.grey[800]!, Colors.grey[700]!] : [Colors.grey[100]!, Colors.grey[200]!],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDarkMode ? Colors.grey[700]!.withValues(alpha: 0.5) : Colors.grey[300]!.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  word.mergedPronounce,
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 13,
                                    fontFamily: 'NotoSansSC',
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textScaler: const TextScaler.linear(1.0),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        /// 单词释义
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[50]!.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDarkMode ? Colors.grey[700]!.withValues(alpha: 0.2) : Colors.grey[200]!.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            word.getMeaningStr(),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontFamily: 'NotoSansSC',
                              height: 1.5,
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.w400,
                            ),
                            textScaler: const TextScaler.linear(1.0),
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
      },
    );
  }

  void onSearchTextChanged(value) async {
    final query = value.toString().trim();

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
      // 搜索出错时不更新UI，保持之前的结果
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        toolbarHeight: 88,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AppTheme.gradientStartColor,
                AppTheme.gradientEndColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            if (Get.currentRoute != '/index')
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            Expanded(
              child: Container(
                height: 48,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: TextField(
                  controller: spell,
                  focusNode: _focusNode,
                  onChanged: (value) {
                    onSearchTextChanged(value);
                  },
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'NotoSansSC',
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入单词或中文释义',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                      fontFamily: 'NotoSansSC',
                      height: 1.0,
                      fontWeight: FontWeight.w400,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.gradientStartColor,
                            AppTheme.gradientEndColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          if (spell.text.trim().isEmpty) return;
                          try {
                            // 使用本地查词替代后端查词
                            var result = await WordBo().searchWordLocalOnly(spell.text);
                            if (result.word == null) {
                              ToastUtil.error("单词 ${spell.text} 不存在");
                            } else {
                              Get.toNamed('/word_detail', arguments: WordDetailPageArgs(result.word!, false, null, false), preventDuplicates: false);
                            }
                          } catch (e, st) {
                            ErrorHandler.handleDatabaseError(e, st, operation: '本地查词');
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.search,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [
                    const Color(0xFF121212),
                    const Color(0xFF1A1A1A),
                    const Color(0xFF121212),
                  ]
                : [
                    const Color(0xFFF5F7FA),
                    const Color(0xFFE8ECF1),
                    const Color(0xFFF5F7FA),
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: matchedWords.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 16, 16, 0),
                  itemCount: matchedWords.length,
                  itemBuilder: (context, index) => renderWord(index),
                  // 性能优化设置
                  cacheExtent: 1000, // 预缓存范围
                  addAutomaticKeepAlives: false, // 不自动保持状态
                  addRepaintBoundaries: true, // 添加重绘边界
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[100]!.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkMode ? Colors.grey[700]!.withValues(alpha: 0.2) : Colors.grey[300]!.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: GestureDetector(
                  onTap: () {
                    // 聚焦到输入框
                    _focusNode.requestFocus();
                  },
                  child: Icon(
                    spell.text.trim().isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
                    size: 48,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                spell.text.trim().isEmpty ? '输入单词开始查词' : '未找到相关单词',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontFamily: 'NotoSansSC',
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              if (spell.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.2) : Colors.grey[100]!.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDarkMode ? Colors.grey[700]!.withValues(alpha: 0.2) : Colors.grey[300]!.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '试试输入完整单词或中文释义',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontFamily: 'NotoSansSC',
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                    textScaler: const TextScaler.linear(1.0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
