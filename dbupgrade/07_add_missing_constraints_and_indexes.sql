-- 数据库升级脚本：为 PostgreSQL 补齐主键/唯一约束/索引/外键
-- 说明：根据 MySQL DDL（/tmp/bdc.sql）生成；可重复执行；若数据不满足约束会报错
-- 注意：先补 PK/UK，再补 FK（避免引用表尚无唯一键导致失败）

SET search_path TO public;

DO $$
BEGIN
  -- ===== Phase 1: Primary Keys & Unique Constraints =====
  -- article
  IF to_regclass('public.article') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.article')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.article ADD CONSTRAINT pk_article_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- book_mark
  IF to_regclass('public.book_mark') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.book_mark')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.book_mark ADD CONSTRAINT pk_book_mark_book_mark_name_user_id PRIMARY KEY (book_mark_name, user_id)';
    END IF;
  END IF;
  -- cigen
  IF to_regclass('public.cigen') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.cigen')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.cigen ADD CONSTRAINT pk_cigen_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- cigen_word_link
  IF to_regclass('public.cigen_word_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.cigen_word_link')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.cigen_word_link ADD CONSTRAINT pk_cigen_word_link_cigen_id_word_id PRIMARY KEY (cigen_id, word_id)';
    END IF;
  END IF;
  -- daka
  IF to_regclass('public.daka') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.daka')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.daka ADD CONSTRAINT pk_daka_for_learning_date_user_id PRIMARY KEY (for_learning_date, user_id)';
    END IF;
  END IF;
  -- dict
  IF to_regclass('public.dict') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.dict')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.dict ADD CONSTRAINT pk_dict_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_dict_dict_owner_idx' AND conrelid = ('public.dict')::regclass) THEN
      EXECUTE 'ALTER TABLE public.dict ADD CONSTRAINT uk_dict_dict_owner_idx UNIQUE (owner_id, name)';
    END IF;
  END IF;
  -- dict_group
  IF to_regclass('public.dict_group') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.dict_group')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.dict_group ADD CONSTRAINT pk_dict_group_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- dict_word
  IF to_regclass('public.dict_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.dict_word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.dict_word ADD CONSTRAINT pk_dict_word_dict_id_word_id PRIMARY KEY (dict_id, word_id)';
    END IF;
  END IF;
  -- email_verification_code
  IF to_regclass('public.email_verification_code') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.email_verification_code')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.email_verification_code ADD CONSTRAINT pk_email_verification_code_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- error_report
  IF to_regclass('public.error_report') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.error_report')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.error_report ADD CONSTRAINT pk_error_report_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- event
  IF to_regclass('public."event"') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public."event"')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT pk_event_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- feature_request
  IF to_regclass('public.feature_request') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.feature_request')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.feature_request ADD CONSTRAINT pk_feature_request_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- feature_request_report
  IF to_regclass('public.feature_request_report') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.feature_request_report')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.feature_request_report ADD CONSTRAINT pk_feature_request_report_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- feature_request_vote
  IF to_regclass('public.feature_request_vote') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.feature_request_vote')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.feature_request_vote ADD CONSTRAINT pk_feature_request_vote_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_feature_request_vote_unique_request_user' AND conrelid = ('public.feature_request_vote')::regclass) THEN
      EXECUTE 'ALTER TABLE public.feature_request_vote ADD CONSTRAINT uk_feature_request_vote_unique_request_user UNIQUE (request_id, user_id)';
    END IF;
  END IF;
  -- forum
  IF to_regclass('public.forum') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.forum')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.forum ADD CONSTRAINT pk_forum_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- forum_post
  IF to_regclass('public.forum_post') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.forum_post')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.forum_post ADD CONSTRAINT pk_forum_post_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- forum_post_reply
  IF to_regclass('public.forum_post_reply') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.forum_post_reply')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.forum_post_reply ADD CONSTRAINT pk_forum_post_reply_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- game_hall
  IF to_regclass('public.game_hall') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.game_hall')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.game_hall ADD CONSTRAINT pk_game_hall_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- get_pwd_log
  IF to_regclass('public.get_pwd_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.get_pwd_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.get_pwd_log ADD CONSTRAINT pk_get_pwd_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- hall_group
  IF to_regclass('public.hall_group') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.hall_group')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.hall_group ADD CONSTRAINT pk_hall_group_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- id_gen
  IF to_regclass('public.id_gen') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.id_gen')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.id_gen ADD CONSTRAINT pk_id_gen_sequence_name PRIMARY KEY (sequence_name)';
    END IF;
  END IF;
  -- info_vote_log
  IF to_regclass('public.info_vote_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.info_vote_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.info_vote_log ADD CONSTRAINT pk_info_vote_log_info_id_user_id PRIMARY KEY (info_id, user_id)';
    END IF;
  END IF;
  -- learning_dict
  IF to_regclass('public.learning_dict') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.learning_dict')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.learning_dict ADD CONSTRAINT pk_learning_dict_dict_id_user_id PRIMARY KEY (dict_id, user_id)';
    END IF;
  END IF;
  -- learning_word
  IF to_regclass('public.learning_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.learning_word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.learning_word ADD CONSTRAINT pk_learning_word_user_id_word_id PRIMARY KEY (user_id, word_id)';
    END IF;
  END IF;
  -- level
  IF to_regclass('public."level"') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public."level"')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public."level" ADD CONSTRAINT pk_level_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- login_log
  IF to_regclass('public.login_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.login_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.login_log ADD CONSTRAINT pk_login_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- mastered_word
  IF to_regclass('public.mastered_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.mastered_word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.mastered_word ADD CONSTRAINT pk_mastered_word_user_id_word_id PRIMARY KEY (user_id, word_id)';
    END IF;
  END IF;
  -- meaning_item
  IF to_regclass('public.meaning_item') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.meaning_item')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.meaning_item ADD CONSTRAINT pk_meaning_item_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- msg
  IF to_regclass('public.msg') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.msg')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.msg ADD CONSTRAINT pk_msg_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sentence
  IF to_regclass('public.sentence') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sentence')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sentence ADD CONSTRAINT pk_sentence_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sentence_chinese
  IF to_regclass('public.sentence_chinese') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sentence_chinese')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese ADD CONSTRAINT pk_sentence_chinese_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sentence_chinese_remark
  IF to_regclass('public.sentence_chinese_remark') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sentence_chinese_remark')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese_remark ADD CONSTRAINT pk_sentence_chinese_remark_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sentence_update_notify
  IF to_regclass('public.sentence_update_notify') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sentence_update_notify')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sentence_update_notify ADD CONSTRAINT pk_sentence_update_notify_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- similar_word
  IF to_regclass('public.similar_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.similar_word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.similar_word ADD CONSTRAINT pk_similar_word_word_id_similar_word_id PRIMARY KEY (word_id, similar_word_id)';
    END IF;
  END IF;
  -- sms_verification_code
  IF to_regclass('public.sms_verification_code') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sms_verification_code')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sms_verification_code ADD CONSTRAINT pk_sms_verification_code_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- study_group
  IF to_regclass('public.study_group') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.study_group')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.study_group ADD CONSTRAINT pk_study_group_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_study_group_uk_jpg0rl0cauvsfe6doei229ae1' AND conrelid = ('public.study_group')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group ADD CONSTRAINT uk_study_group_uk_jpg0rl0cauvsfe6doei229ae1 UNIQUE (group_name)';
    END IF;
  END IF;
  -- study_group_grade
  IF to_regclass('public.study_group_grade') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.study_group_grade')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.study_group_grade ADD CONSTRAINT pk_study_group_grade_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_study_group_grade_uk_grr4fesaas4otr2jq0t2xh7ye' AND conrelid = ('public.study_group_grade')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_grade ADD CONSTRAINT uk_study_group_grade_uk_grr4fesaas4otr2jq0t2xh7ye UNIQUE (name)';
    END IF;
  END IF;
  -- study_group_post
  IF to_regclass('public.study_group_post') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.study_group_post')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.study_group_post ADD CONSTRAINT pk_study_group_post_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- study_group_post_reply
  IF to_regclass('public.study_group_post_reply') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.study_group_post_reply')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.study_group_post_reply ADD CONSTRAINT pk_study_group_post_reply_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- study_group_snapshot_daily
  IF to_regclass('public.study_group_snapshot_daily') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.study_group_snapshot_daily')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.study_group_snapshot_daily ADD CONSTRAINT pk_study_group_snapshot_daily_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- synonym
  IF to_regclass('public.synonym') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.synonym')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.synonym ADD CONSTRAINT pk_synonym_meaning_item_id_word_id PRIMARY KEY (meaning_item_id, word_id)';
    END IF;
  END IF;
  -- sys_db_log
  IF to_regclass('public.sys_db_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sys_db_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sys_db_log ADD CONSTRAINT pk_sys_db_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sys_db_version
  IF to_regclass('public.sys_db_version') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sys_db_version')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sys_db_version ADD CONSTRAINT pk_sys_db_version_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- sys_param
  IF to_regclass('public.sys_param') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.sys_param')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.sys_param ADD CONSTRAINT pk_sys_param_param_name PRIMARY KEY (param_name)';
    END IF;
  END IF;
  -- update_log
  IF to_regclass('public.update_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.update_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.update_log ADD CONSTRAINT pk_update_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- user
  IF to_regclass('public."user"') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public."user"')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT pk_user_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_user_idx_user_name' AND conrelid = ('public."user"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT uk_user_idx_user_name UNIQUE (user_name)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_user_user_email_idx' AND conrelid = ('public."user"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT uk_user_user_email_idx UNIQUE (email)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_user_idx_wechat_open_id' AND conrelid = ('public."user"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT uk_user_idx_wechat_open_id UNIQUE (wechat_open_id)';
    END IF;
  END IF;
  -- user_cow_dung_log
  IF to_regclass('public.user_cow_dung_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_cow_dung_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_cow_dung_log ADD CONSTRAINT pk_user_cow_dung_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- user_db_log
  IF to_regclass('public.user_db_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_db_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_db_log ADD CONSTRAINT pk_user_db_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- user_db_version
  IF to_regclass('public.user_db_version') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_db_version')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_db_version ADD CONSTRAINT pk_user_db_version_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_user_db_version_unique_user_id' AND conrelid = ('public.user_db_version')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_db_version ADD CONSTRAINT uk_user_db_version_unique_user_id UNIQUE (user_id)';
    END IF;
  END IF;
  -- user_game
  IF to_regclass('public.user_game') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_game')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_game ADD CONSTRAINT pk_user_game_game_user_id PRIMARY KEY (game, user_id)';
    END IF;
  END IF;
  -- user_oper
  IF to_regclass('public.user_oper') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_oper')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_oper ADD CONSTRAINT pk_user_oper_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- user_score_log
  IF to_regclass('public.user_score_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_score_log')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_score_log ADD CONSTRAINT pk_user_score_log_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- user_snapshot_daily
  IF to_regclass('public.user_snapshot_daily') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_snapshot_daily')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_snapshot_daily ADD CONSTRAINT pk_user_snapshot_daily_the_date_user_id PRIMARY KEY (the_date, user_id)';
    END IF;
  END IF;
  -- user_study_record
  IF to_regclass('public.user_study_record') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_study_record')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_study_record ADD CONSTRAINT pk_user_study_record_the_date_user_id PRIMARY KEY (the_date, user_id)';
    END IF;
  END IF;
  -- user_study_step
  IF to_regclass('public.user_study_step') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_study_step')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_study_step ADD CONSTRAINT pk_user_study_step_study_step_user_id PRIMARY KEY (study_step, user_id)';
    END IF;
  END IF;
  -- user_wrong_word
  IF to_regclass('public.user_wrong_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.user_wrong_word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.user_wrong_word ADD CONSTRAINT pk_user_wrong_word_user_id_word_id PRIMARY KEY (user_id, word_id)';
    END IF;
  END IF;
  -- verb_tense
  IF to_regclass('public.verb_tense') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.verb_tense')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.verb_tense ADD CONSTRAINT pk_verb_tense_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- word
  IF to_regclass('public.word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.word')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.word ADD CONSTRAINT pk_word_id PRIMARY KEY (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_word_idx_wordspell' AND conrelid = ('public.word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word ADD CONSTRAINT uk_word_idx_wordspell UNIQUE (spell)';
    END IF;
  END IF;
  -- word_additional_info
  IF to_regclass('public.word_additional_info') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.word_additional_info')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.word_additional_info ADD CONSTRAINT pk_word_additional_info_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- word_image
  IF to_regclass('public.word_image') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.word_image')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.word_image ADD CONSTRAINT pk_word_image_id PRIMARY KEY (id)';
    END IF;
  END IF;
  -- word_sentence
  IF to_regclass('public.word_sentence') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.word_sentence')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.word_sentence ADD CONSTRAINT pk_word_sentence_sentence_id_word_id PRIMARY KEY (sentence_id, word_id)';
    END IF;
  END IF;
  -- word_shortdesc_chinese
  IF to_regclass('public.word_shortdesc_chinese') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = ('public.word_shortdesc_chinese')::regclass AND contype = 'p') THEN
      EXECUTE 'ALTER TABLE public.word_shortdesc_chinese ADD CONSTRAINT pk_word_shortdesc_chinese_id PRIMARY KEY (id)';
    END IF;
  END IF;
END
$$;

DO $$
BEGIN
  -- ===== Phase 2: Foreign Keys =====
  -- article
  IF to_regclass('public.article') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_article_fkdw5d9vdw43e3nvtpqk8l4iitp' AND conrelid = ('public.article')::regclass) THEN
      EXECUTE 'ALTER TABLE public.article ADD CONSTRAINT fk_article_fkdw5d9vdw43e3nvtpqk8l4iitp FOREIGN KEY (author) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- book_mark
  IF to_regclass('public.book_mark') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_book_mark_book_mark_user_fk' AND conrelid = ('public.book_mark')::regclass) THEN
      EXECUTE 'ALTER TABLE public.book_mark ADD CONSTRAINT fk_book_mark_book_mark_user_fk FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- cigen_word_link
  IF to_regclass('public.cigen_word_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cigen_word_link_fkfg6o4pg8ran0btsx0fl4v53wt' AND conrelid = ('public.cigen_word_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.cigen_word_link ADD CONSTRAINT fk_cigen_word_link_fkfg6o4pg8ran0btsx0fl4v53wt FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cigen_word_link_fksbo1vxf9xm27mmqfeuytgjm8r' AND conrelid = ('public.cigen_word_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.cigen_word_link ADD CONSTRAINT fk_cigen_word_link_fksbo1vxf9xm27mmqfeuytgjm8r FOREIGN KEY (cigen_id) REFERENCES public.cigen (id)';
    END IF;
  END IF;
  -- daka
  IF to_regclass('public.daka') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_daka_fk9lw3569kklr2aem8j3lgooofo' AND conrelid = ('public.daka')::regclass) THEN
      EXECUTE 'ALTER TABLE public.daka ADD CONSTRAINT fk_daka_fk9lw3569kklr2aem8j3lgooofo FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- dict
  IF to_regclass('public.dict') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_dict_fkba1lo3o2pqjwuhuo55a173tpn' AND conrelid = ('public.dict')::regclass) THEN
      EXECUTE 'ALTER TABLE public.dict ADD CONSTRAINT fk_dict_fkba1lo3o2pqjwuhuo55a173tpn FOREIGN KEY (owner_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- dict_group
  IF to_regclass('public.dict_group') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_dict_group_fkam1kwdtewl5mj4w24i0vjsgvr' AND conrelid = ('public.dict_group')::regclass) THEN
      EXECUTE 'ALTER TABLE public.dict_group ADD CONSTRAINT fk_dict_group_fkam1kwdtewl5mj4w24i0vjsgvr FOREIGN KEY (parent_id) REFERENCES public.dict_group (id)';
    END IF;
  END IF;
  -- dict_word
  IF to_regclass('public.dict_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_dict_word_fkhyb2ixqpghb6s7ksefrm42kfa' AND conrelid = ('public.dict_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.dict_word ADD CONSTRAINT fk_dict_word_fkhyb2ixqpghb6s7ksefrm42kfa FOREIGN KEY (dict_id) REFERENCES public.dict (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_dict_word_fkoocgndgdxfsmi9l22c779ve5f' AND conrelid = ('public.dict_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.dict_word ADD CONSTRAINT fk_dict_word_fkoocgndgdxfsmi9l22c779ve5f FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- error_report
  IF to_regclass('public.error_report') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_error_report_fkt63m0vobg7664cjmoyuwngl2r' AND conrelid = ('public.error_report')::regclass) THEN
      EXECUTE 'ALTER TABLE public.error_report ADD CONSTRAINT fk_error_report_fkt63m0vobg7664cjmoyuwngl2r FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- event
  IF to_regclass('public."event"') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_fk8up0cm0j7flyds8mljh3wslcs' AND conrelid = ('public."event"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT fk_event_fk8up0cm0j7flyds8mljh3wslcs FOREIGN KEY (word_short_desc_chinese_id) REFERENCES public.word_shortdesc_chinese (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_fk8y4063ul9igji7dsmq61t7pg3' AND conrelid = ('public."event"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT fk_event_fk8y4063ul9igji7dsmq61t7pg3 FOREIGN KEY (sentence_chinese_id) REFERENCES public.sentence_chinese (id) ON DELETE CASCADE ON UPDATE RESTRICT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_fkcaqnogrpoabtlfqf9h4wuxybk' AND conrelid = ('public."event"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT fk_event_fkcaqnogrpoabtlfqf9h4wuxybk FOREIGN KEY (sentence_id) REFERENCES public.sentence (id) ON DELETE CASCADE ON UPDATE RESTRICT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_fke4y90yg6c4gxbdwn2w9lgcb98' AND conrelid = ('public."event"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT fk_event_fke4y90yg6c4gxbdwn2w9lgcb98 FOREIGN KEY (word_image_id) REFERENCES public.word_image (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_event_fkn0s3foajghecveph3do4wqngk' AND conrelid = ('public."event"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."event" ADD CONSTRAINT fk_event_fkn0s3foajghecveph3do4wqngk FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- feature_request
  IF to_regclass('public.feature_request') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_feature_request_fk_feature_request_creator' AND conrelid = ('public.feature_request')::regclass) THEN
      EXECUTE 'ALTER TABLE public.feature_request ADD CONSTRAINT fk_feature_request_fk_feature_request_creator FOREIGN KEY (creator_id) REFERENCES public."user" (id) ON DELETE CASCADE';
    END IF;
  END IF;
  -- feature_request_vote
  IF to_regclass('public.feature_request_vote') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_feature_request_vote_fk_feature_request_vote_request' AND conrelid = ('public.feature_request_vote')::regclass) THEN
      EXECUTE 'ALTER TABLE public.feature_request_vote ADD CONSTRAINT fk_feature_request_vote_fk_feature_request_vote_request FOREIGN KEY (request_id) REFERENCES public.feature_request (id) ON DELETE CASCADE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_feature_request_vote_fk_feature_request_vote_user' AND conrelid = ('public.feature_request_vote')::regclass) THEN
      EXECUTE 'ALTER TABLE public.feature_request_vote ADD CONSTRAINT fk_feature_request_vote_fk_feature_request_vote_user FOREIGN KEY (user_id) REFERENCES public."user" (id) ON DELETE CASCADE';
    END IF;
  END IF;
  -- forum_and_manager_link
  IF to_regclass('public.forum_and_manager_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_and_manager_link_fk4rgldqqyj2v6ko5fb3j4h00hw' AND conrelid = ('public.forum_and_manager_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_and_manager_link ADD CONSTRAINT fk_forum_and_manager_link_fk4rgldqqyj2v6ko5fb3j4h00hw FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_and_manager_link_fkm2ne0gyp8to1iltn9y5xatn5g' AND conrelid = ('public.forum_and_manager_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_and_manager_link ADD CONSTRAINT fk_forum_and_manager_link_fkm2ne0gyp8to1iltn9y5xatn5g FOREIGN KEY (forum_id) REFERENCES public.forum (id)';
    END IF;
  END IF;
  -- forum_post
  IF to_regclass('public.forum_post') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_post_fk89ba00sxrqhbgl7cgwt6y0tux' AND conrelid = ('public.forum_post')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_post ADD CONSTRAINT fk_forum_post_fk89ba00sxrqhbgl7cgwt6y0tux FOREIGN KEY (post_creator_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_post_fkh0s5a90088gbywb9u9j5fase4' AND conrelid = ('public.forum_post')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_post ADD CONSTRAINT fk_forum_post_fkh0s5a90088gbywb9u9j5fase4 FOREIGN KEY (forum_id) REFERENCES public.forum (id)';
    END IF;
  END IF;
  -- forum_post_reply
  IF to_regclass('public.forum_post_reply') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_post_reply_fkctt5g9ionoo960lak0p7ss6ou' AND conrelid = ('public.forum_post_reply')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_post_reply ADD CONSTRAINT fk_forum_post_reply_fkctt5g9ionoo960lak0p7ss6ou FOREIGN KEY (post_replyer_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_forum_post_reply_fksmolky8m77uf3aygscwtlh7' AND conrelid = ('public.forum_post_reply')::regclass) THEN
      EXECUTE 'ALTER TABLE public.forum_post_reply ADD CONSTRAINT fk_forum_post_reply_fksmolky8m77uf3aygscwtlh7 FOREIGN KEY (post_id) REFERENCES public.forum_post (id)';
    END IF;
  END IF;
  -- game_hall
  IF to_regclass('public.game_hall') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_game_hall_fkbb8bsyk402u3fxe0vnv2ecp12' AND conrelid = ('public.game_hall')::regclass) THEN
      EXECUTE 'ALTER TABLE public.game_hall ADD CONSTRAINT fk_game_hall_fkbb8bsyk402u3fxe0vnv2ecp12 FOREIGN KEY (dict_group_id) REFERENCES public.dict_group (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_game_hall_fks184ekmq8ct8x9etyonngejo4' AND conrelid = ('public.game_hall')::regclass) THEN
      EXECUTE 'ALTER TABLE public.game_hall ADD CONSTRAINT fk_game_hall_fks184ekmq8ct8x9etyonngejo4 FOREIGN KEY (hall_group_id) REFERENCES public.hall_group (id)';
    END IF;
  END IF;
  -- group_and_dict_link
  IF to_regclass('public.group_and_dict_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_group_and_dict_link_fkanvwboyqdce5mb41j8q4qly3c' AND conrelid = ('public.group_and_dict_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.group_and_dict_link ADD CONSTRAINT fk_group_and_dict_link_fkanvwboyqdce5mb41j8q4qly3c FOREIGN KEY (group_id) REFERENCES public.dict_group (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_group_and_dict_link_fkhuoc8hxjs2c8w1fgickojg6ff' AND conrelid = ('public.group_and_dict_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.group_and_dict_link ADD CONSTRAINT fk_group_and_dict_link_fkhuoc8hxjs2c8w1fgickojg6ff FOREIGN KEY (dict_id) REFERENCES public.dict (id)';
    END IF;
  END IF;
  -- info_vote_log
  IF to_regclass('public.info_vote_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_info_vote_log_fknyxodwmjasis1v8c04xsen7dh' AND conrelid = ('public.info_vote_log')::regclass) THEN
      EXECUTE 'ALTER TABLE public.info_vote_log ADD CONSTRAINT fk_info_vote_log_fknyxodwmjasis1v8c04xsen7dh FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_info_vote_log_fkq3tlgwcmlq54suls4sv2vh9xa' AND conrelid = ('public.info_vote_log')::regclass) THEN
      EXECUTE 'ALTER TABLE public.info_vote_log ADD CONSTRAINT fk_info_vote_log_fkq3tlgwcmlq54suls4sv2vh9xa FOREIGN KEY (info_id) REFERENCES public.word_additional_info (id)';
    END IF;
  END IF;
  -- learning_dict
  IF to_regclass('public.learning_dict') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_learning_dict_fkoaoie5gcg9b8xulawdoaoa4rt' AND conrelid = ('public.learning_dict')::regclass) THEN
      EXECUTE 'ALTER TABLE public.learning_dict ADD CONSTRAINT fk_learning_dict_fkoaoie5gcg9b8xulawdoaoa4rt FOREIGN KEY (dict_id) REFERENCES public.dict (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_learning_dict_fkpiu1chqdc7gn2bchpkxcbdqu6' AND conrelid = ('public.learning_dict')::regclass) THEN
      EXECUTE 'ALTER TABLE public.learning_dict ADD CONSTRAINT fk_learning_dict_fkpiu1chqdc7gn2bchpkxcbdqu6 FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_learning_dict_fks6prwtgob6wmhxysa8bu1096r' AND conrelid = ('public.learning_dict')::regclass) THEN
      EXECUTE 'ALTER TABLE public.learning_dict ADD CONSTRAINT fk_learning_dict_fks6prwtgob6wmhxysa8bu1096r FOREIGN KEY (current_word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- learning_word
  IF to_regclass('public.learning_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_learning_word_fkpqcu8nmvm7ap2971ok6vs3s0n' AND conrelid = ('public.learning_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.learning_word ADD CONSTRAINT fk_learning_word_fkpqcu8nmvm7ap2971ok6vs3s0n FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- login_log
  IF to_regclass('public.login_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_login_log_fk9auh6uhsrknd75ipjypyyha90' AND conrelid = ('public.login_log')::regclass) THEN
      EXECUTE 'ALTER TABLE public.login_log ADD CONSTRAINT fk_login_log_fk9auh6uhsrknd75ipjypyyha90 FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- mastered_word
  IF to_regclass('public.mastered_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_mastered_word_fkkx3r0klb1on3xmbmp40dqwrmh' AND conrelid = ('public.mastered_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.mastered_word ADD CONSTRAINT fk_mastered_word_fkkx3r0klb1on3xmbmp40dqwrmh FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- meaning_item
  IF to_regclass('public.meaning_item') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_meaning_item_fkbq1kwqm7l14nowpnkgyct7qmb' AND conrelid = ('public.meaning_item')::regclass) THEN
      EXECUTE 'ALTER TABLE public.meaning_item ADD CONSTRAINT fk_meaning_item_fkbq1kwqm7l14nowpnkgyct7qmb FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_meaning_item_fkhajsfsxiyna9xuo9i974u8v07' AND conrelid = ('public.meaning_item')::regclass) THEN
      EXECUTE 'ALTER TABLE public.meaning_item ADD CONSTRAINT fk_meaning_item_fkhajsfsxiyna9xuo9i974u8v07 FOREIGN KEY (dict_id) REFERENCES public.dict (id)';
    END IF;
  END IF;
  -- msg
  IF to_regclass('public.msg') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_msg_fkduaesr28u3xkjgacqyp6f9k69' AND conrelid = ('public.msg')::regclass) THEN
      EXECUTE 'ALTER TABLE public.msg ADD CONSTRAINT fk_msg_fkduaesr28u3xkjgacqyp6f9k69 FOREIGN KEY (to_user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_msg_fkpwao1csk2fiqn8x0taf5n4lxp' AND conrelid = ('public.msg')::regclass) THEN
      EXECUTE 'ALTER TABLE public.msg ADD CONSTRAINT fk_msg_fkpwao1csk2fiqn8x0taf5n4lxp FOREIGN KEY (from_user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- sentence
  IF to_regclass('public.sentence') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_fkjsrw5reghdvpvf7rghvlpg8oo' AND conrelid = ('public.sentence')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence ADD CONSTRAINT fk_sentence_fkjsrw5reghdvpvf7rghvlpg8oo FOREIGN KEY (author_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_fknmsdsdecrpllmjlp39xpxnj1d' AND conrelid = ('public.sentence')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence ADD CONSTRAINT fk_sentence_fknmsdsdecrpllmjlp39xpxnj1d FOREIGN KEY (meaning_item_id) REFERENCES public.meaning_item (id)';
    END IF;
  END IF;
  -- sentence_chinese
  IF to_regclass('public.sentence_chinese') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_chinese_fk1ea8mppmrgwbn1gcmn0n4s95n' AND conrelid = ('public.sentence_chinese')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese ADD CONSTRAINT fk_sentence_chinese_fk1ea8mppmrgwbn1gcmn0n4s95n FOREIGN KEY (author) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_chinese_fk4qkl23fg27sp450b9h3n7xnwx' AND conrelid = ('public.sentence_chinese')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese ADD CONSTRAINT fk_sentence_chinese_fk4qkl23fg27sp450b9h3n7xnwx FOREIGN KEY (sentence_id) REFERENCES public.sentence (id) ON DELETE CASCADE ON UPDATE RESTRICT';
    END IF;
  END IF;
  -- sentence_chinese_remark
  IF to_regclass('public.sentence_chinese_remark') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_chinese_remark_fk9eseuj1b3lp9r0cp52hl524i7' AND conrelid = ('public.sentence_chinese_remark')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese_remark ADD CONSTRAINT fk_sentence_chinese_remark_fk9eseuj1b3lp9r0cp52hl524i7 FOREIGN KEY (chinese_id) REFERENCES public.sentence_chinese (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_chinese_remark_fkqb6gj27jt2kffko46xcctg0u6' AND conrelid = ('public.sentence_chinese_remark')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence_chinese_remark ADD CONSTRAINT fk_sentence_chinese_remark_fkqb6gj27jt2kffko46xcctg0u6 FOREIGN KEY (author) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- sentence_update_notify
  IF to_regclass('public.sentence_update_notify') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_sentence_update_notify_fkstugsayfi283agk001cvp8tys' AND conrelid = ('public.sentence_update_notify')::regclass) THEN
      EXECUTE 'ALTER TABLE public.sentence_update_notify ADD CONSTRAINT fk_sentence_update_notify_fkstugsayfi283agk001cvp8tys FOREIGN KEY (sentence_id) REFERENCES public.sentence (id)';
    END IF;
  END IF;
  -- similar_word
  IF to_regclass('public.similar_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_similar_word_fk1mqflio4f1yp8ety4wsa8naku' AND conrelid = ('public.similar_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.similar_word ADD CONSTRAINT fk_similar_word_fk1mqflio4f1yp8ety4wsa8naku FOREIGN KEY (similar_word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_similar_word_fkcwlj8g7yxqfqag6sbcypi705a' AND conrelid = ('public.similar_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.similar_word ADD CONSTRAINT fk_similar_word_fkcwlj8g7yxqfqag6sbcypi705a FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- study_group
  IF to_regclass('public.study_group') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_fk36s0562yu4gydy3xr28u95eqd' AND conrelid = ('public.study_group')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group ADD CONSTRAINT fk_study_group_fk36s0562yu4gydy3xr28u95eqd FOREIGN KEY (grade_id) REFERENCES public.study_group_grade (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_fkfml3yg6yg9a2xi45w4vx7dqfb' AND conrelid = ('public.study_group')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group ADD CONSTRAINT fk_study_group_fkfml3yg6yg9a2xi45w4vx7dqfb FOREIGN KEY (creator_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- study_group_and_manager_link
  IF to_regclass('public.study_group_and_manager_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_and_manager_link_fkgfviie87tlf3c34ipmx31ynj7' AND conrelid = ('public.study_group_and_manager_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_and_manager_link ADD CONSTRAINT fk_study_group_and_manager_link_fkgfviie87tlf3c34ipmx31ynj7 FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_and_manager_link_fkrdflptnxblu6aa5r7s9747ko4' AND conrelid = ('public.study_group_and_manager_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_and_manager_link ADD CONSTRAINT fk_study_group_and_manager_link_fkrdflptnxblu6aa5r7s9747ko4 FOREIGN KEY (group_id) REFERENCES public.study_group (id)';
    END IF;
  END IF;
  -- study_group_and_user_link
  IF to_regclass('public.study_group_and_user_link') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_and_user_link_fk66ybol3y7m0xgvon3hovu9ifv' AND conrelid = ('public.study_group_and_user_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_and_user_link ADD CONSTRAINT fk_study_group_and_user_link_fk66ybol3y7m0xgvon3hovu9ifv FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_and_user_link_fks1c5cfbgl89yn2p955v7sugj7' AND conrelid = ('public.study_group_and_user_link')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_and_user_link ADD CONSTRAINT fk_study_group_and_user_link_fks1c5cfbgl89yn2p955v7sugj7 FOREIGN KEY (group_id) REFERENCES public.study_group (id)';
    END IF;
  END IF;
  -- study_group_post
  IF to_regclass('public.study_group_post') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_post_fkc3t23fo2d1n4cqsq5ct92vtjn' AND conrelid = ('public.study_group_post')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_post ADD CONSTRAINT fk_study_group_post_fkc3t23fo2d1n4cqsq5ct92vtjn FOREIGN KEY (group_id) REFERENCES public.study_group (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_post_fkmy0w3ae9nui45ii8gg5ftx03y' AND conrelid = ('public.study_group_post')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_post ADD CONSTRAINT fk_study_group_post_fkmy0w3ae9nui45ii8gg5ftx03y FOREIGN KEY (post_creator_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- study_group_post_reply
  IF to_regclass('public.study_group_post_reply') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_post_reply_fk302iba0o0rgoegvo0en7a05jl' AND conrelid = ('public.study_group_post_reply')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_post_reply ADD CONSTRAINT fk_study_group_post_reply_fk302iba0o0rgoegvo0en7a05jl FOREIGN KEY (post_id) REFERENCES public.study_group_post (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_post_reply_fklbwltcdwo4x4hlkbl51fpph' AND conrelid = ('public.study_group_post_reply')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_post_reply ADD CONSTRAINT fk_study_group_post_reply_fklbwltcdwo4x4hlkbl51fpph FOREIGN KEY (post_replyer_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- study_group_snapshot_daily
  IF to_regclass('public.study_group_snapshot_daily') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_study_group_snapshot_daily_fks0e3efs4xyt73agwc6e96wjc4' AND conrelid = ('public.study_group_snapshot_daily')::regclass) THEN
      EXECUTE 'ALTER TABLE public.study_group_snapshot_daily ADD CONSTRAINT fk_study_group_snapshot_daily_fks0e3efs4xyt73agwc6e96wjc4 FOREIGN KEY (group_id) REFERENCES public.study_group (id)';
    END IF;
  END IF;
  -- synonym
  IF to_regclass('public.synonym') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_synonym_fkallgsvuhxdjb80476q64s2moe' AND conrelid = ('public.synonym')::regclass) THEN
      EXECUTE 'ALTER TABLE public.synonym ADD CONSTRAINT fk_synonym_fkallgsvuhxdjb80476q64s2moe FOREIGN KEY (meaning_item_id) REFERENCES public.meaning_item (id)';
    END IF;
  END IF;
  -- user
  IF to_regclass('public."user"') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_fk6lqwkmrxl04j2k3d2oqysgwvm' AND conrelid = ('public."user"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT fk_user_fk6lqwkmrxl04j2k3d2oqysgwvm FOREIGN KEY (level_id) REFERENCES public."level" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_fkefu5f2ioj2qy2bycuh6g3wbkd' AND conrelid = ('public."user"')::regclass) THEN
      EXECUTE 'ALTER TABLE public."user" ADD CONSTRAINT fk_user_fkefu5f2ioj2qy2bycuh6g3wbkd FOREIGN KEY (invited_by_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_cow_dung_log
  IF to_regclass('public.user_cow_dung_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_cow_dung_log_fkp01eygbwkg91uujcjasrhbu2y' AND conrelid = ('public.user_cow_dung_log')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_cow_dung_log ADD CONSTRAINT fk_user_cow_dung_log_fkp01eygbwkg91uujcjasrhbu2y FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_db_version
  IF to_regclass('public.user_db_version') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_db_version_fk_user_db_version_user' AND conrelid = ('public.user_db_version')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_db_version ADD CONSTRAINT fk_user_db_version_fk_user_db_version_user FOREIGN KEY (user_id) REFERENCES public."user" (id) ON DELETE CASCADE';
    END IF;
  END IF;
  -- user_game
  IF to_regclass('public.user_game') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_game_fke1j2if58j0qgke4numextbw8a' AND conrelid = ('public.user_game')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_game ADD CONSTRAINT fk_user_game_fke1j2if58j0qgke4numextbw8a FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_oper
  IF to_regclass('public.user_oper') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_oper_fk_user_oper_user' AND conrelid = ('public.user_oper')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_oper ADD CONSTRAINT fk_user_oper_fk_user_oper_user FOREIGN KEY (user_id) REFERENCES public."user" (id) ON DELETE CASCADE';
    END IF;
  END IF;
  -- user_score_log
  IF to_regclass('public.user_score_log') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_score_log_fkn1b5wicvnceas08ju14uk3qqw' AND conrelid = ('public.user_score_log')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_score_log ADD CONSTRAINT fk_user_score_log_fkn1b5wicvnceas08ju14uk3qqw FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_snapshot_daily
  IF to_regclass('public.user_snapshot_daily') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_snapshot_daily_fkm48fwdudlv10kcn0wafvdves3' AND conrelid = ('public.user_snapshot_daily')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_snapshot_daily ADD CONSTRAINT fk_user_snapshot_daily_fkm48fwdudlv10kcn0wafvdves3 FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_study_step
  IF to_regclass('public.user_study_step') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_study_step_fkkb5mbew7a6hawfub12aotlpbh' AND conrelid = ('public.user_study_step')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_study_step ADD CONSTRAINT fk_user_study_step_fkkb5mbew7a6hawfub12aotlpbh FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- user_wrong_word
  IF to_regclass('public.user_wrong_word') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_wrong_word_fkqneibfe99w3ktslncl4vt009k' AND conrelid = ('public.user_wrong_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_wrong_word ADD CONSTRAINT fk_user_wrong_word_fkqneibfe99w3ktslncl4vt009k FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_user_wrong_word_fkwkw9ln2wtbqtq0e7s5ayti2t' AND conrelid = ('public.user_wrong_word')::regclass) THEN
      EXECUTE 'ALTER TABLE public.user_wrong_word ADD CONSTRAINT fk_user_wrong_word_fkwkw9ln2wtbqtq0e7s5ayti2t FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- verb_tense
  IF to_regclass('public.verb_tense') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_verb_tense_fkrymhs6cvyoh40cpcslopn98yo' AND conrelid = ('public.verb_tense')::regclass) THEN
      EXECUTE 'ALTER TABLE public.verb_tense ADD CONSTRAINT fk_verb_tense_fkrymhs6cvyoh40cpcslopn98yo FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- word_additional_info
  IF to_regclass('public.word_additional_info') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_additional_info_fk5jynq4erw7uwlffv3covsa9oc' AND conrelid = ('public.word_additional_info')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_additional_info ADD CONSTRAINT fk_word_additional_info_fk5jynq4erw7uwlffv3covsa9oc FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_additional_info_fkf3xqffcm8vnaqbucfr5i24yqh' AND conrelid = ('public.word_additional_info')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_additional_info ADD CONSTRAINT fk_word_additional_info_fkf3xqffcm8vnaqbucfr5i24yqh FOREIGN KEY (user_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- word_image
  IF to_regclass('public.word_image') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_image_fk22nlb05j0hk398isouqw9ehbc' AND conrelid = ('public.word_image')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_image ADD CONSTRAINT fk_word_image_fk22nlb05j0hk398isouqw9ehbc FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_image_fkcsrc6dqtt1q9907n2w3qcy71v' AND conrelid = ('public.word_image')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_image ADD CONSTRAINT fk_word_image_fkcsrc6dqtt1q9907n2w3qcy71v FOREIGN KEY (author_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
  -- word_sentence
  IF to_regclass('public.word_sentence') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_sentence_fk3ihl69o17ll6saoyahy1iwnml' AND conrelid = ('public.word_sentence')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_sentence ADD CONSTRAINT fk_word_sentence_fk3ihl69o17ll6saoyahy1iwnml FOREIGN KEY (sentence_id) REFERENCES public.sentence (id) ON DELETE CASCADE ON UPDATE RESTRICT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_sentence_fkaqa9an1x12g7s6u92i30raln7' AND conrelid = ('public.word_sentence')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_sentence ADD CONSTRAINT fk_word_sentence_fkaqa9an1x12g7s6u92i30raln7 FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
  END IF;
  -- word_shortdesc_chinese
  IF to_regclass('public.word_shortdesc_chinese') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_shortdesc_chinese_fk662626om3lfe5ov2fohxuqpgp' AND conrelid = ('public.word_shortdesc_chinese')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_shortdesc_chinese ADD CONSTRAINT fk_word_shortdesc_chinese_fk662626om3lfe5ov2fohxuqpgp FOREIGN KEY (word_id) REFERENCES public.word (id)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_word_shortdesc_chinese_fktfaryode4etiv5gh8vr47bnbh' AND conrelid = ('public.word_shortdesc_chinese')::regclass) THEN
      EXECUTE 'ALTER TABLE public.word_shortdesc_chinese ADD CONSTRAINT fk_word_shortdesc_chinese_fktfaryode4etiv5gh8vr47bnbh FOREIGN KEY (author_id) REFERENCES public."user" (id)';
    END IF;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_article_fkdw5d9vdw43e3nvtpqk8l4iitp ON public.article (author);
CREATE INDEX IF NOT EXISTS idx_book_mark_id_xldmdpxpesl4m2anh96p3upne5 ON public.book_mark (user_id);
CREATE INDEX IF NOT EXISTS idx_cigen_word_link_fkfg6o4pg8ran0btsx0fl4v53wt ON public.cigen_word_link (word_id);
CREATE INDEX IF NOT EXISTS idx_daka_fk9lw3569kklr2aem8j3lgooofo ON public.daka (user_id);
CREATE INDEX IF NOT EXISTS idx_dict_fkba1lo3o2pqjwuhuo55a173tpn ON public.dict (owner_id);
CREATE INDEX IF NOT EXISTS idx_dict_group_fkam1kwdtewl5mj4w24i0vjsgvr ON public.dict_group (parent_id);
CREATE INDEX IF NOT EXISTS idx_dict_word_fkoocgndgdxfsmi9l22c779ve5f ON public.dict_word (word_id);
CREATE INDEX IF NOT EXISTS idx_dict_word_idx_dict_seq ON public.dict_word (dict_id, seq);
CREATE INDEX IF NOT EXISTS idx_email_verification_code_idx_email_type ON public.email_verification_code (email, type);
CREATE INDEX IF NOT EXISTS idx_email_verification_code_idx_create_time ON public.email_verification_code (create_time);
CREATE INDEX IF NOT EXISTS idx_error_report_fkt63m0vobg7664cjmoyuwngl2r ON public.error_report (user_id);
CREATE INDEX IF NOT EXISTS idx_event_fkn0s3foajghecveph3do4wqngk ON public."event" (user_id);
CREATE INDEX IF NOT EXISTS idx_event_fke4y90yg6c4gxbdwn2w9lgcb98 ON public."event" (word_image_id);
CREATE INDEX IF NOT EXISTS idx_event_fk8up0cm0j7flyds8mljh3wslcs ON public."event" (word_short_desc_chinese_id);
CREATE INDEX IF NOT EXISTS idx_event_fkcaqnogrpoabtlfqf9h4wuxybk ON public."event" (sentence_id);
CREATE INDEX IF NOT EXISTS idx_event_fk8y4063ul9igji7dsmq61t7pg3 ON public."event" (sentence_chinese_id);
CREATE INDEX IF NOT EXISTS idx_feature_request_idx_status_vote_count ON public.feature_request (status, vote_count, create_time);
CREATE INDEX IF NOT EXISTS idx_feature_request_idx_creator_id ON public.feature_request (creator_id);
CREATE INDEX IF NOT EXISTS idx_feature_request_report_idx_reporter_id ON public.feature_request_report (reporter_id);
CREATE INDEX IF NOT EXISTS idx_feature_request_report_idx_feature_request_id ON public.feature_request_report (feature_request_id);
CREATE INDEX IF NOT EXISTS idx_feature_request_report_idx_create_time ON public.feature_request_report (create_time);
CREATE INDEX IF NOT EXISTS idx_feature_request_vote_idx_request_id ON public.feature_request_vote (request_id);
CREATE INDEX IF NOT EXISTS idx_feature_request_vote_idx_user_id ON public.feature_request_vote (user_id);
CREATE INDEX IF NOT EXISTS idx_forum_and_manager_link_fk4rgldqqyj2v6ko5fb3j4h00hw ON public.forum_and_manager_link (user_id);
CREATE INDEX IF NOT EXISTS idx_forum_and_manager_link_fkm2ne0gyp8to1iltn9y5xatn5g ON public.forum_and_manager_link (forum_id);
CREATE INDEX IF NOT EXISTS idx_forum_post_fkh0s5a90088gbywb9u9j5fase4 ON public.forum_post (forum_id);
CREATE INDEX IF NOT EXISTS idx_forum_post_fk89ba00sxrqhbgl7cgwt6y0tux ON public.forum_post (post_creator_id);
CREATE INDEX IF NOT EXISTS idx_forum_post_reply_fksmolky8m77uf3aygscwtlh7 ON public.forum_post_reply (post_id);
CREATE INDEX IF NOT EXISTS idx_forum_post_reply_fkctt5g9ionoo960lak0p7ss6ou ON public.forum_post_reply (post_replyer_id);
CREATE INDEX IF NOT EXISTS idx_game_hall_fkbb8bsyk402u3fxe0vnv2ecp12 ON public.game_hall (dict_group_id);
CREATE INDEX IF NOT EXISTS idx_game_hall_fks184ekmq8ct8x9etyonngejo4 ON public.game_hall (hall_group_id);
CREATE INDEX IF NOT EXISTS idx_group_and_dict_link_fkhuoc8hxjs2c8w1fgickojg6ff ON public.group_and_dict_link (dict_id);
CREATE INDEX IF NOT EXISTS idx_group_and_dict_link_fkanvwboyqdce5mb41j8q4qly3c ON public.group_and_dict_link (group_id);
CREATE INDEX IF NOT EXISTS idx_info_vote_log_fknyxodwmjasis1v8c04xsen7dh ON public.info_vote_log (user_id);
CREATE INDEX IF NOT EXISTS idx_learning_dict_fks6prwtgob6wmhxysa8bu1096r ON public.learning_dict (current_word_id);
CREATE INDEX IF NOT EXISTS idx_learning_dict_fkpiu1chqdc7gn2bchpkxcbdqu6 ON public.learning_dict (user_id);
CREATE INDEX IF NOT EXISTS idx_learning_word_idx_userid ON public.learning_word (user_id);
CREATE INDEX IF NOT EXISTS idx_login_log_fk9auh6uhsrknd75ipjypyyha90 ON public.login_log (user_id);
CREATE INDEX IF NOT EXISTS idx_mastered_word_mastered_word_user_id_idx ON public.mastered_word (user_id);
CREATE INDEX IF NOT EXISTS idx_meaning_item_fkbq1kwqm7l14nowpnkgyct7qmb ON public.meaning_item (word_id);
CREATE INDEX IF NOT EXISTS idx_meaning_item_fkhajsfsxiyna9xuo9i974u8v07 ON public.meaning_item (dict_id);
CREATE INDEX IF NOT EXISTS idx_msg_fkpwao1csk2fiqn8x0taf5n4lxp ON public.msg (from_user_id);
CREATE INDEX IF NOT EXISTS idx_msg_fkduaesr28u3xkjgacqyp6f9k69 ON public.msg (to_user_id);
CREATE INDEX IF NOT EXISTS idx_msg_idx_msg_client_type ON public.msg (client_type);
CREATE INDEX IF NOT EXISTS idx_sentence_sentence_fk ON public.sentence (author_id);
CREATE INDEX IF NOT EXISTS idx_sentence_sentence_meaning_item_fk ON public.sentence (meaning_item_id);
CREATE INDEX IF NOT EXISTS idx_sentence_chinese_fk1ea8mppmrgwbn1gcmn0n4s95n ON public.sentence_chinese (author);
CREATE INDEX IF NOT EXISTS idx_sentence_chinese_fk4qkl23fg27sp450b9h3n7xnwx ON public.sentence_chinese (sentence_id);
CREATE INDEX IF NOT EXISTS idx_sentence_chinese_remark_fk9eseuj1b3lp9r0cp52hl524i7 ON public.sentence_chinese_remark (chinese_id);
CREATE INDEX IF NOT EXISTS idx_sentence_chinese_remark_fkqb6gj27jt2kffko46xcctg0u6 ON public.sentence_chinese_remark (author);
CREATE INDEX IF NOT EXISTS idx_sentence_update_notify_sentence_update_notify_fk ON public.sentence_update_notify (sentence_id);
CREATE INDEX IF NOT EXISTS idx_similar_word_fk1mqflio4f1yp8ety4wsa8naku ON public.similar_word (similar_word_id);
CREATE INDEX IF NOT EXISTS idx_similar_word_fkcwlj8g7yxqfqag6sbcypi705a ON public.similar_word (word_id);
CREATE INDEX IF NOT EXISTS idx_sms_verification_code_idx_phone_type ON public.sms_verification_code (phone, type);
CREATE INDEX IF NOT EXISTS idx_sms_verification_code_idx_create_time ON public.sms_verification_code (create_time);
CREATE INDEX IF NOT EXISTS idx_study_group_fkfml3yg6yg9a2xi45w4vx7dqfb ON public.study_group (creator_id);
CREATE INDEX IF NOT EXISTS idx_study_group_fk36s0562yu4gydy3xr28u95eqd ON public.study_group (grade_id);
CREATE INDEX IF NOT EXISTS idx_study_group_and_manager_link_fkgfviie87tlf3c34ipmx31ynj7 ON public.study_group_and_manager_link (user_id);
CREATE INDEX IF NOT EXISTS idx_study_group_and_manager_link_fkrdflptnxblu6aa5r7s9747ko4 ON public.study_group_and_manager_link (group_id);
CREATE INDEX IF NOT EXISTS idx_study_group_and_user_link_fk66ybol3y7m0xgvon3hovu9ifv ON public.study_group_and_user_link (user_id);
CREATE INDEX IF NOT EXISTS idx_study_group_and_user_link_fks1c5cfbgl89yn2p955v7sugj7 ON public.study_group_and_user_link (group_id);
CREATE INDEX IF NOT EXISTS idx_study_group_post_fkc3t23fo2d1n4cqsq5ct92vtjn ON public.study_group_post (group_id);
CREATE INDEX IF NOT EXISTS idx_study_group_post_fkmy0w3ae9nui45ii8gg5ftx03y ON public.study_group_post (post_creator_id);
CREATE INDEX IF NOT EXISTS idx_study_group_post_reply_fk302iba0o0rgoegvo0en7a05jl ON public.study_group_post_reply (post_id);
CREATE INDEX IF NOT EXISTS idx_study_group_post_reply_fklbwltcdwo4x4hlkbl51fpph ON public.study_group_post_reply (post_replyer_id);
CREATE INDEX IF NOT EXISTS idx_study_group_snapshot_daily_fks0e3efs4xyt73agwc6e96wjc4 ON public.study_group_snapshot_daily (group_id);
CREATE INDEX IF NOT EXISTS idx_sys_db_log_idx_version ON public.sys_db_log (version);
CREATE INDEX IF NOT EXISTS idx_sys_db_log_idx_table_record ON public.sys_db_log (tbl_name, record_id);
CREATE INDEX IF NOT EXISTS idx_user_fkefu5f2ioj2qy2bycuh6g3wbkd ON public."user" (invited_by_id);
CREATE INDEX IF NOT EXISTS idx_user_fk6lqwkmrxl04j2k3d2oqysgwvm ON public."user" (level_id);
CREATE INDEX IF NOT EXISTS idx_user_cow_dung_log_fkp01eygbwkg91uujcjasrhbu2y ON public.user_cow_dung_log (user_id);
CREATE INDEX IF NOT EXISTS idx_user_game_fke1j2if58j0qgke4numextbw8a ON public.user_game (user_id);
CREATE INDEX IF NOT EXISTS idx_user_oper_idx_user_id_oper_time ON public.user_oper (user_id, oper_time);
CREATE INDEX IF NOT EXISTS idx_user_oper_idx_oper_type ON public.user_oper (oper_type);
CREATE INDEX IF NOT EXISTS idx_user_score_log_fkn1b5wicvnceas08ju14uk3qqw ON public.user_score_log (user_id);
CREATE INDEX IF NOT EXISTS idx_user_snapshot_daily_fkm48fwdudlv10kcn0wafvdves3 ON public.user_snapshot_daily (user_id);
CREATE INDEX IF NOT EXISTS idx_user_study_step_fkkb5mbew7a6hawfub12aotlpbh ON public.user_study_step (user_id);
CREATE INDEX IF NOT EXISTS idx_user_wrong_word_fkwkw9ln2wtbqtq0e7s5ayti2t ON public.user_wrong_word (word_id);
CREATE INDEX IF NOT EXISTS idx_user_wrong_word_fkqneibfe99w3ktslncl4vt009k ON public.user_wrong_word (user_id);
CREATE INDEX IF NOT EXISTS idx_verb_tense_fkrymhs6cvyoh40cpcslopn98yo ON public.verb_tense (word_id);
CREATE INDEX IF NOT EXISTS idx_word_additional_info_fkf3xqffcm8vnaqbucfr5i24yqh ON public.word_additional_info (user_id);
CREATE INDEX IF NOT EXISTS idx_word_additional_info_fk5jynq4erw7uwlffv3covsa9oc ON public.word_additional_info (word_id);
CREATE INDEX IF NOT EXISTS idx_word_image_fkcsrc6dqtt1q9907n2w3qcy71v ON public.word_image (author_id);
CREATE INDEX IF NOT EXISTS idx_word_image_fk22nlb05j0hk398isouqw9ehbc ON public.word_image (word_id);
CREATE INDEX IF NOT EXISTS idx_word_sentence_fkaqa9an1x12g7s6u92i30raln7 ON public.word_sentence (word_id);
CREATE INDEX IF NOT EXISTS idx_word_shortdesc_chinese_fktfaryode4etiv5gh8vr47bnbh ON public.word_shortdesc_chinese (author_id);
CREATE INDEX IF NOT EXISTS idx_word_shortdesc_chinese_fk662626om3lfe5ov2fohxuqpgp ON public.word_shortdesc_chinese (word_id);
