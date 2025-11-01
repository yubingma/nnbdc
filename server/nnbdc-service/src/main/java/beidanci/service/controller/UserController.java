package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.PagedResults;
import beidanci.api.model.UserVo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;
import beidanci.service.util.UserSorter;

@RestController
public class UserController {

    @Autowired
    UserSorter userSorter;

    @Autowired
    UserBo userBo;

    @DeleteMapping("unRegister.do")
    @PreAuthorize("hasAnyRole('USER')")
    public Result<Void> unRegister(String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) { // 用户不存在是可能的, 比如用户注销了账户(通过某台设备), 但是用户有多个设备
            return Result.success(null);
        } else {
            userBo.unRegister(user.getId());
            return Result.success(null);
        }
    }

    @GetMapping("/getUserDbVersion.do")
    public Result<Integer> getUserDbVersion(String userId) {
        int version = userBo.getUserDbVersion(userId);
        return Result.success(version);
    }

    /**
     * 搜索用户（管理员功能）
     *
     * @param keyword 搜索关键词（用户名、昵称、邮箱）
     * @param pageNo 页码
     * @param pageSize 每页大小
     * @param filterType 筛选类型：0-全部, 1-管理员, 2-超级管理员, 3-录入员
     * @return 分页结果
     * @throws IllegalAccessException
     */
    @GetMapping("/admin/searchUsers.do")
    @PreAuthorize("hasAnyRole('ADMIN')")
    public Result<PagedResults<UserVo>> searchUsers(
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "1") int pageNo,
            @RequestParam(defaultValue = "20") int pageSize,
            @RequestParam(required = false) Integer filterType) throws IllegalAccessException {
        PagedResults<User> pagedResults = userBo.searchUsers(keyword, pageNo, pageSize, filterType);
        
        // 转换为UserVo
        List<User> users = pagedResults.getRows();
        List<UserVo> userVos = BeanUtils.makeVos(users, UserVo.class, 
            new String[]{"invitedBy", "StudyGroupVo.creator", "StudyGroupVo.users", 
                        "StudyGroupVo.managers", "studyGroupPosts", "userGames"});
        
        PagedResults<UserVo> result = new PagedResults<>(pagedResults.getTotal(), userVos);
        return Result.success(result);
    }

    /**
     * 更新用户管理员权限（管理员功能）
     *
     * @param userId 用户ID
     * @param isAdmin 是否为管理员
     * @param isSuperAdmin 是否为超级管理员
     * @param isInputor 是否为录入员
     * @return 更新结果
     * @throws IllegalAccessException
     */
    @PostMapping("/admin/updateAdminPermission.do")
    @PreAuthorize("hasAnyRole('ADMIN')")
    public Result<Void> updateAdminPermission(
            @RequestParam String userId,
            @RequestParam(required = false) Boolean isAdmin,
            @RequestParam(required = false) Boolean isSuperAdmin,
            @RequestParam(required = false) Boolean isInputor) throws IllegalAccessException {
        return userBo.updateAdminPermission(userId, isAdmin, isSuperAdmin, isInputor);
    }
}
