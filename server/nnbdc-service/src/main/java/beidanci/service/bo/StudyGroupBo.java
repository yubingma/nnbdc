package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
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
}
