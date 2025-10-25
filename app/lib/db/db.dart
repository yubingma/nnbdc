import 'package:drift/drift.dart';
import 'package:nnbdc/db/dao.dart';
import 'package:nnbdc/db/table.dart';
import 'package:nnbdc/db/shared.dart';

part 'db.g.dart';

@DriftDatabase(tables: [
  Users,
  LocalParams,
  Levels,
  VotedSentences,
  VotedChineses,
  VotedWordImages,
  LearningDicts,
  Dicts,
  Words,
  UserDbLogs,
  UserDbVersions,
  DictWords,
  WordImages,
  VerbTenses,
  Synonyms,
  SimilarWords,
  Cigens,
  CigenWordLinks,
  MeaningItems,
  Sentences,
  LearningWords,
  BookMarks,
  DictGroups,
  GroupAndDictLinks,
  UserStudySteps,
  Dakas,
  UserOpers,
  MasteredWords,
  UserCowDungLogs,
  UserWrongWords,
  SysDbVersion,
  WordShortDescChineses,
], daos: [
  UsersDao,
  LocalParamsDao,
  VotedSentencesDao,
  VotedChinesesDao,
  VotedWordImagesDao,
  LearningDictsDao,
  DictsDao,
  WordsDao,
  UserDbLogsDao,
  UserDbVersionsDao,
  DictWordsDao,
  WordImagesDao,
  VerbTensesDao,
  SynonymsDao,
  SimilarWordsDao,
  CigensDao,
  CigenWordLinksDao,
  MeaningItemsDao,
  SentencesDao,
  LearningWordsDao,
  LevelsDao,
  DictGroupsDao,
  GroupAndDictLinksDao,
  UserStudyStepsDao,
  DakasDao,
  UserOpersDao,
  MasteredWordsDao,
  BookmarksDao,
  UserCowDungLogsDao,
  UserWrongWordsDao,
  SysDbVersionDao,
  WordShortDescChinesesDao,
])
class MyDatabase extends _$MyDatabase {
  MyDatabase(super.e);

  static MyDatabase? _instance;

  static MyDatabase get instance {
    _instance ??= constructDb();
    return _instance!;
  }

  static void closeDatabase() {
    if (_instance != null) {
      _instance!.close();
      _instance = null;
    }
  }

  // we tell the database where to store the data with this constructor
  //MyDatabase() : super(_openConnection());

  // you should bump this number whenever you change or add a table definition. Migrations
  // are covered later in this readme.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // 创建系统所有表
        await m.createAll();

        // 创建性能优化索引（新安装时直接创建）
        await _createPerformanceIndexes();

        // 初始化数据
        await batch((b) {
          b.insertAll(localParams, [
            LocalParamsCompanion.insert(name: 'isDarkMode', value: 'false'),
          ]);
        });
      },

      onUpgrade: (Migrator m, int from, int to) async {
        
      },
      
      beforeOpen: (details) async {

      },
    );
  }

  /// 创建性能优化索引的共用方法
  /// 注意：Drift会自动将驼峰命名转换为下划线命名
  Future<void> _createPerformanceIndexes() async {
    // 为learning_words表添加复合索引以优化常见查询
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_life 
      ON learning_words (user_id, life_value)
    ''');
    
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_learning_date 
      ON learning_words (user_id, last_learning_date)
    ''');
    
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_today_new 
      ON learning_words (user_id, is_today_new_word, last_learning_date)
    ''');
    
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_add_time_life 
      ON learning_words (add_time, life_value, word_id)
    ''');
    
    // 为meaning_items表添加索引以优化释义查询
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_meaning_items_word_dict 
      ON meaning_items (word_id, dict_id)
    ''');
    
    
    // 为dict_words表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_dict_words_dict_seq 
      ON dict_words (dict_id, seq)
    ''');
    
    // 为learning_dicts表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_dicts_user 
      ON learning_dicts (user_id)
    ''');
    
    // 为mastered_words表添加索引（现在统一使用下划线格式）
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mastered_words_user 
      ON mastered_words (user_id)
    ''');
    
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mastered_words_user_time 
      ON mastered_words (user_id, master_at_time)
    ''');
    
    // 为sentences表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sentences_meaning_item 
      ON sentences (meaning_item_id)
    ''');
    
    // UserStageWords table has been removed
    
    // 为words表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_words_spell 
      ON words (spell)
    ''');
  }

  /// 清空本地数据（彻底清空，等同于重新安装）
  ///
  /// 将会清空数据库中所有表的数据，包括登录信息与本地设置。
  /// 注意：调用后应用将回到近似初始安装状态。
  Future<void> wipeLocalData() async {
    // 直接复用全清逻辑，保持与“重新安装”效果一致
    await wipeAllTables();
  }

  /// 清空数据库中所有表的数据（包括用户与本地设置）
  /// 使用后应用将回到近似初始安装状态
  Future<void> wipeAllTables() async {
    await transaction(() async {
      await customStatement('PRAGMA foreign_keys = OFF');

      // 先清理强依赖子表（按依赖层级从深到浅）
      await delete(votedSentences).go(); // 依赖 users, sentences
      await delete(votedChineses).go(); // 依赖 users, wordShortDescChineses
      await delete(votedWordImages).go(); // 依赖 users, wordImages
      await delete(synonyms).go(); // 依赖 meaningItems, words
      await delete(sentences).go(); // 依赖 meaningItems
      await delete(meaningItems).go(); // 依赖 words, dicts(可选)
      await delete(dictWords).go(); // 依赖 dicts, words
      await delete(wordImages).go(); // 依赖 words
      await delete(verbTenses).go(); // 依赖 words
      await delete(similarWords).go(); // 依赖 words
      await delete(cigenWordLinks).go(); // 依赖 cigens, words
      await delete(cigens).go();
      await delete(wordShortDescChineses).go(); // 依赖 words

      await delete(learningWords).go();
      await delete(masteredWords).go();
      await delete(userWrongWords).go();
      await delete(bookMarks).go();
      await delete(userStudySteps).go();
      await delete(dakas).go();
      await delete(userOpers).go();
      await delete(userCowDungLogs).go();

      await delete(learningDicts).go();
      await delete(groupAndDictLinks).go(); // 依赖 dictGroups 和 dicts，需先删
      await delete(dicts).go();

      await delete(userDbLogs).go();
      await delete(userDbVersions).go();

      await delete(words).go();
      await delete(levels).go();
      await delete(dictGroups).go();
      await delete(sysDbVersion).go();
      await delete(localParams).go();
      await delete(users).go();

      await customStatement('PRAGMA foreign_keys = ON');
    });
  }
}
