import subprocess, re, os

result = subprocess.run(
    ['textutil', '-convert', 'txt',
     '/Volumes/ssd/ppdc/tools/book/小学/精通版/六年级下册单词专项/3-6年级单词表.docx',
     '-stdout'],
    capture_output=True, text=True
)
lines = result.stdout.splitlines()

section_order = ['四年级上册','四年级下册','五年级上册','五年级下册','六年级上册','六年级下册']
section_starts = {}
for i, line in enumerate(lines):
    s = line.strip()
    for sec in section_order:
        if s.startswith(sec) and sec not in section_starts:
            section_starts[sec] = i

section_ranges = {}
for idx, sec in enumerate(section_order):
    start = section_starts[sec] + 1
    end = section_starts[section_order[idx+1]] if idx+1 < len(section_order) else len(lines)
    section_ranges[sec] = (start, end)

def parse_line(raw):
    line = re.sub(r'[\u200f\u200e\u202a-\u202e]', '', raw).strip()
    if not line:
        return None
    if re.match(r'^Unit\s+\d+', line, re.I):
        return None
    if not re.match(r'^[a-zA-Z]', line):
        return None
    # Skip contraction/grammar notes like "I'm = I am" (straight or curly apostrophe)
    if ' = ' in line or '‘ = ' in line or '’ = ' in line:
        return None

    # Step 1: strip phonetic bracket content, but NOT Chinese characters
    # Handles [[...], [...], unclosed brackets (stop before CJK)
    clean = re.sub(r'\[+[^\]\u4e00-\u9fff]*\]?', '', line).strip()

    # Step 2: split on the FIRST Chinese (or full-width) character
    m = re.match(r'^([a-zA-Z][a-zA-Z0-9\u2019\u2018\'\-\.\(\)\uff08\uff09/\s]*?)\s*([\u4e00-\u9fff\u3001\uff08\u2026].*)$', clean)
    if m:
        w = m.group(1).strip().rstrip('.')
        d = m.group(2).strip()
        if w and re.search(r'[\u4e00-\u9fff]', d):
            return (w, d)

    return None

out_dir = '/Volumes/ssd/ppdc/tools/book/小学/精通版'
filenames = {s: s + '单词表.txt' for s in section_order}

for sec in section_order:
    start, end = section_ranges[sec]
    entries, skipped = [], []
    for line in lines[start:end]:
        p = parse_line(line)
        if p:
            entries.append(f"{p[0]}|{p[1]}")
        else:
            r = re.sub(r'[\u200f\u200e\u202a-\u202e]', '', line).strip()
            if r and not r.startswith('Unit') and re.match(r'^[a-zA-Z]', r):
                skipped.append(r)
    with open(os.path.join(out_dir, filenames[sec]), 'w', encoding='utf-8') as f:
        f.write('\n'.join(entries) + '\n')
    print(f"{sec}: {len(entries)} words -> {filenames[sec]}")
    for s in skipped[:10]:
        print(f"  SKIP: {repr(s)}")
