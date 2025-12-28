package beidanci.service.controller;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
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
import java.util.Date;

@RestController
public class UserController {

    @Autowired
    UserSorter userSorter;

    @Autowired
    UserBo userBo;

    @DeleteMapping("unRegister.do")
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
    public Result<Void> updateAdminPermission(
            @RequestParam String userId,
            @RequestParam(required = false) Boolean isAdmin,
            @RequestParam(required = false) Boolean isSuperAdmin,
            @RequestParam(required = false) Boolean isInputor) throws IllegalAccessException {
        return userBo.updateAdminPermission(userId, isAdmin, isSuperAdmin, isInputor);
    }

    /**
     * 更新“强制视为会员”开关及其元数据（管理员功能）
     * 注意：程序不会自动根据时间去改 enabled，仅在判定会员时使用这些字段做计算。
     *
     * @param userId 用户ID
     * @param enabled 是否强制视为会员
     * @param reason 修改原因（可空）
     * @param duration 延续时长字符串（形如：10天/360秒/15分钟；null 表示永久）
     */
    @PostMapping("/admin/updatePremiumOverride.do")
    public Result<Void> updatePremiumOverride(
            @RequestParam String userId,
            @RequestParam Boolean enabled,
            @RequestParam(required = false) String reason,
            @RequestParam(required = false) String duration) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户不存在");
        }

        user.setPremiumOverrideEnabled(enabled);
        user.setPremiumOverrideUpdateTime(new Date());
        user.setPremiumOverrideReason(reason);
        user.setPremiumOverrideDuration(duration);

        userBo.updateEntity(user);
        // 服务端主动变更，写入 user_db_log，确保客户端同步可见
        userBo.logUserUpdateForSync(user);
        return Result.success(null);
    }

    /**
     * 删除用户（管理员功能）
     *
     * @param userId 用户ID
     * @return 删除结果
     * @throws IllegalAccessException
     */
    @DeleteMapping("/admin/deleteUser.do")
    public Result<Void> deleteUser(@RequestParam String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户不存在");
        }
        // 防止删除系统用户
        if (user.getIsSysUser() != null && Boolean.TRUE.equals(user.getIsSysUser())) {
            return Result.fail("不能删除系统用户");
        }
        userBo.deleteUser(user);
        return Result.success(null);
    }
    
    /**
     * 获取单个用户信息（管理员功能）
     *
     * @param userId 用户ID
     * @return 用户信息
     * @throws IllegalAccessException
     */
    @GetMapping("/admin/getUserById.do")
    public Result<UserVo> getUserById(@RequestParam String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户不存在");
        }
        
        // 转换为UserVo
        UserVo userVo = BeanUtils.makeVo(user, UserVo.class, 
            new String[]{"invitedBy", "StudyGroupVo.creator", "StudyGroupVo.users", 
                        "StudyGroupVo.managers", "studyGroupPosts", "userGames"});
        
        return Result.success(userVo);
    }
}
