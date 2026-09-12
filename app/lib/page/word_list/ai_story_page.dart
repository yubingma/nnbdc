import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../util/toast_util.dart';
import '../../util/utils.dart';
import '../../widget/frosted_glass_card.dart';
import '../../widget/sound_wave_icon.dart';

/// AI 单词小短文阅读页
///
/// 与全站页面保持同一视觉语言：AppScaffold 流光渐变背景 + 主题渐变顶栏 +
/// 一体化毛玻璃阅读卡。英文原文按宽松字阶与行高排布（点击单词可查词），
/// 中文译文以次级灰阶承接在发丝分割线之后。
class AiStoryPage extends StatelessWidget {
  final String storyContent;
  final bool enTtsEnabled;
  final bool cnTtsEnabled;
  final VoidCallback onPlayEn;
  final VoidCallback onPlayCn;

  const AiStoryPage({
    super.key,
    required this.storyContent,
    required this.enTtsEnabled,
    required this.cnTtsEnabled,
    required this.onPlayEn,
    required this.onPlayCn,
  });

  @override
  Widget build(BuildContext context) {
    final config = context.themeConfig;

    final blocks = _splitIntoBlocks(storyContent);

    return AppScaffold(
      appBar: AppAppBar(
        title: 'AI 单词小短文',
        actions: [
          if (enTtsEnabled)
            IconButton(
              icon: const Row(
                children: [
                  ModernSoundWaveIcon(size: 18, color: Colors.white),
                  Text(' En',
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
              tooltip: '播放英文配音',
              onPressed: onPlayEn,
            ),
          if (cnTtsEnabled)
            IconButton(
              icon: const Row(
                children: [
                  ModernSoundWaveIcon(size: 18, color: Colors.white),
                  Text(' 中',
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
              tooltip: '播放中文配音',
              onPressed: onPlayCn,
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
            tooltip: '复制全文',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: storyContent));
              ToastUtil.info('已复制到剪贴板');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          FrostedGlassCard.primary(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 22),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: config.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.055),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _sectionLabel(context, blocks[i].isChinese ? '中文译文' : '英文原文'),
                  const SizedBox(height: 14),
                  ..._paragraphs(blocks[i].paragraphs,
                      (paragraph) => _buildParagraph(context, paragraph, blocks[i].isChinese)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '轻点文中单词即可查词',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: config.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// 把短文切成连续的同类语言段落（英文原文块 / 中文译文块），并保持原文先后顺序
  List<_StoryBlock> _splitIntoBlocks(String story) {
    // **word** -> <b>word</b>，交给富文本工具负责高亮与点词查词
    final processed = story.replaceAllMapped(
        RegExp(r'\*\*(.*?)\*\*'), (match) => '<b>${match.group(1)}</b>');

    final blocks = <_StoryBlock>[];
    for (final paragraph in processed.split('\n')) {
      final text = paragraph.trim();
      if (text.isEmpty) continue;
      final isChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);
      if (blocks.isEmpty || blocks.last.isChinese != isChinese) {
        blocks.add(_StoryBlock(isChinese));
      }
      blocks.last.paragraphs.add(text);
    }
    return blocks;
  }

  /// 英文原文用更宽的字阶与行高承载阅读，中文译文以次级灰阶温润跟随
  Widget _buildParagraph(
      BuildContext context, String paragraph, bool isChinese) {
    final config = context.themeConfig;
    if (isChinese) {
      return Util.makeChineseSpanText(
        paragraph,
        context,
        style: TextStyle(
          fontSize: 14.5,
          height: 1.85,
          color: config.textSecondary,
        ),
      );
    }
    return Util.makeEnglishSpanText(
      paragraph,
      '', // highlightWord：高亮来自 <b> 标签
      true, // highlightWordHasBeenTaged
      context,
      false, // maskHighlightWord
      null, // maskTextField
      false, // isHighlightWordUnClickable
      FontWeight.w400,
      fontSize: 17,
      height: 1.75,
      color: config.textPrimary,
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: context.themeConfig.textSecondary,
      ),
    );
  }

  /// 段落之间以留白分隔，段末不留多余间距
  List<Widget> _paragraphs(
      List<String> paragraphs, Widget Function(String) build) {
    final widgets = <Widget>[];
    for (var i = 0; i < paragraphs.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 12));
      widgets.add(build(paragraphs[i]));
    }
    return widgets;
  }
}

/// 短文中的一段同语言内容
class _StoryBlock {
  final bool isChinese;
  final List<String> paragraphs = [];

  _StoryBlock(this.isChinese);
}
