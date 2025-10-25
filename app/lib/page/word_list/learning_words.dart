import 'package:get/get.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

import '../../util/word_util.dart';
import '../../util/app_clock.dart';

class LearningWordsProvider implements WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await WordBo().getLearningWordsForAPage(fromIndex, pageSize, Global.getLoggedInUser()!.id);
    var results = PagedResults<WordWrapper>(words.total);
    for (var word in words.rows) {
      var wrapper = WordWrapper(word.word, word);
      results.rows.add(wrapper);
    }
    return results;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    var result = await WordBo().setLearningWordAsMastered(Global.getLoggedInUser()!.id, wordWrapper.word.id!, false);
    if (result.success) {
      ToastUtil.info("${wordWrapper.word.spell} 成功标记为已掌握");
    } else {
      ToastUtil.error(result.msg!);
    }
    return result.success;
  }

  @override
  Future<int> getWordIndex(String spell) async {
    var result = await WordBo().getLearningWordOrder(spell, Global.getLoggedInUser()!.id);
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }
}

class LearningWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 5.0 - (wordTag as LearningWordVo).lifeValue;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5.0;
  }
}

class LearningWordsBookMarkProvider implements BookMarkProvider {
  static const String bookMarkName = 'learning_words_list';
  final _db = MyDatabase.instance;

  @override
  Future<BookMarkVo?> getBookMark() async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        Global.logger.e('获取书签失败：用户未登录');
        return null;
      }

      // 从本地Bookmarks表获取书签
      final bookmarkQuery = _db.select(_db.bookMarks)..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(bookMarkName));

      final bookmark = await bookmarkQuery.getSingleOrNull();

      if (bookmark != null) {
        Global.logger.d('获取书签成功: name=$bookMarkName, position=${bookmark.position}, spell=${bookmark.spell}');
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

      Global.logger.d('未找到书签: name=$bookMarkName');
      return null;
    } catch (e, stackTrace) {
      Global.logger.e('获取书签失败: $e', stackTrace: stackTrace);
      return null;
    }
  }

  // 在本地保存书签
  Future<bool> _saveBookMarkLocally(BookMarkVo bookMark) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        Global.logger.e('保存书签失败：用户未登录');
        return false;
      }

      final uuid = Uuid().v4();

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

      Global.logger.d('书签已保存到本地: name=$bookMarkName, position=${bookMark.position}, spell=${bookMark.spell}');

      // 尝试将修改同步到服务器
      try {
        ThrottledDbSyncService().requestSync();
        Global.logger.d('书签已触发数据库同步');
      } catch (syncError) {
        // 同步失败，但本地已保存，稍后可以再次同步
        Global.logger.e('同步数据库异常: $syncError');
      }

      return true;
    } catch (e, stackTrace) {
      Global.logger.e('保存书签失败: $e', stackTrace: stackTrace);
      return false;
    }
  }

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    return await _saveBookMarkLocally(bookMark);
  }
}

Future<dynamic>? toLearningWordsListPage(bool showDelBtn) {
  return Get.toNamed('/word_list',
      arguments: WordListPageArgs(
          '学习中', LearningWordsProvider(), true, showDelBtn, true, '掌握度', LearningWordsProgressProvider(), LearningWordsBookMarkProvider(), null));
}
