import 'package:nnbdc/global.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../db/db.dart';
import '../util/custom_convert.dart';

part 'vo.g.dart';

class StudyProgress {
  int existDays;
  int dakaDayCount;
  double? dakaRatio;
  int totalScore;
  int? userOrder;
  int rawWordCount;
  int cowDung;
  LevelVo level;
  int masteredWordsCount;
  int learningWordsCount;
  int wordsPerDay;
  int continuousDakaDayCount;
  int throwDiceChance;
  bool allDictsFinished;
  bool todayLearningFinished;
  List<LearningDict> learningDicts;

  StudyProgress(
      this.existDays,
      this.dakaDayCount,
      this.dakaRatio,
      this.totalScore,
      this.userOrder,
      this.rawWordCount,
      this.cowDung,
      this.level,
      this.masteredWordsCount,
      this.learningWordsCount,
      this.wordsPerDay,
      this.continuousDakaDayCount,
      this.throwDiceChance,
      this.allDictsFinished,
      this.todayLearningFinished,
      this.learningDicts);
}

@JsonSerializable()
class LevelVo {
  String id;

  int? level;

  String? name;

  String? figure;

  int? minScore;

  int? maxScore;

  String? style;

  LevelVo(this.id);

  factory LevelVo.fromJson(Map<String, dynamic> json) =>
      _$LevelVoFromJson(json);

  Map<String, dynamic> toJson() => _$LevelVoToJson(this);
}

@JsonSerializable()
class LearningDictVo {
  DictVo dict;
  int? currentWordSeq;
  bool isPrivileged;

  LearningDictVo(this.dict, this.currentWordSeq, this.isPrivileged);

  factory LearningDictVo.fromJson(Map<String, dynamic> json) =>
      _$LearningDictVoFromJson(json);

  Map<String, dynamic> toJson() => _$LearningDictVoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
// ignore: must_be_immutable
class DictVo extends Equatable {
  String id;
  String? name;
  String? shortName;
  UserVo? owner;

  /// 对于用户自定义的单词书，该标志指明该单词书是否已经共享给其他用户
  bool? isShared;

  /// 该单词书是否已经准备就绪（只有准备就绪的单词书才能供用户使用，并且一旦就绪后就不能再编辑）
  bool? isReady;
  bool? visible;
  List<DictWordVo>? dictWords;

  /// 该单词书的单词数量
  int? wordCount;

  DateTime? createTime;
  DateTime? updateTime;

  DictVo.c2(this.id, [this.wordCount]);

  DictVo(
      this.id,
      this.name,
      this.shortName,
      this.owner,
      this.isShared,
      this.isReady,
      this.visible,
      this.dictWords,
      this.wordCount,
      this.createTime);

  factory DictVo.fromJson(Map<String, dynamic> json) => _$DictVoFromJson(json);

  Map<String, dynamic> toJson() => _$DictVoToJson(this);

  @override
  List<Object?> get props => [id];
}

@JsonSerializable()
class UserVo {
  String? id;

  String? userName;

  String? nickName;

  bool? hasDakaToday;

  int? gameScore;

  String? password;

  /// 打卡积分
  int? dakaScore;

  /// 是否直接显示备选答案
  bool? showAnswersDirectly;

  /// 是否自动朗读单词发音
  bool? autoPlayWord;

  DateTime? lastLoginTime;

  DateTime? lastShareTime;

  String? email;

  DateTime? lastLearningDate;

  int? learnedDays;

  int? lastLearningPosition;

  int? lastLearningMode;

  bool? learningFinished;

  bool? inviteAwardTaken;

  bool? isSuper;

  bool? isAdmin;

  bool? isInputor;

  bool? isTodayLearningStarted;

  bool? isTodayLearningFinished;

  bool? autoPlaySentence;

  int? wordsPerDay;

  int? dakaDayCount;

  int? masteredWordsCount;

  int? cowDung;

  int? throwDiceChance;

  String? displayNickName;

  UserVo? invitedBy;

  LevelVo? level;

  /// 连续打卡天数
  int? continuousDakaDayCount;

  /// 最大连续打卡天数
  int? maxContinuousDakaDayCount;

  /// 最近一次打卡的日期
  DateTime? lastDakaDate;

  int? totalScore;

  double? dakaRatio;

  bool? enableAllWrong;

  UserVo(this.id, this.userName);

  UserVo.c2(this.id);

  /// 从User对象创建UserVo对象（只包含基本数据类型的属性）
  static UserVo fromUser(User user) {
    final userVo = UserVo(user.id, user.userName);

    userVo.nickName = user.nickName;
    userVo.gameScore = user.gameScore;
    userVo.password = user.password;
    userVo.dakaScore = user.dakaScore;
    userVo.showAnswersDirectly = user.showAnswersDirectly;
    userVo.autoPlayWord = user.autoPlayWord;
    userVo.lastLoginTime = user.lastLoginTime;
    userVo.lastShareTime = user.lastShareTime;
    userVo.email = user.email;
    userVo.lastLearningDate = user.lastLearningDate;
    userVo.learnedDays = user.learnedDays;
    userVo.lastLearningPosition = user.lastLearningPosition;
    userVo.lastLearningMode = user.lastLearningMode;
    userVo.learningFinished = user.learningFinished;
    userVo.inviteAwardTaken = user.inviteAwardTaken;
    userVo.isSuper = user.isSuper;
    userVo.isAdmin = user.isAdmin;
    userVo.isInputor = user.isInputor;
    userVo.isTodayLearningStarted = user.isTodayLearningStarted;
    userVo.isTodayLearningFinished = user.isTodayLearningFinished;
    userVo.autoPlaySentence = user.autoPlaySentence;
    userVo.wordsPerDay = user.wordsPerDay;
    userVo.dakaDayCount = user.dakaDayCount;
    userVo.masteredWordsCount = user.masteredWordsCount;
    userVo.cowDung = user.cowDung;
    userVo.throwDiceChance = user.throwDiceChance;
    userVo.displayNickName = user.nickName;
    userVo.continuousDakaDayCount = user.continuousDakaDayCount;
    userVo.maxContinuousDakaDayCount = user.maxContinuousDakaDayCount;
    userVo.lastDakaDate = user.lastDakaDate;
    userVo.totalScore = user.totalScore;
    userVo.dakaRatio = user.dakaRatio;
    userVo.enableAllWrong = user.enableAllWrong;

    userVo.password = user.password;
    userVo.lastLoginTime = user.lastLoginTime;

    return userVo;
  }

  factory UserVo.fromJson(Map<String, dynamic> json) => _$UserVoFromJson(json);

  Map<String, dynamic> toJson() => _$UserVoToJson(this);

  @override
  String toString() {
    return 'UserVo{id: $id, userName: $userName, nickName: $nickName, hasDakaToday: $hasDakaToday, gameScore: $gameScore, password: $password, dakaScore: $dakaScore, showAnswersDirectly: $showAnswersDirectly, autoPlayWord: $autoPlayWord, lastLoginTime: $lastLoginTime, lastShareTime: $lastShareTime, email: $email, lastLearningDate: $lastLearningDate, learnedDays: $learnedDays, lastLearningPosition: $lastLearningPosition, lastLearningMode: $lastLearningMode, learningFinished: $learningFinished, inviteAwardTaken: $inviteAwardTaken, isSuper: $isSuper, isAdmin: $isAdmin, isInputor: $isInputor, isTodayLearningStarted: $isTodayLearningStarted, isTodayLearningFinished: $isTodayLearningFinished, autoPlaySentence: $autoPlaySentence, wordsPerDay: $wordsPerDay, dakaDayCount: $dakaDayCount, masteredWordsCount: $masteredWordsCount, cowDung: $cowDung, throwDiceChance: $throwDiceChance, displayNickName: $displayNickName, invitedBy: $invitedBy, level: $level, continuousDakaDayCount: $continuousDakaDayCount, maxContinuousDakaDayCount: $maxContinuousDakaDayCount, lastDakaDate: $lastDakaDate, totalScore: $totalScore, dakaRatio: $dakaRatio, enableAllWrong: $enableAllWrong}';
  }

  bool isGuest() {
    return userName!.startsWith("guest_");
  }
}

@JsonSerializable()
@CustomDateTimeConverter()
class DictWordVo {
  DictVo dict;

  WordVo word;

  int seq;

  DateTime? createTime;
  DateTime? updateTime;

  DictWordVo(this.dict, this.word, this.seq);

  factory DictWordVo.fromJson(Map<String, dynamic> json) =>
      _$DictWordVoFromJson(json);

  Map<String, dynamic> toJson() => _$DictWordVoToJson(this);
}

@JsonSerializable()
class SynonymsItem {
  String meaning;
  List<String> words;

  SynonymsItem(this.meaning, this.words);

  factory SynonymsItem.fromJson(Map<String, dynamic> json) =>
      _$SynonymsItemFromJson(json);

  Map<String, dynamic> toJson() => _$SynonymsItemToJson(this);
}

@JsonSerializable()
class SentenceVo {
  String id;

  String? english;
  String? chinese;
  String? wordMeaning;

  String? englishDigest;

  String theType;
  int footCount;
  int handCount;
  UserVo author;

  bool? voted;

  SentenceVo(this.id, this.english, this.chinese, this.englishDigest,
      this.theType, this.footCount, this.handCount, this.author);

  factory SentenceVo.fromJson(Map<String, dynamic> json) =>
      _$SentenceVoFromJson(json);

  Map<String, dynamic> toJson() => _$SentenceVoToJson(this);
}

@JsonSerializable()
class SentenceChineseRemarkVo {
  String id;
  String creator;
  String content;

  SentenceChineseRemarkVo(this.id, this.creator, this.content);

  factory SentenceChineseRemarkVo.fromJson(Map<String, dynamic> json) =>
      _$SentenceChineseRemarkVoFromJson(json);

  Map<String, dynamic> toJson() => _$SentenceChineseRemarkVoToJson(this);
}

@JsonSerializable()
class CigenVo {
  String id;

  String description;

  CigenVo(this.id, this.description);

  factory CigenVo.fromJson(Map<String, dynamic> json) =>
      _$CigenVoFromJson(json);

  Map<String, dynamic> toJson() => _$CigenVoToJson(this);
}

@JsonSerializable()
class CigenWordLinkVo {
  CigenVo cigen;

  String theExplain;

  CigenWordLinkVo(this.cigen, this.theExplain);

  factory CigenWordLinkVo.fromJson(Map<String, dynamic> json) =>
      _$CigenWordLinkVoFromJson(json);

  Map<String, dynamic> toJson() => _$CigenWordLinkVoToJson(this);
}

@JsonSerializable()
class WordShortDescChineseVo {
  String id;

  WordVo? word;

  int hand;

  int foot;

  UserVo author;

  String content;

  WordShortDescChineseVo(
      this.id, this.word, this.hand, this.foot, this.author, this.content);

  factory WordShortDescChineseVo.fromJson(Map<String, dynamic> json) =>
      _$WordShortDescChineseVoFromJson(json);

  Map<String, dynamic> toJson() => _$WordShortDescChineseVoToJson(this);
}

@JsonSerializable()
@CustomDateTimeConverter()
class WordVo {
  String? id;
  String spell;
  String? britishPronounce;
  String? americaPronounce;
  String? pronounce;
  int? popularity;
  String? groupInfo;
  String? longDesc;
  String? shortDesc;
  String? meaningStr;
  DateTime? createTime;
  DateTime? updateTime;
  List<MeaningItemVo>? meaningItems;
  List<WordVo>? similarWords;
  List<CigenWordLinkVo>? cigenWordLinks;
  List<WordShortDescChineseVo>? shortDescChineses;
  List<WordImageVo>? images;

  WordVo.c2(this.spell);

  WordVo(
      this.id,
      this.spell,
      this.britishPronounce,
      this.americaPronounce,
      this.pronounce,
      this.popularity,
      this.groupInfo,
      this.shortDesc,
      this.meaningStr,
      this.meaningItems,
      this.similarWords,
      this.cigenWordLinks,
      this.shortDescChineses,
      this.longDesc,
      this.createTime,
      this.updateTime);

  get sentences {
    List<SentenceVo> sentences = [];
    if (meaningItems != null) {
      for (MeaningItemVo meaningItemVo in meaningItems!) {
        if (meaningItemVo.sentences != null) {
          sentences.addAll(meaningItemVo.sentences!);
        }
      }
    }
    return sentences;
  }

  setMeaningStr(String meaningStr) {
    this.meaningStr = meaningStr;
  }

  // 安全获取例句列表的方法，避免空指针异常
  Future<List<SentenceVo>> getSentences() async {
    // 初始化一个空列表存储所有例句
    List<SentenceVo> sentences = [];

    // 检查meaningItems是否为null，如果是则直接返回空列表
    if (meaningItems == null || meaningItems!.isEmpty) {
      return sentences;
    }

    // 遍历所有的释义项并异步获取例句
    for (MeaningItemVo meaningItem in meaningItems!) {
      // 从每个释义项获取例句并添加到结果中
      if (meaningItem.sentences != null && meaningItem.sentences!.isNotEmpty) {
        // 如果已有例句数据，直接使用
        sentences.addAll(meaningItem.sentences!);
      } else {
        // 如果没有例句数据，从数据库查询
        List<SentenceVo> dbSentences = await meaningItem.getSentences();
        sentences.addAll(dbSentences);
      }
    }

    return sentences;
  }

  get mergedPronounce {
    var pron = pronounce ?? "";
    if (pron.isEmpty) {
      pron = americaPronounce ?? "";
    }
    if (pron.isEmpty) {
      pron = britishPronounce ?? "";
    }
    return pron;
  }

  factory WordVo.fromJson(Map<String, dynamic> json) => _$WordVoFromJson(json);

  Map<String, dynamic> toJson() => _$WordVoToJson(this);

  /// 将相同词性的释义项合并, 并对释义项进行去重
  /// 同时过滤词性为空且内容重复的释义项
  List<MeaningItemVo> getMergedMeaningItems() {
    if (meaningItems == null || meaningItems!.isEmpty) {
      return [];
    }

    // 按词性分组
    Map<String, List<MeaningItemVo>> meaningItemsByCixing = {};
    for (MeaningItemVo meaningItemVo in meaningItems!) {
      String ciXing = meaningItemVo.ciXing ?? '';
      meaningItemsByCixing[ciXing] = meaningItemsByCixing[ciXing] ?? [];
      meaningItemsByCixing[ciXing]!.add(meaningItemVo);
    }

    // 合并同一词性下的不同释义
    List<MeaningItemVo> mergedMeaningItems = [];
    Map<String, MeaningItemVo> tempMergedItems = {}; // 临时存储合并后的项，用于后续处理

    meaningItemsByCixing.forEach((ciXing, items) {
      Set<String> meanings = {};
      Set<String> addedSubParts = {};
      for (MeaningItemVo item in items) {
        if (item.meaning != null) {
          List<String> rawParts = item.meaning!.split(RegExp(r'[;；]'));
          List<String> parts = [];
          for (String rawPart in rawParts) {
            List<String> subParts = rawPart.trim().split(RegExp(r'[，,、]'));
            String part = '';
            for (int i = 0; i < subParts.length; i++) {
              String subPart = subParts[i].trim();
              if (subPart.isNotEmpty) {
                if (!addedSubParts.contains(subPart)) {
                  part += '$subPart${i < subParts.length - 1 ? '，' : ''}';
                  addedSubParts.add(subPart);
                }
              }
            }
            if (part.isNotEmpty) {
              parts.add(part);
            }
          }
          meanings.addAll(parts);
        }
      }

      StringBuffer sb = StringBuffer();
      for (String meaning in meanings) {
        if (meaning.trim().isNotEmpty) {
          sb.write(meaning.trim());
          sb.write('；');
        }
      }

      MeaningItemVo mergedItem = MeaningItemVo(
          null, // id
          ciXing,
          sb.toString(),
          null, // dict
          null, // synonyms
          null // sentences
          );

      tempMergedItems[ciXing] = mergedItem;
    });

    // 处理词性合并逻辑
    // 1. 检查vt.和vi.是否完全相同
    if (tempMergedItems.containsKey('vt.') &&
        tempMergedItems.containsKey('vi.')) {
      String vtMeaning = tempMergedItems['vt.']!.meaning ?? '';
      String viMeaning = tempMergedItems['vi.']!.meaning ?? '';
      if (vtMeaning == viMeaning) {
        // vt.和vi.完全相同，合并为v.
        tempMergedItems['v.'] =
            MeaningItemVo(null, 'v.', vtMeaning, null, null, null);
        tempMergedItems.remove('vt.');
        tempMergedItems.remove('vi.');
      }
    }

    // 2. 检查v.与vt./vi.是否相同
    if (tempMergedItems.containsKey('v.')) {
      String vMeaning = tempMergedItems['v.']!.meaning ?? '';
      if (tempMergedItems.containsKey('vt.') &&
          tempMergedItems['vt.']!.meaning == vMeaning) {
        tempMergedItems.remove('vt.');
      }
      if (tempMergedItems.containsKey('vi.') &&
          tempMergedItems['vi.']!.meaning == vMeaning) {
        tempMergedItems.remove('vi.');
      }
    }

    // 3. 过滤词性为空且内容重复的释义项
    // 收集所有有词性的释义项的内容（分割为子项进行比对）
    Set<String> meaningPartsWithCixing = {};
    tempMergedItems.forEach((ciXing, item) {
      if (ciXing.isNotEmpty && item.meaning != null) {
        // 将释义按分号和逗号分割为子项
        List<String> parts = item.meaning!.split(RegExp(r'[;；，,、]'));
        for (String part in parts) {
          String trimmed = part.trim();
          if (trimmed.isNotEmpty) {
            meaningPartsWithCixing.add(trimmed);
          }
        }
      }
    });

    // 检查词性为空的释义项
    if (tempMergedItems.containsKey('')) {
      MeaningItemVo? emptyItem = tempMergedItems[''];
      if (emptyItem != null && emptyItem.meaning != null) {
        // 将词性为空的释义分割为子项
        List<String> emptyParts = emptyItem.meaning!.split(RegExp(r'[;；，,、]'));
        bool shouldRemove = true;
        
        // 检查是否所有子项都已在有词性的释义中出现
        for (String part in emptyParts) {
          String trimmed = part.trim();
          if (trimmed.isNotEmpty && !meaningPartsWithCixing.contains(trimmed)) {
            // 发现有独特的内容，不应移除
            shouldRemove = false;
            break;
          }
        }
        
        // 如果所有内容都重复了，移除该词性为空的释义项
        if (shouldRemove) {
          tempMergedItems.remove('');
        }
      }
    }

    // 将处理后的项添加到结果列表
    mergedMeaningItems.addAll(tempMergedItems.values);

    return mergedMeaningItems;
  }

  String getMeaningStr() {
    if (meaningStr != null) {
      return meaningStr!;
    }

    if (meaningItems == null || meaningItems!.isEmpty) {
      return '';
    }

    // 合并所有词性的释义
    StringBuffer sb = StringBuffer();
    for (MeaningItemVo item in getMergedMeaningItems()) {
      if (item.ciXing != null && item.ciXing!.isNotEmpty) {
        sb.write(item.ciXing);
        sb.write(' ');
      }
      if (item.meaning != null && item.meaning!.isNotEmpty) {
        // 处理多余的分号和逗号
        String meaning = item.meaning!;
        // 删除末尾的分号和逗号
        while (meaning.endsWith(';') ||
            meaning.endsWith('；') ||
            meaning.endsWith(',') ||
            meaning.endsWith('，')) {
          meaning = meaning.substring(0, meaning.length - 1);
        }
        // 删除连续的分号
        meaning = meaning.replaceAll(RegExp(r'[;；]+'), '；');
        // 删除连续的逗号
        meaning = meaning.replaceAll(RegExp(r'[,，]+'), '，');
        // 处理分号和逗号的组合
        meaning = meaning.replaceAll(RegExp(r'[,，]?[;；]'), '；');
        sb.write(meaning);
      }
      // 在每个词性后添加换行符
      sb.write('\n');
    }

    String result = sb.toString();
    // 删除最后一个换行符
    if (result.isNotEmpty && result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }

    return result;
  }
}

@JsonSerializable()
class MeaningItemVo {
  String? id;
  String? ciXing;
  String? meaning;
  DictVo? dict;
  List<SynonymVo>? synonyms;
  List<SentenceVo>? sentences;

  MeaningItemVo(this.id, this.ciXing, this.meaning, this.dict, this.synonyms,
      this.sentences);

  MeaningItemVo.from(this.ciXing, this.meaning);

  /// 安全获取例句列表的方法，避免空指针异常
  Future<List<SentenceVo>> getSentences() async {
    // 初始化一个空列表存储所有例句
    List<SentenceVo> result = [];

    // 检查id是否为空，如果是则直接返回空列表
    if (id == null || id!.isEmpty) {
      return result;
    }

    try {
      // 从本地数据库查询该释义项的所有例句
      final db = MyDatabase.instance;
      final sentencesQuery = db.select(db.sentences)
        ..where((s) => s.meaningItemId.equals(id!));

      final sentenceEntries = await sentencesQuery.get();

      // 将查询结果转换为SentenceVo对象
      for (final sentenceEntry in sentenceEntries) {
        // 创建默认的作者信息
        final author = UserVo.c2(sentenceEntry.authorId);

        // 创建SentenceVo对象
        final sentenceVo = SentenceVo(
            sentenceEntry.id,
            sentenceEntry.english,
            sentenceEntry.chinese,
            sentenceEntry.englishDigest,
            sentenceEntry.theType.isEmpty ? 'tts' : sentenceEntry.theType,
            sentenceEntry.handCount,
            sentenceEntry.footCount,
            author);

        result.add(sentenceVo);
      }
    } catch (e) {
      Global.logger.d('获取释义项例句失败: $e');
    }

    return result;
  }

  factory MeaningItemVo.fromJson(Map<String, dynamic> json) =>
      _$MeaningItemVoFromJson(json);

  Map<String, dynamic> toJson() => _$MeaningItemVoToJson(this);
}

@JsonSerializable()
class SynonymVo {
  MeaningItemVo? meaningItem;

  /// 近义词的ID
  String wordId;

  /// 近义词的拼写
  String spell;

  SynonymVo(this.meaningItem, this.wordId, this.spell);

  factory SynonymVo.fromJson(Map<String, dynamic> json) =>
      _$SynonymVoFromJson(json);

  Map<String, dynamic> toJson() => _$SynonymVoToJson(this);
}

@JsonSerializable()
class VersionInfo {
  String verCode;

  String verName;

  VersionInfo(this.verCode, this.verName);

  factory VersionInfo.fromJson(Map<String, dynamic> json) =>
      _$VersionInfoFromJson(json);

  Map<String, dynamic> toJson() => _$VersionInfoToJson(this);
}

@JsonSerializable()
class DictGroupVo {
  String name;
  List<DictVo>? dicts;
  DictGroupVo? dictGroup;
  List<DictVo>? allDicts;

  DictGroupVo(this.name, this.dicts);

  factory DictGroupVo.fromJson(Map<String, dynamic> json) =>
      _$DictGroupVoFromJson(json);

  Map<String, dynamic> toJson() => _$DictGroupVoToJson(this);
}

@JsonSerializable()
class UserStudyStepVo {
  String studyStep;

  UserVo? user;

  /// 本学习步骤在所有步骤中的顺序号，从0开始
  int index;

  String state;

  UserStudyStepVo(this.studyStep, this.index, this.state);

  factory UserStudyStepVo.fromJson(Map<String, dynamic> json) =>
      _$UserStudyStepVoFromJson(json);

  Map<String, dynamic> toJson() => _$UserStudyStepVoToJson(this);

  @override
  String toString() {
    return studyStep;
  }
}

@JsonSerializable()
class LearningWordVo {
  UserVo? user;

  DateTime? addTime;

  int addDay;

  int lifeValue;

  DateTime? lastLearningDate;

  int? learningOrder;

  int learnedTimes;

  WordVo word;

  LearningWordVo(this.user, this.addTime, this.addDay, this.lifeValue,
      this.lastLearningDate, this.learningOrder, this.learnedTimes, this.word);

  factory LearningWordVo.fromJson(Map<String, dynamic> json) =>
      _$LearningWordVoFromJson(json);

  Map<String, dynamic> toJson() => _$LearningWordVoToJson(this);
}

@JsonSerializable()
class MasteredWordVo {
  UserVo? user;
  WordVo word;
  DateTime masterAtTime;

  MasteredWordVo(this.user, this.word, this.masterAtTime);

  factory MasteredWordVo.fromJson(Map<String, dynamic> json) =>
      _$MasteredWordVoFromJson(json);

  Map<String, dynamic> toJson() => _$MasteredWordVoToJson(this);
}

@JsonSerializable()
class BookMarkVo {
  /// 书签名
  String? bookMarkName;

  /// 书签记录的单词位置（从0开始），并且这个位置是对所有单词而言（包括服务端的）
  int position;

  /// 书签记录的单词拼写
  String spell;

  BookMarkVo(this.position, this.spell);

  factory BookMarkVo.fromJson(Map<String, dynamic> json) =>
      _$BookMarkVoFromJson(json);

  Map<String, dynamic> toJson() => _$BookMarkVoToJson(this);

  @override
  String toString() {
    return 'BookMark{name: $bookMarkName, position: $position, spell: $spell}';
  }
}

@JsonSerializable()
class GameHallVo {
  String id;

  String gameType;

  String hallName;

  DictGroupVo dictGroup;

  HallGroupVo? hallGroup;

  int basePoint;

  int displayOrder;

  int userCount;

  GameHallVo(this.id, this.gameType, this.hallName, this.dictGroup,
      this.hallGroup, this.basePoint, this.displayOrder, this.userCount);

  factory GameHallVo.fromJson(Map<String, dynamic> json) =>
      _$GameHallVoFromJson(json);

  Map<String, dynamic> toJson() => _$GameHallVoToJson(this);
}

@JsonSerializable()
class HallGroupVo {
  String id;

  String gameType;

  String groupName;

  int displayOrder;

  List<GameHallVo> gameHalls;

  int userCount;

  HallGroupVo(this.id, this.gameType, this.groupName, this.displayOrder,
      this.gameHalls, this.userCount);

  factory HallGroupVo.fromJson(Map<String, dynamic> json) =>
      _$HallGroupVoFromJson(json);

  Map<String, dynamic> toJson() => _$HallGroupVoToJson(this);
}

@JsonSerializable()
class HallVo {
  String name;
  int userCount;
  String system;

  HallVo(this.name, this.userCount, this.system);

  factory HallVo.fromJson(Map<String, dynamic> json) => _$HallVoFromJson(json);

  Map<String, dynamic> toJson() => _$HallVoToJson(this);
}

@JsonSerializable()
class UserGameVo {
  UserVo user;

  int winCount;

  int loseCount;

  int score;

  UserGameVo(this.user, this.winCount, this.loseCount, this.score, this.game);

  String game;

  factory UserGameVo.fromJson(Map<String, dynamic> json) =>
      _$UserGameVoFromJson(json);

  Map<String, dynamic> toJson() => _$UserGameVoToJson(this);
}

@JsonSerializable()
class GetGameHallDataResult {
  List<HallGroupVo> hallGroups;
  List<HallVo> halls;
  List<UserGameVo> topUserGames;

  GetGameHallDataResult(this.hallGroups, this.halls, this.topUserGames);

  factory GetGameHallDataResult.fromJson(Map<String, dynamic> json) =>
      _$GetGameHallDataResultFromJson(json);

  Map<String, dynamic> toJson() => _$GetGameHallDataResultToJson(this);
}

@JsonSerializable()
class SearchWordResult {
  WordVo? word;

  List<SentenceVo>? sentencesWithUGC;

  /// 我目前学习的词书中是否包含该单词？
  bool? isInMySelectedDicts;

  /// 我的生词本中是否包含该单词？
  bool? isInRawWordDict;

  String? soundPath;

  SearchWordResult(this.word, this.sentencesWithUGC, this.isInMySelectedDicts,
      this.isInRawWordDict, this.soundPath);

  factory SearchWordResult.fromJson(Map<String, dynamic> json) =>
      _$SearchWordResultFromJson(json);

  Map<String, dynamic> toJson() => _$SearchWordResultToJson(this);
}

@JsonSerializable()
class UserGameInfo {
  String userId;

  /// 用户的积分，属于用户级信息，和具体游戏无关
  int score;

  /// 用户的魔法泡泡数
  int cowDung;

  int winCount;
  int lostCount;
  String nickName;

  UserGameInfo(this.userId, this.score, this.cowDung, this.winCount,
      this.lostCount, this.nickName);

  factory UserGameInfo.fromJson(Map<String, dynamic> json) =>
      _$UserGameInfoFromJson(json);

  Map<String, dynamic> toJson() => _$UserGameInfoToJson(this);
}

@JsonSerializable()
class WordAdditionalInfoVo {
  String id;
  String word;
  String content;
  int handCount;
  int footCount;
  String createdBy;
  String createdByNickName;

  /// 我是否已经为该内容投过票了
  bool votedByMe;

  WordAdditionalInfoVo(this.id, this.word, this.content, this.handCount,
      this.footCount, this.createdBy, this.createdByNickName, this.votedByMe);

  factory WordAdditionalInfoVo.fromJson(Map<String, dynamic> json) =>
      _$WordAdditionalInfoVoFromJson(json);

  Map<String, dynamic> toJson() => _$WordAdditionalInfoVoToJson(this);
}

@JsonSerializable()
class ErrorReportVo {
  String id;
  String createdBy;
  String createdByNickName;
  String content;
  String word;
  bool fixed;

  ErrorReportVo(this.id, this.createdBy, this.createdByNickName, this.content,
      this.word, this.fixed);

  factory ErrorReportVo.fromJson(Map<String, dynamic> json) =>
      _$ErrorReportVoFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorReportVoToJson(this);
}

@JsonSerializable()
class WordImageVo {
  String id;
  String imageFile;
  int hand;
  int foot;
  UserVo author;

  WordImageVo(this.id, this.imageFile, this.hand, this.foot, this.author);

  factory WordImageVo.fromJson(Map<String, dynamic> json) =>
      _$WordImageVoFromJson(json);

  Map<String, dynamic> toJson() => _$WordImageVoToJson(this);
}

@JsonSerializable()
class VerbTenseVo {
  String id;

  WordVo? word;

  /// 时态的类型
  String tenseType;

  String tensedSpell;

  VerbTenseVo(this.id, this.word, this.tenseType, this.tensedSpell);

  factory VerbTenseVo.fromJson(Map<String, dynamic> json) =>
      _$VerbTenseVoFromJson(json);

  Map<String, dynamic> toJson() => _$VerbTenseVoToJson(this);
}

@JsonSerializable()
class WordList {
  String name;
  int wordCount;

  WordList(this.name, this.wordCount);

  factory WordList.fromJson(Map<String, dynamic> json) =>
      _$WordListFromJson(json);

  Map<String, dynamic> toJson() => _$WordListToJson(this);
}

@JsonSerializable()
class GetWordResult {
  LearningWordVo? learningWord;
  int learningMode;
  List<WordVo>? otherWords;
  List<int>? progress;
  String? sound;
  bool finished;
  bool noWord;
  List<CigenWordLinkVo>? cigens;
  List<WordAdditionalInfoVo>? additionalInfos;
  List<ErrorReportVo>? errorReports;
  String? shortDesc;
  bool shouldEnterReviewMode;
  List<WordImageVo>? images;
  List<VerbTenseVo>? verbTenses;
  List<WordShortDescChineseVo>? shortDescChineses;
  bool inRawWordDict;
  bool wordMastered; // 新增字段：标识单词已掌握，需要调用者重新获取下一个单词

  GetWordResult(
    this.learningWord,
    this.learningMode,
    this.otherWords,
    this.progress,
    this.sound,
    this.finished,
    this.noWord,
    this.cigens,
    this.additionalInfos,
    this.errorReports,
    this.shortDesc,
    this.shouldEnterReviewMode,
    this.images,
    this.verbTenses,
    this.shortDescChineses,
    this.inRawWordDict,
    this.wordMastered,
  );

  factory GetWordResult.fromJson(Map<String, dynamic> json) =>
      _$GetWordResultFromJson(json);
  Map<String, dynamic> toJson() => _$GetWordResultToJson(this);
}

User userVo2User(UserVo userVo) {
  User user = User(
      autoPlaySentence: userVo.autoPlaySentence!,
      continuousDakaDayCount: userVo.continuousDakaDayCount!,
      autoPlayWord: userVo.autoPlayWord!,
      cowDung: userVo.cowDung!,
      dakaDayCount: userVo.dakaDayCount!,
      dakaScore: userVo.dakaScore!,
      enableAllWrong: userVo.enableAllWrong!,
      gameScore: userVo.gameScore!,
      id: userVo.id!,
      inviteAwardTaken: userVo.inviteAwardTaken!,
      isAdmin: userVo.isAdmin!,
      isInputor: userVo.isInputor!,
      isSuper: userVo.isSuper!,
      isTodayLearningFinished: userVo.isTodayLearningFinished!,
      isTodayLearningStarted: userVo.isTodayLearningStarted!,
      learnedDays: userVo.learnedDays!,
      learningFinished: userVo.learningFinished!,
      levelId: userVo.level!.id,
      masteredWordsCount: userVo.masteredWordsCount!,
      maxContinuousDakaDayCount: userVo.maxContinuousDakaDayCount!,
      showAnswersDirectly: userVo.showAnswersDirectly!,
      throwDiceChance: userVo.throwDiceChance!,
      totalScore: userVo.totalScore!,
      userName: userVo.userName!,
      wordsPerDay: userVo.wordsPerDay!,
      password: userVo.password,
      dakaRatio: userVo.dakaRatio,
      email: userVo.email,
      invitedById: userVo.invitedBy?.id,
      lastDakaDate: userVo.lastDakaDate,
      lastLearningDate: userVo.lastLearningDate,
      lastLearningMode: userVo.lastLearningMode,
      lastLearningPosition: userVo.lastLearningPosition,
      lastLoginTime: userVo.lastLoginTime,
      lastShareTime: userVo.lastShareTime,
      nickName: userVo.nickName);

  return user;
}

@JsonSerializable(genericArgumentFactories: true)
class Pair<L, R> {
  L first;
  R second;

  Pair(this.first, this.second);

  factory Pair.fromJson(
    Map<String, dynamic> json,
    L Function(Object? json) fromJsonL,
    R Function(Object? json) fromJsonR,
  ) =>
      _$PairFromJson(json, fromJsonL, fromJsonR);

  Map<String, dynamic> toJson() =>
      _$PairToJson(this, (value) => value, (value) => value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pair &&
          runtimeType == other.runtimeType &&
          first == other.first &&
          second == other.second;

  @override
  int get hashCode => first.hashCode ^ second.hashCode;

  @override
  String toString() {
    return 'Pair{first: $first, second: $second}';
  }
}

class Triple<F, S, T> {
  F first;
  S second;
  T third;

  Triple(this.first, this.second, this.third);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Triple &&
          runtimeType == other.runtimeType &&
          first == other.first &&
          second == other.second &&
          third == other.third;

  @override
  int get hashCode => first.hashCode ^ second.hashCode ^ third.hashCode;

  @override
  String toString() {
    return 'Triple{first: $first, second: $second, third: $third}';
  }
}

@JsonSerializable()
@CustomDateTimeConverter()
class MsgVo {
  String id;
  String? fromUserName;
  String? fromUserNickName;
  String? toUserName;
  String? toUserNickName;
  String content;
  String? createTimeForDisplay; // 形如"一分钟前"、"10秒前"之类
  String msgType;
  String? clientType;
  UserVo fromUser;
  DateTime createTime;
  bool viewed;
  UserVo toUser;

  MsgVo(
      this.id,
      this.fromUserName,
      this.fromUserNickName,
      this.toUserName,
      this.toUserNickName,
      this.content,
      this.createTimeForDisplay,
      this.msgType,
      this.clientType,
      this.fromUser,
      this.toUser,
      this.createTime,
      this.viewed);

  factory MsgVo.fromJson(Map<String, dynamic> json) => _$MsgVoFromJson(json);

  Map<String, dynamic> toJson() => _$MsgVoToJson(this);
}

// 词典统计信息VO
@JsonSerializable()
@CustomDateTimeConverter()
class DictStatsVo {
  final String id;
  final String name;
  final String ownerId;
  final bool isShared;
  final bool isReady;
  final bool visible;
  final int wordCount;
  final int? popularityLimit;
  final DateTime createTime;
  final DateTime? updateTime;
  
  // 统计信息
  final int userSelectionCount; // 被用户选择的数量
  final int totalUsers; // 总用户数
  final double selectionRate; // 选择率

  DictStatsVo({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isShared,
    required this.isReady,
    required this.visible,
    required this.wordCount,
    this.popularityLimit,
    required this.createTime,
    this.updateTime,
    required this.userSelectionCount,
    required this.totalUsers,
    required this.selectionRate,
  });

  factory DictStatsVo.fromJson(Map<String, dynamic> json) =>
      _$DictStatsVoFromJson(json);

  Map<String, dynamic> toJson() => _$DictStatsVoToJson(this);
}

// 系统健康检查结果VO
@JsonSerializable()
class SystemHealthCheckResult {
  final bool? isHealthy;
  final List<SystemHealthIssue> issues;
  final List<String> errors;

  SystemHealthCheckResult({
    this.isHealthy,
    required this.issues,
    required this.errors,
  });

  factory SystemHealthCheckResult.fromJson(Map<String, dynamic> json) =>
      _$SystemHealthCheckResultFromJson(json);

  Map<String, dynamic> toJson() => _$SystemHealthCheckResultToJson(this);
}

// 系统健康问题VO
@JsonSerializable()
class SystemHealthIssue {
  final String type;
  final String description;
  final String category;

  SystemHealthIssue({
    required this.type,
    required this.description,
    required this.category,
  });

  factory SystemHealthIssue.fromJson(Map<String, dynamic> json) =>
      _$SystemHealthIssueFromJson(json);

  Map<String, dynamic> toJson() => _$SystemHealthIssueToJson(this);
}

// 系统健康修复结果VO
@JsonSerializable()
class SystemHealthFixResult {
  final int fixedCount;
  final List<String> errors;
  final List<String> fixed;

  SystemHealthFixResult({
    required this.fixedCount,
    required this.errors,
    required this.fixed,
  });

  factory SystemHealthFixResult.fromJson(Map<String, dynamic> json) =>
      _$SystemHealthFixResultFromJson(json);

  Map<String, dynamic> toJson() => _$SystemHealthFixResultToJson(this);
}

