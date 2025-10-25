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
     * 近似的已堆积行数（用于估算剩余下落时间）。
     * 注意：这是服务端近似值，未考虑前端道具清行等情况，仅作机器人思考时间的上界估计。
     */
    private int stackRows;

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

    public void setExercise(boolean isExercise) {
        this.isExercise = isExercise;

        if (isExercise) {
            isMatchStarted = false;
        }
    }
}
