import 'package:drift/drift.dart' as drift show Value;
import 'package:drift/drift.dart' hide Value;
import 'package:nnbdc/router.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/utils.dart';

import '../../api/bo/word_bo.dart';
import '../../api/sort_alg.dart';
import '../../global.dart';
import '../../util/app_clock.dart';
import '../../util/word_util.dart';
import '../../constants.dart';

class DictWordsProvider with WordsProvider implements WordModifier {
  DictVo dict;

  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  DictWordsProvider(this.dict);

  @override
  Future<WordSortAlg> getSortAlg() async {
    final bookmarkProvider = DictWordsBookMarkProvider(dict);
    final bookmark = await bookmarkProvider.getBookMark();
    if (bookmark != null) {
      return WordSortAlg.fromCode(bookmark.sortAlg);
    }
    final userId = Global.getLoggedInUser()?.id;
    if (userId != null) {
      final learningDict = await _db.learningDictsDao.findById(userId, dict.id);
      if (learningDict != null) {
        return WordSortAlg.fromCode(learningDict.sortAlg);
      }
    }
    return WordSortAlg.original;
  }

  @override
  Future<void> saveSortAlg(WordSortAlg alg) async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return;

    if (alg == WordSortAlg.semantic) {
      WordBo.clearTspCache(dict.id);
    }

    // 1. 双向联动：更新 LearningDicts 偏好
    final learningDict = await _db.learningDictsDao.findById(userId, dict.id);
    if (learningDict != null) {
      final updatedLD = learningDict.copyWith(sortAlg: alg.code, updateTime: AppClock.now());
      await _db.learningDictsDao.saveEntity(updatedLD, true);
    }

    // 2. 更新对应书签
    final bookmarkProvider = DictWordsBookMarkProvider(dict);
    var bookmark = await bookmarkProvider.getBookMark();
    if (bookmark != null) {
      final updatedBookmark = BookMarkVo(bookmark.position, bookmark.spell, alg.code);
      await bookmarkProvider.saveBookMark(updatedBookmark);
    }
  }

  @override
  Future<bool> get hasUnits async {
    final result = await (_db.selectOnly(_db.dictWords)
          ..addColumns([_db.dictWords.unit])
          ..where(_db.dictWords.dictId.equals(dict.id) & _db.dictWords.unit.isBiggerThanValue(0))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }

  @override
  String? get targetDictId => dict.id;

  @override
  bool get keepWordsOnMaster => true;

  @override
  Future<bool> addWord(String wordId) async {
    final result = await WordBo().addWordToCustomDict(dict.id, wordId);
    if (result.success) {
      return true;
    } else {
      ToastUtil.error(result.msg ?? '添加失败');
      return false;
    }
  }

  @override
  Future<bool> updateMeanings(String wordId, List<MeaningUpdateItem> meanings) async {
    final result = await WordBo().updateMeaningForCustomDict(dict.id, wordId, meanings);
    if (result.success) {
      return true;
    } else {
      ToastUtil.error(result.msg ?? '更新失败');
      return false;
    }
  }

  @override
  Future<bool> deleteMeaning(String wordId) async {
    final result = await WordBo().deleteMeaningForCustomDict(dict.id, wordId);
    if (result.success) {
      return true;
    } else {
      ToastUtil.error(result.msg ?? '操作失败');
      return false;
    }
  }

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final sw = Stopwatch()..start();
    try {
      final sortAlg = await getSortAlg();
      final results = await WordBo().getDictWordsForAPage(dict.id, fromIndex, pageSize, sortAlg: sortAlg.code);
      final wrappedResults = PagedResults<WordWrapper>(results.total);

      for (var dictWordVo in results.rows) {
        wrappedResults.rows.add(WordWrapper(dictWordVo.word, dictWordVo));
      }

      Global.logger.d('DictWordsProvider: getAPageOfWords(from=$fromIndex) completed in ${sw.elapsedMilliseconds}ms');
      return wrappedResults;
    } catch (e) {
      Global.logger.e("获取词典单词失败: $e");
      return PagedResults<WordWrapper>(0);
    }
  }

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) return false;

      await WordBo().setLearningWordAsMastered(userId, wordWrapper.word.id!, true);

      ThrottledDbSyncService().requestSync();
      return true;
    } catch (e) {
      ToastUtil.error("操作失败: $e");
      return false;
    }
  }

  @override
  Future<bool> unmasterWord(WordWrapper wordWrapper) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) return false;

      final result = await WordBo().deleteMasteredWord(userId, wordWrapper.word.id!);
      if (result.success) {
        ThrottledDbSyncService().requestSync();
        return true;
      }
      ToastUtil.error(result.msg ?? "操作失败");
      return false;
    } catch (e) {
      ToastUtil.error("操作失败: $e");
      return false;
    }
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    try {
      // 从本地数据库中删除dictWord记录，并清理后续序号
      await _db.dictWordsDao.deleteDictWordWithCleanup(dict.id, wordWrapper.word.id!, Global.getLoggedInUser()?.id, true);

      // 触发同步
      ThrottledDbSyncService().requestSync();

      StudyAudioSessionController().playSoundEffect('delete.mp3', speed: 1.0, volume: 0.5);
      return true;
    } catch (e) {
      ToastUtil.error("删除失败: $e");
      return false;
    }
  }

  @override
  Future<int> getWordIndex(String spell) async {
    final sw = Stopwatch()..start();
    final sortAlg = await getSortAlg();
    var result = await WordBo().getDictWordOrder(dict.id, spell, sortAlg: sortAlg.code);
    Global.logger.d('DictWordsProvider: getWordIndex($spell) completed in ${sw.elapsedMilliseconds}ms');
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async {
    final user = Global.getLoggedInUser();
    if (user == null) return null;

    final db = MyDatabase.instance;

    // 检查是否已掌握
    final isMastered = await db.masteredWordsDao.isWordMastered(user.id, wordId);
    if (isMastered) return true; // 已掌握

    // 检查是否在学习中
    final learningQuery = db.select(db.learningWords)
      ..where((lw) =>
          lw.userId.equals(user.id) &
          lw.wordId.equals(wordId) &
          (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability)));
    final learning = await learningQuery.getSingleOrNull();
    if (learning != null) return false; // 学习中

    return null; // 未学习
  }

  @override
  Future<Map<String, bool?>> getWordsLearningStatus(List<String> wordIds) async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return {};
    return await WordBo.getWordsLearningStatusBatch(userId, wordIds);
  }
}

class DictWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 0.0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 100.0;
  }
}

class DictWordsBookMarkProvider implements BookMarkProvider {
  DictVo dict;
  late final String bookMarkName;

  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  DictWordsBookMarkProvider(this.dict) {
    bookMarkName = 'dict_${dict.id}_words_list';
  }

  @override
  Future<BookMarkVo?> getBookMark() async {
    // 1. 优先尝试从内存缓存获取
    final cached = WordBo().getBookmarkFromCache(bookMarkName);
    if (cached != null) return cached;

    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) return null;

      // 2. 从本地Bookmarks表获取
      final bookmarkQuery = _db.select(_db.bookMarks)
        ..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(bookMarkName));

      final bookmark = await bookmarkQuery.getSingleOrNull();

      if (bookmark != null) {
        final vo = BookMarkVo(bookmark.position, bookmark.spell, bookmark.sortAlg);
        WordBo().updateBookmarkCache(bookMarkName, vo);
        return vo;
      }

      // 3. 检查旧的localParams表
      final paramQuery = _db.select(_db.localParams)..where((p) => p.name.equals(bookMarkName));
      final param = await paramQuery.getSingleOrNull();

      if (param != null) {
        final content = param.value;
        if (content.contains(':')) {
          final parts = content.split(':');
          if (parts.length == 2) {
            final bookMark = BookMarkVo(int.tryParse(parts[1]) ?? 0, parts[0], 'ORIGINAL');
            WordBo().updateBookmarkCache(bookMarkName, bookMark);
            // 异步迁移到新表，不阻塞当前返回
            _saveBookMarkLocally(bookMark).then((_) {
              (_db.delete(_db.localParams)..where((p) => p.name.equals(bookMarkName))).go();
            });
            return bookMark;
          }
        }
      }
      return null;
    } catch (e) {
      Global.logger.d("获取书签失败: $e");
      return null;
    }
  }

  // 在本地保存书签
  Future<bool> _saveBookMarkLocally(BookMarkVo bookMark) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        Global.logger.d('保存书签失败：用户未登录');
        return false;
      }

      final uuid = Util.uuid();

      // 查询是否已存在相同userId和name的书签
      final existingQuery = _db.select(_db.bookMarks)..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(bookMarkName));

      final existing = await existingQuery.getSingleOrNull();

      // 当前时间
      final now = AppClock.now();

      if (existing != null) {
        // 更新现有记录
        await (_db.update(_db.bookMarks)..where((b) => b.id.equals(existing.id))).write(
          BookMarksCompanion(
            spell: drift.Value(bookMark.spell),
            position: drift.Value(bookMark.position),
            sortAlg: drift.Value(bookMark.sortAlg),
            updateTime: drift.Value(now),
          ),
        );
      } else {
        // 创建新记录
        await _db.into(_db.bookMarks).insert(
              BookMark(
                id: uuid,
                userId: userId,
                bookMarkName: bookMarkName,
                spell: bookMark.spell,
                position: bookMark.position,
                sortAlg: bookMark.sortAlg,
                createTime: now,
                updateTime: now,
              ),
            );
      }
      return true;
    } catch (e, stackTrace) {
      Global.logger.d("本地保存书签失败: $e\n$stackTrace");
      return false;
    }
  }

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    // 0. 更新内存缓存
    WordBo().updateBookmarkCache(bookMarkName, bookMark);

    // 1. 保存到本地数据库
    Global.logger.d('保存字典书签: position=${bookMark.position}, spell=${bookMark.spell}');
    final success = await _saveBookMarkLocally(bookMark);

    if (success) {
      // 尝试同步到服务器
      try {
        // 确保书签变更被记录到 userDbLogs 表中
        final userId = Global.getLoggedInUser()!.id;
        final bookmarkQuery = _db.select(_db.bookMarks)..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(bookMarkName));
        final bookmark = await bookmarkQuery.getSingleOrNull();

        if (bookmark != null) {
          // 记录书签变更到 userDbLogs 表
          await DbLogUtil.logOperation(userId, 'UPDATE', 'bookMarks', bookmark.id, bookmark);
        }

        ThrottledDbSyncService().requestSync();
      } catch (syncError) {
        // 同步失败，但本地已保存，稍后可以再次同步
      }
    }

    return success;
  }
}

Future<dynamic>? toDictWordsListPage(dynamic dictOrId, bool showDelBtn) async {
  try {
    DictVo dict;
    if (dictOrId is DictVo) {
      dict = dictOrId;
    } else if (dictOrId is Dict) {
      // 传入的是 Drift 本地实体对象
      dict = DictVo.c2(dictOrId.id);
      dict.name = dictOrId.name;
      dict.shortName = Util.getShortName(dictOrId.name);
      dict.wordCount = dictOrId.wordCount;
      dict.isReady = dictOrId.isReady;
      dict.isShared = dictOrId.isShared;
      dict.visible = dictOrId.visible;
      dict.editable = dictOrId.editable;
    } else {
      final String dictId = dictOrId is String ? dictOrId : dictOrId.toString();
      // 从本地数据库获取词典信息
      var db = MyDatabase.instance;
      final dictQuery = db.select(db.dicts)..where((d) => d.id.equals(dictId));
      final dictEntry = await dictQuery.getSingleOrNull();

      if (dictEntry != null) {
        // 使用本地数据
        dict = DictVo.c2(dictEntry.id);
        dict.name = dictEntry.name;
        dict.shortName = Util.getShortName(dictEntry.name);
        dict.wordCount = dictEntry.wordCount;
        dict.isReady = dictEntry.isReady;
        dict.isShared = dictEntry.isShared;
        dict.visible = dictEntry.visible;
        dict.editable = dictEntry.editable;
      } else {
        // 本地查无此词书：不再静默捏造"词典(本地模式)"占位书并落库
        // （占位书 ownerId=当前用户且 editable=true，会被"自定义词书"收纳且可编辑，掩盖数据不一致）。
        // 改为从服务端拉取词书元数据；拉取失败则明确报错，让缺失问题暴露出来。
        final remote = await Api.client.getDictInfo(dictId);
        final DictDto? dto = remote.success ? remote.data : null;
        if (dto == null) {
          Global.logger.e('❌ 词书数据缺失: 本地无词书(dictId=$dictId) 且服务端拉取失败: ${remote.msg}');
          ToastUtil.error('词书数据缺失，无法打开词表');
          return null;
        }
        // 补录词书元数据到本地（不生成同步日志：系统词书不由用户同步，此处仅补录而非用户变更）
        await db.into(db.dicts).insertOnConflictUpdate(
              Dict(
                id: dto.id,
                isReady: dto.isReady,
                isShared: dto.isShared,
                name: dto.name,
                wordCount: dto.wordCount,
                ownerId: dto.ownerId,
                visible: dto.visible,
                editable: dto.editable ?? false,
                deletable: dto.deletable ?? true,
                createTime: dto.createTime,
                updateTime: dto.updateTime,
              ),
            );
        dict = DictVo.c2(dto.id);
        dict.name = dto.name;
        dict.shortName = Util.getShortName(dto.name);
        dict.wordCount = dto.wordCount;
        dict.isReady = dto.isReady;
        dict.isShared = dto.isShared;
        dict.visible = dto.visible;
        dict.editable = dto.editable ?? false;
      }
    }

    return goRouter.push('/word_list',
        extra: WordListPageArgs(
            dict.shortName ?? Util.getShortName(dict.name ?? "词典"), DictWordsProvider(dict), true, showDelBtn, false, '', DictWordsProgressProvider(), DictWordsBookMarkProvider(dict), null)
          ..canAddWord = showDelBtn || (dict.editable ?? false)
          ..canEditWord = showDelBtn || (dict.editable ?? false));
  } catch (e) {
    ToastUtil.error("无法打开词典");
    rethrow;
  }
}


