import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/util/app_clock.dart';

class BookmarkBo {
  static final BookmarkBo _instance = BookmarkBo._internal();

  factory BookmarkBo() {
    return _instance;
  }

  BookmarkBo._internal();

  Future<Result<BookMarkVo>> getBookMark(String bookMarkName) async {
    try {
      final user = Global.getLoggedInUser();
      final userId = user?.id;
      if (userId == null) {
        Global.logger.e('获取书签失败：用户未登录');
        final result = Result<BookMarkVo>("ERROR", "用户未登录", false);
        result.data = null;
        return result;
      }

      final db = MyDatabase.instance;
      final query = db.select(db.bookMarks)
        ..where((b) => b.userId.equals(userId))
        ..where((b) => b.bookMarkName.equals(bookMarkName));

      final bookmark = await query.getSingleOrNull();

      if (bookmark != null) {
        final bookmarkVo = BookMarkVo(bookmark.position, bookmark.spell);
        bookmarkVo.bookMarkName = bookmark.bookMarkName;

        Global.logger.d(
            '获取书签成功: name=$bookMarkName, position=${bookmark.position}, spell=${bookmark.spell}');
        final result = Result<BookMarkVo>("SUCCESS", "获取成功", true);
        result.data = bookmarkVo;
        return result;
      }

      Global.logger.d('未找到书签: name=$bookMarkName');
      final result = Result<BookMarkVo>("SUCCESS", "获取成功", true);
      result.data = null;
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('获取书签失败: $e', stackTrace: stackTrace);
      final result =
          Result<BookMarkVo>("ERROR", "获取书签失败: ${e.toString()}", false);
      result.data = null;
      return result;
    }
  }

  Future<Result> saveBookMark(
      String bookMarkName, String spell, int position, String userId) async {
    try {
      Global.logger.d(
          '开始保存书签: name=$bookMarkName, position=$position, spell=$spell, userId=$userId');
      final db = MyDatabase.instance;

      // 检查用户是否存在
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('保存书签失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }

      // 查询是否存在同名书签
      final existingBookmark =
          await db.bookmarksDao.findByUserIdAndName(userId, bookMarkName);
      final now = AppClock.now();

      // 创建或更新书签
      final id = existingBookmark?.id ?? now.millisecondsSinceEpoch.toString();
      final bookmark = BookMark(
        id: id,
        userId: userId,
        bookMarkName: bookMarkName,
        spell: spell,
        position: position,
        createTime: existingBookmark?.createTime ?? now,
        updateTime: now,
      );

      // 保存书签
      await db.bookmarksDao.saveBookmark(bookmark, true);
      Global.logger.d('书签已保存到本地: id=$id, name=$bookMarkName');

      // 尝试将修改同步到服务器
      try {
        ThrottledDbSyncService().requestSync();
        Global.logger.d('书签已触发数据库同步');
      } catch (syncError) {
        Global.logger.e('同步数据库异常: $syncError');
      }

      return Result("SUCCESS", "保存成功", true);
    } catch (e, stackTrace) {
      Global.logger.e('保存书签失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "保存书签失败: ${e.toString()}", false);
    }
  }
}


