package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
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
}
