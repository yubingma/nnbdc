package beidanci.service.controller;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.Assert;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.CheckBy;
import beidanci.api.model.ClientType;
import beidanci.api.model.UserVo;
import beidanci.service.bo.EmailVerificationCodeBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.EmailCodeType;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;

@RestController
public class CheckUserController {

    @Autowired
    UserBo userBo;

    @Autowired
    EmailVerificationCodeBo emailVerificationCodeBo;

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

    /**
     * 邮箱验证码登录（纯验证码登录，不需要密码）
     * @param email 邮箱地址
     * @param code 验证码
     * @param clientType 客户端类型
     * @param clientVersion 客户端版本
     * @return 登录结果
     */
    @PostMapping("/loginByEmailCode.do")
    public Result<UserVo> loginByEmailCode(
            HttpServletRequest request,
            HttpServletResponse response,
            @RequestParam("email") String email,
            @RequestParam("code") String code,
            ClientType clientType,
            String clientVersion) {
        // 先验证验证码（验证邮箱没有输入错误）
        String verifyResult = emailVerificationCodeBo.verifyCode(email, code, EmailCodeType.LOGIN);
        if (!"OK".equals(verifyResult)) {
            return Result.fail(verifyResult);
        }

        // 验证码验证成功，进行登录或注册（不需要密码）
        Result<User> result = userBo.checkUserByEmailCode(request, email, clientType, clientVersion);
        
        if (result.isSuccess()) {
            User user = result.getData();
            Assert.notNull(user, "用户不存在");
            UserVo userVo = BeanUtils.makeVo(user, UserVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                    "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "userGames"});
            return new Result<>(true, "登录成功", userVo);
        }

        return new Result<>(false, result.getMsg(), null);
    }
}
