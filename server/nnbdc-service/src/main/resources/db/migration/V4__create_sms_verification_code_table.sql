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

-- 为user表添加mobile_phone字段的索引（如果字段已存在）
-- ALTER TABLE user ADD INDEX idx_mobile_phone (mobile_phone); 