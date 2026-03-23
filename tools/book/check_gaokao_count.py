import os
import pdfplumber
import collections
import re

pdf_path = "/Volumes/ssd/ppdc/tools/book/高考/高考新课标英语3500单词表(正序版)131页.pdf"

words = {}
with pdfplumber.open(pdf_path) as pdf:
    for page in pdf.pages:
        tables = page.extract_tables()
        for table in tables:
            for row in table:
                if not row or len(row) < 2: continue
                num_str = row[0]
                if not num_str: continue
                num_str = num_str.replace('\n', '').strip()
                if not num_str.isdigit(): continue
                num = int(num_str)
                word_str = row[1]
                if not word_str: continue
                w = word_str.replace('\n', '')
                if '=' in w: w = w.split('=')[0]
                if '(缩' in w: w = w.split('(缩')[0]
                if '(复' in w: w = w.split('(复')[0]
                w = w.strip()
                if num not in words:
                    words[num] = w

orig_list = [words[i] for i in range(1, max(words.keys())+1) if i in words]
orig_list = [re.split(r'[\(（]', w)[0].strip() for w in orig_list]

counts = collections.Counter(orig_list)
duplicates = {w: c for w, c in counts.items() if c > 1}

print(f"Original list length: {len(orig_list)}")
print(f"Unique words count: {len(set(orig_list))}")
print(f"Number of duplicates: {sum(c - 1 for c in duplicates.values())}")

print("\nSample duplicates:")
for i, (w, c) in enumerate(list(duplicates.items())):
    print(f"{w}: {c} times")

# Wait, if the user sees the txt is smaller, it's exactly because of the unique deduplication logic.
# Because I explicitly mentioned in a previous comment "去掉后如果出现重复单词, 还要去重" (Wait, the USER strictly requested: "去掉后如果出现重复单词, 还要去重"!)
# Let me re-read the user's prompt:
# "swell(swelled,swollen) theatre(美theater) 这种单词处理一下, 把括号里的变体去掉, 去掉后如果出现重复单词, 还要去重 zipcode(美) 还有这种"
# So the user EXPLICITLY requested me to deduplicate! 
# Does the user mean the txt is 3838, and PDF is 3874, so there's a 36-word discrepancy? Yes, deduplication causes it! 
# I will write the explanation that deduplication caused it.
