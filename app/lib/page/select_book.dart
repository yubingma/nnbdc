import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';

class SelectBookPage extends StatefulWidget {
  const SelectBookPage({super.key});

  @override
  SelectBookPageState createState() {
    return SelectBookPageState();
  }
}

class SelectBookPageState extends State<SelectBookPage> {
  // E2E集成测试时可将其设置为true以跳过下载步骤
  static bool skipDownloadInTest = false;
  List<DictGroupVo>? dictGroups;
  Set<DictVo>? selectedDictVos;
  Set<DictVo>? initialSelectedDictVos; // 初始选择状态
  bool downloading = false;
  bool downloadStarted = false;
  bool downloadSuccess = false;
  int downloadedBytes = 0;
  int totalBytes = 0;
  bool _isLoading = false;
  bool _hasUserMadeChanges = false; // 用户是否进行了选择动作

  bool isDictSelected(DictVo dict) {
    return selectedDictVos!.contains(dict);
  }

  List<DictVo> getSelectedDictsOfGroup(DictGroupVo group) {
    return group.dicts!.where((element) => isDictSelected(element)).toList();
  }

  @override
  void initState() {
    super.initState();
    selectedDictVos = {};
    initialSelectedDictVos = {};
    dictGroups = [];
    _hasUserMadeChanges = false;
    Future.microtask(() => loadData());
  }

  void loadData() async {
    setState(() {
      _isLoading = true;
    });

    // 禁用API调用的自动loading
    Api.disableAutoLoading = true;

    try {
      var user = await Global.refreshLoggedInUser();
      if (user == null) {
        ToastUtil.error("请先登录");
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/email_login');
        }
        return;
      }

      String userId = user.id!;

      // 先同步系统数据库（立即执行，不等待节流）
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);

      // 从本地数据库获取词书分组和用户选择的词书
      var db = MyDatabase.instance;
      var dictGroupsData = await db.select(db.dictGroups).get();
      var groupAndDictLinks = await db.select(db.groupAndDictLinks).get();
      var dicts = await db.select(db.dicts).get();
      List<LearningDict> learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);

      Global.logger.i("获取到的分组数据: ${dictGroupsData.length} 个");
      Global.logger.i("获取到的分组-词书关联: ${groupAndDictLinks.length} 个");
      Global.logger.i("获取到的词书数据: ${dicts.length} 个");

      // 构建词书分组数据
      dictGroups = [];
      // 1. 构建分组映射
      final groupMap = {for (var g in dictGroupsData) g.id: g};

      // 调试：打印所有分组信息
      Global.logger.i("📋 所有分组数据:");
      for (var g in dictGroupsData) {
        final parent = g.parentId != null ? groupMap[g.parentId] : null;
        Global.logger.i("  - ${g.name} (id: ${g.id}, parentId: ${g.parentId}, parent: ${parent?.name})");
      }

      // 2. 基于 root 分组获取其直接子分组（不显示 root 自身）
      //    优先通过名称为 'root' 的分组定位；若不存在，则取最顶层(parentId==null)作为根
      final rootGroup = dictGroupsData.firstWhere(
        (g) => g.name == 'root',
        orElse: () => dictGroupsData.firstWhere((g) => g.parentId == null),
      );

      var secondLevelGroups = dictGroupsData
          .where((g) => g.parentId == rootGroup.id && !["蒲公英", "职称", "少儿", "其他"].contains(g.name))
          .toList();
      
      // 按 displayIndex 排序
      secondLevelGroups.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

      Global.logger.i("第二级分组: ${secondLevelGroups.map((g) => g.name).join(', ')}");

      // 3. 为每个第二级分组构建VO
      for (var group in secondLevelGroups) {
        // 获取该分组下的所有词书（包括子分组的词书）
        var allDicts = <DictVo>[];
        // 记录已添加的词书ID，防止重复添加
        var addedDictIds = <String>{};

        // 获取直接关联的词书
        var directLinks = groupAndDictLinks.where((l) => l.groupId == group.id);
        Global.logger.i("分组 ${group.name} 直接关联的词书: ${directLinks.length} 个");

        for (var link in directLinks) {
          // 防止重复添加同一本词书
          if (addedDictIds.contains(link.dictId)) {
            Global.logger.i("词书 ${link.dictId} 已经添加过，跳过");
            continue;
          }

          var dictList = dicts.where((d) => d.id == link.dictId).toList();
          if (dictList.isEmpty) {
            Global.logger.w("未找到词书: ${link.dictId}");
            continue;
          }
          var dict = dictList.first;
          // 过滤掉visible为false的词典
          if (dict.visible == false) {
            Global.logger.i("词书 ${dict.name} 被设置为不可见，已跳过");
            continue;
          }
          var vo = DictVo.c2(dict.id);
          vo.name = dict.name;
          vo.shortName = getShortName(dict.name);
          vo.wordCount = dict.wordCount;
          vo.visible = true;
          allDicts.add(vo);
          addedDictIds.add(dict.id);
        }

        // 获取子分组下的词书
        var childGroups = dictGroupsData.where((g) => g.parentId == group.id);
        Global.logger.i("分组 ${group.name} 的子分组: ${childGroups.map((g) => g.name).join(', ')}");

        for (var childGroup in childGroups) {
          var childLinks = groupAndDictLinks.where((l) => l.groupId == childGroup.id);
          Global.logger.i("子分组 ${childGroup.name} 关联的词书: ${childLinks.length} 个");

          for (var link in childLinks) {
            // 防止重复添加同一本词书
            if (addedDictIds.contains(link.dictId)) {
              Global.logger.i("词书 ${link.dictId} 已经添加过，跳过");
              continue;
            }

            var dictList = dicts.where((d) => d.id == link.dictId).toList();
            if (dictList.isEmpty) {
              Global.logger.w("未找到词书: ${link.dictId}");
              continue;
            }
            var dict = dictList.first;
            // 过滤掉visible为false的词典
            if (dict.visible == false) {
              Global.logger.i("词书 ${dict.name} 被设置为不可见，已跳过");
              continue;
            }
            var vo = DictVo.c2(dict.id);
            vo.name = dict.name;
            vo.shortName = getShortName(dict.name);
            vo.wordCount = dict.wordCount;
            vo.visible = true;
            allDicts.add(vo);
            addedDictIds.add(dict.id);
          }
        }

        Global.logger.i(
            "分组 ${group.name} 最终包含的词书: ${allDicts.length} 个，去重前总关联数: ${directLinks.length + childGroups.map((g) => groupAndDictLinks.where((l) => l.groupId == g.id).length).fold(0, (a, b) => a + b)} 个");

        // 创建分组VO
        var groupVo = DictGroupVo(group.name, allDicts);
        dictGroups!.add(groupVo);
      }

      selectedDictVos = learningDicts.map((e) => DictVo.c2(e.dictId)).toSet();
      initialSelectedDictVos = Set.from(selectedDictVos!); // 保存初始状态

      // 更新UI
      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: '加载词书数据', showToast: true);
      setState(() {
        _isLoading = false;
      });
    } finally {
      // 重新启用API调用的自动loading
      Api.disableAutoLoading = false;
    }
  }

  toggleDictSelectedStatus(DictVo dict) {
    setState(() {
      if (isDictSelected(dict)) {
        selectedDictVos!.remove(dict);
      } else {
        selectedDictVos!.add(dict);
      }

      // 检查用户是否进行了选择动作
      if (initialSelectedDictVos != null) {
        _hasUserMadeChanges = !_setsEqual(selectedDictVos!, initialSelectedDictVos!);
      }
    });
  }

  // 比较两个Set是否相等
  bool _setsEqual(Set<DictVo> set1, Set<DictVo> set2) {
    if (set1.length != set2.length) return false;
    for (var item in set1) {
      if (!set2.any((element) => element.id == item.id)) return false;
    }
    return true;
  }

  renderTabs() {
    var tabs = <Widget>[];
    for (var dictGroup in dictGroups!) {
      final selectedCount = getSelectedDictsOfGroup(dictGroup).length;

      tabs.add(Tab(
        text: selectedCount > 0 ? '${dictGroup.name}($selectedCount)' : dictGroup.name,
      ));
    }
    return tabs;
  }

  renderTabContents() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);
    final subtitleColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    var tabs = <Widget>[];
    for (var dictGroup in dictGroups!) {
      var visibleDicts = dictGroup.dicts!.where((dict) => dict.visible!).toList();

      if (visibleDicts.isEmpty) {
        tabs.add(Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.book_outlined,
                size: 48,
                color: textColor.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                '暂无词书',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.6),
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                  height: 1.3,
                  letterSpacing: 0.5,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
            ],
          ),
        ));
        continue;
      }

      tabs.add(ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visibleDicts.length,
        itemBuilder: (context, index) {
          final dict = visibleDicts[index];
          final isSelected = isDictSelected(dict);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : (isDarkMode ? Colors.grey[700]! : Colors.grey[200]!),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  toggleDictSelectedStatus(dict);
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox.shrink(key: Key('select_book_item_${dict.id}')),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryColor : (isDarkMode ? Colors.grey[600]! : Colors.grey[400]!),
                            width: 2,
                          ),
                          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dict.shortName!,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'NotoSansSC',
                                height: 1.4,
                                letterSpacing: 0.5,
                              ),
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.book,
                                  size: 14,
                                  color: subtitleColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${dict.wordCount} 词',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: 'NotoSansSC',
                                    height: 1.3,
                                    letterSpacing: 0.3,
                                  ),
                                  textScaler: const TextScaler.linear(1.0),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '已选择',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'NotoSansSC',
                              height: 1.2,
                              letterSpacing: 0.3,
                            ),
                            textScaler: const TextScaler.linear(1.0),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ));
    }
    return tabs;
  }

  static Future<DictRes?> getDictRes(String dictId) async {
    final stopwatch = Stopwatch()..start();

    try {
      Global.logger.d('🔄 开始获取词典资源: $dictId');

      var result = await Api.client.getDictResById(dictId);

      stopwatch.stop();
      Global.logger.d('📥 API调用完成: ${stopwatch.elapsedMilliseconds}ms');

      if (result.success) {
        // 记录反序列化后的数据大小
        if (result.data != null) {
          final dictRes = result.data!;
          final wordCount = dictRes.words?.length ?? 0;
          final meaningCount = dictRes.meaningItems?.length ?? 0;
          final sentenceCount = dictRes.sentences?.length ?? 0;

          Global.logger.i('📊 词典资源反序列化完成 - 单词: $wordCount, 释义: $meaningCount, 例句: $sentenceCount');
        }

        return result.data;
      } else {
        ToastUtil.error(result.msg!);
        return null;
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      Global.logger.e('❌ 获取词典资源失败: $dictId, 耗时: ${stopwatch.elapsedMilliseconds}ms', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  save() async {
    try {
      // 第一步：保存用户词书选择到本地数据库
      await LoadingUtils.withApiLoading(
          loadingText: '保存选择...',
          operation: () async {
            var user = await Global.refreshLoggedInUser();
            String userId = user!.id!;
            final db = MyDatabase.instance;
            await db.transaction(() async {
              try {
                // 删除用户取消选择的单词书
                var learningDictsDao = db.learningDictsDao;
                var existingDicts = await learningDictsDao.getLearningDictsOfUser(userId);
                for (var existing in existingDicts) {
                  if (!selectedDictVos!.contains(DictVo.c2(existing.dictId))) {
                    await learningDictsDao.deleteEntity(existing, true);
                  }
                }

                // 添加用户新选择的单词书
                for (var dictVo in selectedDictVos!) {
                  LearningDict? existing = await learningDictsDao.findById(userId, dictVo.id);
                  if (existing != null) {
                    continue;
                  }

                  LearningDict learningDict = LearningDict(
                      userId: user.id!,
                      dictId: dictVo.id,
                      isPrivileged: false,
                      fetchMastered: false,
                      currentWordId: null,
                      currentWordSeq: null,
                      createTime: AppClock.now(),
                      updateTime: null);
                  await learningDictsDao.saveEntity(learningDict, true);
                  Global.logger.i("用户[${user.nickName}]选择了单词书[${dictVo.name}]");
                }
              } catch (e) {
                Global.logger.e("保存用户词书选择失败: $e");
                rethrow;
              }
            });
          });

      // 第二步：下载词书（此时loading已经关闭，不会遮挡下载进度对话框）
      var user = await Global.refreshLoggedInUser();
      String userId = user!.id!;
      await downloadDicts(userId);

      // 第三步：同步用户词书选择到服务器
      await LoadingUtils.withApiLoading(
          loadingText: '同步数据...',
          operation: () async {
            await syncDb(user);
          });

      // 第四步：跳转回原始页面
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: '保存用户词书选择', showToast: true);
    }
  }

  /// 为用户下载词书，包括通用词典和用户选择的词书
  Future<void> downloadDicts(String userId) async {
    // 下载用户选择的词书
    try {
      if (selectedDictVos == null) {
        Global.logger.e("selectedDictVos 为空");
        return;
      }

      // 过滤出需要下载的词书
      List<DictVo> dictsToDownload = [];
      for (var dictVo in selectedDictVos!) {
        var db = MyDatabase.instance;
        Dict? existing = await db.dictsDao.findById(dictVo.id);

        // 检查词书是否存在，或存在但没有单词
        if (existing == null) {
          // 词书不存在，需要下载
          Global.logger.i("词书不存在，需要下载: ${dictVo.id}");
          dictsToDownload.add(dictVo);
        } else {
          // 词书存在，但只有当owner是15118(系统词书)时才需要检查是否有单词
          if (existing.ownerId == "15118") {
            bool hasWords = await db.dictWordsDao.hasDictWords(dictVo.id);
            if (!hasWords) {
              // 系统词书中没有单词，需要下载
              Global.logger.i("系统词书存在但没有单词，需要下载: ${dictVo.id}");
              dictsToDownload.add(dictVo);
            } else {
              Global.logger.i("系统词书已存在且包含单词，无需下载: ${dictVo.id}");
            }
          } else {
            Global.logger.i("非系统词书已存在，无需检查单词数量: ${dictVo.id}");
          }
        }
      }

      if (!skipDownloadInTest && dictsToDownload.isNotEmpty && mounted) {
        // 显示下载对话框
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => DictDownloadDialog(
            dicts: dictsToDownload,
            onComplete: () {
              Navigator.of(dialogContext).pop();
            },
          ),
        );
      } else if (skipDownloadInTest) {
        Global.logger.i("跳过词书下载(测试模式)");
      }
    } catch (e) {
      ErrorHandler.handleNetworkError(e, null, api: '下载用户词书', showToast: true);
    }
  }

  /// 下载词书，并保存到本地数据库
  static Future<bool> downloadADict(String dictId, {Function(double)? onProgress}) async {
    // 禁用API调用的自动loading
    Api.disableAutoLoading = true;

    try {
      // 获取词书资源
      DictRes? dictRes = await getDictRes(dictId);
      if (dictRes == null) {
        ToastUtil.error("[$dictId]下载失败");
        return false;
      }

      // 下载完成,更新20%的进度
      if (onProgress != null) {
        onProgress(0.2);
      }

      await importDictRes(dictRes, onProgress: (progress) {
        // 导入进度占剩余的80%
        if (onProgress != null) {
          onProgress(0.2 + progress * 0.8);
        }
      });
      return true;
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: '导入词书', showToast: true);
      rethrow;
    } finally {
      // 重新启用API调用的自动loading
      Api.disableAutoLoading = false;
    }
  }

  static Future<void> updateProgress(int totalSteps, int step, {Function(double)? onProgress}) async {
    // 使用scheduleMicrotask确保UI能更新
    scheduleMicrotask(() async {
      if (onProgress != null) {
        onProgress(step / totalSteps);
      }
    });
  }

  static Future<void> importDictRes(DictRes dictRes, {Function(double)? onProgress}) async {
    final totalStopwatch = Stopwatch()..start();

    // 计算每种资源的记录条数
    final resourceCounts = {
      '词书信息': dictRes.dict != null ? 1 : 0,
      '词书-单词关系': dictRes.dictWords?.length ?? 0,
      '单词': dictRes.words?.length ?? 0,
      '单词图片': dictRes.images?.length ?? 0,
      '形近词': dictRes.similarWords?.length ?? 0,
      '释义': dictRes.meaningItems?.length ?? 0,
      '同义词': dictRes.synonyms?.length ?? 0,
      '例句': dictRes.sentences?.length ?? 0,
    };

    // 计算总记录数
    final totalRecords = resourceCounts.values.fold(0, (sum, count) => sum + count);
    int processedRecords = 0;

    Global.logger.i('🔄 开始导入词典资源 - 总记录数: $totalRecords');
    Global.logger.d('📊 资源统计: $resourceCounts');

    try {
      // 收集所有需要执行的操作和对应的记录数
      List<Map<String, dynamic>> operations = [];

      // 添加词书操作
      if (dictRes.dict != null) {
        operations.add({
          'operation': () => MyDatabase.instance.dictsDao.createEntity(Dict(
              id: dictRes.dict!.id,
              isReady: dictRes.dict!.isReady,
              isShared: dictRes.dict!.isShared,
              ownerId: dictRes.dict!.ownerId,
              name: dictRes.dict!.name,
              wordCount: dictRes.dict!.wordCount,
              visible: dictRes.dict!.visible,
              createTime: dictRes.dict!.createTime,
              updateTime: dictRes.dict!.updateTime)),
          'count': resourceCounts['词书信息']!,
          'name': '词书信息'
        });
      }

      // 添加单词操作(批量) - 必须在词书-单词关系之前插入
      List<Word> words = dictRes.words
              ?.map((word) => Word(
                  id: word.id,
                  americaPronounce: word.americaPronounce,
                  britishPronounce: word.britishPronounce,
                  groupInfo: word.groupInfo,
                  longDesc: word.longDesc,
                  pronounce: word.pronounce,
                  shortDesc: word.shortDesc,
                  popularity: word.popularity,
                  spell: word.spell,
                  createTime: word.createTime,
                  updateTime: word.updateTime))
              .toList() ??
          [];
      if (words.isNotEmpty) {
        operations.add({'operation': () => MyDatabase.instance.wordsDao.insertEntities(words), 'count': resourceCounts['单词']!, 'name': '单词'});
      }

      // 添加词书-单词关系操作(批量) - 必须在单词插入之后
      List<DictWord> dictWords = dictRes.dictWords
              ?.map((dictWord) => DictWord(
                  dictId: dictWord.dictId.toString(), // 确保 dictId 是字符串
                  wordId: dictWord.wordId,
                  seq: dictWord.seq,
                  createTime: dictWord.createTime,
                  updateTime: dictWord.updateTime))
              .toList() ??
          [];
      if (dictWords.isNotEmpty) {
        operations.add({
          'operation': () => MyDatabase.instance.dictWordsDao.insertEntities(dictWords, false),
          'count': resourceCounts['词书-单词关系']!,
          'name': '词书-单词关系'
        });
      }

      // 添加释义操作（批量）- 依赖 Words 和 Dicts
      List<MeaningItem> meaningItems = dictRes.meaningItems
              ?.map((meaningItem) => MeaningItem(
                  id: meaningItem.id,
                  wordId: meaningItem.wordId,
                  dictId: meaningItem.dictId,
                  ciXing: meaningItem.ciXing,
                  meaning: meaningItem.meaning,
                  popularity: meaningItem.popularity,
                  createTime: meaningItem.createTime,
                  updateTime: meaningItem.updateTime))
              .toList() ??
          [];
      if (meaningItems.isNotEmpty) {
        operations
            .add({'operation': () => MyDatabase.instance.meaningItemsDao.insertEntities(meaningItems), 'count': resourceCounts['释义']!, 'name': '释义'});
      }

      // 添加单词图片操作(批量) - 依赖 Words
      List<WordImage> wordImages = dictRes.images
              ?.map((image) => WordImage(
                  id: image.id,
                  imageFile: image.imageFile,
                  foot: image.foot,
                  hand: image.hand,
                  authorId: image.authorId,
                  wordId: image.wordId, // 确保 wordId 是字符串
                  createTime: image.createTime,
                  updateTime: image.updateTime))
              .toList() ??
          [];
      if (wordImages.isNotEmpty) {
        operations
            .add({'operation': () => MyDatabase.instance.wordImagesDao.insertEntities(wordImages), 'count': resourceCounts['单词图片']!, 'name': '单词图片'});
      }

      // 添加形近词操作（批量）- 依赖 Words
      List<SimilarWord> similarWords = dictRes.similarWords
              ?.map((similarWord) => SimilarWord(
                  wordId: similarWord.wordId,
                  similarWordId: similarWord.similarWordId,
                  similarWordSpell: similarWord.similarWordSpell,
                  distance: similarWord.distance))
              .toList() ??
          [];
      if (similarWords.isNotEmpty) {
        operations.add(
            {'operation': () => MyDatabase.instance.similarWordsDao.insertEntities(similarWords), 'count': resourceCounts['形近词']!, 'name': '形近词'});
      }

      // 添加同义词操作(批量) - 依赖 MeaningItems 和 Words
      List<Synonym> synonyms = dictRes.synonyms
              ?.map((synonym) => Synonym(
                  meaningItemId: synonym.meaningItemId,
                  wordId: synonym.wordId,
                  spell: synonym.spell,
                  createTime: synonym.createTime,
                  updateTime: synonym.updateTime))
              .toList() ??
          [];
      if (synonyms.isNotEmpty) {
        operations.add({'operation': () => MyDatabase.instance.synonymsDao.insertEntities(synonyms), 'count': resourceCounts['同义词']!, 'name': '同义词'});
      }

      // 添加例句操作(批量) - 依赖 MeaningItems
      List<Sentence> sentences = dictRes.sentences
              ?.map((sentence) => Sentence(
                  id: sentence.id,
                  english: sentence.english,
                  chinese: sentence.chinese,
                  englishDigest: sentence.englishDigest,
                  theType: sentence.theType,
                  handCount: sentence.handCount,
                  footCount: sentence.footCount,
                  authorId: sentence.authorId,
                  meaningItemId: sentence.meaningItemId,
                  wordMeaning: sentence.wordMeaning,
                  createTime: sentence.createTime,
                  updateTime: sentence.updateTime))
              .toList() ??
          [];
      if (sentences.isNotEmpty) {
        operations.add({'operation': () => MyDatabase.instance.sentencesDao.insertEntities(sentences), 'count': resourceCounts['例句']!, 'name': '例句'});
      }

      // 在一个事务中执行所有操作
      final db = MyDatabase.instance;

      await db.transaction(() async {
        for (var op in operations) {
          final opStopwatch = Stopwatch()..start();
          Global.logger.d("🔄 开始处理: ${op['name']}, 记录数: ${op['count']}");

          await op['operation']();

          opStopwatch.stop();
          Global.logger.d("✅ 处理完成: ${op['name']}, 耗时: ${opStopwatch.elapsedMilliseconds}ms");

          processedRecords += (op['count'] as int);

          // 更新进度
          if (onProgress != null) {
            onProgress(processedRecords / totalRecords);
            Global.logger.d("📊 进度: $processedRecords/$totalRecords (${(processedRecords / totalRecords * 100).toStringAsFixed(1)}%)");
          }

          // 添加延迟，让进度条有足够时间显示
          await Future.delayed(const Duration(milliseconds: 100));

          // 强制垃圾回收，释放内存
          if (processedRecords % 1000 == 0) {
            Global.logger.d("🗑️ 执行垃圾回收，已处理记录数: $processedRecords");
          }
        }
      });

      // 完成后强制垃圾回收
      Global.logger.d("导入完成，执行最终垃圾回收");
    } catch (e) {
      rethrow;
    } finally {
      totalStopwatch.stop();
      Global.logger.d('📊 导入词典资源完成 - 总耗时: ${totalStopwatch.elapsedMilliseconds}ms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF2C3E50);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppTheme.createGradientAppBar(
          title: '选词书',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDarkMode ? const Color(0xFF4A90E2) : const Color(0xFF3498DB),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '正在加载词书...',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                  height: 1.3,
                  letterSpacing: 0.5,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
            ],
          ),
        ),
      );
    } else if (selectedDictVos == null || dictGroups == null || dictGroups!.isEmpty) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppTheme.createGradientAppBar(
          title: '选词书',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.library_books,
                size: 64,
                color: textColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                '没有可用的词书',
                style: TextStyle(
                  color: textColor,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'NotoSansSC',
                  height: 1.3,
                  letterSpacing: 0.5,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              const SizedBox(height: 8),
              Text(
                '请检查网络连接后重试',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                  height: 1.3,
                  letterSpacing: 0.3,
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 只统计在UI分组中可见且被选中的词书数量
    final selectedCount = dictGroups!.fold<int>(0, (sum, group) => sum + getSelectedDictsOfGroup(group).length);

    return DefaultTabController(
      length: dictGroups!.length,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            '选词书',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
              fontFamily: 'NotoSansSC',
              height: 1.3,
              letterSpacing: 1.0,
            ),
            textScaler: TextScaler.linear(1.0),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.gradientStartColor, AppTheme.gradientEndColor],
              ),
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: EdgeInsets.zero,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFamily: 'NotoSansSC',
              height: 1.4,
              letterSpacing: 0.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontFamily: 'NotoSansSC',
              height: 1.4,
              letterSpacing: 0.3,
            ),
            tabs: renderTabs(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: renderTabContents(),
              ),
            ),
            if (_hasUserMadeChanges)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: ElevatedButton(
                    key: const Key('select_book_confirm_btn'),
                    onPressed: save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '确定 ($selectedCount)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 更新本地和服务器数据库（词书相关的）
  static Future<void> syncDb(UserVo user) async {
    try {
      await LoadingUtils.withApiLoading(
        loadingText: '同步数据...',
        operation: () async {
          ThrottledDbSyncService().requestSync();
        },
      );
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '同步数据失败', showToast: true);
    }
  }

  String getShortName(String name) {
    if (name.endsWith(".dict")) {
      return name.substring(0, name.lastIndexOf("."));
    } else {
      return name;
    }
  }
}
