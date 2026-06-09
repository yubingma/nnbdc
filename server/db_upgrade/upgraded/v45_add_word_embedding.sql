CREATE TABLE word_embedding (
    id VARCHAR(32) PRIMARY KEY REFERENCES word(id) ON DELETE CASCADE,
    embedding BYTEA NOT NULL,
    dimension INTEGER NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL
);

CREATE TABLE pca_projection_config (
    id VARCHAR(32) PRIMARY KEY,
    config_json TEXT NOT NULL,
    update_time TIMESTAMP NOT NULL
);

ALTER TABLE word ADD COLUMN vec_x REAL;
ALTER TABLE word ADD COLUMN vec_y REAL;
ALTER TABLE word ADD COLUMN vec_z REAL;
