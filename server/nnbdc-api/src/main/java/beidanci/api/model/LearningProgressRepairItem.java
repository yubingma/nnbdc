package beidanci.api.model;

/**
 * 「学习进度与学习记录一致性」体检里，单个词的明细与可修性判定。
 *
 * <p>管理后台据此逐词展示与逐词修复；`canRepair=false` 时 `repairBlockReason` 说明原因。
 */
public class LearningProgressRepairItem {

    /**
     * 不可修复的原因（同时给界面直接展示）
     */
    public static final String BLOCK_NOT_OVER_TRACK = "进度未超过轨道长度，可能只是同步滞后，不在服务端改动";
    public static final String BLOCK_NO_LOG_TODAY = "今天没有评分流水，没有可靠依据判断该整成几";
    public static final String BLOCK_UPDATED_TODAY = "该词的进度是今天更新过的（用户可能正在学），改动会倒退他的进度";
    public static final String BLOCK_NOT_FOUND = "找不到该用户的学习进度记录";

    private String userId;
    private String nickName;
    private String wordId;
    private String spell;

    /** 记录的今日环节进度 */
    private Integer progress;
    /** 今天的评分流水条数（修复后的目标值） */
    private Integer todayLogCount;
    /** 当前配置下轨道长度上限（取新词/复习轨道中更长的一条） */
    private Integer trackLenMax;

    private boolean canRepair;
    private String repairBlockReason;

    /** 这三个数字对不上时的一句话诊断（口径由服务端给出，客户端只展示，不再自己推断） */
    private String diagnosis;

    /**
     * 该用户最近一次上报给服务端的客户端版本号（来自 sys_error；旧版客户端未上报时为空）。
     * 这类坏数据往往集中在某一版上，按用户看版本就能判断是不是版本问题。
     */
    private String clientVersion;

    public LearningProgressRepairItem() {
    }

    public LearningProgressRepairItem(String userId, String nickName, String wordId, String spell,
            Integer progress, Integer todayLogCount, Integer trackLenMax,
            boolean canRepair, String repairBlockReason, String diagnosis, String clientVersion) {
        this.userId = userId;
        this.nickName = nickName;
        this.wordId = wordId;
        this.spell = spell;
        this.progress = progress;
        this.todayLogCount = todayLogCount;
        this.trackLenMax = trackLenMax;
        this.canRepair = canRepair;
        this.repairBlockReason = repairBlockReason;
        this.diagnosis = diagnosis;
        this.clientVersion = clientVersion;
    }

    public String getUserId() {
        return userId;
    }

    public String getNickName() {
        return nickName;
    }

    public String getWordId() {
        return wordId;
    }

    public String getSpell() {
        return spell;
    }

    public Integer getProgress() {
        return progress;
    }

    public Integer getTodayLogCount() {
        return todayLogCount;
    }

    public Integer getTrackLenMax() {
        return trackLenMax;
    }

    public boolean getCanRepair() {
        return canRepair;
    }

    public String getRepairBlockReason() {
        return repairBlockReason;
    }

    public String getDiagnosis() {
        return diagnosis;
    }

    public String getClientVersion() {
        return clientVersion;
    }
}
