import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BadgeSvgAssets {
  /// 16 枚核心勋章元数据配置池 (自包含、离线优先)
  static const List<Map<String, dynamic>> allBadgeDefinitions = [
    // 1. 恒心打卡
    {'code': 'STREAK_3', 'name': '萌芽初醒', 'category': 'HABIT', 'tier': 'BRONZE', 'isStackable': false, 'conditionType': 'STREAK_DAYS', 'targetValue': 3, 'rewardBubbles': 50, 'description': '千里之行始于足下，连续背单词 3 天'},
    {'code': 'STREAK_21', 'name': '习惯微光', 'category': 'HABIT', 'tier': 'SILVER', 'isStackable': false, 'conditionType': 'STREAK_DAYS', 'targetValue': 21, 'rewardBubbles': 150, 'description': '21天习惯养成，让自律成为你的第二天性'},
    {'code': 'STREAK_100', 'name': '百日筑基', 'category': 'HABIT', 'tier': 'GOLD', 'isStackable': false, 'conditionType': 'STREAK_DAYS', 'targetValue': 100, 'rewardBubbles': 500, 'description': '风雨无阻连续打卡100天，意志如磐石'},
    {'code': 'STREAK_365', 'name': '星火长明', 'category': 'HABIT', 'tier': 'LEGENDARY', 'isStackable': false, 'conditionType': 'STREAK_DAYS', 'targetValue': 365, 'rewardBubbles': 2000, 'description': '整整一年的坚持，足以重塑一个人的人生'},

    // 2. 博学词汇
    {'code': 'VOCAB_100', 'name': '破冰启航', 'category': 'VOCAB', 'tier': 'BRONZE', 'isStackable': false, 'conditionType': 'MASTERED_WORDS', 'targetValue': 100, 'rewardBubbles': 60, 'description': '成功掌握前 100 个词，跨过背词起跑线'},
    {'code': 'VOCAB_1000', 'name': '千词过海', 'category': 'VOCAB', 'tier': 'SILVER', 'isStackable': false, 'conditionType': 'MASTERED_WORDS', 'targetValue': 1000, 'rewardBubbles': 200, 'description': '掌握千词，日常简单英文交流与阅读畅通无阻'},
    {'code': 'VOCAB_5000', 'name': '词海踏浪', 'category': 'VOCAB', 'tier': 'GOLD', 'isStackable': false, 'conditionType': 'MASTERED_WORDS', 'targetValue': 5000, 'rewardBubbles': 800, 'description': '掌握五千词，四六级/考研英语词汇轻松驾驭'},
    {'code': 'VOCAB_FINISH_BOOK', 'name': '全书通关斩', 'category': 'VOCAB', 'tier': 'LEGENDARY', 'isStackable': false, 'conditionType': 'FINISH_BOOK', 'targetValue': 1, 'rewardBubbles': 1500, 'description': '将一整本词书从头背到尾并全部掌握，无懈可击'},

    // 3. 精进学霸 (可重复累加 ×N)
    {'code': 'PERFECT_SCORE', 'name': '百发百中', 'category': 'MASTERY', 'tier': 'BRONZE', 'isStackable': true, 'conditionType': 'PERFECT_SCORE', 'targetValue': 1, 'rewardBubbles': 20, 'description': '单次复习或测验100%全对，每次达成均可重复累加'},
    {'code': 'EASY_FLOW', 'name': '极速心流', 'category': 'MASTERY', 'tier': 'SILVER', 'isStackable': true, 'conditionType': 'EASY_STREAK', 'targetValue': 30, 'rewardBubbles': 30, 'description': '单次背词连续 30 词测评判定为「轻松」，行云流水'},
    {'code': 'DAWN_LEARN', 'name': '破晓之翼', 'category': 'MASTERY', 'tier': 'GOLD', 'isStackable': true, 'conditionType': 'DAWN_CHECKIN', 'targetValue': 1, 'rewardBubbles': 30, 'description': '早晨 6:00 ~ 7:30 间完成背词打卡，见证清晨自律'},
    {'code': 'NIGHT_LEARN', 'name': '夜行学者', 'category': 'MASTERY', 'tier': 'GOLD', 'isStackable': true, 'conditionType': 'NIGHT_CHECKIN', 'targetValue': 1, 'rewardBubbles': 30, 'description': '深夜 23:00 后自律复习，万籁俱寂唯有求知欲'},

    // 4. 共鸣探索
    {'code': 'INVITE_FRIEND', 'name': '布道同行', 'category': 'SOCIAL', 'tier': 'BRONZE', 'isStackable': false, 'conditionType': 'INVITE_FRIEND', 'targetValue': 1, 'rewardBubbles': 100, 'description': '一人行速，二人行远。分享知识的光芒'},
    {'code': 'GROUP_CHECKIN', 'name': '并肩同行', 'category': 'SOCIAL', 'tier': 'SILVER', 'isStackable': false, 'conditionType': 'GROUP_CHECKIN', 'targetValue': 20, 'rewardBubbles': 250, 'description': '在学习小组/班级中与同伴共同自律打卡满 20 次'},
    {'code': 'RANK_TOP3', 'name': '登顶时刻', 'category': 'SOCIAL', 'tier': 'GOLD', 'isStackable': false, 'conditionType': 'RANK_TOP3', 'targetValue': 1, 'rewardBubbles': 600, 'description': '登上所在班级或全站周背词排行榜 TOP 3'},
    {'code': 'AI_ORACLE', 'name': 'AI 智囊伙伴', 'category': 'SOCIAL', 'tier': 'LEGENDARY', 'isStackable': false, 'conditionType': 'AI_ASSIST', 'targetValue': 100, 'rewardBubbles': 1000, 'description': '拥抱 AI 时代学习方式，人机协同背诵词汇'},
  ];

  /// 全局高保真渐变与材质滤镜定义池 (与 HTML 方案 100% 对齐)
  static const String _globalDefs = '''
  <defs>
    <!-- 青铜/红铜金属渐变 (古典红铜/赤铜质感) -->
    <linearGradient id="bronzeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFC2A8"/>
      <stop offset="35%" stop-color="#E07A5F"/>
      <stop offset="70%" stop-color="#C25E3E"/>
      <stop offset="100%" stop-color="#5E2010"/>
    </linearGradient>
    <linearGradient id="bronzeInner" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#3A170C"/>
      <stop offset="100%" stop-color="#1A0702"/>
    </linearGradient>

    <!-- 白银金属渐变 (皓月清辉质感) -->
    <linearGradient id="silverGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="50%" stop-color="#94A3B8"/>
      <stop offset="100%" stop-color="#334155"/>
    </linearGradient>
    <linearGradient id="silverInner" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#1E293B"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>

    <!-- 黄金金属渐变 (璀璨纯正金黄色) -->
    <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFBEB"/>
      <stop offset="25%" stop-color="#FEF08A"/>
      <stop offset="60%" stop-color="#FBBF24"/>
      <stop offset="85%" stop-color="#F59E0B"/>
      <stop offset="100%" stop-color="#92400E"/>
    </linearGradient>
    <linearGradient id="goldInner" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#382103"/>
      <stop offset="100%" stop-color="#170D01"/>
    </linearGradient>

    <!-- 传说幻彩渐变 (极光紫粉晶彩) -->
    <linearGradient id="legendGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#F472B6"/>
      <stop offset="50%" stop-color="#A855F7"/>
      <stop offset="100%" stop-color="#3B82F6"/>
    </linearGradient>
    <linearGradient id="legendInner" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#2E1065"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>

    <!-- 翡翠光渐变 -->
    <linearGradient id="emeraldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#6EE7B7"/>
      <stop offset="100%" stop-color="#059669"/>
    </linearGradient>

    <!-- 烈焰红霞渐变 -->
    <linearGradient id="fireGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FCA5A5"/>
      <stop offset="50%" stop-color="#EF4444"/>
      <stop offset="100%" stop-color="#991B1B"/>
    </linearGradient>

    <!-- 极光蓝青渐变 -->
    <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#67E8F9"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>
  </defs>
''';

  /// 16 枚独创矢量勋章的核心多层 SVG 内容 (纯矢量绘制)
  static final Map<String, String> _badgeSvgMap = {
    // 1. 萌芽初醒 (STREAK_3)
    'STREAK_3': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 外环铜饰 -->
  <circle cx="50" cy="50" r="44" stroke="url(#bronzeGrad)" stroke-width="4" fill="url(#bronzeInner)"/>
  <circle cx="50" cy="50" r="37" stroke="rgba(253, 186, 116, 0.3)" stroke-width="1.5" stroke-dasharray="3 3"/>
  <!-- 晨露地脉光晕 -->
  <ellipse cx="50" cy="68" rx="22" ry="6" fill="#10B981" opacity="0.25"/>
  <!-- 破土初芽 -->
  <path d="M50 72 C50 56 46 44 32 38 C32 54 42 66 50 72 Z" fill="url(#emeraldGrad)"/>
  <path d="M49 68 C52 52 64 42 70 44 C72 58 58 68 49 68 Z" fill="#34D399"/>
  <!-- 晨露水滴 -->
  <circle cx="34" cy="38" r="3" fill="#67E8F9"/>
  <!-- 四角星辉微光 -->
  <path d="M50 18 L52 24 L58 26 L52 28 L50 34 L48 28 L42 26 L48 24 Z" fill="#FDE68A"/>
</svg>
''',

    // 2. 习惯微光 (STREAK_21)
    'STREAK_21': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 八角银菱底盾 -->
  <path d="M50 6 L62 18 L79 18 L82 35 L94 48 L82 61 L79 78 L62 80 L50 92 L38 80 L21 78 L18 61 L6 48 L18 35 L21 18 L38 18 Z" fill="url(#silverInner)" stroke="url(#silverGrad)" stroke-width="3"/>
  <!-- 能量内环 -->
  <circle cx="50" cy="49" r="28" stroke="rgba(148, 163, 184, 0.4)" stroke-width="1.5"/>
  <!-- 闪电习惯聚能符 -->
  <path d="M54 26 L38 48 L48 48 L44 72 L62 46 L50 46 Z" fill="url(#cyanGrad)"/>
  <!-- 聚能光点 -->
  <circle cx="50" cy="49" r="4" fill="#FFFFFF"/>
</svg>
''',

    // 3. 百日筑基 (STREAK_100)
    'STREAK_100': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 十二芒黄金星耀底座 -->
  <path d="M50 4 L57 16 L71 11 L74 25 L88 26 L85 40 L97 47 L89 59 L96 72 L82 77 L82 91 L68 89 L60 100 L49 93 L39 100 L32 89 L18 91 L18 77 L4 72 L11 59 L3 47 L15 40 L12 26 L26 25 L29 11 L43 16 Z" fill="url(#goldInner)" stroke="url(#goldGrad)" stroke-width="2.5"/>
  <!-- 圣盾中央纹章 -->
  <path d="M50 24 C62 24 70 30 70 46 C70 66 50 78 50 78 C50 78 30 66 30 46 C30 30 38 24 50 24 Z" fill="url(#goldGrad)"/>
  <!-- 罗马百日刻印 "100" 与日晷指针 -->
  <path d="M44 38 L44 60 M52 38 C56 38 58 43 58 49 C58 55 56 60 52 60 C48 60 48 38 52 38 Z M62 38 C66 38 68 43 68 49 C68 55 66 60 62 60 C58 60 58 38 62 38 Z" stroke="#2D1A05" stroke-width="2.5" stroke-linecap="round"/>
  <!-- 光芒闪耀 -->
  <circle cx="50" cy="24" r="3" fill="#FFFFFF"/>
</svg>
''',

    // 4. 星火长明 (STREAK_365)
    'STREAK_365': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 幻彩星轨光环 -->
  <circle cx="50" cy="50" r="46" stroke="url(#legendGrad)" stroke-width="3" stroke-dasharray="8 4"/>
  <!-- 永恒皇冠底座 -->
  <path d="M50 16 L60 32 L78 28 L72 52 L82 72 L50 86 L18 72 L28 52 L22 28 L40 32 Z" fill="url(#legendInner)" stroke="url(#legendGrad)" stroke-width="2.5"/>
  <!-- 永恒不死鸟星火 -->
  <path d="M50 30 C56 42 66 48 64 62 C62 74 50 78 50 78 C50 78 38 74 36 62 C34 48 44 42 50 30 Z" fill="url(#fireGrad)"/>
  <path d="M50 44 C53 52 58 56 56 64 C55 70 50 72 50 72 C50 72 45 70 44 64 C42 56 47 52 50 44 Z" fill="#FDE68A"/>
  <!-- 冠顶宝石 -->
  <polygon points="50,14 55,22 50,26 45,22" fill="#E879F9"/>
  <polygon points="22,26 27,33 23,37 18,33" fill="#60A5FA"/>
  <polygon points="78,26 83,33 77,37 73,33" fill="#60A5FA"/>
</svg>
''',

    // 5. 破冰启航 (VOCAB_100)
    'VOCAB_100': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 青铜罗盘圆盘 -->
  <circle cx="50" cy="50" r="44" fill="url(#bronzeInner)" stroke="url(#bronzeGrad)" stroke-width="4"/>
  <!-- 罗盘刻度星轨 -->
  <circle cx="50" cy="50" r="36" stroke="rgba(253, 186, 116, 0.4)" stroke-width="1.5" stroke-dasharray="2 4"/>
  <!-- 破浪风帆战船 -->
  <path d="M48 24 L48 64 L28 64 Z" fill="url(#bronzeGrad)"/>
  <path d="M52 20 L52 64 L74 64 Z" fill="#FED7AA"/>
  <!-- 破冰船首 -->
  <path d="M22 66 L78 66 L68 76 L32 76 Z" fill="url(#bronzeGrad)"/>
  <!-- 浪花与浮冰 -->
  <path d="M16 78 C24 74 34 82 44 78 C54 74 64 82 74 78 C80 76 86 80 88 80" stroke="#67E8F9" stroke-width="2.5" stroke-linecap="round"/>
</svg>
''',

    // 6. 千词过海 (VOCAB_1000)
    'VOCAB_1000': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 八角航海银章 -->
  <rect x="14" y="14" width="72" height="72" rx="16" transform="rotate(45 50 50)" fill="url(#silverInner)" stroke="url(#silverGrad)" stroke-width="3"/>
  <!-- 展开的魔法飞书 -->
  <path d="M50 36 C58 30 72 32 78 36 L78 68 C72 64 58 62 50 68 Z" fill="url(#cyanGrad)"/>
  <path d="M50 36 C42 30 28 32 22 36 L22 68 C28 64 42 62 50 68 Z" fill="#38BDF8"/>
  <!-- 书脊与书页光线 -->
  <line x1="50" y1="36" x2="50" y2="72" stroke="#FFFFFF" stroke-width="2"/>
  <!-- "1000" 浮空金字 -->
  <text x="50" y="56" font-size="14" font-weight="900" fill="#FFFFFF" text-anchor="middle" letter-spacing="1">1000</text>
  <!-- 翻腾的波浪 -->
  <path d="M22 76 C32 72 40 80 50 76 C60 72 68 80 78 76" stroke="url(#silverGrad)" stroke-width="2.5" stroke-linecap="round"/>
</svg>
''',

    // 7. 词海踏浪 (VOCAB_5000)
    'VOCAB_5000': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 雅典神殿金盾 -->
  <circle cx="50" cy="50" r="45" fill="url(#goldInner)" stroke="url(#goldGrad)" stroke-width="3"/>
  <!-- 桂冠枝叶左 -->
  <path d="M26 36 C24 46 26 62 38 72 M22 42 C28 44 32 40 32 40 M24 54 C30 56 34 52 34 52" stroke="#F59E0B" stroke-width="2" stroke-linecap="round"/>
  <!-- 桂冠枝叶右 -->
  <path d="M74 36 C76 46 74 62 62 72 M78 42 C72 44 68 40 68 40 M76 54 C70 56 66 52 66 52" stroke="#F59E0B" stroke-width="2" stroke-linecap="round"/>
  <!-- 智慧神殿门柱与金羽笔 -->
  <path d="M36 40 L36 66 M45 40 L45 66 M55 40 L55 66 M64 40 L64 66" stroke="url(#goldGrad)" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M32 40 L68 40 L50 26 Z" fill="url(#goldGrad)"/>
  <rect x="30" y="66" width="40" height="5" rx="2" fill="url(#goldGrad)"/>
  <!-- 5K 徽章宝石 -->
  <circle cx="50" cy="53" r="10" fill="#2D1A05" stroke="#F59E0B" stroke-width="1.5"/>
  <text x="50" y="57" font-size="10" font-weight="900" fill="#FDE68A" text-anchor="middle">5K</text>
</svg>
''',

    // 8. 全书通关斩 (VOCAB_FINISH_BOOK)
    'VOCAB_FINISH_BOOK': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 传说魔法阵 -->
  <polygon points="50,6 63,18 80,18 84,35 96,48 84,61 80,78 63,78 50,90 37,78 20,78 16,61 4,48 16,35 20,18 37,18" fill="url(#legendInner)" stroke="url(#legendGrad)" stroke-width="2.5"/>
  <!-- 厚重典籍 -->
  <rect x="28" y="28" width="44" height="52" rx="4" fill="url(#legendGrad)"/>
  <rect x="32" y="32" width="36" height="44" rx="2" fill="#1E1B4B"/>
  <!-- 斩断一切的圣剑 (贯穿整书) -->
  <path d="M50 14 L53 30 L50 78 L47 30 Z" fill="#FFFFFF"/>
  <path d="M40 26 L60 26 L50 30 Z" fill="#FDE68A"/>
  <circle cx="50" cy="20" r="3" fill="#E879F9"/>
  <!-- 通关金锁解开特效 -->
  <circle cx="50" cy="54" r="7" fill="none" stroke="#FDE68A" stroke-width="2"/>
  <path d="M47 54 L53 54" stroke="#FDE68A" stroke-width="2"/>
</svg>
''',

    // 9. 百发百中 (PERFECT_SCORE)
    'PERFECT_SCORE': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 青铜靶心底座 -->
  <circle cx="50" cy="50" r="44" fill="url(#bronzeInner)" stroke="url(#bronzeGrad)" stroke-width="3.5"/>
  <circle cx="50" cy="50" r="32" fill="none" stroke="rgba(253, 186, 116, 0.5)" stroke-width="2"/>
  <circle cx="50" cy="50" r="18" fill="none" stroke="rgba(253, 186, 116, 0.8)" stroke-width="2"/>
  <!-- 准心十字准星 -->
  <line x1="50" y1="10" x2="50" y2="90" stroke="url(#bronzeGrad)" stroke-width="1.5" stroke-dasharray="4 4"/>
  <line x1="10" y1="50" x2="90" y2="50" stroke="url(#bronzeGrad)" stroke-width="1.5" stroke-dasharray="4 4"/>
  <!-- 正中红心神箭 -->
  <circle cx="50" cy="50" r="7" fill="#EF4444"/>
  <path d="M74 26 L52 48 M74 26 L64 26 M74 26 L74 36" stroke="#FED7AA" stroke-width="3" stroke-linecap="round"/>
</svg>
''',

    // 10. 极速心流 (EASY_FLOW)
    'EASY_FLOW': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 双环超速轨道 -->
  <ellipse cx="50" cy="50" rx="42" ry="20" transform="rotate(-30 50 50)" stroke="url(#silverGrad)" stroke-width="3" fill="none"/>
  <ellipse cx="50" cy="50" rx="42" ry="20" transform="rotate(30 50 50)" stroke="url(#cyanGrad)" stroke-width="3" fill="none"/>
  <!-- 核心心流反应堆 -->
  <circle cx="50" cy="50" r="18" fill="url(#silverInner)" stroke="#38BDF8" stroke-width="2"/>
  <!-- 光速脉冲离子球 -->
  <circle cx="50" cy="50" r="10" fill="#67E8F9"/>
  <circle cx="50" cy="50" r="5" fill="#FFFFFF"/>
  <!-- 秒表光标与加速粒子 -->
  <path d="M50 38 L50 50 L58 50" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round"/>
</svg>
''',

    // 11. 破晓之翼 (DAWN_LEARN)
    'DAWN_LEARN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 黄金朝阳圆徽 -->
  <circle cx="50" cy="50" r="44" fill="url(#goldInner)" stroke="url(#goldGrad)" stroke-width="3"/>
  <!-- 破晓旭日万丈光芒 -->
  <circle cx="50" cy="62" r="22" fill="url(#fireGrad)"/>
  <path d="M50 18 L50 26 M26 30 L32 35 M74 30 L68 35 M16 50 L24 50 M84 50 L76 50" stroke="#FDE68A" stroke-width="2.5" stroke-linecap="round"/>
  <!-- 展翅高飞的雄鹰金翼 -->
  <path d="M50 48 C40 34 24 38 18 46 C28 54 38 52 50 64 C62 52 72 54 82 46 C76 38 60 34 50 48 Z" fill="url(#goldGrad)"/>
  <polygon points="50,42 53,49 47,49" fill="#FFFFFF"/>
</svg>
''',

    // 12. 夜行学者 (NIGHT_LEARN)
    'NIGHT_LEARN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 暗夜苍穹星盘 -->
  <circle cx="50" cy="50" r="44" fill="#0B0F19" stroke="url(#goldGrad)" stroke-width="3"/>
  <!-- 唯美一弯金月 -->
  <path d="M54 22 C38 22 26 36 26 52 C26 68 38 80 54 80 C44 74 38 64 38 52 C38 40 44 28 54 22 Z" fill="url(#goldGrad)"/>
  <!-- 守夜猫头鹰智慧之眼 -->
  <circle cx="64" cy="46" r="10" fill="#1E293B" stroke="#F59E0B" stroke-width="2"/>
  <circle cx="64" cy="46" r="4" fill="#FDE68A"/>
  <!-- 漫天星斗星座连线 -->
  <circle cx="48" cy="34" r="2" fill="#FFFFFF"/>
  <circle cx="68" cy="26" r="1.5" fill="#FFFFFF"/>
  <circle cx="76" cy="66" r="2" fill="#FFFFFF"/>
  <line x1="48" y1="34" x2="68" y2="26" stroke="rgba(255,255,255,0.3)" stroke-width="1"/>
</svg>
''',

    // 13. 布道同行 (INVITE_FRIEND)
    'INVITE_FRIEND': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 青铜同心圆徽 -->
  <circle cx="50" cy="50" r="44" fill="url(#bronzeInner)" stroke="url(#bronzeGrad)" stroke-width="4"/>
  <!-- 紧密相扣的双子星手印/引力桥 -->
  <circle cx="38" cy="42" r="10" fill="url(#bronzeGrad)"/>
  <circle cx="62" cy="42" r="10" fill="#FED7AA"/>
  <!-- 携手共进的身躯 -->
  <path d="M24 72 C24 58 34 56 42 58 L46 72 Z" fill="url(#bronzeGrad)"/>
  <path d="M76 72 C76 58 66 56 58 58 L54 72 Z" fill="#FED7AA"/>
  <!-- 友谊之光芒中心 -->
  <polygon points="50,44 53,51 60,52 55,57 56,64 50,60 44,64 45,57 40,52 47,51" fill="#FDE68A"/>
</svg>
''',

    // 14. 并肩同行 (GROUP_CHECKIN)
    'GROUP_CHECKIN': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 八角专注圣徽 -->
  <rect x="14" y="14" width="72" height="72" rx="14" transform="rotate(45 50 50)" fill="url(#silverInner)" stroke="url(#silverGrad)" stroke-width="3"/>
  <!-- 沉浸自律的沙漏 -->
  <path d="M34 26 L66 26 L52 48 L66 70 L34 70 L48 48 Z" fill="none" stroke="url(#silverGrad)" stroke-width="3" stroke-linejoin="round"/>
  <path d="M38 30 L62 30 L50 46 Z" fill="url(#cyanGrad)"/>
  <path d="M42 66 L58 66 L50 56 Z" fill="#67E8F9"/>
  <!-- 专注力场光环 -->
  <circle cx="50" cy="50" r="32" stroke="rgba(56, 189, 248, 0.4)" stroke-width="1.5" stroke-dasharray="3 3"/>
</svg>
''',

    // 15. 登顶时刻 (RANK_TOP3)
    'RANK_TOP3': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 十角王者圣徽 -->
  <circle cx="50" cy="50" r="45" fill="url(#goldInner)" stroke="url(#goldGrad)" stroke-width="3"/>
  <!-- 胜利月桂环 -->
  <circle cx="50" cy="50" r="36" stroke="#F59E0B" stroke-width="1.5" stroke-dasharray="4 2"/>
  <!-- 璀璨冠军奖杯 -->
  <path d="M36 30 L64 30 L58 54 C58 60 54 64 50 64 C46 64 42 60 42 54 Z" fill="url(#goldGrad)"/>
  <!-- 奖杯双耳 -->
  <path d="M36 34 C26 34 26 48 38 48 M64 34 C74 34 74 48 62 48" stroke="url(#goldGrad)" stroke-width="3" stroke-linecap="round" fill="none"/>
  <!-- 奖杯底座 -->
  <rect x="46" y="64" width="8" height="8" fill="#F59E0B"/>
  <rect x="38" y="72" width="24" height="6" rx="2" fill="url(#goldGrad)"/>
  <!-- 榜首荣耀星芒 -->
  <polygon points="50,34 52,39 58,40 54,44 55,50 50,47 45,50 46,44 42,40 48,39" fill="#FFFFFF"/>
</svg>
''',

    // 16. AI 智囊伙伴 (AI_ORACLE)
    'AI_ORACLE': '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <!-- 赛博量子多面体底座 -->
  <polygon points="50,6 88,28 88,72 50,94 12,72 12,28" fill="url(#legendInner)" stroke="url(#legendGrad)" stroke-width="3"/>
  <!-- 悬浮全息量子晶核 -->
  <polygon points="50,22 74,36 74,64 50,78 26,64 26,36" fill="url(#legendGrad)" opacity="0.6"/>
  <!-- AI 神经网络突触与眼眸 -->
  <circle cx="50" cy="50" r="10" fill="#FFFFFF"/>
  <circle cx="50" cy="50" r="5" fill="#3B82F6"/>
  <!-- 神经元辐射节点 -->
  <line x1="50" y1="50" x2="32" y2="38" stroke="#E879F9" stroke-width="2"/>
  <line x1="50" y1="50" x2="68" y2="38" stroke="#60A5FA" stroke-width="2"/>
  <line x1="50" y1="50" x2="50" y2="70" stroke="#34D399" stroke-width="2"/>
  <circle cx="32" cy="38" r="3" fill="#E879F9"/>
  <circle cx="68" cy="38" r="3" fill="#60A5FA"/>
  <circle cx="50" cy="70" r="3" fill="#34D399"/>
</svg>
''',
  };

  /// 获取对应勋章的完整高保真 SVG 字符串
  static String getSvgByCode(String? code) {
    if (code == null) return _getDefaultPlaceholder();
    final normalizedCode = code.trim().toUpperCase();
    return _badgeSvgMap[normalizedCode] ?? _getDefaultPlaceholder();
  }

  /// 渲染高质感勋章 Widget (包含锁定灰阶处理与尺寸控制)
  static Widget renderBadge({
    required String? code,
    double size = 64,
    bool isUnlocked = true,
    BoxFit fit = BoxFit.contain,
  }) {
    final svgString = getSvgByCode(code);

    Widget svgWidget = SvgPicture.string(
      svgString,
      width: size,
      height: size,
      fit: fit,
    );

    if (!isUnlocked) {
      // 未解锁状态：应用优雅的半透明和轻微暗淡
      return Opacity(
        opacity: 0.38,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0,      0,      0,      0.9, 0,
          ]),
          child: svgWidget,
        ),
      );
    }

    return svgWidget;
  }

  /// 获取品质主色
  static Color getTierColor(String? tier) {
    switch (tier?.toUpperCase()) {
      case 'BRONZE':
        return const Color(0xFFC25E3E); // 古典红铜色
      case 'SILVER':
        return const Color(0xFF94A3B8); // 皓月白银色
      case 'GOLD':
        return const Color(0xFFFBBF24); // 纯正璀璨黄金色
      case 'LEGENDARY':
        return const Color(0xFFC084FC); // 幻彩紫晶传说色
      default:
        return const Color(0xFF94A3B8);
    }
  }

  /// 获取品质径向辉光色 (用于卡片与弹窗的梦幻流光背景)
  static Color getTierGlowColor(String? tier) {
    switch (tier?.toUpperCase()) {
      case 'BRONZE':
        return const Color(0xFFE07A5F);
      case 'SILVER':
        return const Color(0xFF38BDF8);
      case 'GOLD':
        return const Color(0xFFFBBF24);
      case 'LEGENDARY':
        return const Color(0xFFA855F7);
      default:
        return const Color(0xFF64748B);
    }
  }

  /// 获取品质中文标签
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
        return '常规';
    }
  }

  /// 获取分类中文标签
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
        return '成就徽章';
    }
  }

  static String _getDefaultPlaceholder() {
    return '''
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  $_globalDefs
  <circle cx="50" cy="50" r="44" stroke="url(#silverGrad)" stroke-width="3" fill="url(#silverInner)"/>
  <circle cx="50" cy="50" r="20" fill="none" stroke="#64748B" stroke-width="2"/>
  <text x="50" y="56" font-size="20" font-weight="900" fill="#94A3B8" text-anchor="middle">?</text>
</svg>
''';
  }
}
