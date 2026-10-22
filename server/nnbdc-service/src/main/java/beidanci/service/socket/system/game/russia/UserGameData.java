package beidanci.service.socket.system.game.russia;

import beidanci.service.socket.UserCmd;

/**
 * 保存用户在游戏中的状态和数据
 *
 * @author Administrator
 */
public class UserGameData {
    public UserGameData(String userId) {
        this.userId = userId;
        lastOperationTime = System.currentTimeMillis();
        lastAnswerAtMs = lastOperationTime;
        disconnectedSinceMs = -1;
    }

    private final String userId;

    /**
     * 用户是否按下了【开始】按钮
     */
    private boolean isMatchStarted;

    /**
     * 是否是否处于练习状态
     */
    private boolean isExercise;

    /**
     * 本房间内的连续输局数（赢一局清零），见 {@link #getConsecutiveLosses()}
     */
    private int consecutiveLosses;

    /**
     * 用户或客户端最后一次下达的命令
     */
    private UserCmd lastUserCmd;

    /**
     * 记录用户最后一个操作的时间
     */
    private long lastOperationTime;

    /**
     * 用户每种道具的数量
     */
    private final int[] propsCounts = new int[2];

    /**
     * 连续答对次数
     */
    private int correctCount;

    /**
     * 本局已经作答的题目数量，用于在双方名字旁展示进度。
     */
    private int answeredCount;

    /**
     * 近似的已堆积行数（用于估算剩余下落时间）。
     * 注意：这是服务端近似值，未考虑前端道具清行等情况，仅作机器人思考时间的上界估计。
     */
    private int stackRows;

    /**
     * 服务端最后一次收到该用户答题上报的时刻（毫秒）。
     * 两次答题间隔明显超过一道题的最长下落时间，说明客户端长时间没在出题
     * （例如退到后台被挂起），服务端据此把漏掉的题按漏答补扣。
     */
    private long lastAnswerAtMs;

    /**
     * 本次断线的起点（毫秒）；-1 表示当前在线。
     */
    private long disconnectedSinceMs;

    /**
     * 本局累计断线时长（毫秒）。反复断线重连不能无限刷新宽限，所以要累计封顶。
     */
    private long totalDisconnectedMs;

    public long getLastAnswerAtMs() {
        return lastAnswerAtMs;
    }

    public void setLastAnswerAtMs(long lastAnswerAtMs) {
        this.lastAnswerAtMs = lastAnswerAtMs;
    }

    public long getDisconnectedSinceMs() {
        return disconnectedSinceMs;
    }

    public void setDisconnectedSinceMs(long disconnectedSinceMs) {
        this.disconnectedSinceMs = disconnectedSinceMs;
    }

    public long getTotalDisconnectedMs() {
        return totalDisconnectedMs;
    }

    public void setTotalDisconnectedMs(long totalDisconnectedMs) {
        this.totalDisconnectedMs = totalDisconnectedMs;
    }

    public long getLastOperationTime() {
        return lastOperationTime;
    }

    public void setLastOperationTime(long lastOperationTime) {
        this.lastOperationTime = lastOperationTime;
    }

    public String getUserId() {
        return userId;
    }

    public UserCmd getLastUserCmd() {
        return lastUserCmd;
    }

    public void setLastUserCmd(UserCmd lastUserCmd) {
        this.lastUserCmd = lastUserCmd;
    }

    public int getCorrectCount() {
        return correctCount;
    }

    public void setCorrectCount(int correctCount) {
        this.correctCount = correctCount;
    }

    public int getAnsweredCount() {
        return answeredCount;
    }

    public void setAnsweredCount(int answeredCount) {
        this.answeredCount = Math.max(0, answeredCount);
    }

    public int getStackRows() {
        return stackRows;
    }

    public void setStackRows(int stackRows) {
        this.stackRows = Math.max(0, stackRows);
    }

    public int[] getPropsCounts() {
        return propsCounts;
    }

    public boolean isMatchStarted() {
        return isMatchStarted;
    }

    public void setMatchStarted(boolean isMatchStarted) {
        this.isMatchStarted = isMatchStarted;
        if (isMatchStarted) {
            isExercise = false;
        }
    }

    public boolean isExercise() {
        return isExercise;
    }

    /**
     * 本房间内的连续输局数（赢一局清零）。
     * 机器人靠它决定"输了这么多次还要不要接着开下一局"，真人玩家不读这个值。
     */
    public int getConsecutiveLosses() {
        return consecutiveLosses;
    }

    public void setConsecutiveLosses(int consecutiveLosses) {
        this.consecutiveLosses = Math.max(0, consecutiveLosses);
    }

    public void setExercise(boolean isExercise) {
        this.isExercise = isExercise;

        if (isExercise) {
            isMatchStarted = false;
        }
    }
}
