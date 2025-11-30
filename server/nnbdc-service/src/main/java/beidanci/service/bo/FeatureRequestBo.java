package beidanci.service.bo;

import java.util.Date;
import java.util.List;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
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
    
    @Resource
    private FeatureRequestDao featureRequestDao;
    
    @Resource
    private FeatureRequestVoteDao featureRequestVoteDao;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    
    @PostConstruct
    public void init() {
        setDao(featureRequestDao);
    }
    
    /**
     * 获取所有需求，按投票数降序排列
     */
    public List<FeatureRequest> getAllFeatureRequests() {
        String sql = "SELECT * FROM feature_request ORDER BY voteCount DESC, createTime DESC";
        return namedParameterJdbcTemplate.query(sql, 
            new beidanci.service.dao.EntityRowMapper<>(FeatureRequest.class));
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
     * @return Pair<Boolean, String> 第一个元素表示是否成功，第二个元素是错误信息（失败时）
     */
    public org.apache.commons.lang3.tuple.Pair<Boolean, String> voteForRequest(String requestId, User user) {
        try {
            // 检查需求是否存在
            FeatureRequest request = findById(requestId);
            if (request == null) {
                return org.apache.commons.lang3.tuple.Pair.of(false, "需求不存在");
            }
            
            // 检查用户是否已经投票
            String checkSql = "SELECT * FROM feature_request_vote WHERE requestId = :requestId AND userId = :userId";
            MapSqlParameterSource params = new MapSqlParameterSource();
            params.addValue("requestId", requestId);
            params.addValue("userId", user.getId());
            List<FeatureRequestVote> existingVotes = namedParameterJdbcTemplate.query(checkSql, params, 
                new beidanci.service.dao.EntityRowMapper<>(FeatureRequestVote.class));
            
            if (!existingVotes.isEmpty()) {
                return org.apache.commons.lang3.tuple.Pair.of(false, "您已经对此需求投过票了");
            }
            
            // 创建投票记录
            FeatureRequestVote vote = new FeatureRequestVote();
            vote.setRequest(request);
            vote.setUser(user);
            // 使用 BaseBo 的 createEntity 方法，需要通过 FeatureRequestVoteBo
            // 或者直接使用 JDBC
            String insertSql = "INSERT INTO feature_request_vote (id, requestId, userId, createTime, updateTime) VALUES (:id, :requestId, :userId, :createTime, :updateTime)";
            MapSqlParameterSource voteParams = new MapSqlParameterSource();
            voteParams.addValue("id", beidanci.service.util.Util.uuid());
            voteParams.addValue("requestId", request.getId());
            voteParams.addValue("userId", user.getId());
            Date now = new Date();
            voteParams.addValue("createTime", now);
            voteParams.addValue("updateTime", now);
            namedParameterJdbcTemplate.update(insertSql, voteParams);
            
            // 增加投票数
            request.setVoteCount(request.getVoteCount() + 1);
            updateEntity(request);
            
            return org.apache.commons.lang3.tuple.Pair.of(true, null);
        } catch (IllegalAccessException e) {
            return org.apache.commons.lang3.tuple.Pair.of(false, "更新失败: " + e.getMessage());
        }
    }
    
    /**
     * 检查用户是否已投票
     */
    public boolean hasUserVoted(String requestId, User user) {
        String sql = "SELECT * FROM feature_request_vote WHERE requestId = :requestId AND userId = :userId";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("requestId", requestId);
        params.addValue("userId", user.getId());
        List<FeatureRequestVote> votes = namedParameterJdbcTemplate.query(sql, params, 
            new beidanci.service.dao.EntityRowMapper<>(FeatureRequestVote.class));
        return !votes.isEmpty();
    }
    
    /**
     * 更新需求状态（管理员功能）
     */
    public void updateRequestStatus(String requestId, FeatureRequestStatus status) throws IllegalAccessException {
        FeatureRequest request = findById(requestId);
        if (request != null) {
            request.setStatus(status);
            updateEntity(request);
        }
    }
}

