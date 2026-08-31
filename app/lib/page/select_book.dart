import 'dart:async';
import 'dart:convert';

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
import 'package:nnbdc/util/utils.dart';
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
  final Map<String, int> _selectedSubGroupIndex = {}; // 记录每个一级分类下选中的二级分类索引
  List<DictGroupVo>? parentCategories;
  List<DictGroupVo> _filteredCategories = [];
  TabController? _primaryTabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  final GlobalKey _searchKey = GlobalKey(); // 用于锁定搜索框焦点的稳定 Key

  bool isDictSelected(DictVo dict) {
    return selectedDictVos!.contains(dict);
  }

  List<DictVo> getSelectedDictsOfGroup(DictGroupVo group) {
    return group.dicts!.where((element) => isDictSelected(element)).toList();
  }

  bool _fuzzyMatch(String? target, String query) {
    if (target == null || target.isEmpty) return false;
    if (query.isEmpty) return true;

    final targetLower = target.toLowerCase();
    final queryLower = query.toLowerCase().replaceAll(' ', '');
    
    if (queryLower.isEmpty) return true;

    // 先尝试直接包含
    if (targetLower.contains(queryLower)) return true;

    // 模糊匹配：查询字符串中的每个字符都必须出现在目标字符串中
    final chars = queryLower.split('');
    return chars.every((char) => targetLower.contains(char));
  }

  @override
  void initState() {
    super.initState();
    selectedDictVos = {};
    initialSelectedDictVos = {};
    dictGroups = [];
    customDicts = [];
    _hasUserMadeChanges = false;
    // 注意：不要用 addListener，它会在焦点变化时也触发，导致点击 Tab 时 setState 重置控制器
    // 改为只在 onChanged 中更新，避免 Tab 点击被打断
    Future.microtask(() => loadData());
  }

  @override
  void dispose() {
    _primaryTabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 重新计算过滤后的分类列表，并同步更新 TabController。
  /// 只应在数据加载完成或搜索词改变时调用，而不是在 build() 中实时重算。
  void _recomputeFilteredCategories() {
    final searchLower = _searchText.trim().toLowerCase();
    final filtered = (parentCategories ?? []).where((category) {
      if (searchLower.isEmpty) return true;
      if (category.name == '自定义') {
        return customDicts?.any((d) => _fuzzyMatch(d.name, searchLower) || _fuzzyMatch(d.shortName, searchLower)) ?? false;
      }
      return category.childGroups?.any((subGroup) {
        return subGroup.dicts?.any((d) =>
          d.visible == true &&
          (_fuzzyMatch(d.name, searchLower) || _fuzzyMatch(d.shortName, searchLower))
        ) ?? false;
      }) ?? false;
    }).toList();

    if (_primaryTabController == null || _primaryTabController!.length != filtered.length) {
      _primaryTabController?.dispose();
      _primaryTabController = TabController(length: filtered.length, vsync: this);
    }
    _filteredCategories = filtered;
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
      
      // 立即从本地数据库获取现有数据，实现秒开
      var db = MyDatabase.instance;
      var dictGroupsData = await db.select(db.dictGroups).get();
      var groupAndDictLinks = await db.select(db.groupAndDictLinks).get();
      var dicts = await db.select(db.dicts).get();
      List<LearningDict> learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);

      // 内部辅助方法：根据分组 ID 获取词库中的 VO 列表
      List<DictVo> getGroupDicts(String groupId) {
        var results = <DictVo>[];
        var links = groupAndDictLinks.where((l) => l.groupId == groupId).toList();
        for (var link in links) {
          var dict = dicts.cast<Dict?>().firstWhere((d) => d?.id == link.dictId, orElse: () => null);
          if (dict != null && dict.visible != false) {
            var vo = DictVo.c2(dict.id);
            vo.name = dict.name;
            vo.shortName = getShortName(dict.name);
            vo.wordCount = dict.wordCount;
            vo.visible = true;
            vo.updateTime = dict.updateTime;
            results.add(vo);
          }
        }
        results.sort((a, b) {
          if (a.updateTime == null && b.updateTime == null) {
            return (a.name ?? '').compareTo(b.name ?? '');
          }
          if (a.updateTime == null) return 1;
          if (b.updateTime == null) return -1;
          int cmp = b.updateTime!.compareTo(a.updateTime!);
          if (cmp != 0) return cmp;
          return (a.name ?? '').compareTo(b.name ?? '');
        });
        return results;
      }

      // 1. 确定根节点（ID 或 Name）并筛选出所有一级分类
      final rootNode = dictGroupsData.cast<DictGroup?>().firstWhere(
        (g) => g?.name == 'root', 
        orElse: () => null
      );
      final rootId = rootNode?.id;

      // 如果没有名为 root 的节点，则把所有 parentId 为空的分组作为一级分类
      var topGroups = dictGroupsData.where((g) => 
        (rootId != null ? (g.parentId == rootId) : (g.parentId == null || g.parentId == '')) 
        && g.name != 'root' && g.name != '其他'
      ).toList();
      topGroups.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

      // 2. 构建 parentCategories
      parentCategories = [DictGroupVo(id: 'custom_root', name: '自定义', dicts: [])];

      for (var topGroup in topGroups) {
        var subGroupVos = <DictGroupVo>[];
        var allDictsInThisCategory = <DictVo>[];
        var addedDictIds = <String>{};

        // A. 收集直属词书
        var directDicts = getGroupDicts(topGroup.id);
        for (var d in directDicts) {
          if (addedDictIds.add(d.id)) {
            allDictsInThisCategory.add(d);
          }
        }

        // B. 收集子分组及其词书
        var children = dictGroupsData.where((g) => g.parentId == topGroup.id && g.name != '其他').toList();
        children.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

        var validChildrenVos = <DictGroupVo>[];
        for (var child in children) {
          var childDicts = getGroupDicts(child.id);
          if (childDicts.isNotEmpty) {
            var childVo = DictGroupVo(id: child.id, name: child.name, dicts: childDicts, parentId: child.parentId);
            validChildrenVos.add(childVo);
            for (var d in childDicts) {
              if (addedDictIds.add(d.id)) {
                allDictsInThisCategory.add(d);
              }
            }
          }
        }

        // C. 组装结果
        if (allDictsInThisCategory.isNotEmpty) {
          // 如果有多个子分组，或者既有子分组又有直属词书，则需要展示“全部”胶囊以供切换
          if (validChildrenVos.length > 1 || (validChildrenVos.isNotEmpty && directDicts.isNotEmpty)) {
            subGroupVos.add(DictGroupVo(id: 'all_${topGroup.id}', name: '全部', dicts: allDictsInThisCategory));
            subGroupVos.addAll(validChildrenVos);
          } else if (validChildrenVos.length == 1) {
            // 只有一个子分组且没有直属词书，直接显示该子分组（UI会隐藏胶囊）
            subGroupVos.add(validChildrenVos[0]);
          } else {
            // 只有直属词书（UI会隐藏胶囊）
            subGroupVos.add(DictGroupVo(id: topGroup.id, name: topGroup.name, dicts: directDicts));
          }

          var parentVo = DictGroupVo(id: topGroup.id, name: topGroup.name, dicts: []);
          parentVo.childGroups = subGroupVos;
          parentCategories!.add(parentVo);
        }
      }

      // 同步给后文使用的 dictGroups 变量
      dictGroups = parentCategories;

      // 初始化二级分类索引
      for (var cat in parentCategories!) {
        _selectedSubGroupIndex[cat.name] ??= 0;
      }

      customDicts = (await WordBo().getCustomDicts(userId)).where((d) => d.name != '已掌握').toList();
      customDicts!.sort((a, b) {
        if (a.updateTime == null && b.updateTime == null) {
          return (a.name ?? '').compareTo(b.name ?? '');
        }
        if (a.updateTime == null) return 1;
        if (b.updateTime == null) return -1;
        int cmp = b.updateTime!.compareTo(a.updateTime!);
        if (cmp != 0) return cmp;
        return (a.name ?? '').compareTo(b.name ?? '');
      });

      if (!keepSelection) {
        selectedDictVos = learningDicts.map((e) {
          // 优先从已加载的分组词书中查找，这样可以获取完整的 VO 信息（包括 name 和 baseDictId）
          if (dictGroups != null) {
            for (var group in dictGroups!) {
              for (var dict in group.dicts!) {
                if (dict.id == e.dictId) return dict;
              }
            }
          }
          // 其次从自定义词书中查找
          if (customDicts != null) {
            for (var dict in customDicts!) {
              if (dict.id == e.dictId) return dict;
            }
          }
          // 如果都没找到，则从本地 DB 查找，以便补齐 Metadata（name, baseDictId) 用于下载对话框展示
          final dbDict = dicts.cast<Dict?>().firstWhere((d) => d?.id == e.dictId, orElse: () => null);
          if (dbDict != null) {
            var vo = DictVo.c2(dbDict.id, dbDict.wordCount);
            vo.name = dbDict.name;
            vo.shortName = Util.getShortName(dbDict.name);
            vo.baseDictId = dbDict.baseDictId;
            return vo;
          }
          // 最后实在找不到，才返回一个只有 ID 的补白 VO
          return DictVo.c2(e.dictId);
        }).toSet();
        initialSelectedDictVos = Set.from(selectedDictVos!); // 保存初始状态
      }

      if (!mounted) return;
      // 更新UI，并重算过滤分类
      setState(() {
        _isLoading = false;
        _recomputeFilteredCategories();
      });
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: '加载词书数据', showToast: true);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _recomputeFilteredCategories();
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

  Widget _buildPrimaryTabContent(DictGroupVo parentVo, bool isDarkMode) {
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F8F8);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF333333);
    final subtitleColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    if (parentVo.name == '自定义') {
      return _buildCustomTabContent(isDarkMode, backgroundColor, textColor, subtitleColor);
    }

    final searchLower = _searchText.trim().toLowerCase();
    final subGroups = (parentVo.childGroups ?? []).where((subGroup) {
      if (searchLower.isEmpty) return true;
      return subGroup.dicts?.any((d) => 
        d.visible == true && 
        (_fuzzyMatch(d.name, searchLower) || _fuzzyMatch(d.shortName, searchLower))
      ) ?? false;
    }).toList();

    if (subGroups.isEmpty) return const Center(child: Text('没有匹配的词书'));

    // 如果只有一个二级分类，直接显示列表
    if (subGroups.length == 1) {
      return _buildBookList(subGroups[0].dicts ?? [], isDarkMode);
    }

    // 多个二级分类，显示胶囊选择器
    final selectedSubIndex = _selectedSubGroupIndex[parentVo.name] ?? 0;
    
    // 边界检查
    final actualIndex = selectedSubIndex < subGroups.length ? selectedSubIndex : 0;
    final activeSubGroup = subGroups[actualIndex];

    return Column(
      children: [
        _buildSubCategoryCapsules(parentVo, subGroups, actualIndex, isDarkMode),
        Expanded(
          child: _buildBookList(activeSubGroup.dicts ?? [], isDarkMode),
        ),
      ],
    );
  }

  static final List<List<Color>> _bookGradients = [
    [const Color(0xFF18BA7C), const Color(0xFF0D8255)], // 翡翠绿
    [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)], // 深海蓝
    [const Color(0xFFF59E0B), const Color(0xFFD97706)], // 琥珀金
    [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)], // 紫罗兰
    [const Color(0xFFEC4899), const Color(0xFFBE185D)], // 玫瑰粉
    [const Color(0xFF06B6D4), const Color(0xFF0E7490)], // 天青蓝
    [const Color(0xFF10B981), const Color(0xFF047857)], // 薄荷绿
  ];

  String _formatNumber(int num) {
    return num.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Widget _buildBookCover(String title, int index, {bool isCustom = false}) {
    final gradient = isCustom
        ? [const Color(0xFF64748B), const Color(0xFF334155)]
        : _bookGradients[index.abs() % _bookGradients.length];
    final initial = Util.getInitial(title).toUpperCase();

    return Container(
      width: 44,
      height: 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 书脊暗影效果
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                ),
              ),
            ),
          ),
          // 书脊内侧压线
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            width: 1,
            child: Container(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          // 封面中央字母与小标
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 14,
                  height: 1.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubCategoryCapsules(DictGroupVo parentVo, List<DictGroupVo> subGroups, int selectedIndex, bool isDarkMode) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: subGroups.length,
        itemBuilder: (context, index) {
          final group = subGroups[index];
          final isSelected = index == selectedIndex;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  setState(() {
                    _selectedSubGroupIndex[parentVo.name] = index;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isDarkMode ? const Color(0xFF192C27) : const Color(0xFFFFFFFF)),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDarkMode ? Colors.white12 : const Color(0xFFD1EADE)),
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    group.name,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF425B57)),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookList(List<DictVo> books, bool isDarkMode) {
    final searchLower = _searchText.trim().toLowerCase();
    final visibleBooks = books.where((b) => 
      b.visible == true && 
      (_searchText.isEmpty || _fuzzyMatch(b.name, searchLower) || _fuzzyMatch(b.shortName, searchLower))
    ).toList();

    if (visibleBooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: isDarkMode ? Colors.white24 : const Color(0xFFB2CDC8)),
            const SizedBox(height: 12),
            Text(
              '没有找到匹配的词书',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: visibleBooks.length,
      itemBuilder: (context, index) {
        final dict = visibleBooks[index];
        final isSelected = isDictSelected(dict);
        final bookTitle = dict.shortName ?? dict.name ?? '';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? const Color(0xFF152B24) : const Color(0xFFEDF8F3))
                : (isDarkMode ? const Color(0xFF131E1C) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                  : (isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => toggleDictSelectedStatus(dict),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 立体精致封面
                    _buildBookCover(bookTitle, index),
                    const SizedBox(width: 14),
                    // 词书信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bookTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFE8F8F1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_formatNumber(dict.wordCount ?? 0)} 词',
                                  style: TextStyle(
                                    color: isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (dict.domain != null && dict.domain!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  dict.domain!,
                                  style: TextStyle(
                                    color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 勾选圆形指示器
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                              : (isDarkMode ? Colors.white24 : const Color(0xFFB2CDC8)),
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomTabContent(bool isDarkMode, Color backgroundColor, Color textColor, Color? subtitleColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Builder(builder: (context) {
            final restricted = PlatformUtils.isIOS && !SubscriptionUtil.isPremium();
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showCreateDictDialog,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    color: restricted
                        ? (isDarkMode ? const Color(0xFF1F2A28) : const Color(0xFFE2E8F0))
                        : (isDarkMode ? const Color(0xFF152B24) : const Color(0xFFEDF8F3)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: restricted
                          ? Colors.grey
                          : (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        restricted ? Icons.lock_outline_rounded : Icons.add_rounded,
                        size: 20,
                        color: restricted
                            ? Colors.grey
                            : (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '新建单词书',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: restricted
                              ? Colors.grey
                              : (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        Expanded(
          child: Builder(builder: (context) {
            final searchLower = _searchText.trim().toLowerCase();
            final filteredCustomDicts = customDicts!.where((d) => 
              _searchText.isEmpty || _fuzzyMatch(d.name, searchLower) || _fuzzyMatch(d.shortName, searchLower)
            ).toList();

            if (filteredCustomDicts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu_book_rounded, size: 48, color: isDarkMode ? Colors.white24 : const Color(0xFFB2CDC8)),
                    const SizedBox(height: 12),
                    Text(
                      _searchText.isEmpty ? '点击上方按钮创建词书' : '没有匹配的自定义词书',
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
              itemCount: filteredCustomDicts.length,
              itemBuilder: (context, index) {
                final dict = filteredCustomDicts[index];
                final isSelected = isDictSelected(dict);
                final bookTitle = dict.name ?? '未命名';

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDarkMode ? const Color(0xFF152B24) : const Color(0xFFEDF8F3))
                        : (isDarkMode ? const Color(0xFF131E1C) : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                          : (isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA)),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本' && !isSelected) {
                          _showPremiumPrompt();
                          return;
                        }
                        toggleDictSelectedStatus(dict);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _buildBookCover(bookTitle, index, isCustom: true),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          bookTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'NotoSansSC',
                                          ),
                                        ),
                                      ),
                                      if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本') ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.grey),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFE8F8F1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_formatNumber(dict.wordCount ?? 0)} 词',
                                      style: TextStyle(
                                        color: isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 操作按钮
                            IconButton(
                              icon: Icon(
                                Icons.edit_note_rounded,
                                size: 22,
                                color: (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本')
                                    ? Colors.grey
                                    : (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor),
                              ),
                              onPressed: () async {
                                if (PlatformUtils.isIOS && !SubscriptionUtil.isPremium() && dict.name != '生词本') {
                                  _showPremiumPrompt();
                                  return;
                                }
                                await toDictWordsListPage(dict, true);
                                loadData(keepSelection: true);
                              },
                              tooltip: '管理单词',
                            ),
                            if (dict.canDelete != false)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                                onPressed: () => _confirmDeleteDict(dict),
                                tooltip: '删除词书',
                              ),
                            const SizedBox(width: 4),
                            // 勾选指示器
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? (isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor)
                                      : (isDarkMode ? Colors.white24 : const Color(0xFFB2CDC8)),
                                  width: 1.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Center(
                                      child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
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

                  final now = AppClock.now();
                  LearningDict learningDict = LearningDict(
                      userId: user.id!,
                      dictId: dictVo.id,
                      isPrivileged: false,
                      fetchMastered: false,
                      sortAlg: 'ORIGINAL',
                      createTime: now,
                      updateTime: now);
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
        if (dictVo.baseDictId != null && dictVo.baseDictId!.isNotEmpty) {
          DictVo? baseVo;
          if (dictGroups != null) {
            for (var group in dictGroups!) {
              final found = group.dicts?.where((d) => d.id == dictVo.baseDictId!);
              if (found != null && found.isNotEmpty) {
                baseVo = found.first;
                break;
              }
            }
          }
          if (baseVo != null) {
            bool hasWords = await db.dictWordsDao.hasDictWords(baseVo.id);
            if (!hasWords && !dictsToDownload.any((element) => element.id == baseVo!.id)) {
              dictsToDownload.insert(0, baseVo);
              Global.logger.i("衍生版依赖源词书，添加源词书下载: ${baseVo.id}");
            }
          }
        }

        Dict? existing = await db.dictsDao.findById(dictVo.id);

        // 检查词书是否存在，或存在但没有单词
        if (existing == null) {
          // 词书不存在，需要下载
          if (!dictsToDownload.any((element) => element.id == dictVo.id)) {
            dictsToDownload.add(dictVo);
          }
        } else {
          // 词书存在，但只有当owner是15118(系统词书)时才需要检查是否有单词
          if (existing.ownerId == "15118") {
            bool hasWords = await db.dictWordsDao.hasDictWords(dictVo.id);
            if (!hasWords) {
              if (!dictsToDownload.any((element) => element.id == dictVo.id)) {
                dictsToDownload.add(dictVo);
              }
            }
          }
        }
      }

      if (!skipDownloadInTest && dictsToDownload.isNotEmpty && mounted && !DictDownloadDialog.isShowing) {
        // 显示下载对话框
        await DictDownloadDialog.show(
          context: context,
          dicts: dictsToDownload,
          onComplete: () {},
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
      String? baseDictId = dict.baseDictId;
      if (ownerId == null || baseDictId == null) {
        final dictMeta = await MyDatabase.instance.dictsDao.findById(dictId);
        ownerId ??= dictMeta?.ownerId;
        baseDictId ??= dictMeta?.baseDictId;
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

          // 自动在本地生成衍生版节点（基于原词书生成临时的 DictWord 记录但不上传同步）
          if (baseDictId != null && baseDictId.isNotEmpty) {
            final db = MyDatabase.instance;
            final baseDictDb = await db.dictsDao.findById(baseDictId);
            if (baseDictDb != null) {
              Global.logger.i('📥 Web端本地动态生成衍生版词书节点: ${dict.id}, baseDictId: $baseDictId');
              await WordBo().generateShuffledDictLocally(dict.id, baseDictDb.id);
            }
          }

          return true;
        }

        // 非 Web：下载到临时文件，避免把大包 bytes 在主 isolate 里做拷贝（会导致 20%→21% 仍卡几秒）
        final nonWebStopwatch = Stopwatch()..start();
        double downloadLastEmitted = 0.0;
        final tmpDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tmpPath = p.join(tmpDir.path, 'dict_res_${dictId}_$timestamp.bin');
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

        prepareTimer?.cancel();
        prepareStopwatch?.stop();

        if (importError != null) {
          throw importError;
        }

        // 自动在本地生成衍生版节点（基于原词书生成临时的 DictWord 记录但不上传同步）
        if (baseDictId != null && baseDictId.isNotEmpty) {
          final db = MyDatabase.instance;
          final baseDictDb = await db.dictsDao.findById(baseDictId);
          if (baseDictDb != null) {
            Global.logger.i('📥 本地动态生成衍生版词书节点: ${dict.id}, baseDictId: $baseDictId');
            await WordBo().generateShuffledDictLocally(dict.id, baseDictDb.id);
          }
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
                  baseDictId: dictRes.dict!.baseDictId,
                  sortAlg: dictRes.dict!.sortAlg,
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
            embedding1bit: word.embedding1bit != null ? base64Decode(word.embedding1bit!) : null,
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
            unit: dictWord.unit,
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
        // MeaningItem 实体构造器接收新参数 popularityPercent
        meaningItems.add(MeaningItem(
            id: meaningItem.id,
            wordId: meaningItem.wordId,
            dictId: meaningItem.dictId,
            ciXing: meaningItem.ciXing,
            meaning: meaningItem.meaning,
            popularity: meaningItem.popularity,
            popularityPercent: meaningItem.popularityPercent,
            ownerId: meaningItem.ownerId ?? "",
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
            ownerId: image.ownerId ?? "",
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
            distance: similarWord.distance,
            createTime: similarWord.createTime,
            updateTime: similarWord.updateTime));
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
            authorId: sentence.authorId ?? "",
            ownerId: sentence.ownerId ?? "",
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

  Widget _buildFloatingSaveBar(bool isDarkMode) {
    final selectedCount = selectedDictVos?.length ?? 0;
    int totalWords = 0;
    if (selectedDictVos != null) {
      for (var d in selectedDictVos!) {
        totalWords += d.wordCount ?? 0;
      }
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16,
        (MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom + 6 : 12),
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已选择 $selectedCount 本词书',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共计 ${_formatNumber(totalWords)} 单词',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: save,
            icon: const Icon(Icons.check_rounded, size: 17),
            label: Text(_hasUserMadeChanges ? '保存并同步' : '完成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0C1312) : const Color(0xFFF5F9F7);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF152724);

    if (_isLoading && (parentCategories == null || parentCategories!.isEmpty)) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (parentCategories == null || parentCategories!.isEmpty) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
          title: const Text('选词书'),
          centerTitle: true,
        ),
        body: const Center(child: Text('没有可用的词书')),
      );
    }

    final filteredCategories = _filteredCategories;
    final tabController = _primaryTabController;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: _buildSearchField(isDarkMode, textColor),
        leading: Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF7FBF9),
                  border: Border.all(
                    color: isDarkMode ? Colors.white12 : const Color(0xFFE1EFEA),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 14,
                    color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: save,
            child: Text(
              _hasUserMadeChanges ? '完成' : '保存',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: (tabController != null && filteredCategories.isNotEmpty)
              ? Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA),
                        width: 1,
                      ),
                    ),
                  ),
                  child: TabBar(
                    controller: tabController,
                    isScrollable: true,
                    labelColor: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                    unselectedLabelColor: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691),
                    indicatorColor: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 2.5,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5),
                    dividerColor: Colors.transparent,
                    tabAlignment: TabAlignment.start,
                    tabs: filteredCategories.map((cat) => Tab(text: cat.name)).toList(),
                  ),
                )
              : const SizedBox(height: 44),
        ),
      ),
      bottomNavigationBar: _buildFloatingSaveBar(isDarkMode),
      body: (filteredCategories.isEmpty || tabController == null)
          ? Center(
              child: Text(
                '没有找到匹配的词书',
                style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black45),
              ),
            )
          : TabBarView(
              controller: tabController,
              children: filteredCategories.map((cat) => _buildPrimaryTabContent(cat, isDarkMode)).toList(),
            ),
    );
  }

  Widget _buildSearchField(bool isDarkMode, Color textColor) {
    return Container(
      key: _searchKey,
      height: 38,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF192C27) : const Color(0xFFEDF5F2),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: isDarkMode ? Colors.white12 : const Color(0xFFD1EADE),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
          fontSize: 13.5,
        ),
        onChanged: (value) {
          setState(() {
            _searchText = value;
            _recomputeFilteredCategories();
          });
        },
        decoration: InputDecoration(
          hintText: '搜索词库 / 词书名称...',
          hintStyle: TextStyle(
            color: isDarkMode ? const Color(0xFF6B8B84) : const Color(0xFF8EA8A3),
            fontSize: 13.5,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDarkMode ? const Color(0xFF6B8B84) : const Color(0xFF8EA8A3),
            size: 18,
          ),
          suffixIcon: _searchText.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF6B8B84),
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchText = '';
                      _recomputeFilteredCategories();
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
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
