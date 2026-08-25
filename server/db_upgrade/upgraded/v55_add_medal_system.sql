-- Upgrade database to support Badge & Medal Gamification System
-- 勋章元数据与控制逻辑在代码（Badge 枚举）中维护，数据库仅持久化用户达成状态
CREATE TABLE IF NOT EXISTS user_badge (
    id VARCHAR(32) PRIMARY KEY,
    user_id VARCHAR(32) NOT NULL,
    badge_code VARCHAR(50) NOT NULL,
    obtain_count INT NOT NULL DEFAULT 1,
    star_level INT NOT NULL DEFAULT 1,
    unlocked_at TIMESTAMP NOT NULL,
    is_equipped BOOLEAN NOT NULL DEFAULT FALSE,
    is_viewed BOOLEAN NOT NULL DEFAULT FALSE,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL,
    CONSTRAINT unique_user_badge UNIQUE (user_id, badge_code)
);

CREATE INDEX idx_user_badge_user ON user_badge(user_id);
