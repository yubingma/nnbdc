package beidanci.api.model;

public enum Badge {
    // 1. 恒心打卡系列
    STREAK_3("萌芽初醒", "HABIT", "BRONZE", false, "STREAK_DAYS", 3, 50, "千里之行始于足下，连续背单词 3 天", 1),
    STREAK_21("习惯微光", "HABIT", "SILVER", false, "STREAK_DAYS", 21, 150, "21天习惯养成，让自律成为你的第二天性", 2),
    STREAK_100("百日筑基", "HABIT", "GOLD", false, "STREAK_DAYS", 100, 500, "风雨无阻连续打卡100天，意志如磐石", 3),
    STREAK_365("星火长明", "HABIT", "LEGENDARY", false, "STREAK_DAYS", 365, 2000, "整整一年的坚持，足以重塑一个人的人生", 4),

    // 2. 博学词汇系列
    VOCAB_100("破冰启航", "VOCAB", "BRONZE", false, "MASTERED_WORDS", 100, 60, "成功掌握前 100 个词，跨过背词起跑线", 5),
    VOCAB_1000("千词过海", "VOCAB", "SILVER", false, "MASTERED_WORDS", 1000, 200, "掌握千词，日常简单英文交流与阅读畅通无阻", 6),
    VOCAB_5000("词海踏浪", "VOCAB", "GOLD", false, "MASTERED_WORDS", 5000, 800, "掌握五千词，四六级/考研英语词汇轻松驾驭", 7),
    VOCAB_FINISH_BOOK("全书通关斩", "VOCAB", "LEGENDARY", false, "FINISH_BOOK", 1, 1500, "将一整本词书从头背到尾并全部掌握，无懈可击", 8),

    // 3. 精进学霸系列 (可累加获得)
    PERFECT_SCORE("百发百中", "MASTERY", "BRONZE", true, "PERFECT_SCORE", 1, 20, "单次复习或测验100%全对，每次达成均可重复累加", 9),
    EASY_FLOW("极速心流", "MASTERY", "SILVER", true, "EASY_STREAK", 30, 30, "单次背词连续 30 词测评判定为「轻松」，行云流水", 10),
    DAWN_LEARN("破晓之翼", "MASTERY", "GOLD", true, "DAWN_CHECKIN", 1, 30, "早晨 6:00 ~ 7:30 间完成背词打卡，见证清晨自律", 11),
    NIGHT_LEARN("夜行学者", "MASTERY", "GOLD", true, "NIGHT_CHECKIN", 1, 30, "深夜 23:00 后自律复习，万籁俱寂唯有求知欲", 12),

    // 4. 共鸣探索系列
    INVITE_FRIEND("布道同行", "SOCIAL", "BRONZE", false, "INVITE_FRIEND", 1, 100, "一人行速，二人行远。分享知识的光芒", 13),
    GROUP_CHECKIN("并肩同行", "SOCIAL", "SILVER", false, "GROUP_CHECKIN", 20, 250, "在学习小组/班级中与同伴共同自律打卡满 20 次", 14),
    RANK_TOP3("登顶时刻", "SOCIAL", "GOLD", false, "RANK_TOP3", 1, 600, "登上所在班级或全站周背词排行榜 TOP 3", 15),
    AI_ORACLE("AI 智囊伙伴", "SOCIAL", "LEGENDARY", false, "AI_ASSIST", 100, 1000, "拥抱 AI 时代学习方式，人机协同背诵词汇", 16);

    private final String displayName;
    private final String category;
    private final String tier;
    private final boolean isStackable;
    private final String conditionType;
    private final int targetValue;
    private final int rewardBubbles;
    private final String description;
    private final int displayOrder;

    Badge(String displayName, String category, String tier, boolean isStackable,
          String conditionType, int targetValue, int rewardBubbles, String description, int displayOrder) {
        this.displayName = displayName;
        this.category = category;
        this.tier = tier;
        this.isStackable = isStackable;
        this.conditionType = conditionType;
        this.targetValue = targetValue;
        this.rewardBubbles = rewardBubbles;
        this.description = description;
        this.displayOrder = displayOrder;
    }

    public String getDisplayName() {
        return displayName;
    }

    public String getCategory() {
        return category;
    }

    public String getTier() {
        return tier;
    }

    public boolean isStackable() {
        return isStackable;
    }

    public String getConditionType() {
        return conditionType;
    }

    public int getTargetValue() {
        return targetValue;
    }

    public int getRewardBubbles() {
        return rewardBubbles;
    }

    public String getDescription() {
        return description;
    }

    public int getDisplayOrder() {
        return displayOrder;
    }

    public static Badge fromCode(String code) {
        if (code == null) return null;
        for (Badge b : values()) {
            if (b.name().equalsIgnoreCase(code.trim())) {
                return b;
            }
        }
        return null;
    }
}
