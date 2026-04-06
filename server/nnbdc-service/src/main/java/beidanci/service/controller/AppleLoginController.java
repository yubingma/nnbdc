package beidanci.service.controller;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.ClientType;
import beidanci.api.model.UserVo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import beidanci.service.util.PoVoUtils;

/**
 * 苹果登录控制器
 */
@RestController
public class AppleLoginController {


    @Autowired
    private UserBo userBo;

    /**
     * 苹果登录
     * 
     * @param userIdentifier 苹果返回的唯一用户标识
     * @param email 用户的邮箱（可能为空）
     * @param nickname 用户的昵称（可能为空）
     * @param clientType 客户端类型
     * @param clientVersion 客户端版本
     * @return 登录结果
     */
    @PostMapping("/loginByApple.do")
    public Result<UserVo> loginByApple(HttpServletRequest request, HttpServletResponse response,
                                       @RequestParam String userIdentifier,
                                       @RequestParam(required = false) String email,
                                       @RequestParam(required = false) String nickname,
                                       @RequestParam ClientType clientType, 
                                       @RequestParam String clientVersion) {

        if (userIdentifier == null || userIdentifier.trim().isEmpty()) {
            return new Result<>(false, "缺少苹果用户标识", null);
        }

        // 查找或创建用户
        User user = userBo.findOrCreateUserByApple(userIdentifier, email, nickname);
        if (user == null) {
            return new Result<>(false, "用户创建失败", null);
        }

        // 执行登录逻辑（设置session等） 可以复用 doLoginByWechat
        Result<User> loginResult = userBo.doLoginByWechat(user, clientType, clientVersion, request, response);

        if (loginResult.isSuccess()) {
            UserVo userVo = PoVoUtils.makeVo(user, UserVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                    "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "userGames"});
            return new Result<>(true, "登录成功", userVo);
        } else {
            return new Result<>(false, loginResult.getMsg(), null);
        }
    }
}
