import 'package:flutter/material.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/page/word_list/learning_words.dart';
import 'package:nnbdc/page/word_list/mastered_words.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/page/word_list/wrong_words.dart';
import 'package:provider/provider.dart';

import '../api/vo.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';

class WordListsPage extends StatefulWidget {
  const WordListsPage({super.key});

  @override
  State<StatefulWidget> createState() => _WordListsPageState();
}

class _WordListsPageState extends State<WordListsPage> {
  bool dataLoaded = false;
  late List<WordList> wordLists;
  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    wordLists = (await WordBo().getWordLists()).data!;
    setState(() {
      dataLoaded = true;
    });
  }

  double contentWidth() {
    final size = MediaQuery.of(context).size;
    final width = size.width - leftPadding - rightPadding;
    return width;
  }

  List<Color> gradientColorsByIndex(var wordListIndex) {
    switch (wordListIndex) {
      case 0:
        return [const Color(0xFFE53E3E), const Color(0xFFFC8181)]; // 红色渐变
      case 1:
        return [const Color(0xFFFF6B35), const Color(0xFFFF8E53)]; // 橙红渐变
      case 2:
        return [const Color(0xFFFFB347), const Color(0xFFFFD93D)]; // 橙黄渐变
      case 3:
        return [const Color(0xFF38A169), const Color(0xFF68D391)]; // 绿色渐变
      case 4:
        return [const Color(0xFF00B5D8), const Color(0xFF63B3ED)]; // 青色渐变
      case 5:
        return [const Color(0xFF3182CE), const Color(0xFF63B3ED)]; // 蓝色渐变
      case 6:
        return [const Color(0xFF805AD5), const Color(0xFFB794F6)]; // 紫色渐变
      default:
        return [const Color(0xFF38A169), const Color(0xFF68D391)]; // 默认绿色
    }
  }

  IconData iconByIndex(var wordListIndex) {
    switch (wordListIndex) {
      case 0:
        return Icons.error_outline; // 今日错词
      case 1:
        return Icons.fiber_new; // 今日新词
      case 2:
        return Icons.refresh; // 今日旧词
      case 3:
        return Icons.today; // 今日单词
      case 4:
        return Icons.school; // 学习中
      case 5:
        return Icons.book; // 生词本
      case 6:
        return Icons.check_circle; // 已掌握
      default:
        return Icons.list_alt;
    }
  }

  Widget renderAWordList(WordList wordList, var index) {
    final gradientColors = gradientColorsByIndex(index);
    final icon = iconByIndex(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            var canDeleteTodayWords = !Global.getLoggedInUser()!.isTodayLearningStarted || Global.getLoggedInUser()!.isTodayLearningFinished;
            if (wordList.name == '今日错词') {
              toWrongWordsListPage();
            } else if (wordList.name == '今日新词') {
              toTodayNewWordsListPage(canDeleteTodayWords)!.then((value) => loadData());
            } else if (wordList.name == '今日旧词') {
              toTodayOldWordsListPage(canDeleteTodayWords)!.then((value) => loadData());
            } else if (wordList.name == '今日单词') {
              toTodayWordsListPage(canDeleteTodayWords)!.then((value) => loadData());
            } else if (wordList.name == '学习中') {
              toLearningWordsListPage(true)!.then((value) => loadData());
            } else if (wordList.name == '生词本') {
              var dict = await WordBo().getRawWordDict();
              toDictWordsListPage(dict.id, true)!.then((value) => loadData());
            } else if (wordList.name == '已掌握') {
              toMasteredWordsListPage(true)!.then((value) => loadData());
            }
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // 图标容器
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),

                // 文字内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wordList.name,
                        textScaler: TextScaler.linear(1.0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          height: 1.6,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${wordList.wordCount} 个单词',
                        textScaler: TextScaler.linear(1.0),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          height: 1.5,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),

                // 箭头图标
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);

    return Scaffold(
      backgroundColor: backgroundColor,
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
        child: CustomScrollView(
          slivers: [
            // 美化的AppBar
            SliverAppBar(
              expandedHeight: 88,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
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
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.library_books,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '词表管理',
                                  textScaler: TextScaler.linear(1.0),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w400,
                                    height: 1.5,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(
                                  '复习巩固你的学习成果',
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w300,
                                    height: 1.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 内容区域
            SliverToBoxAdapter(
              child: !dataLoaded
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF0097A7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '正在加载词表...',
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                height: 1.5,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 24),
                      child: Column(
                        children: [
                          for (var i = 0; i < wordLists.length; i++) renderAWordList(wordLists[i], i),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
