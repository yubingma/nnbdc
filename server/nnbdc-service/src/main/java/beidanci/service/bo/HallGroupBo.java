package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.HallGroup;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class HallGroupBo extends BaseBo<HallGroup> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<HallGroup>() {
        });
    }
}
