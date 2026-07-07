-- Upgrade database to support promo activities
CREATE TABLE IF NOT EXISTS promo_activity (
    id VARCHAR(32) PRIMARY KEY,
    activity_code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    duration VARCHAR(50),
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    max_redemptions INT,
    redemption_count INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS promo_redemption (
    id VARCHAR(32) PRIMARY KEY,
    user_id VARCHAR(32) NOT NULL,
    activity_id VARCHAR(32) NOT NULL,
    redeem_time TIMESTAMP NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL,
    CONSTRAINT unique_user_activity UNIQUE (user_id, activity_id)
);
