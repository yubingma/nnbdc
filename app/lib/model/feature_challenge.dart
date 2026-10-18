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

/// 内置题库与功能说明清单
class FeatureChallengeRepository {
  static const List<FeatureChallenge> allChallenges = [
    FeatureChallenge(
      id: 'tip_ai_assistant',
      category: '功能技巧',
      title: '单词详情页 AI 提问',
      question: '在单词详情页，遇到不理解的词义或想看更多例句，可以在哪里向 AI 提问？',
      options: [
        '在页面底部的 AI 输入框直接输入提问',
        '长按单词标题',
        '点击右上角分享按钮',
      ],
      correctIndex: 0,
      explanation: '单词详情页底部内置了 AI 对话框，输入疑问即可获得针对该词的详细解析和造句。',
    ),
    FeatureChallenge(
      id: 'tip_voice_asr',
      category: '学习操作',
      title: '语音直接答题',
      question: '在英译汉或汉译英学习环节，除了点击屏幕选项，还可以怎样答题？',
      options: [
        '按住音量键',
        '直接开口说出答案（中文释义或英文单词）',
        '连击两次屏幕空白处',
      ],
      correctIndex: 1,
      explanation: '背单词时直接开口说出答案，语音识别核验正确后会自动切到下一题，无需手动点按。',
    ),
    FeatureChallenge(
      id: 'tip_pet_progress',
      category: '功能技巧',
      title: '小宠物与今日进度',
      question: '在「今日计划」页面点击底部的小宠物，会发生什么？',
      options: [
        '小宠物会说话，其背篓里的果子数代表今日进度',
        '切换页面主题',
        '跳转到词书选择页面',
      ],
      correctIndex: 0,
      explanation: '点击小宠物会展示它的台词，它背篓里装的智慧果数量对应你今天的背词完成进度。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_scenes',
      category: '功能技巧',
      title: '随身听背景环境音',
      question: '在随身听听词时，可以在哪里开启下雨声或夏夜虫鸣等背景声？',
      options: [
        '在随身听播放页直接切换场景（如闲时听雨、夏夜虫鸣）',
        '只能在手机系统设置里开启',
        '在个人中心的通知设置里开启',
      ],
      correctIndex: 0,
      explanation: '随身听内置了雨声、虫鸣等自然环境音，支持熄屏后台播放，可边听环境音边磨耳朵。',
    ),
    FeatureChallenge(
      id: 'tip_meaning_limit',
      category: '常用设置',
      title: '限制释义显示条数',
      question: '觉得多义词的释义太长时，在哪里可以设置只看最常用的几条释义？',
      options: [
        '在「我」-「设置与工具」中点击「释义展示」',
        '在「我」-「个人信息」中修改',
        '在词书列表页长按词书封面',
      ],
      correctIndex: 0,
      explanation: '在「我」页面的「释义展示」设置中，可选择只看最常用的 1 条、3 条或 5 条释义，减少冗余信息。',
    ),
    FeatureChallenge(
      id: 'tip_learning_pipeline',
      category: '学习规划',
      title: '调整学习环节流水线',
      question: '想要自定义背词流程（例如去掉例句环节、或专门练习拼写），该在哪里设置？',
      options: [
        '在「今日计划」页面点击学习轨迹流水线进行编辑',
        '在「我」页面的账号设置里修改',
        '只能在打卡完成后重置',
      ],
      correctIndex: 0,
      explanation: '在「今日计划」中点击新词或复习的学习轨迹，可以自由添加、删除或重新排序各个学习步骤。',
    ),
    FeatureChallenge(
      id: 'tip_accent_switch',
      category: '常用设置',
      title: '切换英音与美音',
      question: '想把全局默认发音切换为英音或美音，入口在哪里？',
      options: [
        '在「我」-「设置与工具」中点击「发音口音」',
        '修改手机系统的默认语言',
        '长按音量减小键',
      ],
      correctIndex: 0,
      explanation: '在「我」页面的「发音口音」设置中，可一键在英音（UK）与美音（US）之间切换。',
    ),
    FeatureChallenge(
      id: 'tip_import_words',
      category: '词书功能',
      title: '批量导入课外生词',
      question: '想把自己的生词批量导入 App 学习，支持哪些方式？',
      options: [
        '拍照扫描纸面单词，或直接导入 Excel 词表文件',
        '只能在搜索框一个词一个词手动查',
        '只能连接电脑用数据线传输',
      ],
      correctIndex: 0,
      explanation: '在书桌页面点击导入，支持拍照 OCR 提取生词，也支持导入标准格式的 Excel 表格。',
    ),
    FeatureChallenge(
      id: 'tip_fullscreen_mode',
      category: '常用设置',
      title: '全屏模式',
      question: '背单词时如果想隐藏屏幕顶部的状态栏（电量、时间和通知），应如何开启？',
      options: [
        '在「我」-「设置与工具」中开启「全屏模式」',
        '开启手机省电模式',
        '开启手机勿扰模式',
      ],
      correctIndex: 0,
      explanation: '开启「全屏模式」后，App 会自动隐藏系统顶部状态栏，提供更纯净的界面。',
    ),
    FeatureChallenge(
      id: 'tip_nav_custom',
      category: '常用设置',
      title: '底栏导航收纳',
      question: '如果觉得底栏图标过多，可以在哪里隐藏不需要的底栏项目？',
      options: [
        '在「我」-「设置与工具」中点击「底栏导航管理」',
        '长按底栏图标拖动到垃圾桶',
        '双击屏幕空白区域',
      ],
      correctIndex: 0,
      explanation: '在「底栏导航管理」中可以自由收纳不常用的底栏图标，收纳后的项目可以在「我」页面找到。',
    ),
    FeatureChallenge(
      id: 'tip_feed_pet',
      category: '功能技巧',
      title: '智慧果的作用',
      question: '学习和答题获得的智慧果，主要用于什么？',
      options: [
        '在打卡完成后投喂守护兽，或在游戏大厅参与对战',
        '兑换手机话费',
        '抵扣软件会员费用',
      ],
      correctIndex: 0,
      explanation: '智慧果可以在打卡页投喂守护兽（累计投喂会升级变身），也可以在游戏大厅用于排位对战。',
    ),
    FeatureChallenge(
      id: 'tip_daka_rate',
      category: '数据指标',
      title: '打卡率计算规则',
      question: '个人中心展示的「打卡率」是如何计算出来的？',
      options: [
        '累计打卡天数 ÷ 注册至今的总天数',
        '当月打卡天数 ÷ 当月总天数',
        '近 7 天背词正确率',
      ],
      correctIndex: 0,
      explanation: '打卡率等于注册至今累计打卡的总天数除以注册天数，用于反映长期的实际出勤坚持度。',
    ),
  ];
}
