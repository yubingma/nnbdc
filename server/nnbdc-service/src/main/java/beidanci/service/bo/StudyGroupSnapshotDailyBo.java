package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.StudyGroupSnapshotDaily;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class StudyGroupSnapshotDailyBo extends BaseBo<StudyGroupSnapshotDaily> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<StudyGroupSnapshotDaily>() {
        });
    }
}
