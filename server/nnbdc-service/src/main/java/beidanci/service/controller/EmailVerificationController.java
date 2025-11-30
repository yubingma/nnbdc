package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.EmailVerificationCodeBo;
import beidanci.service.po.EmailCodeType;

/**
 * 邮箱验证码控制器
 */
@RestController
public class EmailVerificationController {

    @Autowired
    private EmailVerificationCodeBo emailVerificationCodeBo;

    /**
     * 发送邮箱验证码
     * @param email 邮箱地址
     * @param type 验证码类型（REGISTER/LOGIN/GET_PASSWORD）
     * @return 发送结果
     */
    @PostMapping("/sendEmailCode.do")
    @ResponseBody
    public Result<String> sendEmailCode(
            @RequestParam("email") String email,
            @RequestParam("type") String type) {
        EmailCodeType codeType;
        try {
            codeType = EmailCodeType.valueOf(type.toUpperCase());
        } catch (IllegalArgumentException e) {
            return Result.fail("无效的验证码类型");
        }

        String result = emailVerificationCodeBo.sendVerificationCode(email, codeType);
        if ("OK".equals(result)) {
            return Result.success("验证码已发送到您的邮箱", null);
        } else {
            return Result.fail(result);
        }
    }

    /**
     * 验证邮箱验证码
     * @param email 邮箱地址
     * @param code 验证码
     * @param type 验证码类型
     * @return 验证结果
     */
    @PostMapping("/verifyEmailCode.do")
    @ResponseBody
    public Result<Void> verifyEmailCode(
            @RequestParam("email") String email,
            @RequestParam("code") String code,
            @RequestParam("type") String type) {
        EmailCodeType codeType;
        try {
            codeType = EmailCodeType.valueOf(type.toUpperCase());
        } catch (IllegalArgumentException e) {
            return Result.fail("无效的验证码类型");
        }

        String result = emailVerificationCodeBo.verifyCode(email, code, codeType);
        if ("OK".equals(result)) {
            return Result.success("验证成功", null);
        } else {
            return Result.fail(result);
        }
    }
}

