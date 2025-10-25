package beidanci.service.controller;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.ClientType;
import beidanci.api.model.UserVo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.WechatBo;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;

/**
 * 微信登录控制器
 */
@RestController
public class WechatLoginController {

    private static final Logger logger = LoggerFactory.getLogger(WechatLoginController.class);

    @Autowired
    private UserBo userBo;

    @Autowired
    private WechatBo wechatBo;

    /**
     * 微信授权码登录
     * 
     * @param code 微信授权码
     * @param clientType 客户端类型
     * @param clientVersion 客户端版本
     * @return 登录结果
     */
    @PostMapping("/loginByWechat.do")
    public Result<UserVo> loginByWechat(HttpServletRequest request, HttpServletResponse response,
                                       @RequestParam String code,
                                       @RequestParam ClientType clientType, 
                                       @RequestParam String clientVersion) {

        try {
            // 1. 使用code从微信获取用户信息
            Result<WechatBo.WechatUserInfo> wechatResult = wechatBo.getUserInfoByCode(code);
            if (!wechatResult.isSuccess() || wechatResult.getData() == null) {
                logger.error("获取微信用户信息失败: {}", wechatResult.getMsg());
                return new Result<>(false, wechatResult.getMsg() != null ? wechatResult.getMsg() : "微信授权失败", null);
            }

            WechatBo.WechatUserInfo wechatUserInfo = wechatResult.getData();

            // 2. 根据openId查找或创建用户
            User user = userBo.findOrCreateUserByWechat(wechatUserInfo);
            if (user == null) {
                return new Result<>(false, "用户创建失败", null);
            }

            // 3. 执行登录逻辑（设置session等）
            Result<User> loginResult = userBo.doLoginByWechat(user, clientType, clientVersion, request, response);

            if (loginResult.isSuccess()) {
                UserVo userVo = BeanUtils.makeVo(user, UserVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                        "StudyGroupVo.users", "StudyGroupVo.managers", "StudyGroupVo.studyGroupPosts", "userGames"});
                return new Result<>(true, "登录成功", userVo);
            } else {
                return new Result<>(false, loginResult.getMsg(), null);
            }

        } catch (Exception e) {
            logger.error("微信登录异常", e);
            return new Result<>(false, "登录失败，请稍后重试", null);
        }
    }
}

