import 'package:flutter/material.dart';

/// 海报数据实体
class PosterData {
  final String userName;
  final int continuousDays;
  final int todayWords;
  final int memoryRate;
  final int totalWords;
  final String dateStr;

  const PosterData({
    required this.userName,
    required this.continuousDays,
    required this.todayWords,
    required this.memoryRate,
    required this.totalWords,
    required this.dateStr,
  });
}

/// 海报主题配置
enum PosterThemeType {
  glacier,  // ① 冰川湛蓝 (极光纯蓝)
  cobalt,   // ② 皇家钴蓝 (深邃深蓝)
  dark,     // ③ 暗夜深邃 (沉浸蓝黑)
  sunrise,  // ④ 暖阳晨读 (清晨早读)
  pink,     // ⑤ 活力粉紫 (开口不怕忘)
  green,    // ⑥ 森林墨绿 (慢慢来比较快)
}

class PosterThemeConfig {
  final String name;
  final Color bgGradientStart;
  final Color bgGradientMiddle;
  final Color bgGradientEnd;
  final Color borderColor;
  final Color brandColor;
  final Color tagColor;
  final Color tagBgColor;
  final String tagText;
  final Color numberColorStart;
  final Color numberColorEnd;
  final Color cardBgColor;
  final Color cardBorderColor;
  final Color statHighlightColor;
  final Color quoteTextColor;
  final Color quoteBgColor;
  final Color quoteBorderColor;
  final String quoteMain;
  final String quoteSub;
  final String dateTag;
  final bool isDark;

  const PosterThemeConfig({
    required this.name,
    required this.bgGradientStart,
    required this.bgGradientMiddle,
    required this.bgGradientEnd,
    required this.borderColor,
    required this.brandColor,
    required this.tagColor,
    required this.tagBgColor,
    required this.tagText,
    required this.numberColorStart,
    required this.numberColorEnd,
    required this.cardBgColor,
    required this.cardBorderColor,
    required this.statHighlightColor,
    required this.quoteTextColor,
    required this.quoteBgColor,
    required this.quoteBorderColor,
    required this.quoteMain,
    required this.quoteSub,
    required this.dateTag,
    this.isDark = true,
  });

  static PosterThemeConfig getConfig(PosterThemeType type) {
    switch (type) {
      case PosterThemeType.glacier:
        return const PosterThemeConfig(
          name: '冰川湛蓝',
          bgGradientStart: Color(0xFF0A2540),
          bgGradientMiddle: Color(0xFF06182A),
          bgGradientEnd: Color(0xFF030D17),
          borderColor: Color(0x5938BDF8),
          brandColor: Color(0xFF38BDF8),
          tagColor: Color(0xFF38BDF8),
          tagBgColor: Color(0x2638BDF8),
          tagText: '大声开口 记得牢',
          numberColorStart: Color(0xFFFFFFFF),
          numberColorEnd: Color(0xFF38BDF8),
          cardBgColor: Color(0x0AFFFFFF),
          cardBorderColor: Color(0x14FFFFFF),
          statHighlightColor: Color(0xFF38BDF8),
          quoteTextColor: Color(0xFFE2E8F0),
          quoteBgColor: Color(0x0AFFFFFF),
          quoteBorderColor: Color(0x3338BDF8),
          quoteMain: '“多开口读，全感官记忆。”',
          quoteSub: '每天坚持读一读。',
          dateTag: 'GLACIER',
          isDark: true,
        );
      case PosterThemeType.cobalt:
        return const PosterThemeConfig(
          name: '皇家钴蓝',
          bgGradientStart: Color(0xFF1E3A8A),
          bgGradientMiddle: Color(0xFF172554),
          bgGradientEnd: Color(0xFF0B1120),
          borderColor: Color(0x593B82F6),
          brandColor: Color(0xFF60A5FA),
          tagColor: Color(0xFF60A5FA),
          tagBgColor: Color(0x263B82F6),
          tagText: '嘴巴记住 脑子不忘',
          numberColorStart: Color(0xFFFFFFFF),
          numberColorEnd: Color(0xFF60A5FA),
          cardBgColor: Color(0x0AFFFFFF),
          cardBorderColor: Color(0x14FFFFFF),
          statHighlightColor: Color(0xFF60A5FA),
          quoteTextColor: Color(0xFFE2E8F0),
          quoteBgColor: Color(0x0AFFFFFF),
          quoteBorderColor: Color(0x333B82F6),
          quoteMain: '“嘴巴读得出，心里有底气。”',
          quoteSub: '每天大声读，踏踏实实积累。',
          dateTag: 'COBALT',
          isDark: true,
        );
      case PosterThemeType.dark:
        return const PosterThemeConfig(
          name: '暗夜深邃',
          bgGradientStart: Color(0xFF16203B),
          bgGradientMiddle: Color(0xFF0B1120),
          bgGradientEnd: Color(0xFF060A12),
          borderColor: Color(0x406366F1),
          brandColor: Color(0xFF38BDF8),
          tagColor: Color(0xFF38BDF8),
          tagBgColor: Color(0x2638BDF8),
          tagText: '大声开口 记得才牢',
          numberColorStart: Color(0xFFFFFFFF),
          numberColorEnd: Color(0xFF93C5FD),
          cardBgColor: Color(0x0AFFFFFF),
          cardBorderColor: Color(0x14FFFFFF),
          statHighlightColor: Color(0xFF38BDF8),
          quoteTextColor: Color(0xFFE2E8F0),
          quoteBgColor: Color(0x0AFFFFFF),
          quoteBorderColor: Color(0x14FFFFFF),
          quoteMain: '“光看容易忘，大声读才真会。”',
          quoteSub: '每天十分钟，踏踏实实背完。',
          dateTag: 'TODAY',
          isDark: true,
        );
      case PosterThemeType.sunrise:
        return const PosterThemeConfig(
          name: '暖阳晨读',
          bgGradientStart: Color(0xFFFFFDF5),
          bgGradientMiddle: Color(0xFFFEF3C7),
          bgGradientEnd: Color(0xFFFDE68A),
          borderColor: Color(0x4DF59E0B),
          brandColor: Color(0xFFD97706),
          tagColor: Color(0xFF92400E),
          tagBgColor: Color(0x26D97706),
          tagText: '☀️ 晨读打卡',
          numberColorStart: Color(0xFFD97706),
          numberColorEnd: Color(0xFF9A3412),
          cardBgColor: Color(0xC0FFFFFF),
          cardBorderColor: Color(0x33F59E0B),
          statHighlightColor: Color(0xFFB45309),
          quoteTextColor: Color(0xFF78350F),
          quoteBgColor: Color(0xA6FFFFFF),
          quoteBorderColor: Color(0x33F59E0B),
          quoteMain: '“一天背一点，坚持就很厉害。”',
          quoteSub: '每天早晨开口读，心里很踏实。',
          dateTag: 'MORNING',
          isDark: false,
        );
      case PosterThemeType.pink:
        return const PosterThemeConfig(
          name: '活力粉紫',
          bgGradientStart: Color(0xFF251230),
          bgGradientMiddle: Color(0xFF130B1B),
          bgGradientEnd: Color(0xFF08050D),
          borderColor: Color(0x40EC4899),
          brandColor: Color(0xFFF472B6),
          tagColor: Color(0xFFF472B6),
          tagBgColor: Color(0x26EC4899),
          tagText: '🗣️ 开口读 不怕忘',
          numberColorStart: Color(0xFFFFFFFF),
          numberColorEnd: Color(0xFFF472B6),
          cardBgColor: Color(0x0AFFFFFF),
          cardBorderColor: Color(0x14FFFFFF),
          statHighlightColor: Color(0xFFF472B6),
          quoteTextColor: Color(0xFFE2E8F0),
          quoteBgColor: Color(0x0AFFFFFF),
          quoteBorderColor: Color(0x33EC4899),
          quoteMain: '“嘴巴记住了，脑子就不会忘。”',
          quoteSub: '大声读一遍，胜过默看十遍。',
          dateTag: 'KEEP GOING',
          isDark: true,
        );
      case PosterThemeType.green:
        return const PosterThemeConfig(
          name: '森林墨绿',
          bgGradientStart: Color(0xFF0E2E25),
          bgGradientMiddle: Color(0xFF061A14),
          bgGradientEnd: Color(0xFF030D0A),
          borderColor: Color(0x4010B981),
          brandColor: Color(0xFF34D399),
          tagColor: Color(0xFF34D399),
          tagBgColor: Color(0x2610B981),
          tagText: '🌿 慢慢来 比较快',
          numberColorStart: Color(0xFFFFFFFF),
          numberColorEnd: Color(0xFF6EE7B7),
          cardBgColor: Color(0x0AFFFFFF),
          cardBorderColor: Color(0x14FFFFFF),
          statHighlightColor: Color(0xFF34D399),
          quoteTextColor: Color(0xFFE2E8F0),
          quoteBgColor: Color(0x0AFFFFFF),
          quoteBorderColor: Color(0x3310B981),
          quoteMain: '“背词无捷径，开口是良方。”',
          quoteSub: '每天完成计划，不知不觉积累。',
          dateTag: 'PROGRESS',
          isDark: true,
        );
    }
  }
}

/// 打卡海报组件
class DakaPosterWidget extends StatelessWidget {
  final PosterData data;
  final PosterThemeType themeType;
  final double width;

  const DakaPosterWidget({
    super.key,
    required this.data,
    this.themeType = PosterThemeType.glacier,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = PosterThemeConfig.getConfig(themeType);
    final height = width * 16 / 9;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cfg.borderColor, width: 1.5),
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.1,
          colors: [
            cfg.bgGradientStart,
            cfg.bgGradientMiddle,
            cfg.bgGradientEnd,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 顶部栏
          _buildTopBar(cfg),

          // 主视觉打卡天数
          _buildHeroSection(cfg),

          // 3 栏数据卡片
          _buildDataCard(cfg),

          // 金句卡片
          _buildQuoteCard(cfg),

          // 底部用户标识
          _buildFooter(cfg),
        ],
      ),
    );
  }

  Widget _buildTopBar(PosterThemeConfig cfg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // 统一的泡泡 Logo
            CustomPaint(
              size: const Size(18, 18),
              painter: _BubbleLogoPainter(color: cfg.brandColor),
            ),
            const SizedBox(width: 6),
            Text(
              '泡泡单词',
              style: TextStyle(
                color: cfg.brandColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        Text(
          data.dateStr.isNotEmpty ? data.dateStr : cfg.dateTag,
          style: TextStyle(
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.65) : cfg.brandColor.withValues(alpha: 0.75),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(PosterThemeConfig cfg) {
    return Column(
      children: [
        // 药丸微标
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: cfg.tagBgColor,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: cfg.tagColor.withValues(alpha: 0.3), width: 1),
          ),
          child: Text(
            cfg.tagText,
            style: TextStyle(
              color: cfg.tagColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '连续打卡',
          style: TextStyle(
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.75) : const Color(0xFF78350F),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cfg.numberColorStart, cfg.numberColorEnd],
              ).createShader(bounds),
              child: Text(
                '${data.continuousDays}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 66,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '天',
              style: TextStyle(
                color: cfg.isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF78350F),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDataCard(PosterThemeConfig cfg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: cfg.cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cfg.cardBorderColor, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              title: '今天读了',
              value: '${data.todayWords} 词',
              valueColor: cfg.statHighlightColor,
              cfg: cfg,
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0x33F59E0B),
          ),
          Expanded(
            child: _buildStatItem(
              title: '掌握率',
              value: '${data.memoryRate}%',
              valueColor: cfg.statHighlightColor,
              cfg: cfg,
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0x33F59E0B),
          ),
          Expanded(
            child: _buildStatItem(
              title: '累计掌握',
              value: _formatNumber(data.totalWords),
              valueColor: cfg.isDark ? Colors.white : const Color(0xFF78350F),
              cfg: cfg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required Color valueColor,
    required PosterThemeConfig cfg,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF92400E),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteCard(PosterThemeConfig cfg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cfg.quoteBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.quoteBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cfg.quoteMain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cfg.quoteTextColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            cfg.quoteSub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cfg.quoteTextColor.withValues(alpha: 0.75),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(PosterThemeConfig cfg) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: cfg.isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0x33D97706),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 13,
                color: cfg.isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF92400E),
              ),
              const SizedBox(width: 4),
              Text(
                data.userName,
                style: TextStyle(
                  color: cfg.isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF92400E),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cfg.tagBgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '开口背单词',
              style: TextStyle(
                color: cfg.tagColor,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int num) {
    if (num < 1000) return num.toString();
    final str = num.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }
}

/// 绘制标准泡泡 Logo（大圆外轮廓 + 左上小圆点高光）
class _BubbleLogoPainter extends CustomPainter {
  final Color color;

  _BubbleLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 外圈圆环
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, radius - 1, ringPaint);

    // 左上小圆点高光
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dotCenter = Offset(size.width * 0.35, size.height * 0.35);
    canvas.drawCircle(dotCenter, 1.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _BubbleLogoPainter oldDelegate) => oldDelegate.color != color;
}
