import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 一词多义·认知语言学核心意象卡片
class WordCoreImageCard extends StatefulWidget {
  final WordCoreImage item;

  const WordCoreImageCard({super.key, required this.item});

  @override
  State<WordCoreImageCard> createState() => _WordCoreImageCardState();
}

class _WordCoreImageCardState extends State<WordCoreImageCard> {
  bool _isExpanded = false;

  String _resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final cleanPath = url.startsWith('/') ? url.substring(1) : url;
    return '${Config.imgBaseUrl}$cleanPath';
  }

  List<Map<String, dynamic>> _parseBranches(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return [];
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      if (data.containsKey('branches') && data['branches'] is List) {
        return List<Map<String, dynamic>>.from(
          (data['branches'] as List).whereType<Map<String, dynamic>>(),
        );
      }
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final item = widget.item;
    final imageUrl = _resolveImageUrl(item.imageUrl);
    final branches = _parseBranches(item.topologyJson);

    final cardBg = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final titleColor = isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final bodyTextColor = isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 标题栏：图标 + 标题 + 核心动势大标签
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.bubble_chart_rounded,
                    size: 16,
                    color: context.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '核心意象',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: titleColor,
                  ),
                ),
                const Spacer(),
                if (item.coreImage != null && item.coreImage!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.coreImage!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),

            // 2. 认知图式 2D 极简简笔画
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return SizedBox(
                        height: 160,
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.primaryColor,
                            ),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ],

            // 3. 认知语言学图式剖析
            if (item.schemaDesc != null && item.schemaDesc!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                item.schemaDesc!,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.55,
                  color: bodyTextColor,
                ),
              ),
            ],

            // 4. 多义引申纽带分支 (Branches)
            if (branches.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 0.6,
                color: borderColor,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '释义引申脉络 (${branches.length})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      child: Row(
                        children: [
                          Text(
                            _isExpanded ? '收起' : '展开',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: context.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 显示前 2 个分支，展开后显示全部
              ...List.generate(
                _isExpanded ? branches.length : (branches.length > 2 ? 2 : branches.length),
                (index) {
                  final b = branches[index];
                  final pos = b['pos']?.toString() ?? '';
                  final meaning = b['meaning']?.toString() ?? '';
                  final relation = b['relation']?.toString() ?? '';
                  final desc = b['desc']?.toString() ?? '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧词性与释义
                        if (pos.isNotEmpty)
                          Text(
                            '$pos ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: subtitleColor,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        Text(
                          meaning,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 右侧引申逻辑标签
                        Expanded(
                          child: Text(
                            relation.isNotEmpty ? '← $relation' : desc,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.primaryColor.withValues(alpha: 0.85),
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
