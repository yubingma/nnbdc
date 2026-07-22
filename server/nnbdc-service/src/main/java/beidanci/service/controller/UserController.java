package beidanci.service.controller;

import javax.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.UserBaseDataVo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;

@RestController
public class UserController {

    @Autowired
    private UserBo userBo;

    @DeleteMapping("/unRegister.do")
    public Result<Void> unRegister(@RequestParam String userId) throws IllegalAccessException {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.success(null);
        } else {
            userBo.unRegister(user.getId());
            return Result.success(null);
        }
    }

    @GetMapping("/getUserBaseData.do")
    public Result<UserBaseDataVo> getUserBaseData(@RequestParam String userId, HttpServletRequest request) {
        String supportedSteps = request.getHeader("X-Supported-Steps");
        return userBo.getUserBaseData(userId, supportedSteps);
    }
}
