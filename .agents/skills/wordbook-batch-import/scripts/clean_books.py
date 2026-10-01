#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wordbook-batch-import: 词书批量规范化清洗脚本
使用方法:
    python3 clean_books.py [词书目录路径，默认 tools/book/小学]
"""

import os
import sys
import re
import json

target_dir = sys.argv[1] if len(sys.argv) > 1 else '/Volumes/ssd/ppdc/tools/book/小学'
meta_path = os.path.join(target_dir, 'meta.json')

if not os.path.exists(meta_path):
    print(f"❌ 找不到元数据文件: {meta_path}")
    sys.exit(1)

with open(meta_path, 'r', encoding='utf-8') as f:
    meta = json.load(f)

books = meta.get('books', [])

def clean_spell(spell):
    s = spell.strip()
    
    # 1. 称谓缩写归一化为无点形式
    abbrev_map = {
        'Mr.': 'Mr', 'mr.': 'Mr',
        'Mrs.': 'Mrs', 'mrs.': 'Mrs',
        'Ms.': 'Ms', 'ms.': 'Ms',
        'Dr.': 'Dr', 'dr.': 'Dr'
    }
    if s in abbrev_map:
        return abbrev_map[s]
        
    # 2. 保留固定省略号 (如 "not ... at all")
    if s.endswith('...'):
        prefix = s[:-3].rstrip('!?., ')
        return prefix + ' ...' if prefix else '...'
        
    # 3. 剥离末尾感叹号、问号、句号 (针对口语交际用语)
    s_clean = re.sub(r'[\!\?\.]+$', '', s).strip()
    
    return s_clean

modified_books_count = 0
total_modified_spells = 0
total_dedup_removed = 0

for b in books:
    fname = b['fileName']
    fpath = os.path.join(target_dir, fname)
    if not os.path.exists(fpath):
        continue
        
    with open(fpath, 'r', encoding='utf-8') as tf:
        raw_lines = tf.readlines()
        
    new_lines = []
    seen_spells = set()
    book_modified = False
    
    for line in raw_lines:
        trimmed = line.strip()
        if not trimmed:
            continue
        if trimmed.startswith('#'):
            new_lines.append(trimmed + '\n')
            continue
            
        parts = trimmed.split('|')
        if len(parts) >= 2:
            unit = parts[0].strip()
            spell = parts[1].strip()
            meaning = parts[2].strip() if len(parts) > 2 else None
        else:
            unit = '0'
            spell = trimmed
            meaning = None
            
        c_spell = clean_spell(spell)
        if c_spell != spell:
            book_modified = True
            total_modified_spells += 1
            
        # 同书内完全相同拼写去重 (保留大小写异义词如 Miss vs miss, US vs us)
        if c_spell in seen_spells:
            total_dedup_removed += 1
            book_modified = True
            continue
            
        seen_spells.add(c_spell)
        
        if meaning:
            reconstructed = f"{unit}|{c_spell}|{meaning}\n"
        else:
            reconstructed = f"{unit}|{c_spell}\n"
        new_lines.append(reconstructed)
        
    if book_modified:
        modified_books_count += 1
        with open(fpath, 'w', encoding='utf-8') as out_f:
            out_f.writelines(new_lines)

print(f"清洗完成！")
print(f"- 目标目录: {target_dir}")
print(f"- 涉及词书修改: {modified_books_count} / {len(books)}")
print(f"- 修正拼写数: {total_modified_spells} 处 (脱标/缩写归一)")
print(f"- 去除变体重复: {total_dedup_removed} 处")
