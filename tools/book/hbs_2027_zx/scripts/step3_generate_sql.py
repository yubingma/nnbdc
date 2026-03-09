import os
import re

# Config
DICT_ID = 'hbs_2027_zx'
DICT_NAME = '2027考研英语红宝书（正序版）'
OWNER_ID = '15118'

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INPUT_FILE = os.path.join(BASE_DIR, 'output', '2027_hbs_extracted.txt')
OUTPUT_SQL = os.path.join(BASE_DIR, 'output', 'import_2027_hbs.sql')

POS_PATTERN = r'(v\.|vt\.|vi\.|n\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|art\.|int\.)'

def escape_sql(text):
    if text is None: return "NULL"
    return "'" + text.replace("'", "''") + "'"

def split_pos_meanings(text):
    matches = list(re.finditer(POS_PATTERN, text))
    if not matches:
        return [("", text.strip())]
    
    results = []
    skip_until = -1
    for i in range(len(matches)):
        if i < skip_until: continue
        pos_group = [matches[i].group(0)]
        k = i + 1
        last_e = matches[i].end()
        while k < len(matches) and matches[k].start() <= last_e + 2: 
            pos_group.append(matches[k].group(0))
            last_e = matches[k].end()
            k += 1
        skip_until = k
        pos_str = " ".join(pos_group)
        m_start = last_e
        m_end = matches[k].start() if k < len(matches) else len(text)
        m_val = text[m_start:m_end].strip()
        if m_val:
            for p in re.findall(POS_PATTERN, pos_str):
                results.append((p, m_val))
    return results if results else [("", text.strip())]

def generate():
    if not os.path.exists(INPUT_FILE):
        print("Error: Input extracted file not found.")
        return

    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    with open(OUTPUT_SQL, 'w', encoding='utf-8') as f:
        f.write("-- Automated Migration Script for HBS 2027\nBEGIN;\n\n")
        
        # Cleanup
        e_id = escape_sql(DICT_ID)
        f.write(f"-- Cleanup\nDELETE FROM dict_word WHERE dict_id = {e_id};\n")
        f.write(f"DELETE FROM group_and_dict_link WHERE dict_id = {e_id};\n")
        f.write(f"DELETE FROM learning_dict WHERE dict_id = {e_id};\n")
        f.write(f"DELETE FROM meaning_item WHERE dict_id = {e_id};\n")
        f.write(f"DELETE FROM dict WHERE id = {e_id};\n\n")

        # Dictionary
        f.write(f"INSERT INTO dict (id, name, owner_id, is_ready, is_shared, visible, deletable, editable, popularity_limit, word_count, create_time, update_time) \n")
        f.write(f"VALUES ({e_id}, {escape_sql(DICT_NAME)}, {escape_sql(OWNER_ID)}, true, false, true, true, true, 5, {len(lines)}, NOW(), NOW());\n\n")

        # Temp Tables
        f.write("DROP TABLE IF EXISTS tmp_raw;\n")
        f.write("CREATE TEMP TABLE tmp_raw (spell text, raw_meaning text, seq int);\n")
        f.write("DROP TABLE IF EXISTS tmp_split;\n")
        f.write("CREATE TEMP TABLE tmp_split (spell text, ci_xing text, meaning text);\n\n")

        # Bulk Inserts
        f.write("INSERT INTO tmp_raw (spell, raw_meaning, seq) VALUES\n")
        raw_vals = []
        split_vals = []
        for idx, line in enumerate(lines):
            parts = line.strip().split('|')
            if len(parts) != 2: continue
            spell, mean = parts[0], parts[1]
            raw_vals.append(f"({escape_sql(spell)}, {escape_sql(mean)}, {idx+1})")
            for pos, m in split_pos_meanings(mean):
                split_vals.append(f"({escape_sql(spell)}, {escape_sql(pos)}, {escape_sql(m)})")
        
        f.write(",\n".join(raw_vals) + ";\n\n")
        f.write("INSERT INTO tmp_split (spell, ci_xing, meaning) VALUES\n")
        f.write(",\n".join(split_vals) + ";\n\n")

        # Word Table Sync
        f.write("CREATE TEMP SEQUENCE temp_v_id_seq START WITH 60000;\n")
        f.write("INSERT INTO word (id, spell, create_time, update_time, popularity) \n")
        f.write("SELECT nextval('temp_v_id_seq')::text, sub.spell, NOW(), NOW(), 0 \n")
        f.write("FROM (SELECT DISTINCT spell FROM tmp_raw) sub \n")
        f.write("WHERE NOT EXISTS (SELECT 1 FROM word w WHERE w.spell = sub.spell);\n\n")

        # Meaning Item Sync
        f.write("CREATE TEMP SEQUENCE temp_m_id_seq START WITH 3000000;\n")
        f.write("INSERT INTO meaning_item (id, word_id, dict_id, ci_xing, meaning, is_updating, create_time, update_time, popularity) \n")
        f.write("SELECT nextval('temp_m_id_seq')::text, w.id, '0', s.ci_xing, s.meaning, false, NOW(), NOW(), 0 \n")
        f.write("FROM (SELECT DISTINCT spell, ci_xing, meaning FROM tmp_split) s \n")
        f.write("JOIN word w ON s.spell = w.spell \n")
        f.write("WHERE w.id ~ '^[0-9]+$' AND w.id::bigint >= 50000 \n")
        f.write("AND NOT EXISTS (SELECT 1 FROM meaning_item mi WHERE mi.word_id = w.id AND mi.meaning = s.meaning);\n\n")

        # Final Linking to specific book
        f.write(f"INSERT INTO dict_word (dict_id, word_id, seq, create_time, update_time) \n")
        f.write(f"SELECT {e_id}, w.id, MIN(t.seq), NOW(), NOW() FROM tmp_raw t JOIN word w ON t.spell = w.spell GROUP BY w.id;\n\n")
        
        # Link to General Dictionary '0' (so words are globally searchable without needing to download this specific book first)
        f.write(f"INSERT INTO dict_word (dict_id, word_id, seq, create_time, update_time) \n")
        f.write(f"SELECT '0', w.id, 99999, NOW(), NOW() FROM tmp_raw t JOIN word w ON t.spell = w.spell "
                f"WHERE NOT EXISTS (SELECT 1 FROM dict_word dw WHERE dw.dict_id='0' AND dw.word_id=w.id) GROUP BY w.id;\n\n")
        
        # Ensure accurate word count after deduplication
        f.write(f"UPDATE dict SET word_count = (SELECT COUNT(*) FROM dict_word WHERE dict_id = {e_id}) WHERE id = {e_id};\n\n")
        f.write(f"UPDATE dict SET word_count = (SELECT COUNT(*) FROM dict_word WHERE dict_id = '0') WHERE id = '0';\n\n")
        
        # Incremental Sync for Old Users (Smart Idempotent Log)
        f.write("DO $$\n")
        f.write("DECLARE\n")
        f.write("    next_v INTEGER;\n")
        f.write("    has_changes BOOLEAN := FALSE;\n")
        f.write("BEGIN\n")
        f.write("    -- 1. Check if there are any new items that need logging\n")
        f.write("    IF EXISTS (\n")
        f.write("        SELECT 1 FROM word w WHERE w.id ~ '^[0-9]+$' AND w.id::bigint >= 50000 AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("        AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'word' AND record_id = w.id)\n")
        f.write("    ) OR EXISTS (\n")
        f.write("        SELECT 1 FROM meaning_item mi JOIN word w ON mi.word_id = w.id WHERE mi.id ~ '^[0-9]+$' AND mi.id::bigint >= 1000000\n")
        f.write("        AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("        AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'meaning_item' AND record_id = mi.id)\n")
        f.write("    ) OR EXISTS (\n")
        f.write("        SELECT 1 FROM dict_word dw JOIN word w ON dw.word_id = w.id WHERE dw.dict_id = '0' AND w.id ~ '^[0-9]+$' AND w.id::bigint >= 50000\n")
        f.write("        AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("        AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'dict_word' AND record_id = dw.dict_id || '_' || dw.word_id)\n")
        f.write("    ) THEN\n")
        f.write("        has_changes := TRUE;\n")
        f.write("    END IF;\n")
        f.write("\n")
        f.write("    IF has_changes THEN\n")
        f.write("        SELECT version + 1 INTO next_v FROM sys_db_version WHERE id = 'singleton';\n")
        f.write("        UPDATE sys_db_version SET version = next_v, update_time = NOW() WHERE id = 'singleton';\n")
        f.write("        RAISE NOTICE 'New version triggered: %', next_v;\n")
        f.write("\n")
        f.write("        -- Log new words\n")
        f.write("        INSERT INTO sys_db_log (id, version, operate, tbl_name, record_id, record, create_time, update_time)\n")
        f.write("        SELECT md5(w.id || 'word' || next_v::text), next_v, 'INSERT', 'word', w.id, \n")
        f.write("               json_build_object('id', w.id, 'spell', w.spell, 'popularity', w.popularity, 'createTime', to_char(w.create_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'), 'updateTime', to_char(w.update_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'))::text,\n")
        f.write("               NOW(), NOW()\n")
        f.write("        FROM word w WHERE w.id ~ '^[0-9]+$' AND w.id::bigint >= 50000 AND w.id::bigint < 3000000\n")
        f.write("          AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("          AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'word' AND record_id = w.id);\n")
        f.write("\n")
        f.write("        -- Log new meaning items\n")
        f.write("        INSERT INTO sys_db_log (id, version, operate, tbl_name, record_id, record, create_time, update_time)\n")
        f.write("        SELECT md5(mi.id || 'meaning_item' || next_v::text), next_v, 'INSERT', 'meaning_item', mi.id, \n")
        f.write("               json_build_object('id', mi.id, 'wordId', mi.word_id, 'dictId', mi.dict_id, 'ciXing', mi.ci_xing, 'meaning', mi.meaning, 'popularity', mi.popularity, 'createTime', to_char(mi.create_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'), 'updateTime', to_char(mi.update_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'))::text,\n")
        f.write("               NOW(), NOW()\n")
        f.write("        FROM meaning_item mi JOIN word w ON mi.word_id = w.id\n")
        f.write("        WHERE mi.id ~ '^[0-9]+$' AND mi.id::bigint >= 1000000\n")
        f.write("          AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("          AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'meaning_item' AND record_id = mi.id);\n")
        f.write("\n")
        f.write("        -- Log new dict_word links\n")
        f.write("        INSERT INTO sys_db_log (id, version, operate, tbl_name, record_id, record, create_time, update_time)\n")
        f.write("        SELECT md5(dw.dict_id || '_' || dw.word_id || 'dict_word' || next_v::text), next_v, 'INSERT', 'dict_word', dw.dict_id || '_' || dw.word_id, \n")
        f.write("               json_build_object('dictId', dw.dict_id, 'wordId', dw.word_id, 'seq', dw.seq, 'createTime', to_char(dw.create_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'), 'updateTime', to_char(dw.update_time, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'))::text,\n")
        f.write("               NOW(), NOW()\n")
        f.write("        FROM dict_word dw JOIN word w ON dw.word_id = w.id\n")
        f.write("        WHERE dw.dict_id = '0' AND w.id ~ '^[0-9]+$' AND w.id::bigint >= 50000\n")
        f.write("          AND w.spell IN (SELECT spell FROM tmp_raw)\n")
        f.write("          AND NOT EXISTS (SELECT 1 FROM sys_db_log WHERE tbl_name = 'dict_word' AND record_id = dw.dict_id || '_' || dw.word_id);\n")
        f.write("    ELSE\n")
        f.write("        RAISE NOTICE 'No new items to log. Skipping version bump.';\n")
        f.write("    END IF;\n")
        f.write("END $$;\n")
        f.write(f"INSERT INTO group_and_dict_link (group_id, dict_id) SELECT id, {e_id} FROM dict_group WHERE name = '考研';\n\n")
        
        f.write("COMMIT;\n")

    print(f"Generated robust SQL at {OUTPUT_SQL}")

if __name__ == "__main__":
    generate()
