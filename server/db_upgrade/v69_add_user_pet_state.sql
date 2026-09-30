-- 记忆守护兽养成状态表：每个用户一行，记录累计投喂次数与进化阶段
CREATE TABLE IF NOT EXISTS user_pet_state (
    id              VARCHAR(32)  NOT NULL,
    user_id         VARCHAR(32)  NOT NULL,
    stage_index     INTEGER      NOT NULL DEFAULT 0,
    total_feedings  INTEGER      NOT NULL DEFAULT 0,
    form            VARCHAR(20)  NOT NULL DEFAULT 'neutral',
    create_time     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_time     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_pet_state PRIMARY KEY (id)
);

COMMENT ON TABLE user_pet_state IS '记忆守护兽养成状态：用户投喂守护兽的累计进度，每个用户一行';
COMMENT ON COLUMN user_pet_state.id IS '主键，32 位 UUID';
COMMENT ON COLUMN user_pet_state.user_id IS '所属用户 ID';
COMMENT ON COLUMN user_pet_state.stage_index IS '进化阶段下标：0=泡芽 1=幼兽 2=灵兽 3=守护兽 4=记忆巨兽';
COMMENT ON COLUMN user_pet_state.total_feedings IS '累计投喂次数，只增不减；进化阶段由它按阈值换算';
COMMENT ON COLUMN user_pet_state.form IS '进化系别：neutral=通用；其余由主背词库派生（学者系/英伦系/环球系/学院系）';
COMMENT ON COLUMN user_pet_state.create_time IS '创建时间';
COMMENT ON COLUMN user_pet_state.update_time IS '更新时间';

-- 每个用户至多一行，按 user_id 判存与查询都依赖这个唯一索引
CREATE UNIQUE INDEX IF NOT EXISTS uk_user_pet_state_user_id ON user_pet_state (user_id);
