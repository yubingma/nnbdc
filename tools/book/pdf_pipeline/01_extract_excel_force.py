import openpyxl
import re
import os
from spellchecker import SpellChecker

# 初始化全球拼写检查
spell = SpellChecker()

def clean_word(raw_word):
    if not raw_word: return None
    raw_word = str(raw_word).strip()
    if not raw_word: return None
    
    # 物理层截断
    raw_word = re.split(r'[\(（\[【\u2E80-\u9FFF/~]|\.\.', str(raw_word))[0].strip()
    
    if re.match(r'^(Chapter|List|Table|Date|Page)', raw_word, re.I):
        return None
    
    while True:
        old_word = raw_word
        # 1. 词性标记清理
        raw_word = re.sub(r'\s+(adj|adv|prep|conj|pron|num|art|int|vt|vi|n|v|sb|sth|phr|det)\.*$', '', raw_word, flags=re.IGNORECASE)
        raw_word = re.sub(r'\d+$', '', raw_word).strip()
        
        # 2. 补全/裁切判定
        if len(raw_word) > 4:
            # A. 智能剥离层：仅当错词变正词时才动刀
            if raw_word.endswith(('n', 'v', 'adj', 'adv')):
                p_len = 3 if raw_word.endswith(('adj', 'adv')) else 1
                if spell.unknown([raw_word]):
                    if not spell.unknown([raw_word[:-p_len]]):
                        raw_word = raw_word[:-p_len]
                    else:
                        # B. 暴力剥离保底法 (仅针对确认是错词的情况，且必须匹配双写或特定畸形模式)
                        # 重点：修正 gen -> genn，防止误伤 oxygen/hydrogen
                        if (raw_word.endswith('ionn') or raw_word.endswith('ancen') or raw_word.endswith('encen') or
                            raw_word.endswith('mentn') or raw_word.endswith('ablen') or raw_word.endswith('nessn') or
                            raw_word.endswith('smn') or raw_word.endswith('ismn') or raw_word.endswith('uren') or raw_word.endswith('genn')):
                            raw_word = raw_word[:-1]

        # 3. 彻底清理边缘余孽
        raw_word = raw_word.strip('.,/*+~·- ')
        if raw_word == old_word: break

    clean_w = raw_word
    
    if len(clean_w) < 5 and any(c in '.-/· ' for c in clean_w):
        return None
        
    if clean_w.lower() in ['vt', 'vi', 'adj', 'adv', 'n', 'v', 'prep', 'phr', 'sb', 'sth', 'conj', 'det', 'num']:
        return None
    
    if not any(c.isalpha() for c in clean_w): return None
    if len(clean_w) < 2 or len(clean_w.split()) > 3: return None
    
    return clean_w

def extract_ielts_force(input_path, output_path):
    wb = openpyxl.load_workbook(input_path, data_only=True)
    words = []
    
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        for row in ws.iter_rows(values_only=True):
            if not row: continue
            for val in row:
                cleaned = clean_word(val)
                if cleaned:
                    words.append(cleaned)
    
    unique_words = sorted(list(set(words)))
    with open(output_path, 'w', encoding='utf-8') as f:
        for w in unique_words:
            f.write(w + "\n")
            
    print(f"🔥 V14 安全补丁版提取完成！获得提纯词汇表: {len(unique_words)} 个。")

if __name__ == '__main__':
    extract_ielts_force('/Volumes/ssd/ppdc/tools/book/雅思/彩色词汇中英版.xlsx', '/Volumes/ssd/ppdc/tools/book/pdf_pipeline/raw_output.txt')
