# 手机号登录功能使用说明

## 功能概述

本系统已集成手机号注册/登录功能，支持以下登录方式：
- 手机号 + 验证码登录
- 手机号 + 密码登录
- 邮箱 + 密码登录（原有功能）

## 后端配置

### 1. 阿里云短信服务配置

在 `application-sms.yml` 中配置阿里云短信服务参数：

```yaml
aliyun:
  sms:
    access-key-id: ${ALIYUN_SMS_ACCESS_KEY_ID:your_access_key_id}
    access-key-secret: ${ALIYUN_SMS_ACCESS_KEY_SECRET:your_access_key_secret}
    sign-name: 牛牛背单词
    region-id: cn-hangzhou
    template-codes:
      register: SMS_123456789
      login: SMS_123456790
      reset-password: SMS_123456791
```

### 2. 环境变量配置

设置以下环境变量：
```bash
export ALIYUN_SMS_ACCESS_KEY_ID=your_access_key_id
export ALIYUN_SMS_ACCESS_KEY_SECRET=your_access_key_secret
```

### 3. 数据库迁移

执行数据库迁移脚本：
```sql
-- 创建短信验证码表
CREATE TABLE IF NOT EXISTS sms_verification_code (
    id VARCHAR(36) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    type VARCHAR(20) NOT NULL,
    expire_time DATETIME NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    create_time DATETIME NOT NULL,
    update_time DATETIME NOT NULL,
    PRIMARY KEY (id),
    INDEX idx_phone_type (phone, type),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## API接口

### 1. 发送短信验证码
```
POST /sendSmsCode.do
参数：
- phone: 手机号
- type: 验证码类型（REGISTER/LOGIN/RESET_PASSWORD）
```

### 2. 验证短信验证码
```
POST /verifySmsCode.do
参数：
- phone: 手机号
- code: 验证码
- type: 验证码类型
```

### 3. 手机号注册
```
POST /registerByPhone.do
参数：
- phone: 手机号
- code: 验证码
- password: 密码
- password2: 确认密码
- nickName: 昵称（可选）
- invitorId: 邀请人ID（可选）
```

### 4. 手机号验证码登录
```
POST /loginByPhone.do
参数：
- phone: 手机号
- code: 验证码
- clientType: 客户端类型
- clientVersion: 客户端版本
```

### 5. 手机号密码登录
```
POST /loginByPhonePassword.do
参数：
- phone: 手机号
- password: 密码
- clientType: 客户端类型
- clientVersion: 客户端版本
```

## 前端使用

### 1. 登录页面

在原有登录页面点击"手机号登录"按钮，进入手机号登录页面。

### 2. 手机号登录页面功能

- 支持验证码登录和密码登录两种方式
- 验证码发送有60秒倒计时限制
- 验证码5分钟内有效
- 支持用户协议和隐私政策确认

## 安全说明

1. 验证码有效期：5分钟
2. 发送频率限制：每分钟最多发送1次
3. 验证码使用后立即失效
4. 手机号格式验证：11位数字
5. 密码长度要求：至少6位

## 注意事项

1. 请确保阿里云短信服务已开通并配置正确的模板
2. 生产环境请使用真实的AccessKey和Secret
3. 短信模板需要提前在阿里云控制台申请并通过审核
4. 建议在测试环境先验证功能正常后再部署到生产环境 