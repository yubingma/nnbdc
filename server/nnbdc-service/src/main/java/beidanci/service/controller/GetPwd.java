package beidanci.service.controller;

import java.io.IOException;
import java.util.Date;
import java.util.List;
import java.util.Map;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.commons.mail.EmailException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.GetPwdLogBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.GetPwdLog;
import beidanci.service.po.User;
import beidanci.service.util.Util;

@RestController
public class GetPwd {

    @Autowired
    GetPwdLogBo getPwdLogBo;

    @Autowired
    UserBo userBo;

    @GetMapping("/getPwd.do")
    @ResponseBody
    public Result<Void> handle(HttpServletRequest request, HttpServletResponse response)
            throws EmailException, IOException {
        // Get parameter from request.
        Map<String, String[]> paramMap = request.getParameterMap();
        String email = paramMap.get("email")[0];

        // 查找邮箱对应的用户，并发送密码到该邮箱
        Result<Void> result;
        if (email != null && email.trim().length() > 0) {
            List<User> users = userBo.findByEmail(email);
            if (!users.isEmpty()) {
                StringBuilder content = new StringBuilder();
                content.append("您在牛牛背单词的帐户信息：\r\n");
                for (User user : users) {
                    content.append(String.format("用户名：%s  密码：%s\r\n", user.getEmail(), user.getPassword()));
                }

                sendPwdByEmail(email, Util.getNickNameOfUser(users.get(0)), content.toString());
                result = Result.success(email, null);
            } else {
                result = Result.fail("Email在系统中不存在");
            }
        } else {
            result = Result.fail("Email不能为空");
        }

        return result;
    }

    /**
     * 用Email方式发送用户的密码到用户邮箱
     *
     * @param toEmail
     * @param toName
     * @param content
     */
    private void sendPwdByEmail(String toEmail, String toName, String content) {
        String sendResult = "success";
        Util.sendSimpleEmail(toEmail, toName, "您在牛牛背单词的密码", content);

        // 写日志
        GetPwdLog getPwdLog = new GetPwdLog(toEmail, new Date((new Date()).getTime()), content, sendResult);
        getPwdLogBo.createEntity(getPwdLog);
    }
}
