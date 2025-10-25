package beidanci.service.bo;

import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.ForumPost;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class ForumPostBo extends BaseBo<ForumPost> {
    @PostConstruct
    public void init() {
        setDao(new BaseDao<ForumPost>() {
        });
    }

    public void increaseBrowseCount(ForumPost post) throws IllegalAccessException {
        post.setBrowseCount(post.getBrowseCount() + 1);
        updateEntity(post, false);
    }
}
