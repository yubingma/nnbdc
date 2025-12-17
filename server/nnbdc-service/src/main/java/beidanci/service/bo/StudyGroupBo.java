package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.text.ParseException;
import java.util.Calendar;

import beidanci.api.model.StudyGroupSummary;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.StudyGroup;
import beidanci.service.po.StudyGroupPost;
import beidanci.service.po.StudyGroupPostReply;
import beidanci.service.po.StudyGroupSnapshotDaily;
import beidanci.service.po.User;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyGroupBo extends BaseBo<StudyGroup> {
    private static final Logger log = LoggerFactory.getLogger(StudyGroup.class);

    @Autowired
    StudyGroupSnapshotDailyBo studyGroupSnapshotDailyBo;

    @Autowired
    StudyGroupPostReplyBo studyGroupPostReplyBo;

    @Autowired
    StudyGroupPostBo studyGroupPostBo;

    @Autowired
    UserBo userBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<StudyGroup>() {
        });
    }

    public List<StudyGroup> findByGroupName(String groupName) {
        StudyGroup exam = new StudyGroup();
        exam.setGroupName(groupName);
        return queryAll(exam, false);
    }

    public List<StudyGroup> findAll() {
        return queryAll(null, false);
    }

    public String dismissStudyGroup(String groupID, String userId) throws IllegalAccessException {
        // 验证用户是否是小组创建者
        StudyGroup group = findById(groupID);

        if (!group.getCreator().getId().equals(userId)) {
            return "只有该组的创建者才能解散小组";
        }

        // 删除组管理员
        List<User> managers = new ArrayList<>(group.getManagers());
        for (User manager : managers) {
            exitGroup(manager, group.getId());
        }
        group.getManagers().clear();
        updateEntity(group);

        // 删除组员
        List<User> members = new ArrayList<>(group.getUsers());
        for (User member : members) {
            exitGroup(member, group.getId());
        }
        group.getUsers().clear();
        updateEntity(group);

        // 删除小组的日结记录
        for (StudyGroupSnapshotDaily snapshot : group.getSnapshotDailys()) {
            studyGroupSnapshotDailyBo.deleteEntity(snapshot);
        }
        group.getSnapshotDailys().clear();
        updateEntity(group);

        // 删除小组的帖子
        for (StudyGroupPost post : group.getStudyGroupPosts()) {
            for (StudyGroupPostReply reply : post.getStudyGroupPostReplies()) {
                studyGroupPostReplyBo.deleteEntity(reply);
            }
            post.getStudyGroupPostReplies().clear();
            studyGroupPostBo.updateEntity(post);
            studyGroupPostBo.deleteEntity(post);
        }
        group.getStudyGroupPosts().clear();
        updateEntity(group);

        // 删除组
        deleteEntity(group);

        log.info(String.format("用户[%s]解散了小组[%s]", Util.getNickNameOfUser(group.getCreator()), group.getGroupName()));
        return null;
    }

    public String exitGroup(User user, String groupID) throws IllegalArgumentException, IllegalAccessException {
        StudyGroup group = findById(groupID);

        // 创建者不允许退出小组
        if (group.getCreator().getId().equals(user.getId())) {
            return "小组的创建者不允许退出小组";
        }

        // 首先尝试把用户从管理员中删除
        group.getManagers().remove(user);

        // 然后把用户从组中删除
        group.getUsers().remove(user);
        updateEntity(group);

        return null;
    }

    /*
     * 获取今日打卡人数
     *
     * @return
     */
    public int getTodaysDakaCount(String groupId) {
        StudyGroup group = findById(groupId);
        int count = 0;
        for (User user : group.getUsers()) {
            if (userBo.getHasDakaToday(user.getId())) {
                count++;
            }
        }
        return count;
    }

    /**
     * 获取小组快照（按日期）
     */
    private StudyGroupSnapshotDaily getSnapshotOfDay(String groupId, Calendar calendar) throws ParseException {
        String sql = "SELECT * FROM study_group_snapshot_daily WHERE group_id = :groupId AND the_date = :theDate";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("groupId", groupId);
        params.addValue("theDate", Util.removeTimePart(calendar.getTime()));
        List<StudyGroupSnapshotDaily> snapshots = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(StudyGroupSnapshotDaily.class));
        return snapshots.isEmpty() ? null : snapshots.get(0);
    }

    /**
     * 获取小组摘要信息
     */
    public StudyGroupSummary getGroupSummary(StudyGroup group) throws ParseException {
        StudyGroupSummary summary = new StudyGroupSummary();

        // 小组人数
        int memberCount = group.getUsers().size();
        summary.setMemberCount(memberCount);

        // 小组游戏积分, 打卡分和打卡率
        int gameScore = 0;
        int dakaScore = 0;
        int dakaDays = 0;
        int existDays = 0;
        for (User user : group.getUsers()) {
            gameScore += user.getGameScore();
            dakaScore += user.getDakaScore();
            dakaDays += user.getDakaDayCount();
            existDays += user.getExistDays();
        }
        summary.setGameScore(gameScore);
        summary.setDakaScore(dakaScore);
        double dakaRatio = (dakaDays + 0.0) / existDays;
        summary.setDakaRatio(dakaRatio);

        // 取小组最近快照(为了获取小组排名，计算小组排名是个耗时操作，每天夜间计算，所以取到的是前一天的排名)
        Calendar calendar = Calendar.getInstance();// 当前时间
        calendar.add(Calendar.DATE, -1); // 得到昨天
        StudyGroupSnapshotDaily snapshot = getSnapshotOfDay(group.getId(), calendar);

        if (snapshot != null) {
            summary.setGroupOrder(snapshot.getOrderNo());
        } else {// 无快照，说明是新组
            summary.setGroupOrder(1000000);
        }

        // 计算一日内排名升降
        calendar = Calendar.getInstance(); // 当前时间
        calendar.add(Calendar.DATE, -2); // 得到前天
        StudyGroupSnapshotDaily snapshot2 = getSnapshotOfDay(group.getId(), calendar);
        if (snapshot2 != null && snapshot != null) {
            summary.setDayOrderRise(snapshot.getOrderNo() - snapshot2.getOrderNo());
        }

        // 获取一周前的快照
        calendar = Calendar.getInstance();// 当前时间
        calendar.add(Calendar.DATE, -8); // 得到上周
        StudyGroupSnapshotDaily snapshotAWeekAgo = getSnapshotOfDay(group.getId(), calendar);
        if (snapshot != null && snapshotAWeekAgo != null) {
            summary.setWeekOrderRise(snapshot.getOrderNo() - snapshotAWeekAgo.getOrderNo());
        }

        // 获取一月前的快照
        calendar = Calendar.getInstance();// 当前时间
        calendar.add(Calendar.DATE, -31); // 得到上个月
        StudyGroupSnapshotDaily snapshotAMonthAgo = getSnapshotOfDay(group.getId(), calendar);
        if (snapshot != null && snapshotAMonthAgo != null) {
            summary.setWeekOrderRise(snapshot.getOrderNo() - snapshotAMonthAgo.getOrderNo());
        }

        return summary;
    }
}
