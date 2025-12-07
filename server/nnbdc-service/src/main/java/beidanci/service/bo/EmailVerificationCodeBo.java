package beidanci.service.bo;

import java.util.Calendar;
import java.util.Date;
import java.util.List;

import javax.annotation.PostConstruct;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.EmailCodeType;
import beidanci.service.po.EmailVerificationCode;
import beidanci.service.util.EmailUtil;

/**
 * 邮箱验证码业务逻辑类
 */
@Service
@Transactional(rollbackFor = Throwable.class)
public class EmailVerificationCodeBo extends BaseBo<EmailVerificationCode> {

    @Autowired
    private EmailUtil emailUtil;

    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Value("${sms.code.length:6}")
    private int codeLength;

    @Value("${sms.code.expire-minutes:5}")
    private int expireMinutes;

    @Value("${sms.code.send-interval-seconds:60}")
    private int sendIntervalSeconds;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<EmailVerificationCode>() {
        });
    }

    /**
     * 生成随机验证码
     */
    private String generateCode() {
        return String.format("%0" + codeLength + "d", 
            (int) (Math.random() * Math.pow(10, codeLength)));
    }

    /**
     * 发送邮箱验证码
     * @param email 邮箱地址
     * @param type 验证码类型
     * @return 发送结果，"OK"表示成功，其他为错误信息
     */
    public String sendVerificationCode(String email, EmailCodeType type) {
        // 特殊邮箱处理：test@nnbdc.com 用于审核，固定验证码123456，不发送邮件
        if ("test@nnbdc.com".equalsIgnoreCase(email)) {
            return "OK";
        }

        // 检查发送间隔
        Date now = new Date();
        Date minSendTime = new Date(now.getTime() - sendIntervalSeconds * 1000L);
        
        String sql = "SELECT * FROM email_verification_code WHERE email = :email AND type = :type AND createTime > :minSendTime ORDER BY createTime DESC LIMIT 1";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("email", email);
        params.addValue("type", type.toString());
        params.addValue("minSendTime", minSendTime);
        
        List<EmailVerificationCode> recentCodes = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(EmailVerificationCode.class));
        if (!recentCodes.isEmpty()) {
            return "发送过于频繁，请稍后再试";
        }

        // 生成验证码
        String code = generateCode();
        
        // 计算过期时间
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.MINUTE, expireMinutes);
        Date expireTime = cal.getTime();

        // 保存验证码到数据库
        EmailVerificationCode verificationCode = new EmailVerificationCode(email, code, type, expireTime);
        createEntity(verificationCode);

        // 发送邮件
        String toName = email.contains("@") ? email.split("@")[0] : "用户";
        String result = emailUtil.sendVerificationCode(email, toName, code);
        
        if (!"OK".equals(result)) {
            return "邮件发送失败：" + result;
        }

        return "OK";
    }

    /**
     * 验证邮箱验证码
     * @param email 邮箱地址
     * @param code 验证码
     * @param type 验证码类型
     * @return 验证结果，"OK"表示成功，其他为错误信息
     */
    public String verifyCode(String email, String code, EmailCodeType type) {
        // 特殊邮箱处理：test@nnbdc.com 用于审核，验证码固定为123456时直接通过
        if ("test@nnbdc.com".equalsIgnoreCase(email) && "123456".equals(code)) {
            return "OK";
        }

        String sql = "SELECT * FROM email_verification_code WHERE email = :email AND code = :code AND type = :type ORDER BY createTime DESC LIMIT 1";
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("email", email);
        params.addValue("code", code);
        params.addValue("type", type.toString());
        
        List<EmailVerificationCode> codes = namedParameterJdbcTemplate.query(sql, params, 
            new EntityRowMapper<>(EmailVerificationCode.class));
        if (codes.isEmpty()) {
            return "验证码错误";
        }

        EmailVerificationCode verificationCode = codes.get(0);

        // 只检查是否过期，不检查是否已使用，允许在有效期内多次使用
        if (verificationCode.isExpired()) {
            return "验证码已过期";
        }

        return "OK";
    }
}

