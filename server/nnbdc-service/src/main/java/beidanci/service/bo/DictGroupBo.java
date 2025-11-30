package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.DictGroup;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictGroupBo extends BaseBo<DictGroup> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<DictGroup>() {
        });
    }

    // 获取所有单词书分组
    public List<DictGroup> getAllDictGroups() {
        String sql = "SELECT * FROM dict_group ORDER BY displayIndex ASC";
        return namedParameterJdbcTemplate.query(sql, 
            new beidanci.service.dao.EntityRowMapper<>(DictGroup.class));
    }

}
