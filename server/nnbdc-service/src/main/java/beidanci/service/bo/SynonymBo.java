package beidanci.service.bo;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.PostConstruct;

import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.SynonymDto;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Synonym;

@Service
@Transactional(rollbackFor = Throwable.class)
public class SynonymBo extends BaseBo<Synonym> {
        @PostConstruct
    public void init() {
        setDao(new BaseDao<Synonym>() {
        });
    }

    public List<SynonymDto> getSynonymsOfDict(String dictId) {
        // 通用词典现在是数据库中的实际记录，统一查询
        String sql = "select s.meaningItemId, s.wordId, s.createTime, s.updateTime, w.spell from synonym s left join word w on w.id=s.wordId where s.meaningItemId in (select mi.id from meaning_item mi where mi.dictId=:dictId)";
        Query<?> query = getSession().createNativeQuery(sql);
        List<?> results = query.setParameter("dictId", dictId).list();

        List<SynonymDto> synonymDtos = new ArrayList<>();
        for (Object result : results) {
            Object[] tuple = (Object[]) result;
            SynonymDto synonymDto = new SynonymDto();
            synonymDto.setMeaningItemId((String) tuple[0]);
            synonymDto.setWordId((String) tuple[1]);
            synonymDto.setCreateTime((Timestamp) tuple[2]);
            synonymDto.setUpdateTime((Timestamp) tuple[3]);
            synonymDto.setSpell((String) tuple[4]);
            synonymDtos.add(synonymDto);
        }
        return synonymDtos;
    }
}
