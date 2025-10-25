package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.StudyGroupPost;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyGroupPostBo extends BaseBo<StudyGroupPost> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<StudyGroupPost>() {
        });
    }

    public void increaseBrowseCount(StudyGroupPost post) throws IllegalAccessException {
        post.setBrowseCount(post.getBrowseCount() + 1);
        updateEntity(post, false);
    }
}
