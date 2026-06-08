package beidanci.service.bo;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.WordEmbedding;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.PostConstruct;

@Service
@Transactional(rollbackFor = Throwable.class)
public class WordEmbeddingBo extends BaseBo<WordEmbedding> {

    @PostConstruct
    public void init() {
        setDao(new BaseDao<WordEmbedding>() {
        });
    }
}
