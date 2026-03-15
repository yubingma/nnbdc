-- Fix asrPassRule in study_config JSON from numeric to enum string
UPDATE "user" 
SET study_config = json_build_object(
    'autoPlayWord', (study_config::json)->'autoPlayWord',
    'autoPlaySentence', (study_config::json)->'autoPlaySentence',
    'showAnswersDirectly', (study_config::json)->'showAnswersDirectly',
    'enableAllWrong', (study_config::json)->'enableAllWrong',
    'asrPassRule', CASE 
        WHEN (study_config::json->>'asrPassRule') = '100' THEN 'ALL'
        WHEN (study_config::json->>'asrPassRule') = '80' THEN 'HALF'
        ELSE 'ONE'
    END,
    'walkman', (study_config::json)->'walkman'
)::text
WHERE study_config IS NOT NULL AND study_config <> '';
