#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wordbook-batch-import: 词书批量导入前全量质量审查脚本
使用方法:
    python3 audit_books.py [词书目录路径，默认 tools/book/小学]
"""

import os
import sys
import re
import json
import subprocess

target_dir = sys.argv[1] if len(sys.argv) > 1 else '/Volumes/ssd/ppdc/tools/book/小学'
meta_path = os.path.join(target_dir, 'meta.json')

if not os.path.exists(meta_path):
    print(f"❌ 找不到元数据文件: {meta_path}")
    sys.exit(1)

with open(meta_path, 'r', encoding='utf-8') as f:
    meta = json.load(f)

books = meta.get('books', [])
print(f"==================================================")
print(f"开始词书质量审查: 目录={target_dir}, 词书数={len(books)}")
print(f"==================================================")

# 1. 查询生产库已有词书名 (排查重名冲突)
db_existing_dicts = set()
pwd = os.environ.get('nnbdc_server_pwd', 'Badhorse201418')
cmd = [
    'sshpass', '-p', pwd,
    'ssh', '-o', 'StrictHostKeyChecking=no', 'root@47.108.27.205',
    'docker exec -i pg psql -U myb -d bdc -t -A -c "SELECT name FROM dict;"'
]
res = subprocess.run(cmd, capture_output=True, text=True)
if res.returncode == 0:
    for line in res.stdout.splitlines():
        line = line.strip()
        if line:
            db_existing_dicts.add(line)
    print(f"[1] 生产库已存在词书数: {len(db_existing_dicts)}")
else:
    print(f"[1] ⚠️ 无法直连生产库查询已有词书 (需手动核对): {res.stderr.strip()}")

# 2. 检查重名冲突 (一票否决项)
duplicate_names = [b['dictName'].strip() for b in books if b['dictName'].strip() in db_existing_dicts]
if duplicate_names:
    print(f"❌ 警告: 发现与生产库同名的词书 ({len(duplicate_names)}本): {duplicate_names}")
else:
    print("✅ [重名检查通过] 所有待导入词书与生产库已有词书无同名冲突！")

# 3. 加载系统大词典 (用于粘连词复核)
system_words = set()
for dict_path in ['/usr/share/dict/words', '/usr/dict/words']:
    if os.path.exists(dict_path):
        with open(dict_path, 'r', encoding='utf-8', errors='ignore') as wf:
            for w in wf:
                system_words.add(w.strip().lower())
        break

total_words = 0
suspicious_files = []
dup_word_issues = []
special_char_issues = []
glued_candidates = []
preps = ['at', 'to', 'in', 'on', 'up', 'for', 'with', 'of', 'into', 'out', 'about', 'down', 'off', 'over']

for b in books:
    fname = b['fileName']
    dname = b['dictName']
    fpath = os.path.join(target_dir, fname)
    if not os.path.exists(fpath):
        print(f"❌ 找不到物理文件: {fname}")
        continue
    
    with open(fpath, 'r', encoding='utf-8') as tf:
        raw_lines = [l.strip() for l in tf if l.strip() and not l.strip().startswith('#')]
    
    count = len(raw_lines)
    total_words += count
    if count < 15:
        suspicious_files.append((dname, fname, count))
        
    seen = {}
    for line in raw_lines:
        spell = line.split('|')[1].strip() if '|' in line else line.strip()
        if not spell:
            continue
            
        wl = spell.lower()
        wl_norm = wl.rstrip('.')
        
        # 变体重复检查
        if wl_norm in seen:
            dup_word_issues.append((dname, fname, seen[wl_norm], spell))
        else:
            seen[wl_norm] = spell
            
        # 标点符号与特殊字符审查
        if re.search(r'[^a-zA-Z\s\-\']', spell):
            special_char_issues.append((dname, fname, spell))
            
        # 粘连词审查
        if ' ' not in spell and len(spell) > 5 and system_words and wl not in system_words:
            for p in preps:
                if wl.endswith(p):
                    stem = wl[:-len(p)]
                    if stem in system_words:
                        glued_candidates.append((dname, fname, spell, f"{stem} + {p}"))

print(f"\n[2] 词汇量统计: 总词条数 {total_words}, 平均每本 {total_words/len(books):.1f} 词")
if suspicious_files:
    print(f"⚠️ 词条数过少(<15)的文件 ({len(suspicious_files)}本):")
    for d, f, c in suspicious_files:
        print(f"   - {d} ({f}): 仅 {c} 词")
else:
    print("✅ 没有词条数过少(<15)的异常文件")

print(f"\n[3] 重复/变体重复审查: 共发现 {len(dup_word_issues)} 处")
for d, f, w1, w2 in dup_word_issues[:10]:
    print(f"   - [{d}] 重复: '{w1}' vs '{w2}'")
if len(dup_word_issues) > 10:
    print(f"   ... 还有 {len(dup_word_issues) - 10} 处")

print(f"\n[4] 非标准/含标点符号条目: 共发现 {len(special_char_issues)} 处")
for d, f, w in special_char_issues[:15]:
    print(f"   - [{d}] 特殊符号: '{w}'")
if len(special_char_issues) > 15:
    print(f"   ... 还有 {len(special_char_issues) - 15} 处")

print(f"\n[5] 疑似粘连词 (Glued Words): 共发现 {len(glued_candidates)} 处")
for d, f, w, sug in glued_candidates[:15]:
    print(f"   - [{d}] 疑似连字: '{w}' (切分建议: {sug})")

print(f"\n==================================================")
if not duplicate_names and len(dup_word_issues) == 0 and len(glued_candidates) == 0:
    print("🎉 恭喜！数据审查达到出厂级标准，可推进批量导入！")
else:
    print("⚠️ 请运行 clean_books.py 规范化清洗后再复核！")
print(f"==================================================")
