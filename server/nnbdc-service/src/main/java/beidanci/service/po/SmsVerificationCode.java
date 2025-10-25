package beidanci.service.po;

import java.util.Date;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.Table;

/**
 * 短信验证码实体类
 */
@Entity
@Table(name = "sms_verification_code")
public class SmsVerificationCode extends UuidPo {


    @Column(name = "phone", length = 20, nullable = false)
    private String phone;

    @Column(name = "code", length = 6, nullable = false)
    private String code;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", length = 20, nullable = false)
    private SmsCodeType type;

    @Column(name = "expire_time", nullable = false)
    private Date expireTime;

    @Column(name = "used", nullable = false)
    private Boolean used = false;

    public SmsVerificationCode() {
    }

    public SmsVerificationCode(String phone, String code, SmsCodeType type, Date expireTime) {
        this.phone = phone;
        this.code = code;
        this.type = type;
        this.expireTime = expireTime;
        this.used = false;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }

    public SmsCodeType getType() {
        return type;
    }

    public void setType(SmsCodeType type) {
        this.type = type;
    }

    public Date getExpireTime() {
        return expireTime;
    }

    public void setExpireTime(Date expireTime) {
        this.expireTime = expireTime;
    }

    public Boolean getUsed() {
        return used;
    }

    public void setUsed(Boolean used) {
        this.used = used;
    }

    /**
     * 检查验证码是否已过期
     */
    public boolean isExpired() {
        return new Date().after(expireTime);
    }

    /**
     * 检查验证码是否有效（未使用且未过期）
     */
    public boolean isValid() {
        return !used && !isExpired();
    }
}
