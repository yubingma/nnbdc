package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.StudyGroupGrade;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyGroupGradeBo extends BaseBo<StudyGroupGrade> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<StudyGroupGrade>() {
        });
    }
}
