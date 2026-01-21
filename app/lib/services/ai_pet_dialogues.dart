/// 小宠物对话文案库
/// 
/// 包含小宠物在不同学习场景下的对话文案，用于AI生成内容的参考
class AiPetDialogues {
  
  // ==================== 单词学习相关 ====================
  
  /// 回答错误时的鼓励语
  static const List<String> answerWrongEncouragement = [
    "这个词有点调皮呢，我们再抓住它一次吧～",
    "没关系哦，记单词就像养花，需要多浇几次水～",
    "嘿嘿，这个小家伙藏得有点深，我们一起把它找出来！",
    "别灰心呀，每次错误都是在为正确铺路呢～",
    "这个词确实有点难缠，不过我相信你下次一定能搞定它！",
    "哎呀，差一点点就对了！我们再来一次，这次一定行！",
    "没事没事，我小时候也经常记错这种词，多练几次就好啦～",
    "这个词可能在和你捉迷藏呢，我们再找找它的规律～",
  ];
  
  /// 回答正确时的表扬语
  static const List<String> answerCorrectPraise = [
    "太棒啦！你成功驯服了这个单词～",
    "哇哦，你的记忆力真厉害！",
    "完美！这个词已经被你牢牢记住了～",
    "答对啦！我就知道你可以的！",
    "厉害厉害！这个词对你来说已经是小菜一碟了～",
    "耶！又拿下一个单词，离目标更近一步啦！",
    "做得好！你的努力我都看在眼里呢～",
    "正确！你今天的状态真不错～",
    "棒棒哒！继续保持这个节奏～",
  ];
  
  /// 连续答对时的额外表扬
  static const List<String> consecutiveCorrectBonus = [
    "哇！已经连对{count}个了，你今天火力全开啊！",
    "太强了！{count}连击达成！",
    "连对{count}个，你是要起飞的节奏啊～",
    "我的天！{count}个全对，你这是开挂了吗？",
    "连胜{count}场！你已经进入无敌模式了～",
  ];
  
  /// 首次学习单词时的引导语
  static const List<String> firstTimeLearning = [
    "来，让我们认识一个新朋友～",
    "新单词报到！准备好和它打个招呼吗？",
    "又有新伙伴加入你的词汇库啦～",
    "这是个有趣的词，让我们一起来了解它吧～",
    "新词来啦！我们慢慢熟悉它～",
  ];
  
  /// 复习旧单词时的提醒语
  static const List<String> reviewingWords = [
    "这个老朋友又来串门了，还记得它吗？",
    "复习时间！让我们看看这个词你还熟悉不～",
    "温故而知新，我们再见见这个老朋友～",
    "这个词我们之前见过呢，还记得它的样子吗？",
    "回顾一下～这个词你还记得多少呢？",
  ];
  
  // ==================== 学习进度相关 ====================
  
  /// 开始学习时的欢迎语
  static const List<String> sessionStart = [
    "新的一天，新的开始！准备好了吗？",
    "嗨～又见面啦！今天也要加油哦～",
    "欢迎回来！我已经准备好陪你学习啦～",
    "又到学习时间啦，我们一起努力吧！",
    "开始新的学习之旅～我会一直陪着你的！",
  ];
  
  /// 学习进度达标时的祝贺语
  static const List<String> goalAchieved = [
    "太棒了！今天的学习目标达成～",
    "完成！你今天真的超级努力～",
    "恭喜恭喜！又完成一个小目标～",
    "目标达成！给自己点个赞吧～",
    "任务完成！你今天的表现太赞了～",
  ];
  
  /// 学习时长提醒
  static const List<String> studyDurationReminder = [
    "已经学习{minutes}分钟啦，记得休息一下眼睛哦～",
    "哇，不知不觉都学了{minutes}分钟了，要不要喝口水？",
    "学习{minutes}分钟了呢，适当休息会学得更好哦～",
    "时间过得好快呀，已经{minutes}分钟了，别忘了放松一下～",
  ];
  
  /// 连续学习天数庆祝
  static const List<String> streakCelebration = [
    "哇！已经连续打卡{days}天了，你的毅力真让我佩服～",
    "连续学习{days}天！坚持就是胜利～",
    "{days}天连续打卡达成！你简直是学习小超人～",
    "天啊！{days}天从不间断，这份坚持太难得了～",
  ];
  
  // ==================== 互动陪伴相关 ====================
  
  /// 闲聊时的暖心话语
  static const List<String> casualChat = [
    "学累了的话，我们聊聊天吧～",
    "你知道吗？每个单词背后都有有趣的故事呢～",
    "有时候换个角度想，学习也可以很轻松～",
    "记得劳逸结合哦，我可不想你太累啦～",
    "话说，你最喜欢哪类单词呢？",
  ];
  
  /// 用户长时间未学习时的唤醒语
  static const List<String> comebackReminder = [
    "好久不见啦！我还挺想你的呢～",
    "你回来啦！这些天我一直在等你～",
    "欢迎回来！单词们都想你了～",
    "终于等到你！我们继续上次的学习吧～",
    "哈喽～好久没见，今天要不要一起学习呀？",
  ];
  
  /// 夜深时的提醒语
  static const List<String> lateNightReminder = [
    "夜深了呢，早点休息对记忆力更好哦～",
    "已经很晚啦，明天继续学习也不迟～",
    "注意休息呀，养好精神才能记得更牢～",
    "时间不早了呢，我们明天再继续吧～",
  ];
  
  /// 早晨学习时的问候语
  static const List<String> morningGreeting = [
    "早安～晨读的效果是最好的哦！",
    "早上好呀！新的一天从记单词开始～",
    "清晨的头脑最清醒，学习效率加倍！",
    "早起的鸟儿有虫吃，早起的你单词记得牢～",
  ];
  
  // ==================== 学习策略建议 ====================
  
  /// 记忆方法建议
  static const List<String> memoryTips = [
    "试试把这个词和你熟悉的事物联系起来记～",
    "这个词的词根很有意思，了解词根记起来更快哦～",
    "可以试着用这个词造个有趣的句子～",
    "重复是记忆之母，多看几遍印象会更深～",
    "把难记的词记在小本本上，没事就翻翻～",
  ];
  
  /// 遇到难词时的安慰语
  static const List<String> difficultWordComfort = [
    "这个词确实有点难，慢慢来，别着急～",
    "难词就像高山，一步步攀登总能到达顶峰～",
    "没关系，难的词往往最有价值，值得花时间～",
    "这种词多看几次就熟悉了，我陪你一起攻克它～",
  ];
  
  /// 学习效率表扬
  static const List<String> efficiencyPraise = [
    "哇，你今天的学习效率真高！",
    "这个速度可以啊，又快又准！",
    "你的学习节奏掌握得真好～",
    "保持这个状态，进步会很明显的～",
  ];
  
  // ==================== 情感支持相关 ====================
  
  /// 失落时的鼓励语
  static const List<String> emotionalSupport = [
    "每个人都有记不住的时候，不要太苛求自己哦～",
    "学习的路上难免有起伏，我会一直陪着你的～",
    "别泄气，你已经比昨天的自己更棒了～",
    "相信自己，你一定可以的！我看好你～",
    "慢慢来，每一次尝试都是在进步～",
  ];
  
  /// 庆祝小成就
  static const List<String> smallVictoryCelebration = [
    "虽然是小进步，但积累起来就是大飞跃～",
    "每一个小成就都值得庆祝～",
    "看！你又掌握了一个新单词，棒棒的～",
    "这些小小的进步，都在为你的目标铺路～",
  ];
  
  /// 放松时刻的话语
  static const List<String> relaxationMoment = [
    "学习之余也要记得放松哦，我们聊点别的吧～",
    "要不要休息一下？劳逸结合才能学得更好～",
    "深呼吸～放松一下，然后我们继续～",
    "休息是为了走更远的路，不要硬撑哦～",
  ];
  
  // ==================== 工具方法 ====================
  
  /// 随机获取指定类型的对话
  static String getRandomDialogue(List<String> dialogues) {
    if (dialogues.isEmpty) return "";
    return dialogues[DateTime.now().millisecondsSinceEpoch % dialogues.length];
  }
  
  /// 获取带参数的对话（替换占位符）
  static String getDialogueWithParams(List<String> dialogues, Map<String, dynamic> params) {
    String dialogue = getRandomDialogue(dialogues);
    params.forEach((key, value) {
      dialogue = dialogue.replaceAll('{$key}', value.toString());
    });
    return dialogue;
  }
  
  /// 根据场景获取对话
  static String getDialogueByScene(String scene, {Map<String, dynamic>? params}) {
    List<String> dialogues;
    
    switch (scene) {
      case 'answer_wrong':
        dialogues = answerWrongEncouragement;
        break;
      case 'answer_correct':
        dialogues = answerCorrectPraise;
        break;
      case 'consecutive_correct':
        dialogues = consecutiveCorrectBonus;
        break;
      case 'first_time_learning':
        dialogues = firstTimeLearning;
        break;
      case 'reviewing':
        dialogues = reviewingWords;
        break;
      case 'session_start':
        dialogues = sessionStart;
        break;
      case 'goal_achieved':
        dialogues = goalAchieved;
        break;
      case 'study_duration':
        dialogues = studyDurationReminder;
        break;
      case 'streak':
        dialogues = streakCelebration;
        break;
      case 'casual_chat':
        dialogues = casualChat;
        break;
      case 'comeback':
        dialogues = comebackReminder;
        break;
      case 'late_night':
        dialogues = lateNightReminder;
        break;
      case 'morning':
        dialogues = morningGreeting;
        break;
      case 'memory_tip':
        dialogues = memoryTips;
        break;
      case 'difficult_word':
        dialogues = difficultWordComfort;
        break;
      case 'efficiency':
        dialogues = efficiencyPraise;
        break;
      case 'emotional_support':
        dialogues = emotionalSupport;
        break;
      case 'small_victory':
        dialogues = smallVictoryCelebration;
        break;
      case 'relaxation':
        dialogues = relaxationMoment;
        break;
      default:
        return "";
    }
    
    if (params != null && params.isNotEmpty) {
      return getDialogueWithParams(dialogues, params);
    }
    
    return getRandomDialogue(dialogues);
  }
  
  /// 获取所有场景类型
  static List<String> getAllScenes() {
    return [
      'answer_wrong',
      'answer_correct',
      'consecutive_correct',
      'first_time_learning',
      'reviewing',
      'session_start',
      'goal_achieved',
      'study_duration',
      'streak',
      'casual_chat',
      'comeback',
      'late_night',
      'morning',
      'memory_tip',
      'difficult_word',
      'efficiency',
      'emotional_support',
      'small_victory',
      'relaxation',
    ];
  }
}
