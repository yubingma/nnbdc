package beidanci.service.util;


import java.util.Collection;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import beidanci.service.bo.UserBo;
import beidanci.service.po.Level;
import beidanci.service.po.User;
import beidanci.util.Utils;

/**
 * 计算用户的排名<br>
 * 积分为零的用户不计入排名
 *
 * @author Administrator
 */
@Component
public class UserSorter implements InitializingBean {

    private boolean initialized;

    @Autowired
    UserBo userBo;


    private static final Logger log = LoggerFactory.getLogger(UserSorter.class);

    private final Map<String, UserScoreRecord> userOrders = new ConcurrentHashMap<>();

    /**
     * 获取指定用户的总积分排名
     *
     * @param userName
     * @return 用户总积分排名，如果没有该用户排名记录（用户积分为零），返回-1
     */
    public int getOrderOfUser(String userName) {
        if (!userOrders.containsKey(userName)) {
            return -1;
        }
        return userOrders.get(userName).getOrder();
    }

    /**
     * 从数据库读取用户信息对排名信息进行初始化
     */
    public void init() {
        try {
            long startTime = System.currentTimeMillis();
            log.info("正在初始化用户排序器...");
            List<User> users = userBo.findUsersTotalScoreMoreThan(0, false);

            // 将用户加入到保存排序结果的哈西表，稍后对此哈希表进行排序
            userOrders.clear();
            for (User user : users) {
                userOrders.put(user.getUserName(), new UserScoreRecord(user));
            }

            sort();

            long endTime = System.currentTimeMillis();
            log.info(String.format("用户排序器初始化完毕！用户数(%d), 耗时%dms", users.size(), endTime - startTime));
        } catch (Exception e) {
            log.error("用户排序器初始化失败", e);
            throw new RuntimeException("用户排序器初始化失败", e);
        }
    }

    private void sort() {
        long startTime = System.currentTimeMillis();
        List<UserScoreRecord> userSortRecords = new LinkedList<>(userOrders.values());

        // 对用户列表进行排序
        Collections.sort(userSortRecords, (UserScoreRecord o1, UserScoreRecord o2) -> o2.getTotalScore() - o1.getTotalScore());

        // 保存排序结果到哈希表，以加快查询速度
        userOrders.clear();
        for (int i = 0; i < userSortRecords.size(); i++) {
            UserScoreRecord userScoreRecord = userSortRecords.get(i);
            userScoreRecord.setOrder(i + 1);
            userOrders.put(userScoreRecord.getUserName(), userScoreRecord);
        }

        long endTime = System.currentTimeMillis();
        log.info(String.format("对用户积分进行排名，耗时:%dms", endTime - startTime));
    }

    public void onUserChanged(List<User> changedUsers) {
        for (User user : changedUsers) {
            userOrders.put(user.getUserName(), new UserScoreRecord(user));
        }
        sort();
    }

    @Override
    public void afterPropertiesSet() throws Exception {
        if (!initialized) {
            init();
            initialized = true;
        }
    }

    public boolean isInitialized() {
        return initialized;
    }

    public class UserScoreRecord {
        String userId;
        String userName;

        /**
         * 总积分
         */
        int score;

        // 总积分排名
        int order;

        // 打卡率
        double dakaRatio;

        // 打卡天数
        int dakaDayCount;

        String displayNickName;

        Level level;

        public int getMaxContinuousDakaDayCount() {
            return maxContinuousDakaDayCount;
        }

        public int getContinuousDakaDayCount() {
            return continuousDakaDayCount;
        }

        public int getMasteredWordCount() {
            return masteredWordCount;
        }

        /**
         * 最大连续打卡天数
         */
        int maxContinuousDakaDayCount;

        /**
         * 当前连续打卡天数
         */
        int continuousDakaDayCount;

        /**
         * 已掌握单词数
         */
        int masteredWordCount;

        /**
         * 最近打卡日期是否是今天或昨天
         */
        public boolean getIsLastDakaInTodayOrYesterday() {
            return Utils.getDifferenceDays(lastDakaDate, new Date()) <= 1;
        }

        public Date getLastDakaDate() {
            return lastDakaDate;
        }

        /**
         * 最近打卡日期
         */
        Date lastDakaDate;

        public UserScoreRecord(User user) {
            super();
            this.userId = user.getId();
            this.userName = user.getUserName();
            this.score = user.getTotalScore();
            this.dakaDayCount = user.getDakaDayCount();
            this.dakaRatio = user.getDakaRatio();
            this.displayNickName = user.getDisplayNickName();
            this.level = userBo.getUserLevel(user);
            this.maxContinuousDakaDayCount = user.getMaxContinuousDakaDayCount();
            this.continuousDakaDayCount = user.getContinuousDakaDayCount();
            this.masteredWordCount = user.getMasteredWordsCount();
            this.lastDakaDate = user.getLastDakaDate();
            this.order = -1;
        }

        public String getUserName() {
            return userName;
        }

        public int getTotalScore() {
            return score;
        }

        public int getOrder() {
            return order;
        }

        public void setOrder(int order) {
            this.order = order;
        }

        public int getScore() {
            return score;
        }

        public double getDakaRatio() {
            return dakaRatio;
        }

        public int getDakaDayCount() {
            return dakaDayCount;
        }

        public String getDisplayNickName() {
            return displayNickName;
        }

        public Level getLevel() {
            return level;
        }

        public String getUserId() {
            return userId;
        }

        public void setUserId(String userId) {
            this.userId = userId;
        }
    }

    /**
     * 获取所有用户的积分记录，不包括积分为0的用户
     *
     * @return
     */
    public Collection<UserScoreRecord> getUserScoreRecords() {
        return userOrders.values();
    }
}
