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
        f.write(f"INSERT INTO dict (id, name, owner_id, is_ready, is_shared, visible, deletable, editable, word_count, create_time, update_time) \n")
        f.write(f"VALUES ({e_id}, {escape_sql(DICT_NAME)}, {escape_sql(OWNER_ID)}, true, false, true, true, true, {len(lines)}, NOW(), NOW());\n\n")

        # Temp Tables
        f.write("CREATE TEMP TABLE tmp_raw (spell text, raw_meaning text, seq int);\n")
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
        f.write("WHERE w.id ~ '^[0-9]+$' AND w.id::bigint >= 60000 \n")
        f.write("AND NOT EXISTS (SELECT 1 FROM meaning_item mi WHERE mi.word_id = w.id AND mi.meaning = s.meaning);\n\n")

        # Final Linking
        f.write(f"INSERT INTO dict_word (dict_id, word_id, seq, create_time, update_time) \n")
        f.write(f"SELECT {e_id}, w.id, MIN(t.seq), NOW(), NOW() FROM tmp_raw t JOIN word w ON t.spell = w.spell GROUP BY w.id;\n\n")
        
        f.write(f"INSERT INTO group_and_dict_link (group_id, dict_id) SELECT id, {e_id} FROM dict_group WHERE name = '考研';\n\n")
        
        f.write("COMMIT;\n")

    print(f"Generated robust SQL at {OUTPUT_SQL}")

if __name__ == "__main__":
    generate()
