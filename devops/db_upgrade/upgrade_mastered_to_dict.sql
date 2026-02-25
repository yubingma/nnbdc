-- ============================================================================
-- 将已掌握单词从 mastered_word 表迁移到 dict 词书体系
-- 
-- 处理逻辑：
-- 1. 为【所有用户】创建 "已掌握" 词书 (dict)（没有已掌握单词的用户也需要）
-- 2. 将 mastered_word 数据迁移到 dict_word（如有）
-- 3. 生成同步日志 (user_db_log)，让前端通过同步拿到新数据
-- 4. 递增 user_db_version
-- 5. 最终删除 mastered_word 表
-- ============================================================================

DO $$
DECLARE
    v_user RECORD;
    v_mastered RECORD;
    v_dict_id VARCHAR(32);
    v_word_count INTEGER;
    v_new_version INTEGER;
    v_now TIMESTAMP;
    v_seq INTEGER;
    v_log_id VARCHAR(32);
    v_dict_json TEXT;
    v_dict_word_json TEXT;
    v_user_count INTEGER := 0;
    v_total_words INTEGER := 0;
BEGIN
    v_now := NOW();

    -- 遍历【所有用户】，而不仅仅是有已掌握单词的用户
    FOR v_user IN
        SELECT id AS user_id FROM "user"
    LOOP
        -- 检查该用户是否已经有"已掌握"词书（幂等性）
        SELECT id INTO v_dict_id FROM dict WHERE owner_id = v_user.user_id AND name = '已掌握' LIMIT 1;

        IF v_dict_id IS NULL THEN
            -- 生成新的 dict id
            v_dict_id := REPLACE(gen_random_uuid()::TEXT, '-', '');

            -- 统计该用户的已掌握单词数（排除 word 表中不存在的孤儿记录）
            SELECT COUNT(*) INTO v_word_count FROM mastered_word mw
            JOIN word w ON w.id = mw.word_id
            WHERE mw.user_id = v_user.user_id;

            -- 1. 创建"已掌握"词书
            INSERT INTO dict (id, name, owner_id, is_shared, is_ready, visible, editable, word_count, create_time, update_time)
            VALUES (v_dict_id, '已掌握', v_user.user_id, FALSE, TRUE, TRUE, TRUE, v_word_count, v_now, v_now);

            -- 2. 将 mastered_word 数据迁移到 dict_word（如有）
            IF v_word_count > 0 THEN
                v_seq := 0;
                FOR v_mastered IN
                    SELECT mw.word_id, mw.master_at_time, mw.create_time AS mw_create_time, mw.update_time AS mw_update_time
                    FROM mastered_word mw
                    JOIN word w ON w.id = mw.word_id
                    WHERE mw.user_id = v_user.user_id
                    ORDER BY mw.master_at_time ASC
                LOOP
                    v_seq := v_seq + 1;

                    INSERT INTO dict_word (dict_id, word_id, seq, create_time, update_time)
                    VALUES (v_dict_id, v_mastered.word_id, v_seq, COALESCE(v_mastered.mw_create_time, v_now), COALESCE(v_mastered.mw_update_time, v_now))
                    ON CONFLICT (dict_id, word_id) DO NOTHING;

                    v_total_words := v_total_words + 1;
                END LOOP;
            END IF;

            -- 3. 获取当前用户版本号并递增
            SELECT version INTO v_new_version FROM user_db_version WHERE user_id = v_user.user_id;
            IF v_new_version IS NULL THEN
                v_new_version := 1;
                INSERT INTO user_db_version (id, user_id, version, create_time, update_time)
                VALUES (REPLACE(gen_random_uuid()::TEXT, '-', ''), v_user.user_id, v_new_version, v_now, v_now);
            ELSE
                v_new_version := v_new_version + 1;
                UPDATE user_db_version SET version = v_new_version, update_time = v_now WHERE user_id = v_user.user_id;
            END IF;

            -- 4. 生成同步日志

            -- 4.1 dict INSERT 日志
            v_log_id := REPLACE(gen_random_uuid()::TEXT, '-', '');
            v_dict_json := FORMAT(
                '{"id":"%s","name":"已掌握","ownerId":"%s","isShared":false,"isReady":true,"visible":true,"editable":true,"wordCount":%s,"popularityLimit":null,"createTime":"%s","updateTime":"%s"}',
                v_dict_id, v_user.user_id, v_word_count,
                TO_CHAR(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"+08:00"'),
                TO_CHAR(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"+08:00"')
            );
            INSERT INTO user_db_log (id, user_id, version, operate, tbl_name, record_id, record, create_time, update_time)
            VALUES (v_log_id, v_user.user_id, v_new_version, 'INSERT', 'dict', v_dict_id, v_dict_json, v_now, v_now);

            -- 4.2 dict_word INSERT 日志（每个已掌握单词一条）
            IF v_word_count > 0 THEN
                v_seq := 0;
                FOR v_mastered IN
                    SELECT mw.word_id, mw.master_at_time, mw.create_time AS mw_create_time, mw.update_time AS mw_update_time
                    FROM mastered_word mw
                    JOIN word w ON w.id = mw.word_id
                    WHERE mw.user_id = v_user.user_id
                    ORDER BY mw.master_at_time ASC
                LOOP
                    v_seq := v_seq + 1;
                    v_log_id := REPLACE(gen_random_uuid()::TEXT, '-', '');
                    v_dict_word_json := FORMAT(
                        '{"dictId":"%s","wordId":"%s","seq":%s,"createTime":"%s","updateTime":"%s"}',
                        v_dict_id, v_mastered.word_id, v_seq,
                        TO_CHAR(COALESCE(v_mastered.mw_create_time, v_now), 'YYYY-MM-DD"T"HH24:MI:SS.MS"+08:00"'),
                        TO_CHAR(COALESCE(v_mastered.mw_update_time, v_now), 'YYYY-MM-DD"T"HH24:MI:SS.MS"+08:00"')
                    );
                    INSERT INTO user_db_log (id, user_id, version, operate, tbl_name, record_id, record, create_time, update_time)
                    VALUES (v_log_id, v_user.user_id, v_new_version, 'INSERT', 'dict_word',
                            v_dict_id || '-' || v_mastered.word_id, v_dict_word_json, v_now, v_now);
                END LOOP;
            END IF;

            v_user_count := v_user_count + 1;
        END IF;
    END LOOP;

    RAISE NOTICE '迁移完成: 处理了 % 个用户, 共 % 个已掌握单词', v_user_count, v_total_words;
END $$;

-- 迁移完成后，验证数据正确性
SELECT '迁移后统计' AS label,
       (SELECT COUNT(*) FROM "user") AS total_user_count,
       (SELECT COUNT(*) FROM dict WHERE name = '已掌握') AS mastered_dict_count,
       (SELECT COUNT(*) FROM mastered_word) AS original_word_count,
       (SELECT COUNT(*) FROM dict_word dw JOIN dict d ON dw.dict_id = d.id WHERE d.name = '已掌握') AS migrated_word_count;

-- ============================================================================
-- 确认数据无误后，取消注释以下语句来删除 mastered_word 表
DROP TABLE IF EXISTS mastered_word;
-- ============================================================================
