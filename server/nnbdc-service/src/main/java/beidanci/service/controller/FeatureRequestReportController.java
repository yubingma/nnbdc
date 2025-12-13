package beidanci.service.controller;

import java.sql.SQLException;
import java.util.List;

import javax.naming.NamingException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.FeatureRequestReportBo;
import beidanci.service.po.FeatureRequestReport;
import beidanci.service.util.BeanUtils;
import beidanci.api.model.FeatureRequestReportVo;

@RestController
public class FeatureRequestReportController {
    @Autowired
    FeatureRequestReportBo featureRequestReportBo;

    /**
     * 保存需求墙举报
     */
    @PostMapping("/saveFeatureRequestReport.do")
    public Result<String> saveFeatureRequestReport(
            @RequestParam("requestId") String requestId,
            @RequestParam("content") String content,
            @RequestParam("userId") String userId)
            throws SQLException, NamingException, ClassNotFoundException {
        return featureRequestReportBo.saveFeatureRequestReport(requestId, content, userId);
    }

    /**
     * 获取所有举报（管理员功能）
     */
    @GetMapping("/getAllFeatureRequestReports.do")
    public List<FeatureRequestReportVo> getAllFeatureRequestReports() throws IllegalAccessException {
        List<FeatureRequestReport> reports = featureRequestReportBo.getAllReports();
        return BeanUtils.makeVos(reports, FeatureRequestReportVo.class,
                new String[]{"reporter.password", "reporter.invitedBy", "reporter.StudyGroupVo.creator",
                        "reporter.StudyGroupVo.users", "reporter.StudyGroupVo.managers",
                        "reporter.studyGroupPosts", "reporter.userGames",
                        "featureRequest.creator.password", "featureRequest.creator.invitedBy",
                        "featureRequest.creator.StudyGroupVo.creator",
                        "featureRequest.creator.StudyGroupVo.users",
                        "featureRequest.creator.StudyGroupVo.managers",
                        "featureRequest.creator.studyGroupPosts", "featureRequest.creator.userGames"});
    }
}
