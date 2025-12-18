-- 数据库升级脚本：将整数类型的布尔字段转换为PostgreSQL的boolean类型
-- 日期：2025-12-18
-- 说明：PostgreSQL原生支持boolean类型，比使用整数(0/1)更规范
-- 可重复执行：脚本会检查字段类型，只在需要时才执行转换

-- user表的布尔字段
DO $$
BEGIN
    -- learning_finished
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'learning_finished' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN learning_finished TYPE boolean USING (learning_finished::int::boolean);
    END IF;

    -- invite_award_taken
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'invite_award_taken' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN invite_award_taken TYPE boolean USING (invite_award_taken::int::boolean);
    END IF;

    -- is_super_admin
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'is_super_admin' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN is_super_admin TYPE boolean USING (is_super_admin::int::boolean);
    END IF;

    -- is_admin
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'is_admin' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN is_admin TYPE boolean USING (is_admin::int::boolean);
    END IF;

    -- is_inputor
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'is_inputor' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN is_inputor TYPE boolean USING (is_inputor::int::boolean);
    END IF;

    -- is_sys_user
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'is_sys_user' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN is_sys_user TYPE boolean USING (is_sys_user::int::boolean);
    END IF;

    -- auto_play_sentence
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'auto_play_sentence' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN auto_play_sentence TYPE boolean USING (auto_play_sentence::int::boolean);
    END IF;

    -- show_answers_directly
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'show_answers_directly' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN show_answers_directly TYPE boolean USING (show_answers_directly::int::boolean);
    END IF;

    -- auto_play_word
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'auto_play_word' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN auto_play_word TYPE boolean USING (auto_play_word::int::boolean);
    END IF;

    -- enable_all_wrong
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'enable_all_wrong' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN enable_all_wrong TYPE boolean USING (enable_all_wrong::int::boolean);
    END IF;

    -- is_premium_ios
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'user' 
               AND column_name = 'is_premium_ios' 
               AND data_type != 'boolean') THEN
        ALTER TABLE "user" ALTER COLUMN is_premium_ios TYPE boolean USING (is_premium_ios::int::boolean);
    END IF;
END $$;

-- dict表的布尔字段
DO $$
BEGIN
    -- is_shared
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'dict' 
               AND column_name = 'is_shared' 
               AND data_type != 'boolean') THEN
        ALTER TABLE dict ALTER COLUMN is_shared TYPE boolean USING (is_shared::int::boolean);
    END IF;

    -- is_ready
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'dict' 
               AND column_name = 'is_ready' 
               AND data_type != 'boolean') THEN
        ALTER TABLE dict ALTER COLUMN is_ready TYPE boolean USING (is_ready::int::boolean);
    END IF;

    -- visible
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'dict' 
               AND column_name = 'visible' 
               AND data_type != 'boolean') THEN
        ALTER TABLE dict ALTER COLUMN visible TYPE boolean USING (visible::int::boolean);
    END IF;
END $$;

-- sentence表的布尔字段
DO $$
BEGIN
    -- need_tts
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'sentence' 
               AND column_name = 'need_tts' 
               AND data_type != 'boolean') THEN
        ALTER TABLE sentence ALTER COLUMN need_tts TYPE boolean USING (need_tts::int::boolean);
    END IF;

    -- is_updating (如果存在)
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'sentence' 
               AND column_name = 'is_updating' 
               AND data_type != 'boolean') THEN
        ALTER TABLE sentence ALTER COLUMN is_updating TYPE boolean USING (is_updating::int::boolean);
    END IF;
END $$;

-- meaning_item表的布尔字段
DO $$
BEGIN
    -- is_updating (如果存在)
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'meaning_item' 
               AND column_name = 'is_updating' 
               AND data_type != 'boolean') THEN
        ALTER TABLE meaning_item ALTER COLUMN is_updating TYPE boolean USING (is_updating::int::boolean);
    END IF;
END $$;

-- msg表的布尔字段
DO $$
BEGIN
    -- viewed
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'msg' 
               AND column_name = 'viewed' 
               AND data_type != 'boolean') THEN
        ALTER TABLE msg ALTER COLUMN viewed TYPE boolean USING (viewed::int::boolean);
    END IF;
END $$;

-- learning_dict表的布尔字段
DO $$
BEGIN
    -- is_privileged
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'learning_dict' 
               AND column_name = 'is_privileged' 
               AND data_type != 'boolean') THEN
        ALTER TABLE learning_dict ALTER COLUMN is_privileged TYPE boolean USING (is_privileged::int::boolean);
    END IF;

    -- fetch_mastered
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'learning_dict' 
               AND column_name = 'fetch_mastered' 
               AND data_type != 'boolean') THEN
        ALTER TABLE learning_dict ALTER COLUMN fetch_mastered TYPE boolean USING (fetch_mastered::int::boolean);
    END IF;
END $$;

-- learning_word表的布尔字段
DO $$
BEGIN
    -- is_today_new_word
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'learning_word' 
               AND column_name = 'is_today_new_word' 
               AND data_type != 'boolean') THEN
        ALTER TABLE learning_word ALTER COLUMN is_today_new_word TYPE boolean USING (is_today_new_word::int::boolean);
    END IF;
END $$;

-- error_report表的布尔字段
DO $$
BEGIN
    -- fixed
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'error_report' 
               AND column_name = 'fixed' 
               AND data_type != 'boolean') THEN
        ALTER TABLE error_report ALTER COLUMN fixed TYPE boolean USING (fixed::int::boolean);
    END IF;
END $$;

-- email_verification_code表的布尔字段
DO $$
BEGIN
    -- used
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'email_verification_code' 
               AND column_name = 'used' 
               AND data_type != 'boolean') THEN
        ALTER TABLE email_verification_code ALTER COLUMN used TYPE boolean USING (used::int::boolean);
    END IF;
END $$;

-- sms_verification_code表的布尔字段
DO $$
BEGIN
    -- used
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = current_schema() 
               AND table_name = 'sms_verification_code' 
               AND column_name = 'used' 
               AND data_type != 'boolean') THEN
        ALTER TABLE sms_verification_code ALTER COLUMN used TYPE boolean USING (used::int::boolean);
    END IF;
END $$;
