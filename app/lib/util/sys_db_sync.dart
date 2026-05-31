import 'dart:convert';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/util/sync.dart';
import 'package:nnbdc/util/utils.dart';

/// 同步系统数据库（统一的系统数据同步）
///
/// 包含：
/// - 静态元数据：DictGroups、GroupAndDictLinks、Dicts、DictWords
/// - UGC内容：Sentences、WordImages、WordShortDescChineses
///
/// 使用单例版本号，所有用户共享同一份系统数据
Future<void> syncSysDb() async {
  final stopwatch = Stopwatch()..start();

  try {
    final db = MyDatabase.instance;

    // 1. 获取本地UGC版本（设备级别）
    SysDbVersionData? localSysVersion = await db.sysDbVersionDao.getVersion();
    int localVersion = localSysVersion?.version ?? 0;

    // 2. 获取服务端全局版本
    var remoteVersionResult = await Api.client.getSysDbVersion();
    if (!remoteVersionResult.success) {
      Global.logger.e("❌ 获取系统数据版本失败: ${remoteVersionResult.msg}");
      return;
    }
    int remoteVersion = remoteVersionResult.data!;

    // 3. 版本一致，无需同步
    Global.logger.i("📊 系统数据同步检查 - 本地: $localVersion, 远程: $remoteVersion");
    if (localVersion == remoteVersion) {
      // 容错: 如果版本一致，但表里实际上缺少系统词书、词根主表或关系数据，可能是异常中止导致的，强制从头拉取
      var sysDicts = await (db.select(db.dicts)..where((d) => d.ownerId.equals('15118'))).get();
      var anyCigen = await (db.select(db.cigens)..limit(1)).getSingleOrNull();
      var anyLink = await (db.select(db.cigenWordLinks)..limit(1)).getSingleOrNull();

      if (localVersion > 0 && (sysDicts.isEmpty || anyCigen == null || anyLink == null)) {
        Global.logger.w("⚠️ 系统数据版本为 $localVersion 但本地缺少系统词书或词根/关系数据(Cigen为空: ${anyCigen == null}, Link为空: ${anyLink == null})，触发全量重新同步！");
        localVersion = 0;
      } else {
        Global.logger.i("✅ 系统数据已是最新 - 版本: $localVersion");
        return;
      }
    }

    // 4. 拉取增量日志
    Global.logger.i("📥 开始拉取系统数据增量 - 本地: $localVersion, 远程: $remoteVersion");
    var logsResult = await Api.client.getNewSysDbLogs(localVersion);
    if (!logsResult.success) {
      Global.logger.e("❌ 获取系统数据日志失败: ${logsResult.msg}");
      return;
    }

    List<SysDbLogDto> remoteLogs = logsResult.data!;
    Global.logger.i("📦 收到 ${remoteLogs.length} 条系统数据变更");

    // 记录下行统计
    if (remoteLogs.isNotEmpty) {
      addDownloadCount(remoteLogs.length);
      Map<String, dynamic> dDetails = {};
      for (var log in remoteLogs) {
        String tblName = Util.remoteTableNameToLocal(log.tblName);
        if (tblName == 'IGNORED') continue; // 表已删除，跳过
        dDetails.putIfAbsent(tblName, () => <String, dynamic>{});
        dDetails[tblName][log.operate] = (dDetails[tblName][log.operate] as int? ?? 0) + 1;
      }
      addDownloadDetails(dDetails);
    }

    // 5. 应用日志到本地数据库（应用前按表依赖优先级排序）
    _sortSysLogs(remoteLogs);
    await _applySysDbLogs(remoteLogs);

    // 6. 更新本地版本
    await db.sysDbVersionDao.saveVersion(
      SysDbVersionData(
        id: 'singleton',
        version: remoteVersion,
        lastSyncTime: AppClock.now(),
        createTime: localSysVersion?.createTime ?? AppClock.now(),
        updateTime: AppClock.now(),
      ),
    );

    stopwatch.stop();
    Global.logger.i("✅ 系统数据同步完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms, "
        "变更数: ${remoteLogs.length}, 版本: $localVersion → $remoteVersion");
  } catch (e, stackTrace) {
    stopwatch.stop();
    Global.logger.e("❌ 系统数据同步失败: $e - 耗时: ${stopwatch.elapsedMilliseconds}ms", error: e, stackTrace: stackTrace);
  }
}

/// 应用系统数据日志到本地数据库
Future<void> _applySysDbLogs(List<SysDbLogDto> logs) async {
  final db = MyDatabase.instance;
  Set<String> affectedBaseDictIds = {};

  await db.transaction(() async {
    for (var log in logs) {
      try {
        Map<String, dynamic> entityJson = jsonDecode(log.record);

        // === 静态元数据表 ===
        // 统一修复日期格式
        if (log.operate != 'DELETE') {
          Util.fixJsonDates(entityJson);
        }

        if (log.tblName == 'dict_group') {
          // 词典分组
          if (log.operate == 'DELETE') {
            await (db.delete(db.dictGroups)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            DictGroup entity = DictGroup.fromJson(entityJson);
            await db.into(db.dictGroups).insertOnConflictUpdate(entity);
          }
        } else if (log.tblName == 'group_and_dict_link') {
          // 分组与词典关联
          if (log.operate == 'DELETE') {
            var parts = log.recordId.split('-');
            if (parts.length == 2) {
              await (db.delete(db.groupAndDictLinks)
                    ..where((t) => t.groupId.equals(parts[0]))
                    ..where((t) => t.dictId.equals(parts[1])))
                  .go();
            }
          } else {
            GroupAndDictLink entity = GroupAndDictLink.fromJson(entityJson);
            await db.into(db.groupAndDictLinks).insertOnConflictUpdate(entity);
          }
        } else if (log.tblName == 'dict') {
          // 词典
          if (log.operate == 'DELETE') {
            await (db.delete(db.dicts)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            entityJson['editable'] ??= false;
            entityJson['deletable'] ??= false;
            entityJson['visible'] ??= true;
            Dict entity = Dict.fromJson(entityJson);
            await db.dictsDao.saveEntity(entity, false);
          }
        } else if (log.tblName == 'dict_word') {
          // 词典单词关联（系统词典的单词变更）
          if (log.operate == 'DELETE') {
            // recordId格式为 "dictId_wordId"
            var parts = log.recordId.split('_');
            if (parts.length == 2) {
              final dictId = parts[0];
              final wordId = parts[1];
              affectedBaseDictIds.add(dictId);
              // 使用统一删除方法，不传userId（系统词典不涉及用户学习进度）
              await db.dictWordsDao.deleteDictWordWithCleanup(dictId, wordId, null, false);
            }
          } else {
            // INSERT 或 UPDATE 操作
            DictWord entity = DictWord.fromJson(entityJson);
            affectedBaseDictIds.add(entity.dictId);
            await db.dictWordsDao.insertEntity(entity, false);
          }
        } else if (log.tblName == 'word') {
          // 单词主体
          if (log.operate == 'DELETE') {
            await (db.delete(db.words)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            Word entity = Word.fromJson(entityJson);
            Global.logger.i("📝 同步更新单词: ${entity.spell}, UpdateTime: ${entity.updateTime}");
            await db.wordsDao.insertEntity(entity);
          }
        } else if (log.tblName == 'meaning_item') {
          // 单词释义
          if (log.operate == 'DELETE') {
            await (db.delete(db.meaningItems)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            MeaningItem entity = MeaningItem.fromJson(entityJson);
            await db.meaningItemsDao.insertEntity(entity, false);
          }
        } else if (log.tblName == 'cigen') {
          // 词根
          if (log.operate == 'DELETE') {
            await (db.delete(db.cigens)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            Cigen entity = Cigen.fromJson(entityJson);
            await db.cigensDao.saveEntity(entity);
          }
        } else if (log.tblName == 'cigen_word_link') {
          // 词根单词关联
          if (log.operate == 'DELETE') {
            var parts = log.recordId.split('_');
            if (parts.length == 2) {
              await (db.delete(db.cigenWordLinks)
                    ..where((t) => t.cigenId.equals(parts[0]))
                    ..where((t) => t.wordId.equals(parts[1])))
                  .go();
            }
          } else {
            CigenWordLink entity = CigenWordLink.fromJson(entityJson);
            await db.cigenWordLinksDao.saveEntity(entity);
          }
        } else if (log.tblName == 'sentence') {
          // === UGC内容表 ===
          // 例句
          if (log.operate == 'DELETE') {
            await (db.delete(db.sentences)..where((t) => t.id.equals(log.recordId))).go();
          } else {
            Sentence entity = Sentence.fromJson(entityJson);
            await db.sentencesDao.insertEntity(entity);
          }
        } else if (log.tblName == 'word_image') {
          // 单词配图
          if (log.operate == 'DELETE') {
            final rows = await (db.delete(db.wordImages)..where((t) => t.id.equals(log.recordId))).go();
            Global.logger.i('🗑️ [同步删除配图] 收到 DELETE word_image 日志, recordId=${log.recordId}, 实际删除了 $rows 行');
          } else {
            WordImage entity = WordImage.fromJson(entityJson);
            await db.wordImagesDao.insertEntity(entity);
          }
        } else {
          Global.logger.w('未知的系统数据表: ${log.tblName}');
        }
      } catch (e, stackTrace) {
        Global.logger.e('应用系统数据日志失败 - 表: ${log.tblName}, ID: ${log.recordId}', error: e, stackTrace: stackTrace);
        // 继续处理下一条日志，不中断整个同步
      }
    }
  });

  // ========== 触发联动乱序版重新生成 ==========
  if (affectedBaseDictIds.isNotEmpty) {
    for (var baseDictId in affectedBaseDictIds) {
      // 找出手机本地拥有的所有派生于这本正序词书的衍生词书（如乱序版等）
      final derivedDicts = await (db.select(db.dicts)..where((d) => d.baseDictId.equals(baseDictId))).get();
      for (var derivedDict in derivedDicts) {
        Global.logger.i('检测到词库 [$baseDictId] 有增删改，自动重构衍生软词书: ${derivedDict.id}');
        await WordBo().generateShuffledDictLocally(derivedDict.id, baseDictId);
      }
    }
  }
}


/// 获取系统数据表的同步优先级（用于维护外键关联顺序）
/// 数字越小优先级越高（越接近父表）
int _getSysTablePriority(String tblName) {
  switch (tblName) {
    case 'dict_group':
    case 'dict':
    case 'word':
    case 'cigen':
      return 1; // 核心父表
    case 'group_and_dict_link':
    case 'dict_word':
    case 'meaning_item':
    case 'cigen_word_link':
    case 'sentence':
    case 'word_image':
      return 2; // 关联子表
    default:
      return 3;
  }
}

/// 对系统同步日志进行排序，确保：
/// 1. INSERT/UPDATE: 先父表后子表 (正序)
/// 2. DELETE: 先子表后父表 (逆序)
/// 3. 混合情况：非删除操作优先（以防腾出空间需求）
void _sortSysLogs(List<SysDbLogDto> logs) {
  logs.sort((a, b) {
    int pA = _getSysTablePriority(a.tblName);
    int pB = _getSysTablePriority(b.tblName);

    bool isDeleteA = a.operate == 'DELETE';
    bool isDeleteB = b.operate == 'DELETE';

    if (isDeleteA && isDeleteB) {
      // 两个都是删除：逆序（优先级数值大的先执行，即先删子再删父）
      return pB.compareTo(pA);
    } else if (!isDeleteA && !isDeleteB) {
      // 两个都是增改：正序（优先级数值小的先执行，即先增父再增子）
      return pA.compareTo(pB);
    } else {
      // 混合情况：非删除操作优先于删除操作
      return isDeleteA ? 1 : -1;
    }
  });
}
