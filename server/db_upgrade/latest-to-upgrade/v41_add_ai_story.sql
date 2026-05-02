-- Create ai_story table for caching AI generated stories
CREATE TABLE IF NOT EXISTS ai_story (
    id VARCHAR(32) PRIMARY KEY,
    words_hash VARCHAR(64) NOT NULL UNIQUE,
    words_json TEXT NOT NULL,
    story_content TEXT NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP
);

COMMENT ON COLUMN ai_story.words_hash IS 'Sorted words hash for unique identification';
COMMENT ON COLUMN ai_story.words_json IS 'The list of words used';
COMMENT ON COLUMN ai_story.story_content IS 'The generated story content';

