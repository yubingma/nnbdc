-- Upgrade database from v39 to v40
-- Add user_study_daily_stat table for study history heatmap

CREATE TABLE IF NOT EXISTS user_study_daily_stat (
    user_id VARCHAR(50) NOT NULL,
    date DATE NOT NULL,
    study_seconds INT DEFAULT 0,
    review_count INT DEFAULT 0,
    day_status VARCHAR(20) DEFAULT NULL,
    PRIMARY KEY (user_id, date)
);
