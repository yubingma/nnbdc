package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.UpdateLog;

@Service
@Transactional(rollbackFor = Throwable.class)
public class UpdateLogBo extends BaseBo<UpdateLog> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<UpdateLog>() {
        });
    }

    public UpdateLog getLastestLog() {
        List<UpdateLog> logs = pagedQuery(null, 1, 1, "time", "desc").getRows();
        return !logs.isEmpty() ? logs.get(0) : null;
    }
}
