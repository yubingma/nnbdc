import 'dart:async';

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/dict_import_worker.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/page/subscription.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/analytics_util.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'word_list/dict_words.dart';
import '../api/bo/word_bo.dart';
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

class SelectBookPageState extends State<SelectBookPage> with TickerProviderStateMixin {
  // E2E集成测试时可将其设置为true以跳过下载步骤
  static bool skipDownloadInTest = false;
  List<DictGroupVo>? dictGroups;
  List<DictVo>? customDicts;
  Set<DictVo>? selectedDictVos;
  Set<DictVo>? initialSelectedDictVos; // 初始选择状态
  bool downloading = false;
  bool downloadStarted = false;
  bool downloadSuccess = false;
  int downloadedBytes = 0;
  int totalBytes = 0;
  bool _isLoading = false;
  bool _hasUserMadeChanges = false; // 用户是否进行了选择动作
  TabController? _tabController;
  int _currentTabIndex = -1; // 记录当前 Tab 索引

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
    customDicts = [];
    _hasUserMadeChanges = false;
    Future.microtask(() => loadData());
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _initTabController() {
    final tabsCount = (dictGroups?.length ?? 0) + 1;
    if (_tabController == null || _tabController!.length != tabsCount) {
      _tabController?.dispose();

      // 如果还没有记录过索引，则根据之前的逻辑设置初始值（默认第二个Tab，即系统词书第一组）
      if (_currentTabIndex == -1) {
        _currentTabIndex = (dictGroups?.isNotEmpty ?? false) ? 1 : 0;
      }

      // 确保索引不越界
      if (_currentTabIndex >= tabsCount) {
        _currentTabIndex = 0;
      }

      _tabController = TabController(
        length: tabsCount,
        vsync: this,
        initialIndex: _currentTabIndex,
      );

      _tabController!.addListener(() {
        if (!_tabController!.indexIsChanging) {
          _currentTabIndex = _tabController!.index;
        }
      });
    }
  }

  void loadData({bool keepSelection = false}) async {
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
          Navigator.of(context).pushReplacementNamed('/login');
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

      // 构建词书分组数据
      dictGroups = [];

      var secondLevelGroups = [];
      if (dictGroupsData.isNotEmpty) {
        try {
          final rootGroup = dictGroupsData.firstWhere(
            (g) => g.name == 'root',
            orElse: () => dictGroupsData.firstWhere((g) => g.parentId == null, orElse: () => dictGroupsData.first),
          );
          secondLevelGroups = dictGroupsData.where((g) => g.parentId == rootGroup.id && !["蒲公英", "职称", "少儿", "其他"].contains(g.name)).toList();
        } catch (e) {
          Global.logger.w('No root group found in dictGroupsData: $e');
        }
      }

      // 按 displayIndex 排序
      secondLevelGroups.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

      // 3. 为每个第二级分组构建VO
      for (var group in secondLevelGroups) {
        // 获取该分组下的所有词书（包括子分组的词书）
        var allDicts = <DictVo>[];
        // 记录已添加的词书ID，防止重复添加
        var addedDictIds = <String>{};

        // 获取直接关联的词书
        var directLinks = groupAndDictLinks.where((l) => l.groupId == group.id);

        for (var link in directLinks) {
          // 防止重复添加同一本词书
          if (addedDictIds.contains(link.dictId)) {
            continue;
          }

          var dictList = dicts.where((d) => d.id == link.dictId).toList();
          if (dictList.isEmpty) {
            continue;
          }
          var dict = dictList.first;
          // 过滤掉visible为false的词典
          if (dict.visible == false) {
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

        for (var childGroup in childGroups) {
          var childLinks = groupAndDictLinks.where((l) => l.groupId == childGroup.id);

          for (var link in childLinks) {
            // 防止重复添加同一本词书
            if (addedDictIds.contains(link.dictId)) {
              continue;
            }

            var dictList = dicts.where((d) => d.id == link.dictId).toList();
            if (dictList.isEmpty) {
              continue;
            }
            var dict = dictList.first;
            // 过滤掉visible为false的词典
            if (dict.visible == false) {
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

        // 创建分组VO
        var groupVo = DictGroupVo(group.name, allDicts);
        dictGroups!.add(groupVo);
      }

      customDicts = (await WordBo().getCustomDicts(userId)).where((d) => d.name != '已掌握').toList();

      if (!keepSelection) {
        selectedDictVos = learningDicts.map((e) => DictVo.c2(e.dictId)).toSet();
        initialSelectedDictVos = Set.from(selectedDictVos!); // 保存初始状态
      }

      if (!mounted) return;
      // 更新UI
      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: '加载词书数据', showToast: true);
      if (!mounted) return;
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

  void _showPremiumPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('会员专属功能'),
        content: const Text('自定义词书是会员专享特权，开通会员即可解锁自定义词书及其它多项专属功能。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SubscriptionPage())).then((_) {
                loadData();
              });
            },
            child: const Text('去开通'),
          ),
        ],
      ),
    );
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

    // 添加自定义 Tab
    tabs.add(const Tab(text: '自定义'));

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

    // 添加自定义 Tab 内容
    tabs.add(_buildCustomTabContent(isDarkMode, cardColor, textColor, subtitleColor));

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

  Widget _buildCustomTabContent(bool isDarkMode, Color cardColor, Color textColor, Color? subtitleColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Builder(builder: (context) {
            final restricted = PlatformUtils.isIOS && !SubscriptionUtil.isPremium();
            return ElevatedButton.icon(
              onPressed: _showCreateDictDialog,
              icon: Icon(restricted ? Icons.lock_outline : Icons.add, size: 20),
              label: const Text('新建单词书'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: restricted ? Colors.grey : AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            );
          }),
        ),
        Expanded(
          child: customDicts!.isEmpty
              ? Center(
                  child: Text(
                    '点击上方按钮创建词书',
                    style: TextStyle(color: textColor.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: customDicts!.length,
                  itemBuilder: (context, index) {
                    final dict = customDicts![index];
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
                            if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本' && !isSelected) {
                              _showPremiumPrompt();
                              return;
                            }
                            toggleDictSelectedStatus(dict);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
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
                                  child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            dict.name ?? '未命名',
                                            style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.w500),
                                          ),
                                          if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本') ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${dict.wordCount} 词', style: TextStyle(color: subtitleColor, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit_note,
                                      size: 24,
                                      color: (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本') ? Colors.grey : AppTheme.primaryColor),
                                  onPressed: () async {
                                    if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本') {
                                      _showPremiumPrompt();
                                      return;
                                    }
                                    await toDictWordsListPage(dict.id, true);
                                    loadData(keepSelection: true);
                                  },
                                  tooltip: '管理单词',
                                ),
                                if (dict.canDelete != false)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                    onPressed: () => _confirmDeleteDict(dict),
                                    tooltip: '删除词书',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCreateDictDialog() async {
    if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium()) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('会员专属功能'),
          content: const Text('自定义词书是会员专享特权，开通会员即可解锁自定义词书及其它多项专属功能。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SubscriptionPage())).then((_) {
                  loadData();
                });
              },
              child: const Text('去开通'),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建单词书'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入单词书名称', labelText: '名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final user = Global.getLoggedInUser();
              if (user == null) return;

              final result = await WordBo().createCustomDict(name, user.id);
              if (!context.mounted) return;

              if (result.success) {
                Navigator.pop(context);
                ToastUtil.info('创建成功');
                loadData(keepSelection: true);
              } else {
                ToastUtil.error(result.msg ?? '创建失败');
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDict(DictVo dict) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除单词书 "${dict.name}" 吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final result = await WordBo().deleteCustomDict(dict.id);
              if (result.success) {
                ToastUtil.info('已删除');
                // 如果已选择该词典，从选择列表中移除
                if (selectedDictVos != null) {
                  selectedDictVos!.removeWhere((d) => d.id == dict.id);
                }
                if (!mounted) return;
                loadData(keepSelection: true);
              } else {
                ToastUtil.error(result.msg ?? '删除失败');
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  static Future<DictRes?> getDictRes(DictVo dict) async {
    final stopwatch = Stopwatch()..start();

    try {
      final dictId = dict.id;
      Global.logger.d('🔄 开始获取词典资源: $dictId');

      // 前端判断：ownerId == 当前用户ID -> 用户词书；否则 -> 系统/公共词书
      final currUserId = Global.getLoggedInUser()?.id ?? Global.currentUserId;
      String? ownerId = dict.owner?.id;
      // 若接口返回的 DictVo 未携带 owner，则尝试从本地数据库补齐 ownerId（用于判断是否为用户词书）
      if (ownerId == null) {
        final dictMeta = await MyDatabase.instance.dictsDao.findById(dictId);
        ownerId = dictMeta?.ownerId;
      }
      final isUserDict = currUserId != null && ownerId == currUserId;

      final result = isUserDict ? await Api.client.getUserDictResById(dictId) : await Api.client.getSysDictResById(dictId);

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
      Global.logger.e('❌ 获取词典资源失败: ${dict.id}, 耗时: ${stopwatch.elapsedMilliseconds}ms', error: e, stackTrace: stackTrace);
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
                      createTime: AppClock.now(),
                      updateTime: null);
                  await learningDictsDao.saveEntity(learningDict, true);
                  
                  // 漏斗：用户成功选择了一本词书
                  AnalyticsUtil.trackSelectBook('学习词书', dictVo.name ?? '未命名');
                  
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
      var db = MyDatabase.instance;
      for (var dictVo in selectedDictVos!) {
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
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
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
  static Future<bool> downloadADict(DictVo dict, {Function(double)? onProgress}) async {
    // 禁用API调用的自动loading
    Api.disableAutoLoading = true;

    try {
      // 获取词书资源
      final dictId = dict.id;

      // 判断是用户词书还是系统词书，以确定API路径
      final currUserId = Global.getLoggedInUser()?.id ?? Global.currentUserId;
      String? ownerId = dict.owner?.id;
      if (ownerId == null) {
        final dictMeta = await MyDatabase.instance.dictsDao.findById(dictId);
        ownerId = dictMeta?.ownerId;
      }
      final isUserDict = currUserId != null && ownerId == currUserId;
      final apiPath = isUserDict ? '/res/getUserDictResById.do' : '/res/getSysDictResById.do';
      final resourceId = '$apiPath?dictId=$dictId';

      // 预热后台导入 worker（避免下载完成后第一次 Isolate.spawn 卡住 UI）
      if (!kIsWeb) {
        unawaited(DictImportWorker.instance.ensureStarted());
      }

      // 监听下载进度，将下载进度映射到0-20%的范围
      Function(int, int)? downloadProgressListener;
      if (onProgress != null) {
        double lastEmitted = 0.0;
        bool warnedNoTotal = false;

        downloadProgressListener = (received, total) {
          if (total <= 0) {
            // 真实进度必须依赖 Content-Length。
            // 这里不再做伪进度：用户要求展示真实百分比。
            if (!warnedNoTotal) {
              warnedNoTotal = true;
              Global.logger.w('词典资源下载缺少 Content-Length，无法计算真实下载进度: resourceId=$resourceId');
            }
            return;
          }

          // 有 content-length（或 total 可用）：用真实比例映射到 0%~20%
          final downloadProgress = (received / total).clamp(0.0, 1.0);
          final next = downloadProgress * 0.2;
          if (next > lastEmitted) {
            lastEmitted = next;
            onProgress(next.clamp(0.0, 0.2));
          }
        };
        DownloadProgressManager.addListener(resourceId, downloadProgressListener);
      }

      try {
        // Web 端先不处理（Web 无 isolate/插件限制较多），继续走现有逻辑
        if (kIsWeb) {
          DictRes? dictRes = await getDictRes(dict);
          if (dictRes == null) {
            ToastUtil.error("[$dictId]下载失败");
            return false;
          }
          if (onProgress != null) {
            onProgress(0.2);
          }
          await importDictRes(dictRes, onProgress: (progress) {
            if (onProgress != null) {
              onProgress(0.2 + progress * 0.8);
            }
          });
          return true;
        }

        // 非 Web：下载到临时文件，避免把大包 bytes 在主 isolate 里做拷贝（会导致 20%→21% 仍卡几秒）
        final nonWebStopwatch = Stopwatch()..start();
        double downloadLastEmitted = 0.0;
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, 'dict_res_$dictId.bin');
        await Api.dio.download(
          apiPath,
          tmpPath,
          queryParameters: {'dictId': dictId},
          // 让 Dio 走默认的流式下载路径，避免 bytes 模式在结束阶段产生额外解码/缓存开销
          onReceiveProgress: (received, total) {
            if (onProgress != null && total > 0) {
              final p0 = (received / total).clamp(0.0, 1.0);
              final next = p0 * 0.2;
              if (next > downloadLastEmitted) {
                downloadLastEmitted = next;
                onProgress(next.clamp(0.0, 0.2));
              }
            }
          },
        );
        Global.logger.d('✅ 词典资源下载完成(文件) - dictId=$dictId, 耗时=${nonWebStopwatch.elapsedMilliseconds}ms');

        // 下载完成：进度到 20%
        if (onProgress != null) {
          onProgress(0.2);
        }
        // 让 UI 先有机会渲染 20%（避免紧接着的后续逻辑抢占一帧）
        await Future<void>.delayed(Duration.zero);

        // 解析/准备阶段伪进度（覆盖“反序列化卡顿”）：20% -> 最多 25%，最长 10 秒
        double prepareBase = 0.2;
        double lastEmitted = 0.2;
        Timer? prepareTimer;
        Stopwatch? prepareStopwatch;
        const double prepareWeightMax = 0.05; // 20%~25%
        const int prepareMaxSeconds = 10;

        if (onProgress != null) {
          prepareStopwatch = Stopwatch()..start();
          prepareTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
            final elapsedMs = prepareStopwatch!.elapsedMilliseconds;
            final t = (elapsedMs / (prepareMaxSeconds * 1000)).clamp(0.0, 1.0);
            // ease-out：前期上升更明显，避免用户感觉 20% 卡住
            // 归一化到 [0,1]
            const k = 4.0;
            final eased = (1 - math.exp(-k * t)) / (1 - math.exp(-k));
            final next = 0.2 + prepareWeightMax * eased;
            if (next > lastEmitted) {
              lastEmitted = next;
              prepareBase = next;
              onProgress(next.clamp(0.2, 0.2 + prepareWeightMax));
            }
          });

          // 关键：立即给一个“可见的最小增量”，让用户确认 20% 后进入解析阶段。
          // 然后再把任务交给后台（后台 gzip+jsonDecode 可能会短时间吃满 CPU，导致 UI 定时器被饿死）。
          const immediate = 0.201; // 20.1%
          if (immediate > lastEmitted) {
            lastEmitted = immediate;
            prepareBase = immediate;
            onProgress(immediate);
          }
          // 确保 UI 至少渲染一帧（否则用户会看到 20% 卡住几秒才开始变化）
          await WidgetsBinding.instance.endOfFrame;
        }

        // 计算 db.sqlite 路径（主 isolate 里做，并缓存，避免首次调用 path_provider 导致 20% 附近卡顿）
        final dbPathStart = nonWebStopwatch.elapsedMilliseconds;
        final dbPath = await MyDatabase.getDbFilePath();
        Global.logger.d('📍 获取dbPath耗时=${nonWebStopwatch.elapsedMilliseconds - dbPathStart}ms');

        bool importStarted = false;
        Exception? importError;
        bool done = false;

        // 导入期间暂停数据库同步，避免与后台写库并发导致 database is locked
        ThrottledDbSyncService().suspend();
        Global.logger.d('🚀 开始提交导入任务 - dictId=$dictId');
        await for (final msg in DictImportWorker.instance.submit(dbPath: dbPath, filePath: tmpPath)) {
          final type = msg['type'];
          if (type == 'phase') {
            if (msg['value'] == 'import' && !importStarted) {
              importStarted = true;
              prepareTimer?.cancel();
              prepareStopwatch?.stop();
            }
          } else if (type == 'progress') {
            if (onProgress != null) {
              final double p0 = (msg['value'] as num).toDouble().clamp(0.0, 1.0);
              final overall = prepareBase + p0 * (1.0 - prepareBase);
              if (overall > lastEmitted) {
                lastEmitted = overall;
                onProgress(overall.clamp(prepareBase, 1.0));
              }
            }
          } else if (type == 'done') {
            done = true;
            break;
          } else if (type == 'error') {
            importError = Exception((msg['message'] ?? '后台导入失败').toString());
            break;
          }
        }

        prepareTimer?.cancel();
        prepareStopwatch?.stop();

        if (importError != null) {
          throw importError;
        }
        return done;
      } finally {
        // 恢复数据库同步
        if (!kIsWeb) {
          ThrottledDbSyncService().resume();
        }
        // 移除下载进度监听器
        if (downloadProgressListener != null) {
          DownloadProgressManager.removeListener(resourceId, downloadProgressListener);
        }
      }
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
    final yieldStopwatch = Stopwatch()..start();
    Future<void> yieldToUiIfNeeded([int? forceEveryItems, int? i]) async {
      // 让 UI/Timer 有机会刷新，避免在大列表转换时卡住几秒
      if (forceEveryItems != null && i != null && i % forceEveryItems != 0) {
        return;
      }
      if (yieldStopwatch.elapsedMilliseconds >= 16) {
        yieldStopwatch.reset();
        yieldStopwatch.start();
        await Future<void>.delayed(Duration.zero);
      }
    }

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
      // 先让一帧 UI 有机会刷新（例如 20% 后的“准备阶段”伪进度）
      await Future<void>.delayed(Duration.zero);

      // 收集所有需要执行的操作和对应的记录数
      List<Map<String, dynamic>> operations = [];

      // 添加词书操作（使用 upsert，并补充 popularityLimit）
      if (dictRes.dict != null) {
        operations.add({
          'operation': () => MyDatabase.instance.dictsDao.saveEntity(
              Dict(
                  id: dictRes.dict!.id,
                  isReady: dictRes.dict!.isReady,
                  isShared: dictRes.dict!.isShared,
                  ownerId: dictRes.dict!.ownerId,
                  name: dictRes.dict!.name,
                  wordCount: dictRes.dict!.wordCount,
                  visible: dictRes.dict!.visible,
                  editable: dictRes.dict!.editable ?? (dictRes.dict!.name == '生词本' || dictRes.dict!.ownerId != Global.sysUserId),
                  deletable: dictRes.dict!.deletable ?? (dictRes.dict!.name != '生词本' && dictRes.dict!.name != '已掌握' && dictRes.dict!.ownerId != Global.sysUserId),
                  popularityLimit: dictRes.dict!.popularityLimit,
                  createTime: dictRes.dict!.createTime,
                  updateTime: dictRes.dict!.updateTime),
              false),
          'count': resourceCounts['词书信息']!,
          'name': '词书信息'
        });
      }

      // 添加单词操作(批量) - 必须在词书-单词关系之前插入
      final srcWords = dictRes.words ?? <WordDto>[];
      final List<Word> words = <Word>[];
      for (int i = 0; i < srcWords.length; i++) {
        final word = srcWords[i];
        words.add(Word(
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
            updateTime: word.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (words.isNotEmpty) {
        operations.add({'operation': () => MyDatabase.instance.wordsDao.insertEntities(words), 'count': resourceCounts['单词']!, 'name': '单词'});
      }

      // 添加词书-单词关系操作(批量) - 必须在单词插入之后
      final srcDictWords = dictRes.dictWords ?? <DictWordDto>[];
      final List<DictWord> dictWords = <DictWord>[];
      for (int i = 0; i < srcDictWords.length; i++) {
        final dictWord = srcDictWords[i];
        dictWords.add(DictWord(
            dictId: dictWord.dictId.toString(), // 确保 dictId 是字符串
            wordId: dictWord.wordId,
            seq: dictWord.seq,
            createTime: dictWord.createTime,
            updateTime: dictWord.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (dictWords.isNotEmpty) {
        operations.add({
          'operation': () => MyDatabase.instance.dictWordsDao.insertEntities(dictWords, false),
          'count': resourceCounts['词书-单词关系']!,
          'name': '词书-单词关系'
        });
      }

      // 添加释义操作（批量）- 依赖 Words 和 Dicts
      final srcMeaningItems = dictRes.meaningItems ?? <MeaningItemDto>[];
      final List<MeaningItem> meaningItems = <MeaningItem>[];
      for (int i = 0; i < srcMeaningItems.length; i++) {
        final meaningItem = srcMeaningItems[i];
        meaningItems.add(MeaningItem(
            id: meaningItem.id,
            wordId: meaningItem.wordId,
            dictId: meaningItem.dictId,
            ciXing: meaningItem.ciXing,
            meaning: meaningItem.meaning,
            popularity: meaningItem.popularity,
            createTime: meaningItem.createTime,
            updateTime: meaningItem.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (meaningItems.isNotEmpty) {
        operations
            .add({'operation': () => MyDatabase.instance.meaningItemsDao.insertEntities(meaningItems), 'count': resourceCounts['释义']!, 'name': '释义'});
      }

      // 添加单词图片操作(批量) - 依赖 Words
      final srcImages = dictRes.images ?? <WordImageDto>[];
      final List<WordImage> wordImages = <WordImage>[];
      for (int i = 0; i < srcImages.length; i++) {
        final image = srcImages[i];
        wordImages.add(WordImage(
            id: image.id,
            imageFile: image.imageFile,
            foot: image.foot,
            hand: image.hand,
            authorId: image.authorId ?? "",
            wordId: image.wordId, // 确保 wordId 是字符串
            createTime: image.createTime,
            updateTime: image.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (wordImages.isNotEmpty) {
        operations
            .add({'operation': () => MyDatabase.instance.wordImagesDao.insertEntities(wordImages), 'count': resourceCounts['单词图片']!, 'name': '单词图片'});
      }

      // 添加形近词操作（批量）- 依赖 Words
      final srcSimilarWords = dictRes.similarWords ?? <SimilarWordDto>[];
      final List<SimilarWord> similarWords = <SimilarWord>[];
      for (int i = 0; i < srcSimilarWords.length; i++) {
        final similarWord = srcSimilarWords[i];
        similarWords.add(SimilarWord(
            wordId: similarWord.wordId,
            similarWordId: similarWord.similarWordId,
            similarWordSpell: similarWord.similarWordSpell,
            distance: similarWord.distance));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (similarWords.isNotEmpty) {
        operations.add(
            {'operation': () => MyDatabase.instance.similarWordsDao.insertEntities(similarWords), 'count': resourceCounts['形近词']!, 'name': '形近词'});
      }

      // 添加同义词操作(批量) - 依赖 MeaningItems 和 Words
      final srcSynonyms = dictRes.synonyms ?? <SynonymDto>[];
      final List<Synonym> synonyms = <Synonym>[];
      for (int i = 0; i < srcSynonyms.length; i++) {
        final synonym = srcSynonyms[i];
        synonyms.add(Synonym(
            meaningItemId: synonym.meaningItemId,
            wordId: synonym.wordId,
            spell: synonym.spell,
            createTime: synonym.createTime,
            updateTime: synonym.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
      if (synonyms.isNotEmpty) {
        operations.add({'operation': () => MyDatabase.instance.synonymsDao.insertEntities(synonyms), 'count': resourceCounts['同义词']!, 'name': '同义词'});
      }

      // 添加例句操作(批量) - 依赖 MeaningItems
      final srcSentences = dictRes.sentences ?? <SentenceDto>[];
      final List<Sentence> sentences = <Sentence>[];
      for (int i = 0; i < srcSentences.length; i++) {
        final sentence = srcSentences[i];
        sentences.add(Sentence(
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
            updateTime: sentence.updateTime));
        await yieldToUiIfNeeded(100, i); // 更频繁地让出UI
      }
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
                onPressed: () => loadData(),
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
    final selectedCount =
        dictGroups!.fold<int>(0, (sum, group) => sum + getSelectedDictsOfGroup(group).length) + customDicts!.where((d) => isDictSelected(d)).length;

    _initTabController();

    return DefaultTabController(
      length: dictGroups!.length + 1,
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
            controller: _tabController,
            tabs: renderTabs(),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
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
                          '保存 ($selectedCount)',
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
