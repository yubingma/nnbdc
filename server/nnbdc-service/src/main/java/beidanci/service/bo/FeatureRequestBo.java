package beidanci.service.bo;

import java.util.List;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;

import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.hibernate.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.model.FeatureRequestStatus;
import beidanci.service.dao.FeatureRequestDao;
import beidanci.service.dao.FeatureRequestVoteDao;
import beidanci.service.po.FeatureRequest;
import beidanci.service.po.FeatureRequestVote;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class FeatureRequestBo extends BaseBo<FeatureRequest> {
    
    @Resource(name = "sessionFactory")
    private SessionFactory sessionFactory;
    
    @Resource
    private FeatureRequestDao featureRequestDao;
    
    @Resource
    private FeatureRequestVoteDao featureRequestVoteDao;
    
    @PostConstruct
    public void init() {
        setDao(featureRequestDao);
    }
    
    public Session getSession() {
        return sessionFactory.getCurrentSession();
    }
    
    /**
     * 获取所有需求，按投票数降序排列
     */
    public List<FeatureRequest> getAllFeatureRequests() {
        Session session = getSession();
        String hql = "from FeatureRequest order by voteCount desc, createTime desc";
        Query<FeatureRequest> query = session.createQuery(hql, FeatureRequest.class);
        return query.list();
    }
    
    /**
     * 创建需求
     */
    public FeatureRequest createFeatureRequest(String title, String content, User creator) {
        FeatureRequest request = new FeatureRequest();
        request.setTitle(title);
        request.setContent(content);
        request.setCreator(creator);
        request.setStatus(FeatureRequestStatus.VOTING);
        request.setVoteCount(0);
        createEntity(request);
        return request;
    }
    
    /**
     * 投票
     * @return true 表示投票成功，false 表示已经投过票
     */
    public boolean voteForRequest(String requestId, User user) {
        Session session = getSession();
        
        // 检查是否已经投过票
        FeatureRequest request = session.get(FeatureRequest.class, requestId);
        if (request == null) {
            return false;
        }
        
        // 检查用户是否已经投票
        String checkHql = "from FeatureRequestVote where request.id = :requestId and user.id = :userId";
        Query<FeatureRequestVote> checkQuery = session.createQuery(checkHql, FeatureRequestVote.class);
        checkQuery.setParameter("requestId", requestId);
        checkQuery.setParameter("userId", user.getId());
        FeatureRequestVote existingVote = checkQuery.uniqueResult();
        
        if (existingVote != null) {
            return false; // 已经投过票
        }
        
        // 创建投票记录
        FeatureRequestVote vote = new FeatureRequestVote();
        vote.setRequest(request);
        vote.setUser(user);
        featureRequestVoteDao.createEntity(session, vote);
        
        // 增加投票数
        request.setVoteCount(request.getVoteCount() + 1);
        session.update(request);
        
        return true;
    }
    
    /**
     * 检查用户是否已投票
     */
    public boolean hasUserVoted(String requestId, User user) {
        Session session = getSession();
        String hql = "from FeatureRequestVote where request.id = :requestId and user.id = :userId";
        Query<FeatureRequestVote> query = session.createQuery(hql, FeatureRequestVote.class);
        query.setParameter("requestId", requestId);
        query.setParameter("userId", user.getId());
        return query.uniqueResult() != null;
    }
    
    /**
     * 更新需求状态（管理员功能）
     */
    public void updateRequestStatus(String requestId, FeatureRequestStatus status) {
        Session session = getSession();
        FeatureRequest request = session.get(FeatureRequest.class, requestId);
        if (request != null) {
            request.setStatus(status);
            session.update(request);
        }
    }
}

