package beidanci.service.controller;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.Assert;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.CheckBy;
import beidanci.api.model.ClientType;
import beidanci.api.model.UserVo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;

@RestController
public class CheckUserController {

    @Autowired
    UserBo userBo;

    @PutMapping("/checkUser.do")
    public Result<UserVo> checkUser(HttpServletRequest request, HttpServletResponse response, String userName, String email,
                              String password, CheckBy checkBy, ClientType clientType, String clientVersion)
            throws IllegalArgumentException, IllegalAccessException {

        // 只进行用户名密码验证，不进行真正的登录
        Result<User> result = userBo.checkUser(request, userName, email, password,
                checkBy, clientType, clientVersion);

        if (result.isSuccess()) {
            User user = result.getData();
            Assert.notNull(user, "用户不存在");
            UserVo userVo = BeanUtils.makeVo(user, UserVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                    "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "userGames"});
            return new Result<>(true, "验证成功", userVo);
        }

        return new Result<>(false, result.getMsg(), null);
    }
}
