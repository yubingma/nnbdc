package beidanci.service.bo;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.User;
import beidanci.service.po.UserDbIssue;
import beidanci.service.util.Util;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UserDbIssueBo extends BaseBo<UserDbIssue> {

    @Autowired
    private UserBo userBo;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<UserDbIssue>() {});
    }

    public void recordIssue(String userId, String issueType, String details) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) {
            return;
        }
        UserDbIssue issue = new UserDbIssue(user, issueType, details);
        issue.setId(Util.uuid());
        createEntity(issue);
    }
}


