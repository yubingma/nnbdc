import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';

import '../../../state.dart';
import '../../../theme/app_theme.dart';
import '../word_list_actions.dart';
import 'word_list_item_layout.dart';

/// 同根词表的词根组头行：整行展示「分类胶囊 + 词根 + 中文含义 + 族内词数」。
/// 词根不是单词，本行纯展示不可点；复用 [WordListItemLayout] 的卡片外观与分组圆角，
/// 使其与族内单词共处同一张分组卡片。
class RootFamilyHeaderItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isDarkMode;
  final WordListActionHandler actions;
  final GroupCardPosition groupPosition;

  const RootFamilyHeaderItem({
    super.key,
    required this.word,
    required this.index,
    required this.baseIndex,
    required this.isDarkMode,
    required this.actions,
    this.groupPosition = GroupCardPosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final themeConfig = AppThemeConfig.of(context.watch<DarkMode>().themeStyle);
    final cigen = word.tag is CigenVo ? word.tag as CigenVo : null;

    return WordListItemLayout(
      word: word,
      index: index,
      baseIndex: baseIndex,
      studyMode: WordListStudyMode.list,
      isBookmarked: false,
      isDarkMode: isDarkMode,
      learningStatus: null,
      showWordProgress: false,
      actions: actions,
      slidableActions: const [],
      groupPosition: groupPosition,
      // 组头是「组头 + 族首词」这张卡的上半部分：底部不留边距，与首词无缝相接
      cardMarginOverride:
          const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 0),      headerContent: buildRootFamilyHeaderContent(
        cigen: cigen,
        spell: word.word.spell,
        count: word.word.meaningStr,
        isDarkMode: isDarkMode,
        themeConfig: themeConfig,
      ),
    );
  }
}

/// 词根组头行的行内内容（独立纯函数，便于直接做窄宽约束下的溢出回归测试）。
///
/// 布局：左侧「分类胶囊 + 词根 + 含义」占据全部剩余空间（含义可省略、词根可收缩），
/// 词数固定在行尾——任何词根/含义长度组合都不会溢出。
Widget buildRootFamilyHeaderContent({
  required CigenVo? cigen,
  required String spell,
  required String? count,
  required bool isDarkMode,
  required AppThemeConfig themeConfig,
}) {
  final label = switch (cigen?.category) {
    'ROOT' => '词根',
    'PREFIX' => '前缀',
    'SUFFIX' => '后缀',
    _ => '词缀',
  };
  // 词根主题色（琥珀）：沿用详情页词根 Tab 的语义色
  final accent = isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  final bodyColor = themeConfig.textSecondary;

  return Container(
    key: headerContentKey,
    color: accent.withValues(alpha: isDarkMode ? 0.10 : 0.055),
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDarkMode ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 7),
          // 词根：不参与弹性空间分配（正常宽度下按自身宽度完整显示）；
          // 仅当它超过可用宽度的 40%（极窄屏上的超长合并前缀条目）才收缩省略。
          // 这样弹性空间全部留给释义，不会出现"词根与释义各占一半、右侧却留白"。
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
            child: Text(
              spell,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          if (cigen?.meaningCn?.isNotEmpty ?? false) ...[
            const SizedBox(width: 7),
            // 其余空间全部给释义：放得下就完整显示，确实放不下才省略号
            Expanded(
              child: Text(
                cigen!.meaningCn!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: bodyColor,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (count != null && count.isNotEmpty) ...[
            const SizedBox(width: 8),
            // 词数固定右对齐：无论词根/释义多长都贴着行尾
            SizedBox(
              width: _countColumnWidth,
              child: Text(
                count,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: bodyColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 词数右对齐列的固定宽度：约容纳「999 词」，保证各行词数右边界整齐
const double _countColumnWidth = 46;

/// 组头行根容器 key（供测试定位行边界与内容宽度）
const Key headerContentKey = Key('root_family_header_content');
