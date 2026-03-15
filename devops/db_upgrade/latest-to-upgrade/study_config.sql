-- Add study_config column
ALTER TABLE "user" ADD COLUMN study_config TEXT;

-- Migrate data from individual columns and walkman_config into study_config JSON
UPDATE "user" SET study_config = json_build_object(
    'autoPlayWord', auto_play_word,
    'autoPlaySentence', auto_play_sentence,
    'showAnswersDirectly', show_answers_directly,
    'enableAllWrong', enable_all_wrong,
    'asrPassRule', CASE 
        WHEN asr_pass_rule = 'ALL' THEN 100 
        WHEN asr_pass_rule = 'HALF' THEN 80 
        ELSE 60 
    END,
    'walkman', CASE 
        WHEN walkman_config IS NOT NULL AND walkman_config <> '' THEN walkman_config::json 
        ELSE NULL 
    END
)::text;

-- Drop obsolete columns
ALTER TABLE "user" DROP COLUMN auto_play_word;
ALTER TABLE "user" DROP COLUMN auto_play_sentence;
ALTER TABLE "user" DROP COLUMN show_answers_directly;
ALTER TABLE "user" DROP COLUMN enable_all_wrong;
ALTER TABLE "user" DROP COLUMN asr_pass_rule;
ALTER TABLE "user" DROP COLUMN walkman_config;
