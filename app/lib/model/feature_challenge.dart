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
      title: '单词详情页 AI 助教',
      question: '在单词详情页，想要向 AI 提问单词的生僻用法、辨析或例句造句，需要怎么做？',
      options: [
        '切换到顶部的「AI 助教」Tab 即可提问',
        '在「详情」Tab 底部长按屏幕',
        '切换到「形近」Tab 提问',
      ],
      correctIndex: 0,
      explanation: '单词详情页顶部包含详情、意象、形近等多个 Tab，切换到「AI 助教」Tab 即可与 AI 助手对话探讨该词。',
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
      explanation: '背单词时直接开口说出答案，无需手动点按。',
    ),
    FeatureChallenge(
      id: 'tip_pet_daily_diet',
      category: '陪伴宠物',
      title: '小宠物的每日饭量',
      question: '首页陪伴的小宠物，一天的正常饭量是几颗智慧果？',
      options: [
        '每天吃 2 颗智慧果',
        '每天吃 10 颗智慧果',
        '每周只需要吃 1 颗',
      ],
      correctIndex: 0,
      explanation: '小宠物一天吃两颗智慧果。当天完成学习会攒够 3 颗并吃掉 2 颗，第二天醒来背篓剩 1 颗。',
    ),
    FeatureChallenge(
      id: 'tip_pet_leaves_meaning',
      category: '陪伴宠物',
      title: '宠物背篓里菜叶的含义',
      question: '有时候看到小宠物的背篓里空空的只剩几片菜叶，这代表什么？',
      options: [
        '连续断更没有背单词，智慧果断供只能吃拣来的菜叶',
        '代表小宠物今天吃得太饱了',
        '代表今天已经完成背词打卡',
      ],
      correctIndex: 0,
      explanation: '几天没有背单词断更时，小宠物的智慧果会断供，背篓变空只能吃菜叶，心情也会变成委屈（sad）。',
    ),
    FeatureChallenge(
      id: 'tip_pet_moods',
      category: '陪伴宠物',
      title: '小宠物的情绪与状态',
      question: '小宠物在什么情况下会呈现最兴奋满足的「excited」情绪？',
      options: [
        '今日背词任务已打卡完成，大饱口福',
        '今天还没有开始背单词',
        '连续多天没有打开 App',
      ],
      correctIndex: 0,
      explanation: '小宠物情绪与今日进度同步：未开始时困倦（sleepy），学习中开心（happy），打卡后最兴奋（excited），断更时难过（sad）。',
    ),
    FeatureChallenge(
      id: 'tip_pet_interaction',
      category: '陪伴宠物',
      title: '点击小宠物的交互',
      question: '在「今日计划」页面轻触小宠物，它会做什么？',
      options: [
        '开口说话，解释它当前的心情与今日学习进度',
        '重置当前的背词计划',
        '自动替用户完成打卡',
      ],
      correctIndex: 0,
      explanation: '点击小宠物会展示它的专属台词，用说话的方式告诉你它现在为什么开心或委屈，以及背篓里的果子情况。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_entries',
      category: '随身听',
      title: '随身听的两个入口',
      question: '在 App 中，随身听的两个主要启动入口分别在哪里？',
      options: [
        '底栏快捷入口（或功能收纳）以及具体单词列表页右上角',
        '只能在打卡完成后由系统自动弹出',
        '在手机系统的控制中心长按音量键',
      ],
      correctIndex: 0,
      explanation: '随身听有两个入口：一是底栏常驻（或功能收纳）的全局快捷入口；二是进入任意单词列表页（如生词本、词书）后右上角的耳机图标。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_difference',
      category: '随身听',
      title: '全局续播与定向播放',
      question: '从具体单词列表页右上角打开随身听，与从底栏全局入口打开有什么区别？',
      options: [
        '词表页入口定向播放当前词表；底栏全局入口自动续播上次内容（或今日任务）',
        '词表页入口只能单曲循环，底栏全局入口只能随机播放',
        '两者功能完全一样，没有区别',
      ],
      correctIndex: 0,
      explanation: '从单词列表页右上角进入时，会直接播放当前浏览的这本词表，并记为最新数据源；底栏全局入口则用于一键续播上次收听的词表，若无记录则回落今日任务。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_bookmark_sync',
      category: '随身听',
      title: '听词与列表书签联动',
      question: '在词书列表页点击随身听听了一会儿后退出，该词书列表的书签进度会怎样？',
      options: [
        '自动同步推进到随身听刚刚听到的位置',
        '书签进度保持不变，不会发生变化',
        '书签会直接跳到词书的最后一页',
      ],
      correctIndex: 0,
      explanation: '随身听在播放过程中会持续推进书签进度，退出返回词表时，列表会自动滚动并同步到随身听停留的最新位置。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_scenes',
      category: '随身听',
      title: '随身听背景环境音',
      question: '在随身听听词时，可以在哪里开启下雨声或夏夜虫鸣等自然白噪音？',
      options: [
        '在随身听播放页直接切换场景伴读音',
        '必须在手机系统设置的声音选项中开启',
        '在个人中心的通知设置中开启',
      ],
      correctIndex: 0,
      explanation: '随身听内置了雨声、虫鸣等自然环境音，支持熄屏后台播放，可边听环境音边磨耳朵。',
    ),
    FeatureChallenge(
      id: 'tip_walkman_pure_whitenoise',
      category: '随身听',
      title: '纯净助眠白噪音',
      question: '如果想把随身听当作纯粹的助眠白噪音工具（只听雨声或虫鸣，不读单词），该如何设置？',
      options: [
        '开启自然场景并将「发音」栏中的各项（英文、释义等）全部取消勾选',
        '把手机系统的媒体音量调至静音',
        '在手机系统设置中关闭后台刷新权限',
      ],
      correctIndex: 0,
      explanation: '随身听的环境音与单词发音是独立通道。在设置中选好自然场景（如闲时听雨、夏夜虫鸣）后，把发音栏的各项全部取消勾选，就能得到纯净的助眠白噪音，且支持熄屏后台持续播放。',
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
      id: 'tip_meaning_frequency_dot',
      category: '功能技巧',
      title: '释义末尾圆圈的作用',
      question: '多义词的每个释义末尾带有大小不同的小圆圈，这代表什么？',
      options: [
        '代表该释义在真实语料中的常用度/出现频次，圆圈越大表示越常用',
        '代表用户自己对该释义的掌握熟练度',
        '点击小圆圈可以隐藏或删除该释义',
      ],
      correctIndex: 0,
      explanation: '小圆圈代表该释义的常用度。圆圈越大越明显，表示在真实语境中使用频率越高；圆圈越小则表示越次要或生僻，方便背词时优先抓住核心高频义项。',
    ),
    FeatureChallenge(
      id: 'tip_learning_pipeline',
      category: '学习规划',
      title: '自定义背词流程（学习轨道）',
      question: '如果想自定义背单词的具体步骤（例如增加英汉或汉英测评、关闭例句环节、调整答对/答错后的巩固流程），应该在哪里操作？',
      options: [
        '在「今日计划」页面展开「学习轨道」，点击「编辑」拖拽调整环节',
        '在「我」页面的账号与安全设置中修改',
        '只能在打卡完成后由系统自动调整',
      ],
      correctIndex: 0,
      explanation: '在首页「今日计划」卡片中点击「学习轨道」，再点击下方的「编辑」，即可进入步骤编排态：可自由将底部的步骤卡片拖入测评、答对或答错分支中，定制适合自己的背词路径。',
    ),
    FeatureChallenge(
      id: 'tip_accent_switch',
      category: '功能技巧',
      title: '切换英音与美音',
      question: '学习单词或查看词条时，想要切换英音（UK）与美音（US），支持哪些快捷方式？',
      options: [
        '直接点击背词页或详情页音标旁的「英/美」角标，也可在「我」页面中修改',
        '只能在打卡完成后重置发音偏好',
        '必须通过修改手机系统的系统语言来切换',
      ],
      correctIndex: 0,
      explanation: '发音支持多处便捷切换：在背词页面或单词详情页，轻点音标旁边的「英/美」小角标即可直接就地切换；也可以在「我」-「设置与工具」的「发音口音」或背词设置菜单中统一切换。',
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
