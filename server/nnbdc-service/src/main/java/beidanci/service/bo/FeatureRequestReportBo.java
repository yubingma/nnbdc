package beidanci.service.bo;

import java.sql.Timestamp;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.api.Result;
import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.FeatureRequest;
import beidanci.service.po.FeatureRequestReport;
import beidanci.service.po.User;

@Service
@Transactional(rollbackFor = Throwable.class)
public class FeatureRequestReportBo extends BaseBo<FeatureRequestReport> {
    @Autowired
    UserBo userBo;

    @Autowired
    FeatureRequestBo featureRequestBo;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<FeatureRequestReport>() {
        });
    }

    /**
     * 保存需求墙举报
     */
    public Result<String> saveFeatureRequestReport(String requestId, String content, String userId) {
        // 检查 userId 是否为空
        if (userId == null || userId.trim().isEmpty()) {
            return Result.fail("用户ID不能为空");
        }

        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户不存在");
        }

        // 检查需求是否存在
        FeatureRequest request = featureRequestBo.findById(requestId);
        if (request == null) {
            return Result.fail("需求不存在");
        }

        if (content == null || content.trim().length() == 0) {
            return Result.fail("举报内容不能为空");
        }

        // 保存举报内容
        FeatureRequestReport report = new FeatureRequestReport();
        report.setFeatureRequest(request);
        report.setContent(content.trim());
        report.setCreateTime(new Timestamp(new Date().getTime()));
        report.setReporter(user);
        createEntity(report);

        return Result.success(String.valueOf(report.getId()), content);
    }

    /**
     * 获取所有举报（管理员功能）
     */
    public List<FeatureRequestReport> getAllReports() {
        String sql = "SELECT * FROM feature_request_report ORDER BY create_time DESC";
        List<FeatureRequestReport> reports = namedParameterJdbcTemplate.query(sql,
                new EntityRowMapper<>(FeatureRequestReport.class));

        // 批量加载 User 和 FeatureRequest 对象
        loadUsersAndRequestsForReports(reports);

        return reports;
    }

    /**
     * 批量加载 User 和 FeatureRequest 对象并填充到 FeatureRequestReport 的字段
     */
    private void loadUsersAndRequestsForReports(List<FeatureRequestReport> reports) {
        if (reports == null || reports.isEmpty()) {
            return;
        }

        // 收集所有需要加载的 User ID 和 FeatureRequest ID
        Set<String> userIds = new HashSet<>();
        Set<String> requestIds = new HashSet<>();
        for (FeatureRequestReport report : reports) {
            if (report.getReporter() != null && report.getReporter().getId() != null) {
                userIds.add(report.getReporter().getId());
            }
            if (report.getFeatureRequest() != null && report.getFeatureRequest().getId() != null) {
                requestIds.add(report.getFeatureRequest().getId());
            }
        }

        // 批量查询 User 对象
        Map<String, User> userMap = new HashMap<>();
        if (!userIds.isEmpty()) {
            String sql = "SELECT * FROM \"user\" WHERE id IN (:ids)";
            MapSqlParameterSource params = new MapSqlParameterSource("ids", userIds);
            List<User> users = namedParameterJdbcTemplate.query(sql, params,
                    new EntityRowMapper<>(User.class));
            for (User user : users) {
                userMap.put(user.getId(), user);
            }
        }

        // 批量查询 FeatureRequest 对象
        Map<String, FeatureRequest> requestMap = new HashMap<>();
        if (!requestIds.isEmpty()) {
            String sql = "SELECT * FROM feature_request WHERE id IN (:ids)";
            MapSqlParameterSource params = new MapSqlParameterSource("ids", requestIds);
            List<FeatureRequest> requests = namedParameterJdbcTemplate.query(sql, params,
                    new EntityRowMapper<>(FeatureRequest.class));
            
            // 收集 FeatureRequest 的 creator ID
            Set<String> creatorIds = new HashSet<>();
            for (FeatureRequest request : requests) {
                requestMap.put(request.getId(), request);
                if (request.getCreator() != null && request.getCreator().getId() != null) {
                    creatorIds.add(request.getCreator().getId());
                }
            }
            
            // 批量加载 FeatureRequest 的 creator
            Map<String, User> creatorMap = new HashMap<>();
            if (!creatorIds.isEmpty()) {
                String creatorSql = "SELECT * FROM \"user\" WHERE id IN (:ids)";
                MapSqlParameterSource creatorParams = new MapSqlParameterSource("ids", creatorIds);
                List<User> creators = namedParameterJdbcTemplate.query(creatorSql, creatorParams,
                        new EntityRowMapper<>(User.class));
                for (User creator : creators) {
                    creatorMap.put(creator.getId(), creator);
                }
            }
            
            // 填充 FeatureRequest 的 creator 字段
            for (FeatureRequest request : requests) {
                if (request.getCreator() != null && request.getCreator().getId() != null) {
                    User fullCreator = creatorMap.get(request.getCreator().getId());
                    if (fullCreator != null) {
                        request.setCreator(fullCreator);
                    }
                }
            }
        }

        // 填充 FeatureRequestReport 的字段
        for (FeatureRequestReport report : reports) {
            if (report.getReporter() != null && report.getReporter().getId() != null) {
                User fullUser = userMap.get(report.getReporter().getId());
                if (fullUser != null) {
                    report.setReporter(fullUser);
                }
            }
            if (report.getFeatureRequest() != null && report.getFeatureRequest().getId() != null) {
                FeatureRequest fullRequest = requestMap.get(report.getFeatureRequest().getId());
                if (fullRequest != null) {
                    report.setFeatureRequest(fullRequest);
                }
            }
        }
    }
}
