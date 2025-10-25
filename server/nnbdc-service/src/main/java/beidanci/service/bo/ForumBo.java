package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Forum;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class ForumBo extends BaseBo<Forum> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<Forum>() {
        });
    }

    public Forum findByName(String name) {
        Forum exam = new Forum();
        exam.setName(name);
        return queryUnique(exam);
    }
}
