import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

/// 后台导入词典资源（非 Web 端）
///
/// 目标：
/// - 解决 UI isolate 在大 JSON 反序列化时卡顿（Timer/进度条不刷新）
/// - 在后台 isolate 完成：解压/解析 JSON -> 构造对象 -> 写入 SQLite（drift）
/// - 通过 [SendPort] 回传导入进度
///
/// 入参使用 Map，确保可跨 isolate 传递：
/// - sendPort: SendPort
/// - dbPath: String (db.sqlite 完整路径，由主 isolate 计算好传入，避免 path_provider 在后台不可用)
/// - filePath: String (下载到本地的临时文件路径；避免主 isolate 大字节 copy 导致 20% 附近卡顿)
/// - bytes: TransferableTypedData（可选，兼容旧逻辑）
void dictImportIsolateMain(Map<String, dynamic> args) async {
  final SendPort sendPort = args['sendPort'] as SendPort;
  final String dbPath = args['dbPath'] as String;
  final String? filePath = args['filePath'] as String?;
  final TransferableTypedData? t = args['bytes'] as TransferableTypedData?;

  await _runImport(sendPort: sendPort, dbPath: dbPath, filePath: filePath, bytes: t);
}

/// Worker 模式入口：启动后常驻，接收多次任务，避免反复 spawn。
///
/// 初始消息：主 isolate 传入一个 SendPort，用于回传 worker 的 taskPort。
void dictImportWorkerMain(SendPort initPort) async {
  final taskPort = ReceivePort();
  initPort.send(taskPort.sendPort);

  await for (final msg in taskPort) {
    if (msg is! Map) continue;
    final SendPort? replyPort = msg['replyPort'] as SendPort?;
    final String? dbPath = msg['dbPath'] as String?;
    final String? filePath = msg['filePath'] as String?;
    if (replyPort == null || dbPath == null || filePath == null) {
      continue;
    }
    await _runImport(sendPort: replyPort, dbPath: dbPath, filePath: filePath, bytes: null);
  }
}

Future<void> _runImport({
  required SendPort sendPort,
  required String dbPath,
  String? filePath,
  TransferableTypedData? bytes,
}) async {
  void sendProgress(double v) {
    sendPort.send({'type': 'progress', 'value': v});
  }

  void sendPhase(String phase) {
    sendPort.send({'type': 'phase', 'value': phase});
  }

  void sendError(String message, [Object? e, StackTrace? st]) {
    sendPort.send({
      'type': 'error',
      'message': message,
      'error': e?.toString(),
      'stack': st?.toString(),
    });
  }

  MyDatabase? db;
  try {
    sendPhase('parse');
    Uint8List raw;
    if (filePath != null) {
      final file = File(filePath);
      if (!await file.exists()) {
        sendError('导入失败：找不到临时文件 $filePath');
        return;
      }
      final size = await file.length();
      Global.logger.d('📖 开始读取临时文件: $filePath, 大小: $size bytes');
      raw = await file.readAsBytes();
      // 读完就删，避免临时文件堆积
      try {
        await file.delete();
      } catch (_) {}
    } else if (bytes != null) {
      raw = bytes.materialize().asUint8List();
    } else {
      sendError('后台导入缺少输入数据(filePath/bytes)');
      return;
    }

    String? jsonStr;
    try {
      if (raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
        final decoded = GZipCodec().decode(raw);
        jsonStr = utf8.decode(decoded, allowMalformed: true);
      } else {
        jsonStr = utf8.decode(raw, allowMalformed: true);
      }
    } finally {
      raw = Uint8List(0); // FREE early
    }

    Object? decodedJson;
    try {
      decodedJson = jsonDecode(jsonStr);
    } finally {
      jsonStr = null; // FREE early
    }
    
    if (decodedJson is! Map<String, dynamic>) {
      sendError('词典资源 JSON 顶层结构非对象');
      return;
    }

    final bool success = decodedJson['success'] == true;
    if (!success) {
      sendError('词典资源请求失败: ${decodedJson['msg'] ?? ''}');
      return;
    }

    final Object? dataObj = decodedJson['data'];
    if (dataObj is! Map<String, dynamic>) {
      sendError('词典资源 data 为空或结构不正确');
      return;
    }

    final DictRes dictRes = DictRes.fromJson(dataObj);

    sendPhase('db_open');
    // 在后台 isolate 打开 sqlite（避免 path_provider）
    db = MyDatabase(NativeDatabase(File(dbPath)));
    
    // 立即显式启用 WAL 和 busy_timeout，确保并发安全
    // 注意：NativeDatabase 在打开后会自动执行 beforeOpen 回调，但 isolate 里 MyDatabase 实例独立，
    // 需要确保这些 Pragma 被执行。
    await db.customStatement('PRAGMA journal_mode=WAL;');
    await db.customStatement('PRAGMA busy_timeout=5000;');

    // 触发打开并检查版本
    await db.customSelect('SELECT 1', readsFrom: {}).get();

    // 计算总记录数
    final resourceCounts = <String, int>{
      '词书信息': dictRes.dict != null ? 1 : 0,
      '词书-单词关系': dictRes.dictWords?.length ?? 0,
      '单词': dictRes.words?.length ?? 0,
      '单词图片': dictRes.images?.length ?? 0,
      '形近词': dictRes.similarWords?.length ?? 0,
      '释义': dictRes.meaningItems?.length ?? 0,
      '同义词': dictRes.synonyms?.length ?? 0,
      '例句': dictRes.sentences?.length ?? 0,
    };
    final int totalRecords = resourceCounts.values.fold(0, (a, b) => a + b);
    int processedRecords = 0;

    sendPhase('import');
    sendProgress(0.0);

    Future<void> bump(int count) async {
      processedRecords += count;
      if (totalRecords > 0) {
        sendProgress(processedRecords / totalRecords);
      }
    }

    // 使用事务保证一致性
    await db.transaction(() async {
      // 词书信息
      if (dictRes.dict != null) {
        final d = dictRes.dict!;
        await db!.dictsDao.saveEntity(
            Dict(
                id: d.id,
                isReady: d.isReady,
                isShared: d.isShared,
                ownerId: d.ownerId,
                name: d.name,
                wordCount: d.wordCount,
                visible: d.visible,
                baseDictId: d.baseDictId,
                sortAlg: d.sortAlg,
                editable: d.editable ?? (d.name == '生词本' || d.ownerId != Global.sysUserId),
                deletable: d.deletable ?? (d.name != '生词本' && d.name != '已掌握' && d.ownerId != Global.sysUserId),
                popularityLimit: d.popularityLimit,
                createTime: d.createTime,
                updateTime: d.updateTime),
            false);
        await bump(resourceCounts['词书信息']!);
      }

      // Words
      final srcWords = dictRes.words ?? <WordDto>[];
      if (srcWords.isNotEmpty) {
        final List<Word> words = <Word>[];
        for (int i = 0; i < srcWords.length; i++) {
          final w = srcWords[i];
          words.add(Word(
              id: w.id,
              americaPronounce: w.americaPronounce,
              britishPronounce: w.britishPronounce,
              groupInfo: w.groupInfo,
              longDesc: w.longDesc,
              popularity: w.popularity,
              pronounce: w.pronounce,
              shortDesc: w.shortDesc,
              spell: w.spell,
              createTime: w.createTime,
              updateTime: w.updateTime));

          // 每处理100个单词，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.wordsDao.insertEntities(words);
        await bump(resourceCounts['单词']!);
      }

      // DictWords
      final srcDictWords = dictRes.dictWords ?? <DictWordDto>[];
      if (srcDictWords.isNotEmpty) {
        final List<DictWord> dictWords = <DictWord>[];
        for (int i = 0; i < srcDictWords.length; i++) {
          final dw = srcDictWords[i];
          dictWords.add(DictWord(dictId: dw.dictId.toString(), wordId: dw.wordId, seq: dw.seq, unit: dw.unit, createTime: dw.createTime, updateTime: dw.updateTime));

          // 每处理100个词书-单词关系，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.dictWordsDao.insertEntities(dictWords, false);
        await bump(resourceCounts['词书-单词关系']!);
      }

      // MeaningItems
      final srcMeaningItems = dictRes.meaningItems ?? <MeaningItemDto>[];
      if (srcMeaningItems.isNotEmpty) {
        final List<MeaningItem> meaningItems = <MeaningItem>[];
        for (int i = 0; i < srcMeaningItems.length; i++) {
          final m = srcMeaningItems[i];
          meaningItems.add(MeaningItem(
              id: m.id,
              wordId: m.wordId,
              dictId: m.dictId,
              ciXing: m.ciXing,
              meaning: m.meaning,
              popularity: m.popularity,
              ownerId: m.ownerId ?? "",
              createTime: m.createTime,
              updateTime: m.updateTime));

          // 每处理100个释义，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.meaningItemsDao.insertEntities(meaningItems);
        await bump(resourceCounts['释义']!);
      }

      // WordImages
      final srcImages = dictRes.images ?? <WordImageDto>[];
      if (srcImages.isNotEmpty) {
        final List<WordImage> images = <WordImage>[];
        for (int i = 0; i < srcImages.length; i++) {
          final im = srcImages[i];
          images.add(WordImage(
              id: im.id,
              imageFile: im.imageFile,
              foot: im.foot,
              hand: im.hand,
              authorId: im.authorId ?? "",
              ownerId: im.ownerId ?? "",
              wordId: im.wordId,
              createTime: im.createTime,
              updateTime: im.updateTime));

          // 每处理100个单词图片，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.wordImagesDao.insertEntities(images);
        await bump(resourceCounts['单词图片']!);
      }

      // SimilarWords
      final srcSimilarWords = dictRes.similarWords ?? <SimilarWordDto>[];
      if (srcSimilarWords.isNotEmpty) {
        final List<SimilarWord> similarWords = <SimilarWord>[];
        for (int i = 0; i < srcSimilarWords.length; i++) {
          final sw = srcSimilarWords[i];
          similarWords
              .add(SimilarWord(
                  wordId: sw.wordId, 
                  similarWordId: sw.similarWordId, 
                  similarWordSpell: sw.similarWordSpell, 
                  distance: sw.distance,
                  createTime: sw.createTime,
                  updateTime: sw.updateTime));

          // 每处理100个形近词，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.similarWordsDao.insertEntities(similarWords);
        await bump(resourceCounts['形近词']!);
      }

      // Synonyms
      final srcSynonyms = dictRes.synonyms ?? <SynonymDto>[];
      if (srcSynonyms.isNotEmpty) {
        final List<Synonym> synonyms = <Synonym>[];
        for (int i = 0; i < srcSynonyms.length; i++) {
          final s = srcSynonyms[i];
          synonyms.add(Synonym(meaningItemId: s.meaningItemId, wordId: s.wordId, spell: s.spell, createTime: s.createTime, updateTime: s.updateTime));

          // 每处理100个同义词，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.synonymsDao.insertEntities(synonyms);
        await bump(resourceCounts['同义词']!);
      }

      // Sentences
      final srcSentences = dictRes.sentences ?? <SentenceDto>[];
      if (srcSentences.isNotEmpty) {
        final List<Sentence> sentences = <Sentence>[];
        for (int i = 0; i < srcSentences.length; i++) {
          final s = srcSentences[i];
          sentences.add(Sentence(
              id: s.id,
              english: s.english,
              chinese: s.chinese,
              englishDigest: s.englishDigest,
              theType: s.theType,
              handCount: s.handCount,
              footCount: s.footCount,
              authorId: s.authorId ?? "",
              ownerId: s.ownerId ?? "",
              meaningItemId: s.meaningItemId,
              wordMeaning: s.wordMeaning,
              createTime: s.createTime,
              updateTime: s.updateTime));

          // 每处理100个例句，yield一次，避免阻塞
          if (i % 100 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await db!.sentencesDao.insertEntities(sentences);
        await bump(resourceCounts['例句']!);
      }
    });

    sendProgress(1.0);
    sendPort.send({'type': 'done'});
  } catch (e, st) {
    // 这里不要 throw，避免 isolate 直接崩溃导致主线程收收到错误信息
    Global.logger.e('后台导入失败: $e', error: e, stackTrace: st);
    sendError('后台导入失败', e, st);
  } finally {
    try {
      db?.close();
    } catch (_) {}
  }
}

