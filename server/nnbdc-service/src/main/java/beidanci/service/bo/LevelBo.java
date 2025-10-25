package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Level;

@Service
@Transactional(rollbackFor = Throwable.class)
public class LevelBo extends BaseBo<Level> {
    private static List<Level> levels;

        @PostConstruct
    public void init() {
        setDao(new BaseDao<Level>() {
        });
    }

    public List<Level> getLevels() {
        if (levels == null) {
            levels = new ArrayList<>();
            levels.addAll(queryAll(null, false));
        }
        return levels;
    }
}
