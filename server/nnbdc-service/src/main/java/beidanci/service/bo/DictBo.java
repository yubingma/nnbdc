package beidanci.service.bo;
import javax.annotation.PostConstruct;

import java.io.IOException;
import java.sql.Timestamp;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;

import org.hibernate.Session;
import org.hibernate.query.Query;
import org.slf4j.Logger;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.DigestUtils;

import beidanci.api.Result;
import beidanci.api.model.DictDto;
import beidanci.api.model.DictVo;
import beidanci.api.model.DictStatsVo;
import beidanci.service.dao.BaseDao;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningDictId;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.store.WordCache;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.Util;
import beidanci.util.Constants;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictBo extends BaseBo<Dict> {
    private static final Logger log = org.slf4j.LoggerFactory.getLogger(DictBo.class);

    @Autowired
    LearningDictBo learningDictBo;

    @Autowired
    DictBo dictBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    WordCache wordCache;

        @PostConstruct
    public void init() {
        setDao(new BaseDao<Dict>() {
        });
    }

    public void selectDicts(String[] selectedDicts, String userId) throws IllegalAccessException {

        HashSet<String> selectedDictIds = new HashSet<>(Arrays.asList(selectedDicts));

        // 删除用户取消选择的单词书
        User user = userBo.findById(userId);
        for (Iterator<LearningDict> i = user.getLearningDicts().iterator(); i.hasNext();) {
            LearningDict learningDict = i.next();
            if (!selectedDictIds.contains(learningDict.getDict().getId())
                    && !learningDict.getDict().getName().equals("生词本")) {
                learningDictBo.deleteEntity(learningDict);
                i.remove();
                log.info(String.format("用户[%s]取消选择了单词书[%s]", Util.getNickNameOfUser(user),
                        learningDict.getDict().getShortName()));
            }
        }

        // 添加用户新选择的单词书
        for (String dictId : selectedDicts) {
            LearningDictId id = new LearningDictId(user.getId(), dictId);
            LearningDict selectedDict = learningDictBo.findById(id, false);
            if (selectedDict == null) {
                Dict dict = dictBo.findById(dictId, false);
                assert (dict.getIsReady());
                selectedDict = new LearningDict(id, dict, user, false, false);
                learningDictBo.createEntity(selectedDict);
                user.getLearningDicts().add(selectedDict);
                log.info(String.format("用户[%s]选择了单词书[%s]", Util.getNickNameOfUser(user), dict.getShortName()));
            }
        }

        userBo.updateEntity(user);
    }

    // 获取指定用户的所有单词书
    public List<Dict> getOwnDicts(User owner, Integer fetchSize) {
        Session session = getSession();
        String hql = "from Dict where owner=:owner";
        Query<Dict> query = session.createQuery(hql, Dict.class);
        query.setCacheable(true);
        query.setParameter("owner", owner);
        if (fetchSize != null) {
            query.setFetchSize(fetchSize);
        }
        List<Dict> result = query.list();
        return result;
    }

    // 获取指定用户ID的所有单词书
    public List<Dict> getDictsByOwnerId(String ownerId, Integer fetchSize) {
        Session session = getSession();
        String hql = "from Dict d where d.owner.id=:ownerId";
        Query<Dict> query = session.createQuery(hql, Dict.class);
        query.setCacheable(true);
        query.setParameter("ownerId", ownerId);
        if (fetchSize != null) {
            query.setFetchSize(fetchSize);
        }
        List<Dict> result = query.list();
        System.out.println("查询用户ID为 " + ownerId + " 的词典，共找到 " + result.size() + " 条记录");
        return result;
    }

    // 获取所有系统单词书
    public List<Dict> getAllSysDicts(Integer fetchSize) {
        User user = userBo.getByUserName(Constants.SYS_USER_SYS, false);
        return getOwnDicts(user, fetchSize);
    }

    /**
     * 完成对指定单词书的编辑
     *
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public Result<Object> finishEditingDict(int dictId)
            throws IllegalArgumentException, IllegalAccessException {
        Dict dict = dictBo.findById(dictId, false);
        if (dict.getIsReady()) {
            return new Result<>(false, "单词书已处于就绪状态，不可重复操作", null);
        }
        if (dict.getWordCount() < 10) {
            return new Result<>(false, "单词书中的单词数量不能小于10个", null);
        }

        // 对书中的单词进行乱序
        Collections.sort(dict.getDictWords(), (o1, o2) -> {
            String[] excludeFields = new String[] {
                    "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" };
            return DigestUtils.md5DigestAsHex(o1.getWordVo(wordCache, excludeFields).getSpell().getBytes())
                    .compareTo(DigestUtils
                            .md5DigestAsHex(o2.getWordVo(wordCache, excludeFields).getSpell().getBytes()));
        });
        int seq = 1; // 单词排序的顺序号
        for (DictWord dictWord : dict.getDictWords()) {
            dictWord.setSeq(seq);
            dictWordBo.updateEntity(dictWord);
            seq++;
        }

        dict.setWordCount(dict.getDictWords().size());
        dict.setIsReady(true);
        updateEntity(dict);

        return Result.success(null);
    }

    /**
     * 创建新单词书
     *
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public Result<DictVo> createNewDict(String dictName, User user)
            throws IOException, IllegalArgumentException, IllegalAccessException {
        // 检查同名单词书是否已经存在
        List<Dict> allMyDicts = getOwnDicts(user, null);
        for (Dict dict : allMyDicts) {
            if (dict.getShortName().equalsIgnoreCase(dictName)) {
                return new Result<>(false, "同名单词书已经存在", null);
            }
        }

        Dict dict = new Dict();
        dict.setWordCount(0);
        dict.setIsReady(false); // 新单词书处于待编辑状态
        dict.setIsShared(false);
        dict.setVisible(true);
        dict.setName(dictName + "." + new SimpleDateFormat("yyyyMMddHHmmss").format(new Date()));
        dict.setOwner(user);
        createEntity(dict);

        DictVo vo = BeanUtils.makeVo(dict, DictVo.class,
                new String[] { "invitedBy", "studyGroups", "userGames", "dictWords" });

        return new Result<>(true, null, vo);
    }

    public Dict findByName(String dictName) {
        Dict exam = new Dict();
        exam.setName(dictName);
        return queryUnique(exam);
    }

    public Dict getRawWordDict(User user) {
        Dict exam = new Dict();
        exam.setOwner(user);
        exam.setName("生词本");
        return queryUnique(exam);
    }

    public void clearDict(User user, Dict dict) throws IllegalAccessException {
        if (!dict.getOwner().equals(user)) {
            throw new RuntimeException("用户不得删除不属于自己的词书");
        }

        String hql = "delete DictWord where dict=:dict";
        javax.persistence.Query query = getSession().createQuery(hql);
        query.setParameter("dict", dict);
        query.executeUpdate();

        // 重置词书单词数
        dict.setWordCount(0);
        updateEntity(dict);

        // 重置学习中词书的当前学习位置
        learningDictBo.updateCurrentPositionForUserDict(user, dict.getId(), true);
    }

    public List<Word> getDictWords(Dict dict) {
        String hql = "from Word w where exists (" +
                "from DictWord dw where dw.word.id=w.id and dw.dict=:dict)";
        Query<Word> query = getSession().createQuery(hql, Word.class);
        query.setParameter("dict", dict);
        return query.list();
    }

    public DictDto getDictDto(String dictId) throws ParseException {
        // 通用词典现在是数据库中的实际记录，统一从数据库查询
        String sql = "select id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime from dict where id=:dictId";
        Query<?> query = getSession().createNativeQuery(sql);
        query.setParameter("dictId", dictId);
        Object[] result = (Object[]) query.uniqueResult();

        if (result == null) {
            return null;
        }

        DictDto dto = new DictDto();
        dto.setId((String) result[0]);
        dto.setName((String) result[1]);
        dto.setOwnerId((String) result[2]);
        dto.setIsShared((Boolean) result[3]);
        dto.setIsReady((Boolean) result[4]);
        dto.setVisible((Boolean) result[5]);
        dto.setWordCount((Integer) result[6]);
        dto.setPopularityLimit((Integer) result[7]);
        dto.setCreateTime((Timestamp) result[8]);
        dto.setUpdateTime((Timestamp) result[9]);
        return dto;
    }

    /**
     * 获取系统词典列表及其统计信息
     */
    public List<DictStatsVo> getSystemDictsWithStats() {
        Session session = getSession();
        
        // 获取系统词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE ownerId = :sysUserId ORDER BY createTime DESC";
        Query<?> dictQuery = session.createNativeQuery(dictSql);
        dictQuery.setParameter("sysUserId", Constants.SYS_USER_SYS_ID);
        List<?> dictResults = dictQuery.list();
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Query<?> totalUsersQuery = session.createNativeQuery(totalUsersSql);
        Long totalUsers = ((Number) totalUsersQuery.uniqueResult()).longValue();
        
        List<DictStatsVo> result = new ArrayList<>();
        
        for (Object dictResult : dictResults) {
            Object[] dictData = (Object[]) dictResult;
            
            DictStatsVo dto = new DictStatsVo();
            dto.setId((String) dictData[0]);
            dto.setName((String) dictData[1]);
            dto.setOwnerId((String) dictData[2]);
            dto.setIsShared((Boolean) dictData[3]);
            dto.setIsReady((Boolean) dictData[4]);
            dto.setVisible((Boolean) dictData[5]);
            dto.setWordCount((Integer) dictData[6]);
            dto.setPopularityLimit((Integer) dictData[7]);
            dto.setCreateTime((Timestamp) dictData[8]);
            dto.setUpdateTime((Timestamp) dictData[9]);
            dto.setTotalUsers(totalUsers);
            
            // 获取该词典被用户选择的数量
            String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
            Query<?> selectionQuery = session.createNativeQuery(selectionSql);
            selectionQuery.setParameter("dictId", dto.getId());
            Long selectionCount = ((Number) selectionQuery.uniqueResult()).longValue();
            dto.setUserSelectionCount(selectionCount);
            
            // 计算选择率
            if (totalUsers > 0) {
                dto.setSelectionRate((double) selectionCount / totalUsers * 100);
            } else {
                dto.setSelectionRate(0.0);
            }
            
            result.add(dto);
        }
        
        return result;
    }
    
    /**
     * 获取指定词典的详细统计信息
     */
    public DictStatsVo getDictStats(String dictId) {
        Session session = getSession();
        
        // 获取词典基本信息
        String dictSql = "SELECT id, name, ownerId, isShared, isReady, visible, wordCount, popularityLimit, createTime, updateTime " +
                       "FROM dict WHERE id = :dictId";
        Query<?> dictQuery = session.createNativeQuery(dictSql);
        dictQuery.setParameter("dictId", dictId);
        Object[] dictData = (Object[]) dictQuery.uniqueResult();
        
        if (dictData == null) {
            return null;
        }
        
        DictStatsVo dto = new DictStatsVo();
        dto.setId((String) dictData[0]);
        dto.setName((String) dictData[1]);
        dto.setOwnerId((String) dictData[2]);
        dto.setIsShared((Boolean) dictData[3]);
        dto.setIsReady((Boolean) dictData[4]);
        dto.setVisible((Boolean) dictData[5]);
        dto.setWordCount((Integer) dictData[6]);
        dto.setPopularityLimit((Integer) dictData[7]);
        dto.setCreateTime((Timestamp) dictData[8]);
        dto.setUpdateTime((Timestamp) dictData[9]);
        
        // 获取总用户数
        String totalUsersSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict";
        Query<?> totalUsersQuery = session.createNativeQuery(totalUsersSql);
        Long totalUsers = ((Number) totalUsersQuery.uniqueResult()).longValue();
        dto.setTotalUsers(totalUsers);
        
        // 获取该词典被用户选择的数量
        String selectionSql = "SELECT COUNT(DISTINCT userId) FROM learning_dict WHERE dictId = :dictId";
        Query<?> selectionQuery = session.createNativeQuery(selectionSql);
        selectionQuery.setParameter("dictId", dictId);
        Long selectionCount = ((Number) selectionQuery.uniqueResult()).longValue();
        dto.setUserSelectionCount(selectionCount);
        
        // 计算选择率
        if (totalUsers > 0) {
            dto.setSelectionRate((double) selectionCount / totalUsers * 100);
        } else {
            dto.setSelectionRate(0.0);
        }
        
        return dto;
    }

    /**
     * 更新系统词典信息
     */
    public void updateSystemDict(String dictId, String name, boolean isReady, boolean visible, Integer popularityLimit) {
        Dict dict = findById(dictId);
        if (dict == null) {
            throw new RuntimeException("词典不存在: " + dictId);
        }
        
        dict.setName(name);
        dict.setIsReady(isReady);
        dict.setVisible(visible);
        dict.setPopularityLimit(popularityLimit);
        dict.setUpdateTime(new java.sql.Timestamp(System.currentTimeMillis()));
        
        try {
            updateEntity(dict);
        } catch (Exception e) {
            throw new RuntimeException("更新词典失败: " + e.getMessage(), e);
        }
    }

}
