package beidanci.service.bo;
import javax.annotation.PostConstruct;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.SysParam;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;


@Service
@Transactional(rollbackFor = Throwable.class)
public class SysParamBo extends BaseBo<SysParam> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<SysParam>() {
        });
    }
}
