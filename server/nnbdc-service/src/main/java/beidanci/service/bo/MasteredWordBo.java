package beidanci.service.bo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.store.WordCache;

/**
 * 已掌握单词业务逻辑层
 * 
 * 重构后，已掌握单词不再使用独立的 mastered_word 表，
 * 而是作为一本用户词书（name='已掌握'）存储在 dict + dict_word 体系中。
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class MasteredWordBo {

    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    WordBo wordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    WordCache wordCache;

    @Autowired
    DictBo dictBo;

}
