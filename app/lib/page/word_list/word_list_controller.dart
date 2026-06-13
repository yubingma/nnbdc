import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/global.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'word_list.dart';
import 'dict_words.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';

class WordListController extends ChangeNotifier {
  final WordListPageArgs args;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final StudyAudioSessionController sessionController;

  static const int pageSize = 30;
  static const int minWordCount = 30;
  static const int minQueryInterval = 300;
  static const double handwritingScrollAlignment = 0.3;

  bool dataLoaded = false;
  bool isQuerying = false;
  int totalWordCount = -1;
  BookMarkVo? bookMark;
  int? baseIndex;
  List<WordWrapper> words = [];
  DateTime? lastQueryTime;
  bool doNotQueryPlease = false;
  AiStoryVo? aiStory;
  int? initialScrollIndex;
  double lastExtentAfter = double.infinity;

  bool _disposed = false;

  // 普通词表的内存语义排序缓存
  List<WordWrapper>? _semanticSortedCache;

  /// 获取当前实际排序算法
  Future<WordSortAlg> getCurrentSortAlg() async {
    if (args.wordsProvider is! DictWordsProvider) {
      final currentBookmark = await args.bookMarkProvider.getBookMark();
      if (currentBookmark != null) {
        return WordSortAlg.fromCode(currentBookmark.sortAlg);
      }
    }
    return await args.wordsProvider.getSortAlg();
  }

  /// 确保普通词表的内存语义排序缓存已加载
  Future<void> _ensureSemanticSortedCache() async {
    if (_semanticSortedCache != null) return;
    
    // 一次性获取全量数据
    final allResult = await args.wordsProvider.getAPageOfWords(0, 999999);
    final allRows = allResult.rows;

    if (allRows.isEmpty) {
      _semanticSortedCache = [];
      return;
    }

    final wordIds = allRows.map((w) => w.word.id!).toList();
    final sortedWordIds = await WordBo().getTspSortedWordIdsForList(wordIds);

    final wrapperMap = {for (var w in allRows) w.word.id: w};
    final List<WordWrapper> sortedWrappers = [];
    for (final id in sortedWordIds) {
      final w = wrapperMap[id];
      if (w != null) {
        sortedWrappers.add(w);
      }
    }

    _semanticSortedCache = sortedWrappers;
  }

  WordListController({
    required this.args,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.sessionController,
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void clearQueryResult() {
    words.clear();
    aiStory = null;
    _semanticSortedCache = null;
    notifyListeners();
  }

  bool isBookMarkValid(BookMarkVo? bookMark) {
    return bookMark != null;
  }

  int getBookMarkRawPosition(BookMarkVo? bookMark) {
    return bookMark == null ? -1 : bookMark.position;
  }

  int getBookMarkUiPosition() {
    if (isBookMarkValid(bookMark)) {
      int position = bookMark!.position - baseIndex!;
      return position >= 0 ? position : -1;
    } else {
      return -1;
    }
  }

  Future<void> loadData({
    required VoidCallback checkAndShowGuide,
    required Function(String caller) restoreAsrIfNeeded,
  }) async {
    final swTotal = Stopwatch()..start();
    
    // 1. 获取书签
    bookMark = await args.bookMarkProvider.getBookMark();
    checkAndShowGuide();

    final sortAlg = bookMark != null
        ? WordSortAlg.fromCode(bookMark!.sortAlg)
        : await getCurrentSortAlg();

    if (isBookMarkValid(bookMark)) {
      // --- 预测并行加载优化 ---
      int predWordIndex = bookMark!.position;
      int predCalculatedBase = (predWordIndex ~/ pageSize) * pageSize;
      int predQueryIndex = predCalculatedBase;
      int predQuerySize = pageSize;

      // 智能页补齐逻辑（预测版）
      if (predWordIndex - predCalculatedBase < 10 && predCalculatedBase > 0) {
        predQueryIndex = predCalculatedBase - pageSize;
        predQuerySize = pageSize * 2;
      } else if (predCalculatedBase + pageSize - predWordIndex < 10) {
        predQuerySize = pageSize * 2;
      }

      baseIndex = predQueryIndex;
      initialScrollIndex = predWordIndex - baseIndex!;
      
      // 1. 先进行极其快速的预测分页数据加载
      await doQuery(true, predQueryIndex, predQuerySize, false);

      int actualWordIndex = -1;
      int localOffset = predWordIndex - predQueryIndex;
      
      // 2. 检查加载出来的数据在对应位置是否正好是该书签的单词（预测完美命中）
      if (localOffset >= 0 && localOffset < words.length && words[localOffset].word.spell == bookMark!.spell) {
        actualWordIndex = predWordIndex;
        Global.logger.d('WordListController: 书签预测完美命中！成功跳过 getWordIndex 数据库慢查询！');
      } else {
        if (sortAlg == WordSortAlg.semantic && args.wordsProvider is! DictWordsProvider) {
          await _ensureSemanticSortedCache();
          actualWordIndex = _semanticSortedCache!.indexWhere((w) => w.word.spell == bookMark!.spell);
        } else {
          actualWordIndex = await args.wordsProvider.getWordIndex(bookMark!.spell);
        }
        Global.logger.w('WordListController: 书签预测未命中或越界，回退查询 getWordIndex, spell: ${bookMark!.spell}');
      }

      if (actualWordIndex == -1) {
        if (totalWordCount > 0 && bookMark!.position >= totalWordCount) {
          Global.logger.w('WordListController: 书签位置 ${bookMark!.position} 超过了总词数 $totalWordCount，重置为 0');
          actualWordIndex = 0;
        } else {
          actualWordIndex = bookMark!.position;
        }
      } else if (totalWordCount > 0 && actualWordIndex >= totalWordCount) {
        Global.logger.w('WordListController: 实际书签位置 $actualWordIndex 超过了总词数 $totalWordCount，重置为 0');
        actualWordIndex = 0;
      }
      
      // 重新计算确切的分页参数
      int actualCalculatedBase = (actualWordIndex ~/ pageSize) * pageSize;
      int actualQueryIndex = actualCalculatedBase;
      int actualQuerySize = pageSize;
      if (actualWordIndex - actualCalculatedBase < 10 && actualCalculatedBase > 0) {
        actualQueryIndex = actualCalculatedBase - pageSize;
        actualQuerySize = pageSize * 2;
      } else if (actualCalculatedBase + pageSize - actualWordIndex < 10) {
        actualQuerySize = pageSize * 2;
      }

      // 4. 最终对齐：如果预测的分页区间不对，则需要执行补充加载
      if (actualQueryIndex != predQueryIndex || actualQuerySize != predQuerySize) {
        baseIndex = actualQueryIndex;
        initialScrollIndex = actualWordIndex - baseIndex!; 
        await doQuery(true, baseIndex!, actualQuerySize, false);
      } else {
        baseIndex = predQueryIndex;
        initialScrollIndex = actualWordIndex - baseIndex!;
      }
      
      bookMark = BookMarkVo(actualWordIndex, bookMark!.spell, bookMark!.sortAlg);

      // 数据和页面都准备好后，执行一次精准跳转
      WidgetsBinding.instance.addPostFrameCallback((_) {
        jumpToBookMark(force: true);
      });
    } else {
      // 没有书签：从第一页开始
      baseIndex = 0;
      await doQuery(true, baseIndex!, pageSize, false);
      if (words.isNotEmpty && bookMark == null) {
        final defaultAlg = await getCurrentSortAlg();
        bookMark = BookMarkVo(0, words[0].word.spell, defaultAlg.code);
        args.bookMarkProvider.saveBookMark(bookMark!);
      }
    }

    dataLoaded = true;
    notifyListeners();

    // 语音模式下恢复 ASR
    restoreAsrIfNeeded('loadData');
    Global.logger.d('WordListController: loadData total completed in ${swTotal.elapsedMilliseconds}ms (baseIndex=$baseIndex)');
  }

  Future<void> changeSortAlg(WordSortAlg newAlg) async {
    final currentSpell = bookMark?.spell ?? (words.isNotEmpty ? words[0].word.spell : null);
    if (currentSpell == null) return;

    // 立刻重置页面加载状态，使界面立即转为 Loading 态，避免耗时计算期间显示旧列表
    dataLoaded = false;
    clearQueryResult();

    // 1. 保存新的排序（这会联动修改偏好设置与书签记录的 sortAlg）
    await args.wordsProvider.saveSortAlg(newAlg);
    if (args.wordsProvider is! DictWordsProvider) {
      final currentBookmark = await args.bookMarkProvider.getBookMark();
      if (currentBookmark != null) {
        await args.bookMarkProvider.saveBookMark(
          BookMarkVo(currentBookmark.position, currentBookmark.spell, newAlg.code),
        );
      } else {
        await args.bookMarkProvider.saveBookMark(
          BookMarkVo(0, '', newAlg.code),
        );
      }
    }

    // 2. 重查拼写在新排序下的物理位置
    int newPosition;
    if (newAlg == WordSortAlg.semantic && args.wordsProvider is! DictWordsProvider) {
      await _ensureSemanticSortedCache();
      newPosition = _semanticSortedCache!.indexWhere((w) => w.word.spell == currentSpell);
    } else {
      newPosition = await args.wordsProvider.getWordIndex(currentSpell);
    }
    final finalPos = newPosition == -1 ? 0 : newPosition;

    // 3. 构建新的书签快照
    bookMark = BookMarkVo(finalPos, currentSpell, newAlg.code);
    await args.bookMarkProvider.saveBookMark(bookMark!);

    // 4. 重新加载定位和数据
    await loadData(
      checkAndShowGuide: () {},
      restoreAsrIfNeeded: (_) {},
    );
  }

  Future<void> doQuery(bool clearCurrent, int fromIndex, final int queryPageSize, bool jumpToTailWhenReady, {bool force = false}) async {
    fromIndex = fromIndex < 0 ? 0 : fromIndex;

    if (isQuerying ||
        doNotQueryPlease ||
        (totalWordCount >= 0 && fromIndex >= totalWordCount) ||
        (!clearCurrent &&
            totalWordCount >= 0 &&
            words.length >= totalWordCount &&
            words.isNotEmpty) ||
        fromIndex < 0 ||
        (!force && lastQueryTime != null &&
            AppClock.now().difference(lastQueryTime!).inMilliseconds <
                minQueryInterval)) {
      return;
    }

    isQuerying = true;
    lastQueryTime = AppClock.now();

    if (clearCurrent) {
      clearQueryResult();
      baseIndex = fromIndex;
    }

    await loadAPageOfWords(fromIndex, queryPageSize, jumpToTailWhenReady);
    isQuerying = false;
    notifyListeners();
  }

  Future<void> loadAPageOfWords(final int fromIndex, final int queryPageSize, bool jumpToTailWhenReady) async {
    try {
      final sortAlg = await getCurrentSortAlg();
      
      PagedResults<WordWrapper> result;
      if (sortAlg == WordSortAlg.semantic && args.wordsProvider is! DictWordsProvider) {
        await _ensureSemanticSortedCache();
        final cache = _semanticSortedCache!;
        final end = (fromIndex + queryPageSize) > cache.length ? cache.length : (fromIndex + queryPageSize);
        final slicedRows = fromIndex >= cache.length ? <WordWrapper>[] : cache.sublist(fromIndex, end);
        result = PagedResults<WordWrapper>(cache.length)..rows.addAll(slicedRows);
      } else {
        result = await args.wordsProvider.getAPageOfWords(fromIndex, queryPageSize);
      }

      if (result.rows.isEmpty) {
        totalWordCount = result.total;
        notifyListeners();
        return;
      }

      int newTotalWordCount = result.total;
      List<WordWrapper> newWords = List.from(words);
      int? newBaseIndex = baseIndex;

      if (fromIndex < baseIndex!) {
        Global.logger.d('向上加载数据: fromIndex=$fromIndex, baseIndex=$baseIndex, 当前words长度=${words.length}');
        var beforeLen = newWords.length;
        var newData = result.rows.where((element) => !words.contains(element)).toList();
        for (var w in newData) {
          w.currentProgress = args.wordProgressProvider.getWordProgress(w.tag);
          w.maxProgress = args.wordProgressProvider.getWordProgressMax(w.tag);
        }
        newWords.insertAll(0, newData);
        var lenDelta = newWords.length - beforeLen;
        newBaseIndex = baseIndex! - lenDelta;

        if (jumpToTailWhenReady == false) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (itemScrollController.isAttached) {
              itemScrollController.scrollTo(
                  index: lenDelta,
                  duration: const Duration(milliseconds: 100),
                  alignment: 0.5);
            }
          });
        }
      } else {
        final loadedRows = result.rows.where((element) => !words.contains(element)).toList();
        for (var w in loadedRows) {
          w.currentProgress = args.wordProgressProvider.getWordProgress(w.tag);
          w.maxProgress = args.wordProgressProvider.getWordProgressMax(w.tag);
        }
        newWords.addAll(loadedRows);
      }

      totalWordCount = newTotalWordCount;
      words = newWords;
      baseIndex = newBaseIndex;

      if (jumpToTailWhenReady) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (itemScrollController.isAttached) {
            itemScrollController.scrollTo(
                index: (words.length - 1),
                duration: const Duration(milliseconds: 300),
                alignment: handwritingScrollAlignment);
          }
        });
      }
      notifyListeners();

      _loadLearningStatusForWords(result.rows);
      _prefetchAudioForWords(result.rows);
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '加载单词失败', showToast: false);
    }
  }

  Future<void> _loadLearningStatusForWords(List<WordWrapper> newWords) async {
    final wordIds = newWords
        .where((w) => w.word.id != null && w.initialLearningStatus == null)
        .map((w) => w.word.id!)
        .toList();
    if (wordIds.isEmpty) return;

    final statusMap = await args.wordsProvider.getWordsLearningStatus(wordIds);
    if (statusMap.isEmpty) return;

    bool hasUpdates = false;
    for (var wordWrapper in newWords) {
      final wordId = wordWrapper.word.id;
      if (wordId != null && statusMap.containsKey(wordId)) {
        final status = statusMap[wordId];
        if (status != null) {
          wordWrapper.initialLearningStatus = status;
          wordWrapper.currentLearningStatus = status;
          hasUpdates = true;
        }
      }
    }

    if (hasUpdates) {
      notifyListeners();
    }
  }

  void _prefetchAudioForWords(List<WordWrapper> newWords) {
    if (newWords.isEmpty) return;
    try {
      final urls = newWords.map((w) => Util.getWordSoundUrl(w.word.spell, word: w.word)).toList();
      sessionController.prefetchSounds(urls);
    } catch (e) {
      Global.logger.w('预取音频失败: $e');
    }
  }

  void jumpToBookMark({bool force = false}) {
    if (isBookMarkValid(bookMark)) {
      final bookMarkUiPos = getBookMarkUiPosition();
      if (bookMarkUiPos == -1 || bookMarkUiPos >= words.length) {
        return;
      }

      if (!dataLoaded || words.isEmpty || !itemScrollController.isAttached) {
        return;
      }

      double finalAlignment = handwritingScrollAlignment;
      if (totalWordCount < 8 || (baseIndex == 0 && bookMarkUiPos < 3)) {
        finalAlignment = 0.0;
      }

      if (force) {
        itemScrollController.jumpTo(index: bookMarkUiPos, alignment: finalAlignment);
        initialScrollIndex = null;
        return;
      }

      var positions = itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        var currentPosition = positions.where((pos) => pos.index == bookMarkUiPos).firstOrNull;
        if (currentPosition != null) {
          if (currentPosition.itemLeadingEdge >= finalAlignment - 0.05 &&
              currentPosition.itemLeadingEdge <= finalAlignment + 0.05) {
            return;
          }
        }
      }

      itemScrollController.scrollTo(
          index: bookMarkUiPos,
          duration: const Duration(milliseconds: 300),
          alignment: finalAlignment);
    }
  }

  void scrollToWord(int wordUiIndex) {
    if (wordUiIndex < 0 || wordUiIndex >= words.length) return;

    if (!dataLoaded || words.isEmpty) {
      return;
    }

    if (lastExtentAfter <= 1) {
      return;
    }

    final int targetIndex = wordUiIndex > 1 ? wordUiIndex - 2 : 0;

    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      var targetPos = positions.where((pos) => pos.index == targetIndex).firstOrNull;
      if (targetPos != null && targetPos.itemLeadingEdge.abs() < 0.05) {
        return;
      }
    }

    if (itemScrollController.isAttached) {
      itemScrollController.jumpTo(index: targetIndex, alignment: 0.0);
    }
  }

  int getFirstVisibleListItem() {
    int? min;
    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      min = positions
          .where((ItemPosition position) => position.itemTrailingEdge > 0)
          .reduce((ItemPosition min, ItemPosition position) =>
              position.itemTrailingEdge < min.itemTrailingEdge ? position : min)
          .index;
    }
    return min ?? -1;
  }

  int getLastVisibleListItem() {
    int? max;
    var positions = itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      max = positions
          .where((ItemPosition position) => position.itemLeadingEdge < 1)
          .reduce((ItemPosition max, ItemPosition position) =>
              position.itemLeadingEdge > max.itemLeadingEdge ? position : max)
          .index;
    }
    return max ?? -1;
  }

  Future<void> deleteWord(WordWrapper word, int index) async {
    Global.logger.d('[Perf] deleteWord START: word=${word.word.spell}, index=$index');

    await Future.delayed(const Duration(milliseconds: 200));
    final value = await args.wordsProvider.deleteWord(word);
    
    if (value) {
      EventBus.publishWordDeletedFromWordList(WordDeletedFromWordListEvent(wordId: word.word.id.toString()));
      
      final String providerType = args.wordsProvider.runtimeType.toString();
      final bool isTodayTask = providerType == 'StageWordsProvider' ||
          ['学习中', '今日错词', '今日新词', '今日旧词', '今日单词', '单词列表'].contains(args.appBarTitle);
      final bool todayStudyStarted = Global.getLoggedInUser()?.todayStudyStarted ?? false;

      if (todayStudyStarted && isTodayTask) {
        word.currentLearningStatus = true;
        if (word.tag is LearningWordVo) {
          (word.tag as LearningWordVo).stability = 180.0;
        }
        notifyListeners();
        return;
      }

      words.remove(word);
      totalWordCount--;

      if (isBookMarkValid(bookMark)) {
        final bookMarkPosition = getBookMarkRawPosition(bookMark);
        if (index + baseIndex! < bookMarkPosition && bookMarkPosition <= words.length + baseIndex!) {
          var w = words[bookMarkPosition - baseIndex! - 1];
          bookMark = BookMarkVo(bookMarkPosition - 1, w.word.spell, bookMark!.sortAlg);
          await args.bookMarkProvider.saveBookMark(bookMark!);
        }
      }

      if (words.length < minWordCount) {
        await doQuery(false, baseIndex! + words.length, pageSize, false);
      }
      notifyListeners();
    }
  }

  Future<void> masterWord(WordWrapper word, int index) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final value = await args.wordsProvider.masterWord(word);

    if (value) {
      EventBus.publishWordMastered(WordMasteredEvent(wordId: word.word.id.toString()));

      final String providerType = args.wordsProvider.runtimeType.toString();
      final bool isTodayTask = providerType == 'StageWordsProvider' ||
          ['学习中', '今日错词', '今日新词', '今日旧词', '今日单词', '单词列表'].contains(args.appBarTitle);
      final bool todayStudyStarted = Global.getLoggedInUser()?.todayStudyStarted ?? false;

      if ((todayStudyStarted && isTodayTask) || args.wordsProvider.keepWordsOnMaster) {
        word.currentLearningStatus = true;
        if (word.tag is LearningWordVo) {
          (word.tag as LearningWordVo).stability = 180.0;
        }
        word.currentProgress = word.maxProgress;
        notifyListeners();
        return;
      }

      word.currentLearningStatus = true;
      if (word.tag is LearningWordVo) {
        (word.tag as LearningWordVo).stability = 180.0;
      }
      word.currentProgress = word.maxProgress;
      words.remove(word);
      totalWordCount--;

      if (isBookMarkValid(bookMark)) {
        final bookMarkPosition = getBookMarkRawPosition(bookMark);
        if (index + baseIndex! < bookMarkPosition && bookMarkPosition <= words.length + baseIndex!) {
          var w = words[bookMarkPosition - baseIndex! - 1];
          bookMark = BookMarkVo(bookMarkPosition - 1, w.word.spell, bookMark!.sortAlg);
          await args.bookMarkProvider.saveBookMark(bookMark!);
        }
      }

      if (words.length < minWordCount) {
        await doQuery(false, baseIndex! + words.length, pageSize, false);
      }
      notifyListeners();
    }
  }

  Future<void> unmasterWord(WordWrapper word, int index) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final initialStatus = word.initialLearningStatus;
    final value = await args.wordsProvider.unmasterWord(word);

    if (value) {
      EventBus.publishWordUnMastered(WordUnMasteredEvent(wordId: word.word.id.toString()));

      if (initialStatus == true && !args.wordsProvider.keepWordsOnMaster) {
        words.remove(word);
        totalWordCount--;

        if (isBookMarkValid(bookMark)) {
          final bookMarkPosition = getBookMarkRawPosition(bookMark);
          if (index + baseIndex! < bookMarkPosition && bookMarkPosition <= words.length + baseIndex!) {
            var prevWord = words[bookMarkPosition - baseIndex! - 1];
            bookMark = BookMarkVo(bookMarkPosition - 1, prevWord.word.spell, bookMark!.sortAlg);
            await args.bookMarkProvider.saveBookMark(bookMark!);
          }
        }
        if (words.length < minWordCount) {
          await doQuery(false, baseIndex! + words.length, pageSize, false);
        }
      } else {
        word.currentLearningStatus = initialStatus;
        if (word.tag is LearningWordVo) {
          (word.tag as LearningWordVo).stability = 0.0;
        }
        word.currentProgress = 0.0;
      }
      notifyListeners();
    }
  }
}
