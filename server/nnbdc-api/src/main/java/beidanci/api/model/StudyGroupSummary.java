package beidanci.api.model;

public class StudyGroupSummary {
    private int memberCount;

    /**
     * 小组最新排名
     */
    private int groupOrder;

    /**
     * 一日排名升降
     */
    private int dayOrderRise;

    /**
     * 一周排名升降
     */
    private int weekOrderRise;

    /**
     * 一月排名升降
     */
    private int monthOrderRise;

    /**
     * 打卡率
     */
    private double dakaRatio;

    /**
     * 游戏积分
     */
    private int gameScore;

    /**
     * 打卡积分
     */
    private int dakaScore;

    public int getMemberCount() {
        return memberCount;
    }

    public int getGroupOrder() {
        return groupOrder;
    }

    public int getWeekOrderRise() {
        return weekOrderRise;
    }

    public int getMonthOrderRise() {
        return monthOrderRise;
    }

    public double getDakaRatio() {
        return dakaRatio;
    }

    public int getGameScore() {
        return gameScore;
    }

    public int getGroupScore() {
        return dakaScore + gameScore;
    }

    public void setMemberCount(int memberCount) {
        this.memberCount = memberCount;
    }

    public void setGroupOrder(int groupOrder) {
        this.groupOrder = groupOrder;
    }

    public void setWeekOrderRise(int weekOrderRise) {
        this.weekOrderRise = weekOrderRise;
    }

    public void setMonthOrderRise(int monthOrderRise) {
        this.monthOrderRise = monthOrderRise;
    }

    public void setDakaRatio(double dakaRatio) {
        this.dakaRatio = dakaRatio;
    }

    public void setGameScore(int gameScore) {
        this.gameScore = gameScore;
    }

    public int getDakaScore() {
        return dakaScore;
    }

    public void setDakaScore(int dakaScore) {
        this.dakaScore = dakaScore;
    }

    public int getDayOrderRise() {
        return dayOrderRise;
    }

    public void setDayOrderRise(int dayOrderRise) {
        this.dayOrderRise = dayOrderRise;
    }
}
