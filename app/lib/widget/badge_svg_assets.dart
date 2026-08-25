import 'package:flutter/material.dart';

/// 16 枚核心勋章的高清矢量 SVG 图鉴与样式配置
class BadgeSvgAssets {
  /// 获取勋章 SVG 代码，若无则使用兜底矢量
  static String getSvgByCode(String? code) {
    if (code == null) return _defaultSvg;
    return _svgMap[code] ?? _defaultSvg;
  }

  /// 获取品质对应主色调
  static Color getTierColor(String? tier) {
    switch (tier?.toUpperCase()) {
      case 'BRONZE':
        return const Color(0xFFC25E3E); // 古典红铜
      case 'SILVER':
        return const Color(0xFF94A3B8); // 皓月白银
      case 'GOLD':
        return const Color(0xFFFBBF24); // 纯正耀金
      case 'LEGENDARY':
        return const Color(0xFFA855F7); // 炫彩紫金
      default:
        return const Color(0xFF64748B);
    }
  }

  /// 获取品质中文名称
  static String getTierName(String? tier) {
    switch (tier?.toUpperCase()) {
      case 'BRONZE':
        return '青铜';
      case 'SILVER':
        return '白银';
      case 'GOLD':
        return '黄金';
      case 'LEGENDARY':
        return '传说';
      default:
        return '基础';
    }
  }

  /// 获取分类中文名称
  static String getCategoryName(String? category) {
    switch (category?.toUpperCase()) {
      case 'HABIT':
        return '恒心 · 打卡印记';
      case 'VOCAB':
        return '博学 · 词汇殿堂';
      case 'MASTERY':
        return '精进 · 巅峰学霸';
      case 'SOCIAL':
        return '共鸣 · 探索先锋';
      default:
        return '荣耀勋章';
    }
  }

  static const String _defaultSvg = '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="50" cy="50" r="40" stroke="#94A3B8" stroke-width="4" fill="#1E293B"/>
  <path d="M50 25 L58 41 L76 43 L62 56 L66 74 L50 65 L34 74 L38 56 L24 43 L42 41 Z" fill="#FBBF24"/>
</svg>
''';

  static final Map<String, String> _svgMap = {
    // 1. 萌芽初醒 (STREAK_3)
    'STREAK_3': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_s3_b" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E27D60"/><stop offset="100%" stop-color="#8B3A2B"/>
    </linearGradient>
    <linearGradient id="g_s3_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#4ADE80"/><stop offset="100%" stop-color="#15803D"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_s3_b)" stroke-width="4" stroke-dasharray="6 3" fill="#18151D"/>
  <circle cx="50" cy="50" r="36" fill="#241E26" stroke="#4A3428" stroke-width="2"/>
  <path d="M50 72 C50 72 44 54 44 44 C44 32 50 24 50 24 C50 24 56 32 56 44 C56 54 50 72 50 72 Z" fill="url(#g_s3_g)"/>
  <path d="M50 48 C42 45 32 46 28 52 C26 55 30 62 38 60 C46 58 49 52 50 48 Z" fill="#22C55E"/>
  <path d="M50 40 C58 37 68 38 72 44 C74 47 70 54 62 52 C54 50 51 44 50 40 Z" fill="#86EFAC"/>
  <ellipse cx="50" cy="30" rx="3" ry="5" fill="#BAF7D0"/>
</svg>
''',

    // 2. 习惯微光 (STREAK_21)
    'STREAK_21': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_s21_s" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/><stop offset="50%" stop-color="#CBD5E1"/><stop offset="100%" stop-color="#475569"/>
    </linearGradient>
  </defs>
  <polygon points="50,6 92,50 50,94 8,50" stroke="url(#g_s21_s)" stroke-width="4" fill="#0F172A"/>
  <polygon points="50,16 82,50 50,84 18,50" fill="#1E293B" stroke="#64748B" stroke-width="2"/>
  <circle cx="50" cy="50" r="16" fill="#38BDF8" opacity="0.2"/>
  <path d="M53 26 L39 48 L49 48 L45 74 L61 48 L50 48 Z" fill="#38BDF8" stroke="#FFFFFF" stroke-width="1.5"/>
</svg>
''',

    // 3. 百日筑基 (STREAK_100)
    'STREAK_100': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_s100_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFBEB"/><stop offset="50%" stop-color="#FBBF24"/><stop offset="100%" stop-color="#D97706"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_s100_g)" stroke-width="4" fill="#1E1B18"/>
  <circle cx="50" cy="50" r="38" stroke="#78350F" stroke-width="2" stroke-dasharray="3 3" fill="#2E2415"/>
  <polygon points="50,18 58,34 76,34 62,45 67,62 50,52 33,62 38,45 24,34 42,34" fill="url(#g_s100_g)" stroke="#78350F" stroke-width="1.5"/>
  <text x="50" y="78" text-anchor="middle" font-size="11" font-weight="900" fill="#FDE68A" font-family="sans-serif">100 DAYS</text>
</svg>
''',

    // 4. 星火长明 (STREAK_365)
    'STREAK_365': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_s365_p" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E879F9"/><stop offset="100%" stop-color="#7E22CE"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="45" stroke="url(#g_s365_p)" stroke-width="4" fill="#180D24"/>
  <path d="M50 16 C30 36 34 56 42 66 C42 66 38 60 40 52 C42 44 48 40 50 36 C52 40 58 44 60 52 C62 60 58 66 58 66 C66 56 70 36 50 16 Z" fill="#F43F5E"/>
  <path d="M50 32 C42 44 44 56 48 62 C48 62 46 58 47 53 C48 48 51 46 50 44 C52 46 54 48 55 53 C56 58 54 62 54 62 C58 56 60 44 50 32 Z" fill="#FBBF24"/>
  <circle cx="50" cy="74" r="5" fill="#38BDF8"/>
</svg>
''',

    // 5. 破冰启航 (VOCAB_100)
    'VOCAB_100': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_v100_b" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E27D60"/><stop offset="100%" stop-color="#8B3A2B"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_v100_b)" stroke-width="4" fill="#171C24"/>
  <circle cx="50" cy="50" r="37" fill="#1F2937" stroke="#374151" stroke-width="2"/>
  <path d="M22 68 Q50 78 78 68 L70 56 L30 56 Z" fill="url(#g_v100_b)"/>
  <path d="M48 22 L48 54 L68 54 Z" fill="#38BDF8"/>
  <path d="M44 30 L44 54 L30 54 Z" fill="#67E8F9"/>
</svg>
''',

    // 6. 千词过海 (VOCAB_1000)
    'VOCAB_1000': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_v1k_s" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/><stop offset="100%" stop-color="#475569"/>
    </linearGradient>
  </defs>
  <polygon points="50,8 88,26 88,74 50,92 12,74 12,26" stroke="url(#g_v1k_s)" stroke-width="3.5" fill="#0F172A"/>
  <path d="M50 36 C42 28 26 30 22 32 L22 64 C26 62 42 60 50 68 C58 60 74 62 78 64 L78 32 C74 30 58 28 50 36 Z" fill="#1E293B" stroke="#94A3B8" stroke-width="2"/>
  <text x="50" y="55" text-anchor="middle" font-size="13" font-weight="900" fill="#38BDF8" font-family="sans-serif">1000</text>
</svg>
''',

    // 7. 词海踏浪 (VOCAB_5000)
    'VOCAB_5000': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_v5k_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFBEB"/><stop offset="50%" stop-color="#FBBF24"/><stop offset="100%" stop-color="#D97706"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_v5k_g)" stroke-width="4" fill="#1E1B18"/>
  <circle cx="50" cy="50" r="36" fill="#2E2415" stroke="#78350F" stroke-width="2"/>
  <path d="M50 22 L66 30 L34 30 Z" fill="url(#g_v5k_g)"/>
  <rect x="36" y="32" width="5" height="26" fill="#FBBF24"/>
  <rect x="44.5" y="32" width="5" height="26" fill="#FBBF24"/>
  <rect x="53" y="32" width="5" height="26" fill="#FBBF24"/>
  <rect x="61.5" y="32" width="5" height="26" fill="#FBBF24"/>
  <text x="50" y="74" text-anchor="middle" font-size="12" font-weight="900" fill="#FDE68A" font-family="sans-serif">5000</text>
</svg>
''',

    // 8. 全书通关斩 (VOCAB_FINISH_BOOK)
    'VOCAB_FINISH_BOOK': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_vfb_p" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#F43F5E"/><stop offset="100%" stop-color="#881337"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="45" stroke="url(#g_vfb_p)" stroke-width="4" fill="#180D1B"/>
  <path d="M50 40 C42 32 26 34 20 36 L20 68 C26 66 42 64 50 72 C58 64 74 66 80 68 L80 36 C74 34 58 32 50 40 Z" fill="#2A142D" stroke="#E11D48" stroke-width="2"/>
  <path d="M50 14 L54 66 L50 74 L46 66 Z" fill="#F43F5E" stroke="#FFFFFF" stroke-width="1.5"/>
  <path d="M38 34 L62 34" stroke="#FDE047" stroke-width="3" stroke-linecap="round"/>
</svg>
''',

    // 9. 百发百中 (PERFECT_SCORE)
    'PERFECT_SCORE': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_mp_b" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E27D60"/><stop offset="100%" stop-color="#8B3A2B"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_mp_b)" stroke-width="4" fill="#1C1819"/>
  <circle cx="50" cy="50" r="32" stroke="#EF4444" stroke-width="2" fill="none" stroke-dasharray="4 2"/>
  <circle cx="50" cy="50" r="18" fill="#EF4444"/>
  <circle cx="50" cy="50" r="8" fill="#FFFFFF"/>
  <path d="M22 22 L78 78 M72 78 L78 78 L78 72" stroke="#FBBF24" stroke-width="3.5" stroke-linecap="round"/>
</svg>
''',

    // 10. 极速心流 (EASY_FLOW)
    'EASY_FLOW': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_mf_s" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/><stop offset="100%" stop-color="#475569"/>
    </linearGradient>
  </defs>
  <ellipse cx="50" cy="50" rx="42" ry="20" transform="rotate(-30 50 50)" stroke="url(#g_mf_s)" stroke-width="3" fill="none"/>
  <ellipse cx="50" cy="50" rx="42" ry="20" transform="rotate(30 50 50)" stroke="#38BDF8" stroke-width="3" fill="none"/>
  <circle cx="50" cy="50" r="18" fill="#0F172A" stroke="#38BDF8" stroke-width="2"/>
  <circle cx="50" cy="50" r="8" fill="#67E8F9"/>
  <path d="M50 40 L50 50 L57 50" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round"/>
</svg>
''',

    // 11. 破晓之翼 (DAWN_LEARN)
    'DAWN_LEARN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_md_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFBEB"/><stop offset="50%" stop-color="#FBBF24"/><stop offset="100%" stop-color="#D97706"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_md_g)" stroke-width="4" fill="#1E1912"/>
  <circle cx="50" cy="62" r="22" fill="#F59E0B"/>
  <path d="M50 26 L60 48 L40 48 Z" fill="#FBBF24"/>
  <path d="M50 46 C34 32 16 38 12 50 C24 50 38 56 46 62 Z" fill="url(#g_md_g)"/>
  <path d="M50 46 C66 32 84 38 88 50 C76 50 62 56 54 62 Z" fill="url(#g_md_g)"/>
</svg>
''',

    // 12. 夜行学者 (NIGHT_LEARN)
    'NIGHT_LEARN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_mn_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FDE047"/><stop offset="100%" stop-color="#CA8A04"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_mn_g)" stroke-width="4" fill="#0B0F19"/>
  <path d="M54 22 C38 24 26 38 28 54 C30 68 44 78 58 76 C50 72 44 60 46 48 C48 36 56 26 66 24 C62 22 58 22 54 22 Z" fill="url(#g_mn_g)"/>
  <circle cx="68" cy="46" r="5" fill="#38BDF8"/>
  <circle cx="56" cy="60" r="4" fill="#818CF8"/>
</svg>
''',

    // 13. 布道同行 (INVITE_FRIEND)
    'INVITE_FRIEND': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_si_b" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E27D60"/><stop offset="100%" stop-color="#8B3A2B"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_si_b)" stroke-width="4" fill="#1C181A"/>
  <circle cx="36" cy="42" r="12" fill="#E27D60"/>
  <circle cx="64" cy="42" r="12" fill="#38BDF8"/>
  <path d="M22 72 C22 58 50 58 50 72 Z" fill="#E27D60"/>
  <path d="M50 72 C50 58 78 58 78 72 Z" fill="#38BDF8"/>
</svg>
''',

    // 14. 并肩同行 (GROUP_CHECKIN)
    'GROUP_CHECKIN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_sg_s" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/><stop offset="100%" stop-color="#475569"/>
    </linearGradient>
  </defs>
  <polygon points="50,6 94,50 50,94 6,50" stroke="url(#g_sg_s)" stroke-width="4" fill="#0F172A"/>
  <path d="M34 28 L66 28 L56 50 L66 72 L34 72 L44 50 Z" fill="#1E293B" stroke="#38BDF8" stroke-width="2"/>
  <polygon points="45,64 55,64 50,56" fill="#38BDF8"/>
  <circle cx="50" cy="52" r="2" fill="#FFFFFF"/>
</svg>
''',

    // 15. 登顶时刻 (RANK_TOP3)
    'RANK_TOP3': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_sr_g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFBEB"/><stop offset="50%" stop-color="#FBBF24"/><stop offset="100%" stop-color="#D97706"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="44" stroke="url(#g_sr_g)" stroke-width="4" fill="#1E1B18"/>
  <path d="M32 26 L68 26 L62 56 C62 64 50 68 50 68 C50 68 38 64 38 56 Z" fill="url(#g_sr_g)"/>
  <rect x="46" y="68" width="8" height="12" fill="#FBBF24"/>
  <rect x="36" y="80" width="28" height="6" rx="2" fill="url(#g_sr_g)"/>
  <path d="M32 32 C22 34 22 46 34 48" stroke="#FBBF24" stroke-width="3" fill="none"/>
  <path d="M68 32 C78 34 78 46 66 48" stroke="#FBBF24" stroke-width="3" fill="none"/>
</svg>
''',

    // 16. AI 智囊伙伴 (AI_ORACLE)
    'AI_ORACLE': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g_sa_p" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#C084FC"/><stop offset="100%" stop-color="#6366F1"/>
    </linearGradient>
  </defs>
  <circle cx="50" cy="50" r="45" stroke="url(#g_sa_p)" stroke-width="4" fill="#120D24"/>
  <polygon points="50,18 78,34 78,66 50,82 22,66 22,34" stroke="#818CF8" stroke-width="2.5" fill="#1E1B4B"/>
  <circle cx="50" cy="50" r="14" fill="#6366F1"/>
  <circle cx="50" cy="50" r="7" fill="#A5B4FC"/>
  <path d="M50 20 L50 36 M76 35 L62 43 M76 65 L62 57 M50 80 L50 64 M24 65 L38 57 M24 35 L38 43" stroke="#C084FC" stroke-width="2"/>
</svg>
'''
  };
}
