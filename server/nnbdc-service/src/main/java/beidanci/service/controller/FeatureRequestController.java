package beidanci.service.controller;

import java.util.List;

import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.FeatureRequestStatus;
import beidanci.api.model.FeatureRequestVo;
import beidanci.service.bo.FeatureRequestBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.FeatureRequest;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;

@RestController
public class FeatureRequestController {

    @Autowired
    FeatureRequestBo featureRequestBo;

    @Autowired
    UserBo userBo;

    /**
     * 获取所有需求列表（按投票数降序）
     */
    @GetMapping("/getAllFeatureRequests.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    public List<FeatureRequestVo> getAllFeatureRequests() throws IllegalAccessException {
        List<FeatureRequest> requests = featureRequestBo.getAllFeatureRequests();
        return BeanUtils.makeVos(requests, FeatureRequestVo.class, 
                new String[]{"creator.password", "creator.invitedBy", "creator.StudyGroupVo.creator",
                        "creator.StudyGroupVo.users", "creator.StudyGroupVo.managers", 
                        "creator.studyGroupPosts", "creator.userGames"});
    }

    /**
     * 创建需求
     */
    @PostMapping("/createFeatureRequest.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    @ResponseBody
    public Result<FeatureRequestVo> createFeatureRequest(@RequestParam(name = "title") String title,
                                                         @RequestParam(name = "content") String content,
                                                         @RequestParam(name = "userId") String userId) 
            throws IllegalAccessException {
        if (StringUtils.isEmpty(title.trim())) {
            return Result.fail("标题不得为空");
        }
        if (StringUtils.isEmpty(content.trim())) {
            return Result.fail("内容不得为空");
        }
        
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户未登录");
        }
        
        FeatureRequest request = featureRequestBo.createFeatureRequest(title, content, user);
        FeatureRequestVo vo = BeanUtils.makeVo(request, FeatureRequestVo.class,
                new String[]{"creator.password", "creator.invitedBy", "creator.StudyGroupVo.creator",
                        "creator.StudyGroupVo.users", "creator.StudyGroupVo.managers", 
                        "creator.studyGroupPosts", "creator.userGames"});
        shrinkCreatorInfo(vo);
        return Result.success(vo);
    }

    /**
     * 投票
     */
    @PostMapping("/voteFeatureRequest.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    @ResponseBody
    public Result<Void> voteFeatureRequest(@RequestParam(name = "requestId") String requestId,
                                          @RequestParam(name = "userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户未登录");
        }
        
        boolean success = featureRequestBo.voteForRequest(requestId, user);
        if (success) {
            return Result.success(null);
        } else {
            return Result.fail("已经投过票或需求不存在");
        }
    }

    /**
     * 检查用户是否已投票
     */
    @GetMapping("/hasUserVoted.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    public Result<Boolean> hasUserVoted(@RequestParam(name = "requestId") String requestId,
                                        @RequestParam(name = "userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户未登录");
        }
        
        boolean voted = featureRequestBo.hasUserVoted(requestId, user);
        return Result.success(voted);
    }

    /**
     * 更新需求状态（管理员功能）
     */
    @PutMapping("/updateFeatureRequestStatus.do")
    @PreAuthorize("hasAnyRole('ADMIN')")
    @ResponseBody
    public Result<Void> updateFeatureRequestStatus(@RequestParam(name = "requestId") String requestId,
                                                   @RequestParam(name = "status") String statusStr,
                                                   @RequestParam(name = "adminUserId") String adminUserId) {
        User adminUser = userBo.findById(adminUserId);
        if (adminUser == null || !adminUser.getIsAdmin()) {
            return Result.fail("管理员权限不足");
        }
        
        try {
            FeatureRequestStatus status = FeatureRequestStatus.valueOf(statusStr);
            featureRequestBo.updateRequestStatus(requestId, status);
            return Result.success(null);
        } catch (IllegalArgumentException e) {
            return Result.fail("无效的状态值");
        }
    }

    private void shrinkCreatorInfo(FeatureRequestVo vo) throws IllegalAccessException {
        if (vo.getCreator() != null) {
            BeanUtils.setPropertiesToNull(vo.getCreator(), new String[]{"id", "displayNickName"});
        }
    }
}

