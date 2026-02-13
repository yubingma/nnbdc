import 'package:get/get.dart';
import 'package:drift/drift.dart' hide Value;
import 'package:drift/drift.dart' as drift show Value;
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'dart:convert';

import '../../global.dart';
import '../../util/word_util.dart';
import '../../api/bo/word_bo.dart';
import '../../util/app_clock.dart';

class DictWordsProvider implements WordsProvider, WordModifier {
  DictVo dict;

  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  DictWordsProvider(this.dict);

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
  Future<bool> updateMeanings(String wordId, List<Map<String, String>> meanings) async {
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
    try {
      final results = await WordBo().getDictWordsForAPage(dict.id, fromIndex, pageSize);
      final wrappedResults = PagedResults<WordWrapper>(results.total);

      for (var dictWordVo in results.rows) {
        wrappedResults.rows.add(WordWrapper(dictWordVo.word, dictWordVo));
      }

      return wrappedResults;
    } catch (e) {
      Global.logger.e("获取词典单词失败: $e");
      return PagedResults<WordWrapper>(0);
    }
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    try {
      // 从本地数据库中删除dictWord记录
      var dictWord = await _db.dictWordsDao.getById(dict.id, wordWrapper.word.id!);
      await _db.dictWordsDao.deleteEntity(dictWord!, true);

      // 触发同步
      ThrottledDbSyncService().requestSync();

      ToastUtil.info("${wordWrapper.word.spell} 已删除");
      return true;
    } catch (e) {
      ToastUtil.error("删除失败: $e");
      return false;
    }
  }

  @override
  Future<int> getWordIndex(String spell) async {
    var result = await WordBo().getDictWordOrder(dict.id, spell);
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }
}

class DictWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    throw UnimplementedError();
  }

  @override
  double getWordProgressMax(wordTag) {
    throw UnimplementedError();
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
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) return null;

      // 从本地Bookmarks表获取书签
      final bookmarkQuery = _db.select(_db.bookMarks)..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(bookMarkName));

      final bookmark = await bookmarkQuery.getSingleOrNull();

      if (bookmark != null) {
        return BookMarkVo(bookmark.position, bookmark.spell);
      }

      // 如果Bookmarks表没有，检查旧的localParams表
      final paramQuery = _db.select(_db.localParams)..where((p) => p.name.equals(bookMarkName));

      final param = await paramQuery.getSingleOrNull();

      if (param != null) {
        // 解析本地保存的书签 spell:position 格式
        final parts = param.value.split(':');
        if (parts.length == 2) {
          // 找到旧格式书签，迁移到新表
          final bookMark = BookMarkVo(int.tryParse(parts[1]) ?? 0, parts[0]);
          await _saveBookMarkLocally(bookMark);
          // 删除旧记录
          await (_db.delete(_db.localParams)..where((p) => p.name.equals(bookMarkName))).go();
          return bookMark;
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
    // 先保存到本地数据库
    Global.logger.d('保存字典书签: position=[38;5;28m[1m[22m[39m${bookMark.position}, spell=${bookMark.spell}');
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
          await DbLogUtil.logOperation(userId, 'UPDATE', 'bookMarks', bookmark.id, json.encode(bookmark.toJson()));
        }

        ThrottledDbSyncService().requestSync();
      } catch (syncError) {
        // 同步失败，但本地已保存，稍后可以再次同步
      }
    }

    return success;
  }
}

Future<dynamic>? toDictWordsListPage(String dictId, bool showDelBtn) async {
  try {
    // 从本地数据库获取词典信息
    var db = MyDatabase.instance;
    final dictQuery = db.select(db.dicts)..where((d) => d.id.equals(dictId));

    final dictEntry = await dictQuery.getSingleOrNull();
    DictVo dict;

    if (dictEntry != null) {
      // 使用本地数据
      dict = DictVo.c2(dictEntry.id);
      dict.name = dictEntry.name;
      dict.shortName = getShortName(dictEntry.name);
      dict.wordCount = dictEntry.wordCount;
      dict.isReady = dictEntry.isReady;
      dict.isShared = dictEntry.isShared;
      dict.visible = dictEntry.visible;
    } else {
      // 如果本地没有，创建一个默认词典对象
      dict = DictVo.c2(dictId);
      dict.name = "词典(本地模式)";
      dict.shortName = "词典";
      dict.isReady = true;
      dict.isShared = false;
      dict.visible = true;

      // 保存到本地数据库
      await db.into(db.dicts).insert(
            Dict(
              id: dict.id,
              isReady: true,
              isShared: false,
              name: dict.name ?? '词典',
              wordCount: 0,
              ownerId: Global.getLoggedInUser()?.id ?? 'local',
              visible: true,
              createTime: AppClock.now(),
              updateTime: AppClock.now(),
            ),
          );
    }

    return Get.toNamed('/word_list',
        arguments: WordListPageArgs(
            dict.shortName!, DictWordsProvider(dict), true, showDelBtn, false, '', DictWordsProgressProvider(), DictWordsBookMarkProvider(dict), null)
          ..canAddWord = showDelBtn
          ..canEditWord = showDelBtn);
  } catch (e) {
    ToastUtil.error("无法打开词典");
    rethrow;
  }
}

String getShortName(String name) {
  if (name.endsWith(".dict")) {
    return name.substring(0, name.lastIndexOf("."));
  } else {
    return name;
  }
}
