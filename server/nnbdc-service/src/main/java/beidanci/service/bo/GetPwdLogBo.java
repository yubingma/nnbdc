package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.GetPwdLog;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(rollbackFor = Throwable.class)
public class GetPwdLogBo extends BaseBo<GetPwdLog> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<GetPwdLog>() {
        });
    }
}
