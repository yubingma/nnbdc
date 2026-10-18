class FeatureChallenge {
  final String id;
  final String category;
  final String title;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const FeatureChallenge({
    required this.id,
    required this.category,
    required this.title,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

/// 内置题库与功能秘籍清单（严格对应 App 现有真实代码功能与交互）
class FeatureChallengeRepository {
  static const List<FeatureChallenge> allChallenges = [
    FeatureChallenge(
      id: 'tip_ai_assistant',
      category: '宝藏功能',
      title: '单词详情内置 AI 助教答疑',
      question: '在单词详情页面中，如果对某个单词的生僻用法、近义词辨析或例句造句感到疑惑，可以通过什么方式获取深度解析？',
      options: [
        '在详情页底部的 AI 助手输入框中直接向 AI 提问',
        '只能自己去浏览器外部搜索',
        '拨打人工客服电话',
      ],
      correctIndex: 0,
      explanation: '单词详情页直接集成了 AI 助教，不仅有词根助记，还能针对词义与例句随时向 AI 提问，智能答疑解惑。',
    ),
    FeatureChallenge(
      id: 'tip_voice_asr',
      category: '核心功能',
      title: '全语音识别背词（你说，我来听）',
      question: '在英译汉或汉译英学习环节中，不想频繁低头点按屏幕时，可以通过什么方式高效答题？',
      options: [
        '摇晃手机 3 次',
        '直接开口说出中文意思或英文单词，语音识别会自动核验',
        '双击手机音量键',
      ],
      correctIndex: 1,
      explanation: 'App 内置了语音 ASR 识别答题功能，开口说出答案即可自动核验进入下一词，真正做到免点按解放双手背词。',
    ),
    FeatureChallenge(
      id: 'tip_pet_progress',
      category: '互动陪伴',
      title: '轻触小宠物，听它讲今日进度',
      question: '在「今日计划」主页底部，轻触那只背着布袋的陪伴小宠物，会触发什么有趣的交互？',
      options: [
        '它会开口说话，向你解释它背篓里的智慧果数量代表今天的背词进度',
        '它会立刻逃跑消失',
        '手机会直接关机',
      ],
      correctIndex: 0,
      explanation: '轻触小宠物它会开口和你说话，它背篓里的智慧果数量正是你今天背词进度的直观体现。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_scenes',
      category: '宝藏功能',
      title: '随身听自然白噪音沉浸伴读',
      question: '在通勤或睡前使用「随身听」模式磨耳朵时，如何让背景听感更加专注舒适？',
      options: [
        '切换「闲时听雨 / 夏夜虫鸣 / 空谷晨雾」等原生自然白噪音环境背景',
        '必须同时外放重低音摇滚乐',
        '只能无限单曲循环同一个单词',
      ],
      correctIndex: 0,
      explanation: '随身听内置了闲时听雨、夏夜虫鸣、空谷晨雾等高保真大自然白噪音与动态背景，支持熄屏后台播放，专注沉浸。',
    ),
    FeatureChallenge(
      id: 'tip_meaning_limit',
      category: '常用设置',
      title: '释义精炼过滤，快速过词更高效',
      question: '如果觉得某些多义词的冷门释义太长、影响刷词效率，可以在哪里设置只展示核心释义？',
      options: [
        '在「我 -> 设置与工具」中点击「释义展示」，选择「最多 3 条」或「只看最常用 1 条」',
        '用手指挡住屏幕下半部分',
        '无法设置，所有释义必须强制看完全部',
      ],
      correctIndex: 0,
      explanation: '在释义展示设置中，你可以自由约束通用词典的释义条数，把卡片精炼为最核心的常用义项，极速刷词更清爽。',
    ),
    FeatureChallenge(
      id: 'tip_learning_pipeline',
      category: '学习规划',
      title: '自定义新词与复习学习流水线',
      question: '如果你想调整学习环节（比如跳过例句环节，或者专门只练英译汉和拼写），该怎么定制？',
      options: [
        '必须向客服申请定制专用安装包',
        '在「今日计划」页面点击流水线，自由增删或排序新词与复习的学习步骤',
        '只能每次遇到时手动按跳过',
      ],
      correctIndex: 1,
      explanation: '今日计划支持自由定制学习流水线，可以灵活组合英译汉、汉译英、拼写等环节，完全按你的节奏个性化编排。',
    ),
    FeatureChallenge(
      id: 'tip_accent_switch',
      category: '常用设置',
      title: '一键切换英音与美音发音',
      question: '习惯备考托福美音、或者雅思英音的用户，在哪里可以一键切换全局默认发音口音？',
      options: [
        '在「我 -> 设置与工具」中点击「发音口音」进行切换',
        '只能把手机系统语言整个改为英文',
        '长按音量减小键',
      ],
      correctIndex: 0,
      explanation: '在个人中心的「设置与工具」中点击「发音口音」，即可在英音（UK）与美音（US）之间一键自由切换。',
    ),
    FeatureChallenge(
      id: 'tip_import_words',
      category: '宝藏功能',
      title: '拍照查词与 Excel 批量导词',
      question: '平时在英语真题试卷或原版书中整理的生词表，怎样快速导入 App 进行复习？',
      options: [
        '在纸上抄写后寄送给官方客服',
        '在书桌页面选择「拍照扫描」识别生词，或直接导入 Excel 单词表文件',
        '无法导入自己的生词',
      ],
      correctIndex: 1,
      explanation: '书桌页面提供了强大的自定义导词能力，拍照 OCR 提取生词或直接导入 Excel，都能一键生成专属复习词书。',
    ),
    FeatureChallenge(
      id: 'tip_fullscreen_mode',
      category: '常用设置',
      title: '全屏纯净模式开启专注心流',
      question: '背单词时如果不想被顶部系统状态栏的电量、信号和时间分心，可以开启什么功能？',
      options: [
        '在「我 -> 设置与工具」中开启「全屏模式」',
        '戴上墨镜遮挡屏幕上方',
        '用贴纸粘住手机顶部',
      ],
      correctIndex: 0,
      explanation: '开启全屏模式后，顶部系统状态栏会被自动隐藏，界面呈现无干扰的纯粹视觉，更容易专注进入学习心流。',
    ),
    FeatureChallenge(
      id: 'tip_nav_custom',
      category: '常用设置',
      title: '底栏导航管理与极简收纳',
      question: '如果你平时只专注背单词，想让底部的导航栏更加清爽只留核心图标，该怎么做？',
      options: [
        '在「我」页面点击「底栏导航管理」，按需收纳不需要的 Tab 项',
        '无法修改，底栏图标永远固定',
        '每次用完重新安装 App',
      ],
      correctIndex: 0,
      explanation: '在底栏导航管理中，你可以自由勾选常驻或收纳各个功能模块，收纳后自动放入个人中心，底栏极简透气。',
    ),
    FeatureChallenge(
      id: 'tip_feed_pet',
      category: '互动陪伴',
      title: '智慧果投喂守护兽进阶成长',
      question: '每天打卡背单词和回答智慧小挑战获得的「智慧果」，有什么好玩的作用？',
      options: [
        '只能看，没有任何作用',
        '用来在打卡完成页投喂守护兽助其升级进化，或在游戏大厅参与趣味对战',
        '只能用来更换软件图标',
      ],
      correctIndex: 1,
      explanation: '智慧果是你的学习努力回报，打卡后可以在完成页投喂守护兽，累计投喂达到一定次数守护兽还会进化成更高阶形态！',
    ),
    FeatureChallenge(
      id: 'tip_daka_rate',
      category: '记忆机制',
      title: '打卡出勤率客观真实统计口径',
      question: '个人中心里展示的「打卡率」指标，其背后的统计计算规则是什么？',
      options: [
        '系统随机给出的评分',
        '累计打卡总天数 ÷ 注册至今的总天数',
        '当天的做题正确率',
      ],
      correctIndex: 1,
      explanation: '打卡率定义为你注册以来坚持出勤的天数比例，客观真实地记录你的自律坚持轨迹，见证点滴积累的蜕变。',
    ),
  ];
}
