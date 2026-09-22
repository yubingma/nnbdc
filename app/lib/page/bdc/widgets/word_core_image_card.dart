import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'core_image_orbit_layout.dart';

/// 一词多义·认知语言学核心意象卡片
///
/// 布局形态：中心意象图居中，释义落在环上的框里、箭头指向它，
/// 引申脉络（relation）骑在连线上、被连线穿过。
///
/// 分支过多时（>[_maxOrbitBranches]）环绕会崩：真机实测 9 条以上中心图只剩 ⌀52，
/// 已经不成图，所以自动退回竖排列表，而不是硬撑一张糊掉的图。
class WordCoreImageCard extends StatelessWidget {
  final WordCoreImage item;

  const WordCoreImageCard({super.key, required this.item});

  /// 超过这个分支数就退回列表形态（依据：9 条时中心图仅 ⌀52）
  static const int _maxOrbitBranches = 8;

  /// 按 4 字一行切分 relation。不交给引擎自动换行：
  /// 引擎对 CJK 的断行位置不可控，实测会出现 4+2+2 这种碎裂断法。
  static String wrapRelation(String s, [int per = 4]) {
    if (s.isEmpty) return s;
    final chars = s.characters;
    final buf = StringBuffer();
    for (var i = 0; i < chars.length; i += per) {
      if (i > 0) buf.write('\n');
      buf.write(chars.take(i + per).skip(i).toString());
    }
    return buf.toString();
  }

  static String cleanPunctuation(String? text) {
    if (text == null) return '';
    var s = text.trim();
    const marks = [',', '，', ';', '；', '、', ' '];
    while (s.isNotEmpty && marks.any(s.endsWith)) {
      s = s.substring(0, s.length - 1).trim();
    }
    while (s.isNotEmpty && marks.any(s.startsWith)) {
      s = s.substring(1).trim();
    }
    return s;
  }

  String _resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final cleanPath = url.startsWith('/') ? url.substring(1) : url;
    return '${Config.imgBaseUrl}$cleanPath';
  }

  List<CoreImageBranch> _parseBranches(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return [];
    try {
      final data = jsonDecode(jsonStr);
      if (data is Map && data['branches'] is List) {
        return [
          for (final raw in data['branches'] as List)
            if (raw is Map) CoreImageBranch.fromJson(raw),
        ].where((b) => b.meaning.isNotEmpty).toList();
      }
    } catch (_) {
      // 脏数据不该让整张卡片消失，交给下面的降级分支处理
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final branches = _parseBranches(item.topologyJson);
    final imageUrl = _resolveImageUrl(item.imageUrl);
    final coreImage = cleanPunctuation(item.coreImage);
    final schemaDesc = cleanPunctuation(item.schemaDesc);

    final cardBg =
        isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final titleColor =
        isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final bodyTextColor =
        isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final subtitleColor =
        isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // 有分支且数量在可控范围内 → 环绕形态；否则退回列表，绝不画一张糊掉的图
    final useOrbit =
        branches.length >= 2 && branches.length <= _maxOrbitBranches;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitleRow(context, coreImage, titleColor, useOrbit: useOrbit),
            if (useOrbit)
              _CoreImageOrbit(
                branches: branches,
                imageUrl: imageUrl,
                coreImage: coreImage,
                isDarkMode: isDarkMode,
              )
            else ...[
              if (imageUrl.isNotEmpty) _buildPlainImage(imageUrl, isDarkMode),
              _buildBranchList(branches, isDarkMode, titleColor, subtitleColor),
            ],
            if (schemaDesc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                schemaDesc,
                style: TextStyle(
                    fontSize: 13.5, height: 1.55, color: bodyTextColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow(
    BuildContext context,
    String coreImage,
    Color titleColor, {
    required bool useOrbit,
  }) {
    return Row(
      children: [
        Icon(Icons.bubble_chart_rounded, size: 16, color: context.primaryColor),
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
        // 环绕形态下 coreImage 已经写在中心图里了，这里不再重复
        if (!useOrbit && coreImage.isNotEmpty)
          Text(
            coreImage,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.primaryColor,
            ),
          ),
      ],
    );
  }

  Widget _buildPlainImage(String imageUrl, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          child: Image.network(imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      ),
    );
  }

  /// 降级形态：竖排列表
  Widget _buildBranchList(
    List<CoreImageBranch> branches,
    bool isDarkMode,
    Color titleColor,
    Color subtitleColor,
  ) {
    if (branches.isEmpty) return const SizedBox.shrink();
    final hairline = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(height: 1, thickness: 0.6, color: hairline),
        const SizedBox(height: 10),
        Text(
          '释义引申脉络 (${branches.length})',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: subtitleColor),
        ),
        const SizedBox(height: 4),
        for (final b in branches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.pos.isNotEmpty)
                  Text(
                    '${b.pos} ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                Text(
                  b.meaning,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.relation.isNotEmpty ? '← ${b.relation}' : '',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: subtitleColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一条引申分支
class CoreImageBranch {
  const CoreImageBranch(
      {required this.pos, required this.meaning, required this.relation});

  final String pos;
  final String meaning;
  final String relation;

  factory CoreImageBranch.fromJson(Map<dynamic, dynamic> json) {
    return CoreImageBranch(
      pos: WordCoreImageCard.cleanPunctuation(json['pos']?.toString()),
      meaning: WordCoreImageCard.cleanPunctuation(json['meaning']?.toString()),
      relation:
          WordCoreImageCard.cleanPunctuation(json['relation']?.toString()),
    );
  }

  /// 环上的框要窄，取释义的第一个义项，最多 4 字
  String get shortMeaning {
    final head = meaning.split(RegExp(r'[；;、,/]')).first.trim();
    final base = head.isEmpty ? meaning : head;
    return base.characters.length <= 4
        ? base
        : base.characters.take(4).toString();
  }
}

// ---------------------------------------------------------------------------
// 环绕形态
// ---------------------------------------------------------------------------

class _CoreImageOrbit extends StatelessWidget {
  const _CoreImageOrbit({
    required this.branches,
    required this.imageUrl,
    required this.coreImage,
    required this.isDarkMode,
  });

  final List<CoreImageBranch> branches;
  final String imageUrl;
  final String coreImage;
  final bool isDarkMode;

  /// 画布高度：标签要在上下两个扇区里铺开，垂直空间是这个形态最稀缺的资源。
  /// 压低会同步压小中心图，两者是直接换算关系。
  static const double _canvasHeight = 372;

  static const double _lineWidth = 1.5;

  // 环形标注属于「图内文字」，比正文小；relation 压到 8.5 是为了让中心图站得住
  static const double _relationFontSize = 8.5;
  static const double _posFontSize = 9.5;
  static const double _meaningFontSize = 11;
  static const double _coreLabelFontSize = 11;

  static const double _boxPadH = 9;
  static const double _boxPadV = 5;

  TextStyle _relationStyle(Color c) => TextStyle(
        fontSize: _relationFontSize,
        fontWeight: FontWeight.w400,
        height: 1.32,
        letterSpacing: -0.1,
        color: c,
      );

  TextStyle _posStyle(Color c) => TextStyle(
        fontSize: _posFontSize,
        fontWeight: FontWeight.w600,
        color: c,
      );

  TextStyle _meaningStyle(Color c) => TextStyle(
        fontSize: _meaningFontSize,
        fontWeight: FontWeight.w600,
        color: c,
      );

  /// 图内标注不跟随正文字号缩放（见 build 里的 MediaQuery），
  /// 测量与渲染必须用同一套字度量，否则预留空间会小于实际文字而挤爆。
  static Size _measure(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    return Size(tp.width, tp.height);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    final titleColor =
        isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final borderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);
    final nodeBg = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final lineColor = accent.withValues(alpha: 0.72);

    // 环形图是图形化排版，跟随系统/用户字号放大会直接压垮布局：
    // 这里固定字度量，既保证测量与渲染一致，也让排版在任何字号档位下都稳定。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = _canvasHeight;

        // 1. 先量尺寸，再算布局：位置依赖尺寸，不能反过来
        final metrics = <OrbitNodeMetrics>[];
        final boxSizes = <Size>[];
        final textSizes = <Size>[];
        final wrapped = <String>[];

        for (final b in branches) {
          final posSize =
              b.pos.isEmpty ? Size.zero : _measure(b.pos, _posStyle(accent));
          final meaningSize =
              _measure(b.shortMeaning, _meaningStyle(titleColor));
          final boxW = posSize.width +
              (b.pos.isEmpty ? 0 : 4) +
              meaningSize.width +
              _boxPadH * 2;
          final boxH =
              math.max(posSize.height, meaningSize.height) + _boxPadV * 2;

          final wrappedText = WordCoreImageCard.wrapRelation(b.relation);
          final textSize = _measure(wrappedText, _relationStyle(accent));

          boxSizes.add(Size(boxW, boxH));
          textSizes.add(textSize);
          wrapped.add(wrappedText);
          metrics.add(OrbitNodeMetrics(
            boxHalfW: boxW / 2,
            boxHalfH: boxH / 2,
            textHalfW: textSize.width / 2,
            textHalfH: textSize.height / 2,
          ));
        }

        final labelSize = _measure(
            coreImage,
            TextStyle(
              fontSize: _coreLabelFontSize,
              fontWeight: FontWeight.w600,
              color: accent,
            ));

        final layout = CoreImageOrbitLayout.compute(
          canvas: Size(width, height),
          metrics: metrics,
          labelSize: labelSize,
        );

        final hubImageSize = layout.imageDiameter;

        return SizedBox(
          width: width,
          height: height,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OrbitLinesPainter(
                        layout: layout, color: lineColor, arrowColor: accent),
                  ),
                ),
                // 中心意象图
                _centered(
                  layout.center,
                  hubImageSize,
                  hubImageSize,
                  _HubImage(
                    imageUrl: imageUrl,
                    isDarkMode: isDarkMode,
                    accent: accent,
                  ),
                ),
                // 核心意象文字（写在圆心，语义上就是「被围绕的中心」）
                _centered(
                  layout.labelCenter,
                  labelSize.width + 4,
                  labelSize.height,
                  Text(
                    coreImage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _coreLabelFontSize,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
                // 释义框 + 线上 relation
                for (var i = 0; i < branches.length; i++) ...[
                  _centered(
                    layout.nodes[i].boxCenter,
                    boxSizes[i].width,
                    boxSizes[i].height,
                    _EndpointBox(
                      pos: branches[i].pos,
                      meaning: branches[i].shortMeaning,
                      bg: nodeBg,
                      border: borderColor,
                      accent: accent,
                      titleColor: titleColor,
                      posStyle: _posStyle(accent),
                      meaningStyle: _meaningStyle(titleColor),
                    ),
                  ),
                  _centered(
                    layout.nodes[i].textCenter,
                    textSizes[i].width + 1,
                    textSizes[i].height,
                    Text(
                      wrapped[i],
                      style: _relationStyle(accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _centered(Offset center, double w, double h, Widget child) {
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      width: w,
      height: h,
      child: child,
    );
  }
}

/// 环上的释义框
class _EndpointBox extends StatelessWidget {
  const _EndpointBox({
    required this.pos,
    required this.meaning,
    required this.bg,
    required this.border,
    required this.accent,
    required this.titleColor,
    required this.posStyle,
    required this.meaningStyle,
  });

  final String pos;
  final String meaning;
  final Color bg, border, accent, titleColor;
  final TextStyle posStyle, meaningStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pos.isNotEmpty) ...[
            Text(pos, style: posStyle),
            const SizedBox(width: 4),
          ],
          Text(meaning, style: meaningStyle),
        ],
      ),
    );
  }
}

/// 中心意象图：有配图就用配图，没有就画简笔示意图
class _HubImage extends StatelessWidget {
  const _HubImage(
      {required this.imageUrl, required this.isDarkMode, required this.accent});

  final String imageUrl;
  final bool isDarkMode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bg = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    return ClipOval(
      child: Container(
        color: bg,
        child: imageUrl.isEmpty
            ? CustomPaint(
                painter: _SchematicPainter(color: const Color(0xFF334155)))
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => CustomPaint(
                    painter: _SchematicPainter(color: const Color(0xFF334155))),
              ),
      ),
    );
  }
}

/// 「绕着某个东西转」的极简示意图：虚线圆 + 四向顺时针箭头 + 圆心
class _SchematicPainter extends CustomPainter {
  const _SchematicPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 * 0.72;
    final c = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.017;

    _dashedCircle(canvas, c, r, stroke);
    canvas.drawCircle(c, size.shortestSide * 0.035, stroke);

    // 四个顺时针方向的箭头尖
    final head = size.shortestSide * 0.075;
    _arrowHead(canvas, Offset(c.dx, c.dy - r), const Offset(1, 0), head, color);
    _arrowHead(canvas, Offset(c.dx + r, c.dy), const Offset(0, 1), head, color);
    _arrowHead(
        canvas, Offset(c.dx, c.dy + r), const Offset(-1, 0), head, color);
    _arrowHead(
        canvas, Offset(c.dx - r, c.dy), const Offset(0, -1), head, color);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const segments = 28;
    final step = 2 * math.pi / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step,
          step * 0.62, false, paint);
    }
  }

  void _arrowHead(
      Canvas canvas, Offset at, Offset dir, double len, Color color) {
    final n = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(at.dx + dir.dx * len * 0.5, at.dy + dir.dy * len * 0.5)
      ..lineTo(at.dx + n.dx * len * 0.42, at.dy + n.dy * len * 0.42)
      ..lineTo(at.dx - n.dx * len * 0.42, at.dy - n.dy * len * 0.42)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter old) => old.color != color;
}

/// 连线：中心图边缘 → 穿过线上文字 → 箭头落在释义框边缘
class _OrbitLinesPainter extends CustomPainter {
  const _OrbitLinesPainter({
    required this.layout,
    required this.color,
    required this.arrowColor,
  });

  final OrbitLayoutResult layout;
  final Color color;
  final Color arrowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _CoreImageOrbit._lineWidth
      ..strokeCap = StrokeCap.round;

    for (final n in layout.nodes) {
      canvas.drawLine(n.lineStart, n.lineEnd, paint);
      _arrowHead(canvas, n.lineEnd, n.direction);
    }
  }

  void _arrowHead(Canvas canvas, Offset tip, Offset dir) {
    const len = 6.5;
    final n = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - dir.dx * len + n.dx * len * 0.44,
          tip.dy - dir.dy * len + n.dy * len * 0.44)
      ..lineTo(tip.dx - dir.dx * len - n.dx * len * 0.44,
          tip.dy - dir.dy * len - n.dy * len * 0.44)
      ..close();
    canvas.drawPath(path, Paint()..color = arrowColor);
  }

  @override
  bool shouldRepaint(covariant _OrbitLinesPainter old) =>
      old.layout != layout || old.color != color;
}
