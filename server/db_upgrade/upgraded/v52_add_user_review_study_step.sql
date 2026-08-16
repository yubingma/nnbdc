-- Upgrade database to add user review study steps table (v52)
-- 旧词（复习词）三组学习规则：group_name ∈ ('check' 测评 / 'correct' 答对后 / 'wrong' 答错后)
-- 注意：列名用 group_name（group 是 SQL 保留字）

CREATE TABLE IF NOT EXISTS user_review_study_step (
    user_id VARCHAR(255) NOT NULL,
    group_name VARCHAR(20) NOT NULL,
    study_step VARCHAR(20) NOT NULL,
    seq INT NOT NULL,
    state VARCHAR(20) NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL,
    PRIMARY KEY (user_id, group_name, study_step)
);
