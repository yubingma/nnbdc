import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/vo.dart';
import '../db/db.dart';
import '../global.dart';
import '../util/prefs.dart';
import '../util/toast_util.dart';
import 'walkman.dart';
import 'word_list/bucket_words.dart';
import 'word_list/confusable_words.dart';
import 'word_list/dict_words.dart';
import 'word_list/learning_words.dart';
import 'word_list/mastered_words.dart';
import 'word_list/root_family_words.dart';
import 'word_list/today_new_words.dart';
import 'word_list/today_old_words.dart';
import 'word_list/today_words.dart';
import 'word_list/word_list.dart';
import 'word_list/wrong_words.dart';

/// 随身听的独立启动入口：不依赖任何词表页面的上下文。
///
/// 听哪个词表由「上次收听的数据源」决定——书签名即数据源标识，随身听推进书签时记下；
/// 首次使用、上次的数据源不持久化书签、或那本词书已被删除时，回落今日任务。
class WalkmanLauncher {
  /// 「上次收听的数据源」在本地偏好里的键
  static const String lastSourceKey = 'walkman_last_source';

  /// 上次收听数据源的展示名，随身听顶部要显示它
  static const String lastSourceTitleKey = 'walkman_last_source_title';

  /// 已落盘的数据源，避免随身听每推进一个词就写一次本地偏好
  static String? _remembered;

  /// 记下本次收听的数据源与名称，供下次续播
  static Future<void> remember(String? bookMarkName, String? title) async {
    if (bookMarkName != null && bookMarkName != _remembered) {
      if (await Prefs.write(lastSourceKey, bookMarkName)) {
        _remembered = bookMarkName;
      }
    }
    // 名称单独判断：同一个数据源的名称也会变（兜底名 → 词表页里的精确标题），不能跟着数据源一起跳过
    if (title != null && title != Prefs.read<String>(lastSourceTitleKey)) {
      await Prefs.write(lastSourceTitleKey, title);
    }
  }

  /// 打开随身听
  static Future<void> open(BuildContext context) async {
    if (Global.getLoggedInUser() == null) {
      ToastUtil.info('登录后才能使用随身听');
      return;
    }
    final params = await resolveParams();
    if (!context.mounted) return;
    await context.push('/walkman', extra: params);
  }

  /// 解析这次要听的数据源：优先续播上次的，源已不存在则回落今日任务
  static Future<WalkmanParams> resolveParams() async {
    final last = Prefs.read<String>(lastSourceKey);
    if (last != null) {
      final resumed = await _resume(last);
      if (resumed != null) {
        // 名称优先用上次在词表页看到的标题（词书短名、熟练度区间名这类动态标题只有入口知道），
        // 没有记录时（老版本升级上来、或首次从收纳盒进入）用 _resume 兜底的名字，不留空白
        resumed.title = Prefs.read<String>(lastSourceTitleKey) ?? resumed.title;
        return resumed;
      }
    }
    return WalkmanParams(TodayWordsProvider(),
        bookMarkProvider: TodayWordsBookMarkProvider(), title: '今日单词');
  }

  /// 按书签名重建数据源；返回 null 表示这个名字已经没有对应的词表可听了
  static Future<WalkmanParams?> _resume(String bookMarkName) async {
    // 词书词表：书签名里带着词书 id，先确认那本词书还在
    if (bookMarkName.startsWith(DictWordsBookMarkProvider.namePrefix) &&
        bookMarkName.endsWith(DictWordsBookMarkProvider.nameSuffix)) {
      final dictId = bookMarkName.substring(
          DictWordsBookMarkProvider.namePrefix.length,
          bookMarkName.length - DictWordsBookMarkProvider.nameSuffix.length);
      final dict = await MyDatabase.instance.dictsDao.findById(dictId);
      if (dict == null) return null;
      final dictVo = DictVo.c2(dict.id)..name = dict.name;
      return WalkmanParams(DictWordsProvider(dictVo),
          bookMarkProvider: DictWordsBookMarkProvider(dictVo),
          title: dict.name);
    }

    // 生词本桶：书签名里带着桶号
    if (bookMarkName.startsWith(BucketWordsBookMarkProvider.namePrefix)) {
      final bucketKey = int.tryParse(bookMarkName
          .substring(BucketWordsBookMarkProvider.namePrefix.length));
      if (bucketKey == null) return null;
      return WalkmanParams(BucketWordsProvider(bucketKey),
          bookMarkProvider: BucketWordsBookMarkProvider(bucketKey),
          title: bucketKey == 9999 ? '新词库' : '生词本');
    }

    // 固定数据源：书签名 ↔ 数据源 ↔ 兜底展示名写在一起，新增数据源时不会漏配名字
    final fixed = <(BookMarkProvider, WordsProvider, String)>[
      (TodayWordsBookMarkProvider(), TodayWordsProvider(), '今日单词'),
      (TodayNewWordsBookMarkProvider(), TodayNewWordsProvider(), '今日新词'),
      (TodayOldWordsBookMarkProvider(), TodayOldWordsProvider(), '今日旧词'),
      (LearningWordsBookMarkProvider(), LearningWordsProvider(), '学习中'),
      (MasteredWordsBookMarkProvider(), MasteredWordsProvider(), '已掌握'),
      (ConfusableWordsBookMarkProvider(), ConfusableWordsProvider(), '形近词'),
      (RootFamilyWordsBookMarkProvider(), RootFamilyWordsProvider(), '同根词'),
      (WrongWordsBookMarkProvider(), WrongWordsProvider(), '错词'),
      (WrongWordsBookMarkProvider(isHistory: true),
          WrongWordsProvider(isHistory: true), '历史错词'),
    ];
    for (final (mark, words, title) in fixed) {
      if (mark.bookMarkName == bookMarkName) {
        return WalkmanParams(words, bookMarkProvider: mark, title: title);
      }
    }
    return null;
  }
}
