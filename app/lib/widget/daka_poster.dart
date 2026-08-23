import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';

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

/// 4 大主流标杆海报范式
enum PosterThemeType {
  movieCard,    // ① 电影画报 · 晨曦微光 (不背单词风：沉浸画框 + 英文金句)
  streakMedal,  // ② 自律成就 · 荣耀勋章 (墨墨/多邻国风：立体发光打卡天数勋章)
  dailyCalendar,// ③ 极简日历 · 晨读手账 (扇贝/豆瓣风：撕页日历 + 复古印章)
  soundWave,    // ④ 声波能量 · 泡泡光晕 (泡泡独家科技风：发音声波能量图谱)
}

/// 海报主题配置
class PosterThemeConfig {
  final String name;
  final Color bgGradientStart;
  final Color bgGradientEnd;
  final Color brandColor;

  const PosterThemeConfig({
    required this.name,
    required this.bgGradientStart,
    required this.bgGradientEnd,
    required this.brandColor,
  });

  static PosterThemeConfig getConfig(PosterThemeType type) {
    switch (type) {
      case PosterThemeType.movieCard:
        return const PosterThemeConfig(
          name: '电影画报 · 晨曦',
          bgGradientStart: Color(0xFF0F172A),
          bgGradientEnd: Color(0xFF030712),
          brandColor: Color(0xFF38BDF8),
        );
      case PosterThemeType.streakMedal:
        return const PosterThemeConfig(
          name: '自律成就 · 勋章',
          bgGradientStart: Color(0xFF1E1B4B),
          bgGradientEnd: Color(0xFF05050A),
          brandColor: Color(0xFFFBBF24),
        );
      case PosterThemeType.dailyCalendar:
        return const PosterThemeConfig(
          name: '极简日历 · 手账',
          bgGradientStart: Color(0xFF1E293B),
          bgGradientEnd: Color(0xFF0F172A),
          brandColor: Color(0xFFFDA4AF),
        );
      case PosterThemeType.soundWave:
        return const PosterThemeConfig(
          name: '声波能量 · 科技',
          bgGradientStart: Color(0xFF064E3B),
          bgGradientEnd: Color(0xFF021512),
          brandColor: Color(0xFF34D399),
        );
    }
  }
}

/// 打卡海报核心渲染组件
class DakaPosterWidget extends StatelessWidget {
  final PosterData data;
  final PosterThemeType themeType;
  final double width;

  const DakaPosterWidget({
    super.key,
    required this.data,
    required this.themeType,
    this.width = 270.0,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = PosterThemeConfig.getConfig(themeType);
    final height = width * (16.0 / 9.0);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cfg.bgGradientStart, cfg.bgGradientEnd],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 顶部栏 (品牌 Logo + 风格标签)
            _buildTopBar(cfg),

            // 2. 核心主视觉区 (根据 4 种风格定制)
            Expanded(
              child: Center(
                child: _buildHeroContent(cfg),
              ),
            ),

            // 3. 底部用户信息与矢量二维码
            _buildFooter(cfg),
          ],
        ),
      ),
    );
  }

  /// 顶部 Logo 栏
  Widget _buildTopBar(PosterThemeConfig cfg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        Text(
          data.dateStr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// 核心主视觉内容生成
  Widget _buildHeroContent(PosterThemeConfig cfg) {
    switch (themeType) {
      case PosterThemeType.movieCard:
        return _buildMovieHero();
      case PosterThemeType.streakMedal:
        return _buildMedalHero();
      case PosterThemeType.dailyCalendar:
        return _buildCalendarHero();
      case PosterThemeType.soundWave:
        return _buildSoundWaveHero();
    }
  }

  /// ① 电影画报风 (不背单词风：沉浸晨光画框 + 英文金句 + 超薄数据胶囊)
  Widget _buildMovieHero() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 沉浸自然摄影画框
        Container(
          width: double.infinity,
          height: 195,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E3A8A),
                Color(0xFF0284C7),
                Color(0xFFD97706),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  '🌅 DAWN · 晨光微熹',
                  style: TextStyle(
                    color: Color(0xFFBAE6FD),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '“Every word you speak brings the world a step closer.”',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '大声开口读出的每个词，都在悄悄改变你。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 超薄数据胶囊
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat('${data.continuousDays} 天', '连续自律'),
              Container(width: 1, height: 18, color: Colors.white12),
              _buildMiniStat('${data.todayWords} 词', '今日开口'),
              Container(width: 1, height: 18, color: Colors.white12),
              _buildMiniStat('${data.memoryRate}%', '记牢比例'),
            ],
          ),
        ),
      ],
    );
  }

  /// ② 荣耀勋章风 (墨墨/多邻国风：立体自律徽章)
  Widget _buildMedalHero() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 立体金属质感徽章
        Container(
          width: 125,
          height: 125,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF312E81), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            ),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.7), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 16)),
              Text(
                '${data.continuousDays}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFDE68A),
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'DAYS STREAK',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Color(0xFFFCD34D),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        const Text(
          '✨ 连续自律打卡 · 达成新里程碑',
          style: TextStyle(
            color: Color(0xFFFDE68A),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),

        // 3 宫格统计
        Row(
          children: [
            Expanded(child: _buildMedalStatCard('${data.todayWords} 词', '今日开口')),
            const SizedBox(width: 6),
            Expanded(child: _buildMedalStatCard('${data.memoryRate}%', '牢固度')),
            const SizedBox(width: 6),
            Expanded(child: _buildMedalStatCard(_formatNumber(data.totalWords), '累计掌握')),
          ],
        ),
      ],
    );
  }

  /// ③ 极简日历风 (扇贝/豆瓣风：撕历手账 + 复古印章)
  Widget _buildCalendarHero() {
    final now = DateTime.now();
    final dayStr = now.day.toString().padLeft(2, '0');
    final monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final weekNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final monthStr = '${monthNames[now.month - 1]} · ${weekNames[now.weekday % 7]}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        dayStr,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFDA4AF),
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        monthStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDA4AF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '第 ${data.continuousDays} 天',
                      style: const TextStyle(
                        color: Color(0xFFFDA4AF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 10),
              const Text(
                '“每天大声开口读 10 分钟，不知不觉就走到了很远的地方。”',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日掌握：${data.todayWords} 词',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    '正确率：${data.memoryRate}%',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFFDA4AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 右下角复古小印章
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFDA4AF).withValues(alpha: 0.6), width: 1.5),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '已开口',
                      style: TextStyle(
                        color: Color(0xFFFDA4AF),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'PASSED',
                      style: TextStyle(
                        color: Color(0xFFFDA4AF),
                        fontSize: 6.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ④ 声波能量风 (泡泡科技风：发音声波图谱 + 气泡微光)
  Widget _buildSoundWaveHero() {
    final bars = [22.0, 38.0, 52.0, 32.0, 48.0, 58.0, 40.0, 26.0];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 声波能量图谱
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: bars.map((h) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 5,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF6EE7B7), Color(0xFF059669)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF34D399).withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        const Text(
          '🔊 发音主动记忆',
          style: TextStyle(
            color: Color(0xFF6EE7B7),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '开口发声 · 调动多感官牢固记忆',
          style: TextStyle(
            color: const Color(0xFFA7F3D0).withValues(alpha: 0.8),
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 14),

        // 科技卡片
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('连续打卡', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Text('${data.continuousDays} 天', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF6EE7B7))),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('牢固度', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Text('${data.memoryRate}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF34D399))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildMedalStatCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFBBF24),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部用户信息与官方矢量二维码
  Widget _buildFooter(PosterThemeConfig cfg) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：用户信息
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 13,
                    color: cfg.brandColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.userName,
                    style: TextStyle(
                      color: cfg.brandColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '发音主动记忆 · 记得更牢',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),

          // 右侧：精致二维码与扫码提示
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '扫码体验',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '泡泡单词',
                    style: TextStyle(
                      color: cfg.brandColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Container(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: QrImageView(
                    data: Config.appDownloadUrl,
                    version: QrVersions.auto,
                    size: 28,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0F172A),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
            ],
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

/// 泡泡透明标准 Logo 矢量绘制
class _BubbleLogoPainter extends CustomPainter {
  final Color color;

  const _BubbleLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.0;

    final bubblePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bubblePaint);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, radius, borderPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final highlightCenter = Offset(
      center.dx - radius * 0.35,
      center.dy - radius * 0.35,
    );
    canvas.drawCircle(highlightCenter, radius * 0.22, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _BubbleLogoPainter oldDelegate) => oldDelegate.color != color;
}
