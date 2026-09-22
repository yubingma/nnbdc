import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/bdc/widgets/word_core_image_card.dart';

/// 核心意象环绕布局·真机预览
///
/// 用途：线上库 word_core_image 目前还没有数据，单词详情页里看不到这张卡片。
/// 这里用 about 的真实释义按 5 / 8 / 11 条三个规模构造数据，直接在真机上验证：
///   1. 环形文字压到 8.5px 到底还能不能读
///   2. 分支变多时布局怎么退化
///   3. 超过 8 条是否按预期降级为竖排列表
class CoreImageOrbitPreviewPage extends StatelessWidget {
  const CoreImageOrbitPreviewPage({super.key});

  static const String _schema =
      'about 的核心画面是绕着某个东西的外围转。比如你围着一棵树打转，就是 about 的感觉。';

  static const List<Map<String, String>> _b5 = [
    {'pos': 'prep', 'meaning': '关于', 'relation': '围绕主题外缘关联'},
    {'pos': 'adv', 'meaning': '大约', 'relation': '在准确值周边游移'},
    {'pos': 'adv', 'meaning': '几乎', 'relation': '绕到目标快到了'},
    {'pos': 'adj', 'meaning': '活跃', 'relation': '没对准中心在外围晃'},
    {'pos': 'prep', 'meaning': '附近', 'relation': '围绕中心向外散开'},
  ];

  static const List<Map<String, String>> _b8 = [
    {'pos': 'prep', 'meaning': '关于', 'relation': '围绕主题外缘关联'},
    {'pos': 'prep', 'meaning': '附近', 'relation': '围绕中心向外散开'},
    {'pos': 'prep', 'meaning': '周围', 'relation': '环绕在四周一圈'},
    {'pos': 'prep', 'meaning': '遍布', 'relation': '铺满整个外围'},
    {'pos': 'adv', 'meaning': '大约', 'relation': '在准确值周边游移'},
    {'pos': 'adv', 'meaning': '几乎', 'relation': '绕到目标快到了'},
    {'pos': 'adv', 'meaning': '到处', 'relation': '在外围四处跑动'},
    {'pos': 'adj', 'meaning': '活跃', 'relation': '没对准中心在外围晃'},
  ];

  static const List<Map<String, String>> _b11 = [
    ..._b8,
    {'pos': 'adv', 'meaning': '四处', 'relation': '从中心向各方向散'},
    {'pos': 'adj', 'meaning': '随意', 'relation': '不落在确定位置'},
    {'pos': 'adj', 'meaning': '粗略', 'relation': '只描个大概轮廓'},
  ];

  static WordCoreImage _build(String id, List<Map<String, String>> branches) {
    return WordCoreImage(
      id: id,
      wordId: id,
      word: 'about',
      coreImage: '绕心打转',
      schemaDesc: _schema,
      topologyJson: jsonEncode({'branches': branches}),
      imageUrl: '',
      imageStatus: 'PREVIEW',
      isApplicable: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('核心意象 · 环绕布局预览')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              '线上库 word_core_image 还是空的，单词详情页里暂时看不到这张卡片，'
              '所以这里用 about 的真实释义构造三档规模，用来在真机上确认排版与字号。',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFF64748B)),
            ),
          ),
          _section('5 条分支 · 环绕形态', _b5),
          _section('8 条分支 · 环绕形态（中心图明显缩小）', _b8),
          _section('11 条分支 · 应自动降级为竖排列表', _b11),
        ],
      ),
    );
  }

  Widget _section(String title, List<Map<String, String>> branches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: WordCoreImageCard(
            item: _build('preview-${branches.length}', branches),
          ),
        ),
      ],
    );
  }
}
