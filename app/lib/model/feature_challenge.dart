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

/// 内置题库与功能秘籍清单
class FeatureChallengeRepository {
  static const List<FeatureChallenge> allChallenges = [
    FeatureChallenge(
      id: 'tip_meaning_expand',
      category: '手势秘籍',
      title: '展开完整释义与权威例句',
      question: '在背单词学习过程中，如果想要快速查看该单词更详细的柯林斯英文解释和权威例句，应该怎么做？',
      options: [
        '轻触中文释义卡片区域',
        '双击手机音量键',
        '摇晃手机',
      ],
      correctIndex: 0,
      explanation: '在背单词页面，点击释义所在卡片区域即可展开/收起完整释义与高阶例句，单手随手点开查阅，轻巧不挡视线。',
    ),
    FeatureChallenge(
      id: 'tip_swipe_answer',
      category: '手势秘籍',
      title: '左右滑动快速判定',
      question: '在英译汉或认词环节中，除了点击底部的「认识」或「不认识」按钮，还可以用什么手势极速作答？',
      options: [
        '在屏幕上画圆圈',
        '左右轻滑单词卡片',
        '从屏幕顶部向下滑动',
      ],
      correctIndex: 1,
      explanation: '单词卡片支持左右轻滑手势盲操，向右滑动代表认识，向左滑动代表不认识，单手握持背词流畅高效。',
    ),
    FeatureChallenge(
      id: 'tip_accent_switch',
      category: '常用设置',
      title: '切换英音与美音发音',
      question: '平时习惯听英式发音（如雅思考试），在 App 中可以在哪里将全局默认发音切换为英音？',
      options: [
        '在「我」页面的「设置与工具」中点击「发音口音」',
        '只能在手机系统设置里更改语言',
        '长按音量减小键',
      ],
      correctIndex: 0,
      explanation: '在「我」页面展开「设置与工具」，点击「发音口音」即可在英音（UK）与美音（US）之间一键切换。',
    ),
    FeatureChallenge(
      id: 'tip_feed_pet',
      category: '互动陪伴',
      title: '智慧果与宠物守护兽',
      question: '每天打卡背单词和回答智慧小挑战获得的「智慧果」，有什么好玩的作用？',
      options: [
        '只能看，没有任何作用',
        '用来投喂守护兽助其进化成长，或在游戏大厅参与趣味对战',
        '只能用来更换软件图标',
      ],
      correctIndex: 1,
      explanation: '智慧果是你的学习努力成果，每天打卡后可以在完成页投喂陪伴你的守护兽，投喂达到一定次数它还会进化升级！',
    ),
    FeatureChallenge(
      id: 'tip_plan_adjust',
      category: '学习规划',
      title: '灵活调整每日学习量',
      question: '如果最近考试临近时间紧张，想调整每天计划学习的单词数量，该在哪里调整？',
      options: [
        '在「今日计划」页面轻触「今日目标」卡片即可调整',
        '必须卸载重新安装才能改',
        '只能到下个月才能调整',
      ],
      correctIndex: 0,
      explanation: '在「今日计划」主页点击居中的目标词数卡片，即可随时根据自己的作息时间自由增减每天学习量。',
    ),
    FeatureChallenge(
      id: 'tip_fsrs_review',
      category: '记忆机制',
      title: '为什么有的生词会短时间内再次出现？',
      question: '背单词过程中，有时刚学过的生词在后几题又出现了，这是为什么？',
      options: [
        'App 出现 Bug 卡顿了',
        '记忆遗忘曲线算法在临界点自动调度复习，加深记忆痕迹',
        '词库里的词太少了',
      ],
      correctIndex: 1,
      explanation: '科学的间隔记忆算法会实时跟踪你的记忆稳定性。刚答错或新学的生词处于遗忘高危期，算法会及时调度复习巩固，直到真正掌握。',
    ),
    FeatureChallenge(
      id: 'tip_import_words',
      category: '宝藏功能',
      title: '批量导入课外专属生词',
      question: '如果平时在看英文原版书或真题试卷时遇到了生词，怎样把它加入自己的背词计划？',
      options: [
        '只能在纸上抄写',
        '在书桌页面使用拍照扫描查词，或直接导入 Excel/文本生词表',
        '把手机寄给客服帮忙录入',
      ],
      correctIndex: 1,
      explanation: 'App 提供了强大的生词导入能力，支持拍照 OCR 提取生词、Excel 批量导入，轻松定制你专属的复习词表。',
    ),
    FeatureChallenge(
      id: 'tip_nav_custom',
      category: '常用设置',
      title: '底栏导航管理与极简收纳',
      question: '如果你平时很少玩游戏大厅，想让底部的导航栏更加清爽极简，应该怎么做？',
      options: [
        '在「我」页面点击「底栏导航管理」，按需收纳不需要的 Tab',
        '没有办法，底栏是不可变的',
        '每次退出 App 重新进',
      ],
      correctIndex: 0,
      explanation: '在「我」页面的「底栏导航管理」中，你可以自由勾选常驻或收纳底栏图标，打造成最符合你个人直觉的极简学习工具。',
    ),
    FeatureChallenge(
      id: 'tip_cloud_sync',
      category: '多端同步',
      title: '多设备无缝同步背词进度',
      question: '如果白天用手机背词，晚上用平板或备用机复习，怎样确保两台设备数据一致？',
      options: [
        '必须手动用数据线连电脑传文件',
        '只要登录同一个账号，系统会在每次进入和背词后自动端云增量同步',
        '平板和手机不能登录同一个账号',
      ],
      correctIndex: 1,
      explanation: 'App 内置了健壮的增量云同步服务，随时随地在任何设备背单词，联网后进度与打卡记录均会自动安全同步。',
    ),
    FeatureChallenge(
      id: 'tip_fullscreen_mode',
      category: '常用设置',
      title: '全屏沉浸模式开启心流',
      question: '背单词时如果不想被顶部系统通知、状态栏电量和时间分心，可以开启什么功能？',
      options: [
        '把手机倒过来拿',
        '在「我 -> 设置与工具」中开启「全屏模式」',
        '闭上眼睛背词',
      ],
      correctIndex: 1,
      explanation: '开启全屏模式后，顶部系统状态栏会被自动隐藏，界面呈现极致纯粹的沉浸感，更容易进入专注学习心流。',
    ),
    FeatureChallenge(
      id: 'tip_daka_rate',
      category: '记忆机制',
      title: '打卡出勤率是如何计算的？',
      question: '个人中心里展示的「打卡率」指标，其统计口径是什么？',
      options: [
        '随机生成的分数',
        '累计打卡天数 ÷ 注册至今的总天数',
        '今天的做题正确率',
      ],
      correctIndex: 1,
      explanation: '打卡率定义为从你注册第一天起到今天的真实出勤比率，真实量化你的长期自律与毅力，见证点滴坚持的蜕变。',
    ),
    FeatureChallenge(
      id: 'tip_wallpaper_theme',
      category: '常用设置',
      title: '今日计划画报与壁纸自适应',
      question: '今日计划页面的底栏图标颜色是如何与背景壁纸融合的？',
      options: [
        '固定永远是黑色',
        '系统会自动侦测壁纸明暗，暗色照片自适应白墨，亮色照片自适应深墨',
        '随机变色',
      ],
      correctIndex: 1,
      explanation: '今日计划采用画报美学设计，底栏图标能与壁纸明暗自动同进同退，并带反向柔光描边，确保在任何壁纸下都清晰通透。',
    ),
  ];
}
